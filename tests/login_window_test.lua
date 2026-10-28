-- Run from the repository root: lua tests/login_window_test.lua
local noop = function() end
package.loaded["core.logger"] = { info = noop, debug = noop, warn = noop, error = noop }
local dump = "Window #0 Window{abc u0 com.other/.Main}:\n mLastFocus=Window{old u0 clone.a/.Main}\n"
package.loaded["utils.shell"] = { exec = function() return true, dump end }
local APK = require("managers.apk")
assert(APK.hasWindow("clone.a") == false, "stale focus must not count as a window")
dump = "Window #0 Window{abc u0 clone.a}:\n mAttrs=SYSTEM_ALERT_WINDOW\n"
assert(APK.hasWindow("clone.a") == true, "floating overlay must count")
dump = "Window #0 Window{abc u0 clone.a/com.roblox.client.ActivityNativeMain}:\n"
assert(APK.hasWindow("clone.a") == true)
local visible, opens = false, 0
APK.isRunning = function() return true end
APK.hasWindow = function() return visible end
APK.launch = function() opens = opens + 1; return true end
APK.forceStop = function() error("logged-out clone must never be force-stopped") end
package.loaded["utils.android"] = {}
package.loaded["utils.timer"] = {}
package.loaded["core.config"] = {}
package.loaded["managers.status"] = {}
package.loaded["managers.auth"] = { isLoggedIn = function() return false end }
package.loaded["managers.window_layout"] = {}
package.loaded["managers.heartbeat"] = { markLaunched = noop }
local Recovery = require("managers.recovery")
assert(Recovery.launchAndJoin({ package = "clone.a" }))
assert(opens == 1, "live process without window must be opened gently")
visible = true
assert(Recovery.launchAndJoin({ package = "clone.a" }))
assert(opens == 1, "existing floating window must stay untouched")
print("PASS: actual window headers, floating overlays and gentle login reopening")
