local Logger = require("core.logger")
local File = require("utils.file")

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

function CLI.run()
    local logPath = Logger.getLogPath()
    if not File.exists(logPath) then
        print("Log file not found: " .. tostring(logPath))
        return
    end

    local defaultLines = 200
    local input = prompt("How many lines to show (default " .. tostring(defaultLines) .. "): ") or ""
    local n = tonumber(input) or defaultLines

    local content, err = File.read(logPath)
    if not content then
        print("Failed to read log: " .. tostring(err))
        return
    end

    local lines = {}
    for l in content:gmatch("[^\r\n]+") do table.insert(lines, l) end
    local start = #lines - n + 1
    if start < 1 then start = 1 end
    for i = start, #lines do
        print(lines[i])
    end
end

return CLI
