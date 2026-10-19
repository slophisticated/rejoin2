local DeltaKey = require("managers.delta_key")

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local function readKey()
    io.write("Masukkan key Delta (contoh FREE_XXXXX; input disembunyikan): ")
    io.flush()
    os.execute("stty -echo 2>/dev/null")
    local readOk, key = pcall(io.read, "*l")
    os.execute("stty sane 2>/dev/null")
    os.execute("stty echo icanon opost onlcr 2>/dev/null")
    io.write("\r\n")
    io.flush()
    if not readOk then return "" end
    return (key or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function CLI.run()
    print("\nInput Key Delta")
    print("Masukkan key yang kamu dapatkan dari Delta. Key tidak disimpan di config atau log.")
    local key = readKey()
    if key == "" then
        print("Dibatalkan.")
    else
        local called, ok, message = pcall(DeltaKey.input, key)
        key = nil
        print((called and ok and "Berhasil: " or "Gagal: ") .. tostring(called and message or "input key Delta gagal (error internal)"))
    end
    prompt("Tekan Enter untuk kembali ke menu utama")
end

return CLI
