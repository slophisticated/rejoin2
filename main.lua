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
local installHeartbeatFlag = false
local enableWindowLayoutFlag = false
for i = 1, #args do
    local a = args[i]
    if a == "--headless" or a == "--no-interactive" then headless = true end
    if a == "--no-wizard" then skipWizard = true end
    if a == "--start-monitor" then startMonitorFlag = true end
    if a == "--auto-launch" then autoLaunchFlag = true end
    if a == "--dry-run" then dryRun = true end
    if a == "--doctor" then doctorFlag = true end
    if a == "--install-heartbeat" then installHeartbeatFlag = true end
    if a == "--enable-window-layout" then enableWindowLayoutFlag = true end
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

-- Everything the tool owns lives in one folder; tell the user where it is.
require("core.paths").announce()

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

-- Warn about instances whose package is not installed on this device (e.g. a leftover
-- placeholder from the config template). Warning only — nothing is blocked.
local missing = InstanceManager.missingPackages()
if #missing > 0 then
    print("")
    print("[WARN] Package instance ini TIDAK terpasang di device:")
    for _, m in ipairs(missing) do
        print(string.format("  - id=%s  %s  (%s)", tostring(m.id), tostring(m.name), tostring(m.package)))
    end
    print("      Buang lewat menu Instances Manager > 4) Delete, atau edit config.")
    print("")
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

while true do
    print('\n' .. infoLine .. '\nMain Menu:\n  1) Launch All + Monitor\n  2) Instances Manager\n  3) Settings\n  4) AutoExecute Manager\n  5) Inject Cookie\n  6) Auto-boot (Termux:Boot)\n  7) Uninstall yanamin\n  8) Discord Webhook\n  9) Jendela & Mode Hemat\n 10) Exit\n  (tekan Ctrl+C untuk berhenti)\n')
    local choice = prompt("Choose: ") or ""
    choice = choice:match("^%s*(.-)%s*$")
    if choice == "1" then
        local list = InstanceManager.getAll()
        if #list == 0 then
            print("No instances configured.")
        else
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
        local AutoExecuteCLI = require("core.autoexecute_cli")
        AutoExecuteCLI.run()
    elseif choice == "5" then
        local InjectCookieCLI = require("core.inject_cookie_cli")
        InjectCookieCLI.run()
    elseif choice == "6" then
        local BootCLI = require("core.boot_cli")
        BootCLI.run()
    elseif choice == "7" then
        local UninstallCLI = require("core.uninstall_cli")
        UninstallCLI.run()
    elseif choice == "8" then
        require("core.webhook_cli").run()
    elseif choice == "9" then
        require("core.display_cli").run()
    elseif choice == "10" then
        print("Exiting main")
        break
    else
        print("Unknown choice")
    end
end
