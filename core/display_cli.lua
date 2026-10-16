local Config = require("core.config")

-- Main Menu 10: floating window grid, Delta heartbeat and saver mode.
-- Pick one item at a time; every change is saved right away. Displayed values follow
-- the same defaults as the modules that use them (window_layout / heartbeat).

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local function onoff(v) return v and "nyala" or "mati" end

local function render3dIsOff(hb, sv)
    return hb.enabled ~= false and sv.enabled == true and sv.disable3d ~= false
end

local function save(conf)
    local ok, err = Config.save(conf)
    print(ok and "Tersimpan." or ("Gagal menyimpan: " .. tostring(err)))
end

local function tables(conf)
    conf.windowLayout = type(conf.windowLayout) == "table" and conf.windowLayout or {}
    conf.heartbeat = type(conf.heartbeat) == "table" and conf.heartbeat or {}
    conf.heartbeat.saver = type(conf.heartbeat.saver) == "table" and conf.heartbeat.saver or {}
    return conf.windowLayout, conf.heartbeat, conf.heartbeat.saver
end

-- Ask for a whole number >= min; empty input keeps the old value.
local function askInt(label, current, min)
    local v = prompt(label .. ": [" .. tostring(current) .. "] ")
    if not v or v:match("^%s*$") then return nil end
    local n = tonumber(v)
    if n and n >= min then return math.floor(n) end
    print("Angka tidak valid.")
    return nil
end

function CLI.run()
    local conf = Config.get() or {}
    while true do
        local wl, hb, sv = tables(conf)
        local cols = tonumber(wl.columns) or 0
        print("\nJendela & Mode Hemat:")
        print("  1) Auto atur jendela (grid) [" .. onoff(wl.enabled == true) .. "]")
        print("  2) Kolom grid               [" .. (cols > 0 and tostring(cols) or "0 = otomatis") .. "]")
        print("  3) Jarak antar jendela      [" .. tostring(wl.gap or 0) .. " px]")
        print("  4) Heartbeat Delta          [" .. onoff(hb.enabled ~= false) .. "]")
        print("  5) Mode hemat               [" .. onoff(sv.enabled == true) .. "]")
        print("  6) Batas FPS (mode hemat)   [" .. tostring(sv.fpsCap or 15) .. "]")
        print("  7) Render 3D mati (efektif)  [" .. (render3dIsOff(hb, sv) and "ya" or "tidak") .. "]")
        print("  8) Pasang ulang script heartbeat sekarang")
        print("  9) Baris atas numpuk ke bawah [" .. tostring(wl.overlap or 80) .. " px, 0 = grid biasa]")
        print("  0) Kembali")
        local choice = (prompt("Pilih: ") or "0"):match("^%s*(.-)%s*$")

        if choice == "0" or choice == "" then
            return
        elseif choice == "1" then
            wl.enabled = not (wl.enabled == true)
            print("Auto atur jendela: " .. onoff(wl.enabled))
            save(conf)
        elseif choice == "2" then
            local n = askInt("Kolom grid (0 = otomatis)", cols, 0)
            if n then wl.columns = n; save(conf) end
        elseif choice == "3" then
            local n = askInt("Jarak antar jendela (pixel)", wl.gap or 0, 0)
            if n then wl.gap = n; save(conf) end
        elseif choice == "4" then
            hb.enabled = not (hb.enabled ~= false)
            print("Heartbeat Delta: " .. onoff(hb.enabled))
            if not hb.enabled and sv.enabled then
                print("(Mode hemat ikut tidak aktif tanpa heartbeat.)")
            end
            save(conf)
        elseif choice == "5" then
            sv.enabled = not (sv.enabled == true)
            print("Mode hemat: " .. onoff(sv.enabled))
            if sv.enabled and hb.enabled == false then
                print("(Nyalakan juga Heartbeat Delta / pilihan 4, mode hemat jalan lewat script itu.)")
            end
            save(conf)
        elseif choice == "6" then
            local n = askInt("Batas FPS (0 = tanpa batas)", sv.fpsCap or 15, 0)
            if n then sv.fpsCap = n; save(conf) end
        elseif choice == "7" then
            sv.disable3d = not (sv.disable3d ~= false)
            print("Render 3D mati (efektif): " .. (render3dIsOff(hb, sv) and "ya" or "tidak"))
            if sv.enabled ~= true then print("Mode hemat mati, jadi render 3D tetap aktif saat ini.") end
            if hb.enabled == false then print("Heartbeat Delta mati, jadi pengaturan ini belum diterapkan.") end
            save(conf)
        elseif choice == "8" then
            local Heartbeat = require("managers.heartbeat")
            local ok, msg = Heartbeat.install()
            print((ok and "OK: " or "Gagal: ") .. tostring(msg))
        elseif choice == "9" then
            local n = askInt("Tinggi tambahan baris atas (pixel, 0 = grid biasa)", wl.overlap or 80, 0)
            if n then
                wl.overlap = n
                save(conf)
                print("(Berlaku saat clone dibuka ulang.)")
            end
        else
            print("Pilihan tidak dikenal.")
        end
        if choice ~= "8" and (choice == "4" or choice == "5" or choice == "6" or choice == "7") then
            print("(Berlaku setelah script heartbeat dipasang ulang: pilihan 8, atau otomatis saat monitor mulai.)")
        end
    end
end

return CLI
