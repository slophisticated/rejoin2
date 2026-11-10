local File = require("utils.file")

-- Single source of truth for where the engine keeps its state.
--
-- The repository folder is the root: config/, data/ and the log live there, but
-- always addressed ABSOLUTELY. Previously every module used a relative path
-- ("data/rejoin.log", "config/config.lua"), so state silently moved whenever the
-- engine was started from another working directory (a CLI run, a menu opened
-- from /sdcard, the boot script, an editor shell). The paths are unchanged on
-- disk, only stable now.
--
--   <repo>/config/config.lua    configuration
--   <repo>/data/monitor.pid     monitor lock
--   <repo>/data/rejoin.log      engine log
--
-- Nothing outside the repo (clone app data, Autoexecute scripts, Termux:Boot)
-- is written from here.
--
-- Override the root with the REJOIN_HOME environment variable (debugging, or a
-- second copy running side by side).
--
-- IMPORTANT: directories are created with `mkdir -p` through os.execute, NOT
-- through utils.shell — that one runs as root via `su -c`, which would leave
-- root-owned files Termux can no longer write.

local Paths = {}

local MARKER = "main.lua"

local root = nil
local announced = false

local function shellQuote(s)
    return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

-- `utils.file` is stubbed in several test harnesses (sometimes without exists()) and the
-- root is resolved at require time, so this must not depend on the full module.
local function exists(path)
    if type(File.exists) == "function" then return File.exists(path) end
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function mkdirp(path)
    if not path or path == "" then return end
    pcall(function() os.execute("mkdir -p " .. shellQuote(path)) end)
end

local function writable(path)
    local probe = path .. "/.rejoin_write_test"
    local f = io.open(probe, "w")
    if not f then return false end
    f:write("ok")
    f:close()
    os.remove(probe)
    return true
end

local function stripTrailingSlash(p)
    local out = tostring(p or ""):gsub("[/\\]+$", "")
    if out == "" then return "/" end
    return out
end

-- Directory part of a path, or nil.
local function dirOf(path)
    if not path or path == "" then return nil end
    return path:match("^(.*)[/\\][^/\\]*$")
end

-- Walk up from `dir` looking for the repository root (it holds main.lua).
local function findRoot(dir)
    if not dir or dir == "" then return nil end
    if not dir:match("^/") and not dir:match("^%a:[/\\]") then
        local pwd = os.getenv("PWD")
        if pwd and pwd ~= "" then dir = pwd .. "/" .. dir end
    end
    local cur = stripTrailingSlash(dir)
    for _ = 1, 8 do
        if exists(cur .. "/" .. MARKER) and exists(cur .. "/core/paths.lua") then
            return cur
        end
        local parent = dirOf(cur)
        if not parent or parent == cur then return nil end
        cur = parent
    end
    return nil
end

-- Candidates in order of trust: an explicit override, then the directory of the
-- script being run (`lua /path/rejoin/main.lua`, or crash_guard's `main.lua`
-- argument), then the working directory.
local function candidates()
    local list = {}
    local env = os.getenv("REJOIN_HOME")
    if env and env ~= "" then list[#list + 1] = { path = stripTrailingSlash(env), explicit = true } end
    local scriptDir = dirOf(arg and arg[0])
    if scriptDir then list[#list + 1] = { from = scriptDir } end
    -- `lua utils/crash_guard.lua main.lua`: the real entry is arg[1].
    local real = arg and arg[1]
    if real and real:match("main%.lua$") then list[#list + 1] = { from = dirOf(real) } end
    list[#list + 1] = { from = os.getenv("PWD") }
    list[#list + 1] = { from = "." }
    return list
end

-- Resolved root, created on first use.
function Paths.base()
    if root then return root end
    local tried = {}
    for _, c in ipairs(candidates()) do
        local found = c.path or findRoot(c.from)
        if found then
            mkdirp(found .. "/config")
            mkdirp(found .. "/data")
            if writable(found) or c.explicit then
                root = found
                return root
            end
            tried[#tried + 1] = found
        end
    end
    -- Nothing usable found: keep the old behaviour (relative) instead of dying, so
    -- a dry-run or a sandbox without the full tree still works.
    root = "."
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

-- Relative paths (e.g. a log path stored in config) belong to the root; absolute
-- paths are respected as-is so a log can be pointed somewhere else.
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

-- One-line "where does my stuff live" hint, shown once at startup.
function Paths.announce()
    if announced then return end
    announced = true
    local base = Paths.base()
    local custom = (os.getenv("REJOIN_HOME") or "") ~= ""
    print("[rejoin] Folder data: " .. base .. (custom and "  (REJOIN_HOME)" or ""))
end

return Paths
