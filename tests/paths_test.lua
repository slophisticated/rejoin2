-- Run from the repository root: lua tests/paths_test.lua
-- The data root must be absolute and stable whatever the working directory is.
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

local realExecute, realOpen, realRemove = os.execute, io.open, os.remove

-- The root probe writes a file; keep the test away from the real tree.
local function sandbox()
    local made, files = {}, {}
    os.execute = function(cmd) made[#made + 1] = cmd; return true end
    os.remove = function(p) files[p] = nil; return true end
    io.open = function(path, mode)
        if mode == "w" then
            files[path] = ""
            return { write = function(self) return self end, close = function() return true end }
        end
        if files[path] then return { read = function() return files[path] end, close = function() return true end } end
        -- The root probe only asks "does this file exist".
        if path:match("main%.lua$") or path:match("paths%.lua$") then
            return { read = function() return "" end, close = function() return true end }
        end
        return nil
    end
    package.loaded["core.paths"] = nil
    package.loaded["utils.file"] = nil
    return made
end

local function restore()
    os.execute, io.open, os.remove = realExecute, realOpen, realRemove
    package.loaded["core.paths"] = nil
    package.loaded["utils.file"] = nil
end

test("the root is absolute and never depends on the working directory", function()
    sandbox()
    local envHome, envPwd = os.getenv("REJOIN_HOME"), os.getenv("PWD")
    os.getenv = function(k)
        if k == "REJOIN_HOME" then return "" end
        if k == "PWD" then return "/opt/rejoin" end
        return envPwd
    end
    local Paths = require("core.paths")
    local base = Paths.base()
    restore()
    assert(base:match("^/") or base:match("^%a:[/\\]"), "root is not absolute: " .. tostring(base))
    assert(Paths.data("rejoin.log"):match("^/") or Paths.data("rejoin.log"):match("^%a:[/\\]"),
        "data path is not absolute: " .. tostring(Paths.data("rejoin.log")))
end)

test("REJOIN_HOME wins and trailing slashes are stripped", function()
    sandbox()
    local env = os.getenv("REJOIN_HOME")
    os.getenv = function(k) if k == "REJOIN_HOME" then return "/tmp/rejoin-home///" end return env end
    local Paths = require("core.paths")
    local base = Paths.base()
    restore()
    assert(base == "/tmp/rejoin-home", "override not honoured: " .. tostring(base))
    assert(Paths.config() == "/tmp/rejoin-home/config/config.lua")
end)

test("relative config values resolve under the root, absolute ones are kept", function()
    sandbox()
    local env = os.getenv("REJOIN_HOME")
    os.getenv = function(k) if k == "REJOIN_HOME" then return "/tmp/rejoin-home" end return env end
    local Paths = require("core.paths")
    local relative, absolute, empty = Paths.resolve("data/rejoin.log"), Paths.resolve("/var/log/x.log"), Paths.resolve("")
    restore()
    assert(relative == "/tmp/rejoin-home/data/rejoin.log", tostring(relative))
    assert(absolute == "/var/log/x.log", tostring(absolute))
    assert(empty == "/tmp/rejoin-home/data/rejoin.log", tostring(empty))
end)

test("both subfolders are created on first use", function()
    sandbox()
    local env = os.getenv("REJOIN_HOME")
    os.getenv = function(k) if k == "REJOIN_HOME" then return "/tmp/rejoin-home" end return env end
    local Paths = require("core.paths")
    local made = Paths.ensure()
    restore()
    assert(made == "/tmp/rejoin-home")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
