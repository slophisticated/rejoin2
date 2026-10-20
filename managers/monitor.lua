local Paths = require("core.paths")
local Logger = require("core.logger")
local Timer = require("utils.timer")
local Status = require("managers.status")
local Auth = require("managers.auth")
local Username = require("managers.username")
local ProbeLog = require("utils.probe_log")
local Heartbeat = require("managers.heartbeat")
local WindowLayout = require("managers.window_layout")
local Webhook = require("managers.webhook")
local Remote = require("managers.remote")

local Monitor = {}
local running = false
local interrupted = false
local instanceManager = nil
local apkManager = nil

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
local PID_FILE = Paths.data("monitor.pid")

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
    if cmdline:find("main.lua", 1, true) or cmdline:find("yanamin.lua", 1, true) then return pid end
    return nil
end

local function writePid(pid)
    if not pid then return end
    Paths.ensure()
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

-- All starts/recoveries share one queue; no RSS-based recovery in this module.
local LaunchQueue = require("managers.launch_queue")
local queue = nil
local windowState = {}
local monitorConf = {}
local keyState = nil

local function checkKey()
    local present = queue:keyStatus()
    if present == nil or present == keyState then return end
    keyState = present
    if present then Logger.info("[KEY] license Delta tersedia lagi; tetap tunggu heartbeat"); return end
    Logger.warn("[KEY] validasi key Delta belum lengkap (.license belum tersedia); antrean ditahan")
    Webhook.event("key", "🔑 Delta perlu dicek",
        "File license belum ada atau Delta belum membuat .license setelah validasi. Antrean menunggu; masukkan key yang kamu dapatkan lewat alur resmi Delta.", 16705372)
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

local REQUEST_FILE = Paths.data("rejoin_request.txt")
local AUTH_FORGET_FILE = Paths.data("auth_forget.txt") -- written by CookieInjector.logout

-- Packages just logged out (maybe from Menu 5 in another process): forget their cached
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
local deltaActivationRequested = false

function Monitor.requestRejoin(ids)
    for _, id in ipairs(ids or {}) do rejoinQueue[#rejoinQueue + 1] = id end
end

function Monitor.requestDeltaActivation(ids)
    Monitor.requestRejoin(ids or { "all" })
    deltaActivationRequested = true
end

-- From another process: append ids (or "all") to the request file.
function Monitor.requestRejoinFile(ids)
    local f = io.open(REQUEST_FILE, "a")
    if not f then return false end
    for _, id in ipairs(ids or {}) do f:write(tostring(id), "\n") end
    f:close()
    return true
end

function Monitor.requestDeltaActivationFile(ids)
    local f = io.open(REQUEST_FILE, "a")
    if not f then return false end
    f:write("__delta_key_activate__\n")
    for _, id in ipairs(ids or { "all" }) do f:write(tostring(id), "\n") end
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
        local ref = line:match("^%s*(.-)%s*$")
        if ref == "__delta_key_activate__" then deltaActivationRequested = true
        else rejoinQueue[#rejoinQueue + 1] = ref end
    end
end

local function runRejoinQueue()
    takeFileRequests()
    if #rejoinQueue == 0 then return end
    local list, seen = {}, {}
    for _, ref in ipairs(rejoinQueue) do
        local candidates = ref == "all" and instanceManager.getAll() or { instanceManager.find(ref) }
        for _, inst in ipairs(candidates) do
            if not seen[inst.package] then seen[inst.package] = true; list[#list + 1] = inst end
        end
    end
    rejoinQueue = {}
    queue:request(list, true, { deltaActivation = deltaActivationRequested })
    deltaActivationRequested = false
end

local CONFIG_FILE = Paths.config()
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
    local Config = require("core.config")
    local previousWebhook = monitorConf.webhook
    if not Config.reload() then return end
    configText = text
    monitorConf = Config.get()
    queue.conf = monitorConf
    instanceManager.load(monitorConf)
    if not sameFields(previousWebhook, monitorConf.webhook) then Webhook.configure(monitorConf) end
end

function Monitor.start(conf, opts)
    if running then Logger.warn("Monitor already running"); return false end
    monitorConf, opts = conf or {}, opts or {}
    instanceManager = require("managers.instance")
    apkManager = require("managers.apk")
    local myPid = selfPid()
    local other = otherEngine(myPid)
    if other then
        Logger.error(string.format("Monitor: engine lain masih jalan (pid %d). Stop dulu: kill %d", other, other))
        return false
    end
    writePid(myPid)
    running, interrupted = true, false
    configText, windowState, keyState = readConfigText(), {}, nil
    Status.reset()
    Status.configure(monitorConf)
    Status.resetDashboard()
    ProbeLog.configure(monitorConf)
    ProbeLog.init()
    Username.reset()
    pcall(Username.prefetch, instanceManager.getAll())
    installSignalHandler()
    local installed, err = Heartbeat.install()
    if not installed then Logger.warn("Monitor: heartbeat belum terpasang: " .. tostring(err)) end
    Webhook.configure(monitorConf)
    queue = LaunchQueue.new(monitorConf, { onRecovery = Status.noteRecovery })
    if opts.autoLaunch then
        os.remove(REQUEST_FILE)
        -- Logged-in clones first; login screens are opened gently at the end.
        local first, later = {}, {}
        for _, inst in ipairs(instanceManager.getAll()) do
            local target = Auth.isLoggedIn(inst) == false and later or first
            target[#target + 1] = inst
        end
        for _, inst in ipairs(later) do first[#first + 1] = inst end
        queue:request(first, true)
    end
    Logger.setConsoleVisible(false)
    io.write("\27[2J\27[H")
    Logger.info("Monitor: antrean heartbeat aktif (satu slot loading; RSS hanya info)")
    local lastDiagnostics, lastWindow = 0, 0
    while running do
        pcall(takeAuthForget)
        pcall(syncMenuSettings)
        pcall(runRejoinQueue)
        local instances = instanceManager.getAll()
        local ok, issue = pcall(queue.tick, queue, instances)
        if not ok then
            Logger.error("[QUEUE] gagal cek: " .. tostring(issue))
            -- Hold this cycle: an error must never advance a second launch.
        end
        local statuses = {}
        for _, inst in ipairs(instances) do
            Status.setLifecycle(inst.id, queue.states[inst.package])
            statuses[inst.id] = Status.check(inst)
        end
        local activeIndex
        if queue.active then
            for i, inst in ipairs(instances) do
                if inst.package == queue.active.inst.package then activeIndex = i; break end
            end
        end
        local labels = { wait_key = "Menunggu key", wait_identity = "Identifikasi",
            needs_check = "Perlu dicek", stabilizing = "Stabil", cooldown = "Jeda retry" }
        Status.setProgress(activeIndex, activeIndex and #instances or nil,
            queue.active and (labels[queue.active.state] or "Loading") or nil)
        Status.printSummary(instances)
        pcall(checkKey)
        Webhook.tick(instances)
        pcall(Remote.tick, instances, { requestRejoin = Monitor.requestRejoin,
            requestDeltaActivation = Monitor.requestDeltaActivation, launchBusy = queue.active ~= nil })
        pcall(require("managers.logout_alarm").tick, instances, queue.active ~= nil)
        -- Expensive probes do not run on every loading poll.
        if os.time() - lastDiagnostics >= 30 then
            pcall(ProbeLog.scan, instances, statuses)
            lastDiagnostics = os.time()
        end
        if os.time() - lastWindow >= 60 then
            for _, inst in ipairs(instances) do pcall(checkWindow, inst) end
            lastWindow = os.time()
        end
        os.execute("stty isig 2>/dev/null")
        local delay = queue.active and monitorConf.launchWaitInterval or monitorConf.monitorInterval
        Timer.sleepInterruptible(math.max(1, tonumber(delay) or 5), function() return not running end)
    end
    queue = nil
    clearPid(myPid)
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
