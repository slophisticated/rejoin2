-- Config template for Rejoin Engine
return {
    -- AutoExecute is now managed DIRECTLY in the app's autoexecute folder: scripts are
    -- added/edited/deleted from the "Script Manager" menu into `appAutoExecutePath`
    -- (e.g. /sdcard/Delta/Autoexecute). No separate staging folder, no deploy step.
    monitorInterval = 8,
    recoveryDelay = 3,
    recoveryRetries = 3,
    checkTimeout = 15,
    debug = true,
    -- Console log verbosity. Hidden below this level: "DEBUG" shows everything,
    -- "INFO" is the default (hides the monitor's per-probe/su debug spam).
    logLevel = "INFO",
    logPath = "data/rejoin.log",
    -- Optional fast filter for auto-detect clone scan (e.g. "com.apengjers."). Empty = disabled.
    clonePackagePrefix = "",
    -- Seconds an app may stay frozen/stuck before the monitor force-relaunches it.
    -- (5 minutes = 300s). Clones that are NOT logged in are never relaunched regardless
    -- (see cookiePath / Auth detection).
    freezeTimeout = 300,
    -- Seconds after launch that a running app is still considered "starting" before it
    -- is judged ingame vs stuck.
    gracePeriod = 30,
    -- Enable ANR (Application Not Responding) detection via logcat (best-effort, needs
    -- readable logcat, more reliable with root).
    anrCheckEnabled = true,
    -- RSS threshold for diagnostics only; never triggers a restart.
    minRss = 300,
    -- Timeout (seconds) for each shell command (via the `timeout` tool) so a hung
    -- su/dumpsys call can't freeze the whole tool / stop the terminal accepting input.
    shellTimeout = 10,
    -- Automatic per-cycle diagnostics: written to this file whenever the app is
    -- launched via Menu 1 (Launch + Monitor). Shows running/isActive/RSS per clone.
    launchLogPath = "launch.log",
    launchLogEnabled = true,

    -- Deprioritize the Roblox clones with renice/ionice to cut RAM/CPU contention when
    -- several floating windows run at once. Applied to every clone after launch/recovery
    -- (the process gets a new pid on each relaunch, so tuning is re-applied each time).
    optimizer = {
        enabled = true,
        renice = 19,   -- CPU scheduling priority (higher = lower). 19 = lowest.
        ionice = 3,    -- I/O class: 0=none,1=realtime,2=best-effort,3=idle.
    },

    -- Folder tujuan AutoExecute (Script Manager). Scripts dikelola LANGSUNG di sini
    -- sebagai <name>.lua (Add/Edit/Delete). Path ini shared untuk semua instance.
    -- Delta mod: /sdcard/Delta/Autoexecute (internal storage, tidak perlu root).
    appAutoExecutePath = "/sdcard/Delta/Autoexecute",

    -- Launch All waits for fresh, stable session heartbeats before advancing.
    -- launchJoinTimeout: deadline becomes Needs Check; never falls back to opening others.
    -- launchWaitTimeout/checkTimeout are legacy diagnostic settings, not launch deadlines.
    -- launchSettleDelay is used only when heartbeat is explicitly disabled.
    -- One loading slot, account/session heartbeats (Menu 12).
    -- Existing user configs get these defaults at runtime; updates do not overwrite them.
    launchSafety = {
        stableHeartbeats = 3,
        stableSeconds = 20,
        retryCooldown = 120,
        maxAttempts = 3,
    },
    launchWaitInterval = 3,
    launchWaitTimeout = 60,
    launchJoinTimeout = 240,
    launchSettleDelay = 20,
    -- launchEmptyDelay: short wait (s) after a clone with no account, so its window
    -- can appear before the next clone starts.
    launchEmptyDelay = 5,
    -- A clone without an account is left alone on its login screen, but if it CLOSED
    -- (force close: process gone or no window left) it is opened again, gently (no
    -- force-stop) and at most once per noLoginCooldown seconds.
    relaunchNoLogin = true,
    -- Status reports to a Discord webhook (one message kept up to date + event
    -- messages). Empty url = off. Set it in Main Menu 8) Discord Webhook.
    webhook = {
        url = "",
        interval = 300,
        screenshot = true,
        events = true,      -- separate message when Delta asks for a key
        hideNames = true,
        deviceName = "",    -- Label Device Name in report title/body; "" = device model
    },
    -- Delta's key entry ("license" inside the Delta folder). "" = find automatically.
    deltaLicensePath = "",
    -- Delta's Scripts folder (Menu 4 / bot store scripts here; Autoexecute only gets a
    -- copy from it). "" = Scripts / scripts next to appAutoExecutePath.
    scriptsPath = "",
    -- Game presets (Main Menu 11 / bot). Clones follow `defaultPreset` unless they have
    -- their own `preset = "B"` ("khusus"), or `preset = "-"` (use their own
    -- privateServer). Example:
    --   presets = { A = { name = "Steal an Egg", link = "https://www.roblox.com/games/..." } },
    --   defaultPreset = "A",
    presets = {},
    defaultPreset = "",
    -- Remote control through the Discord bot (docs/discord_bot_prd.md). url or secret
    -- empty = off. Commands run while the monitor / Launch All is running.
    remote = {
        url = "",       -- e.g. https://my-bot.onrender.com ("" = take it from remote_url.txt)
        -- urlManual = true is set when the URL is typed in Menu 8: remote_url.txt never replaces it
        secret = "",    -- same as the bot's DEVICE_SECRET
        interval = 30,  -- seconds between syncs
    },
    noLoginCooldown = 120,
    -- Arrange the clones' floating windows in a grid (App Cloner floating window).
    -- The window bounds are written into the clone's prefs while it is stopped,
    -- right before launch. On by default. columns = 0 picks automatically.
    -- A clone can override its spot with window = { left=, top=, right=, bottom= }.
    windowLayout = {
        enabled = true,
        columns = 0,
        gap = 0,
        offsetTop = 0,       -- extra top margin; auto grid still reserves the Android status bar
        topInset = 0,        -- 0 = detect once per session; >0 pins the status bar height in pixels
        screenWidth = 0,     -- 0 = detect once per session; set with screenHeight to pin the display size
        screenHeight = 0,
        overlap = 80,
    },
    -- In-game heartbeat: rejoin installs the managed script into both Delta and
    -- Arceus X Autoexec folders. Set additionalAutoExecutePaths = {} to disable
    -- the Arceus X copy, or replace the list with other executor Autoexec paths.
    -- Inside the game it reports in-game / kicked, fps, memory;
    -- a kick is rejoined at once. saver = lower CPU/GPU/RAM (3D rendering off, FPS cap,
    -- low graphics, mute). Without a ready heartbeat the queue waits; RSS is diagnostic only.
    heartbeat = {
        enabled = true,
        interval = 10,
        staleAfter = 90,
        workspacePath = "",
        additionalAutoExecutePaths = { "/sdcard/Arceus X/Autoexec" },
        saver = {
            enabled = false,
            disable3d = true,
            fpsCap = 15,
            lowGraphics = true,
            mute = true,
        },
    },
    -- Login check: the .ROBLOSECURITY token on disk is verified against Roblox with curl
    -- (users.roblox.com/v1/users/authenticated). A rejected token (HTTP 401) counts as
    -- logged out, so the clone shows NoLogin and is never force-stopped/relaunched.
    -- loginVerifyInterval: seconds between checks per clone (a changed token is
    -- re-checked right away). Needs `pkg install curl`.
    loginVerifyRemote = true,
    loginVerifyInterval = 600,
    -- Run shell commands as root (su -c). Required on a rooted device Android 11+ so that
    -- ps/pidof/pgrep can actually see the app processes the Monitor depends on; Termux run
    -- as a normal user cannot see other apps' processes. Set false on a non-root device.
    useRoot = true,
    -- Start empty; the setup wizard or Instance Manager adds installed packages.
    instances = {}
}
