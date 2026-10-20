local GoFileAPK = require("managers.gofile_apk")

local CLI = {}

local function prompt(message)
    io.write(message)
    io.flush()
    return io.read()
end

local function trim(value)
    return (tostring(value or ""):match("^%s*(.-)%s*$"))
end

local function hiddenToken()
    io.write("Token API GoFile (input disembunyikan): ")
    io.flush()
    os.execute("stty -echo 2>/dev/null")
    local ok, token = pcall(io.read, "*l")
    os.execute("stty sane 2>/dev/null")
    os.execute("stty echo icanon opost onlcr 2>/dev/null")
    io.write("\r\n")
    io.flush()
    if not ok then return "" end
    return trim(token)
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
    print("\nDownload & Install APK dari GoFile")
    print("Gunakan link folder/file GoFile yang kamu percaya. Hanya file .apk yang ditampilkan.")
    local link = trim(prompt("Link GoFile: "))
    if link == "" then print("Dibatalkan."); return end

    local apiToken
    local files, err = GoFileAPK.list(link)
    if not files and err == "AUTH_REQUIRED" then
        print("GoFile meminta autentikasi API untuk membaca daftar file.")
        apiToken = hiddenToken()
        if apiToken == "" then print("Dibatalkan."); return end
        if #apiToken > 512 or apiToken:find("[%c%s]") then
            print("Format token API GoFile tidak valid.")
            apiToken = nil
            return
        end
        files, err = GoFileAPK.list(link, apiToken)
    end
    if not files then
        print("Gagal membaca GoFile: " .. tostring(err))
        if err == "AUTH_REQUIRED" then
            print("API GoFile membutuhkan token; beberapa endpoint mungkin memerlukan akun Premium.")
        end
        return
    end

    print("\nAPK ditemukan:")
    for i, item in ipairs(files) do
        local folder = item.folder and item.folder ~= "GoFile" and (" [" .. item.folder .. "]") or ""
        print(string.format("  %d) %s%s — %s", i, tostring(item.name), folder, GoFileAPK.describe(item)))
    end
    if #files >= 100 then print("Daftar dibatasi sampai 100 APK pertama.") end

    local selection = prompt("Pilih nomor/rentang (contoh 1-3, atau 0 batal): ")
    if trim(selection) == "0" then print("Dibatalkan."); apiToken = nil; return end
    local selected, selectionErr = parseSelection(selection, #files)
    if not selected then print(selectionErr); apiToken = nil; return end

    for n, index in ipairs(selected) do
        local item = files[index]
        print(string.format("\n[%d/%d] Download dan install %s...", n, #selected, tostring(item.name)))
        local ok, result = GoFileAPK.downloadAndInstall(item, index, apiToken)
        if ok then print(tostring(result))
        else print("Gagal: " .. tostring(result)) end
    end
    apiToken = nil
end

return CLI
