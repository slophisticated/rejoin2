# AGENTS.md — konteks project untuk AI agent (opencode, dll)

Baca ini dulu sebelum ngubah apa pun. Isinya hasil kerja panjang bareng user: apa itu
project ini, aturan teknis yang terbukti dari bug nyata, alur kerja repo, dan
preferensi user.

---

## 1. Tentang project

**Rejoin** = engine Lua 5.3 yang jalan di **Termux** di cloud phone **Redfinger**
(Android 10, 720x1280, density 192, root **Magisk**). Fungsinya buka dan jaga banyak
clone Roblox dari **App Cloner** (floating window) dengan executor **Delta**. Package
clone contohnya `com.apengjers.v3` … `v6`.

Fitur utama:
- **Launch All berurutan**: clone yang udah login dibuka duluan, satu-satu. Tiap clone
  ditunggu sampai heartbeat bilang udah di dalam game, baru clone berikutnya. Clone
  yang belum login dibuka paling akhir dan cuma dikasih jeda 5 detik.
- **Monitor + auto rejoin**: kick, freeze, sama FC ditangani otomatis. Clone yang
  belum login **ga pernah di-force-stop**, cuma dibuka lagi kalau ketutup.
- **Heartbeat Delta**: `scripts/rejoin_heartbeat.lua` dipasang ke folder Autoexecute
  Delta, terus nulis `Workspace/rejoin/hb_<username>.txt`. Ada juga mode hemat (render
  3D mati, FPS cap).
- **Grid jendela floating**: posisi ditulis ke prefs App Cloner. Baris atas sedikit
  numpuk (`overlap`).
- **Discord webhook**: satu pesan status yang di-edit tiap 5 menit, plus notif
  "Delta minta key" dan nama device.
- **Install 1 perintah** (`install.sh`), **auto-update + auto-start pas boot**
  (Termux:Boot), **setting device** (`device_setup.sh`), **root handler** di awal.

## 2. Repo & alur kerja (PENTING)

| Repo | Fungsi |
|---|---|
| `slophisticated/rejoin2` (repo ini) | **Dev / trial and error.** Push ke `main`. Device tes auto-update dari `main` tiap boot. |
| `apengjers/rejoin` (punya temen user) | **Versi publish.** Sengaja **beda**: state di `/sdcard/yanamin`, loader 1 file `yanamin.lua` (dibundel `tools/bundle_loader.js`), menu Uninstall, dll. |

- **Jangan bandingin atau nyamain** dua repo itu kecuali user yang minta.
- Agent **ga punya akses tulis** ke `apengjers/rejoin`. Repo itu public, jadi cuma bisa
  di-clone buat dibaca.
- **Port fitur ke versi publish** (biar ga conflict):
  1. Mulai dari `main` repo temen yang **paling baru**.
  2. Pasang fiturnya dan **sesuain ke struktur dia**, jangan nyalin mentah dari rejoin2.
  3. Push ke `rejoin2` di branch `publish/<fitur>`, **bukan** `main`.
  4. User nerusin dari Termux:
     `git fetch origin publish/<fitur> && git push temen FETCH_HEAD:refs/heads/<fitur>`
  5. Temen user bikin PR terus merge.
- Clone dari installer itu `--depth 1`. Sebelum push ke repo temen dari Termux:
  `git fetch --unshallow origin`. Kalau ga, error `did not receive expected object`.
- Push dari Termux pake **token classic** (scope `repo`). Fine-grained ga bisa buat repo
  orang lain. Token jangan pernah ditulis ke file atau chat log.

## 3. Peta kode

```
main.lua              entry + Main Menu (1 Start Monitor, 2-4, 5 Launch All + Monitor, 6-8, 9 Discord Webhook & Bot,
                      10 Jendela & Mode Hemat, 11 Preset Game, 0 Exit)
                      flag: --headless --start-monitor --auto-launch --dry-run --no-wizard
                            --install-heartbeat --enable-window-layout (one-shot installer)
run.sh                supervisor terminal (Ctrl+C). main.lua jalan di bawahnya (REJOIN_WRAPPER=1)
core/                 menu CLI (settings_cli = Menu 3, item 13 jeda launch; webhook_cli = 9;
                      display_cli = 10; preset_cli = 11), config (+ Config.reload), logger,
                      root_check, setup_wizard
managers/remote.lua   klien bot Discord: POST /api/sync + /api/ack, SCHEMA setting yang boleh
                      diubah bot, handler command (game, preset_set, config_set, ...).
                      Kontrak lengkap: docs/discord_bot_prd.md (bot dibuat terpisah)
                      URL kosong + secret ada -> ambil URL dari remote_url.txt (repo)
                      remote.urlManual (URL diketik di Menu 9) -> ga pernah diganti remote_url.txt
bot/                  bot Discord (Node). Device per owner: env OWNERS=idDiscord:secret (secret = akun),
                      atau daftar HWID (bot/src/registry.js, /hwid redeem; device kirim header
                      X-Rejoin-Hwid = Remote.deviceId, `lua main.lua --hwid`; secret opsional)
managers/instance.lua presetOf/gameLink (preset khusus -> defaultPreset -> privateServer;
                      preset "-" = link sendiri), migrateToPresets, find, save, load (urut key)
utils/json.lua        JSON encode/decode pure Lua (cjson kalau ada)
managers/monitor.lua  loop monitor + runSequentialLaunch (urutan launch, tunggu heartbeat),
                      antrian rejoin (Monitor.requestRejoin / data/rejoin_request.txt dari menu),
                      syncMenuSettings: setting webhook/remote dari Menu 9 dipakai tanpa restart
managers/recovery.lua launchAndJoin (force-stop -> window layout -> deep link), reopenNoLogin
managers/status.lua   klasifikasi status + dashboard
managers/heartbeat.lua install script ke Autoexecute, baca hb file (alive / isUp)
managers/webhook.lua  laporan Discord (POST ?wait=true lalu PATCH /messages/<id>)
managers/window_layout.lua grid floating window App Cloner
managers/auth.lua     cek login (cookie + verifikasi curl)
managers/delta_key.lua cek file "license" Delta (notif minta key)
managers/autoexecute.lua  folder Scripts (scriptSave/Remove/Read, scriptsDir) + Autoexecute
                      (autoAdd = copy dari Scripts, autoRemove). Menu 6 = core/autoexecute_cli.lua
managers/apk.lua      am/pm/pidof/RSS/hasWindow
scripts/rejoin_heartbeat.lua  script Luau di dalam game (Delta autoexecute)
install.sh            installer 8 langkah (aman diulang, skip apt kalau paket lengkap)
update.sh             git fetch + reset (config & log dipertahankan) + migrasi data/.migrated-*
termux-boot.sh        engine pas boot (log ke data/boot.log, restart maks 5x)
device_setup.sh       animasi, dev options, izin background, smallest width (SMALLEST_WIDTH)
tools/update_log.lua  update log -> Discord components (2 kotak); template + update_logs/
.github/workflows/update-log.yml  kirim otomatis log baru / version naik (secret UPDATE_LOG_WEBHOOK)
config/config.lua     config user (dipertahanin pas update); template.lua = default + dok key
data/                 rejoin.log, boot.log, monitor.pid, webhook_msg.txt, delta_license_path.txt
```

Key config penting: `launchJoinTimeout` (240), `launchSettleDelay` (20),
`launchEmptyDelay` (5), `launchWaitTimeout` (60), `minRss`, `freezeTimeout`,
`relaunchNoLogin`, `noLoginCooldown`, `windowLayout{enabled,columns,gap,overlap}`,
`heartbeat{enabled,saver{...}}`, `webhook{url,interval,screenshot,events,hideNames,deviceName}`,
`deltaLicensePath`, `useRoot`, `appAutoExecutePath`, `presets{A={name,link}}`,
`defaultPreset`, `scriptsPath`, `remote{url,secret,interval}`, `instances{...,preset}`.

## 4. Aturan teknis wajib (masing-masing dari bug nyata)

- **`Shell.exec`** (`utils/shell.lua`) ngebungkus perintah jadi `su -c` + timeout +
  `</dev/null`. Perintah majemuk (`if`, `&&`, `;`, `$( )`) **wajib** dibungkus
  `sh -c '...'`. Kalau ga, error syntax.
- **su ga boleh nyentuh tty.** Selalu kasih stdin `/dev/null`. Magisk su bikin terminal
  masuk mode raw, terus Ctrl+C mati. Monitor manggil `stty isig` tiap siklus.
- **Cek login**: query sqlite ke WebView Cookies DB. File `.bak-*` sama `-journal`
  diabaikan. Hasilnya diverifikasi ke `users.roblox.com/v1/users/authenticated`
  pake curl (401 = logout, cache 600 detik). Token ga boleh masuk log.
- **Clone belum login ga pernah di-force-stop.** Force-stop clone kosong bikin clone
  lain ikut FC. Logout akun (`CookieInjector.logout`) cuma force-stop kalau cookie-nya
  masih ada, lalu kasih tau engine lewat `data/auth_forget.txt` (`Auth.forget`).
- **Window App Cloner**: `/data/data/<pkg>/shared_prefs/<pkg>_preferences.xml`, key
  `app_cloner_current_window_{left,top,right,bottom}`. Ditulis **pas clone mati**,
  pake `cat >` biar inode-nya tetep. File `.bak` juga ikut diurus. Kalau file belum
  ada, dibikin dengan owner, mode, dan SELinux context yang sama kayak folder app.
- **Heartbeat** baru ditulis setelah karakter spawn dan antrian aset kosong 5 detik.
  Kalau cuma `game.Loaded`, itu kecepetan. Kalau heartbeat ga muncul sampai
  `launchJoinTimeout`, sisa Launch All pake `launchSettleDelay`.
- **Webhook**: curl jalan sebagai user Termux, **bukan su**. URL webhook ga boleh
  di-log atau di-commit. ID pesan disimpen di `data/webhook_msg.txt`. ID-nya diambil
  dari key `"id"` tingkat atas JSON (urutan key Discord ga tetap). CPU butuh 2 sampel.
  Notif terpisah **cuma** buat "Delta minta key" (permintaan user).
- **Config user ga boleh ditimpa** pas update. Default baru buat device lama dipasang
  lewat migrasi `update.sh` (`data/.migrated-<nama>`), dan cuma jalan sekali.
- **Smallest width tetap 600dp.** 900dp udah dicoba dan user ga suka (kekecilan).
- Termux:Boot harus dibuka sekali (`stopped=false`). Installer ngecek ini sendiri.
- Satu engine aja yang boleh jalan (`data/monitor.pid`).
- **Link game** selalu lewat `InstanceManager.gameLink(inst)` (preset dulu, lalu
  `privateServer`). Jangan baca `privateServer` langsung buat join.
- **Remote/bot**: setting yang boleh diubah bot cuma yang ada di `SCHEMA`
  (`managers/remote.lua`). Nambah setting baru = tambah ke SCHEMA + DEFAULTS + tabel §6
  di PRD. `remote.url/secret` sengaja ga bisa diubah dari bot. Secret ga boleh ke log.
- Rejoin karena ganti preset / perintah bot selalu lewat antrian monitor (berurutan),
  jangan launch langsung.
- **Script**: isi script cuma boleh ditulis ke folder **Scripts**. Autoexecute cuma
  diisi lewat copy dari Scripts (`autoAdd`), jangan ada jalur nulis langsung ke
  Autoexecute. `rejoin_heartbeat.lua` milik rejoin, ga boleh dihapus/ditimpa dari menu
  atau bot. Folder Delta dipake bareng semua clone 1 device (per device, bukan per clone).

## 5. Cara tes (di sandbox ga ada device)

- `luac -p <file.lua>` dan `sh -n <file.sh>`.
- Harness Lua: stub modul pake `package.preload[...]`, stub `su` / `curl` / `dpkg` /
  `git` di `PATH`, dan HOME palsu di folder scratch.
- **Jangan klaim udah dites di device.** Bilang dites pake simulasi, terus kasih user
  perintah buat ngecek di device (biasanya `grep ... ~/rejoin/data/rejoin.log`).
- Tes yang nyentuh `data/rejoin.log` atau `config/config.lua`: balikin pake
  `git checkout` sebelum commit.

## 6. Gaya

- Komentar kode: **Inggris**, ikutin gaya file sekitarnya. Teks menu dan pesan ke user:
  **Indonesia**.
- Tiap fitur: update `README.md`, `setup.md`, dan `docs/changelog.md` (entri baru di
  atas, bagian "Unreleased").
- Commit message: Inggris, singkat, jelasin kenapa.

## 7. Preferensi user

- Balas pake **bahasa Indonesia santai** ("bre", "gue/lu").
- Kalau user **cuma nanya**, **jawab dulu**, jangan langsung bikin fitur.
- Jangan numpuk semua setting di Settings 13. Fitur besar dapet menu sendiri, dan
  itemnya bisa diedit satu-satu, langsung kesimpen.
- **Bypass key system Delta (auto get key lewat situs bypass) ditolak.** Yang boleh:
  notif kalau key ilang, sama masukin key yang user dapet sendiri.
- Kirim ke Discord (webhook) dari sandbox kemungkinan diblokir network policy. Kasih
  perintah buat dijalanin user dari Termux.
