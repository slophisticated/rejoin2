local Boot = require("managers.boot")

-- Submenu "Auto-boot (Termux:Boot)": install / uninstall the boot script and
-- inspect the boot log, so a single-file loader can enable auto-start on its own.

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local function wait()
    print("\n[Selesai] Tekan Enter untuk kembali ke menu utama")
    io.read()
end

function CLI.run()
    while true do
        local st = Boot.status()
        print("\nAuto-boot (Termux:Boot)")
        print("  script boot : " .. st.path .. (st.installed and "   [TERPASANG]" or "   [belum]"))
        print("  aplikasi    : " .. (st.app
            and "Termux:Boot terpasang"
            or "Termux:Boot BELUM terpasang (pasang dari sumber yang sama dengan Termux)"))
        print("  log boot    : " .. st.log .. (st.logExists and "" or "   [belum ada]"))

        print("\n  1) Install / update script boot")
        print("  2) Uninstall script boot")
        print("  3) Lihat 10 baris terakhir boot.log")
        print("  4) Kembali")

        local choice = (prompt("Choose: ") or ""):match("^%s*(.-)%s*$")

        if choice == "1" then
            local ok, info = Boot.install()
            if ok then
                print("\nScript boot terpasang: " .. tostring(info))
                print("Langkah lanjut: BUKA aplikasi Termux:Boot sekali, lalu reboot HP.")
                print("Saat boot engine jalan tersembunyi (headless launch + monitor).")
                print("Log: " .. tostring(Boot.logPath()))
            else
                print("\nGAGAL: " .. tostring(info))
            end
            wait()
            break
        elseif choice == "2" then
            local ok, info = Boot.uninstall()
            if ok then
                print("\nScript boot dihapus: " .. tostring(info))
                print("Auto-start di boot berikutnya tidak dijalankan lagi.")
            else
                print("\n" .. tostring(info))
            end
            wait()
            break
        elseif choice == "3" then
            local out, err = Boot.tailLog(10)
            if out then
                print("\n--- boot.log (10 baris terakhir) ---")
                io.write(out)
                if not out:match("\n$") then io.write("\n") end
            else
                print("\nBelum ada log: " .. tostring(err))
                print("Normal kalau HP belum pernah di-boot sejak script dipasang.")
            end
            wait()
            break
        elseif choice == "4" then
            break
        else
            print("Unknown choice")
        end
    end
end

return CLI