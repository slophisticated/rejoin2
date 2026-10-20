# Panduan Rejoin versi publish

## Siapkan device

1. Root aktif lewat Magisk/KernelSU; izinkan Termux memakai root.
2. Pasang Termux dan Termux:Boot dari sumber yang sama.
3. Jalankan `termux-setup-storage`, izinkan storage, lalu `pkg install lua53 curl sqlite git`.
4. Buka aplikasi Termux:Boot sekali agar Android mengaktifkannya.

## Pasang loader branch percobaan

```sh
curl -fL -o /sdcard/Download/yanamin.lua https://raw.githubusercontent.com/slophisticated/rejoin2/rejoinversifinal/yanamin.lua
lua /sdcard/Download/yanamin.lua
```

Kalau device memakai folder `/sdcard/download`, sesuaikan kedua path. Loader sudah
berisi semua modul dan template; tidak perlu clone repo. Config dan log ada di
`/sdcard/yanamin`, bukan folder Download. Download ulang hanya mengganti loader.
Source modular/installer juga tersedia di [README](README.md#source-modular-dan-update).

## Atur clone

- **Menu 2**: Auto Detect Roblox atau input package manual. Pilih username berbeda
  tiap clone. Package yang terdeteksi tidak otomatis dianggap sudah login.
- **Menu 5**: login dengan cookie yang dimiliki, cek token, atau logout clone.
- **Menu 11**: buat preset game/default; Menu 2 mengatur pengecualian per clone.
  Pilihan `d` saat edit berarti ikut default dan langsung disimpan.
- **Menu 9**: grid jendela, heartbeat, mode hemat. Grid mempertahankan ruang status
  bar Android. Mode hemat opsional, mulai 15 FPS bila diperlukan.
- **Menu 12**: 3 heartbeat baru, stabil minimal 20 detik, cooldown 120 detik,
  maksimal 3 percobaan. Default runtime berlaku untuk config lama.
- **Menu 14**: masukkan key Delta yang kamu dapatkan sendiri; key disembunyikan saat
  diketik dan disimpan ke file license Delta.
- Heartbeat otomatis dipasang di `/sdcard/Delta/Autoexecute` dan
  `/sdcard/Arceus X/Autoexec`. Path kedua bisa diubah lewat
  `heartbeat.additionalAutoExecutePaths`; isi `{}` untuk menonaktifkan salinan Arceus X.
- **Menu 15**: masukkan link folder GoFile, pilih APK dari daftar (contoh `1-3`), lalu
  Rejoin mengunduh dan memasang pilihan satu per satu. File APK dihapus setelah
  pemasangan sukses; jika gagal, file tetap di `/sdcard/Download/Rejoin`. Jika GoFile
  meminta autentikasi, masukkan token API saat
  diminta; token disembunyikan dan tidak disimpan. Instalasi dapat gagal jika signature
  APK berbeda dari aplikasi yang sudah terpasang atau versi APK lebih lama.
- **Menu 8**: webhook status, nama device, HWID/URL bot. Bot opsional; lihat
  [panduan bot](bot/README.md). Tes koneksi hanya memakai `/api/ping`.
- Bot bisa menjadwalkan auto-logout per clone lewat `/alarm set` dengan tanggal dan
  waktu WIB. Monitor device harus aktif saat alarm berjalan.
- Untuk jadwal massal, ekspor spreadsheet sebagai CSV dan upload lewat `/alarm import`.
  Isi `DEVICE`, `USN`, `TANGGAL`, `JAM`; cek file preview dan konfirmasi. Jadwal lama
  ditandai akan diganti, dan baris yang Delete-nya dicentang dilewati.
- Bot juga mendukung `/cookie inject` untuk satu clone. Masukkan cookie milikmu lewat
  modal privat; device harus online dan monitor aktif.
- `/delta input-key` membuka modal privat untuk key Delta yang kamu dapatkan sendiri.
  Key dikirim sekali ke device online dan tidak disimpan bot; device menulisnya ke file
  `license`, lalu menjadwalkan rejoin semua clone satu per satu. Rejoin tidak memeriksa
  file key atau menahan antrean berdasarkan file tersebut; validasi tetap dilakukan Delta.
- Force-stop saat logout, inject cookie, atau recovery menyasar package clone pada user
  Android aktif. Pastikan satu package hanya dipakai satu instance; Rejoin membatalkan
  force-stop jika package terdaftar ganda.
- Clone yang dibuka di layar login akan masuk ke link game setelah kamu login, selama
  clone tersebut punya link game/preset yang valid.

## Jalankan

**Menu 1** membuka clone login duluan satu per satu, lalu clone kosong dengan jeda
5 detik. **Menu 13** memantau proses yang sudah jalan. Keluar monitor memakai Ctrl+C.
**Menu 6** memasang/melepas auto-boot dan membaca log boot. **Menu 7** menampilkan
konfirmasi uninstall dan targetnya; data aplikasi clone/Delta tidak dihapus.

Heartbeat v3 menulis `loading` sampai karakter dan aset siap, lalu `ingame`. Package
terikat pada username dan token sesi launch, sehingga heartbeat clone lain atau
sesi sebelumnya tidak dipakai. Setelah update, buka ulang clone bertahap supaya
script baru dijalankan. Game yang membutuhkan pemilihan karakter/menu bisa tetap
menunggu sampai karakter muncul.

Tidak ada batas RAM atau keputusan recovery berdasarkan RSS. Tanpa heartbeat siap,
clone tetap menahan slot. Timeout 240 detik menampilkan **Perlu dicek**, tidak membuka
clone berikutnya/restart berulang. Heartbeat siap yang datang terlambat melanjutkan
antrean. Rejoin tidak mendeteksi status key Delta; jika layar Delta meminta key,
masukkan key lewat alur resmi Delta atau gunakan Menu 14 untuk menyimpan key manual.

Bot `/restart clones:<clone>` mencoba ulang clone yang ditahan. Tanpa bot, hentikan
monitor lalu pilih Menu 1. Proses mati/kick/heartbeat ingame berhenti masuk retry
terbatas. Clone logout hanya dibuka lembut tanpa force-stop.

## Log dan troubleshooting

```sh
cat /sdcard/yanamin/data/boot.log
grep -E '\[QUEUE\]|\[KEY\]' /sdcard/yanamin/data/rejoin.log | tail -50
grep -E '\[LOGIN\]|\[STATUS\]|\[WINDOW\]' /sdcard/yanamin/data/rejoin.log | tail -40
cat /sdcard/yanamin/launch.log
kill $(cat /sdcard/yanamin/data/monitor.pid)
```

| Gejala | Pemeriksaan |
|---|---|
| Cek username | Pastikan akun terbaca dan username tidak dipakai dua package |
| Perlu dicek | Selesaikan loading/menu/get key; heartbeat siap bisa melanjutkan sendiri |
| Clone terakhir sering FC | Kurangi clone serentak yang menetap, coba mode hemat; batas fisik RAM tetap berlaku |
| Webhook tidak muncul | Menu 8, tes kirim, cek koneksi dan log; pesan lama bisa dipakai ulang |
| Bot tes HTTP 404 | Update bot agar endpoint `/api/ping` tersedia |
| Boot tidak jalan | Buka Termux:Boot sekali, Menu 6 pasang ulang, cek path loader di log |
| Folder tidak bisa ditulis | Jalankan `termux-setup-storage` dan beri izin |

Tes lokal memakai simulasi Lua/HTTP. Timing loading, efek FPS/rendering, dan pemakaian
RAM nyata perlu diuji di device. Mode hemat membantu beban, tetapi tidak menjamin
empat clone muat pada setiap game di device 4 GB.
