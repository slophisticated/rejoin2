# Rejoin Engine

Rejoin menjalankan dan menjaga banyak clone Roblox (App Cloner + Delta) di cloud phone Android yang sudah di-root. Ditulis dalam **Lua** dan jalan di **Termux**. Clone dibuka satu per satu, dipantau terus, dan langsung di-rejoin kalau ke-kick, freeze, atau force close. Semua data disimpan di device, tidak ada server.

> Panduan langkah demi langkah yang siap dibagikan: **[setup.md](setup.md)**

---

## ⚡ Install (1 perintah)

**Yang perlu disiapkan dulu:**
- Root aktif (**Magisk** / **KernelSU**).
- **Termux** dan **Termux:Boot** dari sumber yang **sama** (dua-duanya F-Droid, atau dua-duanya GitHub).
- Di Termux, jalankan `termux-setup-storage` lalu pilih **Izinkan**.

**Install, atau update dari versi lama:**
```sh
curl -sL https://raw.githubusercontent.com/slophisticated/rejoin2/main/install.sh | sh
```

Tunggu sampai muncul **SELESAI**, lalu **reboot sekali**. Tiap langkah ditandai `[OK]` atau `[!!]`:

1. Paket Termux (`lua53 sqlite curl git`)
2. Perintah `lua`
3. Cek root
4. Download Rejoin ke `~/rejoin`. Kalau folder lama sudah ada (termasuk hasil `git clone` dulu), config dan log tetap dipakai, jadi **tidak perlu `rm -rf`**.
5. Setting device: animasi mati, freeform / resizable / *force allow on external*, smallest width 600dp, dan izin Termux jalan di background
6. Cek clone yang ada di config, menyalakan auto atur jendela, dan memasang script heartbeat ke Autoexecute Delta
7. Script boot (auto-update + auto-start)
8. Mengaktifkan Termux:Boot

**Yang otomatis di-allow:** dialog *"Let app always run in background?"*, aktivasi Termux:Boot, dan Developer options.
**Yang tetap perlu tap sekali:** izin root di Magisk (pilih *Grant*) dan izin storage (`termux-setup-storage`).

Perintah yang sama aman dijalankan ulang kapan saja. Setelah install, **tidak perlu `git pull` lagi**: setiap boot, Rejoin update sendiri dari GitHub, lalu langsung jalan.

---

## Fitur

- **Launch All berurutan.** Clone dibuka satu per satu. Clone berikutnya baru dibuka setelah clone sebelumnya **benar-benar masuk game**: karakter sudah spawn dan aset selesai dimuat (lewat heartbeat Delta). Clone yang belum login hanya diberi jeda 5 detik.
- **Auto rejoin.** Clone yang ke-kick, disconnect, freeze, atau force close dibuka ulang dan masuk ke game / private server lagi.
- **Heartbeat Delta.** Script di Autoexecute Delta melaporkan status dari dalam game: in-game atau ke-kick, FPS, ping, dan memori. Kalau ke-kick, langsung rejoin tanpa menunggu.
- **Mode hemat.** Render 3D mati, FPS dibatasi, grafik paling rendah, suara mati. CPU dan RAM per clone turun banyak.
- **Auto atur jendela.** Jendela floating clone disusun jadi grid (4 clone → 2×2). Baris atas sedikit lebih tinggi supaya menu Roblox kelihatan sampai *More*. Posisi dicek terus.
- **Laporan Discord webhook.** Satu pesan status di-update tiap 5 menit (RAM, CPU, suhu, uptime, dan memori per clone + screenshot), plus notif **🔑 Delta minta key** kalau file license Delta hilang. Tiap pesan diberi nama device (diisi di Menu 10).
- **Cek login.** Akun diverifikasi ke Roblox. Clone yang belum login **tidak pernah di-force-stop**, tapi dibuka lagi kalau tertutup.
- **Auto start + auto update saat boot** lewat Termux:Boot, tanpa jendela Termux. Config tidak tertimpa.
- **Setting device otomatis.** Animasi, freeform, smallest width, dan izin background diatur sekali dari installer.
- **Dashboard live** dengan username tiap clone, status berwarna, FPS/RAM dari heartbeat, dan progres launch.
- **Inject Cookie.** Masukkan token `.ROBLOSECURITY` ke clone. Token diverifikasi dulu sebelum ditulis.
- **AutoExecute Manager.** Tambah, edit, atau hapus script di folder Autoexecute Delta langsung dari Termux.
- **Prioritas rendah.** Clone di-`renice` / `ionice` supaya Termux dan sistem tetap responsif.

---

## Pemakaian

```sh
cd ~/rejoin && lua main.lua
```

| Menu | Isi |
|---|---|
| `1` Launch All + Monitor | Buka semua clone berurutan, lalu pantau |
| `2` Instances Manager | Package clone + link game / private server |
| `3` Settings | Pengaturan umum; `13` = jeda launch (`launchJoinTimeout`, `launchSettleDelay`, dst.) |
| `4` View Logs | Lihat `data/rejoin.log` |
| `5` Start Monitor | Pantau saja, tanpa launch |
| `6` AutoExecute Manager | Kelola script Autoexecute Delta |
| `7` Inject Cookie | Login clone pakai cookie |
| `8` Dump Cookies (debug) | Cek baris cookie clone (value tidak ditampilkan) |
| `9` Exit | |
| `10` Discord Webhook | URL, interval, screenshot, notif key, kirim tes, nama device |
| `11` Jendela & Mode Hemat | Grid, heartbeat, mode hemat, batas FPS, tinggi tambahan baris atas |

Keluar dari monitor: **Ctrl+C**. Perubahan di menu 10 dan 11 langsung tersimpan.

---

## Perintah berguna

| Perlu | Perintah |
|---|---|
| Update manual tanpa reboot | `sh ~/rejoin/update.sh` |
| Cek versi | `git -C ~/rejoin log --oneline -1` |
| Stop engine yang jalan dari boot | `kill $(cat ~/rejoin/data/monitor.pid)` |
| Matikan auto-update | `touch ~/rejoin/data/no-auto-update` |
| Matikan auto-start saat boot | `rm ~/.termux/boot/start-rejoin.sh` (install ulang untuk menyalakan lagi) |
| Setting device ulang / kembalikan ke bawaan | `sh ~/rejoin/device_setup.sh` / `sh ~/rejoin/device_setup.sh --undo` |
| Ganti smallest width (angka diingat) | `SMALLEST_WIDTH=700 sh ~/rejoin/device_setup.sh` |
| Jalan tanpa menu (seperti boot) | `cd ~/rejoin && lua main.lua --headless --start-monitor --auto-launch` |

Hanya satu engine yang boleh jalan. Kalau engine dari boot masih aktif dan kamu buka menu `1` / `5`, muncul pesan `engine lain masih jalan`. Stop dulu engine boot-nya dengan perintah di atas.

---

## Konfigurasi

Semua bisa diatur dari menu. Isinya tersimpan di `config/config.lua` dan tetap aman saat update atau install ulang.

Link game per clone (`privateServer`) menerima:

| Jenis | Contoh |
|---|---|
| Game publik | `https://www.roblox.com/games/107778070777162/Steal-An-Egg` |
| Private server | `https://www.roblox.com/share?code=62e6ddb1dc13094d872ea3f91ec427c8&type=Server` |
| Deep link | `roblox://experiences/107778070777162` |

Link game publik otomatis diubah ke deep link supaya langsung join. Link private server dibuka apa adanya.

---

## Troubleshooting

Tabel lengkap ada di **[setup.md](setup.md)** (bagian Troubleshooting). Log yang paling sering dipakai:

```sh
cat ~/rejoin/data/boot.log                                               # boot / auto-update
grep -E "\[LOGIN\]|\[STATUS\]" ~/rejoin/data/rejoin.log | tail -40       # status & login
grep -E "launching|in game|heartbeat" ~/rejoin/data/rejoin.log | tail -20 # urutan Launch All
```

Riwayat perubahan: **[docs/changelog.md](docs/changelog.md)**.

---

## Struktur project

```
rejoin/
├── main.lua            # entry point + main menu
├── install.sh          # installer 1 perintah
├── update.sh           # auto-update (dipanggil saat boot)
├── termux-boot.sh      # engine saat boot (restart otomatis)
├── device_setup.sh     # setting device (root)
├── run.sh              # pengawas terminal (Ctrl+C)
├── config/             # config.lua (punyamu) + template.lua
├── core/               # menu & config
├── managers/           # monitor, recovery, heartbeat, webhook, window_layout, auth, ...
├── scripts/            # rejoin_heartbeat.lua (dipasang ke Autoexecute Delta)
├── utils/              # shell, file, timer, ...
└── data/               # log & status runtime (rejoin.log, boot.log, monitor.pid)
```

---

## Lisensi / Kontribusi

Project ini dikembangkan mandiri untuk keperluan otomatisasi. Gunakan dengan bijak sesuai ketentuan platform Roblox dan kebijakan masing-masing perangkat.
