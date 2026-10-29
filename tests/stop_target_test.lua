-- Run from the repository root: lua tests/stop_target_test.lua
-- Option B: every restart path stops only the target's PIDs, waits for free RAM,
-- and never touches a peer package or Android's stopped state.
local noop = function() end
package.loaded["core.logger"] = { info = noop, warn = noop, debug = noop, error = noop }

local calls, pidsOne = {}, { "4242" }
package.loaded["managers.apk"] = {
    pids = function(pkg)
        if pkg == "com.t.one" then return pidsOne end
        return {}
    end,
    stopProcesses = function(pkg)
        calls[#calls + 1] = "stop:" .. tostring(pkg)
        if pkg == "com.t.one" then pidsOne = {} return true end
        return false
    end,
    waitForMemory = function(minMb, timeout)
        calls[#calls + 1] = "memory:" .. tostring(minMb) .. "/" .. tostring(timeout)
        return true
    end,
    freeMemoryMb = function() return 900 end,
    isRunning = function(pkg) return pkg == "com.t.one" and #pidsOne > 0 end,
    launch = function(pkg) calls[#calls + 1] = "launch:" .. tostring(pkg); return true end,
}
package.loaded["utils.android"] = { openURL = function()
    calls[#calls + 1] = "openURL"; return true
end }
package.loaded["utils.probe_log"] = { line = noop, pids = function(name, pkg, before, after, ok, peers)
    calls[#calls + 1] = "probe:" .. tostring(before) .. "->" .. tostring(after) .. ":" .. tostring(peers)
end }
package.loaded["managers.auth"] = { isLoggedIn = function() return true end }
package.loaded["managers.instance"] = {
    getAll = function() return { { package = "com.t.one" }, { package = "com.t.two" } } end,
    gameLink = function() return "https://www.roblox.com/games/1" end,
    presetOf = function() return "A", "default", "https://www.roblox.com/games/1" end,
}
for _, m in ipairs({ "utils.timer", "core.config", "managers.status", "managers.window_layout" }) do
    package.loaded[m] = setmetatable({}, { __index = function() return noop end })
end
package.loaded["managers.heartbeat"] = { isUp = function() return true end,
    alive = function() return true end, markLaunched = noop, launchedAt = function() return nil end,
    isEnabled = function() return true end }
package.loaded["core.config"] = { get = function() return { launchMinFreeMb = 250, launchFreeWait = 45 } end }

local Recovery = require("managers.recovery")
local inst = { id = 1, name = "Clone1", package = "com.t.one", preset = "A" }

-- Autojoin a running target: PID stop, RAM wait, then the game link. No force-stop.
calls = {}
assert(Recovery.launchAndJoin(inst))
assert(calls[1] == "stop:com.t.one", "target tidak di-stop dulu: " .. table.concat(calls, ","))
assert(calls[3] == "memory:250/45", "RAM tidak dicek sebelum join: " .. table.concat(calls, ","))
assert(calls[4] == "openURL", "link game tidak dibuka: " .. table.concat(calls, ","))
assert(not table.concat(calls, ","):find("com.t.two", 1, true), "peer kesenggol: " .. table.concat(calls, ","))
local probe = table.concat(calls, ",")
assert(probe:find("probe:4242", 1, true), "bukti pid tidak dicatat: " .. probe)

-- Every other restart path uses the same PID stop.
calls, pidsOne = {}, { "4242" }
assert(Recovery.relaunch(inst) and calls[1] == "stop:com.t.one")
calls, pidsOne = {}, { "4242" }
assert(Recovery.checkAndRecover(inst) and calls[1] == "stop:com.t.one")
print("PASS: restart hanya stop target + tunggu RAM, peer tidak kesenggol")
