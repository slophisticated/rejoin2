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

local function monitorScenario(opts)
    local env = sandbox()
    local clock, lastLaunch = 1000, opts.launchedAt
    local recovered = lastLaunch ~= nil
    local recoveries, relaunches = {}, {}
    env.os.time = function() return clock end
    env.io.popen = function() return { read = function() return "" end, close = noop } end
    for _, name in ipairs({ "utils.probe_log", "managers.username", "managers.window_layout", "managers.webhook", "managers.delta_key", "managers.optimizer" }) do
        env.package.preload[name] = dummy
    end
    -- The monitor waits through Remote.idle (a long poll on the bot): here a plain sleep.
    env.package.preload["managers.remote"] = function()
        local remote = dummy()
        remote.idle = function(n, stop) return env.require("utils.timer").sleepInterruptible(n, stop) end
        return remote
    end
    env.package.preload["managers.status"] = function()
        local status = dummy()
        status.check = function() return opts.status and opts.status(clock) or "freeze" end
        status.isFreezeTimeout = function() return opts.freeze == true end
        return status
    end
    env.package.preload["managers.auth"] = function()
        return { isLoggedIn = function() if opts.loggedIn then return opts.loggedIn(clock) end return true end }
    end
    env.package.preload["managers.instance"] = function()
        local list = {{ id = 1, name = "Clone1", package = "com.test.clone" }}
        return { getAll = function() return list end,
            find = function(ref) return tostring(ref) == "1" and list[1] or nil end }
    end
    env.package.preload["managers.apk"] = function()
        return { isRunning = function() return recovered and not opts.dead end }
    end
    env.package.preload["managers.heartbeat"] = function()
        return {
            install = function() return true end,
            isEnabled = function() return false end,
            launchedAt = function() return lastLaunch end,
            isUp = function() return false end,
            alive = function()
                if recovered and opts.kicked then return false, "kicked: disconnected" end
                if recovered and opts.stale then return false, "heartbeat berhenti 90s" end
                return nil
            end,
        }
    end
    env.package.preload["managers.recovery"] = function()
        return {
            checkAndRecover = function()
                recoveries[#recoveries + 1] = clock
                recovered, lastLaunch = true, clock
                return true
            end,
            launchAndJoin = function()
                relaunches[#relaunches + 1] = "join@" .. clock
                return true
            end,
            relaunch = function()
                relaunches[#relaunches + 1] = clock
                recovered, lastLaunch = true, clock
                return true
            end,
        }
    end
    env.package.preload["utils.timer"] = function()
        return { sleepInterruptible = function(n)
            clock = clock + n
            if clock >= 1000 + (opts.duration or 15) then env.require("managers.monitor").stop() end
        end }
    end
    env.require("managers.monitor").start({ monitorInterval = 5, gracePeriod = opts.grace or 30 })
    return recoveries, relaunches
end

test("low RSS after recovery waits at least 60 seconds, then retries", function()
    local times = monitorScenario({ duration = 75 })
    assert(times[1] == 1000)
    assert(#times == 2 and times[2] >= 1060, "clone was recovered again while loading")
end)

test("a longer configured grace period is respected", function()
    local times = monitorScenario({ duration = 90, grace = 120 })
    assert(#times == 1)
end)

test("a fresh launch is protected from freeze relaunch and RSS recovery", function()
    local times, relaunches = monitorScenario({ launchedAt = 1000, freeze = true })
    assert(#times == 0 and #relaunches == 0)
end)

test("a fresh kick is recovered immediately during loading grace", function()
    local times = monitorScenario({ kicked = true, duration = 10 })
    assert(times[1] == 1000 and times[2] == 1005)
end)

test("a dead process is recovered immediately during loading grace", function()
    local times = monitorScenario({ dead = true, duration = 10 })
    assert(times[1] == 1000 and times[2] == 1005)
end)

test("a stopped session heartbeat is not hidden by loading grace", function()
    local times = monitorScenario({ stale = true, duration = 15 })
    assert(times[1] == 1000 and times[2] <= 1010)
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

-- Remote.idle: the monitor's wait is a long poll; a queued command is synced at once.
local function idleScenario(pollReplies)
    local env = sandbox()
    local now = 1000
    env.os.time = function() return now end
    local conf = { remote = { url = "https://test.invalid", secret = "" } }
    env.package.preload["core.config"] = function() return { get = function() return conf end, save = noop } end
    for _, m in ipairs({ "managers.webhook", "managers.status", "managers.heartbeat", "managers.username",
        "managers.instance", "managers.window_layout" }) do
        env.package.preload[m] = function() return {} end
    end
    env.package.preload["managers.autoexecute"] = function()
        return { scriptsList = function() return {} end, autoList = function() return {} end }
    end
    local slept = 0
    env.package.preload["utils.timer"] = function()
        return { sleepInterruptible = function(s) slept = slept + s; now = now + s; return true end }
    end
    env.io.open = function(path, mode)
        if mode == "r" then
            if path ~= "data/device_id.txt" then return nil end
            return { read = function() return "0123456789abcdef" end, close = noop }
        end
        return { write = noop, close = noop }
    end
    local log, syncs = {}, 0
    env.io.popen = function(cmd)
        local path = cmd:match("/api/%a+")
        if not path then return { read = function() return "" end, close = noop } end
        log[#log + 1] = path
        local out = '{"ok":true}\n200'
        if path == "/api/sync" then
            syncs = syncs + 1
            out = (syncs > 1 and '{"commands":[{"id":"c_1","type":"nope","args":{}}]}' or '{"commands":[]}') .. "\n200"
        elseif path == "/api/poll" then
            local r = table.remove(pollReplies, 1) or { after = 25, body = '{"pending":false}', code = 200 }
            now = now + r.after
            out = r.body .. "\n" .. r.code
        end
        return { read = function() return out end, close = noop }
    end
    local Remote = env.require("managers.remote")
    assert(Remote.tick({}, {}) == true)
    return Remote, log, function() return slept end, function() return now end
end

test("a command queued during the monitor wait is synced at once, then the wait continues", function()
    local Remote, log, slept, now = idleScenario({
        { after = 1, body = '{"pending":true}', code = 200 },
        { after = 4, body = '{"pending":false}', code = 200 },
    })
    local start = now()
    assert(Remote.idle(5, nil, {}, {}) == true)
    assert(table.concat(log, " ") == "/api/sync /api/poll /api/sync /api/ack /api/poll", table.concat(log, " "))
    assert(now() - start == 5 and slept() == 0, "idle did not last exactly the monitor wait")
end)

test("an old bot without /api/poll falls back to plain sleeps", function()
    local Remote, log, slept = idleScenario({ { after = 0, body = '{"error":"not_found"}', code = 404 } })
    assert(Remote.idle(5, nil, {}, {}) == true and slept() == 5)
    assert(Remote.idle(5, nil, {}, {}) == true and slept() == 10)
    assert(table.concat(log, " ") == "/api/sync /api/poll", "old bot was polled again: " .. table.concat(log, " "))
end)

test("a poll that returns early never turns into a busy loop", function()
    local Remote, log, slept = idleScenario({ { after = 0, body = '{"pending":false}', code = 200 },
        { after = 0, body = "", code = 0 } })
    assert(Remote.idle(5, nil, {}, {}) == true and slept() == 5)
    assert(#log == 2)
end)

test("a clone logged in by hand after nologin is queued once to open its game", function()
    -- Login screen until t=1010, then logged in on the Roblox home screen.
    local _, relaunches = monitorScenario({ duration = 30,
        status = function(t) return t < 1010 and "nologin" or "running" end,
        loggedIn = function(t) return t >= 1010 end })
    local joins = 0
    for _, r in ipairs(relaunches) do if tostring(r):find("^join@") then joins = joins + 1 end end
    assert(joins == 1, "expected one game join after login, got " .. joins)
end)

local function apkScenario(instances)
    local env = sandbox()
    local cmds = {}
    env.package.preload["utils.shell"] = function()
        return { exec = function(cmd) cmds[#cmds + 1] = cmd; return true, "" end }
    end
    env.package.preload["managers.instance"] = function() return { getAll = function() return instances end } end
    return env.require("managers.apk"), cmds
end

test("force-stop refuses a bad package name and a package shared by two clones", function()
    local APK, cmds = apkScenario({ { package = "com.a.one" }, { package = "com.a.two" }, { package = "com.a.two" } })
    assert(APK.forceStop("com.a.one") == true and cmds[1] == "am force-stop 'com.a.one'", tostring(cmds[1]))
    local ok, why = APK.forceStop("com.a.two")
    assert(ok == false and why:find("lebih dari satu", 1, true))
    assert(APK.forceStop("x; reboot") == false and APK.forceStop(nil) == false)
    assert(#cmds == 1, "a refused force-stop still ran a command")
end)

local function deltaScenario(found)
    local env = sandbox()
    local files, shell = {}, {}
    env.package.preload["core.config"] = function()
        return { get = function() return { appAutoExecutePath = "/sdcard/Delta/Autoexecute", deltaLicensePath = "" } end }
    end
    env.package.preload["utils.shell"] = function()
        return { exec = function(cmd)
            shell[#shell + 1] = cmd
            if found and cmd:find("ls -a '/sdcard/Delta/internal/cache'", 1, true) then return true, ".\n..\nlicense\n" end
            return true, ""
        end }
    end
    env.package.preload["utils.file"] = function()
        return { read = function(p) return files[p] end, write = function(p, c) files[p] = c; return true end }
    end
    env.io.open = function(path, mode)
        if mode ~= "w" then return nil end
        files[path] = ""
        return { write = function(self, v) files[path] = files[path] .. v; return self end, close = function() return true end }
    end
    return env.require("managers.delta_key"), files, shell
end

test("a typed Delta key goes to the license file found, never to a command line", function()
    local DeltaKey, files, shell = deltaScenario(true)
    local key = "FREE_abc123"
    assert(DeltaKey.input(key) == true)
    assert(files["/sdcard/Delta/internal/cache/license"] == key)
    for _, cmd in ipairs(shell) do assert(not cmd:find(key, 1, true), "key reached a shell command") end
    assert(DeltaKey.input("two words") == false and DeltaKey.input("") == false)
end)

test("without a license file yet, the key goes to <Delta>/Internals/Cache/license", function()
    local DeltaKey, files = deltaScenario(false)
    assert(DeltaKey.input("FREE_new") == true)
    assert(files["/sdcard/Delta/Internals/Cache/license"] == "FREE_new")
end)

local function executorScenario(current, dirs, hbTimes, wsTimes)
    local env = sandbox()
    env.os.time = function() return 100000 end
    local conf = { appAutoExecutePath = current }
    local saves = 0
    env.package.preload["core.config"] = function()
        return { get = function() return conf end, save = function() saves = saves + 1; return true end }
    end
    env.package.preload["utils.shell"] = function()
        return { exec = function(cmd)
            if cmd:find("find /sdcard/", 1, true) then return true, table.concat(dirs, "\n") end
            if cmd:find("stat -c", 1, true) then
                local times = cmd:find("hb_", 1, true) and hbTimes or wsTimes
                local out = {}
                for i = 1, #dirs do out[#out + 1] = i .. ":" .. tostring(times and times[i] or "") end
                return true, table.concat(out, "\n")
            end
            for _, d in ipairs(dirs) do
                if cmd:find("[ -d ", 1, true) and cmd:find(d .. "'", 1, true) then return true, "IS_DIR" end
            end
            return true, ""
        end }
    end
    return env.require("managers.executor"), conf, function() return saves end
end

local DELTA, CODEX = "/sdcard/Delta/Autoexecute", "/sdcard/Codex/autoexec"

test("executor: the configured folder stays while no other executor reports", function()
    local Executor, conf, saves = executorScenario(DELTA, { CODEX, DELTA }, { 0, 0 })
    assert(Executor.ensure() == DELTA and saves() == 0 and conf.appAutoExecutePath == DELTA)
end)

test("executor: Delta missing and one other executor found = switched and saved", function()
    local Executor, conf, saves = executorScenario(DELTA, { CODEX, "/sdcard/Android/data/x/files/autoexec" })
    local path, changed = Executor.ensure()
    assert(path == CODEX and changed == true and saves() == 1, tostring(path))
    assert(conf.appAutoExecutePath == CODEX and Executor.name(path) == "Codex")
end)

test("executor: switches to the executor with a fresh heartbeat, without the menu", function()
    -- Delta's last heartbeat is an hour old; Codex wrote one a minute ago.
    local Executor, conf = executorScenario(DELTA, { CODEX, DELTA }, { 100000 - 60, 100000 - 3600 })
    local path, changed = Executor.ensure()
    assert(path == CODEX and changed and conf.appAutoExecutePath == CODEX)
end)

test("executor: old leftovers never undo the current one, a reporting one stays", function()
    -- Picked Codex in the menu; Delta has a 2 hour old heartbeat file left over.
    local Executor, conf = executorScenario(CODEX, { CODEX, DELTA }, { 0, 100000 - 7200 })
    assert(Executor.ensure() == CODEX and conf.appAutoExecutePath == CODEX)
    -- Both report, Delta slightly newer: the current one (still reporting) stays.
    Executor, conf = executorScenario(CODEX, { CODEX, DELTA }, { 100000 - 30, 100000 - 5 })
    assert(Executor.ensure() == CODEX and conf.appAutoExecutePath == CODEX)
end)

test("executor: no heartbeat yet and no folder configured = newest Workspace wins", function()
    local Executor, conf = executorScenario("", { CODEX, DELTA }, { 0, 0 }, { 100000 - 50, 100000 - 900 })
    assert(Executor.ensure() == CODEX and conf.appAutoExecutePath == CODEX)
    local list = Executor.scan()
    assert(#list == 2 and list[1].name == "Codex" and list[2].name == "Delta")
end)

test("GoFile installer rejects any link that is not gofile.io before touching the network", function()
    local env = sandbox()
    local ran = 0
    env.os.execute = function() ran = ran + 1; return true, "exit", 0 end
    env.package.preload["utils.shell"] = function() return { exec = function() ran = ran + 1; return true, "" end } end
    local GoFile = env.require("managers.gofile_apk")
    for _, link in ipairs({ "https://evil.example/d/abcd", "http://gofile.io.evil.example/d/abcd",
        "https://gofile.io/", "file:///sdcard/x.apk", "" }) do
        local files, err = GoFile.list(link)
        assert(files == nil and type(err) == "string", link)
    end
    assert(ran == 0, "a rejected link still ran a command")
end)

test("Delta license detection never takes the hidden .license companion", function()
    local env = sandbox()
    local files = {}
    env.package.preload["core.config"] = function()
        return { get = function() return { appAutoExecutePath = "/sdcard/Delta/Autoexecute", deltaLicensePath = "" } end }
    end
    env.package.preload["utils.shell"] = function()
        return { exec = function(cmd)
            if cmd:find("ls -a '/sdcard/Delta/Internals/Cache'", 1, true) then return true, ".\n..\n.license\ndata\nlicense\nui\n" end
            return true, ""
        end }
    end
    env.package.preload["utils.file"] = function()
        return { read = function(p) return files[p] end, write = function(p, c) files[p] = c; return true end }
    end
    -- An older build remembered ".license": ignored.
    files["data/delta_license_path.txt"] = "/sdcard/Delta/.license"
    local DeltaKey = env.require("managers.delta_key")
    assert(DeltaKey.path() == "/sdcard/Delta/Internals/Cache/license", tostring(DeltaKey.path()))
end)

test("error report masks webhook URLs, cookies, bearer tokens, the bot secret and the HWID", function()
    local env = sandbox()
    env.package.preload["core.config"] = function() return { get = function() return {} end } end
    local Report = env.require("managers.report")
    local text = Report.redact(table.concat({
        "kirim ke https://discord.com/api/webhooks/123/abc_DEF-xyz gagal",
        "https://canary.discordapp.com/api/webhooks/9/zz",
        "cookie _|WARNING:-DO-NOT-SHARE-THIS.--x|_ABC123; next",
        ".ROBLOSECURITY=ABCDEF123; path=/",
        "Authorization: Bearer topsecret123",
        "secret=my-bot-secret-0123456789 hwid 0123456789abcdef",
    }, "\n"), { secret = "my-bot-secret-0123456789", hwid = "0123456789abcdef" })
    for _, leak in ipairs({ "abc_DEF", "/9/zz", "DO-NOT-SHARE", "ABCDEF123", "topsecret123", "my-bot-secret", "0123456789abcdef" }) do
        assert(not text:find(leak, 1, true), "leaked: " .. leak .. "\n" .. text)
    end
    assert(text:find("[webhook]", 1, true) and text:find("[cookie]", 1, true) and text:find("[hwid]", 1, true))
    assert(Report.base64("foobar") == "Zm9vYmFy" and Report.base64("fo") == "Zm8=")
end)

-- Launch All with a heartbeat that already says "in game" (another clone's file, a
-- leftover, or two clones read as one username): the next clone must still wait.
local function launchScenario(names, aliveFn)
    local env = sandbox()
    local clock = 1000
    local launches = {}
    env.os.time = function() return clock end
    env.io.popen = function() return { read = function() return "" end, close = noop } end
    for _, name in ipairs({ "utils.probe_log", "managers.window_layout", "managers.webhook", "managers.delta_key", "managers.optimizer" }) do
        env.package.preload[name] = dummy
    end
    env.package.preload["managers.remote"] = function()
        local remote = dummy()
        remote.idle = function(n, stop) return env.require("utils.timer").sleepInterruptible(n, stop) end
        return remote
    end
    env.package.preload["managers.username"] = function()
        local u = dummy()
        u.get = function(inst) return names[inst.id] end
        return u
    end
    env.package.preload["managers.status"] = function() local st = dummy(); st.check = function() return "ingame" end; return st end
    env.package.preload["managers.auth"] = function() return { isLoggedIn = function() return true end } end
    local list = { { id = 1, name = "Clone1", package = "com.t.one" }, { id = 2, name = "Clone2", package = "com.t.two" },
        { id = 3, name = "Clone3", package = "com.t.three" } }
    env.package.preload["managers.instance"] = function()
        return { getAll = function() return list end, find = function() return nil end }
    end
    env.package.preload["managers.apk"] = function()
        return { isRunning = function() return true end, isActive = function() return true end }
    end
    local launchedAt = {}
    env.package.preload["managers.heartbeat"] = function()
        return {
            install = function() return true end,
            isEnabled = function() return true end,
            launchedAt = function(inst) return launchedAt[inst.package] end,
            isUp = function() return true end,
            alive = function(inst) return aliveFn(inst, clock, launchedAt[inst.package]) end,
        }
    end
    env.package.preload["managers.recovery"] = function()
        return { launchAndJoin = function(inst)
            launches[#launches + 1] = clock
            launchedAt[inst.package] = clock
            return true
        end }
    end
    env.package.preload["utils.timer"] = function()
        return { sleepInterruptible = function(n)
            clock = clock + n
            if clock >= 1600 then env.require("managers.monitor").stop() end
            return true
        end, sleep = function(n) clock = clock + n end }
    end
    env.require("managers.monitor").start({ monitorInterval = 5, launchJoinTimeout = 240, launchSettleDelay = 20,
        launchWaitInterval = 3, launchWaitTimeout = 60 }, { autoLaunch = true })
    return launches
end

test("Launch All: a heartbeat seen right after a launch is too fast and is waited out", function()
    -- The heartbeat file already reads "in game" (e.g. a leftover / another clone's).
    local launches = launchScenario({ "a", "b", "c" }, function() return true end)
    assert(#launches == 3, "launches: " .. #launches)
    for i = 2, 3 do
        assert(launches[i] - launches[i - 1] >= 10, string.format("clone %d started %ds after the previous one",
            i, launches[i] - launches[i - 1]))
    end
end)

test("Launch All: clones read as the same username get the settle delay, not each other's heartbeat", function()
    local launches = launchScenario({ "same", "same", "c" }, function() return true end)
    assert(#launches == 3)
    assert(launches[2] - launches[1] >= 20, "clone 2 started " .. (launches[2] - launches[1]) .. "s after clone 1")
end)

test("Launch All: a real join (heartbeat after 30s) is waited for before the next clone", function()
    local launches = launchScenario({ "a", "b", "c" }, function(_, now, at)
        if at and now - at >= 30 then return true end
        return nil
    end)
    assert(#launches == 3 and launches[2] - launches[1] >= 30 and launches[3] - launches[2] >= 30)
end)

local function recoveryScenario(loggedIn, running)
    local env = sandbox()
    local calls, freshAsked = {}, nil
    env.package.preload["managers.apk"] = function()
        return { forceStop = function() calls[#calls + 1] = "forceStop"; return true end,
            isRunning = function() return running end,
            launch = function() calls[#calls + 1] = "launch"; return true end }
    end
    env.package.preload["utils.android"] = function()
        return { openURL = function() calls[#calls + 1] = "openURL"; return true end }
    end
    env.package.preload["managers.auth"] = function()
        return { isLoggedIn = function(_, fresh) freshAsked = fresh; return loggedIn end }
    end
    env.package.preload["managers.instance"] = function()
        return { gameLink = function() return "https://www.roblox.com/games/1" end,
            presetOf = function() return "A", "default", "https://www.roblox.com/games/1" end }
    end
    for _, m in ipairs({ "utils.timer", "core.config", "managers.status", "managers.window_layout", "managers.heartbeat" }) do
        env.package.preload[m] = dummy
    end
    local Recovery = env.require("managers.recovery")
    local ok = Recovery.launchAndJoin({ id = 1, name = "Clone1", package = "com.t.one", preset = "A" })
    return ok, table.concat(calls, ","), freshAsked
end

test("a logged-out clone is never force-stopped or sent to the game link", function()
    local ok, calls, fresh = recoveryScenario(false, true)
    assert(ok and calls == "" and fresh == true, "open at the login screen: " .. calls)
    ok, calls = recoveryScenario(false, false)
    assert(ok and calls == "launch", "closed: opened gently only, got " .. calls)
    ok, calls = recoveryScenario(true, true)
    assert(calls:find("forceStop", 1, true) and calls:find("openURL", 1, true), "logged in still joins: " .. calls)
end)

test("logout ends the Roblox session (CSRF round) without the token on a command line", function()
    local env = sandbox()
    local files, cmds, step = {}, {}, 0
    env.io.open = function(path, mode)
        if mode == "w" then
            files[path] = ""
            return { write = function(self, ...) for _, v in ipairs({ ... }) do files[path] = files[path] .. v end; return self end,
                close = noop }
        end
        if not files[path] then return nil end
        return { read = function() return files[path] end, close = noop }
    end
    env.os.remove = function(path) files[path] = nil end
    local sentCsrf
    env.io.popen = function(cmd)
        cmds[#cmds + 1] = cmd
        step = step + 1
        local req = cmd:match("%-H @'([^']+)'")
        local resp = cmd:match("%-D '([^']+)'")
        sentCsrf = files[req] and files[req]:match("X%-CSRF%-TOKEN: (%S+)")
        if step == 1 then files[resp] = "HTTP/2 403\r\nx-csrf-token: abc123\r\n"; return { read = function() return "403" end, close = noop } end
        files[resp] = "HTTP/2 200\r\n"
        return { read = function() return "200" end, close = noop }
    end
    for _, m in ipairs({ "managers.auth", "managers.apk", "utils.shell", "utils.timer" }) do env.package.preload[m] = dummy end
    local CI = env.require("managers.cookie_injector")
    local token = "_|WARNING:-DO-NOT-SHARE-THIS.--x|_TOKENVALUE1234567890"
    local ok, msg = CI.revokeSession(token)
    assert(ok and msg:find("dimatiin", 1, true), tostring(msg))
    assert(#cmds == 2 and sentCsrf == "abc123", "csrf round")
    for _, c in ipairs(cmds) do assert(not c:find("TOKENVALUE", 1, true), "token on the command line") end
    for path in pairs(files) do assert(not path:find("rejoin_logout", 1, true), "temp file left: " .. path) end
end)

test("error report folds a repeated warning into one line with a count", function()
    local env = sandbox()
    env.package.preload["core.config"] = function() return { get = function() return {} end } end
    local Report = env.require("managers.report")
    local out = Report.collapse({
        "[07:13:33] [WARN] Monitor: instance not healthy: Clone2",
        "[07:14:00] [WARN] Monitor: instance not healthy: Clone2",
        "[07:30:31] [WARN] Monitor: Clone4 heartbeat berhenti 99s",
        "[07:40:30] [WARN] Monitor: instance not healthy: Clone2",
    }, 40)
    assert(#out == 2, table.concat(out, "\n"))
    assert(out[1] == "[07:30:31] [WARN] Monitor: Clone4 heartbeat berhenti 99s")
    assert(out[2] == "[07:40:30] [WARN] Monitor: instance not healthy: Clone2  (x3)", out[2])
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
