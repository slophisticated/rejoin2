local Logger = require("core.logger")
local Config = require("core.config")
local Shell = require("utils.shell")

-- Which executor's folders rejoin uses.
--
-- Everything executor-related follows appAutoExecutePath: the heartbeat script goes in
-- it, its Workspace / Scripts siblings are found next to it, and the Delta license
-- check looks in its parent. Executors other than Delta keep that folder elsewhere and
-- name it differently (/sdcard/<Executor>/autoexec, AutoExec, ...). When the configured
-- folder does not exist, look for one on /sdcard: exactly one found = use it (saved to
-- the config), several = the user picks one in Main Menu 10.

local Executor = {}

local AUTOEXEC_NAMES = { "autoexecute", "autoexec", "auto-execute", "auto-exec", "auto_execute", "auto_exec" }
local warned = false

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function isDir(path)
    local ok, out = Shell.exec("sh -c " .. q("[ -d " .. q(path) .. " ] && echo IS_DIR"))
    return ok and tostring(out):find("IS_DIR", 1, true) ~= nil
end

-- Executor name shown to the user: the folder holding the autoexec folder.
function Executor.name(path)
    path = tostring(path or ""):gsub("/+$", "")
    local parent = path:match("^(.*)/[^/]+$") or path
    return parent:match("([^/]+)$") or parent
end

-- Every autoexec folder up to /sdcard/<a>/<b>/<autoexec>, sorted by executor name.
-- Returns { { name = "Delta", path = "/sdcard/Delta/Autoexecute" }, ... }.
function Executor.scan()
    local tests = {}
    for _, n in ipairs(AUTOEXEC_NAMES) do tests[#tests + 1] = "-iname " .. q(n) end
    local cmd = "find /sdcard/ -maxdepth 3 -type d \\( " .. table.concat(tests, " -o ") .. " \\) 2>/dev/null"
    local ok, out = Shell.exec("sh -c " .. q(cmd))
    local list, seen = {}, {}
    for line in tostring(ok and out or ""):gmatch("[^\r\n]+") do
        local path = line:gsub("/+$", ""):gsub("^/sdcard//", "/sdcard/")
        -- App data and Termux's own storage links are never an executor's folder.
        if path:match("^/sdcard/") and not path:find("/Android/", 1, true) and not seen[path] then
            seen[path] = true
            list[#list + 1] = { name = Executor.name(path), path = path }
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

-- Save `path` as the autoexec folder (the executor in use).
function Executor.use(path)
    local conf = Config.get() or {}
    conf.appAutoExecutePath = path
    local ok, err = Config.save(conf)
    if ok then Logger.info("[EXECUTOR] pakai " .. Executor.name(path) .. ": " .. path) end
    return ok, err
end

-- Make sure appAutoExecutePath points at an existing folder. Returns the path in use
-- (nil when none could be chosen) and whether it was changed.
function Executor.ensure()
    local conf = Config.get() or {}
    local current = type(conf.appAutoExecutePath) == "string" and conf.appAutoExecutePath:gsub("/+$", "") or ""
    if current ~= "" and isDir(current) then return current, false end
    local list = Executor.scan()
    if #list == 1 then
        Logger.info("[EXECUTOR] folder " .. (current ~= "" and current or "autoexec") .. " ga ada; ketemu "
            .. list[1].name .. " (" .. list[1].path .. ")")
        Executor.use(list[1].path)
        return list[1].path, true
    end
    if not warned then
        warned = true
        if #list == 0 then
            Logger.warn("[EXECUTOR] folder autoexec ga ketemu (" .. tostring(current) .. "); buka executor sekali, lalu Menu 10 -> executor")
        else
            local names = {}
            for _, e in ipairs(list) do names[#names + 1] = e.name end
            Logger.warn("[EXECUTOR] ada " .. #list .. " executor (" .. table.concat(names, ", ") .. "); pilih di Menu 10 -> executor")
        end
    end
    return nil, false
end

return Executor
