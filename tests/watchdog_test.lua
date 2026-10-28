-- Run from the repository root: lua tests/watchdog_test.lua
local files, now, sends = {}, 1000, 0
local originalTime, originalGetenv, originalOpen = os.time, os.getenv, io.open
os.time = function() return now end
os.getenv = function(key) if key == "REJOIN_ENGINE_PID" then return "123" end end
io.open = function(path, mode)
    assert(mode == "w")
    return { write = function(_, ...) files[path] = table.concat({...}) end, close = function() end }
end
local rename = os.rename
os.rename = function(a, b) files[b] = files[a]; files[a] = nil; return true end
local Health = require("managers.engine_health")
Health.touch()
assert(files["data/engine_health.txt"] == "123 1000\n")
now = 1005; Health.touch()
assert(files["data/engine_health.txt"] == "123 1000\n")
now = 1010; Health.touch()
assert(files["data/engine_health.txt"] == "123 1010\n")
io.open, os.getenv, os.time, os.rename = originalOpen, originalGetenv, originalTime, rename
print("PASS: engine liveness is owner-scoped, atomic and throttled")

package.loaded["utils.file"] = { read = function(p) return files[p] end,
    write = function(p, text) files[p] = text; return true end }
local config = { webhook = { url = "https://discord.com/api/webhooks/123/secret-token" } }
package.loaded["core.config"] = { get = function() return config end }
package.loaded["managers.report"] = { redact = function(text) return text end }
local popen, execute, remove = io.popen, os.execute, os.remove
io.open = function() return nil end
os.execute = function(cmd) assert(not cmd:find("secret-token", 1, true)); return true end
os.remove = function(p) files[p] = nil end
local code = "200"
io.popen = function(cmd)
    assert(not cmd:find("secret-token", 1, true), "webhook secret in command line")
    sends = sends + 1
    return { read = function() return code end, close = function() end }
end
arg = { "crash", "123" }
dofile("utils/watchdog_report.lua")
assert(sends == 0 and files["data/watchdog_pending.txt"], "missing status message must never POST")
files["data/webhook_msg.txt"] = "456\n"
code = "500"; arg = { "retry", "123" }; dofile("utils/watchdog_report.lua")
assert(files["data/watchdog_pending.txt"], "failed upload lost pending report")
code = "200"; dofile("utils/watchdog_report.lua")
assert(sends == 2 and not files["data/watchdog_pending.txt"])
assert(files["data/watchdog_report.txt"], "local evidence must survive upload")
io.open, io.popen, os.execute, os.remove = originalOpen, popen, execute, remove
print("PASS: watchdog PATCH-only delivery, secret-free command and offline retry")
