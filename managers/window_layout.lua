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
--       enabled = false,   -- off by default
--       columns = 0,       -- 0 = automatic (2 columns for 2-4 clones, 3 for 5-9, ...)
--       gap = 0,           -- pixels between windows
--       offsetTop = 0,     -- pixels kept free at the top of the screen
--       screenWidth = 0,   -- 0 = detect from the current display
--       screenHeight = 0,
--   }
--   Per instance: window = { left = 0, top = 0, right = 640, bottom = 360 } overrides
--   the grid for that clone.
--
-- Best-effort: any failure is logged and the launch continues as normal.

local WindowLayout = {}

local KEYS = { "left", "top", "right", "bottom" }
local KEY_PREFIX = "app_cloner_current_window_"

local screenCache = nil

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

-- Current display size in its current orientation (e.g. 1280x720 in landscape).
local function screenSize(wl)
    local w, h = tonumber(wl.screenWidth), tonumber(wl.screenHeight)
    if w and h and w > 0 and h > 0 then return w, h end
    if screenCache then return screenCache[1], screenCache[2] end
    local ok, out = Shell.exec("dumpsys window displays")
    if ok and out then
        local cw, ch = out:match("cur=(%d+)x(%d+)")
        if cw then
            screenCache = { tonumber(cw), tonumber(ch) }
            return screenCache[1], screenCache[2]
        end
    end
    ok, out = Shell.exec("wm size")
    local pw, ph = (out or ""):match("(%d+)x(%d+)")
    if pw then
        -- No orientation info: the floating clones run in landscape.
        local a, b = tonumber(pw), tonumber(ph)
        screenCache = { math.max(a, b), math.min(a, b) }
        return screenCache[1], screenCache[2]
    end
    return nil
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

    local file = "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
    local tmp = "/data/local/tmp/rejoin_window_" .. pkg .. ".xml"
    local script = table.concat({
        "f=" .. shQuote(file) .. "; t=" .. shQuote(tmp),
        '[ -f "$f" ] || exit 3',
        "sed " .. table.concat(sedArgs, " ") .. ' "$f" > "$t" || exit 4',
        'grep -q "' .. KEY_PREFIX .. 'left" "$t" || { rm -f "$t"; exit 5; }',
        'cat "$t" > "$f"; rc=$?; rm -f "$t"; exit $rc',
    }, "\n")
    -- Shell.exec prefixes `timeout`; run the compound script as one command.
    local ok, out, code = Shell.exec("sh -c " .. shQuote(script))
    if not ok then
        local reason = code == 3 and "prefs file not found (open the clone once first)"
            or ("write failed (code " .. tostring(code) .. ") " .. tostring(out or ""))
        Logger.warn("WindowLayout[" .. pkg .. "]: " .. reason)
        return false, reason
    end
    Logger.info(string.format("WindowLayout[%s]: window #%d/%d -> left=%d top=%d right=%d bottom=%d",
        pkg, index or 1, count or 1, b.left, b.top, b.right, b.bottom))
    return true
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
