local Uninstall = require("managers.uninstall")
local Paths = require("core.paths")

-- Submenu "Uninstall yanamin": one button that removes the auto-boot script,
-- the whole data root and (when it is the single-file loader) the loader file.
-- Everything is listed first and only happens after typing HAPUS.

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

function CLI.run()
    local targets = Uninstall.targets()

    print("\nUninstall yanamin")
    print("  Data root : " .. Paths.base())
    print("")
    print("  Yang akan DIHAPUS:")
    if #targets == 0 then
        print("    (tidak ada — belum ada data root, script boot, atau file loader)")
    else
        for _, t in ipairs(targets) do
            if t.path then
                print("    - " .. t.what)
                print("      " .. t.path)
            else
                print("    - " .. t.what)
            end
        end
    end
    print("")
    print("  TIDAK disentuh: data app/clone, script AutoExecute, file lain di HP.")

    print("\n  1) Hapus semua (butuh ketik HAPUS)")
    print("  2) Batal")

    local choice = (prompt("Choose: ") or ""):match("^%s*(.-)%s*$")
    if choice ~= "1" then
        print("\nDibatalkan.")
        return
    end

    local typed = (prompt("Ketik HAPUS untuk konfirmasi: ") or ""):match("^%s*(.-)%s*$")
    if typed ~= "HAPUS" then
        print("\nDibatalkan (konfirmasi tidak cocok).")
        return
    end

    print("\nMenghapus...")
    local results = Uninstall.runAll()
    for _, line in ipairs(results) do print("  " .. line) end
    print("\nSelesai. Keluar...")
    print("Kalau file loader ikut terhapus, unduh ulang untuk dipakai lagi.")
    io.stdout:flush()
    os.exit(0)
end

return CLI