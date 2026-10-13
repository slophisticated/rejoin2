## 📝 Rejoin Installation Guide

## ⚡ Step 1: Root, Termux & Termux:Boot
1. **Root** harus aktif (**Magisk** / **KernelSU**). Buka **Superuser** → pastikan **Termux** diizinkan.
2. Install **[Termux](https://f-droid.org/packages/com.termux/)** dan **[Termux:Boot](https://f-droid.org/packages/com.termux.boot/)** dari **sumber yang sama** (dua-duanya F-Droid, atau dua-duanya GitHub).
   *Termux:Boot itu aplikasi (APK), bukan paket — `pkg install termux-boot` memang selalu gagal.*
3. **Tap ikon Termux:Boot sekali** sampai muncul halaman teks, lalu kembali ke Termux.
4. Di Termux, izinkan akses storage (dibutuhkan untuk folder Delta):
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
1. Paket Termux (`lua53 sqlite curl git`)
2. Perintah `lua`
3. Cek root
4. Download Rejoin ke `~/rejoin` (config lama tetap dipakai kalau install ulang)
5. **Setting device otomatis**: animasi mati, Developer options (*Force allow apps on external*, *Force activities to be resizable*, *Enable freeform windows*, *Enable non-resizable in multi-window*), Smallest width 600dp — plus script heartbeat ke folder Autoexecute Delta
6. Cek clone di config terpasang di device
7. Script auto-start + auto-update saat boot
8. Aktifkan Termux:Boot

*Ada `[!!]`? Ikuti petunjuk di baris itu, lalu jalankan perintah install lagi (aman diulang).*
*Setelah selesai, **reboot sekali** supaya freeform/resizable aktif.*

## 🚀 Step 3: Run & Setup
💻 Desktop Copy:
```bash
cd ~/rejoin && lua main.lua
```
📱 Mobile Copy:
`cd ~/rejoin && lua main.lua`

1. **Instances** — menu `2`: sesuaikan package clone (mis. `com.apengjers.v3`) + link game / Private Server tiap clone.
2. **Settings** — menu `3` → `13`:
   - Jeda launch (`launchSettleDelay`, default 20 dtk: waktu masuk game sebelum clone berikutnya)
   - **Auto atur jendela floating** jadi grid (y/n)
   - **Heartbeat Delta** (status dari dalam game, langsung rejoin kalau ke-kick) (y/n)
   - **Mode hemat** (render 3D mati, FPS dibatasi, grafik rendah) (y/n)
   - Simpan: `15) Save and Exit`
3. **Start** — menu `1` (Launch All + Monitor). Keluar: **Ctrl+C**.
*Clone yang belum login dibuka tapi tidak ditunggu; yang sudah login ditunggu sampai masuk game.*

## 🔁 Auto Start & Update
Cukup **reboot** cloud phone: Rejoin otomatis **update dari GitHub** lalu jalan sendiri (±10 detik setelah boot, tanpa jendela Termux). Config kamu tidak tertimpa.

| Perlu | Perintah |
|---|---|
| Update manual tanpa reboot | `sh ~/rejoin/update.sh` |
| Stop engine yang jalan dari boot | `kill $(cat ~/rejoin/data/monitor.pid)` |
| Matikan auto-update | `touch ~/rejoin/data/no-auto-update` |
| Setting device ulang / kembalikan | `sh ~/rejoin/device_setup.sh` / `sh ~/rejoin/device_setup.sh --undo` |
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
| Heartbeat Delta tidak jalan | `ls /sdcard/Delta/Workspace/rejoin/` harus ada `hb_<username>.txt` setelah masuk game (Delta harus sudah di-key) |
| Terminal nyangkut / Ctrl+C tidak mempan | `stty sane` |
| Notification bar hilang (Redfinger) | `su -c "cmd statusbar expand-notifications"` |

*Note: Grant Root permissions when prompted.*
