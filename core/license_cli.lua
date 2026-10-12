local License = require("managers.license")

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

function CLI.run()
    while true do
        print("\nLicense System:")
        print("  1) Status lisensi")
        print("  2) Login (masukkan key)")
        print("  3) Logout (hapus lisensi lokal)")
        print("  4) Kembali")
        local choice = (prompt("Choose: ") or ""):match("^%s*(.-)%s*$")

        if choice == "1" then
            local kind = License.check()
            print("\n" .. License.statusText(kind))
            local st = License.getState()
            if st then
                print("  deviceId : " .. tostring(st.deviceId or ""))
                print("  key      : " .. tostring(st.keyFam or ""))
                print("  disimpan : " .. tostring(st.saved or ""))
            end
            print("\n[Selesai] Tekan Enter untuk kembali ke menu utama")
            io.read()
            break
        elseif choice == "2" then
            print("Masukkan key (kode dari admin):")
            local key = prompt("Key: ") or ""
            key = key:match("^%s*(.-)%s*$")
            local ok, info = License.register(key)
            if ok then
                print("\nLOGIN BERHASIL — lisensi permanen terpasang (key: " .. tostring(info or "") .. ").")
            else
                print("\nLOGIN GAGAL: " .. tostring(info or "unknown"))
                print("Cek: key benar? device belum terpakai maks device? server URL terisi?")
            end
            print("\n[Selesai] Tekan Enter untuk kembali ke menu utama")
            io.read()
            break
        elseif choice == "3" then
            License.clear()
            print("\nLisensi lokal dihapus.")
            print("\n[Selesai] Tekan Enter untuk kembali ke menu utama")
            io.read()
            break
        elseif choice == "4" then
            break
        else
            print("Unknown choice")
        end
    end
end

return CLI