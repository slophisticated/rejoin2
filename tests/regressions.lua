-- Run from the repository root: lua tests/regressions.lua
-- Isolated Lua 5.3 harness: no device, filesystem writes, or network calls.
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n" .. tostring(err))
    end
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
    return out
end

local noop = function() end
local function dummy()
    return setmetatable({}, { __index = function() return noop end })
end

local function sandbox()
    local env = setmetatable({ os = copy(os), io = copy(io), print = noop }, { __index = _G })
    env._G = env
    env.package = { loaded = {}, preload = {} }
    env.os.execute, env.os.remove = noop, noop
    env.io.write, env.io.flush = noop, noop
    env.io.open = function() return nil end
    env.require = function(name)
        if env.package.loaded[name] then return env.package.loaded[name] end
        local loader = env.package.preload[name]
        if not loader then
            local err
            loader, err = loadfile(name:gsub("%.", "/") .. ".lua", "t", env)
            assert(loader, err)
        end
        local value = loader(name)
        if value == nil then value = true end
        env.package.loaded[name] = value
        return value
    end
    env.package.preload["core.paths"] = function()
        return { data = function(name) return "data/" .. name end,
            config = function() return "config/config.lua" end,
            template = function() return "config/template.lua" end,
            resolve = function(path) return path end, ensure = noop }
    end
    env.package.preload["core.logger"] = dummy
    return env
end

local function editPreset(choice)
    local env = sandbox()
    local conf = {
        presets = { A = { name = "A", link = "roblox://placeId=1" }, B = { name = "B", link = "roblox://placeId=2" } },
        defaultPreset = "A",
        instances = {{ id = 1, name = "Clone1", package = "com.test.clone", preset = "B" }},
    }
    local saved, saves = nil, 0
    env.package.preload["core.config"] = function()
        return { get = function() return conf end, save = function(c)
            saved, saves = copy(c), saves + 1
            return true
        end }
    end
    local inputs = { "3", "1", "", "", choice, "5" }
    env.io.read = function() return assert(table.remove(inputs, 1), "test input exhausted") end
    local instances = env.require("managers.instance")
    instances.load(conf)
    env.require("core.instances_cli").run()
    return saved, saves, instances
end

test("editing only a preset to default survives reload", function()
    local saved, saves, instances = editPreset("d")
    assert(saves == 1, "preset change was not saved")
    instances.load(saved)
    local key, source = instances.presetOf(instances.getAll()[1])
    assert(key == "A" and source == "default", "reloaded clone did not follow default")
end)

test("leaving the preset blank keeps its current value", function()
    local _, saves, instances = editPreset("")
    assert(saves == 0)
    local key, source = instances.presetOf(instances.getAll()[1])
    assert(key == "B" and source == "khusus")
end)

local function remoteProbe(code)
    local env = sandbox()
    local conf = { remote = { url = "https://test.invalid", secret = "" } }
    env.package.preload["core.config"] = function() return { get = function() return conf end } end
    local files = { ["data/device_id.txt"] = "0123456789abcdef" }
    env.io.open = function(path, mode)
        if mode == "r" then
            if not files[path] then return nil end
            return { read = function() return files[path] end, close = noop }
        end
        files[path] = ""
        return { write = function(_, ...)
            for _, v in ipairs({...}) do files[path] = files[path] .. v end
        end, close = noop }
    end
    local requests = 0
    env.io.popen = function(cmd)
        assert(cmd:find("/api/ping", 1, true), "connection test polled or acknowledged commands")
        requests = requests + 1
        return { read = function() return '{"ok":true}\n' .. code end, close = noop }
    end
    local ok, msg = env.require("managers.remote").test()
    assert(requests == 1)
    return ok, msg
end

test("connection test authenticates without polling or acknowledging commands", function()
    assert(remoteProbe(200) == true)
end)

test("connection test reports an old bot without falling back to sync", function()
    local ok, msg = remoteProbe(404)
    assert(ok == false and msg:find("update bot", 1, true))
end)

test("connection test reports an unregistered device", function()
    local ok, msg = remoteProbe(401)
    assert(ok == false and msg:find("belum didaftarkan", 1, true))
end)

test("logout alarm schedules in WIB, waits for launch slot, then fires once", function()
    local env = sandbox()
    local now = 1700000000
    local calls, saves = 0, 0
    local inst = { id = 2, name = "Clone2", package = "com.test.two" }
    env.os.time = function() return now end
    env.package.preload["core.config"] = function() return { get = function() return {} end } end
    env.package.preload["managers.instance"] = function()
        return { getAll = function() return { inst } end, save = function() saves = saves + 1; return true end }
    end
    env.package.preload["managers.cookie_injector"] = function()
        return { logout = function() calls = calls + 1; return true, "logout" end }
    end
    local Alarm = env.require("managers.logout_alarm")
    local tomorrow = env.os.date("!*t", now + 86400 + 7 * 3600)
    local date = string.format("%02d/%02d", tomorrow.day, tomorrow.month)
    local resolvedDate = string.format("%02d/%02d/%04d", tomorrow.day, tomorrow.month, tomorrow.year)
    local ok = Alarm.set(2, date, "12:00", false)
    assert(ok and inst.logoutAlarm.date == resolvedDate and inst.logoutAlarm.time == "12:00" and inst.logoutAlarm.timezone == "Asia/Jakarta")
    local due = inst.logoutAlarm.nextAt
    local dueWib = env.os.date("!*t", due + 7 * 3600)
    assert(dueWib.year == tomorrow.year and dueWib.month == tomorrow.month and dueWib.day == tomorrow.day)
    assert(dueWib.hour == 12 and dueWib.min == 0)
    now = due
    Alarm.tick({ inst }, true)
    assert(calls == 0, "alarm interfered with active launch queue")
    Alarm.tick({ inst }, false)
    assert(calls == 1 and inst.logoutAlarm == nil and saves >= 2)
    local followingDay = env.os.date("!*t", now + 86400 + 7 * 3600)
    local dailyDate = string.format("%02d/%02d", followingDay.day, followingDay.month)
    assert(Alarm.set(2, dailyDate, "12:00", true))
    now = inst.logoutAlarm.nextAt
    Alarm.tick({ inst }, false)
    assert(calls == 2 and inst.logoutAlarm.daily and inst.logoutAlarm.nextAt > now)
    assert(Alarm.remove(2) and inst.logoutAlarm == nil)
end)

local function queueFixture()
    local Queue = require("managers.launch_queue")
    local f = { clock = 1000, packets = {}, processes = {}, opens = {}, names = {}, accounts = {}, key = true }
    f.instances = {{ id = 1, name = "Clone1", package = "com.test.one" },
        { id = 2, name = "Clone2", package = "com.test.two" }}
    f.conf = { launchJoinTimeout = 240, launchSafety = { stableHeartbeats = 3, stableSeconds = 20,
        retryCooldown = 30, maxAttempts = 3 } }
    local hb = {
        isEnabled = function() return f.enabled ~= false end,
        identity = function(inst) if f.names[inst.id] == false then return nil, "unknown" end; return "user" .. inst.id end,
        read = function(inst) return f.packets[inst.id] end,
        alive = function(inst)
            local h = f.packets[inst.id]
            if not h or not h.current then return nil end
            if h.state == "kicked" then return false, "kicked: test" end
            if h.state == "ingame" then return h.fresh, "heartbeat berhenti" end
            return nil
        end,
    }
    f.q = Queue.new(f.conf, { hb = hb, auth = { isLoggedIn = function(inst) return f.accounts[inst.id] ~= false end },
        apk = { isRunning = function(pkg) return f.processes[pkg] == true end, hasWindow = function() return true end,
            isActive = function() error("RSS must not decide readiness") end },
        recovery = { launchAndJoin = function(inst)
            f.opens[#f.opens + 1] = { id = inst.id, at = f.clock, link = inst.link }
            f.processes[inst.package], f.packets[inst.id] = true, nil
            return true
        end, reopenNoLogin = function(inst)
            f.gentle = (f.gentle or 0) + 1; f.processes[inst.package] = true; return true
        end }, key = { present = function() return f.key end }, optimizer = { applyForInstance = noop },
        log = dummy(), now = function() return f.clock end })
    function f:tick(seconds)
        self.clock = self.clock + (seconds or 0)
        self.q:tick(self.instances)
    end
    function f:beat(id, seq, state)
        self.packets[id] = { session = "session" .. id, seq = seq, time = self.clock,
            state = state or "ingame", fresh = true, current = true }
    end
    function f:ready(id)
        for n = 1, 3 do self:beat(id, n); self:tick(10) end
    end
    return f
end

test("one loading slot waits for distinct heartbeats and a stable interval", function()
    local f = queueFixture()
    f.q:request(f.instances, true); f:tick()
    assert(#f.opens == 1 and f.opens[1].id == 1)
    f:beat(1, 1); f:tick(1); f:tick(30)
    assert(#f.opens == 1, "re-reading the same heartbeat counted as new")
    f:beat(1, 2); f:tick(3)
    assert(#f.opens == 1)
    f:beat(1, 3); f:tick(3); f:tick(1)
    assert(#f.opens == 2 and f.opens[2].id == 2)
end)

test("missing heartbeat timeout holds the queue without restarting; late readiness resumes it", function()
    local f = queueFixture()
    f.q:request(f.instances, true); f:tick(); f:tick(300); f:tick(600)
    assert(#f.opens == 1 and f.q.active.state == "needs_check")
    f:ready(1); f:tick(1)
    assert(#f.opens == 2 and f.opens[2].id == 2)
end)

test("loading progress never releases another clone", function()
    local f = queueFixture(); f.q:request(f.instances, true); f:tick()
    for seq = 1, 30 do f:beat(1, seq, "loading"); f:tick(10) end
    assert(#f.opens == 1 and f.q.active.state == "needs_check")
end)

test("missing key is checked before launch and while loading; waiting does not consume retries", function()
    local f = queueFixture(); f.key = false
    f.q:request(f.instances, true); f:tick(); f:tick(300)
    assert(#f.opens == 0 and f.q.active.state == "wait_key")
    f.key = true; f:tick(6)
    assert(#f.opens == 1)
    f.key = false; f:tick(6); f:tick(1000)
    assert(#f.opens == 1 and f.q.attempts[f.instances[1].package].count == 1)
    f.key = true; f:tick(6)
    assert(f.q.active.state == "starting")
    f:ready(1); f:tick(1)
    assert(#f.opens == 2)
end)

test("unknown license is not a claim that Get Key is on screen", function()
    local f = queueFixture(); f.key = nil
    f.q:request(f.instances, true); f:tick()
    assert(#f.opens == 1 and f.q.active.state == "starting")
end)

test("working heartbeats override a missing license heuristic", function()
    local f = queueFixture(); f.q:request(f.instances, true); f:tick()
    f.key = false
    f:ready(1)
    assert(f.q.states[f.instances[1].package] == "ingame")
end)

test("automatic recovery and manual restarts share the same slot with a retry budget", function()
    local f = queueFixture()
    f.q:request({ f.instances[1] }, false)
    f.q:request({ f.instances[2] }, true)
    for attempt = 1, 3 do
        f:tick(31)
        assert(#f.opens == attempt and f.opens[attempt].id == 1)
        f.processes[f.instances[1].package] = false
        f:tick(1)
        assert(f.q.active.state == "cooldown")
    end
    f:tick(31); f:tick(600)
    assert(#f.opens == 3 and f.q.active.state == "needs_check")
    f.q:request({ f.instances[1] }, true); f:tick()
    assert(#f.opens == 4 and f.opens[4].id == 1, "manual retry bypassed the held loading slot")
end)

test("live processes with no heartbeat are observed without an RSS restart", function()
    local f = queueFixture()
    for _, inst in ipairs(f.instances) do f.processes[inst.package] = true end
    f:tick(); f:tick(300); f:tick(600)
    assert(#f.opens == 0 and f.q.active.state == "needs_check")
end)

test("unknown username holds identification instead of borrowing another account", function()
    local f = queueFixture(); f.names[1] = false
    f.q:request(f.instances, true); f:tick(); f:tick(300)
    assert(#f.opens == 0 and f.q.active.state == "wait_identity")
    f.names[1] = true; f:tick()
    assert(#f.opens == 1)
end)

test("requests are deduplicated and removing a held clone releases its slot", function()
    local f = queueFixture(); f.q:request(f.instances, true); f.q:request(f.instances, true)
    assert(#f.q.pending == 2)
    f:tick(); f:tick(300)
    table.remove(f.instances, 1); f:tick()
    assert(#f.opens == 2 and f.opens[2].id == 2)
end)

test("an already-running clone with unknown identity waits without restarting", function()
    local f = queueFixture(); f.processes[f.instances[1].package] = true; f.names[1] = false
    f:tick(); f:tick(600)
    assert(#f.opens == 0 and f.q.active.state == "wait_identity")
end)

test("login clones are ordered ahead of logged-out clones for every batch", function()
    local f = queueFixture(); f.accounts[1] = false
    f.q:request(f.instances, true); f:tick()
    assert(#f.opens == 1 and f.opens[1].id == 2 and not f.gentle)
end)

test("re-reading old packets cannot stretch the heartbeat stable interval", function()
    local f = queueFixture(); f.q:request(f.instances, true); f:tick()
    f:beat(1, 1); f:tick(1); f:beat(1, 2); f:tick(1); f:beat(1, 3); f:tick(1)
    f:tick(30)
    assert(#f.opens == 1 and f.q.active, "wall-clock waiting passed a stalled heartbeat stream")
    f:beat(1, 4); f:tick()
    assert(f.q.active == nil)
end)

test("logged-out clones only use the gentle launcher and respect its delay", function()
    local f = queueFixture(); f.accounts[1] = false
    f.q:request({ f.instances[1] }, true); f:tick()
    assert(f.gentle == 1 and #f.opens == 0)
    f.q:request({ f.instances[2] }, true); f:tick(5); f:tick(1)
    assert(#f.opens == 1 and f.opens[1].id == 2)
end)

test("clone that logs in after nologin automatically enters its configured game link", function()
    local f = queueFixture()
    local inst = f.instances[1]
    f.instances = { inst }
    inst.link = "https://www.roblox.com/games/123"
    f.accounts[1] = false
    f.q:request({ inst }, true)
    f:tick()
    assert(f.gentle == 1 and #f.opens == 0 and f.q.states[inst.package] == "nologin")
    f:tick(5)
    assert(f.q.active == nil and f.q.states[inst.package] == "nologin")
    f.accounts[1] = true
    f:tick(1)
    assert(#f.opens == 1 and f.opens[1].id == inst.id and f.opens[1].link == inst.link,
        "login transition should queue a fresh game-link launch")
end)

local function heartbeatFixture()
    local env, files = sandbox(), {}
    local clock = 1000
    local inst = { id = 1, package = "com.test.one", username = "UserOne" }
    local conf = { instances = { inst }, heartbeat = { enabled = true, workspacePath = "/ws" } }
    env.os.time = function() return clock end
    env.package.preload["core.config"] = function() return { get = function() return conf end } end
    env.package.preload["utils.file"] = function() return { read = function(p) return files[p] end,
        write = function(p, v) files[p] = v; return true end } end
    env.package.preload["utils.shell"] = function() return { exec = function() return false, "" end } end
    env.package.preload["managers.username"] = function() return { get = function(i) return i.username end } end
    local hb = env.require("managers.heartbeat")
    local f = { hb = hb, inst = inst, files = files, conf = conf, env = env }
    function f:launch()
        assert(hb.markLaunched(inst))
        return files["/ws/rejoin/start_userone.txt"]:match("session=([^\n]+)")
    end
    function f:packet(session, name, state)
        files["/ws/rejoin/hb_userone.txt"] = string.format("name=%s\npackage=%s\nsession=%s\ntime=%d\nseq=1\nstate=%s\n",
            name or "UserOne", inst.package, session, clock, state or "ingame")
    end
    function f:advance(n) clock = clock + n end
    return f
end

test("same-second relaunch rejects the previous session heartbeat", function()
    local f = heartbeatFixture()
    local old = f:launch(); f:packet(old)
    assert(f.hb.readNow(f.inst).current)
    local fresh = f:launch()
    assert(fresh ~= old and not f.hb.readNow(f.inst).current)
    f:packet(fresh)
    assert(f.hb.alive(f.inst) == true)
end)

test("a heartbeat from a different username is rejected", function()
    local f = heartbeatFixture(); local session = f:launch()
    f:packet(session, "OtherUser")
    assert(f.hb.readNow(f.inst) == nil)
end)

test("duplicate account mappings block identification", function()
    local f = heartbeatFixture()
    f.conf.instances[2] = { package = "com.test.two", username = "userone" }
    assert(f.hb.identity(f.inst) == nil)
end)

test("loading is unknown, not healthy or a stale ingame heartbeat", function()
    local f = heartbeatFixture(); local session = f:launch(); f:packet(session, nil, "loading")
    local apk = { isRunning = function() return true end, isActive = function() error("RSS fallback") end }
    assert(f.hb.isUp(f.inst, apk) == nil)
    f:advance(300)
    assert(f.hb.alive(f.inst) == nil)
    apk.isRunning = function() return false end
    assert(f.hb.isUp(f.inst, apk) == false)
end)

test("engine restart adopts persisted session but rejects legacy heartbeat files", function()
    local f = heartbeatFixture(); local session = f:launch(); f:packet(session)
    f.env.package.loaded["managers.heartbeat"] = nil
    assert(f.env.require("managers.heartbeat").readNow(f.inst).current)
    f.files["/ws/rejoin/hb_userone.txt"] = "name=UserOne\ntime=1000\nstate=ingame\n"
    assert(f.hb.readNow(f.inst) == nil)
end)

test("real recovery writes the launch session before opening the game", function()
    local f = heartbeatFixture()
    local stopped, opened = false, false
    f.env.package.preload["managers.auth"] = function() return { isLoggedIn = function() return true end } end
    f.env.package.preload["managers.instance"] = function() return { gameLink = function() return "roblox://placeId=1" end } end
    f.env.package.preload["managers.apk"] = function() return { forceStop = function() stopped = true; return true end } end
    f.env.package.preload["managers.window_layout"] = function() return { applyForInstance = noop } end
    f.env.package.preload["utils.timer"] = function() return { sleep = noop } end
    f.env.package.preload["utils.android"] = function() return { openURL = function(_, pkg)
        assert(stopped and pkg == f.inst.package and f.files["/ws/rejoin/start_userone.txt"])
        opened = true
        return true
    end } end
    assert(f.env.require("managers.recovery").launchAndJoin(f.inst))
    assert(opened)
end)

test("in-game script never claims readiness merely because 180 seconds elapsed", function()
    local env = sandbox()
    local now, tasks, reports = 1000, {}, {}
    local player = { Name = "UserOne", UserId = 1, GetNetworkPing = function() return 0 end }
    local content = { RequestQueueSize = 10 }
    local signal = { Connect = function() return { Disconnect = noop } end, Wait = noop }
    local services = {
        Players = { LocalPlayer = player }, RunService = { Heartbeat = signal },
        GuiService = { ErrorMessageChanged = signal, GetErrorMessage = function() return "" end },
        Stats = { GetTotalMemoryUsageMb = function() return 100 end }, ContentProvider = content,
        CoreGui = { WaitForChild = function() return nil end },
    }
    env.game = { IsLoaded = function() return true end, GetService = function(_, n) return assert(services[n]) end,
        PlaceId = 1, JobId = "job-one" }
    env.os.time, env.os.clock = function() return now end, function() return now end
    env.getgenv = function() return env end
    env.makefolder, env.isfolder = noop, function() return true end
    env.readfile = function() return "name=userone\npackage=com.test.one\nsession=request_one\n" end
    env.writefile = function(_, text) reports[#reports + 1] = { at = now, text = text } end
    env.task = {
        wait = function(n) return coroutine.yield(n or 1) end,
        spawn = function(fn) tasks[#tasks + 1] = { co = coroutine.create(fn), at = now } end,
    }
    local source = assert(loadfile("scripts/rejoin_heartbeat.lua", "t", env))
    env.task.spawn(source)
    for time = 1000, 1250 do
        now = time
        if time == 1225 then
            player.Character = { FindFirstChild = function() return {} end }
            content.RequestQueueSize = 0
        end
        for _, task in ipairs(tasks) do
            if task.at <= now and coroutine.status(task.co) ~= "dead" then
                local ok, delay = coroutine.resume(task.co)
                assert(ok, delay)
                task.at = now + (tonumber(delay) or 1)
            end
        end
    end
    assert(#reports > 20)
    local ready = false
    for _, report in ipairs(reports) do
        assert(report.text:find("session=request_one", 1, true))
        if report.at < 1225 then assert(report.text:find("state=loading", 1, true)) end
        if report.text:find("state=ingame", 1, true) then ready = true end
    end
    assert(ready, "script did not become ready after character/assets were ready")
end)

test("monitor keeps bot polling while the loading slot waits for a key", function()
    local env, clock = sandbox(), 1000
    local ticks, syncs, notices, requests = 0, 0, 0, 0
    local inst = { id = 1, name = "Clone1", package = "com.test.one" }
    local monitor
    env.os.time = function() return clock end
    env.io.popen = function() return { read = function() return "" end, close = noop } end
    for _, name in ipairs({ "managers.username", "utils.probe_log", "managers.window_layout", "managers.delta_key", "managers.status" }) do
        env.package.preload[name] = dummy
    end
    env.package.preload["managers.auth"] = function() return { isLoggedIn = function() return true end } end
    env.package.preload["managers.instance"] = function() return { getAll = function() return { inst } end } end
    env.package.preload["managers.apk"] = dummy
    env.package.preload["managers.heartbeat"] = function() return { install = function() return true end } end
    env.package.preload["managers.webhook"] = function() return { configure = noop, tick = noop,
        event = function() notices = notices + 1 end } end
    env.package.preload["managers.remote"] = function() return { tick = function() syncs = syncs + 1 end } end
    env.package.preload["managers.launch_queue"] = function() return { new = function()
        return { states = {}, active = { inst = inst, state = "wait_key" },
            tick = function() ticks = ticks + 1 end, keyStatus = function() return false end,
            request = function() requests = requests + 1 end }
    end } end
    env.package.preload["utils.timer"] = function() return { sleepInterruptible = function(n)
        clock = clock + n
        if ticks == 3 then monitor.stop() end
    end } end
    monitor = env.require("managers.monitor")
    monitor.start({ launchWaitInterval = 3 }, { autoLaunch = true })
    assert(ticks == 3 and syncs == 3 and notices == 1 and requests == 1)
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
