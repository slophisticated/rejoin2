-- Sample config for Rejoin Engine (adjust package names and paths for your device)
return {
    monitorInterval = 5,
    recoveryDelay = 3,
    recoveryRetries = 3,
    checkTimeout = 15,
    debug = true,
    logPath = "data/rejoin.log",
    -- Optional fast filter for auto-detect clone scan (e.g. "com.apengjers."). Empty = disabled.
    clonePackagePrefix = "",
    -- Deteksi freeze/stuck. Recovery baru dipicu setelah freeze 300 detik (5 menit).
    freezeTimeout = 300,
    gracePeriod = 30,
    anrCheckEnabled = true,
    -- Minimum resident memory (MB) for a clone's process to be considered ACTIVE.
    -- A running clone reads ~1 GB while a force-close stub is ~188 MB, so anything
    -- below this is treated as "not really running" and gets relaunched. Tune if needed.
    minRss = 200,
    -- Timeout (seconds) for each shell command (via the `timeout` tool) so a hung
    -- su/dumpsys call can't freeze the whole tool / stop the terminal accepting input.
    shellTimeout = 10,
    -- Menu 1 launch berurutan: buka clone, tunggu jalan (RSS >= minRss, maks
    -- launchWaitTimeout detik), lalu tunggu sampai MASUK GAME (heartbeat Delta, maks
    -- launchJoinTimeout detik) baru clone berikutnya. Tanpa heartbeat: jeda tetap
    -- launchSettleDelay detik. Clone yang belum login tetap dibuka, tapi tidak ditunggu.
    launchWaitInterval = 3,
    launchWaitTimeout = 60,
    launchJoinTimeout = 120,
    launchSettleDelay = 20,
    -- Jeda singkat (detik) setelah clone kosong dibuka, biar jendelanya sempat muncul.
    launchEmptyDelay = 5,
    -- Clone yang belum login dibiarkan di layar login, tapi kalau TERTUTUP (FC /
    -- proses mati / jendela hilang) dibuka lagi pelan-pelan (tanpa force-stop),
    -- maks sekali tiap noLoginCooldown detik. false = jangan pernah dibuka ulang.
    relaunchNoLogin = true,
    -- Laporan status ke Discord webhook (1 pesan yang terus di-update + notif kejadian).
    -- url kosong = mati. Isi lewat Main Menu 10) Discord Webhook.
    webhook = {
        url = "",
        interval = 300,    -- detik antar laporan
        screenshot = true, -- sertakan screenshot layar
        events = true,     -- pesan terpisah saat engine mulai / ke-kick / recovery gagal
        hideNames = true,  -- nama akun disembunyikan (spoiler)
    },
    noLoginCooldown = 120,
    -- Auto atur jendela floating jadi grid (ditulis ke setting clone pas clone mati,
    -- sebelum dibuka). Default NYALA; matikan lewat Main Menu 11) Jendela & Mode Hemat.
    windowLayout = {
        enabled = true,
        columns = 0,   -- 0 = otomatis (4 clone -> 2x2)
        gap = 0,       -- jarak antar jendela (pixel)
        offsetTop = 0, -- ruang kosong di atas layar (pixel)
        overlap = 80,  -- baris atas lebih tinggi sekian pixel (numpuk baris bawah) biar menu Roblox sampai More kelihatan; 0 = grid biasa
    },
    -- Heartbeat Delta: rejoin memasang script ke folder Autoexecute Delta. Dari dalam
    -- game script lapor status (in-game / ke-kick, fps, memori); ke-kick = langsung
    -- rejoin. saver = mode hemat (render 3D mati, FPS dibatasi, grafik rendah, mute).
    heartbeat = {
        enabled = true,
        interval = 10,
        staleAfter = 90,
        workspacePath = "", -- "" = otomatis (folder Workspace di sebelah Autoexecute)
        saver = {
            enabled = false,
            disable3d = true,
            fpsCap = 15,
            lowGraphics = true,
            mute = true,
        },
    },
    -- Cek login: token .ROBLOSECURITY diverifikasi ke Roblox pakai curl. Token yang
    -- ditolak (HTTP 401) = dianggap logout -> status NoLogin, tidak di-force-stop.
    -- loginVerifyInterval: jeda (detik) antar verifikasi per clone.
    loginVerifyRemote = true,
    loginVerifyInterval = 600,
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
    -- Folder tujuan Deploy (Script Manager / AutoExecute). Scripts di-deploy ke sini
    -- sebagai <name>.lua. Path ini shared untuk semua instance (Delta mod: internal storage).
    appAutoExecutePath = "/sdcard/Delta/Autoexecute",
    instances = {
        [1] = {
        id = 1,
        name = "Clone1",
        package = "com.apengjers.v3",
        privateServer = "https://www.roblox.com/games/107778070777162/Steal-An-Egg",
        },
        [2] = {
        id = 2,
        name = "Clone2",
        package = "com.apengjers.v4",
        privateServer = "https://www.roblox.com/games/107778070777162/Steal-An-Egg",
        },
        [3] = {
        id = 3,
        name = "Clone3",
        package = "com.apengjers.v5",
        privateServer = "https://www.roblox.com/games/107778070777162/Steal-An-Egg",
        },
        [4] = {
        id = 4,
        name = "Clone4",
        package = "com.apengjers.v6",
        privateServer = "https://www.roblox.com/games/107778070777162/Steal-An-Egg",
        },
    }
}