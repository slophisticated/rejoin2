-- Run from the repository root: lua tests/launch_diagnostics_test.lua
local files, commands = {}, {}
local mode = "ok"
local secret = "private-bot-secret"
package.loaded["core.config"] = { get = function() return { remote = { secret = secret } } end }
package.loaded["utils.file"] = {
    read = function(p) return files[p] end,
    write = function(p, text) files[p] = text; return true end,
}
package.loaded["utils.shell"] = { exec = function(cmd)
    commands[#commands + 1] = cmd
    assert(not cmd:find("logcat -c", 1, true), "diagnostics cleared the Android log")
    if cmd:find("logcat", 1, true) then
        if mode == "fail" then return false, "denied secret" end
        return true, table.concat({
            "10-28 15:31:08 am_kill: [0,123,clone.b,900,low memory] " .. secret,
            "10-28 15:31:08 lmkd: Kill pid 123",
            "10-28 15:31:08 AndroidRuntime: clone.b WARNING:-DO-NOT-SHARE!cookie12345",
            "10-28 15:31:08 ActivityManager: unrelated.private.app unrelated data",
        }, "\n")
    end
    if cmd:find("meminfo", 1, true) then return true, "MemAvailable: 123 kB" end
    return true, "clone.a\n111\nclone.b\n123"
end }
local D = require("managers.launch_diagnostics")
local instances = { { package = "clone.a" }, { package = "clone.b" }, { package = "bad'; command" } }
local snap = D.snapshot(instances)
assert(not commands[1]:find("bad", 1, true), "unvalidated package reached the shell")
assert(snap:find("123", 1, true))
assert(D.capture(instances[1], instances, snap, 1000))
local saved = files["data/launch_android.log"]
assert(saved:find("am_kill", 1, true) and saved:find("lmkd", 1, true))
assert(not saved:find(secret, 1, true) and not saved:find("cookie12345", 1, true))
assert(not saved:find("unrelated data", 1, true))
assert(saved:find("123", 1, true), "pre-launch PID mapping lost")
mode = "fail"
assert(D.capture(instances[1], instances, snap, 1000))
assert(files["data/launch_android.log"]:find("Logcat gagal/tidak diizinkan", 1, true))
for _ = 1, 100 do D.capture(instances[1], instances, snap, 1000) end
assert(#files["data/launch_android.log"] <= 24000, "diagnostic history grew unbounded")

-- Report includes saved evidence and applies its final redaction too.
package.loaded["managers.instance"] = { getAll = function() return {} end }
package.loaded["managers.webhook"] = {}
package.loaded["managers.heartbeat"] = {}
package.loaded["managers.auth"] = {}
package.loaded["managers.username"] = {}
io.popen = function() return { read = function() return "" end, close = function() return true end } end
local Report = require("managers.report")
local report = Report.build()
assert(report:find("Android saat proses peer hilang", 1, true))
assert(report:find("Logcat gagal/tidak diizinkan", 1, true))
print("PASS: bounded Android diagnostics, package validation, redaction, logcat failure and report inclusion")
