local Logger = require("core.logger")
local Config = require("core.config")
local File = require("utils.file")
local Shell = require("utils.shell")

-- Is Delta's key still there?
--
-- Delta keeps its key in an entry named like "license" inside its folder (the parent
-- of appAutoExecutePath, e.g. /sdcard/Delta). When the key runs out the entry is gone
-- and every clone shows the key screen again. The folder is shared by all clones, so
-- this is one status for the whole device.
--
-- Newer Delta builds keep it in <Delta>/internal/cache/license, which is checked too.
--
-- Config (optional): deltaLicensePath = "" -- "" = find it automatically.
-- The path found once is remembered in data/delta_license_path.txt, so a key that is
-- already gone when the engine starts (e.g. after a reboot) is still noticed.

local DeltaKey = {}

local REMEMBER = "data/delta_license_path.txt"
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
    local dir, c = deltaDir()
    local forced = type(c.deltaLicensePath) == "string" and c.deltaLicensePath:gsub("%s+$", "") or ""
    if forced ~= "" then return forced end
    if cached then return cached end
    for _, where in ipairs(dir and { dir, dir .. "/internal/cache" } or {}) do
        local ok, out = Shell.exec("ls -a " .. q(where) .. " 2>/dev/null")
        for name in tostring(ok and out or ""):gmatch("[^\r\n]+") do
            if name:lower():find("license", 1, true) then
                cached = where .. "/" .. name
                if File.read(REMEMBER) ~= cached then
                    File.write(REMEMBER, cached)
                    Logger.info("[KEY] file license Delta: " .. cached)
                end
                return cached
            end
        end
    end
    local remembered = (File.read(REMEMBER) or ""):gsub("%s+$", "")
    if remembered ~= "" then
        cached = remembered
        return cached
    end
    if not warnedMissing then
        warnedMissing = true
        Logger.info("[KEY] file license Delta belum ditemukan di " .. tostring(dir) .. " (cek key dilewati)")
    end
    return nil
end

-- true = key there (non-empty file, or folder with something in it), false = gone or
-- empty, nil = unknown (no path known / Delta folder unreadable).
function DeltaKey.present()
    local dir = deltaDir()
    local p = DeltaKey.path()
    if not p then return nil end
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

-- Save a key the user got from Delta themselves into Delta's license file. Manual input
-- only: nothing here obtains, derives or checks a key. The key never goes to the log,
-- the config or a shell command line (written with Lua as the Termux user).
-- Goes to the license file found before, else <Delta>/internal/cache/license.
function DeltaKey.input(key)
    if type(key) ~= "string" then return false, "key tidak valid" end
    key = key:gsub("^%s+", ""):gsub("%s+$", "")
    if #key < 1 or #key > 256 or key:find("[%c%s]") then
        return false, "format key tidak valid (1-256 karakter tanpa spasi)"
    end
    local dir = deltaDir() or "/sdcard/Delta"
    local path = DeltaKey.path() or (dir .. "/internal/cache/license")
    if path:find("%c") then return false, "path license Delta tidak valid" end
    local okD, isDir = Shell.exec("sh -c " .. q("[ -d " .. q(path) .. " ] && echo IS_DIR"))
    if okD and tostring(isDir):find("IS_DIR", 1, true) then
        return false, "license Delta di device ini berupa folder (" .. path .. "); masukkan key lewat Delta"
    end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then return false, "path license Delta tidak valid" end
    -- Created as the Termux user (not su), like the file itself.
    os.execute("mkdir -p " .. q(parent) .. " 2>/dev/null")
    local f = io.open(path, "w")
    if not f then
        return false, "file license Delta tidak bisa ditulis (izin storage Termux? jalankan termux-setup-storage)"
    end
    local wrote = f:write(key)
    local closed = f:close()
    if not wrote or not closed or File.read(path) ~= key then
        return false, "gagal menyimpan key ke file license Delta"
    end
    cached = path
    File.write(REMEMBER, path)
    Logger.info("[KEY] key Delta dimasukkan manual ke " .. path)
    return true, "key Delta tersimpan di " .. path .. "; buka ulang Delta kalau layar key belum hilang"
end

return DeltaKey
