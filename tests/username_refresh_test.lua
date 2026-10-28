-- Run from the repository root: lua tests/username_refresh_test.lua
local now, remote = 1000, nil
os.time = function() return now end
local shellCalls = 0
package.loaded["core.logger"] = {}
package.loaded["utils.file"] = { read = function() return "ManualAccount" end }
package.loaded["utils.shell"] = { exec = function()
    shellCalls = shellCalls + 1
    return false, ""
end }
package.loaded["managers.auth"] = { remoteName = function() return remote end }
-- Keep username evidence in memory, not in the user's data directory.
io.open = function() return nil end
local Username = require("managers.username")
local inst = { package = "clone.a" }
assert(Username.get(inst) == nil)
local calls = shellCalls
remote = "NewAccount"
assert(Username.get(inst) == "NewAccount", "negative cache hid the verified login")
remote = "ReplacementAccount"
assert(Username.get(inst) == remote, "previous account cache hid the replacement login")
assert(shellCalls == calls, "verified identity triggered extra network/local scans")
remote = nil
Username.forget(inst.package)
assert(Username.get(inst) == nil, "per-package invalidation kept the previous account")
inst.usernamePath = "manual.txt"
Username.forget(inst.package)
remote = "VerifiedAccount"
assert(Username.get(inst) == "ManualAccount", "verified identity overrode the manual file")
print("PASS: verified login replaces negative/old username caches; invalidation and manual override preserved")
