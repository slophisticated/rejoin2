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

test("without a license file yet, the key goes to <Delta>/internal/cache/license", function()
    local DeltaKey, files = deltaScenario(false)
    assert(DeltaKey.input("FREE_new") == true)
    assert(files["/sdcard/Delta/internal/cache/license"] == "FREE_new")
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
