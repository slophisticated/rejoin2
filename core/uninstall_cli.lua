local Uninstall = require("managers.uninstall")
local Paths = require("core.paths")

-- Main Menu 16: Uninstall. Everything is listed first and only removed after the
-- user types HAPUS. The repo folder itself stays (see managers/uninstall.lua).

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

function CLI.run()
    local targets = Uninstall.targets()

    -- A boot engine writes to data/ and would recreate files right after the wipe.
    local okM, Monitor = pcall(require, "managers.monitor")
    local other = okM and type(Monitor.otherEngine) == "function" and Monitor.otherEngine() or nil
    if other then
        print(string.format("\nPERINGATAN: engine lain masih jalan (pid %d, biasanya dari boot).", other))
        print("Stop dulu biar data/ ga dibikin ulang: kill -TERM " .. other)
    end

    print("\nUninstall rejoin")
    print("  Folder repo : " .. Paths.base())
    print("")
    print("  Yang akan DIHAPUS:")
    for _, t in ipairs(targets) do
        if t.path then
            print("    - " .. t.what)
            print("      " .. t.path)
        else
            print("    - " .. t.what)
        end
    end
    print("")
    print("  TIDAK disentuh: data app/clone, script AutoExecute lain, file lain di HP.")

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
    print("\nSelesai. Engine mati (menu tidak lanjut).")
    io.stdout:flush()
    os.exit(0)
end

return CLI
