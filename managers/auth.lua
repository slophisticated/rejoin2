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
-- ---------------------------------------------------------------------------
-- Remote check: the token found on disk is sent to Roblox
-- (users.roblox.com/v1/users/authenticated) with curl. A token Roblox rejects
-- (HTTP 401: logged out, kicked, or revoked) means the clone is NOT logged in even
-- though a cookie row still exists. Results are cached per clone for
-- `loginVerifyInterval` seconds (default 600) so Roblox is not hit every cycle.
-- Set `loginVerifyRemote = false` in config to turn it off. The token is never logged.
-- ---------------------------------------------------------------------------
local remote = {} -- pkg -> { result, at, code, name }
local curlBin = nil -- nil = not probed yet, false = none

local function confValue(key)
    local ok, conf = pcall(function() return require("core.config").get() end)
    if not ok or type(conf) ~= "table" then return nil end
    return conf[key]
end

local function shellOut(cmd)
    local called, succeeded, out = pcall(function() return Shell.exec(cmd) end)
    if not called or not succeeded or not out or out == "(dry-run)" then return nil end
    return out
end

local function resolveCurl()
    if curlBin ~= nil then return curlBin end
    curlBin = false
    for _, c in ipairs({ "/data/data/com.termux/files/usr/bin/curl", "/system/bin/curl" }) do
        local out = shellOut("[ -x '" .. c .. "' ] && echo AE_YES || echo AE_NO")
        if out and out:find("AE_YES", 1, true) then curlBin = c; break end
    end
    return curlBin
end

local function validTokenText(t)
    return t and #t >= 20 and #t <= 2048 and not t:find("[%s'\"\\]") and t or nil
end

-- Read the live token: newest non-empty cookie row first, then a grep over the data
-- dir that skips our backups.
local function readToken(base)
    if sqliteRunner then
        local okReq, CookieInjector = pcall(require, "managers.cookie_injector")
        local dbs = okReq and CookieInjector.locateCookieDbs(base) or nil
        for _, db in ipairs(dbs or {}) do
            local quoted = "'" .. db:gsub("'", "'\\''") .. "'"
            local out = shellOut(sqliteRunner .. " " .. quoted
                .. " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY' AND length(value) > 0"
                .. " ORDER BY last_access_utc DESC LIMIT 1;\"")
            local tok = validTokenText(out and out:match("^%s*(.-)%s*$"))
            if tok then return tok, "cookie_db" end
        end
    end
    local quoted = "'" .. base:gsub("'", "'\\''") .. "'"
    -- Token shape: _|WARNING:-DO-NOT-SHARE-THIS.--...-items.|_<base64-ish session>
    local out = shellOut("grep -a -r -h -o -E '_[|]WARNING:-DO-NOT-SHARE[A-Za-z.-]*[|]_[A-Za-z0-9+/=_-]{20,}' --exclude='*.bak-*' "
        .. quoted .. " 2>/dev/null | head -1")
    local tok = validTokenText(out and out:match("^%s*(.-)%s*$"))
    if tok then return tok, "grep" end
    return nil, "not_found"
end

-- Returns true (Roblox accepts the token), false (Roblox rejects it), or nil when it
-- could not be checked (no token, no curl, no network, unexpected answer).
local function remoteCheck(pkg, base)
    if confValue("loginVerifyRemote") == false then return nil end
    local ttl = tonumber(confValue("loginVerifyInterval")) or 600
    local now = os.time()
    local token, source = readToken(base)
    -- Re-check right away when the token changed (e.g. the user logged in again).
    local c = remote[pkg]
    if c and c.token == token and now - c.at < ttl then return c.result end

    local result, code, name, note = nil, nil, nil, nil
    local bin = resolveCurl()
    if not token then
        note = "token tidak ketemu (" .. source .. ")"
    elseif not bin then
        note = "curl tidak ada (pkg install curl)"
    else
        local out = shellOut(string.format(
            "%s -s --max-time 8 -w '\n%%{http_code}' -H 'Cookie: .ROBLOSECURITY=%s' https://users.roblox.com/v1/users/authenticated",
            bin, token))
        local body, codeStr = (out or ""):match("^(.-)\n?(%d%d%d)$")
        code = tonumber(codeStr)
        if code == 200 and body and body:find('"id"', 1, true) then
            result = true
            name = body:match('"name"%s*:%s*"([^"]*)"')
        elseif code == 401 then
            result = false
        end
        note = string.format("token=%s len=%d http=%s", source, #token, tostring(code or "gagal"))
    end

    remote[pkg] = { result = result, at = now, code = code, name = name, token = token }
    Logger.info(string.format("[LOGIN] %s verifikasi Roblox: %s -> %s%s", pkg, note,
        result == nil and "tidak pasti (pakai hasil lokal)" or (result and "VALID" or "DITOLAK (dianggap logout)"),
        name and (" user=" .. name) or ""))
    return result
end

-- Username from the last successful remote check (lets Username skip its own call).
function Auth.remoteName(pkg)
    local c = remote[pkg]
    if c and c.result == true then return c.name end
    return nil
end

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

    local result, dbResult
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
            dbResult = result
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

    -- A token on disk is not proof of a session: ask Roblox whether it still accepts it.
    local remoteResult = nil
    if result == true then
        remoteResult = remoteCheck(pkg, base)
        if remoteResult == false then result = false end
    end

    if not cached or cached.result ~= result then
        Logger.info(string.format("[LOGIN] %s login = %s (cookie db = %s, roblox = %s)",
            pkg, tostring(result), tostring(dbResult), tostring(remoteResult)))
    end
    cache[pkg] = { result = result, at = now }
    Logger.debug(string.format("Auth.isLoggedIn(%s): base=%s -> %s", pkg, base, tostring(result)))
    return result
end

-- Clear the cache (e.g. after a login/logout or on monitor start).
function Auth.resetCache()
    cache = {}
    remote = {}
end

return Auth
