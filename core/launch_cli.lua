local Config = require("core.config")
local Queue = require("managers.launch_queue")
local CLI = {}
local fields = {
    { "stableHeartbeats", "Jumlah heartbeat baru sebelum lanjut", 2, 10 },
    { "stableSeconds", "Waktu stabil minimum (detik)", 5, 300 },
    { "retryCooldown", "Jeda retry (detik)", 30, 3600 },
    { "maxAttempts", "Batas percobaan per clone", 1, 10 },
}
function CLI.run()
    local conf = Config.get()
    conf.launchSafety = type(conf.launchSafety) == "table" and conf.launchSafety or {}
    local safety = conf.launchSafety
    while true do
        print("\nAntrean & Heartbeat:")
        for i, f in ipairs(fields) do
            local value = safety[f[1]]
            if value == nil then value = Queue.DEFAULTS[f[1]] end
            print(string.format("  %d) %s [%s]", i, f[2], tostring(value)))
        end
        print("  0) Kembali")
        print("Timeout menahan antrean (Perlu dicek). Restart clone dari bot/menu untuk coba lagi.")
        print("Mode hemat/FPS: Menu 9. RAM/RSS hanya informasi, tidak membatasi antrean.")
        io.write("Pilih: ")
        io.flush()
        local selected = tonumber(io.read() or "0")
        if selected == 0 then return end
        local f = fields[selected]
        if f then
            if f[3] == "bool" then
                safety[f[1]] = safety[f[1]] == false
            else
                io.write("Nilai baru: ")
                io.flush()
                local value = tonumber(io.read() or "")
                if value and value % 1 == 0 and value >= f[3] and value <= f[4] then safety[f[1]] = value
                else print(string.format("Isi bilangan bulat %d–%d.", f[3], f[4])) end
            end
            local ok, err = Config.save(conf)
            print(ok and "Tersimpan; engine memakai saat siklus berikutnya." or ("Gagal: " .. tostring(err)))
        end
    end
end
return CLI
