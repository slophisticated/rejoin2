local Logger = require("core.logger")
local Config = require("core.config")
local JSON = require("utils.json")

-- Remote control through the user's Discord bot (see docs/discord_bot_prd.md).
--
-- The cloud phone has no public address, so the device calls the bot: every
-- remote.interval seconds the monitor loop POSTs a snapshot to <url>/api/sync and gets
-- back a list of commands, runs them, and POSTs each result to <url>/api/ack.
-- Every command is validated here; the bot is never trusted blindly. curl runs as the
-- Termux user (never su). The secret never goes to the log.
--
-- Config:
--   remote = { url = "", secret = "", interval = 30 }   -- url or secret empty = off
--
-- When the bot moves (new Railway account / URL), set the new URL once in
-- remote_url.txt on GitHub: after 5 failed syncs in a row the device reads it and
-- switches over by itself.

local Remote = {}

local REMOTE_URL_FILE = "https://raw.githubusercontent.com/slophisticated/rejoin2/main/remote_url.txt"
local PROTOCOL = 1

local lastSync = 0
local failures = 0
local lastFallback = 0
local warned = {}
local versionCache = nil

local function warnOnce(key, msg)
    if warned[key] then return end
    warned[key] = true
    Logger.warn("Remote: " .. msg)
end

local function section(conf)
    conf = conf or Config.get() or {}
    conf.remote = type(conf.remote) == "table" and conf.remote or {}
    return conf.remote, conf
end

function Remote.enabled()
    local r = section()
    return type(r.url) == "string" and r.url:match("^https?://") ~= nil
        and type(r.secret) == "string" and r.secret ~= ""
end

local function interval()
    local r = section()
    return math.max(10, math.floor(tonumber(r.interval) or 30))
end

local function version()
    if versionCache then return versionCache end
    local p = io.popen("git rev-parse --short HEAD 2>/dev/null")
    versionCache = p and (p:read("*l") or "") or ""
    if p then p:close() end
    if versionCache == "" then versionCache = "-" end
    return versionCache
end

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- HTTP ---------------------------------------------------------------------------
-- Returns status code (number, 0 = no connection) and the body.
local function request(path, payload)
    local r = section()
    local base = tostring(r.url or ""):gsub("/+$", "")
    local tmp = os.getenv("TMPDIR") or "/data/data/com.termux/files/usr/tmp"
    local stamp = tostring(os.time()) .. tostring(math.random(100000, 999999))
    local hdr = tmp .. "/rejoin_remote_h_" .. stamp
    local body = tmp .. "/rejoin_remote_b_" .. stamp
    -- The header file holds the secret: create it private (0600) before writing.
    os.execute("umask 077; : > " .. shq(hdr) .. " 2>/dev/null")
    local fh = io.open(hdr, "w")
    if not fh then return 0, "" end
    fh:write("Content-Type: application/json\n")
    fh:write("Authorization: Bearer " .. tostring(r.secret or "") .. "\n")
    fh:close()
    local fb = io.open(body, "w")
    if not fb then os.remove(hdr); return 0, "" end
    fb:write(JSON.encode(payload))
    fb:close()
    local cmd = "curl -s -m 15 -X POST -H @" .. shq(hdr) .. " --data-binary @" .. shq(body)
        .. " -w '\\n%{http_code}' " .. shq(base .. path) .. " </dev/null 2>/dev/null"
    local p = io.popen(cmd)
    local out = p and p:read("*a") or ""
    if p then p:close() end
    os.remove(hdr)
    os.remove(body)
    local text, code = out:match("^(.*)\n(%d+)%s*$")
    return tonumber(code) or 0, text or ""
end

-- Settings the bot may read and change. Anything else is refused.
local SCHEMA = {
    { key = "launchJoinTimeout", type = "int", min = 0, max = 1800, label = "Maks tunggu clone masuk game (dtk)" },
    { key = "launchSettleDelay", type = "int", min = 0, max = 600, label = "Jeda tanpa heartbeat (dtk)" },
    { key = "launchEmptyDelay", type = "int", min = 0, max = 120, label = "Jeda clone belum login (dtk)" },
    { key = "launchWaitTimeout", type = "int", min = 5, max = 600, label = "Maks tunggu Roblox kebuka (dtk)" },
    { key = "launchWaitInterval", type = "int", min = 1, max = 60, label = "Interval cek saat launch (dtk)" },
    { key = "monitorInterval", type = "int", min = 2, max = 120, label = "Interval monitor (dtk)" },
    { key = "freezeTimeout", type = "int", min = 30, max = 7200, label = "Batas freeze sebelum relaunch (dtk)" },
    { key = "minRss", type = "int", min = 0, max = 4000, label = "RSS minimal clone hidup (MB)" },
    { key = "relaunchNoLogin", type = "bool", label = "Buka lagi clone belum login yang FC" },
    { key = "noLoginCooldown", type = "int", min = 30, max = 3600, label = "Jeda buka lagi clone belum login (dtk)" },
    { key = "windowLayout.enabled", type = "bool", label = "Auto atur jendela (grid)" },
    { key = "windowLayout.columns", type = "int", min = 0, max = 10, label = "Kolom grid (0 = otomatis)" },
    { key = "windowLayout.gap", type = "int", min = 0, max = 200, label = "Jarak antar jendela (px)" },
    { key = "windowLayout.overlap", type = "int", min = 0, max = 400, label = "Baris atas numpuk (px)" },
    { key = "heartbeat.enabled", type = "bool", label = "Heartbeat Delta" },
    { key = "heartbeat.saver.enabled", type = "bool", label = "Mode hemat" },
    { key = "heartbeat.saver.fpsCap", type = "int", min = 0, max = 240, label = "Batas FPS mode hemat" },
    { key = "heartbeat.saver.disable3d", type = "bool", label = "Render 3D mati (mode hemat)" },
    { key = "webhook.url", type = "string", secret = true, max = 300,
      pattern = "^https://[%w%.%-]+/api/webhooks/", label = "URL Discord webhook" },
    { key = "webhook.interval", type = "int", min = 60, max = 3600, label = "Interval laporan webhook (dtk)" },
    { key = "webhook.screenshot", type = "bool", label = "Screenshot di laporan" },
    { key = "webhook.events", type = "bool", label = "Notif Delta minta key" },
    { key = "webhook.hideNames", type = "bool", label = "Sembunyikan nama akun" },
    { key = "webhook.deviceName", type = "string", max = 60, label = "Nama device" },
    { key = "deltaLicensePath", type = "string", max = 300, label = "Path file license Delta (kosong = otomatis)" },
    { key = "appAutoExecutePath", type = "string", max = 300, label = "Folder Autoexecute Delta" },
    { key = "remote.interval", type = "int", min = 10, max = 600, label = "Interval sync bot (dtk)" },
}
local SCHEMA_BY_KEY = {}
for _, s in ipairs(SCHEMA) do SCHEMA_BY_KEY[s.key] = s end
Remote.SCHEMA = SCHEMA

local function getPath(t, key)
    for part in key:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

local function setPath(t, key, value)
    local parts = {}
    for part in key:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        if type(t[parts[i]]) ~= "table" then t[parts[i]] = {} end
        t = t[parts[i]]
    end
    t[parts[#parts]] = value
end

-- Effective value (with the same defaults the modules use).
local DEFAULTS = {
    launchJoinTimeout = 240, launchSettleDelay = 20, launchEmptyDelay = 5, launchWaitTimeout = 60,
    launchWaitInterval = 3, monitorInterval = 5, freezeTimeout = 300, minRss = 300,
    relaunchNoLogin = true, noLoginCooldown = 120,
    ["windowLayout.enabled"] = false, ["windowLayout.columns"] = 0, ["windowLayout.gap"] = 0,
    ["windowLayout.overlap"] = 80, ["heartbeat.enabled"] = true, ["heartbeat.saver.enabled"] = false,
    ["heartbeat.saver.fpsCap"] = 15, ["heartbeat.saver.disable3d"] = true, ["webhook.url"] = "",
    ["webhook.interval"] = 300, ["webhook.screenshot"] = true, ["webhook.events"] = true,
    ["webhook.hideNames"] = true, ["webhook.deviceName"] = "", deltaLicensePath = "",
    appAutoExecutePath = "/sdcard/Delta/Autoexecute", ["remote.interval"] = 30,
}

local function settingsSnapshot(conf)
    local out = JSON.array({})
    for _, s in ipairs(SCHEMA) do
        local v = getPath(conf, s.key)
        if v == nil then v = DEFAULTS[s.key] end
        local e = { key = s.key, type = s.type, label = s.label, min = s.min, max = s.max }
        if s.secret then
            e.value = (type(v) == "string" and v ~= "") and "set" or ""
            e.secret = true
        else
            e.value = v
        end
        out[#out + 1] = e
    end
    return out
end

local function parseValue(s, raw)
    if s.type == "bool" then
        if type(raw) == "boolean" then return raw end
        local t = tostring(raw):lower()
        if t == "true" or t == "on" or t == "ya" or t == "1" or t == "nyala" then return true end
        if t == "false" or t == "off" or t == "tidak" or t == "0" or t == "mati" then return false end
        return nil, "harus true/false"
    elseif s.type == "int" then
        local n = tonumber(raw)
        if not n then return nil, "harus angka" end
        n = math.floor(n)
        if s.min and n < s.min then return nil, "minimal " .. s.min end
        if s.max and n > s.max then return nil, "maksimal " .. s.max end
        return n
    else
        local v = tostring(raw == nil and "" or raw):gsub("^%s+", ""):gsub("%s+$", "")
        if s.max and #v > s.max then return nil, "terlalu panjang (maks " .. s.max .. ")" end
        if v ~= "" and s.pattern and not v:match(s.pattern) then return nil, "format tidak valid" end
        return v
    end
end

-- Snapshot -------------------------------------------------------------------------
local function snapshot(instances)
    local conf = Config.get() or {}
    local okW, Webhook = pcall(require, "managers.webhook")
    local okS, Status = pcall(require, "managers.status")
    local okH, Heartbeat = pcall(require, "managers.heartbeat")
    local okU, Username = pcall(require, "managers.username")
    local okI, Instances = pcall(require, "managers.instance")

    local presets = {}
    for k, p in pairs(type(conf.presets) == "table" and conf.presets or {}) do
        if type(p) == "table" then presets[tostring(k)] = { name = p.name or "", link = p.link or "" } end
    end

    local list = JSON.array({})
    for _, inst in ipairs(instances or {}) do
        local hb = okH and Heartbeat.read and select(2, pcall(Heartbeat.read, inst)) or nil
        local e = {
            id = inst.id, name = inst.name or "", package = inst.package or "",
            preset = inst.preset or "",
            link = okI and Instances.gameLink and Instances.gameLink(inst) or (inst.privateServer or ""),
            status = okS and Status.statusOf and Status.statusOf(inst.id) or "unknown",
        }
        if okU and Username.get then
            local okN, n = pcall(Username.get, inst)
            if okN and n then e.username = n end
        end
        if type(hb) == "table" and hb.fresh then
            e.fps = hb.fps
            e.mem = hb.mem
        end
        list[#list + 1] = e
    end

    return {
        protocol = PROTOCOL,
        device = okW and Webhook.deviceLabel and Webhook.deviceLabel() or "-",
        version = version(),
        time = os.time(),
        presets = presets,
        instances = list,
        settings = settingsSnapshot(conf),
    }
end

-- Commands -------------------------------------------------------------------------
local function cloneLabel(inst) return tostring(inst.name or inst.package or inst.id) end

local function findClones(refs)
    local Instances = require("managers.instance")
    local all = Instances.getAll()
    if refs == nil or refs == "all" or (type(refs) == "table" and #refs == 0) then return all end
    if type(refs) ~= "table" then refs = { refs } end
    local out, missing = {}, {}
    for _, r in ipairs(refs) do
        local inst = Instances.find(r)
        if inst then out[#out + 1] = inst else missing[#missing + 1] = tostring(r) end
    end
    if #missing > 0 then return nil, "clone tidak ditemukan: " .. table.concat(missing, ", ") end
    return out
end

local function validLink(l)
    return type(l) == "string" and (l:match("^https://[%w%.%-]*roblox%.com/") or l:match("^roblox://")) ~= nil
end

local function save(conf)
    local ok, err = Config.save(conf)
    if not ok then return false, "gagal menyimpan config: " .. tostring(err) end
    return true
end

local H = {}

function H.status(args, ctx, instances)
    local n, ingame = 0, 0
    local okS, Status = pcall(require, "managers.status")
    for _, inst in ipairs(instances or {}) do
        n = n + 1
        if okS and Status.statusOf and Status.statusOf(inst.id) == "ingame" then ingame = ingame + 1 end
    end
    return true, string.format("%d/%d clone di dalam game", ingame, n), snapshot(instances)
end

function H.game(args, ctx)
    local conf = Config.get() or {}
    local key = tostring(args.preset or "")
    local p = type(conf.presets) == "table" and conf.presets[key] or nil
    if type(p) ~= "table" or not validLink(p.link) then return false, "preset '" .. key .. "' tidak ada / link kosong" end
    local list, err = findClones(args.clones)
    if not list then return false, err end
    local ids, names = {}, {}
    for _, inst in ipairs(list) do
        inst.preset = key
        ids[#ids + 1] = inst.id
        names[#names + 1] = cloneLabel(inst)
    end
    local ok, e = require("managers.instance").save()
    if not ok then return false, tostring(e) end
    if args.rejoin ~= false then ctx.requestRejoin(ids) end
    return true, string.format("%s → %s (%s)%s", table.concat(names, ", "), key, p.name or "",
        args.rejoin ~= false and ", rejoin berurutan" or "")
end
H.set_preset = H.game

function H.restart(args, ctx)
    local list, err = findClones(args.clone or args.clones)
    if not list then return false, err end
    if args.clone == nil and args.clones == nil then return false, "clone wajib diisi" end
    local ids, names = {}, {}
    for _, inst in ipairs(list) do ids[#ids + 1] = inst.id; names[#names + 1] = cloneLabel(inst) end
    ctx.requestRejoin(ids)
    return true, "rejoin: " .. table.concat(names, ", ")
end

function H.launch_all(args, ctx)
    ctx.requestRejoin({ "all" })
    return true, "Launch All dimulai (login duluan, satu per satu)"
end

function H.preset_set(args, ctx)
    local key = tostring(args.key or "")
    if not key:match("^[%w_%-]+$") or #key > 16 then return false, "kode preset harus huruf/angka (maks 16)" end
    if not validLink(args.link) then return false, "link harus link roblox.com atau roblox://" end
    local conf = Config.get() or {}
    conf.presets = type(conf.presets) == "table" and conf.presets or {}
    local existed = conf.presets[key] ~= nil
    conf.presets[key] = { name = tostring(args.name or key):sub(1, 60), link = args.link }
    local ok, err = save(conf)
    if not ok then return false, err end
    local used = {}
    for _, inst in ipairs(require("managers.instance").getAll()) do
        if inst.preset == key then used[#used + 1] = inst.id end
    end
    if args.rejoin and #used > 0 then ctx.requestRejoin(used) end
    return true, string.format("preset %s %s (%d clone pakai preset ini%s)", key,
        existed and "diubah" or "ditambah", #used, (args.rejoin and #used > 0) and ", rejoin" or "")
end

function H.preset_remove(args)
    local key = tostring(args.key or "")
    local conf = Config.get() or {}
    if type(conf.presets) ~= "table" or conf.presets[key] == nil then return false, "preset '" .. key .. "' tidak ada" end
    conf.presets[key] = nil
    local n = 0
    for _, inst in ipairs(require("managers.instance").getAll()) do
        if inst.preset == key then inst.preset = nil; n = n + 1 end
    end
    local ok, err = save(conf)
    if not ok then return false, err end
    return true, string.format("preset %s dihapus (%d clone kembali ke link sendiri)", key, n)
end

local function validPackage(p) return type(p) == "string" and p:match("^[%w_]+%.[%w_%.]+$") ~= nil end

function H.instance_add(args)
    if not validPackage(args.package) then return false, "package tidak valid (mis. com.apengjers.v7)" end
    local Instances = require("managers.instance")
    for _, inst in ipairs(Instances.getAll()) do
        if inst.package == args.package then return false, "package sudah ada: " .. cloneLabel(inst) end
    end
    local conf = Config.get() or {}
    local inst = { name = tostring(args.name or args.package):sub(1, 40), package = args.package }
    if args.preset and args.preset ~= "" then
        if type(conf.presets) ~= "table" or not conf.presets[args.preset] then return false, "preset tidak ada" end
        inst.preset = args.preset
    end
    if args.link and args.link ~= "" then
        if not validLink(args.link) then return false, "link tidak valid" end
        inst.privateServer = args.link
    end
    local ok, res = Instances.add(inst)
    if not ok then return false, tostring(res) end
    return true, "clone ditambah: " .. cloneLabel(inst) .. " (id " .. tostring(inst.id) .. ")"
end

function H.instance_edit(args)
    local Instances = require("managers.instance")
    local inst = Instances.find(args.clone)
    if not inst then return false, "clone tidak ditemukan" end
    local conf = Config.get() or {}
    if args.name ~= nil and args.name ~= "" then inst.name = tostring(args.name):sub(1, 40) end
    if args.package ~= nil and args.package ~= "" then
        if not validPackage(args.package) then return false, "package tidak valid" end
        inst.package = args.package
    end
    if args.preset ~= nil then
        if args.preset == "" or args.preset == "-" then
            inst.preset = nil
        elseif type(conf.presets) == "table" and conf.presets[args.preset] then
            inst.preset = args.preset
        else
            return false, "preset tidak ada"
        end
    end
    if args.link ~= nil then
        if args.link == "" or args.link == "-" then
            inst.privateServer = nil
        elseif validLink(args.link) then
            inst.privateServer = args.link
        else
            return false, "link tidak valid"
        end
    end
    local ok, err = Instances.save()
    if not ok then return false, tostring(err) end
    return true, "clone diubah: " .. cloneLabel(inst)
end

function H.instance_remove(args)
    local Instances = require("managers.instance")
    local inst = Instances.find(args.clone)
    if not inst then return false, "clone tidak ditemukan" end
    local label = cloneLabel(inst)
    local ok, err = Instances.remove(inst.id)
    if not ok then return false, tostring(err) end
    return true, "clone dihapus dari daftar: " .. label .. " (app-nya tidak di-uninstall)"
end

local function applySideEffects(key, conf)
    if key:match("^webhook%.") then
        pcall(function() require("managers.webhook").configure(conf) end)
    elseif key:match("^heartbeat%.") or key == "appAutoExecutePath" then
        pcall(function() require("managers.heartbeat").install() end)
    end
end

function H.config_set(args)
    local s = SCHEMA_BY_KEY[tostring(args.key or "")]
    if not s then return false, "setting '" .. tostring(args.key) .. "' tidak boleh diubah dari bot" end
    local v, err = parseValue(s, args.value)
    if v == nil then return false, s.key .. ": " .. tostring(err) end
    local conf = Config.get() or {}
    setPath(conf, s.key, v)
    local ok, e = save(conf)
    if not ok then return false, e end
    applySideEffects(s.key, conf)
    local shown = s.secret and (v ~= "" and "diset" or "dikosongkan") or tostring(v)
    return true, string.format("%s = %s", s.label or s.key, shown)
end

function H.device_rename(args)
    return H.config_set({ key = "webhook.deviceName", value = args.name })
end

function H.webhook_use_message(args)
    local Webhook = require("managers.webhook")
    Webhook.configure(Config.get() or {})
    local id, err = Webhook.useMessage(args.link)
    if not id then return false, tostring(err) end
    return true, "pesan status lama dipakai (id " .. id .. "), di-update di laporan berikutnya"
end

function H.webhook_test(args, ctx, instances)
    local Webhook = require("managers.webhook")
    Webhook.configure(Config.get() or {})
    if not Webhook.enabled() then return false, "URL webhook belum diisi" end
    local ok, res = pcall(Webhook.report, instances)
    if ok and res then return true, "laporan terkirim" end
    return false, "gagal kirim laporan (cek URL / internet)"
end

Remote.handlers = H

-- Run one command table { id, type, args }. Returns ok, message, data.
function Remote.run(cmd, ctx, instances)
    if type(cmd) ~= "table" then return false, "command tidak valid" end
    local h = H[tostring(cmd.type or "")]
    if not h then return false, "command tidak dikenal: " .. tostring(cmd.type) end
    local args = type(cmd.args) == "table" and cmd.args or {}
    local ok, a, b, c = pcall(h, args, ctx or { requestRejoin = function() end }, instances)
    if not ok then return false, "error: " .. tostring(a) end
    return a, b, c
end

-- Sync -------------------------------------------------------------------------------
local function fallbackUrl()
    if os.time() - lastFallback < 600 then return end
    lastFallback = os.time()
    local p = io.popen("curl -s -m 10 " .. shq(REMOTE_URL_FILE) .. " </dev/null 2>/dev/null")
    local text = p and p:read("*a") or ""
    if p then p:close() end
    local url = text:match("(https://[%w%.%-%:/_]+)")
    if not url then return end
    url = url:gsub("/+$", "")
    local r, conf = section()
    if url ~= tostring(r.url or ""):gsub("/+$", "") then
        r.url = url
        Config.save(conf)
        failures = 0
        Logger.info("Remote: URL bot pindah ke " .. url .. " (remote_url.txt)")
    end
end

-- One sync: send the snapshot, run the commands, ack each. Returns the HTTP code.
function Remote.sync(instances, ctx)
    local code, body = request("/api/sync", snapshot(instances))
    if code == 401 or code == 403 then
        warnOnce("auth", "bot menolak secret (HTTP " .. code .. "); cek remote.secret")
        return code
    end
    if code < 200 or code >= 300 then
        failures = failures + 1
        warnOnce("http" .. code, "sync gagal (HTTP " .. code .. ")")
        if failures >= 5 then pcall(fallbackUrl) end
        return code
    end
    failures = 0
    warned = {}
    local data = JSON.decode(body)
    local cmds = type(data) == "table" and type(data.commands) == "table" and data.commands or {}
    local okW, Webhook = pcall(require, "managers.webhook")
    local device = okW and Webhook.deviceLabel and Webhook.deviceLabel() or "-"
    for _, cmd in ipairs(cmds) do
        local ok, msg, extra = Remote.run(cmd, ctx, instances)
        Logger.info(string.format("Remote: %s %s -> %s %s", tostring(cmd.type), tostring(cmd.id),
            ok and "OK" or "GAGAL", tostring(msg)))
        request("/api/ack", {
            protocol = PROTOCOL,
            device = device,
            id = cmd.id,
            ok = ok and true or false,
            message = tostring(msg or ""),
            data = extra,
        })
    end
    return code
end

-- Called once per monitor cycle.
function Remote.tick(instances, ctx)
    if not Remote.enabled() then return false end
    local now = os.time()
    if now - lastSync < interval() then return false end
    lastSync = now
    Remote.sync(instances, ctx)
    return true
end

-- Menu "tes koneksi": one sync without running anything heavy. Returns ok, message.
function Remote.test()
    if not Remote.enabled() then return false, "URL bot / secret belum diisi" end
    local Instances = require("managers.instance")
    local code = Remote.sync(Instances.getAll(), { requestRejoin = function() end })
    if code >= 200 and code < 300 then return true, "terhubung (HTTP " .. code .. ")" end
    if code == 401 or code == 403 then return false, "secret ditolak bot (HTTP " .. code .. ")" end
    if code == 0 then return false, "bot tidak bisa dihubungi (URL / internet)" end
    return false, "bot membalas HTTP " .. code
end

return Remote
