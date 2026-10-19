local File = require("utils.file")
local Logger = require("core.logger")
local Paths = require("core.paths")
local Boot = require("managers.boot")

-- Full uninstall for the single-file loader.
--
-- Removes everything the tool owns, and nothing else:
--   1. the Termux:Boot script (~/.termux/boot/start-rejoin.sh)
--   2. the whole data root (/sdcard/yanamin: config + data + all logs)
--   3. the engine/loader file itself — but only when it is the single-file
--      loader. When the running entry is main.lua (the repo checkout) the file
--      is left alone on purpose: deleting it would wreck the source tree.
--
-- Clone app data, AutoExecute scripts and anything else on the device are never
-- touched.

local Uninstall = {}

local function shellQuote(s)
    return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

-- The file this process is running from, if it is safe to delete.
function Uninstall.selfRemovable()
    local self = Boot.selfPath()
    if not self then return nil, "tidak tahu file yang sedang jalan" end
    local name = self:match("([^/\\]+)$")
    if name == "main.lua" then
        return nil, "file engine main.lua tidak dihapus (hapus manual bila perlu)"
    end
    if not File.exists(self) then
        return nil, "file " .. self .. " tidak ditemukan"
    end
    return self, name
end

-- Everything that would be deleted, for the confirmation screen.
function Uninstall.targets()
    local list = {}

    local bootScript = Boot.scriptPath()
    if File.exists(bootScript) then
        table.insert(list, { path = bootScript, what = "auto-boot (Termux:Boot)" })
    end

    local base = Paths.base()
    if File.exists(base .. "/config/config.lua") or File.exists(base .. "/data") then
        table.insert(list, { path = base, what = "data root (config + data + log)" })
    end

    local self, why = Uninstall.selfRemovable()
    if self then
        table.insert(list, { path = self, what = "file loader" })
    else
        table.insert(list, { path = nil, what = "file loader: TIDAK dihapus (" .. tostring(why) .. ")" })
    end

    return list
end

-- Do the actual removal. Returns a list of human-readable results.
function Uninstall.runAll()
    local results = {}

    -- 1) Termux:Boot script
    local okBoot, infoBoot = Boot.uninstall()
    if okBoot then
        table.insert(results, "Auto-boot dihapus: " .. tostring(infoBoot))
    else
        table.insert(results, "Auto-boot: " .. tostring(infoBoot))
    end

    -- 2) data root (config + data + logs)
    local base = Paths.base()
    os.execute("rm -rf " .. shellQuote(base))
    if File.exists(base) then
        table.insert(results, "GAGAL hapus data root: " .. base)
    else
        table.insert(results, "Data root dihapus: " .. base)
    end

    -- 3) the loader file itself
    local self = Uninstall.selfRemovable()
    if self then
        local removed = os.remove(self)
        if removed then
            table.insert(results, "File loader dihapus: " .. self)
        else
            table.insert(results, "GAGAL hapus file loader: " .. self)
        end
    else
        table.insert(results, "File loader tidak dihapus (hapus manual bila perlu)")
    end

    Logger.info("Uninstall: " .. table.concat(results, " | "))
    return results
end

return Uninstall