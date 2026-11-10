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

local function heartbeatScriptPath()
    local ok, Heartbeat = pcall(require, "managers.heartbeat")
    if not ok or type(Heartbeat.workspaceDir) ~= "function" then return nil end
    local okDir, dir = pcall(Heartbeat.workspaceDir)
    if not okDir or not dir then return nil end
    return dir .. "/rejoin/rejoin_heartbeat.lua"
end

-- Everything that would be deleted, for the confirmation screen.
function Uninstall.targets()
    local list = {}
    local boot = Boot.scriptPath()
    if File.exists(boot) then
        table.insert(list, { path = boot, what = "auto-boot (Termux:Boot)" })
    end
    local hb = heartbeatScriptPath()
    if hb and File.exists(hb) then
        table.insert(list, { path = hb, what = "script heartbeat di Autoexecute" })
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

    local hb = heartbeatScriptPath()
    if hb then
        if File.exists(hb) then
            results[#results + 1] = os.remove(hb) and ("Script heartbeat dihapus: " .. hb)
                or ("GAGAL hapus script heartbeat: " .. hb)
        else
            results[#results + 1] = "Script heartbeat: tidak ada di Autoexecute"
        end
    else
        results[#results + 1] = "Script heartbeat: folder executor tidak diketahui, dilewati"
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
