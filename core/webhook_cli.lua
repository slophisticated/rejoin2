local Config = require("core.config")

-- Main Menu 9: Discord webhook status reports (managers/webhook.lua).
-- Pick one item at a time; every change is saved right away.

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local function section(conf)
    conf.webhook = type(conf.webhook) == "table" and conf.webhook or {}
    return conf.webhook
end

local function onoff(v) return v and "nyala" or "mati" end

local function save(conf)
    local ok, err = Config.save(conf)
    print(ok and "Tersimpan." or ("Gagal menyimpan: " .. tostring(err)))
end

function CLI.run()
    local conf = Config.get() or {}
    while true do
        local wh = section(conf)
        local hasUrl = type(wh.url) == "string" and wh.url ~= ""
        print("\nDiscord Webhook:")
        print("  1) URL webhook          [" .. (hasUrl and "diset" or "kosong") .. "]")
        print("  2) Interval laporan     [" .. tostring(wh.interval or 300) .. " detik]")
        print("  3) Screenshot           [" .. onoff(wh.screenshot ~= false) .. "]")
        print("  4) Notif Delta minta key [" .. onoff(wh.events ~= false) .. "]")
        print("  5) Sembunyikan nama     [" .. onoff(wh.hideNames ~= false) .. "]")
        print("  6) Kirim tes sekarang")
        local dn = type(wh.deviceName) == "string" and wh.deviceName or ""
        print("  7) Label Device Name    [" .. (dn ~= "" and dn or "kosong = model device") .. "]")
        print("  8) Pakai pesan status lama (paste link pesan dari device lama)")
        print("  0) Kembali")
        local choice = (prompt("Pilih: ") or "0"):match("^%s*(.-)%s*$")

        if choice == "0" or choice == "" then
            return
        elseif choice == "1" then
            local v = prompt("URL webhook (Discord > Edit Channel > Integrations > Webhooks > Copy URL; '-' = hapus): ")
            v = (v or ""):gsub("%s+", "")
            if v == "-" then
                wh.url = ""
                save(conf)
            elseif v == "" then
                print("Tidak diubah.")
            elseif v:match("^https://[%w%.%-%_]+/api/webhooks/%S+$") then
                wh.url = v
                save(conf)
            else
                print("URL tidak valid (harus https://discord.com/api/webhooks/...).")
            end
        elseif choice == "2" then
            local v = prompt("Interval laporan (detik, min 60): [" .. tostring(wh.interval or 300) .. "] ")
            local n = tonumber(v)
            if n and n >= 60 then
                wh.interval = math.floor(n)
                save(conf)
            elseif v and not v:match("^%s*$") then
                print("Angka tidak valid (min 60).")
            end
        elseif choice == "3" then
            wh.screenshot = not (wh.screenshot ~= false)
            print("Screenshot: " .. onoff(wh.screenshot))
            save(conf)
        elseif choice == "4" then
            wh.events = not (wh.events ~= false)
            print("Notif Delta minta key: " .. onoff(wh.events))
            save(conf)
        elseif choice == "5" then
            wh.hideNames = not (wh.hideNames ~= false)
            print("Sembunyikan nama: " .. onoff(wh.hideNames))
            save(conf)
        elseif choice == "6" then
            if not hasUrl then
                print("Isi URL webhook dulu (pilihan 1).")
            else
                local Webhook = require("managers.webhook")
                Webhook.configure(conf)
                local okI, Instances = pcall(require, "managers.instance")
                local list = okI and Instances.getAll and Instances.getAll() or {}
                print("Mengirim laporan tes...")
                local ok, res = pcall(Webhook.report, list)
                if ok and res then
                    print("Terkirim. Cek channel Discord.")
                else
                    print("Gagal kirim (cek URL / internet; detail di data/rejoin.log).")
                end
            end
        elseif choice == "7" then
            local v = prompt("Label Device Name (mis. 01; '-' = hapus): ")
            v = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if v == "-" then
                wh.deviceName = ""
                save(conf)
            elseif v == "" then
                print("Tidak diubah.")
            else
                wh.deviceName = v:sub(1, 60)
                save(conf)
            end
        elseif choice == "8" then
            if not hasUrl then
                print("Isi URL webhook dulu (pilihan 1), harus sama dengan device lama.")
            else
                print("Discord: klik kanan pesan status lama > Copy Message Link (atau Copy Message ID).")
                local v = prompt("Link / ID pesan: ")
                local Webhook = require("managers.webhook")
                Webhook.configure(conf)
                local id, err = Webhook.useMessage(v)
                if not id then
                    print(err)
                else
                    print("Mengedit pesan itu sekarang...")
                    local okI, Instances = pcall(require, "managers.instance")
                    local list = okI and Instances.getAll and Instances.getAll() or {}
                    local ok, res = pcall(Webhook.report, list)
                    if not (ok and res) then
                        print("Gagal kirim (cek URL / internet; detail di data/rejoin.log).")
                    elseif Webhook.messageId() == id then
                        print("Berhasil: pesan lama sekarang di-update oleh device ini.")
                    else
                        print("Pesan itu tidak bisa diedit (sudah dihapus atau dari webhook lain); dibuat pesan baru.")
                    end
                end
            end
        else
            print("Pilihan tidak dikenal.")
        end
    end
end

return CLI
