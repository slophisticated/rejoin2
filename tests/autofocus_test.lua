-- Run from the repository root: lua tests/autofocus_test.lua
-- A healthy clone whose window vanished is focused (no kill, no launch);
-- dead clones fall back to launch; visible ones are untouched.
local noop = function() end
package.loaded["core.logger"] = { info = noop, warn = noop, debug = noop, error = noop }
local launched, focused = {}, {}
package.loaded["utils.shell"] = { exec = function(cmd)
    cmd = tostring(cmd or "")
    if cmd:find("dumpsys window windows", 1, true) then
        if cmd:find("gone") then return true, "Window{abc u0 com.gone}]" end
        return true, "Window{abc u0 com.mini/com.mini.Activity}"
    end
    return true, "ok"
end }
local APK = require("managers.apk")
APK.isRunning = function(pkg) return pkg ~= "com.dead" end
APK.hasWindow = function(pkg) return pkg ~= "com.mini" end
local realLaunch = APK.launch
APK.launch = function(pkg) launched[#launched + 1] = pkg; return true end
assert(APK.focus("com.mini") == true, "minimized harus di-focus tanpa kill")
assert(#launched == 0, "focus ga boleh launch ulang: " .. table.concat(launched, ","))
assert(APK.focus("com.visible") == true and #launched == 0, "yang keliatan jangan disentuh")
assert(APK.focus("com.dead") == true and launched[1] == "com.dead", "yang mati fallback launch")
APK.launch = realLaunch
print("PASS: autofocus buka jendela minimize tanpa restart")
