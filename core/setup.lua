local Paths = require("core.paths")
local File = require("utils.file")
local Logger = require("core.logger")

local Setup = {}
local configPath = Paths.config()
local templatePath = Paths.template()

-- Ensure a usable config exists. If config/config.lua is missing, copy template to config/config.lua
-- Optionally, pass a sourcePath to copy from instead of the packaged template
-- Returns: ok, created(boolean)/err
function Setup.ensureConfig(sourcePath)
    if File.exists(configPath) then
        Logger.info("Setup: config exists: " .. configPath)
        return true, false
    end

    local tplPath = sourcePath or templatePath

    local content, err = File.read(tplPath)
    if not content and not sourcePath then
        if type(__ya_source) == "function" then content = __ya_source("config.template") end
        if not content then
            local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/core/[^/]+$") or "."
            content, err = File.read(here .. "/config/template.lua")
        end
    end
    if not content then
        Logger.error("Setup: failed to read template: " .. tostring(err))
        return false, err
    end

    local ok, writeErr = File.write(configPath, content)
    if not ok then
        Logger.error("Setup: failed to write config: " .. tostring(writeErr))
        return false, writeErr
    end

    Logger.info("Setup: created config from template: " .. configPath)
    return true, true
end

return Setup
