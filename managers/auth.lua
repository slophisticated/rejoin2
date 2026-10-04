local Logger = require("core.logger")
local Shell = require("utils.shell")

-- Auth / account-login detection.
--
-- Roblox (incl. Lite/Floating mod clones) stores its session cookie as a
-- `.ROBLOSECURITY` token somewhere under the app's data directory. For a stock
-- install that is the WebView cookie DB at
--   /data/data/<package>/app_webview/Default/Cookies   (a SQLite file)
-- but modded/"Lite" clones can keep it in a different place (databases, shared_prefs,
-- app_flutter, ...). Rather than pin one path, we SCAN the clone's data directory
-- recursively (root) for the token.
--
-- A clone that has NEVER been logged in has no `.ROBLOSECURITY` token anywhere, so we
-- can tell "not logged in" apart from "force-close stub". When `isLoggedIn == false`
-- the monitor/recovery must NEVER force-relaunch the clone (low RSS is expected while
-- sitting on the login screen).
--
-- Returns:
--   true  -> an account is logged in (a session token is present)
--   false -> definitely NOT logged in (no token found anywhere under the data dir)
--   nil   -> could not determine (e.g. root read failed). Callers fall back to the
--            restart-safe behavior (treat as logged in / relaunch normally).
--
-- The scan is cached per instance for a short TTL so we do not grep every monitor cycle.
-- `cookiePath`, if set on an instance, overrides the base directory to scan.

local Auth = {}

-- Cache: pkg -> { result, at }  (result one of true/false/nil)
local cache = {}
local TTL = 30 -- seconds

-- Resolved sqlite3 runner: nil = not probed yet, false = none available.
local sqliteRunner = nil

-- WebKit stores expiry as microseconds since 1601-01-01.
local WEBKIT_EPOCH_OFFSET = 11644473600

local function defaultBaseDir(pkg)
    return "/data/data/" .. pkg
end

local function baseDir(instance)
    if instance and instance.cookiePath and instance.cookiePath ~= "" then
        return instance.cookiePath
    end
    if instance and instance.package then
        return defaultBaseDir(instance.package)
    end
    return nil
end

-- Public helper: the base directory under which this instance's session data lives
-- (honours the per-instance `cookiePath` override). Shared with cookie_injector so the
-- injection targets the exact same location the login scan uses.
function Auth.getBaseDir(instance)
    return baseDir(instance)
end

-- Files that may contain the token text without being a live session: our own
-- Cookies DB backups (`Cookies.bak-<stamp>`) and SQLite rollback journals. Counting
-- them made a logged-out clone read as logged in forever, so the monitor kept
-- force-stopping and relaunching it.
local function isStaleCopy(path)
    return path:find(".bak-", 1, true) ~= nil or path:sub(-8) == "-journal"
end

-- Authoritative check: ask SQLite whether any Cookies DB under `base` holds a live,
-- non-empty .ROBLOSECURITY row. Logging out deletes the row, but its bytes can stay in
-- the DB file, so grepping the raw file is not enough. Returns true/false, or nil when
-- there is no Cookies DB or sqlite3 is unavailable (caller falls back to grep).
local function sessionInCookieDb(base)
    local okReq, CookieInjector = pcall(require, "managers.cookie_injector")
    if not okReq then return nil end
    local dbs = CookieInjector.locateCookieDbs(base)
    if not dbs or #dbs == 0 then return nil end
    if sqliteRunner == nil then
        sqliteRunner = CookieInjector.resolveSqlite3(dbs[1]) or false
    end
    if not sqliteRunner then return nil end

    local now = string.format("%.0f", (os.time() + WEBKIT_EPOCH_OFFSET) * 1000000)
    local answered = false
    for _, db in ipairs(dbs) do
        local quoted = "'" .. db:gsub("'", "'\\''") .. "'"
        local sql = "SELECT COUNT(*) FROM cookies WHERE name='.ROBLOSECURITY'"
            .. " AND length(value) > 0 AND (expires_utc = 0 OR expires_utc > " .. now .. ");"
        local called, succeeded, out = pcall(function()
            return Shell.exec(sqliteRunner .. " " .. quoted .. " \"" .. sql .. "\"")
        end)
        local n = called and succeeded and tonumber((out or ""):match("^%s*(%d+)%s*$"))
        if n then
            answered = true
            if n > 0 then return true end
        end
    end
    if answered then return false end
    return nil
end

-- Cookie DB files (main DB plus its WAL/SHM), already read row-by-row via SQLite.
local function isCookieDb(path)
    return path:match("/Cookies$") ~= nil or path:match("/Cookies%-wal$") ~= nil
        or path:match("/Cookies%-shm$") ~= nil
end

-- Grep recursively (as root) for the token under `base`. Returns the matching file
-- paths (newline separated, "" = none), or nil if the probe itself failed. Stale copies
-- are always skipped; `skipCookieDbs` also skips Cookies DBs that SQLite already
-- answered for, so only other session stores (modded clones) count.
local function countToken(base, skipCookieDbs)
    -- `grep -a -r -l` prints the file paths that contain the token; `-l` means we only
    -- get file names (one per line) so the count is the number of files with the token.
    local quoted = "'" .. base:gsub("'", "'\\''") .. "'"
    local cmd = string.format("grep -a -r -l '.ROBLOSECURITY' %s 2>/dev/null", quoted)
    -- Shell.exec returns (ok, output); pcall returns (true, ok, output) so capture the
    -- THIRD value (the actual output string), not the second (Shell's ok boolean).
    local called, succeeded, out, code = pcall(function() return Shell.exec(cmd) end)
    if not called or not out or out == "(dry-run)" then return nil end
    if not succeeded then
        if code == 1 then return "" end -- grep found no match
        return nil -- unreadable directory or other grep failure
    end
    -- Empty output = no matches found (dir exists and was scanned OK). We cannot tell a
    -- truly empty result from "grep failed" via output alone, so first verify the base
    -- dir is readable; if it is, empty means "no session".
    local live = {}
    for line in out:gmatch("[^\r\n]+") do
        if not isStaleCopy(line) and not (skipCookieDbs and isCookieDb(line)) then
            live[#live + 1] = line
        end
    end
    return table.concat(live, "\n")
end

local function baseDirExists(base)
    local quoted = "'" .. base:gsub("'", "'\\''") .. "'"
    local cmd = string.format("[ -d %s ] && echo AE_DIR || echo AE_NODIR", quoted)
    -- See countToken: capture the THIRD pcall value (the output string).
    local called, succeeded, out = pcall(function() return Shell.exec(cmd) end)
    if not called or not succeeded or not out or out == "(dry-run)" then return nil end
    if out:find("AE_DIR", 1, true) then return true end
    if out:find("AE_NODIR", 1, true) then return false end
    return nil
end

function Auth.isLoggedIn(instance)
    local pkg = instance and instance.package
    if not pkg then return nil end
    local base = baseDir(instance)
    if not base then return nil end

    -- Cache check.
    local cached = cache[pkg]
    local now = os.time()
    if cached and now - cached.at < TTL then
        return cached.result
    end

    local result
    do
        local exists = baseDirExists(base)
        if exists == false then
            -- Data dir does not exist => the app has never stored anything => not logged in.
            result = false
        elseif exists == nil then
            -- Could not even probe the dir => indeterminate.
            result = nil
        else
            result = sessionInCookieDb(base)
        end
        -- Modded/Lite clones may keep the session outside the WebView Cookies DB, so a
        -- "no row" answer is still cross-checked against the rest of the data dir.
        if exists and result ~= true then
            local hits = countToken(base, result == false)
            if hits ~= nil then
                result = hits ~= ""
            end
        end
    end

    -- A probe that fails once (e.g. a slow grep hitting the shell timeout) must not
    -- flip a known logged-out clone back to "unknown", which callers treat as
    -- logged in and recover. Keep the last definite answer until a new one arrives.
    if result == nil and cached and cached.result ~= nil then
        result = cached.result
    end

    cache[pkg] = { result = result, at = now }
    Logger.debug(string.format("Auth.isLoggedIn(%s): base=%s -> %s", pkg, base, tostring(result)))
    return result
end

-- Clear the cache (e.g. after a login/logout or on monitor start).
function Auth.resetCache()
    cache = {}
end

return Auth
