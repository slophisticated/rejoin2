local Logger = require("core.logger")
local Shell = require("utils.shell")

-- Status reports to a Discord webhook.
--
-- Every `interval` seconds the monitor calls Webhook.tick(): one status message
-- (device, RAM / CPU / temperature, online count, uptime / memory / CPU per clone,
-- optional screenshot) is posted once and then EDITED in place, so the channel holds
-- a single live status. If that message was deleted, a new one is posted. Events
-- (engine start, kick, failed recovery) are sent as separate small messages.
--
-- Config:
--   webhook = {
--       url = "",          -- Discord webhook URL; "" = feature off (nothing runs)
--       interval = 300,    -- seconds between status updates
--       screenshot = true, -- attach a screenshot of the cloud phone
--       events = true,     -- separate messages for engine start / kick / failures
--       hideNames = true,  -- show account names as spoilers
--   }
--
-- curl runs as the Termux user (not through su), so the webhook URL never appears in
-- a root command line, and it is never written to the log.

local Webhook = {}

local conf = {}
local lastReport = 0
local firstReportAt = nil
local warned = {}
local eventLast = {}
local cpuPrev = nil      -- { total, idle }
local procPrev = {}      -- pkg -> { proc, total }
local STATE_FILE = "data/webhook_msg.txt"
local TMP = (os.getenv("PREFIX") or "/data/data/com.termux/files/usr") .. "/tmp"
local SHOT = TMP .. "/rejoin_ss.png"
local PAYLOAD = TMP .. "/rejoin_webhook.json"
local HZ = 100

local function warnOnce(key, msg)
    if warned[key] then return end
    warned[key] = true
    Logger.warn("Webhook: " .. msg)
end

function Webhook.configure(c)
    local w = type(c) == "table" and type(c.webhook) == "table" and c.webhook or {}
    conf = {
        url = type(w.url) == "string" and w.url:gsub("%s+", "") or "",
        interval = math.max(60, math.floor(tonumber(w.interval) or 300)),
        screenshot = w.screenshot ~= false,
        events = w.events ~= false,
        hideNames = w.hideNames ~= false,
    }
    if not conf.url:match("^https://[%w%.%-]+/api/webhooks/") then conf.url = "" end
    lastReport = 0
    firstReportAt = os.time() + 30
end

function Webhook.enabled()
    return conf.url ~= nil and conf.url ~= ""
end

-- JSON string escaping.
local function js(s)
    s = tostring(s or "")
    s = s:gsub('[%c"\\]', function(ch)
        if ch == '"' then return '\\"' end
        if ch == "\\" then return "\\\\" end
        if ch == "\n" then return "\\n" end
        if ch == "\r" then return "" end
        if ch == "\t" then return "\\t" end
        return string.format("\\u%04x", ch:byte())
    end)
    return '"' .. s .. '"'
end
Webhook._js = js

local function shQuote(v)
    return "'" .. tostring(v):gsub("'", "'\\''") .. "'"
end

-- Run curl as the Termux user. Returns http code (number or nil) and body.
local function curl(args)
    local cmd = "curl -s --max-time 25 -w '\\n%{http_code}' " .. args .. " </dev/null 2>/dev/null"
    local f = io.popen(cmd)
    if not f then return nil, "" end
    local out = f:read("*a") or ""
    f:close()
    local body, code = out:match("^(.-)\n?(%d%d%d)%s*$")
    return tonumber(code), body or out
end

local function writeFile(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function root(cmd)
    local ok, out = Shell.exec(cmd)
    if not ok or not out or out == "(dry-run)" then return nil end
    return out
end

-- System numbers ------------------------------------------------------------------
local function cpuTotals()
    local stat = root("cat /proc/stat")
    if not stat then return nil end
    local line = stat:match("^cpu%s+([^\n]+)")
    if not line then return nil end
    local nums = {}
    for n in line:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
    local total = 0
    for _, n in ipairs(nums) do total = total + n end
    local idle = (nums[4] or 0) + (nums[5] or 0)
    local cores = 0
    for _ in stat:gmatch("\ncpu%d+ ") do cores = cores + 1 end
    return total, idle, math.max(cores, 1)
end

local function systemStats()
    local s = {}
    s.device = (root("getprop ro.product.model") or ""):gsub("%s+$", "")
    if s.device == "" then s.device = "-" end

    local mem = root("cat /proc/meminfo") or ""
    local total = tonumber(mem:match("MemTotal:%s*(%d+)"))
    local avail = tonumber(mem:match("MemAvailable:%s*(%d+)"))
    if total and avail and total > 0 then
        s.ram = string.format("%dMB free (%d%%)", math.floor(avail / 1024), math.floor(avail * 100 / total))
    else
        s.ram = "-"
    end

    local t, idle, cores = cpuTotals()
    s.cores = cores or 1
    s.cpuTotal = t
    if t and cpuPrev and t > cpuPrev.total then
        local dt, di = t - cpuPrev.total, idle - cpuPrev.idle
        s.cpu = string.format("%d%%", math.floor((dt - di) * 100 / dt + 0.5))
    else
        s.cpu = "-"
    end
    if t then cpuPrev = { total = t, idle = idle } end

    local temps = root("cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null") or ""
    local best
    for n in temps:gmatch("%-?%d+") do
        local v = tonumber(n)
        if v and v > 1000 then v = v / 1000 end
        if v and v > 0 and v < 150 and (not best or v > best) then best = v end
    end
    s.temp = best and string.format("%.1f°C", best) or "-"

    s.uptime = tonumber((root("cat /proc/uptime") or ""):match("^(%d+%.?%d*)"))
    return s
end

local function fmtDuration(sec)
    sec = math.max(0, math.floor(sec or 0))
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

-- Uptime and CPU of one clone's main process, from /proc/<pid>/stat.
local function procStats(pkg, sys)
    if type(pkg) ~= "string" or not pkg:match("^[%w_%.]+$") then return nil end
    local pid = (root("pidof " .. pkg) or ""):match("(%d+)")
    if not pid then return nil end
    local stat = root("cat /proc/" .. pid .. "/stat")
    if not stat then return nil end
    local rest = stat:match("%)%s+(.*)$")
    if not rest then return nil end
    local f = {}
    for v in rest:gmatch("%S+") do f[#f + 1] = v end
    -- after ") ": state is field 3, utime 14, stime 15, starttime 22 (1-based in /proc docs)
    local utime, stime, start = tonumber(f[12]), tonumber(f[13]), tonumber(f[20])
    local r = {}
    if start and sys.uptime then r.uptime = sys.uptime - start / HZ end
    if utime and stime then
        local proc = utime + stime
        local prev = procPrev[pkg]
        if prev and sys.cpuTotal and sys.cpuTotal > prev.total and proc >= prev.proc then
            local share = (proc - prev.proc) / ((sys.cpuTotal - prev.total) / sys.cores)
            r.cpu = string.format("%.1f%%", share * 100)
        end
        procPrev[pkg] = { proc = proc, total = sys.cpuTotal or 0 }
    end
    return r
end

-- Report body ---------------------------------------------------------------------
local ICON = {
    ingame = "🟢", starting = "🟡", recovery = "🟡", resetting = "🟡",
    nologin = "⚪", kicked = "🔴", freeze = "🔴", stuck = "🔴", offline = "🔴",
}

local function buildReport(instances, sys, withImage)
    local okS, Status = pcall(require, "managers.status")
    local okU, Username = pcall(require, "managers.username")
    local okH, Heartbeat = pcall(require, "managers.heartbeat")
    local okA, APK = pcall(require, "managers.apk")

    local online, offline, nologin = 0, 0, 0
    local rows = {}
    for _, inst in ipairs(instances or {}) do
        local status = okS and Status.statusOf and Status.statusOf(inst.id) or "offline"
        status = status or "offline"
        if status == "ingame" then online = online + 1
        elseif status == "nologin" then nologin = nologin + 1
        else offline = offline + 1 end

        local name = okU and Username.get(inst) or nil
        if not name or tostring(name) == "" then name = inst.name or inst.package end
        name = tostring(name)
        if conf.hideNames then name = "||" .. name .. "||" end

        local p = procStats(inst.package, sys) or {}
        local memMb
        local hb = okH and Heartbeat.read and Heartbeat.read(inst) or nil
        if hb and hb.fresh and hb.mem and hb.mem > 0 then
            memMb = hb.mem
        elseif okA then
            local kb = APK.getRSSinKB(inst.package)
            if kb and kb > 0 then memMb = math.floor(kb / 1024) end
        end
        rows[#rows + 1] = string.format("%s %s\n└ ⏱️ %s | 💾 %s | ⚡ %s",
            ICON[status] or "⚪", name,
            p.uptime and fmtDuration(p.uptime) or "-",
            memMb and (memMb .. " MB") or "-",
            p.cpu or "-")
    end

    local now = os.time()
    local lines = {
        string.format("Last Updated: <t:%d:f> (<t:%d:R>)", now, now),
        "",
        "📱 **Device**", sys.device,
        "",
        "🖥️ **System Stats**",
        "💾 RAM: " .. sys.ram,
        "⚙️ CPU: " .. sys.cpu,
        "🌡️ Temp: " .. sys.temp,
        "",
        "**Status Overview**",
        "🟢 Online: " .. online,
        "🔴 Offline: " .. offline,
    }
    if nologin > 0 then lines[#lines + 1] = "⚪ Belum login: " .. nologin end
    lines[#lines + 1] = "🤖 Total: " .. #(instances or {})
    lines[#lines + 1] = ""
    lines[#lines + 1] = "**Application Details**"
    local desc = table.concat(lines, "\n")
    for i, r in ipairs(rows) do
        if #desc + #r + 40 > 4000 then
            desc = desc .. string.format("\n… +%d clone lagi", #rows - i + 1)
            break
        end
        desc = desc .. "\n" .. r
    end

    local color = 5763719 -- green
    if online == 0 then color = 15548997 elseif offline > 0 then color = 16705372 end
    local embed = '{"title":' .. js("📊 Rejoin Status Update")
        .. ',"description":' .. js(desc)
        .. ',"color":' .. color
        .. ',"timestamp":' .. js(os.date("!%Y-%m-%dT%H:%M:%SZ", now))
    if withImage then embed = embed .. ',"image":{"url":"attachment://rejoin_ss.png"}' end
    embed = embed .. "}"
    local payload = '{"embeds":[' .. embed .. ']'
    if withImage then
        payload = payload .. ',"attachments":[{"id":0,"filename":"rejoin_ss.png"}]'
    else
        payload = payload .. ',"attachments":[]'
    end
    return payload .. "}"
end
Webhook._buildReport = buildReport

local function screenshot()
    os.execute("mkdir -p " .. shQuote(TMP))
    local out = root("screencap -p " .. shQuote(SHOT) .. " && chmod 644 " .. shQuote(SHOT) .. " && echo SS_OK")
    if not out or not out:find("SS_OK", 1, true) then return false end
    local f = io.open(SHOT, "rb")
    if not f then return false end
    local size = f:seek("end")
    f:close()
    return size and size > 0
end

-- Message id of the status message we keep editing.
local function msgId()
    local s = readFile(STATE_FILE)
    return s and s:match("(%d+)")
end

-- The message's own "id": the "id" key of the top-level JSON object. Discord's key
-- order is not fixed and nested objects (author, attachments, embeds) have ids too,
-- so walk the JSON tracking depth instead of matching neighbours.
local function parseId(body)
    if type(body) ~= "string" then return nil end
    local depth, i, n = 0, 1, #body
    while i <= n do
        local c = body:sub(i, i)
        if c == '"' then
            local j = i + 1
            while j <= n do
                local cj = body:sub(j, j)
                if cj == "\\" then j = j + 2
                elseif cj == '"' then break
                else j = j + 1 end
            end
            if depth == 1 and body:sub(i + 1, j - 1) == "id" then
                local v = body:match('^%s*:%s*"(%d+)"', j + 1)
                if v then return v end
            end
            i = j + 1
        elseif c == "{" or c == "[" then
            depth = depth + 1
            i = i + 1
        elseif c == "}" or c == "]" then
            depth = depth - 1
            i = i + 1
        else
            i = i + 1
        end
    end
    return nil
end
Webhook._parseId = parseId

local function send(payload, withImage, method, url)
    if not writeFile(PAYLOAD, payload) then
        os.execute("mkdir -p " .. shQuote(TMP))
        if not writeFile(PAYLOAD, payload) then return nil, "" end
    end
    local args = "-X " .. method .. " "
    if withImage then
        args = args .. "-F " .. shQuote("payload_json=<" .. PAYLOAD)
            .. " -F " .. shQuote("files[0]=@" .. SHOT .. ";filename=rejoin_ss.png;type=image/png")
    else
        args = args .. "-H 'Content-Type: application/json' --data-binary " .. shQuote("@" .. PAYLOAD)
    end
    return curl(args .. " " .. shQuote(url))
end

-- Post or edit the status message now.
-- CPU numbers need two samples. Before the very first report, take one and wait a
-- moment, so the first report already shows CPU instead of "-".
local function primeCpu(instances)
    local t, idle, cores = cpuTotals()
    if not t then return end
    cpuPrev = { total = t, idle = idle }
    local sys = { cpuTotal = t, cores = cores }
    for _, inst in ipairs(instances or {}) do
        pcall(procStats, inst.package, sys)
    end
    os.execute("sleep 2")
end

function Webhook.report(instances)
    if not Webhook.enabled() then return false end
    if not cpuPrev then primeCpu(instances) end
    local sys = systemStats()
    local withImage = conf.screenshot and screenshot() or false
    local payload = buildReport(instances, sys, withImage)

    local id = msgId()
    if id then
        local code = send(payload, withImage, "PATCH", conf.url .. "/messages/" .. id)
        if code and code >= 200 and code < 300 then return true end
        if code ~= 404 then
            warnOnce("edit" .. tostring(code), "update pesan gagal (HTTP " .. tostring(code or "?") .. ")")
            return false
        end
        os.remove(STATE_FILE) -- message deleted: post a new one
    end
    local code, body = send(payload, withImage, "POST", conf.url .. "?wait=true")
    if not code or code < 200 or code >= 300 then
        warnOnce("post" .. tostring(code), "kirim laporan gagal (HTTP " .. tostring(code or "?") .. ")")
        return false
    end
    local newId = parseId(body)
    if newId then
        writeFile(STATE_FILE, newId .. "\n")
        Logger.info("Webhook: pesan status dibuat")
    else
        warnOnce("noid", "id pesan tidak terbaca; laporan berikutnya jadi pesan baru")
    end
    return true
end

-- Called once per monitor cycle; reports when the interval has passed.
function Webhook.tick(instances)
    if not Webhook.enabled() then return false end
    local now = os.time()
    if firstReportAt and now < firstReportAt then return false end
    if lastReport > 0 and now - lastReport < conf.interval then return false end
    lastReport = now
    local ok, res = pcall(Webhook.report, instances)
    if not ok then warnOnce("err", "error: " .. tostring(res)) end
    return ok and res
end

-- Separate event message (rate-limited per key: at most one per 60s).
function Webhook.event(key, title, text, color)
    if not Webhook.enabled() or not conf.events then return false end
    local now = os.time()
    if eventLast[key] and now - eventLast[key] < 60 then return false end
    eventLast[key] = now
    local payload = '{"embeds":[{"title":' .. js(title) .. ',"description":' .. js(text or "")
        .. ',"color":' .. tostring(color or 16705372)
        .. ',"timestamp":' .. js(os.date("!%Y-%m-%dT%H:%M:%SZ", now)) .. '}]}'
    local ok, code = pcall(send, payload, false, "POST", conf.url)
    if not ok or not code or code < 200 or code >= 300 then
        warnOnce("event" .. tostring(code), "kirim event gagal (HTTP " .. tostring(code or "?") .. ")")
        return false
    end
    return true
end

return Webhook
