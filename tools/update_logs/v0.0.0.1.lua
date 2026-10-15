return {
    title   = "Rejoin Update Logs",
    mention = "",  -- kosong = tanpa mention; ping role: "<@&ROLE_ID>"
    version = "v0.0.0.1",
    color   = 0x5865F2,

    notes = {
        "Found any bugs or issues? Feel free to report them to the developers!",
        "Got ideas or suggestions for new scripts? We'd love to hear them!",
        "Update otomatis tiap reboot, atau manual: sh ~/rejoin/update.sh",
    },

    added = {
        "Notif Discord \"Delta minta key\" — dikirim sekali tiap file license Delta hilang",
        "Nama device di pesan webhook (Menu 9 → 7)",
        "Pakai pesan status lama setelah ganti device (Menu 9 → 8), jadi ga ada pesan nyangkut",
        "Info versi + status install instan & auto-start di atas Main Menu",
        "Generator update log (tools/update_log.lua)",
    },

    improved = {
        "Launch All: clone yang sudah login dibuka duluan, yang belum login paling akhir",
        "Launch All nunggu tiap clone benar-benar masuk game (karakter spawn + aset selesai) baru buka clone berikutnya",
        "Grid jendela: baris atas lebih tinggi biar menu Roblox kelihatan sampai More",
        "Install ulang jadi cepat (upgrade paket dilewati kalau sudah lengkap)",
        "Main Menu dirapihin: 9 = Discord Webhook, 10 = Jendela & Mode Hemat, 0 = Exit di paling bawah",
        "README & panduan install dirapihin (cukup 1 perintah)",
    },

    fixed = {
        "Fix pesan status webhook ga ke-update (runtime beku)",
        "Fix CPU tampil \"-\" di laporan pertama",
    },

    deleted = {
        "Remove notif ke-kick / recovery gagal / engine mulai di Discord (tetap di log)",
    },
}
