-- Keep `lua main.lua` as the single entrypoint. The shell supervisor owns the
-- terminal while Lua runs, so Ctrl+C works even during os.execute/io.popen.
-- REJOIN_WRAPPER prevents the supervisor's child from launching another one.
if os.getenv("REJOIN_WRAPPER") ~= "1" then
    local function shellQuote(value)
        return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
    end
    local scriptDir = (arg and arg[0] and arg[0]:match("^(.*[/\\])")) or ""
    local command = "sh " .. shellQuote(scriptDir .. "run.sh")
    for i = 1, #(arg or {}) do
        command = command .. " " .. shellQuote(arg[i])
    end
    local ok, _, code = os.execute(command)
    if type(ok) == "number" then
        -- Lua 5.1 returns the wait status as a number; newer Lua returns a
        -- boolean plus the exit code.
        os.exit(ok > 255 and math.floor(ok / 256) or ok)
    end
    os.exit(ok and 0 or (code or 1))
end

-- Recover terminal mode left by a previous interrupted cookie paste before any
-- logs or menu text. A redirected/headless stdin makes stty fail harmlessly.
local ttyReady = os.execute("stty sane 2>/dev/null")
if ttyReady == true or ttyReady == 0 then
    os.execute("stty echo icanon opost onlcr 2>/dev/null")
    io.write("\r\27[2J\27[H")
    io.flush()
end

local Logger = require("core.logger")
local State = require("core.state")

Logger.info(State.get())

State.set("MENU")

Logger.info(State.get())

-- Parse simple CLI flags
local args = arg or {}
local headless = false
local skipWizard = false
local startMonitorFlag = false
local autoLaunchFlag = false
local configSource = nil
local dryRun = false
local doctorFlag = false
local reportFlag = false
local installHeartbeatFlag = false
local migratePresetsFlag = false
local enableWindowLayoutFlag = false
for i = 1, #args do
    local a = args[i]
    if a == "--headless" or a == "--no-interactive" then headless = true end
    if a == "--no-wizard" then skipWizard = true end
    if a == "--start-monitor" then startMonitorFlag = true end
    if a == "--auto-launch" then autoLaunchFlag = true end
    if a == "--dry-run" then dryRun = true end
    if a == "--doctor" then doctorFlag = true end
    if a == "--report" then reportFlag = true end
    if a == "--install-heartbeat" then installHeartbeatFlag = true end
    if a == "--enable-window-layout" then enableWindowLayoutFlag = true end
    if a == "--migrate-presets" then migratePresetsFlag = true end
    if a == "--hwid" then
        -- Print this device's HWID (for a bot key) and stop; needs no root.
        print(require("managers.remote").deviceId())
        os.exit(0)
    end
    if a == "--config" then
        local nextArg = args[i+1]
        if nextArg and nextArg:sub(1,2) ~= "--" then
            configSource = nextArg
        end
    end
end

-- Set runtime dry-run early
local Runtime = require("core.runtime")
if dryRun then
    Runtime.setDryRun(true)
    Logger.info("Runtime: dry-run mode enabled")
end

-- Root handler: stop right away when Termux has no root (everything else needs it,
-- the setup wizard's clone detection included). Skipped for --dry-run, for the
-- installer's one-shot flags (they do not need root) and with useRoot = false.
do
    local okC, c = pcall(dofile, "config/config.lua")
    local rootOff = okC and type(c) == "table" and c.useRoot == false
    -- --report must work exactly when something (root included) is broken.
    if not (dryRun or installHeartbeatFlag or enableWindowLayoutFlag or migratePresetsFlag or reportFlag or rootOff) then
        local RootCheck = require("core.root_check")
        if not RootCheck.ok() then
            Logger.error("Root belum aktif; rejoin berhenti")
            io.stderr:write(RootCheck.MESSAGE .. "\n")
            os.exit(3)
        end
    end
end

-- Ensure configuration exists (setup will copy template -> config if needed)
local Setup = require("core.setup")
local ok, created_or_err = Setup.ensureConfig(configSource)
if not ok then
    Logger.error("Failed to ensure config: " .. tostring(created_or_err))
else
    if created_or_err == true and not skipWizard and not headless then
        -- config was just created from template; run the interactive setup wizard
        local Wizard = require("core.setup_wizard")
        local wok, werr = Wizard.run()
        if not wok then
            Logger.warn("Setup wizard did not complete: " .. tostring(werr))
            Logger.info("You can edit config/config.lua manually or re-run the wizard later.")
        end
    end
end

local Config = require("core.config")

-- Initialize logger path from loaded config
local conf = Config.get() or {}
if conf.logPath then
    Logger.setLogPath(conf.logPath)
end

local data = conf

local InstanceManager = require("managers.instance")
InstanceManager.load(Config.get())

-- One-shot: the error report of Main Menu 4 (all logs, secrets masked, copied to the
-- clipboard). Usable when the menu itself does not work: cd ~/rejoin && lua main.lua --report
if reportFlag then
    local Report = require("managers.report")
    local text, status = Report.run()
    print(text)
    for _, line in ipairs(status) do print(line) end
    os.exit(0)
end

-- One-shot: environment doctor -- run on EACH device, diff outputs to find the
-- dependency/fingerprint difference causing "inject [OK] tapi app ga login" on one
-- device but not the other. Exits after printing.
if doctorFlag then
    local Doctor = require("managers.doctor")
    local report = Doctor.run()
    print("\n===== DOCTOR REPORT (jalankan di KEDUA device, diff outputnya) =====")
    print(report)
    print("====================================================================")
    os.exit(0)
end

-- One-shot (installer): switch the floating window grid on in the user's config.
-- One-shot (update.sh migration): turn the clones' own game links into presets with a
-- default preset. Does nothing when presets already exist.
if migratePresetsFlag then
    local c = Config.get() or {}
    local msg = InstanceManager.migrateToPresets(c)
    if not msg then
        print("OK: preset tidak perlu dipindah")
        os.exit(0)
    end
    local saved, err = Config.save(c)
    print(saved and ("OK: " .. msg) or ("GAGAL: " .. tostring(err)))
    os.exit(saved and 0 or 1)
end

if enableWindowLayoutFlag then
    local c = Config.get() or {}
    c.windowLayout = type(c.windowLayout) == "table" and c.windowLayout or {}
    if c.windowLayout.enabled == true then
        print("OK: auto atur jendela sudah nyala")
        os.exit(0)
    end
    c.windowLayout.enabled = true
    local saved, err = Config.save(c)
    print(saved and "OK: auto atur jendela dinyalakan" or ("GAGAL: " .. tostring(err)))
    os.exit(saved and 0 or 1)
end

-- One-shot: (re)install the in-game heartbeat script into the Delta autoexecute folder.
if installHeartbeatFlag then
    local Heartbeat = require("managers.heartbeat")
    local hbOk, hbMsg = Heartbeat.install()
    print((hbOk and "OK: " or "GAGAL: ") .. tostring(hbMsg))
    os.exit(hbOk and 0 or 1)
end

-- Headless mode: optionally start monitor immediately
if headless and startMonitorFlag then
    Logger.info("Headless mode: starting monitor")
    local Monitor = require("managers.monitor")
    -- --auto-launch behaves like Menu 1: launch all clones (Starting -> Running) with
    -- optimizer applied, then monitor. Without it, only the monitor runs (no launch).
    local opts = autoLaunchFlag and { autoLaunch = true } or nil
    Monitor.start(Config.get(), opts)
    os.exit(0)
end

-- Interactive menu loop
local function prompt(msg)
    io.write(msg)
    io.flush()
    local line = io.read()
    -- Ctrl+C / EOF while in the menu returns nil; treat it as a clean hard stop.
    if line == nil then
        print("\nInterrupted by Ctrl+C; exiting.")
        os.exit(0)
    end
    return line
end

-- One info line above the menu: version, and whether this device was set up with the
-- one-command installer (its boot script carries a marker) / starts on boot.
local function installInfo()
    local p = io.popen("git rev-parse --short HEAD 2>/dev/null")
    local hash = p and (p:read("*l") or "") or ""
    if p then p:close() end
    if hash == "" then hash = "-" end
    local home = os.getenv("HOME") or ""
    local f = io.open(home .. "/.termux/boot/start-rejoin.sh", "r")
    local boot = f and (f:read("*a") or "") or nil
    if f then f:close() end
    local instant = boot and boot:find("Generated by rejoin install.sh", 1, true) ~= nil
    return string.format("Rejoin %s | install instan: %s | auto-start boot: %s",
        hash, instant and "ya" or "tidak", boot and "ya" or "tidak")
end
local infoLine = installInfo()

-- Menu 1 / 5 while the boot engine still runs: offer to stop it and continue here
-- (two engines would launch the same clones at once). SIGTERM = a clean stop, so the
-- boot script does not restart it. Returns true when no other engine is left.
local function takeOverEngine()
    local Monitor = require("managers.monitor")
    local other = Monitor.otherEngine()
    if not other then return true end
    print(string.format("Engine lain masih jalan (pid %d, biasanya dari boot).", other))
    local answer = (prompt("Stop engine itu terus lanjut di sini? [Y/n]: ") or "n"):lower()
    if answer:match("^%s*n") then return false end
    os.execute("kill -TERM " .. other .. " 2>/dev/null")
    for _ = 1, 15 do
        if not Monitor.otherEngine() then
            print("Engine lama udah berhenti.")
            return true
        end
        os.execute("sleep 1")
    end
    print("Engine lama belum berhenti; coba lagi sebentar lagi.")
    return false
end

while true do
    print('\n' .. infoLine .. '\nMain Menu:\n  1) Start Monitor (clone yang jalan ga di-launch ulang)\n  2) Instances Manager\n  3) Settings\n  4) Logs & Report Error\n  5) Launch All + Monitor\n  6) Script Manager (Scripts & Autoexecute)\n  7) Inject Cookie\n  8) Dump Cookies (debug)\n  9) Discord (Webhook & Bot)\n 10) Jendela & Mode Hemat\n 11) Preset Game\n 12) Input Key Delta\n 13) Install APK dari GoFile\n 14) Antrean Launch (status / lewati satu / batalkan sisa)\n  0) Exit\n  (tekan Ctrl+C untuk berhenti)\n')
    local choice = prompt("Choose: ") or ""
    choice = choice:match("^%s*(.-)%s*$")
    if choice == "5" then
        local list = InstanceManager.getAll()
        if #list == 0 then
            print("No instances configured.")
        elseif takeOverEngine() then
            -- Launch clones one at a time (Starting -> Running) inside the live monitor
            -- dashboard; the monitor then watches/recovers them.
            local Monitor = require("managers.monitor")
            Monitor.start(Config.get(), { autoLaunch = true })
            if Monitor.interrupted() then
                print("Monitor stopped by Ctrl+C; exiting.")
                os.exit(0)
            end
            break
        end
    elseif choice == "2" then
        local InstancesCLI = require("core.instances_cli")
        InstancesCLI.run()
    elseif choice == "3" then
        local SettingsCLI = require("core.settings_cli")
        SettingsCLI.run()
    elseif choice == "4" then
        local LogsCLI = require("core.logs_cli")
        LogsCLI.run()
    elseif choice == "1" then
        -- Most used: bring the monitor (and the bot connection) back without
        -- relaunching clones that are already running.
        local Monitor = require("managers.monitor")
        if takeOverEngine() then
            print("(tekan Ctrl+C untuk berhenti monitor)")
            Monitor.start(Config.get())
        end
        if Monitor.interrupted() then
            print("Monitor stopped by Ctrl+C; exiting.")
            os.exit(0)
        end
    elseif choice == "6" then
        local AutoExecuteCLI = require("core.autoexecute_cli")
        AutoExecuteCLI.run()
    elseif choice == "7" then
        local InjectCookieCLI = require("core.inject_cookie_cli")
        InjectCookieCLI.run()
    elseif choice == "8" then
        local DumpCookiesCLI = require("core.dump_cookies_cli")
        DumpCookiesCLI.run()
    elseif choice == "9" then
        require("core.webhook_cli").run()
    elseif choice == "10" then
        require("core.display_cli").run()
    elseif choice == "11" then
        require("core.preset_cli").run()
    elseif choice == "12" then
        require("core.delta_key_cli").run()
    elseif choice == "13" then
        require("core.gofile_apk_cli").run()
        prompt("Tekan Enter untuk kembali ke menu utama")
    elseif choice == "14" then
        require("core.launch_control_cli").run()
        prompt("Tekan Enter untuk kembali ke menu utama")
    elseif choice == "0" then
        print("Exiting main")
        break
    else
        print("Unknown choice")
    end
end
