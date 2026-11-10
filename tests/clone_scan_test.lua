-- Run from the repository root: lua tests/clone_scan_test.lua
-- Clone detection must survive a user-scoped package list, and a config copied from
-- another device must be repointed instead of being reported as all-missing.
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
        print("PASS: " .. name)
    else
        failed = failed + 1
        print("FAIL: " .. name .. "\n" .. tostring(err))
    end
end

local function stub(name, value) package.loaded[name] = value end
local noop = function() end
stub("core.logger", { info = noop, warn = noop, error = noop, debug = noop })
stub("managers.apk", { resolveLaunchComponent = function(pkg)
    if pkg:match("^com%.apengjers%.") then return pkg .. "/com.roblox.client.Activity" end
end })

-- Shell stub: each command maps to canned output; nil = command fails.
local outputs = {}
local function shell(out)
    outputs = out or {}
    stub("utils.shell", {
        exec = function(cmd)
            local value = outputs[cmd]
            if value == nil then return false, "" end
            return true, value
        end,
    })
    package.loaded["managers.clone_scan"] = nil
    return require("managers.clone_scan")
end

local function fresh() package.loaded["managers.clone_scan"] = nil; return require("managers.clone_scan") end

test("the package-manager fallback finds renamed clones", function()
    -- `pm list packages` alone shows nothing (user-scoped); /data/data does.
    local Scan = shell({
        ["pm list packages"] = "",
        ["cmd package list packages"] = "package:com.roblox.client\npackage:com.apengjers.v3\npackage:com.apengjers.v4\npackage:com.termux\n",
    })
    local list = Scan.scanClones("")
    table.sort(list)
    assert(#list == 3, "expected 3 clones, got " .. tostring(#list))
    assert(list[1] == "com.apengjers.v3" and list[3] == "com.roblox.client")
end)

test("a renamed clone is recognised by its Roblox launcher component", function()
    local Scan = shell({
        ["pm list packages"] = "package:com.mystery.app\npackage:com.termux\n",
        ["cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER"] =
            "com.mystery.app/com.roblox.client.Activity\ncom.termux/com.termux.app.TermuxActivity\n",
    })
    local list = Scan.scanClones("")
    assert(#list == 1 and list[1] == "com.mystery.app", table.concat(list, ","))
end)

test("the prefix filter picks up clones whose name says nothing", function()
    local Scan = shell({
        ["pm list packages"] = "package:com.apengjers.v5\npackage:com.termux\n",
    })
    local list = Scan.scanClones("com.apengjers.")
    assert(#list == 1 and list[1] == "com.apengjers.v5")
end)

test("every probe failing is reported as unknown, not as nothing installed", function()
    local Scan = shell({})
    assert(Scan.listInstalled() == nil)
    local list, err = Scan.scanClones("")
    assert(list == nil and err == "detection_failed")
end)

test("leftover data alone does not count as installed", function()
    local Scan = shell({ ["pm list packages"] = "package:com.termux\n" })
    local installed = Scan.listInstalled()
    outputs["dumpsys package com.apengjers.v3"] = "Packages:\n  Package [com.apengjers.v3] (abc):"
    assert(Scan.isInstalled("com.apengjers.v3", installed) == false)
    assert(Scan.isInstalled("com.gone.app", installed) == false)
end)

test("a config from another device is repointed at clones that exist here", function()
    local Scan = shell({
        ["pm list packages"] = "package:com.apengjers.v3\npackage:com.apengjers.v4\n",
    })
    local conf = { instances = {
        { id = 1, package = "com.other.v3", cookiePath = "/old/Cookies", usernamePath = "/old/user" },
        { id = 2, package = "com.other.v4" },
    } }
    local results = Scan.fix(conf)
    assert(results[1].kind == "fix" and results[2].kind == "fix")
    assert(conf.instances[1].package == "com.apengjers.v3")
    assert(conf.instances[1].cookiePath == nil and conf.instances[1].usernamePath == nil)
    assert(conf.instances[2].package == "com.apengjers.v4")
end)

test("an installed package is left alone and the same clone is not handed out twice", function()
    local Scan = shell({
        ["pm list packages"] = "package:com.apengjers.v3\npackage:com.apengjers.v4\n",
    })
    local conf = { instances = {
        { id = 1, package = "com.apengjers.v3" },
        { id = 2, package = "com.other.v4" },
        { id = 3, package = "com.other.v5" },
    } }
    local results = Scan.fix(conf)
    assert(results[1].kind == "ok")
    assert(conf.instances[2].package == "com.apengjers.v4")
    -- only one free clone existed, so the third has nothing left
    assert(results[3].kind == "missing")
end)

test("same prefix family wins over an unrelated clone", function()
    local Scan = shell({
        ["pm list packages"] = "package:com.apengjers.v6\npackage:com.roblox.client\n",
    })
    local conf = { instances = { { id = 1, package = "com.apengjers.v3" } } }
    local results = Scan.fix(conf)
    assert(results[1].kind == "fix" and conf.instances[1].package == "com.apengjers.v6")
end)

test("nothing free means missing, and detection failure means no blind fix", function()
    local Scan = shell({ ["pm list packages"] = "package:com.termux\n" })
    local conf = { instances = { { id = 1, package = "com.other.v3" } } }
    assert(Scan.fix(conf)[1].kind == "missing")
    assert(conf.instances[1].package == "com.other.v3")

    local Broken = shell({})
    local conf2 = { instances = { { id = 1, package = "com.other.v3" } } }
    local results, err = Broken.fix(conf2)
    assert(results == nil and err == "detection_failed")
    assert(conf2.instances[1].package == "com.other.v3")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
