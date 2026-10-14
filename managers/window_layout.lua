local Logger = require("core.logger")
local Shell = require("utils.shell")
local Config = require("core.config")

-- Arranges the clones' floating windows in a grid.
--
-- The App Cloner floating window keeps its bounds in
--   /data/data/<pkg>/shared_prefs/<pkg>_preferences.xml
-- as app_cloner_current_window_{left,top,right,bottom} (pixels). We rewrite those
-- four values ONLY while the clone is force-stopped (right before it is launched), so
-- the window opens where we want it and the running app never fights our write.
--
-- Config (all optional):
--   windowLayout = {
--       enabled = true,    -- on in the shipped config; installer turns it on
--       columns = 0,       -- 0 = automatic (2 columns for 2-4 clones, 3 for 5-9, ...)
--       gap = 0,           -- pixels between windows
--       offsetTop = 0,     -- pixels kept free at the top of the screen
--       screenWidth = 0,   -- 0 = detect from the current display
--       screenHeight = 0,
--       orientation = "landscape", -- grid in landscape even if the display reads
--                                  -- portrait (e.g. right after boot); "auto" = as read
--   }
--   Per instance: window = { left = 0, top = 0, right = 640, bottom = 360 } overrides
--   the grid for that clone.
--
-- Best-effort: any failure is logged and the launch continues as normal.
--
-- Validation: after every write the four values are read back, and while a clone runs
-- WindowLayout.verify() compares the bounds the app reports in its prefs with the grid.
-- A window found out of place is only reported; it is put back on the clone's next
-- launch (recovery / relaunch / boot), never by restarting a running game.

local WindowLayout = {}

local KEYS = { "left", "top", "right", "bottom" }
local KEY_PREFIX = "app_cloner_current_window_"

local screenCache = nil      -- { w, h, at }
local SCREEN_TTL = 30
local TOLERANCE = 10          -- pixels the app may adjust a window by
local lastVerify = {}         -- pkg -> { ok, at, actual, target }

local function layoutConf()
    local ok, conf = pcall(Config.get)
    conf = ok and type(conf) == "table" and conf or {}
    local wl = type(conf.windowLayout) == "table" and conf.windowLayout or {}
    return wl, conf
end

function WindowLayout.isEnabled()
    local wl = layoutConf()
    return wl.enabled == true
end

local function validPackage(pkg)
    return type(pkg) == "string" and pkg:match("^[%a_][%w_%.]*$") ~= nil
end

local function shQuote(v)
    return "'" .. tostring(v):gsub("'", "'\\''") .. "'"
end

-- Display size for the grid. Re-read every SCREEN_TTL seconds (never cached for the
-- whole run: a read taken while the display was still portrait right after boot would
-- otherwise skew every window until the engine restarts). The floating clones run in
-- landscape, so the long side is the width unless orientation = "auto".
local function screenSize(wl)
    local w, h = tonumber(wl.screenWidth), tonumber(wl.screenHeight)
    if w and h and w > 0 and h > 0 then return w, h end
    local now = os.time()
    if screenCache and now - screenCache[3] < SCREEN_TTL then
        return screenCache[1], screenCache[2]
    end
    local a, b
    local ok, out = Shell.exec("dumpsys window displays")
    if ok and out then
        local cw, ch = out:match("cur=(%d+)x(%d+)")
        a, b = tonumber(cw), tonumber(ch)
    end
    if not a then
        ok, out = Shell.exec("wm size")
        local pw, ph = (out or ""):match("(%d+)x(%d+)")
        a, b = tonumber(pw), tonumber(ph)
    end
    if not a or not b then return nil end
    if wl.orientation ~= "auto" then
        a, b = math.max(a, b), math.min(a, b)
    end
    screenCache = { a, b, now }
    return a, b
end

local function prefsFile(pkg)
    return "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
end

-- The four window values currently stored in the clone's prefs, or nil.
local function readBounds(pkg)
    local ok, out = Shell.exec("cat " .. shQuote(prefsFile(pkg)) .. " 2>/dev/null")
    if not ok or not out or out == "" or out == "(dry-run)" then return nil end
    local b = {}
    for _, k in ipairs(KEYS) do
        local v = out:match('<int name="' .. KEY_PREFIX .. k .. '" value="(%-?%d+)"')
        b[k] = tonumber(v)
        if not b[k] then return nil end
    end
    return b
end
WindowLayout.readBounds = readBounds

local function sameBounds(a, b)
    if not a or not b then return false end
    for _, k in ipairs(KEYS) do
        if math.abs((a[k] or 0) - (b[k] or 0)) > TOLERANCE then return false end
    end
    return true
end

local function fmt(b)
    if not b then return "?" end
    return string.format("%d,%d,%d,%d", b.left, b.top, b.right, b.bottom)
end
WindowLayout.formatBounds = fmt

-- `am force-stop` returns before every process of the package is gone, and a dying
-- app can still flush its old window bounds. Wait until it is really stopped.
local function waitStopped(pkg)
    local okA, APK = pcall(require, "managers.apk")
    if not okA then return true end
    local okT, Timer = pcall(require, "utils.timer")
    for attempt = 1, 4 do
        local okR, running = pcall(APK.isRunning, pkg)
        if okR and not running then return true end
        if attempt == 3 then Shell.exec("am force-stop " .. pkg) end
        if okT then Timer.sleep(1) end
    end
    local okR, running = pcall(APK.isRunning, pkg)
    return okR and not running
end

-- Bounds for the clone at 1-based position `index` out of `count`.
function WindowLayout.boundsFor(instance, index, count)
    local wl = layoutConf()
    local o = type(instance) == "table" and instance.window or nil
    if type(o) == "table" then
        local b = {}
        for _, k in ipairs(KEYS) do
            b[k] = tonumber(o[k])
            if not b[k] then return nil, "window." .. k .. " missing" end
        end
        return b
    end

    local sw, sh = screenSize(wl)
    if not sw then return nil, "screen size unknown" end
    count = math.max(1, count or 1)
    local cols = math.floor(tonumber(wl.columns) or 0)
    if cols < 1 then cols = math.ceil(math.sqrt(count)) end
    local rows = math.ceil(count / cols)
    local gap = math.max(0, math.floor(tonumber(wl.gap) or 0))
    local top0 = math.max(0, math.floor(tonumber(wl.offsetTop) or 0))

    local cellW = math.floor((sw - gap * (cols - 1)) / cols)
    local cellH = math.floor((sh - top0 - gap * (rows - 1)) / rows)
    if cellW < 50 or cellH < 50 then return nil, "grid too small" end

    local i = index - 1
    local col, row = i % cols, math.floor(i / cols)
    local left = col * (cellW + gap)
    local top = top0 + row * (cellH + gap)
    return { left = left, top = top, right = left + cellW, bottom = top + cellH }
end

-- Write the bounds into the clone's prefs. Call only while the clone is stopped.
function WindowLayout.apply(instance, index, count)
    if not WindowLayout.isEnabled() then return false, "disabled" end
    local pkg = instance and instance.package
    if not validPackage(pkg) then return false, "invalid_package" end

    local b, err = WindowLayout.boundsFor(instance, index, count)
    if not b then
        Logger.warn("WindowLayout[" .. pkg .. "]: " .. tostring(err))
        return false, err
    end
    if not waitStopped(pkg) then
        Logger.warn("WindowLayout[" .. pkg .. "]: app masih jalan, posisi tidak ditulis")
        return false, "still running"
    end

    -- Drop any existing entries for the four keys, then add fresh ones before </map>.
    -- The result is written back with `cat >` so the file keeps its inode, owner,
    -- permissions and SELinux label (the app must still be able to read/write it).
    local sedArgs, entries = {}, {}
    for _, k in ipairs(KEYS) do
        local name = KEY_PREFIX .. k
        sedArgs[#sedArgs + 1] = "-e " .. shQuote("s#<int name=\"" .. name .. "\" value=\"[^\"]*\" */>##g")
        entries[#entries + 1] = string.format('<int name="%s" value="%d" />', name, b[k])
    end
    sedArgs[#sedArgs + 1] = "-e " .. shQuote("s#</map>#" .. table.concat(entries) .. "</map>#")
    sedArgs[#sedArgs + 1] = "-e " .. shQuote("/^[[:space:]]*$/d")

    -- Android loads <file>.bak instead of the file when a previous write was cut off,
    -- so a leftover backup gets the same edit.
    --
    -- A clone that was never opened has no prefs file yet (common on a fresh device):
    -- create an empty one with the same owner, mode and SELinux label as the app's data
    -- directory, so the app can read and write it like its own, then edit it as usual.
    local file = prefsFile(pkg)
    local tmp = "/data/local/tmp/rejoin_window_" .. pkg .. ".xml"
    local script = table.concat({
        "f=" .. shQuote(file) .. "; t=" .. shQuote(tmp),
        "d=" .. shQuote("/data/data/" .. pkg) .. '; sp="$d/shared_prefs"',
        'if [ ! -f "$f" ]; then',
        '  [ -d "$d" ] || exit 3',
        '  own=$(stat -c "%u:%g" "$d") || exit 6',
        '  ctx=$(ls -Zd "$d" 2>/dev/null | awk \'{print $1}\')',
        '  if [ ! -d "$sp" ]; then mkdir "$sp" && chown "$own" "$sp" && chmod 771 "$sp" || exit 6; fi',
        '  printf "%s\\n%s\\n%s\\n" "<?xml version=\'1.0\' encoding=\'utf-8\' standalone=\'yes\' ?>" "<map>" "</map>" > "$f" || exit 6',
        '  chown "$own" "$f" && chmod 660 "$f" || exit 6',
        '  case "$ctx" in *:*) chcon "$ctx" "$sp" "$f" 2>/dev/null ;; esac',
        '  echo CREATED',
        'fi',
        "edit() {",
        "  sed " .. table.concat(sedArgs, " ") .. ' "$1" > "$t" || return 4',
        '  grep -q "' .. KEY_PREFIX .. 'left" "$t" || { rm -f "$t"; return 5; }',
        '  cat "$t" > "$1"; rc=$?; rm -f "$t"; return $rc',
        "}",
        'edit "$f" || exit $?',
        'if [ -f "$f.bak" ]; then edit "$f.bak" || exit $?; fi',
        "exit 0",
    }, "\n")
    -- Shell.exec prefixes `timeout`; run the compound script as one command.
    local ok, out, code = Shell.exec("sh -c " .. shQuote(script))
    if not ok then
        local reason = code == 3 and "app data folder not found (clone not installed?)"
            or code == 6 and "could not create prefs file"
            or ("write failed (code " .. tostring(code) .. ") " .. tostring(out or ""))
        Logger.warn("WindowLayout[" .. pkg .. "]: " .. reason)
        return false, reason
    end
    if out and out:find("CREATED", 1, true) then
        Logger.info("WindowLayout[" .. pkg .. "]: file setting jendela dibuat (clone belum pernah dibuka)")
    end
    local stored = readBounds(pkg)
    if not sameBounds(stored, b) then
        Logger.warn(string.format("[WINDOW] %s: tulis %s tapi terbaca %s", pkg, fmt(b), fmt(stored)))
        return false, "read-back mismatch"
    end
    Logger.info(string.format("WindowLayout[%s]: window #%d/%d -> left=%d top=%d right=%d bottom=%d",
        pkg, index or 1, count or 1, b.left, b.top, b.right, b.bottom))
    lastVerify[pkg] = nil
    return true
end

-- Compare the bounds the running app keeps in its prefs with this clone's grid slot.
-- Returns true | false, actual, target | nil (feature off, or nothing to compare yet).
function WindowLayout.verify(instance)
    if not WindowLayout.isEnabled() then return nil end
    local pkg = instance and instance.package
    if not validPackage(pkg) then return nil end
    local index, count = WindowLayout.slotOf(instance)
    local target = WindowLayout.boundsFor(instance, index, count)
    local actual = readBounds(pkg)
    if not target or not actual then return nil end
    local ok = sameBounds(actual, target)
    lastVerify[pkg] = { ok = ok, at = os.time(), actual = actual, target = target }
    if ok then return true end
    return false, actual, target
end

-- Last verify() result for the dashboard (no I/O).
function WindowLayout.lastVerify(pkg)
    return lastVerify[pkg]
end

-- Position of `instance` in the configured list (by package), and the list size.
function WindowLayout.slotOf(instance)
    local _, conf = layoutConf()
    local list = type(conf.instances) == "table" and conf.instances or {}
    local count, index = 0, nil
    for _, inst in ipairs(list) do
        count = count + 1
        if type(inst) == "table" and inst.package == (instance and instance.package) then
            index = index or count
        end
    end
    return index or 1, math.max(count, 1)
end

-- Convenience for callers: apply for this instance at its configured slot. Never throws.
function WindowLayout.applyForInstance(instance)
    if not WindowLayout.isEnabled() then return false end
    local okCall, ok = pcall(function()
        local index, count = WindowLayout.slotOf(instance)
        return WindowLayout.apply(instance, index, count)
    end)
    if not okCall then
        Logger.warn("WindowLayout: error " .. tostring(ok))
        return false
    end
    return ok
end

return WindowLayout
