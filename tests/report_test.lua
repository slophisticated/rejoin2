-- Run from the repository root: lua tests/report_test.lua
local conf = { remote = { secret = "secret-for-report" } }
package.loaded["core.config"] = { get = function() return conf end }
package.loaded["utils.file"] = { read = function() return nil end }
package.loaded["managers.instance"] = { getAll = function()
    return { { id = 4, package = "com.apengjers.v6" } }
end }
package.loaded["managers.webhook"] = {}
package.loaded["managers.heartbeat"] = {}
package.loaded["managers.auth"] = {}
package.loaded["managers.username"] = {}
io.popen = function() return nil end
local success, output = true, ""
package.loaded["utils.shell"] = { exec = function(cmd)
    assert(cmd == "logcat -b events -d -v threadtime -t 2000", "unexpected device action")
    return success, output
end }
local Report = require("managers.report")
local function event(tag, pkg, message)
    return "10-29 00:46:00.000 850 879 I " .. tag .. " : [0,123," .. pkg .. "," .. message .. "]"
end
output = table.concat({ event("am_kill", "com.apengjers.v6", "stop secret-for-report"),
    event("am_proc_died", "com.apengjers.v6", "died"),
    event("am_proc_start", "com.apengjers.v6", "start"),
    event("am_anr", "com.apengjers.v6", "anr"),
    event("am_crash", "com.apengjers.v6", "crash"),
    event("am_kill", "com.apengjers.v60", "wrong-prefix"),
    event("am_kill", "other.com.apengjers.v6", "wrong-suffix"),
    event("am_other", "com.apengjers.v6", "wrong-tag") }, "\n")
local report = Report.build()
for _, tag in ipairs({ "am_kill", "am_proc_died", "am_proc_start", "am_anr", "am_crash" }) do
    assert(report:find(tag, 1, true), "missing " .. tag)
end
assert(not report:find("wrong-", 1, true))
assert(not report:find("secret-for-report", 1, true))
assert(report:find("stop [secret]", 1, true))
local many = {}
for i = 1, 100 do many[i] = event("am_proc_start", "com.apengjers.v6", "event-" .. i .. "-end") end
output = table.concat(many, "\n")
report = Report.build()
assert(not report:find("event-20-end", 1, true))
assert(report:find("event-21-end", 1, true) and report:find("event-100-end", 1, true))
output = ""
assert(Report.build():find("Tidak ada event proses clone", 1, true))
success, output = false, "raw error must not leak"
report = Report.build()
assert(report:find("Gagal membaca event Android", 1, true))
assert(not report:find(output, 1, true))
print("PASS: report live Android events filter exact clones/tags, limit history, redact secrets and distinguish failure/empty")
