-- Runs outside the engine; no root probes or dependency on its event loop.
local File = require("utils.file")
local Json = require("utils.json")
local Report = require("managers.report")
local conf = require("core.config").get()
local kind, pid = arg[1], arg[2]
local pending = "data/watchdog_pending.txt"
if kind ~= "retry" then
    if kind ~= "hang" and kind ~= "crash" then os.exit(2) end
    local function tail(path)
        local f = io.open(path, "rb")
        if not f then return "" end
        local size = f:seek("end") or 0
        f:seek("set", math.max(0, size - 6000))
        local text = f:read("*a") or ""
        f:close()
        return text
    end
    local label = kind == "hang" and "Engine tidak merespons (>=5 menit)" or "Engine crash"
    local text = label .. " | pid " .. tostring(pid) .. " | " .. os.date("%Y-%m-%d %H:%M:%S")
        .. "\n\nCRASH\n" .. tail("data/crash.log") .. "\nENGINE\n" .. tail("data/rejoin.log")
    text = Report.redact(text, { secret = (conf.remote or {}).secret,
        webhook = (conf.webhook or {}).url, hwid = (File.read("data/device_id.txt") or ""):gsub("%s+", "") })
    File.write("data/watchdog_report.txt", text)
    File.write(pending, text)
end
local text = File.read(pending)
if not text then return end
local w = conf.webhook or {}
local url = type(w.url) == "string" and w.url:gsub("%s+", "") or ""
local id = (File.read("data/webhook_msg.txt") or ""):match("^%s*(%d+)%s*$")
if not url:match("^https://[%w%.%-]+/api/webhooks/") or not id then return end
-- Separate files from the live webhook sender; secrets stay out of shell arguments.
local base = (os.getenv("TMPDIR") or "data") .. "/rejoin_watchdog_" .. tostring(pid):gsub("%D", "")
local payload, cfg = base .. ".json", base .. ".curl"
local body = { content = "⚠️ Rejoin — " .. text:match("^[^\n]*"),
    embeds = { { title = "Log terakhir (disensor)", description = text:sub(-3000) } },
    allowed_mentions = { parse = {} }, attachments = {} }
local q = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function escape(s) return s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("[\r\n]", "") end
os.execute("umask 077; : > " .. q(cfg) .. "; : > " .. q(payload))
local config = 'url = "' .. escape(url .. "/messages/" .. id) .. '"\nrequest = "PATCH"\n'
    .. 'header = "Content-Type: application/json"\ndata-binary = "@' .. escape(payload) .. '"\n'
local written = File.write(payload, Json.encode(body)) and File.write(cfg, config)
if written then
    local f = io.popen("curl -s --max-time 25 -o /dev/null -w '%{http_code}' --config " .. q(cfg) .. " </dev/null 2>/dev/null")
    local code = f and f:read("*a") or ""
    if f then f:close() end
    if tonumber(code) == 200 then os.remove(pending) end
end
os.remove(payload)
os.remove(cfg)
