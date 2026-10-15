## 📝 Rejoin Installation Guide

## ⚡ Step 1: Root, Termux & Termux:Boot
1. **Root** harus aktif (**Magisk** / **KernelSU**). Buka **Superuser** → pastikan **Termux** diizinkan.
2. Install **[Termux](https://f-droid.org/packages/com.termux/)** dan **[Termux:Boot](https://f-droid.org/packages/com.termux.boot/)** dari **sumber yang sama** (dua-duanya F-Droid, atau dua-duanya GitHub).
   *Termux:Boot itu aplikasi (APK), bukan paket — `pkg install termux-boot` memang selalu gagal.*
3. Buka **Termux**, lalu izinkan akses storage (dibutuhkan untuk folder Delta):
💻 Desktop Copy:
```bash
termux-setup-storage
```
📱 Mobile Copy:
`termux-setup-storage`
*Pilih **Izinkan** saat diminta.*

## 📦 Step 2: Install (1 perintah)
💻 Desktop Copy:
```bash
curl -sL https://raw.githubusercontent.com/slophisticated/rejoin2/main/install.sh | sh
```
📱 Mobile Copy:
`curl -sL https://raw.githubusercontent.com/slophisticated/rejoin2/main/install.sh | sh`

Tunggu sampai muncul **SELESAI**. Installer mengerjakan 8 langkah dan menandai tiap langkah `[OK]` / `[!!]`:
1. Paket Termux (`lua53 sqlite curl git`) — dilewati kalau sudah lengkap, jadi install ulang cepat
2. Perintah `lua`
3. Cek root
4. Download Rejoin ke `~/rejoin` (config lama tetap dipakai kalau install ulang)
5. **Setting device otomatis** + auto atur jendela floating (grid) dinyalakan: animasi mati, Developer options (*Force allow apps on external*, *Force activities to be resizable*, *Enable freeform windows*, *Enable non-resizable in multi-window*), Smallest width 600dp, izin Termux jalan di background (dialog *"always run in background"* tidak muncul lagi) — plus script heartbeat ke folder Autoexecute Delta
6. Cek clone di config terpasang di device
7. Script auto-start + auto-update saat boot
8. Aktifkan Termux:Boot (layar Termux:Boot bisa terbuka sendiri — kembali saja ke Termux)

*Ada `[!!]`? Ikuti petunjuk di baris itu, lalu jalankan perintah install lagi (aman diulang). Kalau `[!!]` di langkah 8: tap ikon Termux:Boot sekali, lalu install lagi.*
*Setelah selesai, **reboot sekali** supaya freeform/resizable aktif.*

## 🚀 Step 3: Run & Setup
💻 Desktop Copy:
```bash
cd ~/rejoin && lua main.lua
```
📱 Mobile Copy:
`cd ~/rejoin && lua main.lua`

1. **Instances** — menu `2`: sesuaikan package clone (mis. `com.apengjers.v3`) + link game / Private Server tiap clone.
2. **Jeda launch** — menu `3` → `13`: `launchJoinTimeout` (default 240 dtk: maks tunggu clone **masuk game** lewat heartbeat Delta sebelum clone berikutnya) dan `launchSettleDelay` (20 dtk, dipakai kalau heartbeat tidak ada), lalu `15) Save and Exit`.
3. **Jendela & Mode Hemat** — menu `10` (pilih nomor, langsung tersimpan):
   - Auto atur jendela floating (grid) — sudah **nyala** dari installer. Baris atas numpuk 80 px ke baris bawah biar menu Roblox sampai *More* kelihatan (pilihan `9`, 0 = grid biasa)
   - Heartbeat Delta (status dari dalam game, langsung rejoin kalau ke-kick)
   - Mode hemat (render 3D mati, FPS dibatasi, grafik rendah) + batas FPS
4. **Discord Webhook** (opsional) — menu `9`: `1)` paste URL webhook channel (Discord → Edit Channel → Integrations → Webhooks → New Webhook → Copy Webhook URL), isi `7) Nama device` (mis. nama di Redfinger, biar tiap device kebedain), lalu `6) Kirim tes sekarang`. Status di-update tiap 5 menit + screenshot; notif terpisah hanya kalau **Delta minta key** (file license di folder Delta hilang).
5. **Start** — menu `1` (Launch All + Monitor). Keluar: **Ctrl+C**.
*Clone yang sudah login dibuka duluan, satu per satu: tiap clone ditunggu sampai heartbeat-nya bilang masuk game, baru clone berikutnya. Clone yang belum login dibuka paling akhir dan tidak ditunggu.*

## 🔁 Auto Start & Update
Cukup **reboot** cloud phone: Rejoin otomatis **update dari GitHub** lalu jalan sendiri (±10 detik setelah boot, tanpa jendela Termux). Config kamu tidak tertimpa.

| Perlu | Perintah |
|---|---|
| Update manual tanpa reboot | `sh ~/rejoin/update.sh` |
| Stop engine yang jalan dari boot | `kill $(cat ~/rejoin/data/monitor.pid)` |
| Matikan auto-update | `touch ~/rejoin/data/no-auto-update` |
| Setting device ulang / kembalikan | `sh ~/rejoin/device_setup.sh` / `sh ~/rejoin/device_setup.sh --undo` |
| Tampilan kekecilan / kegedean (default 600, angka tersimpan) | `SMALLEST_WIDTH=800 sh ~/rejoin/device_setup.sh` lalu buka ulang clone |
| Install ulang (config tetap) | perintah di Step 2 |

*Mau pakai menu manual saat engine boot sedang jalan? Stop engine boot dulu (perintah di atas), kalau tidak muncul pesan `engine lain masih jalan`.*

## 🛠️ Troubleshooting
| Masalah | Solusi |
|---|---|
| `CANNOT LINK EXECUTABLE ... libcurl` | `apt update && apt full-upgrade -y`, lalu ulangi install |
| `apt update` gagal / 404 | `termux-change-repo` → **Mirror group** → **Mirrors in Asia**, lalu ulangi |
| Reboot tapi clone tidak terbuka | `cat ~/rejoin/data/boot.log` — kosong/tidak ada = Termux:Boot belum aktif: tap ikonnya sekali, cek `su -c "dumpsys package com.termux.boot \| grep stopped="` harus `stopped=false` |
| Status / login aneh | `grep -E "\[LOGIN\]\|\[STATUS\]" ~/rejoin/data/rejoin.log \| tail -40` |
| Jendela floating tidak di grid | `grep WINDOW ~/rejoin/data/rejoin.log \| tail` (dibetulkan otomatis saat clone dibuka ulang) |
| Notif key tidak pernah muncul | `grep KEY ~/rejoin/data/rejoin.log` — harus ada baris `file license Delta: <path>`. Tidak ketemu → isi `deltaLicensePath` di `config/config.lua` |
| Heartbeat Delta tidak jalan | `ls /sdcard/Delta/Workspace/rejoin/` harus ada `hb_<username>.txt` setelah masuk game (Delta harus sudah di-key) |
| Terminal nyangkut / Ctrl+C tidak mempan | `stty sane` |
| Notification bar hilang (Redfinger) | `su -c "cmd statusbar expand-notifications"` |

*Note: Grant Root permissions when prompted.*
