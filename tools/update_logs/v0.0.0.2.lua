return {
    title   = "Rejoin Update Logs",
    mention = "",  -- kosong = tanpa mention; ping role: "<@&ROLE_ID>"
    version = "v0.0.0.2",
    color   = 0x5865F2,

    notes = {
        "Found any bugs or issues? Feel free to report them to the developers!",
        "Got ideas or suggestions for new scripts? We'd love to hear them!",
        "Update otomatis tiap reboot, atau manual: sh ~/rejoin/update.sh",
    },

    added = {
        "Bot Discord: atur semua device dari slash command (status, game, preset, clone, script, screenshot, config) — balasan cuma kelihatan sama kamu",
        "Preset game + preset default: ganti game semua clone cukup ganti default sekali (Menu 11 / /default)",
        "Script Manager: script di folder Scripts Delta, Autoexecute ambil copy dari Scripts (Menu 6 / /script, /autoexec)",
        "Logout akun clone (Menu 7 → 4 / /clone logout) — clone yang di-logout ga di-rejoin lagi",
        "Screenshot layar device dari Discord (/screenshot) + rejoin beberapa clone sekaligus",
        "Device per owner: temen bisa pakai bot yang sama, tiap orang cuma lihat device miliknya",
        "Cek root di awal: berhenti dengan petunjuk kalau root belum diizinkan",
    },

    improved = {
        "Main Menu: 1 = Start Monitor (tanpa launch ulang clone), 5 = Launch All + Monitor",
        "URL bot otomatis dari repo, tiap device cukup isi secret (Menu 9 → 10)",
        "Ganti nama device / setting Discord di Menu 9 langsung dipakai engine tanpa restart",
        "Inject Cookie: kalau tetap logout, dikasih tau kemungkinan penyebabnya (proteksi lokasi Roblox / versi app)",
        "Installer beresin sendiri upgrade paket yang sempat ke-stop (dpkg interrupted)",
    },

    fixed = {
        "Fix Launch All ga nunggu clone berikutnya (RAM turun pas loading dikira clone mati)",
        "Fix device kelihatan offline di bot selama Launch All",
        "Fix runtime clone selalu 0m di cloud phone",
        "Fix logout manual malah di-rejoin lagi",
        "Fix nama device lama nyangkut di bot setelah diganti",
    },

    deleted = {},
}
