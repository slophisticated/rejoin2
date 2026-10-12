local Logger = require("core.logger")
local Shell = require("utils.shell")
local File = require("utils.file")
local Config = require("core.config")

-- License / key system client (prive, gratis, Apps Script backend).
--   - deviceId  : hash stabil per perangkat (serialno + android_id).
--   - register  : bind device ke sebuah kode key via POST /exec.
--   - session   : permanen (tidak kedaluwarsa), dicabut hanya oleh admin.
--   - gate      : "ok" / "offline" = lanjut; "no_license"/"revoked" = blok menu.
-- Offline dianggap aman (skala prive): kalau server tak terjangkau dan device
-- sudah ter-register, tetap boleh dipakai (session permanen + warning).

local License = {}

local STATE_PATH = "data/license.json"
local TIMEOUT = 8

-- ---------- helpers ----------

local function quote(s)
    s = s or ""
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function cfg()
    local ok, c = pcall(function() return Config.get() end)
    if not ok or type(c) ~= "table" then return {} end
    return c
end

local function serverUrl()
    local l = cfg().license
    if type(l) ~= "table" then return nil end
    local u = l.serverUrl
    if u and u ~= "" then return u end
    return nil
end

local function licenseEnabled()
    local l = cfg().license
    return type(l) == "table" and l.enabled == true
end

function License.getState()
    if not File.exists(STATE_PATH) then return nil end
    local content = File.read(STATE_PATH)
    if not content or content == "" then return nil end
    -- JSON sederhana: {"deviceId":"..","sess":"..","keyFam":"..","saved":".."}
    local st = {}
    st.deviceId = content:match('"deviceId"%s*:%s*"([^"]*)"')
    st.sess = content:match('"sess"%s*:%s*"([^"]*)"')
    st.keyFam = content:match('"keyFam"%s*:%s*"([^"]*)"')
    st.saved = content:match('"saved"%s*:%s*"([^"]*)"')
    if not st.deviceId or not st.sess then return nil end
    return st
end

local function saveState(st)
    local body = string.format(
        '{"deviceId":"%s","sess":"%s","keyFam":"%s","saved":"%s"}',
        st.deviceId, st.sess, st.keyFam or "", st.saved or ""
    )
    local ok, err = File.write(STATE_PATH, body)
    if not ok then
        Logger.error("License: gagal simpan state: " .. tostring(err))
        return false
    end
    Logger.info("License: state disimpan ke " .. STATE_PATH)
    return true
end

function License.clear()
    local ok, err = File.write(STATE_PATH, "")
    if ok then Logger.info("License: state lokal dihapus") end
    return ok or (err == nil)
end

-- ---------- deviceId ----------

local function shellGet(cmd)
    local _, out = Shell.exec(cmd)
    if not out then return "" end
    return (out:gsub("%s+", ""):gsub("^.-:", "")) -- strip leading "xxx:" jika ada
end

local function deviceFingerprint()
    local serial = shellGet("getprop ro.serialno")
    if serial == "" then serial = shellGet("getprop ro.boot.serialno") end
    local androidId = shellGet("settings get secure android_id")
    if androidId == "" then androidId = shellGet("su -c 'settings get secure android_id'") end
    local base = (serial ~= "" and serial or "noserial") .. "|" .. (androidId ~= "" and androidId or "noid") .. "|rejoin"
    return base
end

function License.getDeviceId()
    local _, out = Shell.exec(
        "printf '%s' " .. quote(deviceFingerprint()) .. " | md5sum | awk '{print $1}'"
    )
    local h = out and out:match("%x+") or ""
    if h == "" then
        -- fallback: md5sum tidak tersedia (Android/termux jarang), pakai sha1sum
        _, out = Shell.exec("printf '%s' " .. quote(deviceFingerprint()) .. " | sha1sum | awk '{print $1}'")
        h = out and out:match("%x+") or "na"
    end
    Logger.info("License: deviceId=" .. h)
    return h
end

-- ---------- HTTP (Apps Script) ----------

local function findStr(body, key)
    local v = body:match('"%s*' .. key .. '%s*":%s*"([^"]*)"')
    return v or ""
end

local function postJSON(action, extra)
    local url = serverUrl()
    if not url then return nil end
    local parts = { '"action":"' .. action .. '"' }
    if extra then
        for k, v in pairs(extra) do
            parts[#parts + 1] = string.format('"%s":"%s"', k, tostring(v):gsub('["\\]', "\\%1"))
        end
    end
    local body = "{" .. table.concat(parts, ",") .. "}"
    local cmd = "curl -sL --max-time " .. tostring(TIMEOUT) ..
        " -X POST -H 'Content-Type: application/json' -d " .. quote(body) ..
        " -w '\\n%{http_code}' " .. quote(url)
    local ok, out = Shell.exec(cmd)
    if not ok or not out or out == "" then return nil end
    local code = out:match("(%d+)%s*$") or "0"
    local json = out:gsub(code .. "%s*$", "")
    return {
        http = tonumber(code) or 0,
        ok = findStr(json, "ok") == "true",
        sess = findStr(json, "sess"),
        keyFam = findStr(json, "keyFam"),
        reason = findStr(json, "reason"),
    }
end

-- ---------- register / validate / gate ----------

function License.register(key)
    key = tostring(key or ""):match("^%s*(.-)%s*$")
    if key == "" then return false, "key kosong" end
    local dev = License.getDeviceId()
    local res = postJSON("register", { key = key, deviceId = dev })
    if not res then return false, "server tidak terjangkau (offline?)" end
    if not res.ok then return false, (res.reason ~= "" and res.reason or "server menolak") end
    if res.sess == "" then return false, "response tanpa sess" end
    saveState({ deviceId = dev, sess = res.sess, keyFam = res.keyFam, saved = os.date("!%Y-%m-%dT%H:%M:%SZ") })
    return true, res.keyFam
end

-- check(): panggil saat startup. Kembali: "ok" | "offline" | "no_license" |
--          "revoked" | "disabled" (config license.enabled=false).
function License.check()
    if not licenseEnabled() then return "disabled" end
    local st = License.getState()
    if not st then return "no_license" end
    local dev = License.getDeviceId()
    if st.deviceId ~= dev then
        Logger.warn("License: deviceId berubah (" .. dev .. ") -> perlu re-register")
        License.clear()
        return "no_license"
    end
    local res = postJSON("validate", { deviceId = st.deviceId, sess = st.sess })
    if not res then
        -- offline: session permanen, tetap boleh pakai (skala prive)
        return "offline"
    end
    if res.ok then return "ok" end
    if res.reason == "key_revoked" or res.reason == "not_bound" or res.reason == "bad_session" then
        License.clear()
        return "revoked"
    end
    return "offline"
end

function License.statusText(kind)
    local st = License.getState()
    if kind == "disabled" then
        return "Sistem key NONAKTIF (config license.enabled=false)."
    elseif kind == "no_license" then
        return "BELUM LISENSI — masukkan key (menu License > Login)."
    elseif kind == "revoked" then
        return "LISENSI DICABUT admin. Hubungi pemilik tool untuk key baru."
    elseif kind == "offline" then
        local extra = st and ("key: " .. tostring(st.keyFam or "-")) or ""
        return "Server tidak terjangkau — pakai lisensi tersimpan. (" .. extra .. ")"
    elseif kind == "ok" then
        local extra = st and ("key: " .. tostring(st.keyFam or "-")) or ""
        return "LISENSI VALID. (" .. extra .. ")"
    end
    return "Status lisensi tidak dikenal."
end

return License