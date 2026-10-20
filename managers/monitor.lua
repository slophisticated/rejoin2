local Logger = require("core.logger")
local Timer = require("utils.timer")
local Status = require("managers.status")
local Auth = require("managers.auth")
local Username = require("managers.username")
local ProbeLog = require("utils.probe_log")
local Heartbeat = require("managers.heartbeat")
local WindowLayout = require("managers.window_layout")
local Webhook = require("managers.webhook")
local DeltaKey = require("managers.delta_key")
local Remote = require("managers.remote")

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

-- Only one engine may drive the clones: the boot engine runs hidden in the
-- background, and a second one started from the menu would force-stop and relaunch
-- the same clones. The running engine's pid is kept in data/monitor.pid.
local PID_FILE = "data/monitor.pid"

local function selfPid()
    -- The shell spawned by popen is our child, so its $PPID is this Lua process.
    local f = io.popen("echo $PPID")
    if not f then return nil end
    local pid = tonumber(f:read("*l") or "")
    f:close()
    return pid
end

-- pid of another live engine, or nil.
local function otherEngine(myPid)
    local f = io.open(PID_FILE, "r")
    if not f then return nil end
    local pid = tonumber(f:read("*l") or "")
    f:close()
    if not pid or pid == myPid then return nil end
    local c = io.open("/proc/" .. pid .. "/cmdline", "r")
    if not c then return nil end
    local cmdline = c:read("*a") or ""
    c:close()
    if cmdline:find("main.lua", 1, true) then return pid end
    return nil
end

local function writePid(pid)
    if not pid then return end
    os.execute("mkdir -p data 2>/dev/null")
    local f = io.open(PID_FILE, "w")
    if f then f:write(tostring(pid), "\n"); f:close() end
end

local function clearPid(pid)
    local f = io.open(PID_FILE, "r")
    if not f then return end
    local stored = tonumber(f:read("*l") or "")
    f:close()
    if stored == pid then os.remove(PID_FILE) end
end

-- track instances currently undergoing recovery to avoid duplicate recoveries
local recovering = {}
-- id -> consecutive unhealthy cycles; RSS dips while Roblox loads, so one low reading
-- alone does not trigger a recovery (a heartbeat kick still does at once).
local unhealthyStreak = {}

local function isRecovering(id)
    return recovering[id] == true
end

local function setRecovering(id, val)
    if id == nil then return end
    if val then recovering[id] = true else recovering[id] = nil end
end

-- Menu 5 flow: launch the clones ONE AT A TIME, showing the live dashboard the whole
-- time. Each instance flips to Starting, gets force-stopped + joined, and the next one
-- only starts after this one is really RUNNING (RSS >= minRss, i.e. isActive) and has
-- then stayed up for launchSettleDelay seconds (time to load into the game).
--   launchWaitTimeout  - max seconds to wait for the clone to become active
--   launchWaitInterval - seconds between checks while waiting
--   launchSettleDelay  - seconds to wait after it is active, before the next clone
--   launchEmptyDelay   - seconds to wait after a clone with no account, before the next
-- Every clone is launched. One that reads as not logged in only gets a short pause
-- instead of the full wait, since it will sit on the login screen with low RSS.
-- Floating window check (window grid on): compare each running clone's window with
-- its grid slot. Only reported (log on change + dashboard mark); the position is
-- rewritten on the clone's next launch, never by restarting a running game.
local windowState = {} -- pkg -> true (in place) / false (off grid)
local monitorConf = {}

-- A freshly launched process may dip below minRss while its game loads. Only defer
-- recovery when it is still running and has no heartbeat from this session yet.
-- Explicit kicks, stale heartbeats and dead processes must still be recovered.
local function isLoading(inst)
    local at = Heartbeat.launchedAt(inst)
    if not at then return false end
    local grace = math.max(60, tonumber(monitorConf.gracePeriod) or 60)
    local age = os.time() - at
    if age < 0 or age >= grace then return false end
    if Heartbeat.alive(inst) ~= nil then return false end
    local ok, up = pcall(apkManager.isRunning, inst.package)
    return ok and up == true
end

-- A clone without a logged-in account is left alone while it sits on the login
-- screen, but if it CLOSED (process gone, or a stub left with no window) it is opened
-- again: gently (no force-stop) and at most once per noLoginCooldown seconds, so it can
-- never turn into the old force-stop loop. relaunchNoLogin = false turns this off.
local noLoginLast = {} -- pkg -> os.time() of the last reopen
local wasNoLogin = {}  -- pkg -> true while the clone sits without an account

-- A clone seen without an account that is logged in now (the owner signed in by hand)
-- is still on the Roblox home screen: queue a rejoin so it opens its game link. Goes
-- through the rejoin queue (one at a time); skipped when it already reached a game.
local function joinAfterLogin(inst, id, name, pkg, status)
    if not pkg then return end
    if status == "nologin" then wasNoLogin[pkg] = true return end
    if not wasNoLogin[pkg] or status == "unknown" or Auth.isLoggedIn(inst) ~= true then return end
    wasNoLogin[pkg] = nil
    local okH, alive = pcall(Heartbeat.alive, inst)
    if okH and alive == true then return end
    Logger.info(string.format("[NOLOGIN] %s sekarang sudah login; dibuka ke game", name))
    Monitor.requestRejoin({ id })
end

local function reopenNoLoginIfClosed(inst, id, name, pkg)
    if monitorConf.relaunchNoLogin == false or not pkg then return false end
    local okR, alive = pcall(function() return apkManager.isRunning(pkg) end)
    if not okR then return false end
    local why
    if not alive then
        why = "proses mati"
    else
        local okW, has = pcall(function() return apkManager.hasWindow(pkg) end)
        if okW and has == false then why = "tanpa jendela" end
    end
    if not why then return false end
    local cooldown = tonumber(monitorConf.noLoginCooldown) or 120
    local now = os.time()
    if noLoginLast[pkg] and now - noLoginLast[pkg] < cooldown then return false end
    if isRecovering(id) then return false end
    noLoginLast[pkg] = now

    Logger.info(string.format("[NOLOGIN] %s tertutup (%s); dibuka lagi", name, why))
    setRecovering(id, true)
    Status.beginRecovery(id)
    local okL, launched = pcall(function() return recoveryManager.reopenNoLogin(inst) end)
    Status.endRecovery(id)
    setRecovering(id, false)
    if okL and launched then
        pcall(function() return Optimizer.applyForInstance(inst) end)
    else
        Logger.warn(string.format("[NOLOGIN] %s gagal dibuka lagi: %s", name, tostring(launched)))
    end
    return true
end

-- Delta key: one status for the whole device (shared Delta folder). Notify once each
-- time the license entry disappears; nothing when it comes back.
local keyState = nil
local function checkKey()
    local present = DeltaKey.present()
    if present == nil or present == keyState then return end
    local was = keyState
    keyState = present
    if present then
        if was == false then Logger.info("[KEY] key Delta aktif lagi") end
        return
    end
    Logger.warn("[KEY] file license Delta hilang (" .. tostring(DeltaKey.path()) .. "): Delta minta key")
    Webhook.event("key", "🔑 Delta minta key",
        "File license Delta hilang. Script (heartbeat, autoexecute) tidak jalan sampai key dimasukkan lagi.",
        16705372)
end

local function checkWindow(inst)
    if not WindowLayout.isEnabled() then return end
    local pkg = inst and inst.package
    if not pkg then return end
    local okR, runningNow = pcall(function() return apkManager.isRunning(pkg) end)
    if not okR or not runningNow then return end
    local okV, res, actual, target = pcall(WindowLayout.verify, inst)
    if not okV or res == nil then return end
    if windowState[pkg] == res then return end
    windowState[pkg] = res
    local name = tostring(inst.name or pkg)
    if res then
        Logger.info(string.format("[WINDOW] %s posisi OK", name))
    else
        Logger.warn(string.format("[WINDOW] %s meleset (sekarang %s; target %s) -> dibetulkan saat relaunch berikutnya",
            name, WindowLayout.formatBounds(actual), WindowLayout.formatBounds(target)))
    end
end

-- A Launch All / sequential rejoin can wait minutes per clone; keep syncing with the
-- bot meanwhile so the device is not shown offline (Remote.tick has its own interval).
local launching = false -- true while runSequentialLaunch runs (bot cookie inject waits)

local function launchCtx()
    return { requestRejoin = function(ids) return Monitor.requestRejoin(ids) end, launchBusy = launching }
end

local function keepRemoteAlive()
    pcall(Remote.tick, instanceManager.getAll(), launchCtx())
end

-- Launch waits double as a long poll on the bot, so its commands run at once.
local function launchWait(seconds, stopped)
    local ok = pcall(Remote.idle, seconds, stopped, instanceManager.getAll(), launchCtx())
    if not ok then Timer.sleepInterruptible(seconds, stopped) end
end

local function launchInOrder(conf, only)
    -- Logged-in clones first (each waited for until in game), clones without an account
    -- last; within each group the Menu 2 order. Unknown login counts as logged in.
    -- Window slots follow the Menu 2 order, so positions do not change.
    -- `only` (optional): launch just these instances (a rejoin request), same rules.
    local instances, later, names, laterNames = {}, {}, {}, {}
    for _, inst in ipairs(only or instanceManager.getAll()) do
        local okL, li = pcall(Auth.isLoggedIn, inst)
        local label = tostring(inst.name or inst.id or "?")
        if okL and li == false then
            later[#later + 1] = inst
            laterNames[#laterNames + 1] = label
        else
            instances[#instances + 1] = inst
            names[#names + 1] = label
        end
    end
    for _, inst in ipairs(later) do instances[#instances + 1] = inst end
    Logger.info("Monitor: urutan launch: " .. (#names > 0 and table.concat(names, ", ") or "-")
        .. (#laterNames > 0 and (" | belum login: " .. table.concat(laterNames, ", ")) or ""))
    local timeout = tonumber(conf and conf.launchWaitTimeout) or 60
    local poll = tonumber(conf and conf.launchWaitInterval) or 3
    if poll <= 0 then poll = 3 end
    local settle = tonumber(conf and conf.launchSettleDelay) or 5
    if settle < 0 then settle = 0 end
    local emptyDelay = tonumber(conf and conf.launchEmptyDelay) or 5
    if emptyDelay < 0 then emptyDelay = 0 end
    local joinTimeout = tonumber(conf and conf.launchJoinTimeout) or 240
    if joinTimeout < 0 then joinTimeout = 0 end
    -- With the Delta heartbeat, wait until each clone is really in game before the next
    -- one starts. One clone without a heartbeat (e.g. Delta asking for a key) does not
    -- end the waiting for the others; only after 2 such clones in a row is the rest of
    -- this Launch All given the fixed settle delay instead.
    local hbEnabled = Heartbeat.isEnabled() and joinTimeout > 0
    local hbMisses = 0
    local hbWorking = hbEnabled
    local function stopped() return not running end

    for i, inst in ipairs(instances) do
        if not running then break end
        Status.setProgress(i, #instances, "Launching")
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
                -- Login screen never reaches minRss, so don't wait for it to be "active".
                -- Still give its window a short head start: launching the next clone at
                -- the same instant can stop this one's floating window from appearing.
                Logger.info(string.format("Monitor: %s not logged in; short pause %ds", name, emptyDelay))
                launchWait(emptyDelay, stopped)
                keepRemoteAlive()
                launched = false
            end

            local function isActiveNow()
                if not pkg then return false end
                local okA, resA = pcall(function() return Heartbeat.isUp(inst, apkManager) end)
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
                launchWait(poll, stopped)
                waited = waited + poll -- bounded; sleepInterruptible may stop earlier on Ctrl+C
                keepRemoteAlive()
                if running then Status.printSummary(instanceManager.getAll()) end
            end

            -- 2) Give it time to load into the game before starting the next clone:
            --    until its heartbeat says in game (up to launchJoinTimeout), or without a
            --    heartbeat a fixed launchSettleDelay.
            local settled = 0
            local limit = hbWorking and joinTimeout or settle
            local sawHeartbeat = false
            -- RSS dips below minRss while Roblox loads a place, so a low reading is not a
            -- crash. Only a process that is really gone on two checks in a row counts.
            local goneChecks = 0
            while active and running and settled < limit do
                local alive, why = Heartbeat.alive(inst)
                if alive == true then
                    Logger.info(string.format("Monitor: %s in game (heartbeat, %ds); next clone", name, waited + settled))
                    sawHeartbeat = true
                    break
                elseif alive == false and tostring(why):find("^kicked") then
                    Logger.warn(string.format("Monitor: %s %s while joining; moving on", name, tostring(why)))
                    sawHeartbeat = true
                    break
                end
                local step = math.min(poll, limit - settled)
                launchWait(step, stopped)
                settled = settled + step
                keepRemoteAlive()
                if running then Status.printSummary(instanceManager.getAll()) end
                local okR, isUp = pcall(function() return apkManager.isRunning(pkg) end)
                if okR and isUp == false then goneChecks = goneChecks + 1 else goneChecks = 0 end
                if goneChecks >= 2 then
                    Logger.warn(string.format("Monitor: %s dropped while loading the game; moving on", name))
                    sawHeartbeat = true -- not the heartbeat's fault
                    break
                end
            end
            if hbWorking and active and running and not sawHeartbeat then
                hbMisses = hbMisses + 1
                hbWorking = hbMisses < 2
                Logger.warn(string.format("Monitor: %s: heartbeat tidak muncul dalam %ds (executor belum key / script tidak jalan?)%s",
                    name, joinTimeout, hbWorking and "; clone berikutnya tetap ditunggu"
                        or string.format("; 2 clone berturut-turut, sisa clone pakai jeda launchSettleDelay %ds", settle)))
            elseif hbEnabled and sawHeartbeat then
                hbMisses = 0
            end

            Status.endStarting(id)
            if launched then checkWindow(inst) end
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

-- Marks the launch as busy (the bot's cookie inject waits) and always clears it again.
local function runSequentialLaunch(conf, only)
    launching = true
    local ok, err = pcall(launchInOrder, conf, only)
    launching = false
    if not ok then error(err, 0) end
end

-- Rejoin requests (preset change from Menu 11, the remote bot, ...). Processed one
-- batch at a time by the monitor loop with the Launch All rules, so loading peaks
-- do not pile up. Another process (the menu while the boot engine runs) asks through
-- data/rejoin_request.txt: one instance id per line, or "all".
local REQUEST_FILE = "data/rejoin_request.txt"
local AUTH_FORGET_FILE = "data/auth_forget.txt" -- written by CookieInjector.logout

-- Packages just logged out (maybe from Menu 7 in another process): forget their cached
-- login state before deciding whether a closed clone gets rejoined.
local function takeAuthForget()
    local f = io.open(AUTH_FORGET_FILE, "r")
    if not f then return end
    local text = f:read("*a") or ""
    f:close()
    os.remove(AUTH_FORGET_FILE)
    for pkg in text:gmatch("[^\r\n]+") do Auth.forget(pkg) end
end
local rejoinQueue = {}

function Monitor.requestRejoin(ids)
    for _, id in ipairs(ids or {}) do rejoinQueue[#rejoinQueue + 1] = id end
end

-- From another process: append ids (or "all") to the request file.
function Monitor.requestRejoinFile(ids)
    local f = io.open(REQUEST_FILE, "a")
    if not f then return false end
    for _, id in ipairs(ids or {}) do f:write(tostring(id), "\n") end
    f:close()
    return true
end

local function takeFileRequests()
    local f = io.open(REQUEST_FILE, "r")
    if not f then return end
    local text = f:read("*a") or ""
    f:close()
    os.remove(REQUEST_FILE)
    -- The menu saved new config (presets / links) before asking: pick it up.
    pcall(function()
        local Config = require("core.config")
        Config.reload()
        instanceManager.load(Config.get())
    end)
    for line in text:gmatch("[^\r\n]+") do
        rejoinQueue[#rejoinQueue + 1] = line:match("^%s*(.-)%s*$")
    end
end

local function runRejoinQueue(conf)
    takeFileRequests()
    if #rejoinQueue == 0 then return end
    local list, seen = {}, {}
    for _, ref in ipairs(rejoinQueue) do
        if ref == "all" then
            for _, inst in ipairs(instanceManager.getAll()) do
                if not seen[inst] then seen[inst] = true; list[#list + 1] = inst end
            end
        else
            local inst = instanceManager.find(ref)
            if inst and not seen[inst] then seen[inst] = true; list[#list + 1] = inst end
        end
    end
    rejoinQueue = {}
    if #list == 0 then return end
    Logger.info(string.format("Monitor: rejoin %d clone (permintaan menu / bot)", #list))
    runSequentialLaunch(conf, list)
    Status.setProgress(nil)
end

-- Menu 9 (webhook / bot: device name, URLs, secret) runs in another process and only
-- writes config/config.lua. Copy those sections into the running engine when the file
-- changes, so a renamed device or a new bot secret applies without a restart.
local CONFIG_FILE = "config/config.lua"
local configText = nil

local function readConfigText()
    local f = io.open(CONFIG_FILE, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local function sameFields(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

local function syncMenuSettings()
    local text = readConfigText()
    if not text or text == configText then return end
    configText = text
    local chunk = load(text, "config", "t", {})
    local ok, fresh = pcall(chunk or error)
    if not ok or type(fresh) ~= "table" then return end
    if type(fresh.remote) == "table" then monitorConf.remote = fresh.remote end
    if type(fresh.webhook) == "table" and not sameFields(fresh.webhook, monitorConf.webhook) then
        monitorConf.webhook = fresh.webhook
        Webhook.configure(monitorConf)
        Logger.info("Monitor: setting webhook / nama device dari menu dipakai")
    end
end

function Monitor.start(conf, opts)
    configText = readConfigText()
    interval = conf and conf.monitorInterval or interval
    monitorConf = type(conf) == "table" and conf or {}
    Webhook.configure(monitorConf)
    noLoginLast = {}
    wasNoLogin = {}
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

    local myPid = selfPid()
    local other = otherEngine(myPid)
    if other then
        Logger.error(string.format("Monitor: engine lain masih jalan (pid %d, mis. dari boot). "
            .. "Stop dulu: kill %d", other, other))
        return false
    end
    writePid(myPid)

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
    local hbOk, hbMsg = Heartbeat.install()
    if not hbOk then Logger.warn("Monitor: heartbeat script not installed: " .. tostring(hbMsg)) end
    -- Full-screen dashboard: hide console log lines while monitoring so they don't push
    -- the dashboard around (log lines still go to the log file).
    Logger.setConsoleVisible(false)
    -- Clear the screen so leftover menu/launch text doesn't sit above the dashboard.
    io.write("\27[2J\27[H")
    Logger.info("Monitor: starting (interval=" .. tostring(interval) .. ")")

    -- Menu 5 passes autoLaunch=true: launch clones one at a time with the live
    -- dashboard (Starting -> Running) before the monitoring loop takes over.
    if opts.autoLaunch then
        -- Launch All opens everything anyway: drop rejoin requests left from the menu.
        os.remove(REQUEST_FILE)
        runSequentialLaunch(conf)
        Status.setProgress(nil)
        -- one full refresh so the "starting" override is cleared and statuses settle
        if running then Status.printSummary(instanceManager.getAll()) end
    end

    local cycle = 0
    local windowEvery = math.max(1, math.floor(60 / math.max(1, tonumber(interval) or 5)))
    while running do
        cycle = cycle + 1
        pcall(takeAuthForget)
        local instances = instanceManager.getAll()
        local statuses = {}
        for i, inst in ipairs(instances) do
            pcall(takeAuthForget)
            Status.setProgress(i, #instances, "Checking")
            if i > 1 then Status.printSummary(instances) end
            local id = inst.id or i
            local name = tostring(inst.name or id)
            local pkg = inst.package
            Logger.debug(string.format("Monitor: checking instance %s (%s)", name, tostring(pkg)))

            -- Update per-instance status (running / starting / ingame / stuck / freeze / recovery)
            local status
            local okStatus, resStatus = pcall(function() return Status.check(inst) end)
            status = okStatus and resStatus or "unknown"
            statuses[id] = status
            pcall(joinAfterLogin, inst, id, name, pkg, status)

            -- If frozen/stuck long enough, relaunch the app — UNLESS the clone has no
            -- logged-in account: then low RSS / no activity is expected (it's just sitting
            -- on the login screen), so it must never be force-relaunched.
            local timeToRelaunch = false
            if status == "freeze" then
                local p_ok, should = pcall(function() return Status.isFreezeTimeout(id) end)
                timeToRelaunch = p_ok and should
            end
            if timeToRelaunch and not isLoading(inst) then
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
                -- An in-game heartbeat (when the Delta script runs) decides first: a kick or
                -- a stopped heartbeat is unhealthy even with plenty of RSS.
                local ok, res = pcall(function() return Heartbeat.isUp(inst, apkManager) end)
                healthy = ok and res
                if not healthy and isLoading(inst) then
                    healthy = true
                    Logger.debug(string.format("Monitor: %s masih loading; tunggu sebelum cek RSS lagi", name))
                end
                local kicked = false
                if not healthy then
                    local _, why = Heartbeat.alive(inst)
                    if why then Logger.warn(string.format("Monitor: %s %s", name, why)) end
                    kicked = tostring(why or ""):find("^kicked") ~= nil
                end
                if healthy then
                    unhealthyStreak[id] = nil
                elseif not kicked then
                    -- A closed app (no process) is certain; only a low-RSS reading waits.
                    local okR, isUp = pcall(function() return apkManager.isRunning(pkg) end)
                    unhealthyStreak[id] = (okR and isUp == false) and 2 or (unhealthyStreak[id] or 0) + 1
                    if unhealthyStreak[id] < 2 then
                        Logger.info(string.format("Monitor: %s kelihatan ga sehat (RSS rendah?), dicek lagi siklus berikutnya", name))
                        healthy = true
                    end
                end
            end

            if healthy then
                Logger.debug(string.format("Monitor: instance healthy: %s", name))
            else
                unhealthyStreak[id] = nil -- after acting, a fresh low reading gets its grace again
                Logger.warn(string.format("Monitor: instance not healthy: %s", name))
                -- A clone that has no logged-in account is treated as idle (low memory is
                -- expected while it sits on the login screen). Never force-recover it,
                -- regardless of the transient status shown.
                if status == "nologin" or Auth.isLoggedIn(inst) == false then
                    -- On the login screen: leave it. Closed: reopen gently (see above).
                    if not reopenNoLoginIfClosed(inst, id, name, pkg) then
                        Logger.debug(string.format("Monitor: instance %s not logged in; treating as idle (no recovery)", name))
                    end
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

        -- Automatic per-cycle diagnostics (Menu 5 flow) — evidence for launch.log.
        if running then
            pcall(function() return ProbeLog.scan(instances, statuses) end)
        end

        -- Print the per-instance status table for the user to see.
        Status.setProgress(nil)
        Status.printSummary(instances)
        pcall(syncMenuSettings)
        Webhook.tick(instances)
        pcall(Remote.tick, instances, { requestRejoin = Monitor.requestRejoin, launchBusy = false })
        pcall(require("managers.logout_alarm").tick, instances, false)
        if running then pcall(runRejoinQueue, conf) end

        -- Make sure Ctrl+C still generates SIGINT, even if an interrupted root command
        -- left the terminal in raw mode.
        os.execute("stty isig 2>/dev/null")

        if running and cycle % windowEvery == 0 then
            for _, inst in ipairs(instances) do pcall(checkWindow, inst) end
            pcall(checkKey)
        end
        -- Follow a switch to another executor (no Termux needed): ~every 5 minutes.
        if running and cycle % (windowEvery * 5) == 0 then pcall(Heartbeat.install) end

        -- The wait between cycles is a long poll on the bot: a command sent from Discord
        -- runs within a second or two instead of on the next remote.interval.
        local stopFn = function() return not running end
        local okI = pcall(Remote.idle, interval, stopFn, instances,
            { requestRejoin = Monitor.requestRejoin, launchBusy = false })
        if not okI then Timer.sleepInterruptible(interval, stopFn) end
    end

    clearPid(myPid)
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
