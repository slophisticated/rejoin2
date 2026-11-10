local File = require("utils.file")
local Logger = require("core.logger")
local Paths = require("core.paths")
local Boot = require("managers.boot")

-- Menu "Uninstall": remove what rejoin owns, and nothing else.
--
--  1. the Termux:Boot script, so a reboot does not start the engine again
--  2. the heartbeat script from the executor's Autoexecute folder (rejoin's own
--     file only; anything the user added there stays)
--  3. the engine state (config/ + data/) inside the repo
--
-- The repo checkout itself, clone app data and the user's other scripts are left
-- alone: deleting the tree from inside a running main.lua is not worth the risk, so
-- the menu prints how to remove the folder by hand.

local Uninstall = {}

local function quote(s)
    return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

local MARKER = "REJOIN_HEARTBEAT"
local SCRIPT_NAME = "rejoin_heartbeat.lua"

-- Every copy of rejoin's heartbeat script: the configured executor plus every other
-- executor that was found, mirroring what Heartbeat.install() writes.
local function heartbeatScripts()
    local paths = {}
    local ok, Heartbeat = pcall(require, "managers.heartbeat")
    if ok and type(Heartbeat.install) == "function" then
        local okCfg, config = pcall(require, "core.config")
        if okCfg and type(config.get) == "function" then
            local okGet, c = pcall(config.get)
            local dir = okGet and type(c) == "table" and c.appAutoExecutePath or nil
            if type(dir) == "string" and dir ~= "" then
                paths[#paths + 1] = (dir:gsub("/+$", "")) .. "/" .. SCRIPT_NAME
            end
        end
        local okE, Executor = pcall(require, "managers.executor")
        if okE and type(Executor.found) == "table" then
            for _, e in ipairs(Executor.found) do
                if type(e.path) == "string" then
                    paths[#paths + 1] = (e.path:gsub("/+$", "")) .. "/" .. SCRIPT_NAME
                end
            end
        end
    end
    return paths
end

-- Only rejoin's own copy (identified by the marker), so a same-named user script
-- that rejoin did not write is left alone.
local function ownHeartbeat(path)
    local content = File.read(path)
    return content ~= nil and content:find(MARKER, 1, true) ~= nil
end

-- Everything that would be deleted, for the confirmation screen.
function Uninstall.targets()
    local list = {}
    local boot = Boot.scriptPath()
    if File.exists(boot) then
        table.insert(list, { path = boot, what = "auto-boot (Termux:Boot)" })
    end
    for _, path in ipairs(heartbeatScripts()) do
        if File.exists(path) and ownHeartbeat(path) then
            table.insert(list, { path = path, what = "script heartbeat di Autoexecute" })
        end
    end
    local cfg, data = Paths.config(), Paths.dataDir()
    if File.exists(cfg) then table.insert(list, { path = cfg, what = "config (semua setting)" }) end
    if File.exists(data) then table.insert(list, { path = data, what = "data (log, pid, antrian, laporan)" }) end
    table.insert(list, { path = nil, what = "folder repo " .. Paths.base() .. ": TIDAK dihapus" })
    return list
end

function Uninstall.removable()
    local list = {}
    for _, item in ipairs(Uninstall.targets()) do
        if item.path then list[#list + 1] = item end
    end
    return #list > 0
end

-- Do the removal. Returns human-readable results, one per target.
function Uninstall.runAll()
    local results = {}

    local okBoot, infoBoot = Boot.uninstall()
    results[#results + 1] = okBoot and ("Auto-boot dihapus: " .. tostring(infoBoot))
        or ("Auto-boot: " .. tostring(infoBoot))

    local scripts = heartbeatScripts()
    local removedHb = 0
    for _, path in ipairs(scripts) do
        if File.exists(path) and ownHeartbeat(path) then
            if os.remove(path) then
                removedHb = removedHb + 1
                results[#results + 1] = "Script heartbeat dihapus: " .. path
            else
                results[#results + 1] = "GAGAL hapus script heartbeat: " .. path
            end
        end
    end
    if removedHb == 0 then
        results[#results + 1] = #scripts == 0
            and "Script heartbeat: folder executor tidak diketahui, dilewati"
            or "Script heartbeat: tidak ada di Autoexecute"
    end

    local base = Paths.base()
    for _, name in ipairs({ "config", "data" }) do
        local target = base .. "/" .. name
        if File.exists(target) then
            os.execute("rm -rf " .. quote(target))
            results[#results + 1] = File.exists(target) and ("GAGAL hapus " .. target)
                or ("Dihapus: " .. target)
        end
    end

    results[#results + 1] = "Folder repo tetap: " .. base .. " (hapus manual: rm -rf " .. base .. ")"
    Logger.info("Uninstall: " .. table.concat(results, " | "))
    return results
end

return Uninstall
