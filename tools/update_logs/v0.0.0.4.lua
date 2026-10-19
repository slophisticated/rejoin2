return {
    title = "Rejoin Publish Update Logs",
    mention = "",
    version = "v0.0.0.4",
    color = 0x5865F2,
    notes = {
        "Versi publish: loader yanamin.lua disinkronkan; config dan state tetap di /sdcard/yanamin.",
        "Heartbeat v3 dipasang saat monitor mulai; clone lama perlu dibuka ulang bertahap supaya memakai script baru.",
        "RAM/RSS tetap informasi saja: tidak ada batas RAM atau antrean yang ditahan berdasarkan RAM.",
        "Mode hemat/FPS tetap opsional di Menu 9. Validasi memakai simulasi, belum di device asli.",
    },
    added = {
        "Generator loader satu file yang bisa dibangun ulang dari source; menu boot/uninstall dan autodetect tetap tersedia",
        "Menu 12 Antrean & Heartbeat: jumlah heartbeat stabil, waktu stabil, jeda retry, dan batas percobaan",
        "Status Menunggu key, Cek username, Menunggu stabil, Perlu dicek, dan Jeda retry di dashboard/bot",
    },
    improved = {
        "Launch All, rejoin bot/preset, dan recovery otomatis memakai satu slot loading; bot tetap sync saat antrean menunggu",
        "Identitas heartbeat berdasarkan username yang dipetakan ke package, dengan penanda sesi baru setiap launch",
    },
    fixed = {
        "Timeout tidak lagi membuka clone berikutnya atau mengulang restart: antrean menunggu heartbeat siap / tindakan manual",
        "License Delta hilang + tidak ada heartbeat menahan antrean untuk pemeriksaan/key manual, tanpa menghabiskan retry",
        "RSS rendah tidak lagi memicu recovery; proses mati/kick/heartbeat ingame berhenti memakai retry terbatas",
        "Heartbeat tidak lagi mengaku ingame karena batas waktu loading habis; tunggu karakter dan aset siap",
    },
    deleted = {},
}
