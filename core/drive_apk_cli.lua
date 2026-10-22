local DriveAPK = require("managers.drive_apk")

local CLI = {}

local function prompt(message)
    io.write(message)
    io.flush()
    return io.read()
end

local function trim(value)
    return (tostring(value or ""):match("^%s*(.-)%s*$"))
end

local function hiddenApiKey()
    io.write("Google Drive API key (input disembunyikan): ")
    io.flush()
    os.execute("stty -echo 2>/dev/null")
    local ok, key = pcall(io.read, "*l")
    os.execute("stty sane 2>/dev/null")
    os.execute("stty echo icanon opost onlcr 2>/dev/null")
    io.write("\r\n")
    io.flush()
    if not ok then return "" end
    return trim(key)
end

local function parseSelection(input, count)
    input = trim(input):lower()
    local picked, seen = {}, {}
    if input == "all" or input == "a" then
        for i = 1, count do picked[#picked + 1] = i end
        return picked
    end
    if input == "" then return nil, "Pilihan kosong." end
    for atom in input:gmatch("[^,%s]+") do
        local first, last = atom:match("^(%d+)%-(%d+)$")
        if first then
            first, last = tonumber(first), tonumber(last)
            if first > last then return nil, "Rentang harus urut dari kecil ke besar." end
        else
            first = tonumber(atom:match("^(%d+)$"))
            if not first then return nil, "Format pilihan tidak valid. Contoh: 1-3 atau 1,3,5." end
            last = first
        end
        if first < 1 or last > count then return nil, "Nomor pilihan di luar daftar." end
        for i = first, last do
            if not seen[i] then picked[#picked + 1] = i; seen[i] = true end
        end
    end
    if #picked == 0 then return nil, "Tidak ada APK yang dipilih." end
    table.sort(picked)
    return picked
end

function CLI.run()
    print("\nDownload & Install APK dari Google Drive")
    print("Folder harus dapat diakses siapa saja yang memiliki link. Hanya file .apk yang ditampilkan.")
    print("Aktifkan Google Drive API dan gunakan API key yang dibatasi untuk Drive API.")
    local link = trim(prompt("Link folder Google Drive: "))
    if link == "" then print("Dibatalkan."); return end

    local apiKey = os.getenv("GOOGLE_DRIVE_API_KEY") or ""
    if apiKey == "" then apiKey = hiddenApiKey() end
    if apiKey == "" then print("Dibatalkan."); return end
    if #apiKey > 512 or apiKey:find("[%c%s]") then
        print("Format API key tidak valid.")
        apiKey = nil
        return
    end

    local files, err = DriveAPK.list(link, apiKey)
    if not files then
        print("Gagal membaca Google Drive: " .. tostring(err))
        if err == "API_KEY_INVALID" then print("Cek API key dan pastikan Google Drive API aktif di project Google Cloud.") end
        apiKey = nil
        return
    end

    print("\nAPK ditemukan:")
    for i, item in ipairs(files) do
        local folder = item.folder and item.folder ~= "Google Drive" and (" [" .. item.folder .. "]") or ""
        print(string.format("  %d) %s%s — %s", i, tostring(item.name), folder, DriveAPK.describe(item)))
    end
    if #files >= 100 then print("Daftar dibatasi sampai 100 APK pertama.") end

    local selection = prompt("Pilih nomor/rentang (contoh 1-3, atau 0 batal): ")
    if trim(selection) == "0" then print("Dibatalkan."); apiKey = nil; return end
    local selected, selectionErr = parseSelection(selection, #files)
    if not selected then print(selectionErr); apiKey = nil; return end

    for _, index in ipairs(selected) do
        local item = files[index]
        print(string.format("\n[%d/%d] Download dan install %s...", index, #selected, tostring(item.name)))
        local ok, result = DriveAPK.downloadAndInstall(item, index)
        if ok then print(tostring(result))
        else print("Gagal: " .. tostring(result)) end
    end
    apiKey = nil
end

return CLI
