local Logger = require("core.logger")
local Config = require("core.config")
local File = require("utils.file")
local Shell = require("utils.shell")

-- In-game status from inside Roblox.
--
-- rejoin installs scripts/rejoin_heartbeat.lua into the executor's autoexecute folder
-- (appAutoExecutePath). Inside the game that script writes
--   <workspace>/rejoin/hb_<username>.txt
-- every `interval` seconds: state (ingame / kicked), fps, ping, memory, time.
-- The workspace folder is found next to the autoexecute folder (Workspace/workspace)
-- unless heartbeat.workspacePath is set.
--
-- Only a heartbeat written AFTER the clone's latest launch counts, so an old file
-- (e.g. the "kicked" one from before a relaunch) never triggers anything.
--
-- Config (all optional):
--   heartbeat = {
--       enabled = true,      -- install the script and use its status
--       interval = 10,       -- seconds between writes inside the game
--       staleAfter = 90,     -- seconds without a write before the game counts as gone
--       workspacePath = "",  -- "" = auto
--       saver = { enabled = false, disable3d = true, fpsCap = 15,
--                 lowGraphics = true, mute = true },
--   }

local Heartbeat = {}

local SCRIPT_NAME = "rejoin_heartbeat.lua"
local MARKER = "REJOIN_HEARTBEAT"
local FOLDER = "rejoin"

local launchedAt = {} -- pkg -> os.time() of the latest launch
-- Files older than this engine run never count (e.g. yesterday's stale heartbeat).
local startedAt = os.time()
local wsCache = nil
local readCache = {} -- pkg -> { at, hb } ; the monitor asks several times per cycle
local expected = {} -- pkg -> session request written before opening the app
local serial = 0
local readFile

function Heartbeat.identity(instance)
    local Username = require("managers.username")
    local name = Username.get(instance)
    if type(name) ~= "string" or not name:match("^[%w_]+$") then
        return nil, "username belum teridentifikasi"
    end
    local conf = Config.get() or {}
    for _, other in pairs(conf.instances or {}) do
        if type(other) == "table" and other.package ~= instance.package then
            local otherName = Username.get(other)
            if type(otherName) == "string" and otherName:lower() == name:lower() then
                return nil, "username dipakai dua clone; periksa mapping akun"
            end
        end
    end
    return name:lower()
end

local function fields(content)
    local out = {}
    for line in tostring(content or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^(%w+)=(.*)$")
        if k then out[k] = v end
    end
    return out
end

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function conf()
    local ok, c = pcall(Config.get)
    c = ok and type(c) == "table" and c or {}
    local hb = type(c.heartbeat) == "table" and c.heartbeat or {}
    local sv = type(hb.saver) == "table" and hb.saver or {}
    return {
        enabled = hb.enabled ~= false,
        interval = math.max(3, math.floor(tonumber(hb.interval) or 10)),
        staleAfter = math.max(20, math.floor(tonumber(hb.staleAfter) or 90)),
        workspacePath = type(hb.workspacePath) == "string" and hb.workspacePath or "",
        saver = {
            enabled = sv.enabled == true,
            disable3d = sv.disable3d ~= false,
            fpsCap = math.max(0, math.floor(tonumber(sv.fpsCap) or 15)),
            lowGraphics = sv.lowGraphics ~= false,
            mute = sv.mute ~= false,
        },
    }, c
end

function Heartbeat.isEnabled() return conf().enabled end
function Heartbeat.saverEnabled()
    local c = conf()
    return c.enabled and c.saver.enabled
end

local function autoexecDir()
    local _, c = conf()
    local dir = c.appAutoExecutePath
    if type(dir) ~= "string" or dir == "" then return nil end
    return (dir:gsub("/+$", ""))
end

local function dirExists(path)
    local ok, out = Shell.exec("[ -d '" .. path:gsub("'", "'\\''") .. "' ] && echo AE_YES || echo AE_NO")
    return ok and out and out:find("AE_YES", 1, true) ~= nil
end

-- The executor's workspace folder (where writefile() lands).
function Heartbeat.workspaceDir()
    local c = conf()
    if c.workspacePath ~= "" then return (c.workspacePath:gsub("/+$", "")) end
    if wsCache then return wsCache end
    local ae = autoexecDir()
    if not ae then return nil end
    local parent = ae:match("^(.*)/[^/]+$") or ae
    for _, name in ipairs({ "Workspace", "workspace" }) do
        local p = parent .. "/" .. name
        if dirExists(p) then
            wsCache = p
            return p
        end
    end
    return parent .. "/Workspace"
end

local function scriptSource()
    local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/managers/[^/]+$") or "."
    if type(__ya_source) == "function" then
        local embedded = __ya_source("scripts.rejoin_heartbeat")
        if embedded then return embedded end
    end
    return File.read(here .. "/scripts/rejoin_heartbeat.lua") or File.read("scripts/rejoin_heartbeat.lua")
end

local function luaValue(v)
    if type(v) == "boolean" or type(v) == "number" then return tostring(v) end
    return string.format("%q", tostring(v))
end

-- Install (or refresh) the script in the autoexecute folder; remove it when disabled.
-- Returns ok, message.
function Heartbeat.install()
    local c = conf()
    local dir = autoexecDir()
    if not dir then return false, "appAutoExecutePath kosong" end
    local target = dir .. "/" .. SCRIPT_NAME

    if not c.enabled then
        local existing = File.read(target)
        if existing and existing:find(MARKER, 1, true) then
            os.remove(target)
            Logger.info("Heartbeat: script dilepas dari " .. target)
        end
        return true, "disabled"
    end

    local src = scriptSource()
    if not src then return false, "scripts/rejoin_heartbeat.lua tidak ditemukan" end
    local cfg = string.format(
        "{\n    interval = %d,\n    folder = %s,\n    saver = %s,\n    disable3d = %s,\n"
        .. "    fpsCap = %d,\n    lowGraphics = %s,\n    mute = %s,\n}",
        c.interval, luaValue(FOLDER), luaValue(c.saver.enabled), luaValue(c.saver.disable3d),
        c.saver.fpsCap, luaValue(c.saver.lowGraphics), luaValue(c.saver.mute))
    local s, e = src:find("--[[REJOIN_CFG]]", 1, true)
    local s2, e2 = src:find("--[[/REJOIN_CFG]]", 1, true)
    if not s or not s2 then return false, "template rusak" end
    local out = src:sub(1, e) .. cfg .. src:sub(s2)

    if File.read(target) == out then return true, "up to date" end
    local ok, err = File.write(target, out)
    if not ok then
        Logger.warn("Heartbeat: gagal menulis " .. target .. ": " .. tostring(err))
        return false, tostring(err)
    end
    Logger.info("Heartbeat: script terpasang di " .. target .. (c.saver.enabled and " (mode hemat)" or ""))
    return true, target
end

-- os.time() of this clone's latest launch by this engine, or nil.
function Heartbeat.launchedAt(instance)
    return instance and instance.package and launchedAt[instance.package] or nil
end

function Heartbeat.markLaunched(instance)
    local pkg = instance and instance.package
    if pkg then
        launchedAt[pkg] = os.time()
        readCache[pkg] = nil
        if not Heartbeat.isEnabled() then return true end
        local name, err = Heartbeat.identity(instance)
        if not name then return false, err end
        local ws = Heartbeat.workspaceDir()
        if not ws then return false, "folder Workspace belum ditemukan" end
        serial = serial + 1
        local random = io.open("/dev/urandom", "rb")
        local bytes = random and random:read(8) or nil
        if random then random:close() end
        local suffix = bytes and bytes:gsub(".", function(b) return string.format("%02x", b:byte()) end)
            or string.format("%d_%d", math.random(100000, 999999), math.floor(os.clock() * 1000000))
        local token = string.format("%d_%s_%d", os.time(), suffix, serial)
        local request = { name = name, package = pkg, session = token, started = os.time() }
        local dir = ws .. "/" .. FOLDER
        local path = dir .. "/start_" .. name .. ".txt"
        local content = string.format("name=%s\npackage=%s\nsession=%s\nstarted=%d\n", name, pkg, token, request.started)
        local ok = File.write(path, content)
        if not ok then
            ok = Shell.exec("sh -c " .. quote("mkdir -p " .. quote(dir) .. " && printf %s " .. quote(content) .. " > " .. quote(path)))
        end
        if not ok then return false, "gagal menulis penanda sesi heartbeat" end
        expected[pkg] = request
        return true
    end
    return false, "package kosong"
end

readFile = function(path)
    local content = File.read(path)
    if content then return content end
    -- Files written by the app may not be readable by Termux directly.
    local ok, out = Shell.exec("cat '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null")
    if ok and out and out ~= "" and out ~= "(dry-run)" then return out end
    return nil
end

-- Latest heartbeat for this clone, or nil. Fields: state, fps, ping, mem, time,
-- fresh (written within staleAfter), current (written after the latest launch).
function Heartbeat.read(instance)
    local c = conf()
    if not c.enabled or not instance or not instance.package then return nil end
    local cached = readCache[instance.package]
    if cached and os.time() - cached.at < 2 then return cached.hb end
    local hb = Heartbeat.readNow(instance, c)
    readCache[instance.package] = { at = os.time(), hb = hb }
    return hb
end

function Heartbeat.readNow(instance, c)
    c = c or conf()
    local name = Heartbeat.identity(instance)
    if not name or name == "" then return nil end
    local ws = Heartbeat.workspaceDir()
    if not ws then return nil end
    local content = readFile(ws .. "/" .. FOLDER .. "/hb_" .. name:lower() .. ".txt")
    if not content then return nil end

    local hb = fields(content)
    hb.time = tonumber(hb.time)
    if not hb.time or tostring(hb.name):lower() ~= name then return nil end
    if type(hb.session) ~= "string" or not hb.session:match("^[%w_%-]+$") then return nil end
    hb.seq = tonumber(hb.seq)
    if not hb.seq or hb.seq < 1 then return nil end
    hb.fps, hb.ping, hb.mem = tonumber(hb.fps), tonumber(hb.ping), tonumber(hb.mem)
    local now = os.time()
    hb.age = now - hb.time
    if hb.age < -5 then return nil end
    hb.fresh = hb.age >= -5 and hb.age <= c.staleAfter
    local since = launchedAt[instance.package] or startedAt
    local request = expected[instance.package]
    if not request then
        local saved = fields(readFile(ws .. "/" .. FOLDER .. "/start_" .. name .. ".txt"))
        if saved.package == instance.package and saved.name == name and saved.session then
            request = saved
            expected[instance.package] = saved
        end
    end
    -- Manual app starts can report a self-generated session; an engine launch must
    -- echo its exact request. A previous run cannot satisfy a new launch in the same second.
    local matches = request and hb.session == request.session and hb.package == instance.package
        or (not request and not launchedAt[instance.package] and (hb.package == "" or hb.package == instance.package))
    hb.current = matches and hb.time >= since
    return hb
end

-- Is the game up, judged from inside it?
--   true  = fresh heartbeat from this session, in game
--   false = kicked/disconnected, or this session's heartbeat stopped
--   nil   = no heartbeat from this session yet: caller decides another way
function Heartbeat.alive(instance)
    local ok, hb = pcall(Heartbeat.read, instance)
    if not ok or not hb or not hb.current then return nil end
    if hb.state == "kicked" then
        if hb.fresh then return false, "kicked: " .. tostring(hb.reason or "") end
        return nil
    end
    if hb.fresh then
        if hb.state == "ingame" then return true end
        return nil -- a loading report is progress, never proof that the game is ready
    end
    if hb.state == "ingame" then return false, string.format("heartbeat berhenti %ds", hb.age) end
    return nil
end

-- Short dashboard suffix like "12fps 380MB", or nil.
function Heartbeat.summary(instance)
    local ok, hb = pcall(Heartbeat.read, instance)
    if not ok or not hb or not hb.fresh or not hb.current or hb.state ~= "ingame" then return nil end
    local parts = {}
    if hb.fps then parts[#parts + 1] = hb.fps .. "fps" end
    if hb.mem and hb.mem > 0 then parts[#parts + 1] = hb.mem .. "MB" end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- RSS is diagnostic only. A live process without HB is unknown, not unhealthy.
function Heartbeat.isUp(instance, apk)
    local alive = Heartbeat.alive(instance)
    if alive ~= nil then return alive end
    local pkg = instance and instance.package
    if not pkg then return false end
    apk = apk or require("managers.apk")
    local ok, res = pcall(apk.isRunning, pkg)
    if ok and res == false then return false end
    if not Heartbeat.isEnabled() and ok then return res end
    return nil
end

return Heartbeat
