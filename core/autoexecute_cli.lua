local AutoExecute = require("managers.autoexecute")

-- Main Menu 4: Script Manager. Scripts are stored in Delta's Scripts folder; the
-- Autoexecute folder only gets a COPY of a script from Scripts (never written to
-- directly). The Delta folder is shared by every clone on this device.

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Read multi-line script input from the terminal until a line that is exactly `END`
-- (the very last line). The `END` line is NOT stored / not executed.
local function readScript()
    local lines = {}
    while true do
        io.write("> ")
        io.flush()
        local line = io.read()
        if line == nil then return nil end                 -- EOF / Ctrl+D
        if line:match("^%s*END%s*$") then break end        -- terminal marker
        table.insert(lines, line)
    end
    return table.concat(lines, "\n") .. "\n"
end

local function show()
    print("\nScript Manager (berlaku untuk SEMUA clone di device ini)")
    print("Folder Scripts: " .. tostring(AutoExecute.scriptsDir() or "?"))
    local list, err = AutoExecute.scriptsList()
    if not list then
        print("  (tidak bisa dibaca: " .. tostring(err) .. ")")
    elseif #list == 0 then
        print("  (kosong — pilih 1 / 2 untuk menambah)")
    else
        for i, s in ipairs(list) do
            print(string.format("  %2d) %-32s %7d bytes %s", i, s.name, s.size, s.auto and "[AUTO]" or ""))
        end
    end
    local auto = AutoExecute.autoList() or {}
    local names = {}
    for _, s in ipairs(auto) do
        names[#names + 1] = s.name .. (s.managed and " (rejoin)" or (s.fromScripts and "" or " (tidak ada di Scripts)"))
    end
    print("Autoexecute: " .. (#names > 0 and table.concat(names, ", ") or "(kosong)"))
end

-- Pick a script of the Scripts folder by number or name.
local function pick(label)
    local list = AutoExecute.scriptsList() or {}
    local v = trim(prompt(label))
    if v == "" then return nil end
    local n = tonumber(v)
    if n and list[n] then return list[n].name end
    return v
end

local function offerRejoin()
    local v = trim(prompt("Rejoin semua clone biar langsung berlaku? (y/n) [n] "))
    if v:lower() == "y" then
        require("managers.monitor").requestRejoinFile({ "all" })
        print("Diminta. Engine yang jalan akan rejoin satu per satu.")
    else
        print("Berlaku saat clone masuk game berikutnya.")
    end
end

local function saveFlow(name, content)
    local n, replaced, autoUpdated = AutoExecute.scriptSave(name, content)
    if not n then print("Gagal: " .. tostring(replaced)); return end
    print((replaced and "Diganti: " or "Disimpan: ") .. n
        .. (autoUpdated and " (copy di Autoexecute ikut diperbarui)" or ""))
end

function CLI.run()
    while true do
        show()
        print("")
        print("  1) Tambah / ganti script (ketik, akhiri baris END)")
        print("  2) Tambah dari loadstring URL")
        print("  3) Hapus script dari Scripts")
        print("  4) Masukkan ke Autoexecute (copy dari Scripts)")
        print("  5) Keluarkan dari Autoexecute")
        print("  6) Edit script")
        print("  0) Kembali")
        local choice = prompt("Pilih: ")
        if choice == nil then
            print("\n(Input berakhir — kembali ke menu utama)")
            break
        end
        choice = trim(choice)
        if choice == "0" or choice == "" then
            break
        elseif choice == "1" then
            local name = trim(prompt("Nama script (mis. egg_farm): "))
            print("Tulis / paste kode script. Akhiri dengan baris `END` di paling bawah, lalu Enter:")
            local content = readScript()
            if content == nil then print("Input dibatalkan (EOF).") else saveFlow(name, content) end
        elseif choice == "2" then
            local name = trim(prompt("Nama script: "))
            local loader, err = AutoExecute.loaderFor(trim(prompt("URL script (https://...): ")))
            if not loader then print(err) else saveFlow(name, loader .. "\n") end
        elseif choice == "3" then
            local name = pick("Nomor / nama script yang dihapus: ")
            if name and trim(prompt("Hapus " .. name .. "? ketik 'yes': ")):lower() == "yes" then
                local n, stillAuto = AutoExecute.scriptRemove(name)
                if not n then print("Gagal: " .. tostring(stillAuto))
                else
                    print("Dihapus dari Scripts: " .. n)
                    if stillAuto then print("Catatan: copy-nya masih ada di Autoexecute (keluarkan lewat pilihan 5).") end
                end
            end
        elseif choice == "4" then
            local name = pick("Nomor / nama script untuk Autoexecute: ")
            if name then
                local n, err = AutoExecute.autoAdd(name)
                if n then print("Masuk Autoexecute: " .. n); offerRejoin() else print("Gagal: " .. tostring(err)) end
            end
        elseif choice == "5" then
            local name = trim(prompt("Nama script yang dikeluarkan dari Autoexecute: "))
            if name ~= "" then
                local n, err = AutoExecute.autoRemove(name)
                if n then print("Keluar dari Autoexecute: " .. n); offerRejoin() else print("Gagal: " .. tostring(err)) end
            end
        elseif choice == "6" then
            local name = pick("Nomor / nama script yang diedit: ")
            if name then
                local _, n = AutoExecute.scriptRead(name)
                if not n then print("Script tidak ada di Scripts.") else
                    print("Edit " .. n .. ". Tulis kode baru, akhiri dengan baris `END`:")
                    local content = readScript()
                    if content == nil then print("Input dibatalkan (EOF).") else saveFlow(n, content) end
                end
            end
        else
            print("Pilihan tidak dikenal.")
        end
    end
end

return CLI
