-- Run from the repository root: lua tests/logout_test.lua
local noop = function() end
package.loaded["core.logger"] = { info = noop, warn = noop, debug = noop, error = noop }
local instances = { { id = 4, package = "com.apengjers.v6" } }
package.loaded["managers.instance"] = { getAll = function() return instances end }
local command, shellOK, shellOut = nil, true, "REJOIN_STOPPED"
package.loaded["utils.shell"] = { exec = function(cmd)
    command = cmd; return shellOK, shellOut
end }
local APK = require("managers.apk")
assert(APK.stopProcesses("com.apengjers.v6"))
assert(command:find("kill -9", 1, true) and command:find("/cmdline", 1, true))
assert(not command:find("force-stop", 1, true))
local script = command:match("^sh %-c '(.*)'$"):gsub("'\\''", "'")
if os.getenv("REJOIN_STOP_SCRIPT") then
    local f = assert(io.open(os.getenv("REJOIN_STOP_SCRIPT"), "w")); f:write(script); f:close()
end
shellOK = false
assert(not APK.stopProcesses("com.apengjers.v6"))
instances[2] = instances[1]
command = nil
assert(not APK.stopProcesses("com.apengjers.v6") and command == nil)
assert(not APK.stopProcesses("bad;kill") and command == nil)
instances[2] = nil

-- Exercise logout without reading real cookies or touching real files.
local stops, deletes, verifies, stopOK, remaining = 0, 0, 0, true, "0"
package.loaded["managers.apk"] = { stopProcesses = function()
    stops = stops + 1; return stopOK, "stop failed"
end, forceStop = function() error("logout used force-stop") end }
package.loaded["managers.auth"] = { getBaseDir = function() return "/data/target" end, forget = noop }
package.loaded["utils.timer"] = { sleep = noop }
package.loaded["utils.shell"].exec = function(cmd)
    if cmd:find("find ", 1, true) then return true, "/data/target/Cookies" end
    if cmd:find("AE_YES", 1, true) then return true, "AE_YES" end
    if cmd:find("SELECT 1", 1, true) then return true, "1" end
    if cmd:find("SELECT COUNT", 1, true) then
        verifies = verifies + 1
        return true, deletes > 0 and remaining or "1"
    end
    if cmd:find("SELECT value", 1, true) then return true, string.rep("t", 25) end
    if cmd:find("DELETE FROM", 1, true) then deletes = deletes + 1 end
    return true, ""
end
local oldOpen = io.open
io.open = function() return { write = noop, close = noop } end
local Cookies = require("managers.cookie_injector")
Cookies.revokeSession = function() return true, "session invalid" end
stopOK = false
assert(not Cookies.logout(instances[1]) and deletes == 0)
stopOK = true
assert(Cookies.logout(instances[1]) and deletes == 1 and stops == 4 and verifies >= 3)
deletes, remaining = 0, "1"
assert(not Cookies.logout(instances[1]), "remaining cookie reported as logout success")
io.open = oldOpen
print("PASS: PID stop has no force-stop fallback; logout aborts on stop failure and verifies cookie deletion")
