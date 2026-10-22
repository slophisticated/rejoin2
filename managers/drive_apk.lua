local JSON = require("utils.json")
local Shell = require("utils.shell")

local DriveAPK = {}

local MAX_FILES = 100
local MAX_DEPTH = 5
local MAX_BYTES = 2 * 1024 * 1024 * 1024
local DOWNLOAD_DIR = "/sdcard/Download/Rejoin"
local resolvedCurl = false

local function shq(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function curlPath()
    if resolvedCurl then return resolvedCurl end
    local prefix = os.getenv("PREFIX") or "/data/data/com.termux/files/usr"
    local candidates = { prefix:gsub("/+$", "") .. "/bin/curl", "/data/data/com.termux/files/usr/bin/curl", "/system/bin/curl" }
    local seen = {}
    for _, candidate in ipairs(candidates) do
        if not seen[candidate] then
            seen[candidate] = true
            local ok, _, code = os.execute("test -x " .. shq(candidate) .. " >/dev/null 2>&1")
            if ok == true or code == 0 then resolvedCurl = candidate; return candidate end
        end
    end
    local ok, _, code = os.execute("command -v curl >/dev/null 2>&1")
    if ok == true or code == 0 then resolvedCurl = "curl"; return resolvedCurl end
    return nil
end

local function runCapture(cmd, quiet)
    local outputPath = os.tmpname()
    local full = cmd .. " > " .. shq(outputPath)
    if quiet ~= false then full = full .. " 2>/dev/null" end
    local ok, why, code = os.execute(full)
    local f = io.open(outputPath, "r")
    local output = f and (f:read("*a") or "") or nil
    if f then f:close() end
    os.remove(outputPath)
    if output == nil then
        return nil, "curl gagal dijalankan (" .. tostring(why or "shell") .. ", exit " .. tostring(code or "?")
            .. "); pastikan curl terpasang di Termux."
    end
    return output, ok == true or code == 0, code
end

local function urlEncode(value)
    return (tostring(value):gsub("([^%w%-_%.~])", function(ch) return string.format("%%%02X", ch:byte()) end))
end

local function urlDecode(value)
    return (tostring(value or ""):gsub("%+", " "):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function parseFolderLink(link)
    if type(link) ~= "string" then return nil, "Masukkan link folder Google Drive." end
    link = link:match("^%s*(.-)%s*$")
    local scheme, host, rest = link:match("^(https?)://([^/%?#]+)(.*)$")
    if scheme ~= "https" or not host or host:lower() ~= "drive.google.com" then
        return nil, "Masukkan link folder resmi drive.google.com."
    end
    local path, query = rest:match("^([^?]*)%?(.*)$")
    if not path then path, query = rest, "" end
    local id = path:match("/drive/folders/([%w_-]+)") or path:match("/folders/([%w_-]+)")
    local resourceKey
    for pair in (query .. "&"):gmatch("(.-)&") do
        local key, value = pair:match("^([^=]+)=(.*)$")
        key, value = urlDecode(key):lower(), urlDecode(value)
        if key == "id" and not id then id = value end
        if key == "resourcekey" then resourceKey = value end
    end
    if not id then return nil, "ID folder Google Drive tidak terbaca dari link." end
    if not id:match("^[%w_-]+$") or (resourceKey and not resourceKey:match("^[%w_-]+$")) then
        return nil, "ID folder atau resource key pada link Google Drive tidak valid."
    end
    return id, resourceKey
end

local function apiRequest(url, apiKey, fileId, resourceKey, pageToken)
    local curl = curlPath()
    if not curl then return nil, "curl tidak ditemukan. Jalankan `pkg install curl` di Termux." end
    local headerPath = os.tmpname()
    local f = io.open(headerPath, "w")
    if not f then return nil, "Tidak bisa menyiapkan header Google Drive." end
    f:write("X-Goog-Api-Key: ", apiKey, "\n")
    if fileId and resourceKey then f:write("X-Goog-Drive-Resource-Keys: ", fileId, "/", resourceKey, "\n") end
    f:close()
    pcall(function() os.execute("chmod 600 " .. shq(headerPath)) end)
    local args = { shq(curl), "-sS", "-L", "--max-time", "30", "-w", shq("\nHTTP_STATUS:%{http_code}"), "-H", shq("@" .. headerPath) }
    if pageToken then args[#args + 1] = "--get"; args[#args + 1] = "--data-urlencode"; args[#args + 1] = "pageToken=" .. shq(pageToken) end
    args[#args + 1] = shq(url)
    local output, ok, code = runCapture(table.concat(args, " "))
    os.remove(headerPath)
    if not output then return nil, ok end
    local body, statusText = output:match("^(.*)\nHTTP_STATUS:(%d%d%d)%s*$")
    local status = tonumber(statusText)
    if not ok or not status or status < 200 or status >= 300 then
        local decoded = JSON.decode(body or "")
        local message = type(decoded) == "table" and decoded.error and decoded.error.message
        if status == 403 and tostring(message):lower():find("api key", 1, true) then
            return nil, "API_KEY_INVALID"
        end
        if status == 403 then return nil, "Google Drive menolak akses. Pastikan folder dibagikan ke siapa saja yang memiliki link dan API key mengaktifkan Drive API." end
        if status == 404 then return nil, "Folder tidak ditemukan atau link/resource key tidak cocok." end
        return nil, "Google Drive gagal merespons (HTTP " .. tostring(status or code or "?") .. ")."
    end
    local decoded, err = JSON.decode(body or "")
    if type(decoded) ~= "table" then return nil, "Respons Google Drive tidak valid: " .. tostring(err) end
    return decoded
end

local function listChildren(folderId, resourceKey, apiKey, pageToken)
    local query = "'" .. folderId .. "' in parents and trashed = false"
    local fields = "nextPageToken,files(id,name,mimeType,size,resourceKey)"
    local url = "https://www.googleapis.com/drive/v3/files?q=" .. urlEncode(query)
        .. "&fields=" .. urlEncode(fields) .. "&pageSize=1000"
    local all, token = {}, pageToken
    repeat
        local page, err = apiRequest(url, apiKey, folderId, resourceKey, token)
        if not page then return nil, err end
        for _, item in ipairs(page.files or {}) do all[#all + 1] = item end
        token = page.nextPageToken
    until not token
    return all
end

local function fileList(folderId, folderKey, apiKey)
    local files, visited = {}, {}
    local function scan(id, key, folder, depth)
        if #files >= MAX_FILES or depth > MAX_DEPTH or visited[id] then return end
        visited[id] = true
        local children, err = listChildren(id, key, apiKey)
        if not children then error(err, 0) end
        table.sort(children, function(a, b) return tostring(a.name or ""):lower() < tostring(b.name or ""):lower() end)
        for _, item in ipairs(children) do
            if item.mimeType == "application/vnd.google-apps.folder" and item.id then
                scan(item.id, item.resourceKey, table.concat({ folder, item.name or item.id }, "/"), depth + 1)
            elseif type(item.name) == "string" and item.name:lower():match("%.apk$") and type(item.id) == "string" then
                item.folder = folder
                files[#files + 1] = item
                if #files >= MAX_FILES then break end
            end
        end
    end
    local ok, err = pcall(scan, folderId, folderKey, "Google Drive", 0)
    if not ok then return nil, tostring(err) end
    return files
end

function DriveAPK.list(link, apiKey)
    local folderId, resourceKeyOrError = parseFolderLink(link)
    if not folderId then return nil, resourceKeyOrError end
    if type(apiKey) ~= "string" or apiKey == "" then return nil, "API_KEY_REQUIRED" end
    local folderKey = resourceKeyOrError
    local metadataUrl = "https://www.googleapis.com/drive/v3/files/" .. folderId .. "?fields="
        .. urlEncode("id,name,mimeType,resourceKey")
    local metadata, err = apiRequest(metadataUrl, apiKey, folderId, folderKey)
    if not metadata then return nil, err end
    if metadata.mimeType ~= "application/vnd.google-apps.folder" then
        return nil, "Link Google Drive harus menunjuk ke folder, bukan file."
    end
    local files, listErr = fileList(folderId, metadata.resourceKey or folderKey, apiKey)
    if not files then return nil, listErr end
    if #files == 0 then return nil, "Tidak ada file APK di folder Google Drive tersebut." end
    return files
end

function DriveAPK.describe(item)
    local bytes = tonumber(item.size) or 0
    if bytes >= 1024 * 1024 * 1024 then return string.format("%.2f GB", bytes / (1024 * 1024 * 1024)) end
    if bytes >= 1024 * 1024 then return string.format("%.1f MB", bytes / (1024 * 1024)) end
    return string.format("%.0f KB", bytes / 1024)
end

local function safeName(name)
    name = tostring(name or "apk"):gsub("[/\\]", "_"):gsub("[^%w%._%- ]", "_")
    name = name:gsub("^%.+", ""):sub(1, 100)
    if name == "" or name == "." or name == ".." then name = "update.apk" end
    if not name:lower():match("%.apk$") then name = name .. ".apk" end
    return name
end

local function zipFile(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local head = f:read(4) or ""
    f:close()
    return head:sub(1, 2) == "PK"
end

local function isGoogleDownloadUrl(url)
    local scheme, host = tostring(url or ""):match("^(https?)://([^/:?#]+)")
    host = host and host:lower()
    return scheme == "https" and host and (host == "google.com" or host:match("%.google%.com$")
        or host == "googleusercontent.com" or host:match("%.googleusercontent%.com$")) ~= nil
end

local function download(item, index)
    local curl = curlPath()
    if not curl then return nil, "curl tidak ditemukan. Jalankan `pkg install curl` di Termux." end
    local made = os.execute("mkdir -p " .. shq(DOWNLOAD_DIR))
    if made ~= true and made ~= 0 then return nil, "Folder Download tidak bisa dibuat." end
    local path = DOWNLOAD_DIR .. "/" .. tostring(os.time()) .. "_" .. tostring(index) .. "_" .. safeName(item.name)
    local cookiePath = os.tmpname()
    pcall(function() os.execute("chmod 600 " .. shq(cookiePath)) end)
    local url = "https://drive.google.com/uc?export=download&id=" .. urlEncode(item.id)
    if item.resourceKey then url = url .. "&resourcekey=" .. urlEncode(item.resourceKey) end
    local function fetch(target)
        local cmd = table.concat({ shq(curl), "-sS", "-fL", "--show-error", "--proto", "'=https'", "--proto-redir", "'=https'",
            "--max-time", "1800", "--max-filesize", tostring(MAX_BYTES), "--cookie", shq(cookiePath), "--cookie-jar", shq(cookiePath),
            "-o", shq(path), "-w", shq("EFFECTIVE_URL:%{url_effective}"), shq(target) }, " ")
        return runCapture(cmd, false)
    end
    local out, ok = fetch(url)
    if not zipFile(path) then
        local html
        local f = io.open(path, "r")
        html = f and (f:read("*a") or "") or ""
        if f then f:close() end
        local confirm = html:match('[?&]confirm=([%w_%-]+)') or html:match('name="confirm" value="([%w_%-]+)"')
        if confirm then
            out, ok = fetch(url .. "&confirm=" .. urlEncode(confirm))
        end
    end
    os.remove(cookiePath)
    local effective = out and out:match("EFFECTIVE_URL:(%S+)")
    if not ok or not zipFile(path) or not isGoogleDownloadUrl(effective) then
        os.remove(path)
        return nil, "Download gagal, butuh izin folder, atau Google menampilkan halaman konfirmasi: " .. tostring(item.name)
    end
    local f = io.open(path, "rb")
    local size = f and f:seek("end") or 0
    if f then f:close() end
    if not size or size <= 0 or size > MAX_BYTES then os.remove(path); return nil, "Ukuran APK tidak valid." end
    return path
end

function DriveAPK.downloadAndInstall(item, index)
    local path, err = download(item, index)
    if not path then return false, err end
    local staged = "/data/local/tmp/rejoin_drive_" .. tostring(os.time()) .. "_" .. tostring(index) .. ".apk"
    local install = "cp " .. shq(path) .. " " .. shq(staged)
        .. " && pm install -r --user current " .. shq(staged)
        .. "; result=$?; rm -f " .. shq(staged) .. "; exit $result"
    local ok, out = Shell.exec("sh -c " .. shq(install))
    if not ok or not tostring(out):find("Success", 1, true) then
        return false, "APK terunduh di " .. path .. ", tetapi instalasi gagal: " .. tostring(out)
    end
    local removed, removeErr = os.remove(path)
    if not removed then return true, "APK berhasil dipasang; file unduhan gagal dihapus (" .. tostring(removeErr) .. "): " .. path end
    return true, "APK berhasil dipasang dan file unduhan dihapus."
end

return DriveAPK
