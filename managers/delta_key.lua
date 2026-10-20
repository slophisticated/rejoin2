local Paths = require("core.paths")
local Logger = require("core.logger")
local Config = require("core.config")
local File = require("utils.file")
local Shell = require("utils.shell")

-- Resolve Delta's license destination and store a user-supplied key there.
--
-- Config (optional): deltaLicensePath = "" -- "" = find it automatically.
-- The path found once is remembered in data/delta_license_path.txt so later manual
-- key input uses the same Delta folder.

local DeltaKey = {}

local REMEMBER = Paths.data("delta_license_path.txt")
local DEFAULT_LICENSE = "/sdcard/Delta/Internals/Cache/license"
local cached = nil

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function deltaDir()
    local ok, c = pcall(Config.get)
    c = ok and type(c) == "table" and c or {}
    local ae = type(c.appAutoExecutePath) == "string" and c.appAutoExecutePath:gsub("/+$", "") or ""
    if ae == "" then return nil, c end
    return (ae:match("^(.*)/[^/]+$") or ae), c
end

local function rememberPath(path)
    cached = path
    if File.read(REMEMBER) ~= path then File.write(REMEMBER, path .. "\n") end
    return path
end

-- Path of the license entry, or nil when it was never seen.
function DeltaKey.path()
    local dir, c = deltaDir()
    local forced = type(c.deltaLicensePath) == "string" and c.deltaLicensePath:gsub("%s+$", "") or ""
    if forced ~= "" then return forced end
    if cached then return cached end

    -- Delta's shared-storage layout uses this exact case-sensitive folder. Prefer it
    -- over stale remembered paths from older builds when the Cache directory exists.
    local base = dir or "/sdcard/Delta"
    local cacheDir = base .. "/Internals/Cache"
    local cacheOk = Shell.exec("ls -a " .. q(cacheDir) .. " 2>/dev/null")
    if cacheOk then return rememberPath(cacheDir .. "/license") end

    local remembered = (File.read(REMEMBER) or ""):gsub("%s+$", "")
    if remembered ~= "" then
        cached = remembered
        return cached
    end
    if dir then
        local ok, out = Shell.exec("ls -a " .. q(dir) .. " 2>/dev/null")
        for name in tostring(ok and out or ""):gmatch("[^\r\n]+") do
            if name:lower():find("license", 1, true) then
                local path = rememberPath(dir .. "/" .. name)
                Logger.info("[KEY] file license Delta: " .. path)
                return path
            end
        end
    end
    return nil
end

-- Store a user-supplied Delta key in Delta's own license entry. This only accepts
-- manual input; it never obtains, derives, or validates a key. Keep the key out of
-- logs and config, and write it directly so it is not exposed in a shell command.
function DeltaKey.input(key)
    if type(key) ~= "string" then return false, "key tidak valid" end
    key = key:gsub("^%s+", ""):gsub("%s+$", "")
    if #key < 1 or #key > 256 or key:find("[%c%s]") then
        return false, "format key tidak valid (1–256 karakter tanpa spasi)"
    end

    -- Reuse the exact path detected/remembered; this Delta build stores
    -- its license beside data/ui in Internals/Cache.
    local path = DeltaKey.path() or DEFAULT_LICENSE
    local dir = path:match("^(.*)/[^/]+$")
    if not dir or dir == "" or path:find("[%c]") then return false, "path license Delta tidak valid" end
    -- Create the shared-storage folder as Termux, so the following Lua file write
    -- keeps the same owner instead of leaving a root-owned cache directory.
    local made = os.execute("mkdir -p " .. q(dir) .. " 2>/dev/null")
    if made ~= true and made ~= 0 then return false, "folder cache Delta tidak bisa dibuat" end

    local f = io.open(path, "w")
    if not f then return false, "file license Delta tidak bisa ditulis" end
    local wrote = f:write(key)
    local flushed = f:flush()
    local closed = f:close()
    if not wrote or not flushed or not closed then return false, "gagal menyimpan key ke file license Delta" end

    local saved = File.read(path)
    if saved ~= key then return false, "verifikasi file license Delta gagal" end
    cached = path
    File.write(REMEMBER, path .. "\n")
    Logger.info("[KEY] input key Delta tersimpan di file license")
    return true, "key Delta tersimpan di " .. path
end

return DeltaKey
