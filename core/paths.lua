local File = require("utils.file")

-- Single source of truth for where the engine keeps its state.
--
-- Everything the tool owns lives under one root so a user can back it up, read
-- it or wipe it from one folder:
--
--   /sdcard/yanamin/config/config.lua      configuration
--   /sdcard/yanamin/data/rejoin.log        engine log
--   /sdcard/yanamin/data/launch.log        per-cycle launch/monitor diagnostics
--   /sdcard/yanamin/data/monitor.pid       monitor lock
--   /sdcard/yanamin/data/username_scan.log username resolution log
--   /sdcard/yanamin/data/boot.log          Termux:Boot log
--   /sdcard/yanamin/data/yanamin_wrapper.sh  embedded terminal supervisor
--
-- Nothing outside this root is ever written (clone app data, AutoExecute
-- scripts and the Termux:Boot script live elsewhere on purpose).
--
-- Override the root with the YANAMIN_HOME environment variable (debugging).
--
-- IMPORTANT: directories are created with a plain `mkdir -p` (os.execute), NOT
-- through utils.shell — that one runs commands as root via `su -c`, which would
-- leave root-owned files that Termux can no longer write.

local Paths = {}

local DEFAULT_ROOT = "/sdcard/yanamin"
local STORAGE_HINT = "Jalankan:  termux-setup-storage  (beri izin storage), lalu ulangi."

local root = nil
local migrated = false

local function shellQuote(s)
    return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

local function mkdirp(path)
    if not path or path == "" then return end
    pcall(function() os.execute("mkdir -p " .. shellQuote(path)) end)
end

-- Can we actually create files here? Used to hard-stop early with a clear
-- message instead of failing later in a dozen places.
local function writable(path)
    local probe = path .. "/.yanamin_write_test"
    local f = io.open(probe, "w")
    if not f then return false end
    f:write("ok")
    f:close()
    os.remove(probe)
    return true
end

local function stripTrailingSlash(p)
    local out = tostring(p or ""):gsub("/+$", "")
    if out == "" then return "/" end
    return out
end

local function hardStop(candidate)
    io.stdout:write("\n[yanamin] Folder data " .. candidate .. " tidak bisa ditulis.\n")
    io.stdout:write("[yanamin] " .. STORAGE_HINT .. "\n\n")
    io.stdout:flush()
    os.exit(1)
end

-- Move anything the engine owned in the old working directory (before the data
-- root existed) into the new root, so upgrading does not look like a wipe.
local function migrateLegacy(cwd)
    if migrated then return false end
    migrated = true

    if not cwd or cwd == "" or cwd == root then return false end
    -- Skip when the two paths are related (cwd is the root, sits inside it, or
    -- contains it) — those config/data folders are not ours to move.
    if cwd:sub(1, #root + 1) == root .. "/" or root:sub(1, #cwd + 1) == cwd .. "/" then
        return false
    end

    local moved = {}
    local function mv(src, dst)
        os.execute("mv -f " .. shellQuote(src) .. " " .. shellQuote(dst) .. " 2>/dev/null")
        if not File.exists(src) then
            table.insert(moved, src .. " -> " .. dst)
        end
    end

    local configPath = root .. "/config/config.lua"
    local templatePath = root .. "/config/template.lua"
    local dataDir = root .. "/data"

    if not File.exists(configPath) then
        local legacyConf = cwd .. "/config/config.lua"
        local legacyTpl = cwd .. "/config/template.lua"
        if File.exists(legacyConf) then mv(legacyConf, configPath) end
        if File.exists(legacyTpl) then mv(legacyTpl, templatePath) end
    end

    local legacyData = cwd .. "/data"
    local names = File.listDir(legacyData)
    if names then
        for _, name in ipairs(names) do
            local dst = dataDir .. "/" .. name
            if not File.exists(dst) then mv(legacyData .. "/" .. name, dst) end
        end
    end

    if #moved > 0 then
        print("[yanamin] Data lama dipindahkan ke " .. root .. ":")
        for _, line in ipairs(moved) do print("           " .. line) end
    end
    return #moved > 0
end

-- Resolved root, created on first use. Hard-stops when it is not writable.
function Paths.base()
    if root then return root end
    local candidate = os.getenv("YANAMIN_HOME")
    if not candidate or candidate == "" then candidate = DEFAULT_ROOT end
    candidate = stripTrailingSlash(candidate)

    mkdirp(candidate .. "/config")
    mkdirp(candidate .. "/data")
    if not writable(candidate) then hardStop(candidate) end

    root = candidate
    migrateLegacy(os.getenv("PWD") or ".")
    return root
end

function Paths.config()
    return Paths.base() .. "/config/config.lua"
end

function Paths.template()
    return Paths.base() .. "/config/template.lua"
end

function Paths.dataDir()
    return Paths.base() .. "/data"
end

function Paths.data(name)
    return Paths.dataDir() .. "/" .. tostring(name)
end

-- Relative paths (the ones stored in config) belong to the data root; absolute
-- paths are respected as-is so users can point logs somewhere else.
function Paths.resolve(path)
    path = tostring(path or "")
    if path == "" then return Paths.data("rejoin.log") end
    if path:match("^/") then return path end
    return Paths.base() .. "/" .. path
end

-- Make sure both subfolders exist (cheap, idempotent).
function Paths.ensure()
    local base = Paths.base()
    mkdirp(base .. "/config")
    mkdirp(base .. "/data")
    return base
end

local announced = false

-- One-line "where does my stuff live" hint, shown once at startup.
function Paths.announce()
    if announced then return end
    announced = true
    local base = Paths.base()
    local custom = (os.getenv("YANAMIN_HOME") or "") ~= ""
    print("[yanamin] Data root: " .. base .. (custom and "  (YANAMIN_HOME)" or ""))
    if not custom and base ~= DEFAULT_ROOT then
        print("[yanamin] Bukan " .. DEFAULT_ROOT .. " — cek YANAMIN_HOME.")
    end
end

return Paths