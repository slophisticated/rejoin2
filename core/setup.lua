local File = require("utils.file")
local Logger = require("core.logger")

local Setup = {}
local configPath = "config/config.lua"
local templatePath = "config/template.lua"

-- Ensure a usable config exists. If config/config.lua is missing, copy template to config/config.lua
-- Optionally, pass a sourcePath to copy from instead of the packaged template
-- Returns: ok, created(boolean)/err
function Setup.ensureConfig(sourcePath)
    if File.exists(configPath) then
        Logger.info("Setup: config exists: " .. configPath)
        return true, false
    end

    local tplPath = sourcePath or templatePath

    if not File.exists(tplPath) then
        Logger.error("Setup: template not found: " .. tplPath)
        return false, "no_template"
    end

    local content, err = File.read(tplPath)
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
