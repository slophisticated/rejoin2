local Config = require("core.config")
local InstanceManager = require("managers.instance")

-- Main Menu 11: game presets. A preset is a named game link (e.g. A = Steal an Egg,
-- B = Fisch). Clones follow the DEFAULT preset unless they are given their own preset
-- ("khusus") or told to use their own link. Switching every clone to another game is
-- one change of the default. Every change is saved right away.

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function presets(conf)
    conf.presets = type(conf.presets) == "table" and conf.presets or {}
    return conf.presets
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return keys
end

local function validLink(l)
    return (l:match("^https://[%w%.%-]*roblox%.com/") or l:match("^roblox://")) ~= nil
end

local function save(conf)
    conf.instances = InstanceManager.getAll()
    local ok, err = Config.save(conf)
    print(ok and "Tersimpan." or ("Gagal menyimpan: " .. tostring(err)))
    return ok
end

-- Clones (ids) that currently follow the default preset.
local function followersOfDefault()
    local ids = {}
    for _, inst in ipairs(InstanceManager.getAll()) do
        local _, source = InstanceManager.presetOf(inst)
        if source == "default" or ((inst.preset == nil or inst.preset == "") and source ~= "khusus") then
            ids[#ids + 1] = inst.id
        end
    end
    return ids
end

-- Ask whether to rejoin now. The running engine (Menu 1 / boot) picks the request up
-- through data/rejoin_request.txt; without an engine the new link is used next launch.
local function offerRejoin(ids)
    if #ids == 0 then return end
    local v = trim(prompt(#ids .. " clone kena perubahan. Rejoin sekarang? (y/n) [y] "))
    if v == "" or v:lower() == "y" then
        local Monitor = require("managers.monitor")
        if Monitor.requestRejoinFile(ids) then
            print("Diminta. Engine yang jalan akan rejoin satu per satu; kalau engine tidak jalan, link baru dipakai di Launch All berikutnya.")
        end
    end
end

local SOURCE_LABEL = { khusus = "khusus", default = "ikut default", link = "link sendiri", none = "belum ada link" }

local function show(conf)
    local ps = presets(conf)
    local def = conf.defaultPreset
    print("\nPreset Game:")
    local keys = sortedKeys(ps)
    if #keys == 0 then print("  (belum ada preset)") end
    for _, k in ipairs(keys) do
        local p = ps[k]
        print(string.format("  [%s] %s%s\n      %s", k, tostring(p.name or ""),
            k == def and "  <- DEFAULT" or "", tostring(p.link or "")))
    end
    print("Clone:")
    for _, inst in ipairs(InstanceManager.getAll()) do
        local key, source = InstanceManager.presetOf(inst)
        local game = key and ("[" .. key .. "] " .. tostring(ps[key].name or "")) or (source == "link" and "link sendiri" or "-")
        print(string.format("  %s) %-14s -> %s (%s)", tostring(inst.id), tostring(inst.name or inst.package),
            game, SOURCE_LABEL[source] or source))
    end
end

local function pickPreset(conf, label)
    local key = trim(prompt(label))
    if key == "" then return nil end
    if not presets(conf)[key] then print("Preset '" .. key .. "' tidak ada."); return nil end
    return key
end

function CLI.run()
    local conf = Config.get() or {}
    while true do
        show(conf)
        print("\n  1) Tambah / ubah preset")
        print("  2) Hapus preset")
        print("  3) Set preset DEFAULT (semua clone yang ikut default pindah)")
        print("  4) Atur satu clone (preset khusus / ikut default / link sendiri)")
        print("  5) Semua clone ikut default")
        print("  0) Kembali")
        local choice = trim(prompt("Pilih: ") or "0")

        if choice == "0" or choice == "" then
            return
        elseif choice == "1" then
            local key = trim(prompt("Kode preset (mis. A, B, egg): "))
            if not key:match("^[%w_]+$") or #key > 16 or key == "default" then
                print("Kode harus huruf/angka (maks 16), bukan 'default'.")
            else
                local ps = presets(conf)
                local old = ps[key] or {}
                local name = trim(prompt("Nama game [" .. tostring(old.name or "") .. "]: "))
                local link = trim(prompt("Link game / private server [" .. tostring(old.link or "") .. "]: "))
                if name == "" then name = old.name or key end
                if link == "" then link = old.link or "" end
                if not validLink(link) then
                    print("Link harus link roblox.com (games/... atau share?code=...) atau roblox://")
                else
                    ps[key] = { name = name, link = link }
                    local firstOne = (conf.defaultPreset == nil or conf.defaultPreset == "")
                    if firstOne then
                        conf.defaultPreset = key
                        print("Preset pertama: otomatis jadi DEFAULT.")
                    end
                    if save(conf) and old.link and old.link ~= link then
                        local used = {}
                        for _, inst in ipairs(InstanceManager.getAll()) do
                            if InstanceManager.presetOf(inst) == key then used[#used + 1] = inst.id end
                        end
                        offerRejoin(used)
                    end
                end
            end
        elseif choice == "2" then
            local key = pickPreset(conf, "Kode preset yang dihapus: ")
            if key then
                if conf.defaultPreset == key then
                    print("Ini preset DEFAULT. Set default lain dulu (pilihan 3).")
                else
                    presets(conf)[key] = nil
                    local n = 0
                    for _, inst in ipairs(InstanceManager.getAll()) do
                        if inst.preset == key then inst.preset = nil; n = n + 1 end
                    end
                    save(conf)
                    if n > 0 then print(n .. " clone sekarang ikut default.") end
                end
            end
        elseif choice == "3" then
            local key = pickPreset(conf, "Kode preset untuk DEFAULT: ")
            if key and key ~= conf.defaultPreset then
                conf.defaultPreset = key
                if save(conf) then offerRejoin(followersOfDefault()) end
            elseif key then
                print("Itu sudah default.")
            end
        elseif choice == "4" then
            local inst = InstanceManager.find(trim(prompt("Id / nama clone: ")))
            if not inst then
                print("Clone tidak ditemukan.")
            else
                local v = trim(prompt("Kode preset khusus, 'd' = ikut default, '-' = pakai link sendiri: "))
                local ok = true
                if v == "d" or v == "D" then
                    inst.preset = nil
                elseif v == "-" then
                    if not inst.privateServer or inst.privateServer == "" then
                        local l = trim(prompt("Link sendiri untuk clone ini: "))
                        if validLink(l) then inst.privateServer = l else print("Link tidak valid."); ok = false end
                    end
                    if ok then inst.preset = "-" end
                elseif presets(conf)[v] then
                    inst.preset = v
                else
                    print("Pilihan tidak valid."); ok = false
                end
                if ok and save(conf) then offerRejoin({ inst.id }) end
            end
        elseif choice == "5" then
            local changed = {}
            for _, inst in ipairs(InstanceManager.getAll()) do
                if inst.preset ~= nil and inst.preset ~= "" then
                    inst.preset = nil
                    changed[#changed + 1] = inst.id
                end
            end
            if #changed == 0 then
                print("Semua clone sudah ikut default.")
            elseif save(conf) then
                offerRejoin(changed)
            end
        else
            print("Pilihan tidak dikenal.")
        end
    end
end

return CLI
