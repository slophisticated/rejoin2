return {
    title   = "Rejoin Update Logs",
    mention = "",
    version = "v0.0.0.3",
    color   = 0x5865F2,

    notes = {
        "Update otomatis tiap reboot, atau manual: sh ~/rejoin/update.sh",
        "Update deployment bot juga: Tes koneksi sekarang memakai endpoint /api/ping.",
        "Validasi simulasi: 78 tes bot dan 11 tes regresi Lua lolos; belum diuji langsung di Redfinger.",
    },

    added = {
        "Daftar HWID sekali lewat /hwid redeem: device bisa tersambung tanpa mengisi key/secret di Termux",
    },

    improved = {
        "Pencabutan HWID menunggu channel siap; gagal hapus pesan ditampilkan supaya bisa dicoba ulang",
    },

    fixed = {
        "Fix HWID yang sudah dicabut muncul lagi setelah bot restart saat volume dan channel dipakai bersamaan",
        "Fix clone masih loading direcovery berulang gara-gara RSS turun: ada masa tunggu minimal 60 detik, sementara kick/proses mati tetap ditangani",
        "Fix Tes koneksi bot menghabiskan antrean Launch All/restart tanpa menjalankannya: tes autentikasi terpisah dari sync/ACK",
        "Fix preset ikut default (Menu 2 → 3, pilih d) tidak tersimpan kalau nama/package tidak ikut diubah",
    },

    deleted = {},
}
