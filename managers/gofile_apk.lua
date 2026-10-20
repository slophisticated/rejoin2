local JSON = require("utils.json")
local Shell = require("utils.shell")

local GoFileAPK = {}

local MAX_FILES = 100
local MAX_DEPTH = 5
local MAX_BYTES = 2 * 1024 * 1024 * 1024
local DOWNLOAD_DIR = "/sdcard/Download/Rejoin"

local function shq(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function termuxCurl()
    local prefix = os.getenv("PREFIX") or "/data/data/com.termux/files/usr"
    local candidate = prefix:gsub("/+$", "") .. "/bin/curl"
    local f = io.open(candidate, "r")
    if f then f:close(); return candidate end
    return "curl"
end

local function runCapture(cmd, quiet)
    if quiet ~= false then cmd = cmd .. " 2>/dev/null" end
    if not f then return nil, "curl tidak bisa dijalankan; pastikan curl terpasang" end
    local out = f:read("*a") or ""
    local ok, _, code = f:close()
    return out, ok == true, code
end

local function extractId(link)
    if type(link) ~= "string" then return nil end
    link = link:match("^%s*(.-)%s*$")
    local scheme, host, path = link:match("^(https?)://([^/%?#]+)([^?#]*)")
    if not scheme or (host:lower() ~= "gofile.io" and host:lower() ~= "www.gofile.io") then
        return nil, "Masukkan link GoFile resmi (gofile.io), bukan link download langsung."
    end
    local id = path:match("^/d/([%w_-]+)") or path:match("^/download/([%w_-]+)")
    if not id then id = link:match("[?&]c=([%w_-]+)") end
    if not id or #id < 4 or #id > 128 then return nil, "ID folder GoFile tidak terbaca dari link." end
    return id
end

local function request(url, token, method, body)
    local curl = termuxCurl()
    local args = { shq(curl), "-sS", "-L", "--fail", "--max-time", "30", "-w", shq("\nHTTP_STATUS:%{http_code}") }
    local headerPath
    if token and token ~= "" then
        headerPath = os.tmpname()
        local f = io.open(headerPath, "w")
        if not f then return nil, "Tidak bisa menyiapkan autentikasi GoFile." end
        f:write("Authorization: Bearer ", token, "\n")
        f:close()
        pcall(function() os.execute("chmod 600 " .. shq(headerPath)) end)
        args[#args + 1] = "-H"
        args[#args + 1] = shq("@" .. headerPath)
    end
    if method then
        args[#args + 1] = "-X"
        args[#args + 1] = shq(method)
    end
    if body then
        args[#args + 1] = "-H"
        args[#args + 1] = shq("Content-Type: application/json")
        args[#args + 1] = "--data"
        args[#args + 1] = shq(body)
    end
    args[#args + 1] = shq(url)
    local out, ok, code = runCapture(table.concat(args, " "))
    if headerPath then os.remove(headerPath) end
    if not out then return nil, ok end
    local body, statusText = out:match("^(.*)\nHTTP_STATUS:(%d%d%d)%s*$")
    local status = tonumber(statusText)
    if status == 401 or status == 403 then return nil, "AUTH_REQUIRED" end
    if not ok or not status or status < 200 or status >= 300 then
        return nil, "GoFile gagal merespons (HTTP " .. tostring(status or code or "?") .. ")."
    end
    local decoded, err = JSON.decode(body or "")
    if type(decoded) ~= "table" then return nil, "Respons GoFile tidak valid: " .. tostring(err) end
    if decoded.status and decoded.status ~= "ok" then
        local message = type(decoded.data) == "table" and (decoded.data.error or decoded.data.message)
        local lowerMessage = tostring(message or ""):lower()
        if lowerMessage:find("auth", 1, true) or lowerMessage:find("token", 1, true) then
            return nil, "AUTH_REQUIRED"
        end
        return nil, tostring(message or decoded.status)
    end
    return decoded
end

local function fileList(data, token)
    local files = {}
    local visited = {}
    local function scan(folderId, folderName, depth, prefetched)
        if #files >= MAX_FILES or depth > MAX_DEPTH or visited[folderId] then return end
        visited[folderId] = true
        local response = prefetched
        if not response then
            local err
            response, err = request("https://api.gofile.io/contents/" .. folderId, token)
            if not response then error(err, 0) end
        end
        local root = response.data or response
        local children = root.children or {}
        local sorted = {}
        for _, item in pairs(children) do
            if type(item) == "table" then sorted[#sorted + 1] = item end
        end
        table.sort(sorted, function(a, b) return tostring(a.name or ""):lower() < tostring(b.name or ""):lower() end)
        for _, item in ipairs(sorted) do
            if type(item.id) == "string" and item.type == "folder" then
                scan(item.id, table.concat({ folderName, item.name or item.id }, "/"), depth + 1)
            elseif type(item.name) == "string" and item.name:lower():match("%.apk$") then
                item.folder = folderName
                files[#files + 1] = item
                if #files >= MAX_FILES then break end
            end
        end
    end
    local ok, err = pcall(scan, data.id, data.name or "GoFile", 0, data)
    if not ok then return nil, tostring(err) end
    return files
end

function GoFileAPK.list(link, token)
    local id, err = extractId(link)
    if not id then return nil, err end
    local response, requestErr = request("https://api.gofile.io/contents/" .. id, token)
    if not response then return nil, requestErr end
    local root = response.data or response
    if type(root) ~= "table" or type(root.id) ~= "string" then
        return nil, "Folder GoFile tidak ditemukan atau tidak bisa diakses."
    end
    local files, scanErr = fileList(root, token)
    if not files then return nil, scanErr end
    if #files == 0 then return nil, "Tidak ada file APK di link GoFile tersebut." end
    return files
end

local function safeDownloadUrl(url)
    if type(url) ~= "string" then return false end
    local scheme, host = url:match("^(https?)://([^/%?#]+)")
    host = host and host:lower()
    return scheme == "https" and host and (host == "gofile.io" or host:match("%.gofile%.io$") ~= nil)
end

local function directUrl(item, token)
    local candidate = item.directLink or item.link or item.downloadUrl
    if safeDownloadUrl(candidate) then return candidate end
    if type(item.id) == "string" and item.id:match("^[%w_-]+$") then
        local response = request("https://api.gofile.io/contents/" .. item.id .. "/directlinks", token, "POST", "{}")
        local data = response and response.data
        local direct = type(data) == "table" and (data.link or data.directLink or data.url)
        if type(direct) == "table" then direct = direct.link or direct.url end
        if safeDownloadUrl(direct) then return direct end
    end
    return nil
end

local function fileSize(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 * 1024 then return string.format("%.2f GB", bytes / (1024 * 1024 * 1024)) end
    if bytes >= 1024 * 1024 then return string.format("%.1f MB", bytes / (1024 * 1024)) end
    return string.format("%.0f KB", bytes / 1024)
end

function GoFileAPK.describe(item)
    return fileSize(item.size)
end

local function safeName(name)
    name = tostring(name or "apk"):gsub("[/\\]", "_"):gsub("[^%w%._%- ]", "_")
    name = name:gsub("^%.+", ""):sub(1, 100)
    if name == "" or name == "." or name == ".." then name = "update.apk" end
    if not name:lower():match("%.apk$") then name = name .. ".apk" end
    return name
end

local function fileStartsWithZip(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local head = f:read(4) or ""
    f:close()
    return head:sub(1, 2) == "PK"
end

local function download(item, index, token)
    local url = directUrl(item, token)
    if not url then return nil, "GoFile tidak memberikan tautan unduh aman untuk " .. tostring(item.name) end
    local made = os.execute("mkdir -p " .. shq(DOWNLOAD_DIR))
    if made ~= true and made ~= 0 then return nil, "Folder Download tidak bisa dibuat." end
    local stamp = tostring(os.time()) .. "_" .. tostring(index)
    local name = stamp .. "_" .. safeName(item.name)
    local path = DOWNLOAD_DIR .. "/" .. name
    local cmd = table.concat({ shq(termuxCurl()), "-fL", "--show-error", "--progress-bar", "--proto", "'=https'",
        "--proto-redir", "'=https'", "--max-time", "1800", "--max-filesize", tostring(MAX_BYTES),
        "-o", shq(path), "-w", shq("EFFECTIVE_URL:%{url_effective}"), shq(url) }, " ")
    local out, ok = runCapture(cmd, false)
    local effectiveUrl = out and out:match("EFFECTIVE_URL:(%S+)")
    if not ok or not safeDownloadUrl(effectiveUrl) or not fileStartsWithZip(path) then
        os.remove(path)
        return nil, "Download gagal atau file bukan APK ZIP yang valid: " .. tostring(item.name)
    end
    local f = io.open(path, "rb")
    local size = f and f:seek("end") or 0
    if f then f:close() end
    if not size or size <= 0 or size > MAX_BYTES then
        os.remove(path)
        return nil, "Ukuran APK tidak valid: " .. tostring(item.name)
    end
    return path
end

function GoFileAPK.downloadAndInstall(item, index, token)
    local path, err = download(item, index, token)
    if not path then return false, err end
    local staged = "/data/local/tmp/rejoin_gofile_" .. tostring(os.time()) .. "_" .. tostring(index) .. ".apk"
    local install = "cp " .. shq(path) .. " " .. shq(staged)
        .. " && pm install -r --user current " .. shq(staged)
        .. "; result=$?; rm -f " .. shq(staged) .. "; exit $result"
    local ok, out = Shell.exec("sh -c " .. shq(install))
    if not ok or not tostring(out):find("Success", 1, true) then
        return false, "APK terunduh di " .. path .. ", tetapi instalasi gagal: " .. tostring(out)
    end
    local removed, removeErr = os.remove(path)
    if not removed then
        return true, "APK berhasil dipasang; file unduhan gagal dihapus (" .. tostring(removeErr) .. "): " .. path
    end
    return true, "APK berhasil dipasang dan file unduhan dihapus."
end

return GoFileAPK
