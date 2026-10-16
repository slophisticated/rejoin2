local Logger = require("core.logger")
local Config = require("core.config")
local File = require("utils.file")
local Shell = require("utils.shell")

-- Is Delta's key still there?
--
-- Delta's shared license file is /sdcard/delta/internal/cache/license. When it is
-- removed, every clone shows the key screen again, so this is one device-wide status.
--
-- Config can override deltaLicensePath. The standard Delta path is used by default.
-- The path found once is remembered in data/delta_license_path.txt, so a key that is
-- already gone when the engine starts (e.g. after a reboot) is still noticed.

local DeltaKey = {}

local REMEMBER = "data/delta_license_path.txt"
local DEFAULT_LICENSE_PATH = "/sdcard/delta/internal/cache/license"
local cached = nil
local warnedMissing = false

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function deltaDir()
    local ok, c = pcall(Config.get)
    c = ok and type(c) == "table" and c or {}
    local ae = type(c.appAutoExecutePath) == "string" and c.appAutoExecutePath:gsub("/+$", "") or ""
    if ae == "" then return nil, c end
    return (ae:match("^(.*)/[^/]+$") or ae), c
end

-- Path of the license entry, or nil when it was never seen.
function DeltaKey.path()
    local _, c = deltaDir()
    local forced = type(c.deltaLicensePath) == "string" and c.deltaLicensePath:gsub("%s+$", "") or ""
    if forced ~= "" then return forced end
    if cached then return cached end
    local remembered = (File.read(REMEMBER) or ""):gsub("%s+$", "")
    if remembered ~= "" and remembered:lower():find("/delta/internal/cache/license", 1, true) then
        cached = remembered
        return cached
    end
    cached = DEFAULT_LICENSE_PATH
    if not warnedMissing then
        warnedMissing = true
        Logger.info("[KEY] memantau file license Delta: " .. cached)
    end
    return cached
end

-- true = key there (non-empty file, or folder with something in it), false = gone or
-- empty, nil = unknown (no path known / Delta folder unreadable).
function DeltaKey.present()
    local p = DeltaKey.path()
    if not p then return nil end
    local dir = p:match("^(.*)/[^/]+$") or "/"
    local cmd = "if [ -d " .. q(p) .. " ]; then [ -n \"$(ls -A " .. q(p) .. " 2>/dev/null)\" ] && echo KEY_YES || echo KEY_NO; "
        .. "elif [ -s " .. q(p) .. " ]; then echo KEY_YES; "
        .. "elif [ -d " .. q(dir or "/") .. " ]; then echo KEY_NO; else echo KEY_UNKNOWN; fi"
    -- Shell.exec prefixes a timeout, so a compound command needs its own sh -c.
    local ok, out = Shell.exec("sh -c " .. q(cmd))
    out = ok and out or ""
    if out:find("KEY_YES", 1, true) then return true end
    if out:find("KEY_NO", 1, true) then return false end
    return nil
end

return DeltaKey
