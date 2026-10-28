local Shell = require("utils.shell")
local File = require("utils.file")
local Config = require("core.config")
local Report = require("managers.report")

local Diagnostics = {}
local PATH = "data/launch_android.log"

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function valid(pkg)
    return type(pkg) == "string" and pkg:match("^[%a_][%w_%.]*$") ~= nil
end

-- One root call per launch; keep package/PID mapping before a peer disappears.
function Diagnostics.snapshot(instances)
    local commands = {}
    for _, inst in ipairs(instances) do
        if valid(inst.package) then
            commands[#commands + 1] = "echo " .. quote(inst.package) .. "; pidof " .. quote(inst.package)
        end
    end
    if #commands == 0 then return "" end
    local ok, out = Shell.exec("sh -c " .. quote(table.concat(commands, "; ") .. "; :"))
    return ok and (out or ""):sub(1, 2000) or "PID snapshot gagal"
end

-- Only process-management tags, never the full application log or a cleared buffer.
function Diagnostics.capture(target, instances, snapshot, started)
    local conf = Config.get() or {}
    local remote, webhook = conf.remote or {}, conf.webhook or {}
    local out = {
        string.format("[%s] target=%s mulai=%s deteksi=%s", os.date("%Y-%m-%d %H:%M:%S"),
            tostring(target.package), tostring(started), tostring(os.time())),
        "PID sebelum launch:\n" .. (snapshot or "tidak tersedia"),
        "Logcat ring buffer: bisa memuat kejadian sebelum launch; kosong bukan bukti tidak ada kill/crash.",
    }
    local ok, raw = Shell.exec("logcat -d -b events -b system -b crash -v threadtime -t 600 "
        .. "am_kill:I am_proc_died:I am_crash:I am_anr:I ActivityManager:I lmkd:I lowmemorykiller:I AndroidRuntime:E DEBUG:E '*:S'")
    local selected = {}
    if ok then
        for line in (raw or ""):gmatch("[^\r\n]+") do
            local keep = line:find("lmkd", 1, true) or line:find("lowmemorykiller", 1, true)
            for _, inst in ipairs(instances) do
                if valid(inst.package) and line:find(inst.package, 1, true) then keep = true end
            end
            if keep then selected[#selected + 1] = line:sub(1, 600) end
        end
        out[#out + 1] = #selected > 0 and table.concat(selected, "\n") or "Tidak ada baris terkait pada sampel logcat."
    else
        out[#out + 1] = "Logcat gagal/tidak diizinkan; penyebab proses hilang belum diketahui."
    end
    local memOk, mem = Shell.exec("sh -c " .. quote("grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo"))
    out[#out + 1] = "Memori saat deteksi (bukan syarat launch):\n" .. (memOk and (mem or ""):sub(1, 1000) or "tidak tersedia")
    local text = Report.redact(table.concat(out, "\n"), {
        secret = remote.secret, webhook = webhook.url,
        hwid = (File.read("data/device_id.txt") or ""):gsub("%s+", ""),
    })
    -- Bounded history survives restart so a later /report still includes the incident.
    local previous = File.read(PATH) or ""
    return File.write(PATH, (previous .. "\n" .. text:sub(1, 12000) .. "\n"):sub(-24000))
end

return Diagnostics
