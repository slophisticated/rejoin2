local Logger = require("core.logger")
local Shell = require("utils.shell")

local APKManager = {}

local function validPackageName(packageName)
    return type(packageName) == "string"
        and packageName:match("^[%a_][%w_%.]*$") ~= nil
end

local function packageArg(packageName)
    return "'" .. packageName:gsub("'", "'\\''") .. "'"
end

-- Android stops processes at package scope. If config maps multiple logical clones
-- to the same package, there is no safe way to stop just one of them, so fail closed.
local function packageIsUnique(packageName)
    local ok, Instances = pcall(require, "managers.instance")
    if not ok or type(Instances.getAll) ~= "function" then return true end
    local matches = 0
    for _, inst in ipairs(Instances.getAll() or {}) do
        if type(inst) == "table" and inst.package == packageName then matches = matches + 1 end
    end
    return matches <= 1
end

-- Resolve the default launchable activity component for a package (best-effort).
-- Returns the component string like "com.roblox.client/.Activity" or nil on failure.
function APKManager.resolveLaunchComponent(packageName)
    if not validPackageName(packageName) then return nil end
    -- cmd package resolve-activity --brief returns the package/activity component on the last line
    local cmd = string.format("cmd package resolve-activity --brief %s", packageArg(packageName))
    local ok, out = Shell.exec(cmd)
    if ok and out then
        for line in out:gmatch("[^\r\n]+") do
            local comp = line:match("(%S+%/%S+)")
            if comp then
                return comp
            end
        end
    end
    return nil
end

-- Launch an APK by package name for Termux/Android.
--
-- Order of attempts:
--   1) `am start -a MAIN -c LAUNCHER -p <pkg>`  -- targets the package explicitly and
--      starts its own task/launcher activity. Works for cloned apps (each clone is a
--      distinct package) and does NOT depend on `cmd package resolve-activity`, which is
--      often unavailable in a Termux (non-adb, non-root) shell.
--   2) `monkey -p <pkg> -c LAUNCHER 1`          -- legacy fallback.
--   3) resolve-activity + `am start -n <component>` -- best-effort fallback.
--
-- Returns (success, output_or_err).
function APKManager.launch(packageName)
    if not validPackageName(packageName) then return false, "invalid_package" end
    Logger.info("APKManager: launching package: " .. tostring(packageName))
    APKManager.invalidateSnapshot()

    -- 1) Primary: am start MAIN/LAUNCHER targeting the package explicitly.
    local pkgArg = packageArg(packageName)
    local cmd = string.format("am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p %s", pkgArg)
    Logger.info("APKManager: exec: " .. cmd)
    local ok, out = Shell.exec(cmd)
    local failedHint = { "Error", "Failure", "Exception", "does not exist", "is not allowed", "Activity not started" }
    local failed = false
    if ok and out then
        for _, h in ipairs(failedHint) do
            if out:find(h, 1, true) then failed = true break end
        end
        if not failed then
            Logger.info("APKManager: am start accepted for " .. tostring(packageName))
            APKManager.invalidateSnapshot()
            return true, out
        end
    else
        failed = true
    end
    Logger.warn("APKManager: am start launch failed/not accepted for " .. tostring(packageName) .. ": " .. tostring(out))

    -- 2) Fallback: monkey launches the main activity of a package by name (no component needed)
    cmd = string.format("monkey -p %s -c android.intent.category.LAUNCHER 1", pkgArg)
    Logger.info("APKManager: fallback exec: " .. cmd)
    ok, out = Shell.exec(cmd)
    if ok and out then
        -- monkey exits 0 even on some errors; only treat as success on injected events
        if out:find("Events injected", 1, true) then
            Logger.info("APKManager: monkey launch injected events for " .. tostring(packageName))
            APKManager.invalidateSnapshot()
            return true, out
        end
        Logger.warn("APKManager: monkey reported an error for " .. tostring(packageName) .. ": " .. tostring(out))
    else
        Logger.warn("APKManager: monkey launch failed/empty for " .. tostring(packageName))
    end

    -- 3) Fallback: resolve the launchable activity then `am start` (best-effort)
    local component = APKManager.resolveLaunchComponent(packageName)
    if component then
        Logger.info("APKManager: fallback resolved launch component: " .. tostring(component))
        local ok2, out2 = Shell.exec(string.format("am start -n %s", component))
        if ok2 and out2 and out2:find("Error", 1, true) == nil then
            APKManager.invalidateSnapshot()
            return true, out2
        end
        Logger.warn("APKManager: fallback am start failed for " .. tostring(packageName) .. ": " .. tostring(out2))
    end

    return false, out
end

function APKManager.forceStop(packageName)
    if not validPackageName(packageName) then return false, "invalid_package" end
    if not packageIsUnique(packageName) then
        return false, "package dipakai lebih dari satu instance; force-stop dibatalkan agar clone lain tidak ikut tertutup"
    end
    Logger.info("APKManager: force stopping: " .. tostring(packageName))
    -- Limit the stop to the current Android user and one validated package name.
    local cmd = string.format("am force-stop --user current %s", packageArg(packageName))
    local ok, out = Shell.exec(cmd)
    APKManager.invalidateSnapshot()
    return ok, out
end

-- Escape regex metacharacters so a package name is matched literally in a POSIX ERE
-- (as consumed by `pgrep -f`). Produces `\.` etc. (backslash-dot), NOT `%.` (percent-dot).
local function escapeRegex(s)
    return s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "\\%1")
end

-- ---------------------------------------------------------------------------
-- Process snapshot: ONE `ps -A` per monitor cycle instead of one per probe.
--
-- isRunning, isActive and getRSSinKB are each called once per instance per cycle, and
-- every one of them used to shell out (pidof / pgrep / ps -A). With four clones that
-- added up to ~20 `su` spawns per cycle. The snapshot parses `ps -A` once and is then
-- reused by all probes in the same cycle.
--
-- It is invalidated explicitly after launch / force-stop / recovery (see
-- APKManager.invalidateSnapshot) and also expires after SNAPSHOT_TTL, so a stale list
-- can never outlive a process change we did not initiate.
-- ---------------------------------------------------------------------------
local SNAPSHOT_TTL = 1.5 -- seconds
local snapshot = nil

local function parseSnapshot(out)
    local byName, order = {}, {}
    for line in out:gmatch("[^\r\n]+") do
        local fields = {}
        for f in line:gmatch("%S+") do fields[#fields + 1] = f end
        if #fields >= 9 then
            local name = fields[#fields]
            if name ~= "" then
                byName[name] = { name = name, pid = fields[2], rssKb = tonumber(fields[5]) or -1 }
                order[#order + 1] = name
            end
        end
    end
    return { byName = byName, order = order, at = os.time() }
end

-- Cached process list, refreshed when older than SNAPSHOT_TTL.
-- Returns nil when `ps -A` cannot be read; callers then use their own fallback probe.
function APKManager.snapshot()
    if snapshot and (os.time() - snapshot.at) < SNAPSHOT_TTL then
        return snapshot
    end
    local ok, out = Shell.exec("ps -A")
    if not ok or not out or out == "(dry-run)" then
        snapshot = nil
        return nil
    end
    snapshot = parseSnapshot(out)
    return snapshot
end

-- Drop the cached process list. Call after anything that changes the process table so
-- the next probe in the same cycle reads fresh data.
function APKManager.invalidateSnapshot()
    snapshot = nil
end

-- Check whether a package has a running process. A clone's MAIN process runs under its
-- own exact package name (e.g. com.apengjers.v3), so we match that name EXACTLY — NOT
-- sub-processes like `com.apengjers.v3:p0` (background services that keep running after
-- the UI is swiped away, which previously left `isRunning` true -> status stuck at "ingame"
-- -> the closed app was never recovered/open again).
-- Returns true if any method finds a matching process, false otherwise.
function APKManager.isRunning(packageName)
    if not packageName or packageName == "" then return false end
    local pkg = packageName:gsub("['\" ]", "")
    if pkg == "" then return false end

    -- 1) Snapshot: one `ps -A` shared by every probe in this cycle.
    local snap = APKManager.snapshot()
    if snap and next(snap.byName) ~= nil then
        return snap.byName[pkg] ~= nil
    end

    -- 2) Snapshot unavailable (restricted shell / unreadable ps) -> probe directly.
    -- pidof: exact process-name match; busybox sometimes missing it.
    local ok, out = Shell.exec(string.format("pidof %s", pkg))
    if ok and out and out ~= "" and out ~= "(dry-run)" then
        return true
    end

    -- pgrep -f with a pattern matching this clone's exact process command
    local pattern = "^" .. escapeRegex(pkg) .. "$"
    ok, out = Shell.exec(string.format("pgrep -f '%s'", pattern))
    if ok and out and out ~= "" and out ~= "(dry-run)" then
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- RSS/memory-based "active" detection.
--
-- On this device `dumpsys activity`/`dumpsys window` does NOT list the floating-window
-- clones at all (even when fully running), so UI visibility can't be used. The signal
-- that actually separates a running clone from a force-close stub is resident memory:
--    * running clone    ~1 GB    (RSS from `ps -A`, kB)
--    * force-close stub ~188 MB   (observed when the floating window was closed)
--    * earliest running example seen ~235 MB (older build)
-- So we treat a clone as ACTIVE only when its process exists AND its RSS is at or above
-- a threshold (config.minRss, default 300 MB). A low-RSS stub therefore reads as
-- "not active" -> recovery relaunches it.
--
-- getRSSinKB(pkg): RSS in kilobytes from `ps -A`, or -1 if no process / not parseable.
-- isActive(pkg):  process exists AND RSS >= threshold. Returns boolean.
-- ---------------------------------------------------------------------------

local function rssThreshold()
    local ok, cfg = pcall(require, "core.config")
    if ok and cfg then
        local g = cfg.get and cfg.get() or {}
        local v = tonumber(g and g.minRss)
        if v and v > 0 then return v * 1024 end -- config stored in MB -> kB
    end
    return 300 * 1024 -- default 300 MB (in kB)
end

function APKManager.getRSSinKB(packageName)
    if not packageName or packageName == "" then return -1 end
    local pkg = packageName:gsub("['\" ]", "")
    if pkg == "" then return -1 end
    local snap = APKManager.snapshot()
    if snap and next(snap.byName) ~= nil then
        local entry = snap.byName[pkg]
        if entry then return entry.rssKb end
        return -1
    end

    -- Snapshot unavailable -> read `ps -A` directly.
    local ok, out = Shell.exec("ps -A")
    if not ok or not out or out == "(dry-run)" then return -1 end
    for line in out:gmatch("[^\r\n]+") do
        local fields = {}
        for f in line:gmatch("%S+") do fields[#fields + 1] = f end
        if #fields >= 9 and fields[#fields] == pkg then
            local rss = tonumber(fields[5])
            if rss then return rss end
            return -1
        end
    end
    return -1
end

-- Does the package have a window on screen? A force-closed clone can leave a stub
-- process alive with no window at all. Window lines in `dumpsys window windows` look
-- like "Window{a1b2c3 u0 com.pkg/com.pkg.Activity}" (or "... u0 com.pkg}" for a
-- floating window titled with the package).
-- Returns true / false, or nil when the dump could not be read (caller: don't guess).
function APKManager.hasWindow(packageName)
    if not packageName or packageName == "" then return nil end
    local pkg = packageName:gsub("['\" ]", "")
    local ok, out = Shell.exec("dumpsys window windows")
    if not ok or not out or out == "" or out == "(dry-run)" then return nil end
    if not out:find("Window{", 1, true) then return nil end
    local esc = pkg:gsub("%p", "%%%0")
    for line in out:gmatch("[^\r\n]+") do
        if line:find("Window{", 1, true) and line:match(" u%d+ " .. esc .. "[/}%s]") then
            return true
        end
    end
    return false
end

function APKManager.isActive(packageName)
    if not packageName or packageName == "" then return false end
    if not APKManager.isRunning(packageName) then return false end
    local rss = APKManager.getRSSinKB(packageName)
    if rss < 0 then return false end
    return rss >= rssThreshold()
end


-- Used by "Launch All" to detect how many clones have actually come up: every Roblox
-- clone runs a process named `com.roblox.client`, so waiting for the count to reach the
-- number of clones launched gives a reliable per-launch progress signal even when the
-- per-package process name differs from the package (App Cloner renames packages only).
-- Returns a number (>= 0). In dry-run returns 1 (as if one process is running).
function APKManager.countProcess(name)
    if not name or name == "" then return 0 end

    -- 1) Snapshot: count the exact process plus its `name:sub` services.
    local snap = APKManager.snapshot()
    if snap and next(snap.byName) ~= nil then
        local n = 0
        for _, entryName in ipairs(snap.order) do
            if entryName == name or entryName:sub(1, #name + 1) == name .. ":" then
                n = n + 1
            end
        end
        return n
    end

    -- 2) Snapshot unavailable -> probe directly.
    -- pgrep -f <name>: one PID per line; count non-empty lines (works on busybox).
    local ok, out = Shell.exec(string.format("pgrep -f %s", name))
    if ok and out and out == "(dry-run)" then
        return 1
    end
    if ok and out and out ~= "" then
        local n = 0
        for _ in (out.."\n"):gmatch("[^\r\n]+") do
            n = n + 1
        end
        return n
    end

    -- pidof <name>: a space-separated list of PIDs; count tokens.
    ok, out = Shell.exec(string.format("pidof %s", name))
    if ok and out and out ~= "" and out ~= "(dry-run)" then
        local n = 0
        for _ in (out.." "):gmatch("%S+") do
            n = n + 1
        end
        return n
    end

    return 0
end

-- Count how many of the given packages currently have a running process.
-- Used by "Launch All" to decide when each launched clone is actually up, so it can
-- move on to the next one. Unlike countProcess (which matches a single base name),
-- this matches each clone's own package name, which is more accurate because every
-- App Cloner clone keeps its own process name (e.g. com.apengjers.v3).
function APKManager.countRunning(packages)
    if not packages then return 0 end
    local n = 0
    for _, pkg in ipairs(packages) do
        if APKManager.isRunning(pkg) then
            n = n + 1
        end
    end
    return n
end

return APKManager
