local Logger = require("core.logger")
local Timer = require("utils.timer")
local Status = require("managers.status")
local Auth = require("managers.auth")
local Username = require("managers.username")
local ProbeLog = require("utils.probe_log")

local Monitor = {}
local running = false
local interrupted = false
local interval = 5
local instanceManager = nil
local recoveryManager = nil
local apkManager = nil
local Optimizer = nil

-- Install a SIGINT handler via lua-posix so Ctrl+C stops monitoring and exits the
-- program immediately. This is the ONLY reliable way to catch Ctrl+C in Termux: the
-- default SIGINT action does NOT kill the program here, and without a handler the
-- signal is effectively swallowed. Requires `pkg install lua-posix` (Lua PUC-Rio).
local function installSignalHandler()
    local ok, posix = pcall(require, "posix.signal")
    if not ok or not posix then
        -- lua-posix is not available in Termux's repos for this setup. Without it there
        -- is no pure-Lua way to catch SIGINT, and the default action is unreliable here
        -- (the monitor is almost always inside os.execute, which blocks SIGINT). Advise
        -- the run.sh wrapper, which catches Ctrl+C in the shell and kill(1)s us, instead.
        Logger.warn("Monitor: lua-posix not available; run via `sh run.sh` so Ctrl+C can stop the engine")
        return false
    end
    local sigint = posix.SIGINT or 2
    pcall(function()
        posix.signal(sigint, function()
            -- Flip flags so the monitor loop unwinds, then exit hard. os.exit from a
            -- signal handler is not strictly async-signal-safe, but works on PUC-Rio
            -- / LuaJIT in practice and makes Ctrl+C stop the program decisively.
            running = false
            interrupted = true
            os.exit(0)
        end)
    end)
    Logger.info("Monitor: SIGINT handler installed (Ctrl+C will exit)")
    return true
end

-- track instances currently undergoing recovery to avoid duplicate recoveries
local recovering = {}

local function isRecovering(id)
    return recovering[id] == true
end

local function setRecovering(id, val)
    if id == nil then return end
    if val then recovering[id] = true else recovering[id] = nil end
end

-- Menu 1 flow: launch the clones ONE AT A TIME, showing the live dashboard the whole
-- time. Each instance flips to Starting, gets force-stopped + joined, and the next one
-- only starts after this one is really RUNNING (RSS >= minRss, i.e. isActive) and has
-- then stayed up for launchSettleDelay seconds (time to load into the game).
--   launchWaitTimeout  - max seconds to wait for the clone to become active
--   launchWaitInterval - seconds between checks while waiting
--   launchSettleDelay  - seconds to wait after it is active, before the next clone
-- Every clone is launched. One that reads as not logged in only gets a short pause
-- instead of the full wait, since it will sit on the login screen with low RSS.
local function runSequentialLaunch(conf)
    local instances = instanceManager.getAll()
    local timeout = tonumber(conf and conf.launchWaitTimeout) or 60
    local poll = tonumber(conf and conf.launchWaitInterval) or 3
    if poll <= 0 then poll = 3 end
    local settle = tonumber(conf and conf.launchSettleDelay) or 5
    if settle < 0 then settle = 0 end
    local function stopped() return not running end

    for i, inst in ipairs(instances) do
        if not running then break end
        local id = inst.id or i
        local name = tostring(inst.name or id)
        local pkg = inst.package

        Status.beginStarting(id)
        Status.printSummary(instanceManager.getAll())
        Logger.info(string.format("Monitor: launching #%d %s (%s)", i, name, tostring(pkg)))
        ProbeLog.line(string.format("[%s] EVENT launch_begin #%d %s (%s)", os.date("%H:%M:%S"), i, name, tostring(pkg)))

        do
            local p_ok, l_ok = pcall(function() return recoveryManager.launchAndJoin(inst) end)
            local launched = p_ok and l_ok
            if not launched then
                Logger.error(string.format("Monitor: launch failed for %s: %s", name, tostring(l_ok)))
            end
            local loggedIn = Auth.isLoggedIn(inst)
            Logger.info(string.format("Monitor: %s login check = %s", name, tostring(loggedIn)))
            if launched and loggedIn == false then
                -- Login screen never reaches minRss: start the next clone right away.
                Logger.info(string.format("Monitor: %s not logged in; not waiting for it", name))
                launched = false
            end

            local function isActiveNow()
                if not pkg then return false end
                local okA, resA = pcall(function() return apkManager.isActive(pkg) end)
                return okA and resA
            end

            -- 1) Wait for the clone to come up (RSS >= minRss).
            local waited = 0
            local active = false
            while launched and running do
                active = isActiveNow()
                if active then break end
                if waited >= timeout then
                    Logger.warn(string.format("Monitor: %s not active (RSS) within %ds; moving on", name, timeout))
                    ProbeLog.line(string.format("[%s] EVENT launch_timeout %s (%s)", os.date("%H:%M:%S"), name, tostring(pkg)))
                    break
                end
                Timer.sleepInterruptible(poll, stopped)
                waited = waited + poll -- bounded; sleepInterruptible may stop earlier on Ctrl+C
                if running then Status.printSummary(instanceManager.getAll()) end
            end

            -- 2) Give it time to load into the game before starting the next clone.
            local settled = 0
            while active and running and settled < settle do
                local step = math.min(poll, settle - settled)
                Timer.sleepInterruptible(step, stopped)
                settled = settled + step
                if running then Status.printSummary(instanceManager.getAll()) end
                if not isActiveNow() then
                    Logger.warn(string.format("Monitor: %s dropped while loading the game; moving on", name))
                    break
                end
            end

            Status.endStarting(id)
            -- New process got a new pid during this launch: deprioritize it now.
            pcall(function() return Optimizer.applyForInstance(inst) end)
            ProbeLog.line(string.format("[%s] EVENT launch_done #%d %s (%s) waited=%ds settled=%ds",
                os.date("%H:%M:%S"), i, name, tostring(pkg), waited, settled))
        end
        if running then
            Status.printSummary(instanceManager.getAll())
        end
    end
end

function Monitor.start(conf, opts)
    interval = conf and conf.monitorInterval or interval
    instanceManager = require("managers.instance")
    recoveryManager = require("managers.recovery")
    apkManager = require("managers.apk")
    Optimizer = require("managers.optimizer")
    Status.configure(conf)
    opts = opts or {}

    if running then
        Logger.warn("Monitor already running")
        return false
    end

    running = true
    interrupted = false
    Status.reset()
    Status.resetDashboard()
    ProbeLog.configure(conf)
    ProbeLog.init()
    Username.reset()
    -- Warm the username cache once right away so the launch/dashboard draws hit the
    -- cache instead of firing a Roblox API call on every frame.
    pcall(function() Username.prefetch(instanceManager.getAll()) end)
    installSignalHandler()
    -- Full-screen dashboard: hide console log lines while monitoring so they don't push
    -- the dashboard around (log lines still go to the log file).
    Logger.setConsoleVisible(false)
    -- Clear the screen so leftover menu/launch text doesn't sit above the dashboard.
    io.write("\27[2J\27[H")
    Logger.info("Monitor: starting (interval=" .. tostring(interval) .. ")")

    -- Menu 1 passes autoLaunch=true: launch clones one at a time with the live
    -- dashboard (Starting -> Running) before the monitoring loop takes over.
    if opts.autoLaunch then
        runSequentialLaunch(conf)
        -- one full refresh so the "starting" override is cleared and statuses settle
        if running then Status.printSummary(instanceManager.getAll()) end
    end

    while running do
        local instances = instanceManager.getAll()
        local statuses = {}
        for i, inst in ipairs(instances) do
            local id = inst.id or i
            local name = tostring(inst.name or id)
            local pkg = inst.package
            Logger.debug(string.format("Monitor: checking instance %s (%s)", name, tostring(pkg)))

            -- Update per-instance status (running / starting / ingame / stuck / freeze / recovery)
            local status
            local okStatus, resStatus = pcall(function() return Status.check(inst) end)
            status = okStatus and resStatus or "unknown"
            statuses[id] = status

            -- If frozen/stuck long enough, relaunch the app — UNLESS the clone has no
            -- logged-in account: then low RSS / no activity is expected (it's just sitting
            -- on the login screen), so it must never be force-relaunched.
            local timeToRelaunch = false
            if status == "freeze" then
                local p_ok, should = pcall(function() return Status.isFreezeTimeout(id) end)
                timeToRelaunch = p_ok and should
            end
            if timeToRelaunch then
                if Auth.isLoggedIn(inst) == false then
                    Logger.debug(string.format("Monitor: %s not logged in; skipping relaunch", name))
                else
                    Logger.warn(string.format("Monitor: instance %s frozen too long; relaunching", name))
                    Status.beginRecovery(id)
                    ProbeLog.line(string.format("[%s] EVENT relaunch_begin %s (%s)", os.date("%H:%M:%S"), name, tostring(pkg)))
                    local r_ok, r_err = pcall(function()
                        return recoveryManager.relaunch(inst)
                    end)
                    if not r_ok or not r_err then
                        Logger.error(string.format("Monitor: relaunch failed for %s: %s", name, tostring(r_err)))
                        ProbeLog.line(string.format("[%s] EVENT relaunch_failed %s (%s)", os.date("%H:%M:%S"), name, tostring(pkg)))
                    else
                        Logger.info(string.format("Monitor: relaunched %s", name))
                        ProbeLog.line(string.format("[%s] EVENT relaunch_success %s (%s)", os.date("%H:%M:%S"), name, tostring(pkg)))
                        -- relaunch() restart changes the pid; re-apply deprioritization.
                        pcall(function() return Optimizer.applyForInstance(inst) end)
                    end
                    Status.endRecovery(id)
                end
            end

            -- Health is based on the REAL process state every cycle (not the status
            -- memory), so a clone whose UI was closed is detected and recovered. Previously
            -- a stale "ingame" status memory kept the instance forever "healthy" and the
            -- recovery was never triggered (the app stayed closed).
            local healthy = false
            if pkg then
                -- A force-close leaves a low-RSS stub process alive, so process existence
                -- (isRunning) alone reports it as healthy forever and it's never reopened.
                -- Decide health from the RSS threshold (isActive): a running clone has
                -- ~1 GB while a force-close stub is only ~188 MB.
                local ok, res = pcall(function() return apkManager.isActive(pkg) end)
                healthy = ok and res
            end

            if healthy then
                Logger.debug(string.format("Monitor: instance healthy: %s", name))
            else
                Logger.warn(string.format("Monitor: instance not healthy: %s", name))
                -- A clone that has no logged-in account is treated as idle (low memory is
                -- expected while it sits on the login screen). Never force-recover it,
                -- regardless of the transient status shown.
                if status == "nologin" or Auth.isLoggedIn(inst) == false then
                    Logger.debug(string.format("Monitor: instance %s not logged in; treating as idle (no recovery)", name))
                elseif isRecovering(id) then
                    Logger.info(string.format("Monitor: recovery already in progress for %s; skipping", name))
                else
                    -- mark as recovering and run recovery (synchronous). This avoids overlapping recoveries.
                    setRecovering(id, true)
                    Status.beginRecovery(id)
                    ProbeLog.line(string.format("[%s] EVENT recovery_begin %s (%s)", os.date("%H:%M:%S"), name, tostring(pkg)))
                    local p_ok, recovered = pcall(function()
                        return recoveryManager.checkAndRecover(inst)
                    end)
                    if not p_ok then
                        Logger.error(string.format("Monitor: recovery raised an error for %s: %s", name, tostring(recovered)))
                        ProbeLog.line(string.format("[%s] EVENT recovery_error %s (%s)", os.date("%H:%M:%S"), name, tostring(pkg)))
                    elseif recovered then
                        Logger.info(string.format("Monitor: recovery succeeded for %s", name))
                        ProbeLog.line(string.format("[%s] EVENT recovery_success %s (%s)", os.date("%H:%M:%S"), name, tostring(pkg)))
                        -- checkAndRecover restarts the process -> new pid -> re-tune it.
                        pcall(function() return Optimizer.applyForInstance(inst) end)
                    else
                        Logger.error(string.format("Monitor: recovery failed for %s (all attempts)", name))
                        ProbeLog.line(string.format("[%s] EVENT recovery_failed %s (%s)", os.date("%H:%M:%S"), name, tostring(pkg)))
                    end
                    Status.endRecovery(id)
                    setRecovering(id, false)
                end
            end

            if not running then break end
        end

        -- Automatic per-cycle diagnostics (Menu 1 flow) — evidence for launch.log.
        if running then
            pcall(function() return ProbeLog.scan(instances, statuses) end)
        end

        -- Print the per-instance status table for the user to see.
        Status.printSummary(instances)

        -- Make sure Ctrl+C still generates SIGINT, even if an interrupted root command
        -- left the terminal in raw mode.
        os.execute("stty isig 2>/dev/null")

        Timer.sleepInterruptible(interval, function() return not running end)
    end

    -- Monitor stopped: restore console output and cursor, then leave a clean line.
    Logger.setConsoleVisible(true)
    io.write("\27[?25h\r\n")
    io.flush()
    return true
end

function Monitor.stop()
    running = false
    Logger.info("Monitor: stopped")
end

function Monitor.interrupted()
    return interrupted
end

return Monitor
