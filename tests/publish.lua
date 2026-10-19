-- Publish smoke tests: in-memory Android filesystem/shell, no device or network.
local passed = 0
local function test(name, run)
    run()
    passed = passed + 1
    print("PASS " .. name)
end
local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end
local noop = function() end
local function device(entry, options)
    options = options or {}
    local files, commands, printed = {}, {}, {}
    if entry == "main.lua" then
        local template = assert(io.open("config/template.lua", "r"))
        files["./config/template.lua"] = template:read("*a")
        template:close()
    end
    local env = setmetatable({ os = copy(os), io = copy(io), arg = options.args or { "--dry-run", "--no-wizard" } }, { __index = _G })
    env._G = env
    env.arg[0] = options.entry or ("/downloads/" .. entry)
    env.package = { loaded = {} }
    local vars = { PWD = "/downloads", HOME = "/termux", YANAMIN_HOME = "/test/yanamin", REJOIN_WRAPPER = "1" }
    if options.wrapper then vars.REJOIN_WRAPPER = nil end
    env.os.getenv = function(name) return vars[name] end
    env.os.execute = function(cmd) commands[#commands + 1] = cmd; return true, "exit", 0 end
    env.os.remove = function(path) files[path] = nil; return true end
    env.os.exit = function(code) error({ exit = code }, 0) end
    env.print = function(...) printed[#printed + 1] = table.concat({...}, " ") end
    env.io.write, env.io.flush = noop, noop
    env.io.read = function() return "10" end
    env.io.open = function(path, mode)
        mode = mode or "r"
        if mode:sub(1, 1) == "r" and files[path] == nil then return nil end
        if mode:sub(1, 1) == "w" then files[path] = "" end
        return { read = function(_, format)
            if format == "*l" then return (files[path] or ""):match("[^\n]*") end
            return files[path] or ""
        end, write = function(_, ...)
            for _, v in ipairs({...}) do files[path] = (files[path] or "") .. tostring(v) end
        end, close = noop, seek = function() return #(files[path] or "") end }
    end
    env.io.popen = function(cmd)
        commands[#commands + 1] = cmd
        return { read = function() return "" end, close = function() return true end }
    end
    env.dofile = function(path)
        assert(files[path], "missing fake file " .. path)
        return assert(load(files[path], "@" .. path, "t", env))()
    end
    env.require = function(name)
        if env.package.loaded[name] then return env.package.loaded[name] end
        if name == "lfs" or name == "cjson" or name:match("^socket") or name:match("^posix") then error("optional module unavailable") end
        assert(entry ~= "yanamin.lua", "missing embedded module " .. name)
        local chunk = assert(loadfile(name:gsub("%.", "/") .. ".lua", "t", env))
        local value = chunk()
        env.package.loaded[name] = value
        return value
    end
    local ok, err = pcall(assert(loadfile(entry, "t", env)))
    if not ok and not (type(err) == "table" and err.exit == 0) then error(err) end
    return env, files, commands, printed
end

for _, entry in ipairs({ "main.lua", "yanamin.lua" }) do
    test(entry .. " starts with no config and shares the publish data root", function()
        -- The modular entry reads its shipped template; the bundle reads its asset.
        local env, files = device(entry)
        assert(files["/test/yanamin/config/config.lua"], "no initial config")
        local conf = env.require("core.config").get()
        assert(conf.monitorInterval == 8 and #conf.instances == 0)
        assert(conf.launchSafety.stableHeartbeats == 3 and conf.launchSafety.stableSeconds == 20)
        local instances = env.require("managers.instance")
        assert(type(instances.missingPackages) == "function")
        assert(type(instances.presetOf) == "function")
        assert(type(env.require("utils.shell").rootAvailable) == "function")
        for _, mod in ipairs({ "core.boot_cli", "core.uninstall_cli", "core.launch_cli", "core.preset_cli", "managers.remote", "managers.monitor" }) do
            assert(env.require(mod), mod .. " did not load")
        end
        assert(env.require("managers.boot").logPath() == "/test/yanamin/data/boot.log")
        assert(env.require("core.config").save(conf))
        assert(not files["config/config.lua"] and not files["data/device_id.txt"])
        env.require("managers.remote").deviceId()
        assert(files["/test/yanamin/data/device_id.txt"])
    end)
end

test("bundle installs the current heartbeat without any adjacent source files", function()
    local env, files = device("yanamin.lua")
    local ok, err = env.require("managers.heartbeat").install()
    assert(ok, err)
    local script = files["/sdcard/Delta/Autoexecute/rejoin_heartbeat.lua"]
    assert(script and script:find("REJOIN_HEARTBEAT", 1, true))
    assert(script:find("session", 1, true) and script:find('"loading"', 1, true))
end)

test("bundle supervisor quotes a loader path containing spaces and apostrophes", function()
    local _, files, commands = device("yanamin.lua", { wrapper = true, entry = "/downloads/a'b c.lua" })
    local supervisor = files["/test/yanamin/data/yanamin_wrapper.sh"]
    assert(supervisor and supervisor:find("TARGET='/downloads/a'\\''b c.lua'", 1, true))
    assert(commands[#commands]:find("sh '/test/yanamin/data/yanamin_wrapper.sh'", 1, true))
end)

test("boot script preserves the publish root and quotes the entry path", function()
    local env = device("yanamin.lua")
    local script = assert(env.require("managers.boot").script("/downloads/a'b c.lua"))
    assert(script:find("REJOIN_HOME='/test/yanamin'", 1, true))
    assert(script:find("REJOIN_ENTRY='/downloads/a'\\''b c.lua'", 1, true))
    assert(script:find('REJOIN_WRAPPER=1 "$LUA_BIN" "$REJOIN_ENTRY"', 1, true))
end)

test("publish auto-detect adds a clone using the default preset", function()
    local env = device("yanamin.lua")
    local conf = env.require("core.config").get()
    conf.presets, conf.defaultPreset = { A = { name = "Game", link = "roblox://placeId=123" } }, "A"
    local inputs = { "2", "1", "1", "Clone1", "", "5" }
    env.io.read = function() return assert(table.remove(inputs, 1), "no input") end
    env.require("utils.shell").exec = function() return true, "package:com.roblox.clone" end
    env.require("core.instances_cli").run()
    local list = env.require("managers.instance").getAll()
    assert(#list == 1 and list[1].package == "com.roblox.clone")
    assert(env.require("managers.instance").gameLink(list[1]) == "roblox://placeId=123")
end)

test("menu and cross-process rejoin state agree for modular and bundled startup", function()
    for _, entry in ipairs({ "main.lua", "yanamin.lua" }) do
        local env, files, _, printed = device(entry)
        local menu = table.concat(printed, "\n")
        assert(menu:find("6) Auto-boot", 1, true) and menu:find("7) Uninstall", 1, true))
        assert(menu:find("12) Antrean", 1, true) and menu:find("13) Start Monitor", 1, true))
        local monitor = env.require("managers.monitor")
        assert(monitor.requestRejoinFile({ 1, 2 }))
        assert(files["/test/yanamin/data/rejoin_request.txt"] == "1\n2\n")
        local config = env.require("core.config")
        local before = config.get()
        files["/test/yanamin/config/config.lua"] = 'return { launchSafety = { maxAttempts = 2 }, instances = {} }'
        assert(config.reload() and config.get() == before and before.launchSafety.maxAttempts == 2)
    end
end)

test("publish process snapshot shares probes and invalidates after force-stop", function()
    local env = device("yanamin.lua")
    local commands, active = 0, true
    env.require("utils.shell").exec = function(cmd)
        if cmd == "ps -A" then
            commands = commands + 1
            return true, "USER PID PPID VSZ RSS WCHAN ADDR S NAME\n" ..
                (active and "u0_a1 10 1 2000000 400000 ep_poll 0 S com.roblox.clone\n" or "") ..
                "root 1 0 10000 1000 ep_poll 0 S init\n"
        end
        if cmd:find("am force-stop", 1, true) then active = false end
        return true, ""
    end
    local apk = env.require("managers.apk")
    assert(apk.isRunning("com.roblox.clone") and apk.getRSSinKB("com.roblox.clone") == 400000)
    assert(commands == 1)
    apk.forceStop("com.roblox.clone")
    assert(not apk.isRunning("com.roblox.clone") and commands == 2)
end)

test("webhook keeps message IDs in the publish root and never logs a rejected URL", function()
    local env, files = device("yanamin.lua")
    local webhook = env.require("managers.webhook")
    webhook.configure({ webhook = { url = "https://bad.invalid/private-secret" } })
    assert(not webhook.enabled())
    for name, content in pairs(files) do
        if name:match("%.log$") then assert(not content:find("private-secret", 1, true)) end
    end
    local id = "123456789012345678"
    assert(webhook.useMessage(id) == id and webhook.messageId() == id)
    assert(files["/test/yanamin/data/webhook_msg.txt"] == id .. "\n")
end)

print(passed .. " publish smoke tests passed")
