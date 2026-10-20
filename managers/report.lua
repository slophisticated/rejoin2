local Config = require("core.config")
local File = require("utils.file")

-- One error report for everything (Main Menu 4 -> 1, or `lua main.lua --report`).
--
-- Collects device / rejoin info plus the recent errors and activity of every log
-- (data/rejoin.log, data/boot.log with the update lines, data/crash.log, launch.log,
-- data/username_scan.log) into one text, saved to data/report.txt and
-- /sdcard/Download/rejoin-report.txt and copied to the clipboard, so it can be pasted
-- straight into a chat. Secrets are masked first: webhook URLs, the bot secret, the
-- HWID (it logs the device in to the bot), Roblox cookies and bearer tokens.

local Report = {}

local MAX_CHARS = 60000
local SAVE_PATHS = { "data/report.txt", "/sdcard/Download/rejoin-report.txt" }

local function sh(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return "" end
    local out = p:read("*a") or ""
    p:close()
    return (out:gsub("%s+$", ""))
end

local function lines(path)
    local content = path and File.read(path)
    local out = {}
    for l in (content or ""):gmatch("[^\r\n]+") do out[#out + 1] = l end
    return out
end

-- Last `n` lines of `list` (that pass `keep`, when given).
local function tail(list, n, keep)
    local picked = {}
    for i = #list, 1, -1 do
        if not keep or keep(list[i]) then
            table.insert(picked, 1, list[i])
            if #picked >= n then break end
        end
    end
    return picked
end

local function isProblem(l)
    return l:find("[ERROR]", 1, true) or l:find("[WARN]", 1, true) or l:find("ERROR", 1, true)
        or l:find("GAGAL", 1, true) or l:find("gagal", 1, true) or l:find("traceback", 1, true)
        or l:find("[!!]", 1, true)
end

local function plain(s) return (tostring(s):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- Mask everything that must not leave the device.
function Report.redact(text, secrets)
    text = text:gsub("https?://[%w%.%-]*discord[%w%.%-]*/api/webhooks/[^%s\"'<>]+", "[webhook]")
    text = text:gsub("_|WARNING:%-DO%-NOT%-SHARE%-THIS[^%s\"';]*", "[cookie]")
    text = text:gsub("%.ROBLOSECURITY=[^%s;\"']+", ".ROBLOSECURITY=[cookie]")
    text = text:gsub("[Bb]earer%s+[^%s\"']+", "Bearer [secret]")
    for label, value in pairs(secrets or {}) do
        if type(value) == "string" and #value >= 8 then text = text:gsub(plain(value), "[" .. label .. "]") end
    end
    return text
end

local function deviceId()
    return (File.read("data/device_id.txt") or ""):gsub("%s+", "")
end

local function engineRunning()
    local pid = tonumber((File.read("data/monitor.pid") or ""):match("%d+") or "")
    if not pid then return "tidak" end
    local cmd = File.read("/proc/" .. pid .. "/cmdline")
    return (cmd and cmd:find("main.lua", 1, true)) and ("jalan (pid " .. pid .. ")") or "tidak"
end

local function section(out, title, list)
    out[#out + 1] = ""
    out[#out + 1] = "== " .. title .. " =="
    if #list == 0 then out[#out + 1] = "(kosong)" end
    for _, l in ipairs(list) do out[#out + 1] = l end
end

function Report.build()
    local conf = Config.get() or {}
    local remote = type(conf.remote) == "table" and conf.remote or {}
    local webhook = type(conf.webhook) == "table" and conf.webhook or {}
    local hb = type(conf.heartbeat) == "table" and conf.heartbeat or {}
    local okW, Webhook = pcall(require, "managers.webhook")
    local label = okW and Webhook.deviceLabel and select(2, pcall(Webhook.deviceLabel)) or "-"
    local logPath = conf.logPath or "data/rejoin.log"
    local launchLog = conf.launchLogPath or "launch.log"

    local out = {
        "===== Rejoin report =====",
        "Waktu      : " .. os.date("%Y-%m-%d %H:%M:%S"),
        "Device     : " .. tostring(label),
        "Rejoin     : " .. sh("git rev-parse --short HEAD") .. " (" .. sh("git log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M'") .. ")",
        "Android    : " .. sh("getprop ro.build.version.release") .. " · " .. sh("getprop ro.product.model"),
        "Lua        : " .. tostring(_VERSION) .. " · Termux " .. (os.getenv("TERMUX_VERSION") or "?"),
        "Engine     : " .. engineRunning(),
        "Executor   : " .. tostring(conf.appAutoExecutePath or "-") .. " · heartbeat " .. (hb.enabled == false and "mati" or "nyala"),
        "Bot        : " .. ((tostring(remote.url or ""):match("^https?://([^/]+)")) or "URL kosong")
            .. " · secret " .. ((remote.secret or "") ~= "" and "ada" or "kosong"),
        "Webhook    : " .. ((webhook.url or "") ~= "" and "diset" or "kosong"),
        "RAM        : " .. (sh("grep -E 'MemTotal|MemAvailable' /proc/meminfo | tr -s ' ' | tr '\\n' ' '")),
        "Penyimpanan: " .. sh("df -h \"$HOME\" | tail -1 | tr -s ' '"),
    }
    local okI, Instances = pcall(require, "managers.instance")
    local clones = okI and Instances.getAll and Instances.getAll() or {}
    out[#out + 1] = "Clone      : " .. #clones
    for _, inst in ipairs(clones) do
        out[#out + 1] = string.format("  - %s · %s · preset %s", tostring(inst.name or inst.id), tostring(inst.package),
            tostring(inst.preset or "default"))
    end

    local main = lines(logPath)
    section(out, "ERROR / WARN terakhir (" .. logPath .. ")", tail(main, 60, isProblem))
    section(out, "Crash Lua (data/crash.log)", tail(lines("data/crash.log"), 40))
    section(out, "Boot + update (data/boot.log)", tail(lines("data/boot.log"), 40))
    section(out, "Aktivitas terakhir (" .. logPath .. ")", tail(main, 80))
    section(out, "Launch (" .. launchLog .. ")", tail(lines(launchLog), 25))
    section(out, "Username scan (data/username_scan.log)", tail(lines("data/username_scan.log"), 10, isProblem))

    local text = Report.redact(table.concat(out, "\n"), {
        secret = remote.secret, hwid = deviceId(), webhook = webhook.url,
    })
    if #text > MAX_CHARS then
        -- Keep the head (device info + errors), cut the long activity part.
        text = text:sub(1, MAX_CHARS) .. "\n... (dipotong, lengkapnya di data/report.txt)"
    end
    return text .. "\n===== akhir report =====\n"
end

-- Base64 for the OSC 52 clipboard fallback.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function Report.base64(s)
    return ((s:gsub(".", function(c)
        local byte, bits = c:byte(), ""
        for i = 8, 1, -1 do bits = bits .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0") end
        return bits
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local n = 0
        for i = 1, 6 do n = n + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
        return B64:sub(n + 1, n + 1)
    end) .. ({ "", "==", "=" })[#s % 3 + 1])
end

-- Copy to the clipboard: Termux:API when installed (timeout: it hangs without the
-- app), else the terminal's OSC 52 sequence. Returns ok, how.
function Report.copy(text, path)
    if sh("command -v termux-clipboard-set") ~= "" then
        local ok = os.execute("timeout 10 termux-clipboard-set < '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null")
        if ok == true or ok == 0 then return true, "termux-clipboard-set" end
    end
    if #text <= 100000 then
        io.write("\27]52;c;" .. Report.base64(text) .. "\7")
        io.flush()
        return true, "terminal (OSC 52)"
    end
    return false, "report kegedean buat clipboard"
end

-- Build, save, copy. Returns the text and status lines for the user.
function Report.run()
    local text = Report.build()
    local saved = {}
    for _, p in ipairs(SAVE_PATHS) do
        local ok = File.write(p, text)
        if ok then saved[#saved + 1] = p end
    end
    local status = {}
    if #saved > 0 then
        status[#status + 1] = "Report disimpan: " .. table.concat(saved, ", ")
        local ok, how = Report.copy(text, saved[1])
        status[#status + 1] = ok and ("Report di-copy ke clipboard (" .. how .. "), tinggal paste.")
            or ("Gagal copy ke clipboard (" .. how .. "); buka file di atas.")
    else
        status[#status + 1] = "Report gagal disimpan (izin storage?)."
    end
    return text, status
end

return Report
