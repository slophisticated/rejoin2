local Config = require("core.config")
local InstanceManager = require("managers.instance")

-- Main Menu 11: game presets. A preset is a named game link (e.g. A = Grow a Garden,
-- B = Fisch); a clone that uses a preset joins its link, so switching games is one
-- choice instead of pasting links clone by clone. Every change is saved right away.

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
    local ok, err = Config.save(conf)
    print(ok and "Tersimpan." or ("Gagal menyimpan: " .. tostring(err)))
    return ok
end

-- Ask whether to rejoin now. The running engine (Menu 1 / boot) picks the request up
-- through data/rejoin_request.txt; without an engine the new link is used next launch.
local function offerRejoin(ids)
    if #ids == 0 then return end
    local v = trim(prompt("Rejoin clone itu sekarang? (y/n) [y] "))
    if v == "" or v:lower() == "y" then
        local Monitor = require("managers.monitor")
        if Monitor.requestRejoinFile(ids) then
            print("Diminta. Engine yang jalan akan rejoin satu per satu; kalau engine tidak jalan, link baru dipakai di Launch All berikutnya.")
        end
    end
end

local function show(conf)
    local ps = presets(conf)
    print("\nPreset Game:")
    local keys = sortedKeys(ps)
    if #keys == 0 then print("  (belum ada preset)") end
    for _, k in ipairs(keys) do
        local p = ps[k]
        print(string.format("  [%s] %s\n      %s", k, tostring(p.name or ""), tostring(p.link or "")))
    end
    print("Clone:")
    for _, inst in ipairs(InstanceManager.getAll()) do
        local key = inst.preset
        local label = (key and ps[key]) and ("[" .. key .. "] " .. tostring(ps[key].name or "")) or "link sendiri"
        print(string.format("  %s) %s -> %s", tostring(inst.id), tostring(inst.name or inst.package), label))
    end
end

local function pickPreset(conf, label)
    local ps = presets(conf)
    local key = trim(prompt(label))
    if key == "" then return nil end
    if not ps[key] then print("Preset '" .. key .. "' tidak ada."); return nil end
    return key
end

function CLI.run()
    local conf = Config.get() or {}
    while true do
        show(conf)
        print("\n  1) Tambah / ubah preset")
        print("  2) Hapus preset")
        print("  3) Atur preset satu clone")
        print("  4) Ganti SEMUA clone ke satu preset")
        print("  0) Kembali")
        local choice = trim(prompt("Pilih: ") or "0")

        if choice == "0" or choice == "" then
            return
        elseif choice == "1" then
            local key = trim(prompt("Kode preset (mis. A, B, fisch): "))
            if not key:match("^[%w_%-]+$") or #key > 16 then
                print("Kode harus huruf/angka, maks 16.")
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
                    if save(conf) then
                        local used = {}
                        for _, inst in ipairs(InstanceManager.getAll()) do
                            if inst.preset == key then used[#used + 1] = inst.id end
                        end
                        if old.link and old.link ~= link then offerRejoin(used) end
                    end
                end
            end
        elseif choice == "2" then
            local key = pickPreset(conf, "Kode preset yang dihapus: ")
            if key then
                presets(conf)[key] = nil
                local n = 0
                for _, inst in ipairs(InstanceManager.getAll()) do
                    if inst.preset == key then inst.preset = nil; n = n + 1 end
                end
                conf.instances = InstanceManager.getAll()
                save(conf)
                if n > 0 then print(n .. " clone kembali pakai link sendiri.") end
            end
        elseif choice == "3" then
            local inst = InstanceManager.find(trim(prompt("Id / nama clone: ")))
            if not inst then
                print("Clone tidak ditemukan.")
            else
                local v = trim(prompt("Kode preset ('-' = pakai link sendiri): "))
                if v == "-" then
                    inst.preset = nil
                elseif presets(conf)[v] then
                    inst.preset = v
                else
                    print("Preset tidak ada."); v = nil
                end
                if v then
                    conf.instances = InstanceManager.getAll()
                    if save(conf) then offerRejoin({ inst.id }) end
                end
            end
        elseif choice == "4" then
            local key = pickPreset(conf, "Kode preset untuk semua clone: ")
            if key then
                local ids = {}
                for _, inst in ipairs(InstanceManager.getAll()) do
                    inst.preset = key
                    ids[#ids + 1] = inst.id
                end
                conf.instances = InstanceManager.getAll()
                if save(conf) then offerRejoin(ids) end
            end
        else
            print("Pilihan tidak dikenal.")
        end
    end
end

return CLI
