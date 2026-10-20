-- Runs a Lua script (main.lua) and keeps the traceback of an uncaught error in
-- data/crash.log. Started from the menu (run.sh) a crash was only printed to the
-- screen and lost; the error report (Main Menu 4) reads this file.
--
-- Usage: lua utils/crash_guard.lua main.lua [args...]   (arg / ... look as usual)

local LOG = "data/crash.log"
local script = arg and arg[1]
if not script then
    io.stderr:write("usage: lua utils/crash_guard.lua <script.lua> [args...]\n")
    os.exit(2)
end
local args = { [0] = script }
for i = 2, #arg do args[i - 1] = arg[i] end
arg = args

local chunk, loadErr = loadfile(script)
if not chunk then
    io.stderr:write(tostring(loadErr) .. "\n")
    os.exit(1)
end

local ok, err = xpcall(chunk, debug.traceback, table.unpack(args))
if ok then return end

local message = tostring(err)
pcall(function()
    os.execute("mkdir -p data 2>/dev/null")
    local f = io.open(LOG, "r")
    local size = f and f:seek("end") or 0
    if f then f:close() end
    if size > 262144 then os.rename(LOG, LOG .. ".old") end
    local out = io.open(LOG, "a")
    if out then
        out:write(string.format("[%s] %s %s\n%s\n\n", os.date("%Y-%m-%d %H:%M:%S"), script,
            table.concat(args, " "), message))
        out:close()
    end
end)
io.stderr:write(message .. "\n(error ini kesimpen di " .. LOG .. "; Menu 4 -> 1 buat report)\n")
os.exit(1)
