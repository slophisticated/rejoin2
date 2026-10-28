-- Run from the repository root: lua tests/auth_fresh_test.lua
local noop = function() end
package.loaded["core.logger"] = { info = noop, debug = noop }
package.loaded["managers.cookie_injector"] = { locateCookieDbs = function() return {} end }
local phase = "missing"
package.loaded["utils.shell"] = { exec = function(cmd)
    if cmd:find("AE_DIR", 1, true) then
        return true, phase == "missing" and "AE_NODIR" or "AE_DIR"
    end
    return false, "simulated scan timeout", 124
end }
local Auth = require("managers.auth")
local inst = { package = "clone.a" }
assert(Auth.isLoggedIn(inst, true) == false)
phase = "unreadable"
assert(Auth.isLoggedIn(inst, true) == false, "legacy callers retain last definite answer")
assert(Auth.isLoggedIn(inst, true, true) == nil, "strict probe must not confirm logout from old cache")
print("PASS: strict login verification rejects cached logout when the current scan fails")
