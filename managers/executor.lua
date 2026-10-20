local Logger = require("core.logger")
local Config = require("core.config")
local Shell = require("utils.shell")

-- Which executor's folders rejoin uses.
--
-- Everything executor-related follows appAutoExecutePath: the heartbeat script goes in
-- it, its Workspace / Scripts siblings are found next to it, and the Delta license
-- check looks in its parent. Executors other than Delta keep that folder elsewhere and
-- name it differently (/sdcard/<Executor>/autoexec, AutoExec, ...).
--
-- Automatic, so the user never has to open Termux: every autoexec folder on /sdcard
-- gets the heartbeat script (Heartbeat.install), so whichever executor runs writes
-- heartbeats into its own Workspace. The executor whose heartbeat is newest is the one
-- in use; the monitor re-checks every few minutes. No heartbeat anywhere yet: keep the
-- configured folder when it exists, else the one with the newest Workspace file.
-- Main Menu 10 -> 10 still picks one by hand.

local Executor = {}

local AUTOEXEC_NAMES = { "autoexecute", "autoexec", "auto-execute", "auto-exec", "auto_execute", "auto_exec" }
local warned = false
local STALE = 300 -- the current executor's heartbeat older than this = not in use
Executor.found = {} -- the latest scan, for Heartbeat.install

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
    Executor.found = list
    return list
end

-- Newest mtime per candidate (0 = none): of its rejoin heartbeat files, or with
-- anyFile of any file in its Workspace. One root call for all candidates.
local function newest(list, anyFile)
    local lines = {}
    for i, e in ipairs(list) do
        local parent = e.path:match("^(.*)/[^/]+$") or e.path
        local files = anyFile
            and ("find " .. q(parent) .. "/[Ww]orkspace -maxdepth 2 -type f -exec stat -c %Y {} + 2>/dev/null")
            or ("stat -c %Y " .. q(parent) .. "/[Ww]orkspace/rejoin/hb_*.txt 2>/dev/null")
        lines[#lines + 1] = "echo \"" .. i .. ":$(" .. files .. " | sort -n | tail -1)\""
    end
    local ok, out = Shell.exec("sh -c " .. q(table.concat(lines, "; ")))
    local times = {}
    for i, t in tostring(ok and out or ""):gmatch("(%d+):(%d*)") do times[tonumber(i)] = tonumber(t) or 0 end
    return times
end

-- With `fresh`, only times within STALE count (old leftovers never win).
local function pickNewest(list, times, fresh)
    local best, bestTime = nil, 0
    for i, e in ipairs(list) do
        local t = times[i] or 0
        if t > bestTime and (not fresh or os.time() - t < STALE) then best, bestTime = e, t end
    end
    return best
end

-- Save `path` as the autoexec folder (the executor in use).
function Executor.use(path)
    local conf = Config.get() or {}
    conf.appAutoExecutePath = path
    local ok, err = Config.save(conf)
    if ok then Logger.info("[EXECUTOR] pakai " .. Executor.name(path) .. ": " .. path) end
    return ok, err
end

-- Point appAutoExecutePath at the executor in use (see the top of this file).
-- Returns the path in use (nil when none) and whether it was changed.
function Executor.ensure()
    local conf = Config.get() or {}
    local current = type(conf.appAutoExecutePath) == "string" and conf.appAutoExecutePath:gsub("/+$", "") or ""
    local list = Executor.scan()
    if #list == 0 then
        if not warned then
            warned = true
            Logger.warn("[EXECUTOR] folder autoexec executor ga ketemu di /sdcard; buka executor-nya sekali")
        end
        return current ~= "" and current or nil, false
    end
    warned = false
    local why = "heartbeat terbaru"
    local pick
    if #list > 1 then
        local times = newest(list, false)
        pick = pickNewest(list, times, true)
        -- Stay while the current executor still reports (a recent heartbeat), so a
        -- choice made in the menu is not undone by another executor's leftovers.
        for i, e in ipairs(list) do
            if e.path == current and os.time() - (times[i] or 0) < STALE then pick = nil end
        end
    end
    if not pick then
        local currentOk = current ~= "" and isDir(current)
        if currentOk then return current, false end
        if #list == 1 then
            pick, why = list[1], "satu-satunya executor"
        else
            pick, why = pickNewest(list, newest(list, true)) or list[1], "Workspace paling baru dipakai"
        end
    end
    if pick.path == current then return current, false end
    Logger.info(string.format("[EXECUTOR] pindah ke %s (%s): %s", pick.name, why, pick.path))
    Executor.use(pick.path)
    return pick.path, true
end

return Executor
