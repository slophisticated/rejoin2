-- Main Menu 12: type in a Delta key the user got from Delta. Manual input only; the
-- key is hidden while typing and never saved to the config or the log.
local DeltaKey = require("managers.delta_key")

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local function readKey()
    io.write("Masukkan key Delta (contoh FREE_XXXXX; ketikan disembunyikan, kosong = batal): ")
    io.flush()
    os.execute("stty -echo 2>/dev/null")
    local readOk, key = pcall(io.read, "*l")
    os.execute("stty sane 2>/dev/null")
    os.execute("stty echo icanon opost onlcr 2>/dev/null")
    io.write("\r\n")
    io.flush()
    if not readOk then return "" end
    return ((key or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function CLI.run()
    print("\nInput Key Delta")
    print("Masukkan key yang kamu dapat sendiri dari Delta. Key ga disimpan di config atau log.")
    print("File license: " .. tostring(DeltaKey.path() or "(belum ketemu, pakai <Delta>/internal/cache/license)"))
    local key = readKey()
    if key == "" then
        print("Dibatalkan.")
    else
        local called, ok, message = pcall(DeltaKey.input, key)
        key = nil
        print((called and ok and "Berhasil: " or "Gagal: ") .. tostring(called and message or "input key Delta gagal (error internal)"))
        if called and ok then
            -- Clones reopen one by one through the monitor queue so Delta reads the key.
            if require("managers.monitor").requestRejoinFile({ "all" }) then
                print("Semua clone dijadwalkan buka ulang satu per satu (monitor yang jalan ngambil sendiri;")
                print("kalau monitor belum jalan, pilih Menu 1).")
            end
        end
    end
    prompt("Tekan Enter untuk kembali ke menu utama")
end

return CLI
