local Logger = require("core.logger")
local File = require("utils.file")

-- Main Menu 4: one error report for everything (copied to the clipboard), or a raw
-- look at a single log.

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local function showTail(path, defaultLines)
    if not File.exists(path) then
        print("Log belum ada: " .. tostring(path))
        return
    end
    local input = prompt("Berapa baris terakhir (default " .. defaultLines .. "): ") or ""
    local n = tonumber(input) or defaultLines
    local content, err = File.read(path)
    if not content then
        print("Gagal baca log: " .. tostring(err))
        return
    end
    local lines = {}
    for l in content:gmatch("[^\r\n]+") do lines[#lines + 1] = l end
    for i = math.max(1, #lines - n + 1), #lines do print(lines[i]) end
end

function CLI.run()
    while true do
        print("\nLogs & Report Error:")
        print("  1) Report error lengkap (semua log digabung) + copy ke clipboard")
        print("  2) Lihat rejoin.log")
        print("  3) Lihat boot.log (boot + auto-update)")
        print("  4) Lihat crash.log (error Lua)")
        print("  0) Kembali")
        local choice = (prompt("Pilih [1]: ") or "0"):match("^%s*(.-)%s*$")
        if choice == "" then choice = "1" end
        if choice == "0" then return end
        if choice == "1" then
            local Report = require("managers.report")
            local ok, text, status = pcall(Report.run)
            if not ok then
                print("Report gagal dibuat: " .. tostring(text))
            else
                print("\n" .. text)
                for _, line in ipairs(status) do print(line) end
                print("Rahasia (URL webhook, secret, HWID, cookie) udah disensor.")
            end
        elseif choice == "2" then
            showTail(Logger.getLogPath(), 200)
        elseif choice == "3" then
            showTail("data/boot.log", 100)
        elseif choice == "4" then
            showTail("data/crash.log", 100)
        else
            print("Pilihan tidak dikenal.")
        end
    end
end

return CLI
