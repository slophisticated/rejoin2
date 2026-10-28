# Changelog

## Unreleased / Bug fixes

- **Layar login tidak dilewati karena proses stub**: dua cek tanpa jendela/overlay
  mengantrekan pembukaan tanpa force-stop. Slot layar login menunggu jendela muncul
  lalu `launchEmptyDelay`; bila gagal muncul, ditahan dengan kontrol Menu 14.
  Header Window dumpsys dipakai; referensi focus lama bukan bukti jendela ada.
  Tes parser overlay/activity dan layar login hilang ditambah.

- **Tutup jalur launch di luar slot**: reopen clone tanpa akun sekarang mengantre
  dengan jeda `launchEmptyDelay`, tidak membuka beberapa layar login langsung dari
  loop monitor. Proses hidup tanpa jendela dibiarkan (ikon floating bukan bukti FC).
  Proses mati tidak sehat walaupun heartbeat terakhir masih segar. Autojoin cold
  tetap memerlukan restart target login; dampak App Cloner ke clone lain masih perlu
  diuji di device, tidak dijamin oleh perubahan antrean ini.

- **Percobaan satu slot loading** (`trial/single-loading-slot`): FC dengan login
  valid dicoba ulang maksimal dua kali dengan jeda 10 detik, tanpa membuka target
  lain. Permintaan rejoin bot untuk target aktif menggantikan percobaan lama dengan
  link terbaru; target batch berikutnya tidak diantrekan dobel. Timeout tetap menahan
  slot. Cek logout ketat tidak memakai cache lokal jika pembacaan terbaru gagal;
  cancel saat jeda logout tidak hilang. Tes simulasi retry, penggantian target,
  pembatasan antrean dan cancel ditambah. Main tidak berubah.

- **Logout saat menunggu heartbeat tidak menahan clone lain**: login dicek ulang
  tiap 30 detik, atau lebih cepat setelah proses mati dua kali berturut-turut.
  Jika terkonfirmasi belum login, lanjut setelah `launchEmptyDelay` tanpa force-stop.
  FC dengan akun masih login, hasil tidak pasti, dan cek gagal tetap menahan antrean.
  Tes simulasi mencakup logout saat loading dan pemeriksaan setelah FC.

- **Antrean heartbeat ketat**: Launch All/rejoin/recovery tidak lanjut karena RSS,
  timeout, username dobel, atau dua heartbeat gagal. Timeout menahan antrean dengan
  diagnosis key/executor/kick/proses mati; heartbeat baru melanjutkan otomatis.
  Menu **14** (sesi Termux kedua) untuk lewati satu target atau batalkan sisa antrean.
  Mode heartbeat mati tetap memakai jeda lama; nilai timeout 0 tidak mematikan gate.
- **Login/inject tidak restart dobel**: target yang antre/loading dilindungi dari
  recovery RSS; freeze/kick/recovery masuk antrean yang sama. Inject bot hanya target,
  inject Menu 7 mengantrekan target untuk Menu 1 (ditolak jika monitor lain aktif).
  Clone yang sudah mati tidak di-force-stop lagi sebelum cold autojoin. Heartbeat
  state selain `ingame` tidak diterima sebagai bukti siap. Tes simulasi antrean ditambah.

- **Webhook cuma satu pesan**: notif terpisah "🔑 Delta minta key" dihapus. Status key sekarang jadi baris `🔑 Delta minta key` di pesan status yang di-edit tiap 5 menit. Setting-nya ikut dihapus: Menu `9` → `4`, bot `/webhook options notif_key`, `webhook.events` (nomor menu lain tetep sama). Perlu deploy ulang bot.

- **Fix auto-rejoin abis kick masih join link game buat akun yang udah logout**: cek login seger (Roblox ditanya ulang, bukan cache 10 menit) sekarang juga dipake di recovery abis kick/disconnect (`checkAndRecover`), restart pas freeze (`relaunch`), dan keputusan monitor sebelum recovery. Sebelumnya cuma Launch All / rejoin dari antrean yang ngecek seger, jadi akun yang ke-logout terus ke-kick dalam 10 menit masih dimasukin ke game dan nyangkut loading. Clone tanpa akun tetep dibuka ke layar login kayak biasa.

- **Disconnect ga lolos lagi** (heartbeat v3): script heartbeat sekarang juga ngecek **sambungan ke server** (ClientReplicator di NetworkClient ilang = koneksi putus) dan ngecek ulang pesan error **tiap nulis heartbeat**, bukan cuma ngandelin event. Waktu nunggu UI popup error dipanjangin dari 30 detik ke 10 menit (di device lambat UI-nya telat muncul, jadi kick ga pernah ketangkep). Script baru kepasang sendiri pas monitor mulai, dan kepake pas clone masuk game berikutnya.
- **Clone belum login ga nyepam log lagi**: monitor ga ngecek kesehatan clone yang statusnya belum login (RAM kecil di layar login itu wajar). Cuma dibuka lagi pelan kalau ketutup. Sebelumnya muncul `instance not healthy` tiap siklus.
- **Report: warning yang sama digabung** jadi 1 baris + jumlah (`(x38)`) + jam terakhir, biar error beneran ga ketutup.

- **Logout beneran tuntas**: Menu `7` → `4`, `/clone logout`, dan alarm logout sekarang **matiin session di server Roblox** dulu (`auth.roblox.com/v2/logout` pake cookie clone itu, sama kayak tombol Log Out di app), baru hapus cookie lokal. Token (termasuk yang ada di backup `.bak-`) langsung ga berlaku, jadi verifikasi login rejoin langsung bilang logout. Token cuma lewat file header sementara (0600), ga pernah di command line atau log. Kalau Roblox ga ngerespon, cookie lokal tetep dihapus dan pesannya bilang session server belum dimatiin.
- **Bot: `/report`**: report error device (sama kayak Menu `4`) dikirim ke Discord sebagai file `.txt` (`device:all` = 1 file per device), rahasia disensor. Report sekarang juga punya bagian **login + heartbeat tiap clone** (state, umur, sesi ini atau lama, alasan kick), buat ngelacak disconnect yang ga ke-rejoin.

- **Fix clone yang udah logout tetep dibuka ke link game** (stuck loading): Launch All / rejoin dari antrean manggil `launchAndJoin` buat semua clone, dan status login baru dicek *setelah* clone di-force-stop terus dibuka pake link game. Sekarang `launchAndJoin` ngecek login duluan, dan cek-nya **seger** (cache dilewatin, Roblox ditanya ulang kecuali <20 detik lalu / cookie baru di-inject). Jadi akun yang baru di-logout semenit lalu juga ketauan. Belum login: kalau kebuka dibiarin di layar login, kalau ketutup dibuka pelan tanpa link, **ga pernah di-force-stop**.

- **Launch All ga lagi "kebuka semua barengan"**:
  - **Satu engine aja**: Menu `1`/`5` pas engine boot masih jalan sekarang nawarin "stop engine itu terus lanjut di sini?" (SIGTERM, jadi ga di-restart). Sebelumnya langsung keluar. `termux-boot.sh` juga ga nyalain/restart engine kalau udah ada engine lain di `data/monitor.pid`. Sebelumnya engine boot yang mati bukan secara normal (mis. `kill -9`) idup lagi 30 detik kemudian dan ikut Launch All bareng engine menu.
  - **Heartbeat kecepetan ga dianggep**: heartbeat "in game" yang muncul < 10 detik abis clone dibuka (ga mungkin secepet itu join) ditunggu lagi, bukan langsung lanjut ke clone berikutnya.
  - **Username dobel**: kalau 2 clone kebaca username yang sama, heartbeat-nya ga dipake (saling kebaca). Clone itu pake jeda `launchSettleDelay`, plus ada warning di log.
  - **Log jelas per clone**: `Monitor: #2 Clone2 beres dalam 47s (masuk game (heartbeat))`. Alasannya bisa belum login / launch gagal (+ kenapa, mis. force-stop gagal) / timeout / kick. Jadi kalau masih kebuka barengan, Menu `4` langsung nunjukin sebabnya.
- **Rejoin nunggu clone lain kelar loading**: rejoin dari bot/menu (ganti preset, `/restart`, input key, dll) ditahan selama masih ada clone yang lagi join (udah login, jalan, belum ada heartbeat). Maksimal `launchJoinTimeout`, abis itu tetep jalan. Rejoin-nya sendiri tetep satu-satu kayak Launch All.

- **Report error 1 tempat + auto copy**: Main Menu `4` → `1` (atau Enter) / `lua main.lua --report` (jalan juga kalau root lagi rusak). Isinya info device (versi rejoin, Android, engine jalan?, executor, bot/webhook diset?, RAM, storage, clone) + error/warning dan aktivitas terakhir dari `rejoin.log`, `boot.log` (termasuk auto-update), `crash.log`, `launch.log`. Rahasia disensor (URL webhook, secret bot, HWID, cookie Roblox, Bearer). Disimpen ke `data/report.txt` + `/sdcard/Download/rejoin-report.txt`, terus di-copy ke clipboard (Termux:API, fallback OSC 52). **Crash Lua sekarang kecatet**: `run.sh` sama boot jalanin `main.lua` lewat `utils/crash_guard.lua`, traceback-nya masuk `data/crash.log`.

- **Fix daftar di bot telat keupdate** (mis. `/script add` sukses tapi `/script list` masih "Kosong"): snapshot dikirim device *sebelum* command dijalanin, jadi perubahan baru keliatan di sync berikutnya. Sekarang ACK tiap command bawa snapshot terbaru, jadi `/script list`, `/clone list`, `/preset list`, `/overview` langsung berubah. Perlu update engine + deploy ulang bot.

- **Device senyap + setting ga penting dimatiin** (`device_setup.sh`): semua volume (media/game, dering, notif, sistem, alarm) 0; suara sentuh, getar, suara kunci layar, nada dial, suara charging mati; notif pop-up (heads-up) mati biar ga nutupin jendela clone; auto-rotate, lokasi, scan Wi-Fi/Bluetooth di background mati. Tiap item dicek ulang abis di-set. Device lama dapet sekali lewat migrasi `update.sh` (`data/.migrated-quiet-device`) pas reboot. `--undo` ngebalikin volume ke setengah dan setting ke bawaan Android. App bawaan / batas proses / verifikasi APK sengaja ga disentuh.

- **Bot: `/overview`**: satu tampilan buat semua device di akun (atau satu device): versi rejoin tiap device (⚠️ kalau beda-beda, tandanya ada device yang ketinggalan update), tiap clone (status, posisi, username ikut setting sembunyikan nama, preset + sumbernya), daftar preset (⭐ default), Scripts (⚡ = ikut Autoexecute), dan Autoexecute. Dibaca dari snapshot, jadi langsung muncul tanpa nunggu device. Perlu deploy ulang bot.

- **Port dari versi publish (Apeng: "fix: path key", "bulk set alarm+install app")**:
  - **Fix deteksi license Delta**: `<Delta>/Internals/Cache/license` dicek duluan (juga `internal/cache`), dan file `.license` buatan Delta **ga pernah** dianggep license. Sebelumnya `ls -a` bisa nampilin `.license` duluan, jadi input key bisa nulis ke file yang salah. Path `.license` yang kadung kesimpen diabaikan. Default input key jadi `<Delta>/Internals/Cache/license`.
  - **Rejoin abis input key**: Menu `12` dan `/delta input-key` masukin semua clone ke antrean rejoin (satu per satu) biar Delta baca key baru.
  - **`/alarm import`** (bot): banyak alarm logout dari CSV (`DEVICE, USN, TANGGAL, JAM`, opsional `DAILY/NOTES/ORDER ID/Delete`), preview + CSV hasil cek, diterapin setelah tombol. Beda dari versi publish: jalan juga kalau akun punya banyak device (di sana kena "isi opsi device dulu").
  - **Menu `13` Install APK dari GoFile**: link GoFile → pilih APK → download + `pm install` (root). Temp file pakai `$TMPDIR` Termux (bukan `os.tmpname`), nomor progres dibetulin.

- **Executor selain Delta, otomatis tanpa buka Termux**: rejoin nyari semua folder autoexec executor di `/sdcard` (`Autoexecute`, `autoexec`, `auto-exec`, …) dan masang script heartbeat ke semuanya. Executor yang dipake (`appAutoExecutePath`) = yang heartbeat-nya masih seger. Pindah otomatis kalau executor sekarang udah basi 5 menit, dicek monitor tiap 5 menit. Sisa heartbeat lama ga bisa ngebalikin pilihan. Heartbeat dibaca dari Workspace semua executor (yang terbaru menang), jadi Launch All ga nyangkut pas baru ganti executor. Belum ada heartbeat: folder yang ada di config dipake, kalau ga ada ya Workspace yang paling baru dipake. Menu `10` → `10` buat maksa pilih / ketik path. Heartbeat (Workspace), Scripts, dan Autoexecute ikut executor itu (`managers/executor.lua`).

- **Bot: `/device remove`**: device yang udah ga dipake (mis. abis replace cloud phone) bisa dihapus dari `/devices` pakai konfirmasi. Cuma device **offline** milik akun sendiri; command yang masih nyangkut ikut dibatalkan. Device yang sync lagi muncul lagi otomatis. Perlu deploy ulang bot.

- **Port dari versi publish (Apeng, commit "Write Delta Key")**:
  - **Input Key Delta**: Main Menu `12` + bot `/delta input-key` (popup privat). Key yang didapat user sendiri ditulis ke file license Delta yang terdeteksi, atau `<Delta>/internal/cache/license` kalau belum ada. Bedanya dari versi publish: path license yang udah kedeteksi dipake duluan. Key ga masuk config, log, atau command shell; command bot transient kayak cookie. Deteksi key sekarang juga ngecek `<Delta>/internal/cache`.
  - **Force-stop lebih aman**: nama package divalidasi + di-quote; kalau satu package dipake lebih dari satu clone, force-stop dibatalkan (biar clone lain ga ikut ketutup). Logout / inject cookie ga ngubah cookie kalau clone gagal ditutup. Semua jalur force-stop lewat `APKManager.forceStop`.
  - **Auto masuk game abis login manual**: clone yang tadinya belum login, begitu kedeteksi udah login, dimasukin ke antrean rejoin monitor dan dibuka ke link game/preset-nya (dilewati kalau heartbeat bilang udah di game).

- **Command bot jalan instan (long poll)**: jeda antar siklus monitor (dan jeda saat Launch All) sekarang dipake device buat nunggu di `POST /api/poll`. Bot langsung jawab begitu ada command, device langsung sync, jadi command jalan ±1–2 detik setelah dikirim, ga nunggu `remote.interval` (30 dtk) lagi. Poll ga bawa snapshot dan ga pake root, jadi bebannya kecil; snapshot lengkap tetap tiap `remote.interval`. Bot lama (tanpa `/api/poll`) = otomatis balik ke sleep biasa. **Bot di Railway perlu di-deploy ulang** biar fitur ini aktif.

- **Inject cookie lewat bot langsung kepake**: abis `/cookie inject` sukses, engine langsung nganggep clone itu login (`Auth.markLoggedIn`) dan buka ulang clone-nya ke game lewat antrean rejoin (kayak Menu 7), tanpa lewat jalur "belum login". Cek token ke Roblox ditahan sampai `loginVerifyInterval` (600 dtk) biar app yang baru login ga "dibalap" client kedua (bisa bikin sesi di-revoke).

- **Petunjuk clone di bot saat grid jendela mati**: kalau auto-atur jendela (Menu 10) mati, pilihan clone nampilin nomor urut Menu 2 (`#2`) sebagai pengganti posisi jendela.

- **Port dari versi publish (Apeng): logout terjadwal + inject cookie lewat bot.** `/alarm set|remove|list`: logout akun clone di tanggal + jam WIB (sekali / tiap hari), dijalankan monitor (`managers/logout_alarm.lua`, alarm disimpan di instance `logoutAlarm`). `/cookie inject`: cookie diisi di modal Discord privat, dikirim sebagai command transient (ga dipersist, ga diretry, ga di-log, dihapus setelah ACK / 90 dtk), ditolak selama Launch All. Ditambah tes regresi alarm + tes bot.

- **Bot: petunjuk clone**: pilihan clone (autocomplete), `/clone list`, dan `/status` nampilin posisi jendela clone di layar (`kiri atas`, `kanan bawah`, atau `baris 2 kolom 3`, sesuai grid) + `belum login` buat clone tanpa akun, jadi gampang milih clone yang belum login tanpa hafal urutan. Bisa juga ngetik posisinya (mis. `kanan`) buat nyaring pilihan. Device kirim `slot` per clone di snapshot (`WindowLayout.positionLabel`).

- **Fix pencabutan HWID setelah restart bot**: registry melengkapi ID pesan channel
  untuk HWID yang dimuat dari `DATA_DIR`, supaya `/hwid remove` menghapus salinan
  channel juga. Perubahan menunggu channel siap; gagal hapus pesan dilaporkan dan
  bisa dicoba ulang, bukan dinyatakan sukses lalu HWID muncul lagi setelah restart.
- **Fix recovery ulang saat clone masih loading**: monitor memakai waktu launch dari
  heartbeat, melindungi proses hidup tanpa heartbeat minimal 60 detik (atau
  `gracePeriod` yang lebih besar). Kick, heartbeat berhenti, dan proses mati tidak
  disembunyikan oleh masa loading; setelahnya RSS rendah tetap memicu recovery.
- **Fix Tes koneksi bot menghabiskan antrean command**: Menu 9 → 11 memakai endpoint
  autentikasi baru `POST /api/ping`, tanpa sync/ACK atau mengubah waktu sync. Bot lama
  (404) diminta update; tidak ada fallback yang mengambil command. Deploy bot bersama
  engine untuk memakai tes ini.
- **Fix preset ikut default tidak tersimpan**: edit clone ke `d` di Menu 2 tetap
  menyimpan perubahan meskipun nama/package tidak diubah. Ditambah tes regresi Lua
  (`lua tests/regressions.lua`) serta tes HTTP dan persistence HWID.

- **Daftar HWID, tanpa key/secret di device**: device punya HWID (acak, `data/device_id.txt`; tampil di akhir installer, Menu 9, `lua main.lua --hwid`). `/hwid redeem hwid:...` di Discord nyatet HWID itu ke akun yang ngetik (`/hwid remove` nyabut) — user ga perlu input apa-apa di Termux. Device kirim HWID di header `X-Rejoin-Hwid`; bot cuma nyimpen hash-nya di `DATA_DIR/hwid.json` (volume) dan/atau channel privat (`HWID_CHANNEL_ID`). Bot sync otomatis begitu URL ada (secret opsional); device yang belum terdaftar dapet 401 + backoff dan pesan jelas di log / tes koneksi. Env baru `HWID_USERS`, `HWID_CHANNEL_ID`; `DEVICE_SECRET` jadi opsional, secret lama tetap jalan.

- **Lisensi GPL-3.0-or-later** (`LICENSE`) + `CONTRIBUTING.md` (cara tes, gaya, aturan penting) biar orang bisa kontribusi.

- **Monitor ga rejoin cuma gara-gara RAM turun sekali**: clone tanpa heartbeat yang RSS-nya sekali di bawah `minRss` dicek lagi siklus berikutnya dulu; app yang beneran ketutup atau heartbeat "kicked" tetap langsung ditangani.
- **Launch All: 1 clone tanpa heartbeat ga bikin sisa clone ga ditunggu**: clone berikutnya tetap ditunggu heartbeat-nya; baru setelah 2 clone berturut-turut ga ada heartbeat, sisa clone pakai jeda `launchSettleDelay`.

- **Fix Launch All ga nunggu clone berikutnya**: RAM (RSS) Roblox sempet turun di bawah `minRss` pas loading game, dan sekali turun langsung dianggap "dropped while loading" → clone berikutnya langsung dibuka. Sekarang clone baru dianggap mati kalau prosesnya beneran ga ada 2x cek berturut-turut.

- **Main Menu: `1` = Start Monitor, `5` = Launch All + Monitor** (ditukar). Yang paling sering dipake (nyalain monitor + bot lagi tanpa launch ulang clone) jadi nomor 1; menu lain tetap. Engine boot ga berubah (`--auto-launch`).

- **Fix device keliatan offline di bot selama Launch All / rejoin berurutan**: engine sekarang tetep sync ke bot (`Remote.tick`) waktu nunggu clone kebuka / masuk game, jadi device ga dianggap offline dan command bot tetep diterima.

- **Logout akun clone** (Menu 7 → 4, bot `/clone logout clones:...` dengan konfirmasi): `CookieInjector.logout` force-stop clone (cuma kalau masih login), backup tiap Cookies DB lalu hapus baris `.ROBLOSECURITY` (cookie lain tetap). Engine dikasih tau lewat `data/auth_forget.txt` / `Auth.forget` biar langsung nganggep clone itu belum login dan ga nge-rejoin. Session ga di-revoke di Roblox, jadi cookie-nya bisa di-inject lagi. Menu 7 sekarang `0) Kembali`.

- **Bot: pilih device dulu**: command yang opsinya diisi dari data device (preset, clone, clones, script, key setting) sekarang wajib `device` dan `device` jadi opsi pertama, biar autocomplete clone/preset langsung keluar sesuai device yang dipilih.

- **Fix nama device di bot ga ikut ganti**: engine yang lagi jalan sekarang ngecek `config/config.lua` tiap siklus dan langsung pakai setting webhook/bot dari Menu 9 (nama device, URL, secret) tanpa restart. Device ngirim `deviceId` (acak, `data/device_id.txt`); bot gabungin entri nama lama ke nama baru (antrian ikut) setelah nama lama diam ±1 menit, dan nandain ⚠️ di `/devices` kalau 2 device online pakai nama sama (mis. nama kosong = model HP).

- **Bot: device terpisah per owner** (`OWNERS=idDiscord:secret,...`): secret yang dipakai device menentukan akunnya; `/devices`, `/status`, autocomplete, `device:all` dan semua command cuma menyentuh device milik pemanggil, nama device boleh sama antar akun, ACK/upload dari akun lain ditolak. `OWNER_IDS` + `DEVICE_SECRET` tetap jalan. State persist versi 2 (versi 1 tetap kebaca).
- **URL bot manual tidak ketimpa `remote_url.txt`**: URL yang diketik di Menu 9 → 9 ditandai `remote.urlManual`, fallback 5x gagal ga ganti URL itu (biar device yang pakai bot sendiri ga nyasar ke bot repo). Isi `-` untuk kembali ikut repo.

- **Panduan deploy bot di Railway** (`bot/README.md`): root `bot`, healthcheck `/health`, watch path `bot/**`, generate domain → `remote_url.txt`, pindah akun dengan `DEVICE_SECRET` yang sama. Kode bot tidak berubah.

- **Rejoin Control Bot siap deploy**: implementasi Node.js 24 + discord.js v14 di
  `bot/`, blueprint Render Free di root, registrasi slash command guild otomatis,
  seluruh command PRD dengan balasan ephemeral owner-only, screenshot dan attachment
  script, config dari schema device, antrean FIFO/resend/timeout, serta persistence
  opsional. Rename memindahkan snapshot/antrean dan menerima ACK batch lama.
  Limit IP hanya menghitung auth gagal (60/menit); secret valid dibatasi satu sync
  per empat detik per device sehingga shared IP Redfinger tetap jalan. Disertai
  tes HTTP localhost + mock Discord dan panduan deploy. Tidak mengubah engine Lua,
  installer, updater, atau boot device.

- **Inject Cookie: kemungkinan penyebab kalau tetep logout**: abis `[VERDICT]`, menu nampilin penjelasan dari hasil probe (`CookieInjector.hints`): app ga buka cookie store WebView (versi Roblox beda → bandingin `versionName`), cookie dihapus app (Roblox nolak sesi / proteksi lokasi → cek 7 > 3, 401 = revoke), atau cookie dibaca tapi tetep logout (proteksi lokasi). Ditambah negara IP device (`ipinfo.io/country`, curl tanpa su & tanpa token) + tips ambil cookie dari negara/jaringan yang sama. `probeToken` balikin `info` sebagai nilai ke-3.

- **URL bot otomatis dari `remote_url.txt`**: device yang secret bot-nya diisi tapi URL bot kosong ngambil URL dari `remote_url.txt` di repo (maks sekali per 10 menit, `Remote.tick`; `Tes koneksi bot` langsung ngecek). Tiap device cukup diisi secret (Menu 9 → 10). URL yang diisi manual tetap dipakai; fallback 5x gagal tetap jalan. Menu 9 nampilin `kosong = ambil dari remote_url.txt`.

- **Bot: screenshot + pilih banyak clone + sync cepat**: command `screenshot` (device `screencap` → `POST /api/upload/<id>` PNG mentah → ack `data.uploaded`; bot menaruh gambar di balasan ephemeral). `clones` boleh teks dipisah koma (`"Clone1,Clone3"`) di `restart` / `game`. Setelah menerima command, device sync tiap 5 dtk selama 2 menit (mode cepat). `Webhook.captureScreen()` dipakai bersama. PRD: §4.2b upload, `/screenshot`, opsi `clones` multi-pilih.

- **Script Manager (Scripts + Autoexecute)**: script disimpan di folder **Scripts** Delta (`scriptsPath`, "" = `Scripts`/`scripts` di sebelah Autoexecute). Autoexecute cuma diisi lewat **copy dari Scripts** (`AutoExecute.autoAdd`) dan dikosongkan dengan `autoRemove`; ganti isi script di Scripts ikut memperbarui copy di Autoexecute. Nama divalidasi (`[A-Za-z0-9_.-]`, maks 64), isi maks 200 KB, `rejoin_heartbeat.lua` dilindungi. Menu 6 jadi "Script Manager" (tambah/ganti, dari loadstring URL, hapus, masukkan/keluarkan Autoexecute, edit, tawaran rejoin). Bot: command `script_add` (content / url), `script_remove`, `script_get`, `auto_add`, `auto_remove`; snapshot kirim `scripts` + `autoexecute`; PRD: `/script` + `/autoexec`.
- **Fix PRD bot sempat kosong** di commit sebelumnya (file terpotong waktu revisi Render); isi dipulihkan + revisi Render dipasang ulang.

- **PRD bot untuk Render**: deploy Render free (Root Directory `bot`, health check `/health`, build filter `bot/**`, `render.yaml`), state cuma di memori, slash command didaftarkan otomatis, catatan service tidur + saran ping uptime. Device: timeout sync 20 dtk dan **backoff** (interval x2…x10) kalau bot ga bisa dihubungi, biar monitor ga nunggu timeout tiap siklus.

- **Preset default**: `defaultPreset` di config. Clone tanpa preset sendiri ikut default; `preset = "B"` = khusus; `preset = "-"` = link sendiri (`InstanceManager.presetOf` → key, sumber, link). Menu 11: set default (clone yang ikut default di-rejoin), atur clone (khusus / ikut default / link sendiri), semua clone ikut default; preset pertama otomatis jadi default; preset default tidak bisa dihapus. Menu 2 (tambah/edit clone) nanya preset, bukan link. Migrasi sekali (`--migrate-presets`, update.sh + installer): link tiap clone jadi preset (satu per link, nama dari URL game), yang paling banyak dipakai jadi default. Bot: command `default_set`; `game` tanpa clone = jadikan default + semua ikut; snapshot kirim `defaultPreset`, `presetSource`, `game`, `link` per clone (PRD: `/default`, `/status` per clone + link).
- **Fix urutan clone berubah setelah config disimpan**: `InstanceManager.load` sekarang urut sesuai key (dulu `pairs()` pada key eksplisit `[1] = ...` bisa mengacak urutan launch & slot jendela).

- **Preset game + kontrol dari bot Discord**:
  - `presets = { A = { name, link } }` + `preset` per clone; link efektif lewat `InstanceManager.gameLink` (fallback `privateServer`), dipakai recovery. Main Menu `11) Preset Game` (tambah/ubah/hapus preset, preset per clone, ganti semua clone sekaligus). Rejoin hasil ganti preset lewat antrian monitor (berurutan, aturan Launch All); dari menu saat engine boot jalan lewat `data/rejoin_request.txt`.
  - `managers/remote.lua`: device POST `/api/sync` tiap `remote.interval` (30 dtk) ke bot, jalankan command (`game`, `restart`, `launch_all`, `preset_set/remove`, `instance_add/edit/remove`, `config_set` hanya untuk key di SCHEMA, `device_rename`, `webhook_use_message`, `webhook_test`, `status`), lalu POST `/api/ack`. curl sebagai user Termux, secret lewat header file 0600, tidak pernah di-log. 5x gagal → baca `remote_url.txt` di repo untuk URL bot baru.
  - Menu 9 jadi "Discord (Webhook & Bot)": `9)` URL bot, `10)` secret, `11)` tes koneksi.
  - `utils/json.lua` sekarang punya encoder/decoder pure Lua (dulu error tanpa cjson).
  - Spesifikasi bot untuk dibangun terpisah: `docs/discord_bot_prd.md`.

- **Fix runtime clone di webhook selalu `0m`**: Redfinger menjalankan Android di container, jadi `/proc/uptime` (sejak cloud phone boot) dan `starttime` proses (sejak host boot) tidak sejalan; hasilnya negatif lalu jadi 0. Sekarang nilai `/proc` hanya dipakai kalau masuk akal; kalau tidak, runtime dihitung sejak pid clone pertama kali terlihat (atau sejak engine me-launch clone itu), disimpan di `data/clone_pids.txt` supaya tidak reset saat engine restart.

- **Root handler**: `core/root_check.lua` mengecek `su -c id` (timeout 15 dtk, stdin /dev/null) di awal `main.lua`, sebelum setup wizard. Tanpa root → pesan petunjuk + exit 3 (menu tidak dibuka; saat boot, `termux-boot.sh` mencoba lagi tiap 30 dtk maks 5x). Dilewati untuk `--dry-run`, flag one-shot installer, dan `useRoot = false`.

- **Installer membereskan upgrade paket yang terputus**: kalau `dpkg --audit` menemukan paket setengah terpasang ("dpkg was interrupted"), langkah 1 menjalankan `dpkg --configure -a` + `apt-get --fix-broken install` sebelum `apt-get update`, dan jalur cepat (skip upgrade) tidak dipakai.

- **Update log: 2 kotak + kirim otomatis saat push**: pesan dibagi jadi 2 container (judul/version/notes, lalu isi section). Workflow `.github/workflows/update-log.yml` jalan saat push ke `main` yang menyentuh `tools/update_logs/**`; `tools/send_new_update_logs.sh` mengirim file log yang baru atau yang `version`-nya berubah (edit tanpa ganti version tidak dikirim ulang). URL dari secret repo `UPDATE_LOG_WEBHOOK`; tanpa secret workflow tetap sukses tanpa mengirim.

- **Update log jadi pesan components**: `tools/update_log.lua --send` sekarang mengirim lewat webhook sebagai pesan Components V2 (`?with_components=true`, flag 32768): satu container dengan garis warna (`color`), judul `# Rejoin Update Logs`, mention, Version + Developer Notes, lalu tiap bagian (`### Added` dst.) dipisah separator. Field `place` dihapus dari template. Kalau Discord menolak format components (HTTP 4xx), teks yang sama dikirim sebagai pesan biasa.

- **Generator update log**: `tools/update_log.lua <file>` membuat teks update log (judul, mention, Place, Version, Developer Notes, Added `[ + ]`, Improved `[ / ]`, Fixed `[ ! ]`, Deleted `[ - ]`; bagian kosong dilewati) dari file Lua seperti `tools/update_log_template.lua`. `--send <url>` (atau env `UPDATE_LOG_WEBHOOK`) langsung mengirim ke Discord webhook, dipecah per 2000 karakter; ping role lewat `mention = "<@&ROLE_ID>"`.

- **Webhook: lanjutkan pesan status lama**: Menu 9 → `8) Pakai pesan status lama` menerima link pesan Discord (`.../channels/<guild>/<channel>/<message>`) atau ID pesan, menyimpannya ke `data/webhook_msg.txt` dan langsung mengedit pesan itu. Berguna setelah replace device, supaya pesan device lama tidak nyangkut. Pesan yang sudah dihapus / dari webhook lain → otomatis pesan baru.

- **Launch All: clone yang sudah login duluan**: sebelum launch, status login tiap clone dibaca (`Auth.isLoggedIn`). Urutan baru: clone login (dan yang tidak diketahui) sesuai urutan Menu 2, lalu clone belum login di paling belakang. Urutan dicatat di log (`Monitor: urutan launch: ...`). Posisi jendela grid tetap per urutan Menu 2.

- **Install ulang jadi cepat**: `install.sh` melewati `apt update` + `full-upgrade` (beberapa menit) kalau `lua53 sqlite curl git` sudah terpasang (`dpkg -s`) dan benar-benar jalan (`curl/git/sqlite3 --version`, lua). Ada yang kurang/rusak → alur apt lama. Paksa: `FULL_UPGRADE=1`.

- **Main Menu dirapihin**: `0) Exit` sekarang di paling bawah; `9) Discord Webhook`, `10) Jendela & Mode Hemat` (dulu 10 dan 11). Di atas menu ada baris info: versi (commit), `install instan: ya/tidak` (script boot berisi penanda `Generated by rejoin install.sh`) dan `auto-start boot: ya/tidak`.

- **Webhook: notif kejadian diganti notif key + nama device**: notif ke-kick, recovery gagal dan clone belum login gagal dibuka dihapus (tetap di log). Notif baru **🔑 Delta minta key**: `managers/delta_key.lua` mencari entri bernama `license` di folder Delta (induk `appAutoExecutePath`; ditimpa lewat `deltaLicensePath`), path-nya diingat di `data/delta_license_path.txt`, dan monitor mengecek tiap ±60 dtk. Notif dikirim sekali tiap kali entri itu hilang/kosong (log `[KEY]`). Nama device baru di Menu 10 → `7)` (`webhook.deviceName`; nama Redfinger tidak terbaca dari dalam Android) tampil di judul status dan notif; kosong = model device.

- **Heartbeat baru muncul setelah game benar-benar selesai loading** (script v2): dulu heartbeat pertama ditulis begitu `game.Loaded`, padahal karakter belum spawn dan aset masih didownload, jadi Launch All membuka clone berikutnya saat clone sebelumnya masih loading. Sekarang script menunggu karakter (`HumanoidRootPart`) ada dan antrian aset `ContentProvider.RequestQueueSize` kosong 5 detik berturut-turut (masing-masing maks 90 dtk; ke-kick saat loading langsung dilaporkan). Default `launchJoinTimeout` naik ke 240 dtk. Script terpasang ulang otomatis saat monitor mulai.

- **Launch All benar-benar menunggu clone masuk game**: dulu clone berikutnya dibuka setelah jeda tetap `launchSettleDelay` (20 dtk) sejak proses jalan — di device lambat clone sebelumnya masih loading, jadi kelihatan dibuka barengan. Sekarang dengan heartbeat Delta, tiap clone ditunggu sampai heartbeat-nya muncul (in game) maks `launchJoinTimeout` (baru, default 120 dtk; Settings `13`). Lanjut lebih cepat kalau proses mati atau ke-kick. Kalau satu clone tidak pernah mengirim heartbeat (Delta belum key / script tidak jalan), sisa Launch All itu kembali ke jeda `launchSettleDelay`. Heartbeat dimatikan = perilaku lama.

- **Webhook: notif "Rejoin engine mulai" dihapus** (cuma spam tiap engine start/boot). Notif kick, recovery gagal dan clone belum login gagal dibuka tetap ada.

- **Grid: baris atas lebih tinggi (numpuk)**: `windowLayout.overlap` (default 80 px) memanjangkan jendela di semua baris kecuali baris terakhir, jadi sidebar Roblox sampai *More* kelihatan tanpa mengubah density. Baris diisi dari bawah (clone pertama di baris bawah), karena jendela yang dibuka belakangan tampil di depan, jadi baris atas menutup tepi atas baris bawah. Diatur di Main Menu `11` → `9`; `0` = grid biasa (diisi dari atas seperti dulu). Clone yang dibuka ulang sendirian (recovery) bisa muncul di depan sampai Launch All berikutnya.

- **Smallest width tetap 600dp** (900dp sempat jadi default tapi tampilan terlalu kecil). `SMALLEST_WIDTH=...` sekarang diingat di `data/smallest_width` (install ulang tidak mengembalikan), `--undo` menghapusnya. Device yang sempat pindah ke 900dp kembali ke 600dp lewat migrasi `update.sh` (`data/.migrated-sw600`) saat boot berikutnya.

- **Fix: pesan status webhook tidak ter-update + CPU "-"**: id pesan dari respons Discord dulu cuma terbaca kalau `"id"` berada tepat di sebelah `"channel_id"`; urutan key Discord beda, jadi id tidak tersimpan dan tiap laporan tidak bisa meng-edit pesan (runtime kelihatan beku). Sekarang id diambil dari key `"id"` tingkat atas JSON (bukan id author/attachment). CPU butuh dua sampel: laporan pertama sekarang mengambil sampel awal + jeda 2 dtk, jadi CPU sistem & per clone langsung tampil.

- **Fix: grid jendela tidak jalan di device baru**: clone yang belum pernah dibuka belum punya `<pkg>_preferences.xml`, jadi posisinya dilewati sampai clone dibuka sekali. `WindowLayout.apply` sekarang membuat file itu (dan folder `shared_prefs`) dengan owner, izin (771/660) dan label SELinux yang sama dengan folder data app, lalu menulis posisi grid — jadi Launch All pertama di device baru sudah langsung rapi.

- **Izin background Termux otomatis**: `device_setup.sh` memasukkan `com.termux`, `com.termux.boot`, `com.termux.api` (yang terpasang) ke whitelist optimasi baterai (`dumpsys deviceidle whitelist +pkg`) dan `cmd appops set ... RUN_IN_BACKGROUND / RUN_ANY_IN_BACKGROUND allow`, jadi dialog "Let app always run in background?" dari `termux-wake-lock` tidak muncul. `--undo` mengembalikan. `termux-boot.sh` juga mem-whitelist Termux sebelum wake lock.

- **Menu dirapihin**: Settings `13` kembali hanya jeda launch (+ useRoot). Fitur besar pindah ke Main Menu: `10) Discord Webhook` (`core/webhook_cli.lua`: URL, interval, screenshot, notif, sembunyikan nama, kirim tes) dan `11) Jendela & Mode Hemat` (`core/display_cli.lua`: grid, kolom, jarak, heartbeat, mode hemat, batas FPS, render 3D, pasang ulang script). Pilih item satu-satu dengan nilai sekarang ditampilkan; tiap perubahan langsung disimpan.

- **Laporan Discord webhook**: `managers/webhook.lua` — status (device, RAM `/proc/meminfo`, CPU dari selisih `/proc/stat`, suhu thermal zone, online/offline, per clone uptime + CPU dari `/proc/<pid>/stat`, memori heartbeat/RSS, screenshot `screencap`) dikirim tiap `webhook.interval` (300 dtk). Pesan pertama `POST ?wait=true`, id disimpan di `data/webhook_msg.txt`, berikutnya `PATCH /messages/<id>` (404 → pesan baru). Event terpisah (engine mulai, kick, recovery gagal, clone belum login gagal dibuka) dibatasi 1/menit per kejadian. curl jalan sebagai user Termux; URL tidak pernah masuk log. Diatur di Settings `13`; `url` kosong = tidak ada yang dijalankan.

- **Fix: clone belum login yang FC tidak pernah dibuka lagi**: monitor dulu selalu diam untuk clone tanpa akun. Sekarang kalau clone itu tertutup — proses mati, atau proses tersisa tanpa jendela (`APKManager.hasWindow` dari `dumpsys window windows`; tidak terbaca = tidak menebak) — `Recovery.reopenNoLogin` membukanya lagi lewat launcher biasa, **tanpa force-stop** dan tanpa link game, maks sekali per `noLoginCooldown` (120 dtk). Clone yang masih di layar login tetap dibiarkan. Config: `relaunchNoLogin`, `noLoginCooldown`.

- **Dashboard lebih rapi untuk banyak instance**: baris System / Memory / Storage pindah ke atas daftar clone; baris System menampilkan progres `Launching [i/N]` saat Launch All dan `Checking [i/N]` saat monitor mengecek tiap clone (`Monitoring` saat diam); nama `package (username)` dipendekkan di bagian username (`Martlock_..`) supaya package tetap terbaca; baris kosong dihapus supaya 14+ clone muat.

- **`update.sh` langsung pakai versi barunya**: setelah update berhasil, skrip `exec` dirinya yang baru (`--after-update`) supaya migrasi yang dibawa update itu jalan di boot yang sama (sebelumnya baru di boot berikutnya).

- **Migrasi sekali-jalan di `update.sh`**: config lama yang dipertahankan saat update tidak ikut default baru, jadi grid jendela tetap mati setelah reboot. `update.sh` kini menjalankan migrasi (sekarang: `--enable-window-layout`) satu kali per device di setiap jalur keluar (sudah terbaru / offline / habis update); penanda `data/.migrated-<nama>` hanya dibuat kalau hasilnya `OK`, jadi pengaturan yang diubah user setelahnya tidak ditimpa.

- **Auto atur jendela default nyala**: `windowLayout.enabled = true` di `config/config.lua` & template; installer menjalankan `lua main.lua --enable-window-layout` (flag baru) supaya config lama yang dipertahankan saat install ulang juga ikut nyala. Bisa dimatikan di Settings `13`.

- **Auto atur jendela: lebih andal + divalidasi terus**: ukuran layar tidak lagi di-cache selamanya (dibaca ulang tiap 30 dtk; layar yang terbaca portrait setelah boot tetap jadi grid landscape kecuali `orientation = "auto"`), tunggu proses clone benar-benar mati sebelum menulis (force-stop ulang kalau perlu; masih hidup = tidak ditulis), file `<pkg>_preferences.xml.bak` ikut diedit (Android memuat .bak kalau ada), nilai dibaca balik setelah ditulis. `WindowLayout.verify` membandingkan posisi jendela di prefs clone yang jalan dengan slot grid (toleransi 10 px): dicek setelah tiap launch di Launch All dan tiap ±60 dtk; meleset = log `[WINDOW]` saat berubah + penanda `[win]` di dashboard, dibetulkan pada launch berikutnya.

- **Setting device otomatis (`device_setup.sh`)**: lewat root `settings put global` — `window_animation_scale`/`transition_animation_scale`/`animator_duration_scale` = 0, `development_settings_enabled`, `force_allow_on_external`, `force_resizable_activities`, `enable_freeform_support`, `enable_non_resizable_multi_window` = 1 — dan Smallest width 600dp (`wm density = min(w,h)*160/600`, ikut override `wm size`). Idempotent, nilai dibaca balik, `--undo` mengembalikan bawaan, tanpa root = dilewati. Jadi langkah 5/8 di `install.sh`.

- **Heartbeat Delta + mode hemat**: `scripts/rejoin_heartbeat.lua` (Luau) dipasang ke `appAutoExecutePath` oleh `managers/heartbeat.lua` (`Heartbeat.install`, saat monitor start, `lua main.lua --install-heartbeat`, dan installer). Script menulis `<Workspace>/rejoin/hb_<username>.txt` (state ingame/kicked lewat `GuiService` + `ErrorPrompt`, fps, ping, `Stats` memory, `os.time`). `Heartbeat.isUp` dipakai monitor, Launch All, status, dan recovery: heartbeat dari sesi ini menang (kicked/berhenti = tidak sehat → recovery langsung); tanpa heartbeat = cek lama (RSS), atau proses berjalan saat mode hemat. Heartbeat sebelum launch terakhir / sebelum engine start diabaikan. Status baru `Kicked`, label `Running <fps> <MB>`. Mode hemat: `Set3dRenderingEnabled(false)`, `setfpscap`, QualityLevel 1, mute. Diatur di Settings `13`.

- **Installer satu perintah + auto-update tiap boot**: `install.sh` (`curl -sL .../install.sh | sh`) memasang paket lewat `apt`, `lua`, cek root, clone ulang `~/rejoin` dengan config & `data/` lama dipertahankan, cek package clone di config, menulis `~/.termux/boot/start-rejoin.sh` (stub: `update.sh --boot` lalu `termux-boot.sh`), dan mengaktifkan Termux:Boot (`am start` kalau `stopped=true`). `update.sh` = `git fetch` (retry 3x) + `reset --hard` dengan `config/config.lua` & `data/rejoin.log` dipertahankan; gagal = tetap versi lama. Matikan auto-update dengan `data/no-auto-update`. `BOOT_DELAY` default turun ke 10 dtk.

- **Auto atur jendela floating (grid)**: modul baru `managers/window_layout.lua` menulis `app_cloner_current_window_{left,top,right,bottom}` ke `/data/data/<pkg>/shared_prefs/<pkg>_preferences.xml` setiap kali clone di-force-stop sebelum dibuka (Launch All, relaunch, recovery). File ditulis lewat `cat >` supaya inode/owner/izin/SELinux tetap. Default mati (`windowLayout.enabled`), diatur di Settings `13`; ukuran layar dideteksi dari `dumpsys window displays`. Tool `tools/float_probe.sh` untuk melihat key setting jendela.

- **Boot lebih tahan banting**: `termux-boot.sh` mencatat tiap langkah ke `data/boot.log` (dirotasi > 256 KB), menunggu `BOOT_DELAY` (30 dtk), stdin `/dev/null`, dan menjalankan ulang engine kalau crash (maks `MAX_RESTARTS` = 5, jeda `RESTART_DELAY` = 30 dtk; exit 0/130/143 = berhenti). Monitor sekarang menolak jalan kalau engine lain masih aktif (`data/monitor.pid`), supaya engine boot yang tersembunyi dan engine dari menu tidak saling force-stop clone.

- **Launch All: clone kosong dapat jeda singkat `launchEmptyDelay` (default 5 dtk)**: tanpa jeda sama sekali, clone berikutnya dibuka di detik yang sama dan jendela floating clone kosong kadang tidak muncul. Bisa diatur di Settings `13`.

- **Fix: Ctrl+C kadang tidak bisa stop dashboard monitor (harus exit lewat notif bar)**: perintah root (`su -c ...`) mewarisi terminal sebagai stdin, dan Magisk `su` mengubah terminal ke mode raw selama perintah jalan — Ctrl+C jadi byte biasa, bukan SIGINT. Monitor hampir selalu sedang menjalankan `su`, jadi Ctrl+C sering hilang; kalau `su` terputus, terminal bisa tertinggal raw. Sekarang `Shell.exec` menjalankan semua perintah dengan stdin `/dev/null` (dibungkus `{ ...; }` supaya berlaku untuk perintah gabungan), dan loop monitor memastikan `stty isig` tiap siklus.

- **Cek login diverifikasi ke Roblox (curl) + status NoLogin saat clone jalan + debug log**: token `.ROBLOSECURITY` dibaca dari Cookies DB (atau grep, tanpa file `.bak-*`) lalu dicek ke `users.roblox.com/v1/users/authenticated`. HTTP 401 = logout/kicked → `NoLogin`; jaringan gagal = pakai hasil lokal. Cache per clone `loginVerifyInterval` (default 600 dtk), langsung dicek ulang kalau tokennya berubah; bisa dimatikan `loginVerifyRemote = false`. `Status.check` sekarang cek login juga saat RSS clone tinggi (sebelumnya clone yang logout tapi RAM-nya besar tetap tampil Running). Log baru di `data/rejoin.log`: `[LOGIN] ...` (sumber token, panjang token, kode HTTP, hasil) dan `[STATUS] nama: lama -> baru (rss, login)`. Username dashboard memakai nama dari verifikasi ini (token tidak dikirim dua kali).

- **Fix: clone yang logout di-force-stop terus (bikin clone lain ikut force close)**: `Auth.isLoggedIn` dulu grep teks `.ROBLOSECURITY` di seluruh data dir, jadi backup `Cookies.bak-*` dari Inject Cookie dan sisa baris yang sudah dihapus di file SQLite tetap kebaca "login". Clone yang sudah logout (RSS kecil di layar login) dianggap freeze → force-stop + relaunch berulang → RAM penuh → clone lain ikut ketutup. Sekarang login dicek langsung lewat `sqlite3` ke baris cookie aktif (tidak kosong, belum expired); grep cadangan mengabaikan `.bak-*` / `-journal`; probe yang gagal sekali tidak lagi membalik status "belum login" jadi "tidak diketahui". Launch All tetap membuka semua clone; clone yang kebaca belum login hanya tidak ditunggu. Hasil cek login per clone dicatat di log (`Auth: <pkg> login = ...`, `Monitor: <name> login check = ...`).
- **Launch All: jeda antar clone bisa diatur**: `launchSettleDelay` (default 20 dtk) sekarang benar-benar dipakai — clone berikutnya baru dibuka setelah clone sebelumnya jalan **dan** sudah ditunggu `launchSettleDelay` detik (waktu masuk game). `launchWaitInterval` juga dipakai. Menu Settings `13` diperjelas (bahasa Indonesia, input kosong = nilai lama).

- **Fitur clear cache dihapus total**: menu `10) Cache Manager` (`core/cache_cli.lua`), module `managers/cache_cleaner.lua`, flag `lua main.lua --clear-cache`, toggle cache di Settings, dan auto clear saat relaunch di `recovery.lua` dibuang. Menu Settings kembali: Save = 15, Exit = 16. Key `cacheCleaner` di config lama diabaikan.

- **Auto clear cache default OFF + toggle di Settings**: `cacheCleaner.enabled` kini **`false`** di template & config baru (sebelumnya ON, tiap cold start/relaunch). Fallback pembaca dibalik `cc.enabled == true` (key hilang/`nil` = mati) di `managers/cache_cleaner.lua`. Menu **Settings (3)** punya toggle baru: **`15) Toggle auto clear cache`** dan **`16) Toggle clearWebView`** (Save = 17, Exit = 18) + nilai ditampilkan di "View settings". Konsekuensi yang dihindari: `lua main.lua --clear-cache` kini **tetap jalan walau auto mati** — `applyAll(force=true)`/`applyForInstance(inst, force=true)` melewati saklar (permintaan manual eksplisit menang); ganti `main.lua` memanggil `applyAll(true)`. Install lama dengan config `enabled=true` tetap true sampai di-toggle manual.

- **Reverse "Get Key" Delta apengjers → URL keysystem terungkap (fondasi Auto Get Key)**: statis scan penuh (`DeltaNonLiteFloatingA10 (1).apk` — 5 dex, `libroblox.so`, assets, string pool + UTF-16) **tidak menemukan URL** karena link dibuat saat runtime dan payload executor terenkripsi di `assets/natives_sec_blob.dat` (563,952 B; bukan zlib/XOR/base64; sha256 **identik di 8 varian** proyek → satu family). Tangkapan nyata: rekam intent browser (ACTION_VIEW) setelah tombol ditekan → browser dibuka ke `https://auth.platorelay.com/a?d=<token>`. Domain **`auth.platorelay.com`** (Cloudflare 104.21.58.119 / 172.67.159.107; bukan deltaexecutor/linkvertise) — `d=` = token per-device runtime; halaman disajikan **HTTP 200 `text/html` tanpa redirect** (alur checkpoint dijalankan JS client-side). Key sistem dikendalikan server mod. Detail + kandidat pendekatan auto-get-key: `docs/research/delta_get_key.md`.

- **Inject Cookie (REVERT: pm clear + seed launch dihapus)**: percobaan "reset penuh data clone sebelum inject" **tidak membantu** (data kehapus tapi tetap ga login) → reverted penuh: `force-stop` → inject kembali non-destruktif; nggak ada `pm clear`, nggak ada seed launch, banner/prompt kembali seperti semula. Ke depannya inject TIDAK menghapus data clone apa pun selain baris `.ROBLOSECURITY` usang.
- **`probeToken` tambah Live store check**: setelah launch, tiap DB dicek keberadaan `Cookies-wal` pasca-launch — Chromium membuat `-wal` begitu network/cookie service app **sungguh membuka store**. `-wal ADA` = app baca cookie (gagal login = server-side); `-wal TIDAK ADA` = app bahkan tidak menyentuh cookie store (masalah sebelum pembacaan DB). Ini sinyal biner baru untuk memisahkan dua kelas kegagalan yang sebelumnya tak terlihat.
- **Doctor tambah 3 sinyal kunci**: `WEBVIEW_PROVIDER` (webviewupdate get-current-webview-package — provider yang SESUNGGUHNYA dimuat bisa beda walau versionName sama), `MAGISK` (versi — kalau deny-list tidak aktif di satu device, GMS Play Integrity gagal → Roblox tolak/revoke login khusus device itu), `NETWORK_IP` (ipinfo.io — token sama di dua jaringan beda bisa lolos di satu dan di-flag di lain).
- **Inject Cookie (hapus stale WAL WebView — gap dari learn.md #2)**: setelah `force-stop` dan backup, kini `rm -f "<db>-wal" "<db>-shm" "<db>-journal"` per Cookies DB (log `hapus stale` vs `tidak ada` via `existsFile`). Chromium membuka cookie store dalam mode WAL — file transaksi sisa dari proses yang dibunuh bisa di-replay saat relaunch dan **menimpa row yang baru kita tulis**; menghapusnya saat app mati aman (dibuat ulang saat buka). Ditambah `dbInfo()` (`--doctor`) kini mencetak **`journal_mode`** (delete vs wal) + **`wal_size`** per Cookies DB — sinyal biner baru untuk diff device bisa-vs-tidak (apakah device yang gagal menyisakan WAL membengkak / mode journal berbeda).
- **`wal_checkpoint` log kini terinterpretasi**: `0|-1|-1` selama ini TIDAK berarti gagal — itu `journal_mode!=WAL` saat koneksi kita membuka DB → tidak ada WAL untuk dilipat (no-op). Sekarang checkbox FULL dengan retry sekali saat BUSY (`sleep 0.2` lalu ulang), dan log memberi makna: `no-op`, `BUSY (belum dilipat)`, atau `WAL dilipat ke DB utama`.
- **Diff `--doctor` dua device → koreksi kesimpulan**: env (WebView, APK SHA1, root, SELinux, Android, schema DB) **identik** di device yang bisa vs tidak bisa — teori dependency gugur. Data inject pasca-launch juga identik (row `len=1200 count=1` SAMA), TAPI device-mu login & temen tidak → pembeda ada di interaksi WebView↔Roblox (fingerprint/IP/attestation) atau akun. Ditambah **prop attestation** ke doctor: `BUILD_FINGERPRINT`, `FLASH_LOCKED`, `VERIFIED_BOOTSTATE`, `VBMETA_DEVICE_STATE`, `SECURITY_PATCH` (bahan diff device-flag). Eksperimen cross penentu: inject token fresh akun yang "bisa" ke device temen → jika tetap gagal = fingerprint device yang di-flag (bukan kode).
- **`probeToken` filter backup di-fix**: `line:find("%.bak%-", 1, true)` memakai `plain=true` tetapi string masih ber-persen sehingga mencari literal `%.bak%-` → **tidak pernah** mem-filter `Cookies.bak-*` sendiri (log device penuh noise backup). Sekarang `.bak-`.
- **Verdict probe dikoreksi (jujur terhadap bukti)**: device yang BERHASIL login ternyata TIDAK men-rotasi cookie dalam 8 detik (log bisa: `prefix=SAMA` + login sukses). Maka `COOKIE_OK_NO_USE` kini **TIDAK KONKLUSIF** (bukan "belum pakai"), teks diubah termasuk status per-DB; rotasi (`BERBEDA`) tetap sinyal kuat autocontained = `LOGIN_CONFIRMED`.
- **Doctor `command -v` di-fix**: toybox `timeout` meng-exec kata pertama sebagai binary sungguhan, sementara `command` adalah shell builtin → `exec command: No such file or directory` (terlihat di kedua log device untuk `LUA_BIN`/`CURL_BIN`/`SQLITE_BIN`). Ganti dengan `ls <termux path>` (binary nyata, aman di bawah timeout).
- **Inject Cookie (`--doctor` + output lengkap untuk diff antar-device)**: modus baru `lua main.lua --doctor` (`managers/doctor.lua`) mencetak report compare-friendly `KEY=value` (root uid & SELinux, Android SDK/release/model, versi WebView Google/AOSP + Play Services, lua/curl/sqlite3, per instance: versionName/versionCode + **SHA1 APK** + firstInstallTime + daftar SEMUA Cookies DB + ukuran + `PRAGMA user_version` + kolom schema). Jalankan di **kedua device** dan diff output — baris yang beda = dependency/fingerprint penyebab "inject [OK] tapi app ga login" di satu device. Semua jalur diagnostik inject kini **juga masuk `error.log`** (bukan cuma console): hasil pre-inject verify (code+snippet), kolom schema yang diisi per DB, DELETE output, wal_checkpoint, hasil verifikasi ketat per DB (`len|count`), probe rotasi, dan blok `[VERDICT]`.
- **Inject Cookie (`[VERDICT]` otomatis)**: setelah launch + jeda 8 detik (hanya baca-DB, tanpa network), `probeToken` kini mengembalikan verdict: `LOGIN_CONFIRMED` (prefix != token → WebView sudah authenticate & Roblox rotasi session = login pasti sukses), `COOKIE_OK_NO_USE` (row utuh tapi belum rotasi → bandingkan dua device via `--doctor`), `COOKIE_CLEARED` (baris hilang → app menghapus cookie saat boot), atau `NEED_MANUAL_CHECK`. Dump (menu 8) juga di-log penuh ke `error.log`.

- **Inject Cookie (hilangkan pemicu revoke — jangan auth server saat app jalan)**: bukti error.log 01:43: token VALID HTTP 200 (01:43:28) → inject 1200 char OK → app dibuka (01:43:30) → **verifyRemote pasca-launch yang kita kirim 5 detik kemudian : 401 code 9002 "User is not authenticated"**. Diagnosa: curl + WebView mengotentikasi **session yang sama dari dua klien beruntun** dalam hitungan detik = pola "session hijack" yang dikenali Roblox → app dianggap mencuri session → session langsung dibatalkan (sekali-sekali membawa browser sumber ikut logout). Pemicunya di kendali kita → **dihapus**: setelah launch TIDAK ada lagi panggilan network dengan token. Diganti pemeriksaan **rotasi yang murni baca-DB** (`probeToken`): tiap Cookies DB dibaca `len | substr(value,1,6) | count` dan dibandingkan dengan token yang di-inject — prefix BERBEDA = WebView SUDAH authenticate & Roblox men-rotasi session = **login pasti sukses**; prefix SAMA = belum ada rotasi, cek app. Verifikasi live (`verifyRemote`) tetap ada hanya di **pre-inject fail-fast** dan di submenu `3) Cek validitas` — dan menu 3 kini memperingatkan **tutup clone dulu** sebelum cek. `probeToken` juga tidak lagi menampilkan `Cookies.bak-*` kita sendiri di daftar "File lain" (noise).
- **Inject Cookie (multi-DB, fix "ga kelogin padahal [OK]")**: sebelumnya inject SELALU menulis ke `app_webview/Default/Cookies` (`locateCookieDb` ambil `head -n 1`), padahal clone mod/Lite bisa menyimpan profile WebView live di direktori lain (`app_webview/<profile>/Cookies`) — injeksi masuk ke DB yang **tidak pernah dibaca app**, sehingga token VALID + row utuh (verifikasi ketat lolos) tapi UI tetap logout. Sekarang `locateCookieDbs` (plural): `find -maxdepth 6 -name Cookies` mengumpulkan **SEMUA** Cookies DB, dan inject menulis row yang sama ke **tiap DB** (backup `<db>.bak-<ts>` per DB → DELETE ragged rows → INSERT schema dinamis → `wal_checkpoint(TRUNCATE)` → verifikasi ketat `len==#token` & count==1 per DB). Gagal satu DB di-lapor dengan path-nya; sukses sebagian → `[WARN]`. Dump (menu 8) kini men-dump **semua** DB ber-label path.
- **Inject Cookie (auto diagnostik pasca-launch)**: setelah launch + `[CEK]`, CLI otomatis mencetak `probeToken`: per-DB status baris `.ROBLOSECURITY` (`len|count`) + hasil `grep -a -r -l -F` prefix token di seluruh base dir → memperlihatkan **file lain** yang menyimpan token (tanda mod menyimpan session di luar WebView). Menghilangkan tebak-tebakan: kalau token hanya ada di Cookies DB → live store murni WebView; kalau muncul file lain → lokasi session mod yang sebenarnya.

- **Inject Cookie (rule pakai 1 clone = 1 akun)**: root cause "inject berhasil tapi ga kelogin" terakhir = **session di-revoke server-side karena satu token dipakai login ke banyak clone/device beruntun** (Roblox force-logout SEMUA sesi, termasuk browser sumber). Bukti log: token VALID (HTTP 200) sebelum inject (`00:45:43`) dan 4 detik setelah app dibuka (`00:45:49`), value utuh 1200 char (verifikasi ketat lolos) — jadi serialize inject/DB tidak bersalah; session mati *setelah* app authenticate. Kini opsi 1 mencetak **banner peringatan** sebelum paste: 1 token = 1 clone = 1 akun; token yang dipakai >1 clone → force-logout + rotasi. Rekomendasi hasil: untuk tiap clone, export + inject token akun yang BEDA, lalu verifikasi visual (avatar/username muncul = login sukses).

- **Inject Cookie (login fix)**: verifikasi pasca-INSERT kini **ketat** — `length(value)` harus **persis sama dengan panjang token asal** (sebelumnya cukup `>0`, sehingga value yang terpotong/rusak di-shell masih lolos `[OK]` tetapi cookie invalid → app tetap di layar login). Mismatch → `[GAGAL] INJECT TERPOTONG/RUSAK` dengan angka char tersimpan vs asal + lokasi backup.
- **Inject Cookie (auto-launch + re-check)**: setelah inject `[OK]`, CLI otomatis **membuka clone** (`APK.launch`) supaya app langsung authenticate ke Roblox (mempersempit jendela revoke session server-side dan menghapus langkah manual "buka app"), lalu **verifikasi ulang token via curl 4 detik setelah launch** dan mencetak `[CEK]` apakah session masih VALID atau sudah di-REVOKE. Ini memisahkan dua kelas kegagalan: (a) token di-revoke server (bukan bug inject), (b) session masih valid tapi app tetap di layar login → masalah DB/WebView yang nyata untuk diburu lebih jauh.

- **Inject Cookie (terminal I/O)**: alur token kini **tanpa input sama sekali setelah paste**. Opsi 1 (Inject) & 3 (Cek validitas) membaca token (`readToken()` yang langsung menghapus baris echo paste 1170-char dari layar), lalu **`os.exit(0)`** begitu hasil tercetak — tidak ada lagi `io.read()` pasca-paste, tidak ada submenu/menu yang menunggu input yang tidak datang. Terminal jadi mandek karena *paste raksasa diikuti blok baca*; dengan membunuh proses segera setelah inject, tidak pernah ada momen "nunggu input beku". Konfirmasi inject cukup `type 'y'`. Setelah selesai kembali ke shell (`~ $`), tinggal `lua main.lua` bila mau menu lain. Opsi 2 (Dump, tanpa paste) tetap one-shot balik ke menu utama. Pengaman ekstra `core/logger.lua`: echo log ke konsol di-cap 200 char + `...` (file log tetap penuh) — melindungi baris raksasa jika `logLevel=DEBUG` di-flick. Risiko sisa hanya jika UI Termux beku *di tengah* paste: swipe-close session → buka baru (ketik/Enter/Ctrl+C bisa ikut mati di level OS, di luar jangkauan script).

- **Inject Cookie (UX anti-stuck)**: submenu now one-shot — habis aksi (inject/dump/cek token) muncul `[Selesai] Tekan Enter untuk kembali ke menu utama`, `io.read()` sekali menelan sisa buffer stdin hasil paste token besar (yang bisa mendesync keyboard Termux), lalu otomatis `break` balik ke Menu Utama. Tidak ada lagi kondisi "macet di submenu / input ga respon" pasca-inject. Pemulihan darurat tetap: `Ctrl+C` → `lua main.lua`.

- **Inject Cookie**: menu `7) Inject Cookie` (`core/inject_cookie_cli.lua` + `managers/cookie_injector.lua`) — inject token `.ROBLOSECURITY` ke Cookies DB WebView clone pilihan dari config. Auto `am force-stop` dulu, target path memakai `Auth.getBaseDir()` (hormati override `cookiePath`), deteksi DB via app_webview/Default/Cookies + fallback `find -maxdepth 5 -name Cookies`, butuh `sqlite3` (`pkg install sqlite`). Runner sqlite di-resolve otomatis: `su` tidak mewarisi PATH Termux, jadi dicoba `env PATH=<termux>/bin:/system/bin LD_LIBRARY_PATH=<termux>/lib <termux>/bin/sqlite3`, lalu path absolut Termux, lalu `sqlite3` sistem; tiap kandidat diuji `SELECT 1;`. Schema dibaca dinamis (`pragma_table_info`, 6 kolom) sebelum `INSERT OR REPLACE`, row mengikuti **jejak nyata login in-app** (di-verifikasi dari dump clone yang berhasil login): `host_key='.roblox.com'` (dengan titik, domain cookie), `expires_utc=14380828598000000` (WebKit µs ~2056), `samesite=-1` (UNSPECIFIED), `source_scheme=2` (HttpsOrigin), `source_port=443`, `top_frame_site_key=''` (legacy/unpartitioned agar match semua top frame), kolom ekstra NOT NULL tanpa default diisi literal kosong sesuai tipe. Sebelum INSERT: **verifikasi remote token** via curl → `users.roblox.com/v1/users/authenticated` — **fail-closed**: hanya respons `HTTP 200` + body berisi `"name"` yang lolos; semua kondisi lain dibatalkan dengan pesan yang menampilkan respos server (~160 char). Verifikasi memakai **satu panggilan curl di stdout** (`-w '\n%{http_code}'`) — tidak ada lagi file temp `$$.json` (sebelumnya `$$` beda PID antar `su -c` → body selalu kosong). B2: fix `tonumber(string.gsub(...))` yang mem-boom nge-crash (`base out of range`) karena gsub mengembalikan 2 nilai; verify remote dibungkus pcall. Fitur baru: submenu `3) Cek validitas token` di Inject Cookie (geser Exit ke 4) untuk cek token tanpa inject. DELETE semua baris `.ROBLOSECURITY` usang (host_key salah/top_frame penuh) supaya cuma satu baris bersih, `creation_utc`/`last_access_utc` diisi WebKit-µs sekarang (mirror login asli), verifikasi akhir `length|count` harus `1170|1`. Backup DB ke `<db>.bak-<ts>`, `PRAGMA wal_checkpoint(TRUNCATE)`, `Auth.resetCache()`. `core.main` expose `Auth.getBaseDir()`. Debug: menu `8) Dump Cookies (debug)` (`core/dump_cookies_cli.lua` + `CookieInjector.dump()`) menampilkan semua baris cookies (value hanya panjangnya) buat diff login kerja vs hasil inject. Main menu: Exit digeser ke `9)`.

- Auto clear cache saat launch: `cacheCleaner` (default ON) — cache tiap clone dibersihkan setiap cold start / relaunch (setelah force-stop, sebelum launch) via `rm -rf` manual terhadap dir cache app (sama dengan tombol Settings "Clear cache"; **`pm clear-cache` tidak ada di Android**): `cache/`, `code_cache/`, external cache, dan dengan `clearWebView=true` + WebView caches (`app_webview/Default/{Cache,Service Worker,Code Cache,GPUCache}`). Log mengukur byte `before/after` sebagai bukti. CLI manual: `lua main.lua --clear-cache`. Login aman: Cookies (`.ROBLOSECURITY`), Local Storage, `shared_prefs`, databases, `files` tidak pernah disentuh. Module baru `managers/cache_cleaner.lua`, call site di-wrap pcall di `recovery.lua` (launchAndJoin/relaunch/checkAndRecover).

## v0.1

Initial Project

- Project Structure
- Logger
- State Manager

---

## Unreleased / Bug fixes

- Launch APK: resolve real launchable activity (`cmd package resolve-activity`) with `monkey` fallback instead of hardcoded `.MainActivity`
- Process detection: `pidof` -> `pgrep` -> `ps` fallback chain for `isRunning`
- Monitor/recovery: correct success/failure handling around pcall + recovery boolean
- AutoExecute: treat global `config.autoExecute` as the shared script; per-instance path is an optional override
- Config template/working config: removed per-instance `autoExecutePath` in favour of the global AutoExecute path

---

## v0.2 — Android clone integration

- Auto-detect Roblox apps/clones during Setup Wizard via `cmd package resolve-activity` (works for renamed clones like `com.apengjers.v3`), plus optional `clonePackagePrefix` fast filter. Manual input still available.
- New `utils/roblox_link.lua`: safe game-link normalization
  - Public game links (`https://www.roblox.com/games/<placeId>`) optionally converted to `roblox://experiences/<placeId>`
  - Private server share links (`https://www.roblox.com/share?code=...&type=Server`) always opened as-is
  - Unknown/invalid links rejected safely
- Recovery now opens the instance game/private-server link through the normalizer before `am start VIEW`
- New settings: `clonePackagePrefix`, `normalizeGameLink`
- Main Menu: new shortcut `Launch + Join an instance` (choose an instance, launch its app and open its game link manually via `Recovery.launchAndJoin`)

---

## v0.3 — Launch-all + live per-instance status

- Main Menu `1) Launch + Join` now launches ALL configured instances (no manual pick), then immediately starts the monitor.
- New `managers/status.lua`: tracks per-instance status — `offline`, `starting`, `ingame`, `stuck`, `freeze`, `recovery`.
- Freeze detection via logcat ANR (`ANR in <package>`) with a grace-period fallback for `stuck`.
- `Recovery.relaunch()` force-stops and relaunches an app that has stayed frozen for `freezeTimeout` (default 300s, counted from when stuck/freeze was set).
- Monitor prints a live per-instance status table each cycle.
- New settings: `freezeTimeout`, `gracePeriod`, `anrCheckEnabled`.

---

## v0.3.1 — Fix launch & public link

- Launch now uses `monkey -p <pkg> -c LAUNCHER 1` FIRST (works in Termux without `cmd package resolve-activity`, which is unavailable in a non-root Termux shell); resolve-activity is only a fallback and no longer blocks the launch. Fixes instances not opening.
- Public game links are now ALWAYS converted to the deep link `roblox://experiences/<placeId>` so Roblox joins the place directly (an https URL only wakes the app without entering the game).
- Removed the `normalizeGameLink` setting/config/menu option (public links always deep-link; private `/share` links are still opened as-is).
- `utils/android.lua` launch updated to match the monkey-first strategy.

---

## v0.3.2 — Fix multiple-clone launch (App Cloner floating)

- Launch now targets the package EXPLICITLY first: `am start -a MAIN -c LAUNCHER -p <pkg>`. This starts each clone's own launcher task (works for App Cloner clones like `com.apengjers.v3`/`v4`, whose activities stay `com.roblox.client.*`) without depending on `cmd package resolve-activity`. `monkey` and resolve-activity remain fallbacks.
- "Launch All" (`main.lua` option 1) now pauses ~3s between instances so a floating-window clone appears before the next one is launched.
- `Android.openURL` now accepts an optional target package and opens the game link with `-p <pkg>` so a `roblox://experiences/<placeId>` deep link is delivered to the correct clone instead of a single shared default handler. Falls back to a non-targeted VIEW if the targeted start fails.

---

## v0.3.3 — Fix disappearing config & stuck "ingame" status

- `core/config.lua serializeTable`: array/numeric keys now serialize as real integer keys (`[1] = ...`) instead of string keys (`["1"] = ...`). Previously a save rewrote `instances` with string keys which `ipairs` could not read, so a later save blanked the config to `instances = {}`.
- `managers/instance.lua load` + `core/setup_wizard.lua nextId`: read with `pairs()` and normalize mixed string/number keys so configured instances always survive a reload.
- `managers/apk.lua isRunning`: process matching is now anchored to the START of the process command (`^<pkg>($|:)`) instead of a loose substring. This fixes status getting stuck at "ingame" after an app is closed (a leftover process containing the name as a substring no longer counts), so the monitor now reports `offline` and recovers/relaunches the app.

---

## v0.3.4 — Launch one clone at a time

- `Recovery.waitUntilRunning()` added: after launching a clone, poll `APK.isRunning()` until its process is observed (then a short settle pause) or a timeout elapses.
- "Launch All" (menu 1) now launches clones ONE AT A TIME — it waits for each clone to reopen before starting the next, so multiple floating-window clones each get a chance to appear instead of one being crowded out (previously a fixed 3s pause / then a monitor that still reported "starting").
- New settings (Settings menu → `14) Edit launch wait settings`): `launchWaitInterval` (3s), `launchWaitTimeout` (90s), `launchSettleDelay` (5s).

---

## v0.3.5 — Fix launch hang (isRunning never matched)

- Fixed `managers/apk.lua escapeRegex`: the replacement was producing `%.` (percent-dot) instead of `\.` (backslash-dot), so the `pgrep -f '^com\.apengjers\.v6($|:)'` pattern never matched and `isRunning` always returned false. `waitUntilRunning` then waited a full timeout per clone, making "Launch All" appear stuck (repeating `pidof`/`pgrep`/`ps`).
- `escapeRegex` now emits backslash escapes (`\.`) valid for POSIX ERE (`pgrep -f`).
- `ps -A` fallback compares the process command start with a plain (non-regex) check (`cmd == pkg or cmd starts with pkg..":"`) instead of feeding an ERE pattern to Lua's `string.match`.

---

## v0.3.6 — Count-based launch wait + public link joins the map

- New `managers/apk.lua APKManager.countProcess(name)`: counts running processes for a base name (e.g. `com.roblox.client`) via pgrep/pidof/ps. App Cloner clones all run as `com.roblox.client`, so the count tracks how many clones are actually up regardless of the renamed package.
- `Recovery.waitUntilRunning` now accepts a `target` count: it waits until `countProcess(processCheckName) >= target` (then a settle pause) or a (shortened) timeout. Default `launchWaitTimeout` lowered 90→30s so a failed detection never hangs "Launch All".
- "Launch All" (`main.lua`) records a baseline `countProcess` before the loop, then after launching clone `i` waits for `count >= baseline + i` before starting the next — launching one clone at a time, each confirmed open before the next.
- New setting `processCheckName` (default `com.roblox.client`) — the base process counted; editable via Settings → `14) Edit launch wait settings`.
- `utils/roblox_link.lua`: public game links now convert to `roblox://placeId=<placeId>` (deep link that drops straight into the game/map) instead of `roblox://experiences/<placeId>` (which only opened the game's page on mobile).

---

## v0.3.7 — Root (su) process detection + direct-join deep link

- **Root required** (`utils/shell.lua`): every shell command now runs through `su -c '...'` when `useRoot` is enabled (default `true`). This is the real fix for "detection looks broken": on a rooted device Android 11+, Termux running as a NORMAL user cannot see other apps' processes, so every `pidof`/`pgrep`/`ps` probe returned empty and every instance looked offline. Running as root (Magisk) makes the Monitor see the real per-clone processes again. Set `useRoot = false` on a non-root device.
- **Correct process model**: App Cloner clones keep their OWN package process name (`com.apengjers.v3`, etc. — verified from the clone APK manifest and on-device `su -c "pidof com.apengjers.v3"`), NOT `com.roblox.client` as v0.3.6 assumed. `com.roblox.client` is only the class/activity base, not the process name.
- `managers/apk.lua`: new `APK.countRunning(packages)` counts how many of the given configured packages report `isRunning` — accurate per-clone count without needing a shared base name.
- `Recovery.waitUntilRunning` + "Launch All": replaced the `countProcess(processCheckName)` target with `targetCount` of running instances (`countRunning >= baseline + i`). Drops the now-unneeded `processCheckName` setting.
- `utils/roblox_link.lua`: public game links now convert to **`robloxmobile://placeID=<placeId>`** (capital `ID`) — the scheme the clones register and that `ActivityProtocolLaunch` handles by joining the map directly — instead of `roblox://placeId=<placeId>` which only opened the game's page. `robloxmobile://` added to the accepted-scheme whitelist.
- New setting `useRoot` (default `true`), editable via Settings → `14) Edit launch wait settings`.

---

## v0.3.8 — Quiet monitor + direct-join deep link

- `core/logger.lua`: new console `logLevel` filter (default `INFO`). `Logger.debug` lines are now hidden unless `logLevel = "DEBUG"`, fixing the monitor being flooded with `su -c ...` and per-probe `pidof`/`pgrep`/`ps` debug spam every cycle. Set to DEBUG via Settings → `15) Edit logLevel` for troubleshooting.
- `managers/status.lua printSummary`: status table rewritten as one compact line — e.g. `1=starting  2=running  3=freeze  4=recovery` — instead of the verbose multi-line log-style output.
- New setting `logLevel` (default `INFO`), editable via Settings → `15) Edit logLevel`.
- `utils/roblox_link.lua`: public game links now convert to **`roblox://experiences/start?placeId=<placeId>`** — the deep link form Roblox uses to START/join the game directly. Earlier formats (`roblox://experiences/<id>`, `roblox://placeId=...`, `robloxmobile://placeID=`) only opened the game's page on this client. Example: `https://www.roblox.com/games/110776611234/Steal-An-Egg` → `roblox://experiences/start?placeId=110776611234`.

---

## v0.3.9 — Force ActivityProtocolLaunch for direct join

- `utils/android.lua openURL`: public-game links are now delivered by forcing the clone's **`ActivityProtocolLaunch`** handler via `am start -a VIEW -d '<url>' -n <pkg>/com.roblox.client.ActivityProtocolLaunch`, instead of the old `-p <pkg>` (which lets Android pick an activity that only shows the game's page). Falls back to `-p <pkg>` then an untargeted VIEW, logging which strategy ran.
- `utils/roblox_link.lua`: public links convert back to **`robloxmobile://placeID=<placeId>`** — the form that `ActivityProtocolLaunch` on the App Cloner clones joins straight into the map (verified on the cloned Roblox activity set and the Android direct-join path).

## v0.4.0 — roblox://placeId= auto-join via -p (proven per-clone)

- `utils/roblox_link.lua`: public game links convert to **`roblox://placeId=<placeId>`** (was `robloxmobile://placeID=` / earlier `roblox://experiences/start?placeId=`).
- `utils/android.lua openURL`: primary strategy is now **`am start -a VIEW -d '<url>' -p <clone>`**; the `-n <pkg>/com.roblox.client.ActivityProtocolLaunch` strategy (which only opened the game page) is removed. Untargeted VIEW remains as fallback.
- On-device testing proved `roblox://placeId=<id>` delivers the clone's deep-link join directly into the map, and `-p com.apengjers.v3/v4` routes each to its own account.

## v0.4.1 — wait for clone before joining

- `managers/recovery.lua launchAndJoin`: now polls until the clone's process is running (up to `checkTimeout`, with a short `launchSettleDelay` settle) **before** sending the deep link. Previously the join link was sent immediately after launch, landing while the app was still on the splash screen, so Roblox showed the game's page instead of auto-joining. Mirrors the wait already done by the monitor's `recover` path.

## v0.4.2 — direct deep-link join + Ctrl+C hard stop

- `managers/recovery.lua launchAndJoin`: instances with a `privateServer` are now joined by sending the deep link **directly** (`openGameLink`), **without** a separate `APK.launch` (MAIN/LAUNCHER) first. On-device proof: firing `roblox://placeId=<id>` + `-p <clone>` at a cold clone auto-joins the map, whereas launching through the launcher activity first left the app on its home screen so the link only showed the game page. `APK.launch` is still used for instances with no link.
- `main.lua`: Ctrl+C hard stop — `prompt()` now `os.exit(0)` when `io.read()` returns nil (Ctrl+C/EOF in the menu), plus "tekan Ctrl+C untuk berhenti" hints in the menu and before the monitor starts.

## v0.4.3 — cold start (force-stop) before join

- `managers/recovery.lua launchAndJoin`: instances with a `privateServer` are now **force-stopped first** (`APK.forceStop(pkg)`, 1s settle) before the join deep link `roblox://placeId=<id>` + `-p <clone>` is sent. On-device proof: option-A join only auto-enters the map from a *cold* clone; if the clone is still warm the link just shows the game page. This makes the tool mirror the manual procedure that worked (force-stop → join link).
- Instances without a link still use `APK.launch(pkg)`.

## v0.4.4 — self-contained join link in recovery.lua

- `managers/recovery.lua`: `openGameLink` is now **self-contained** — it extracts the place id and builds `roblox://placeId=<id>` directly (no longer depends on `utils/roblox_link` syncing to the device). Handles `https://www.roblox.com/games/<id>/...`, `?placeId=<id>`, `roblox://placeId=<id>`, `roblox://experiences/<id>`. Private-server `/share` links stay untouched. Removed the unused `RobloxLink` require. This guarantees the tool sends the proven auto-join form regardless of other files.
- Prior fix (v0.4.3) already force-stops the clone (cold start) before sending the link.

## v0.4.5 — colored live-status dashboard + Ctrl+C actually stops monitoring

- `managers/status.lua`: `printSummary` now clears the terminal (`\27[2J\27[H`) each cycle and renders a full multi-row, colorized table instead of stacking plain lines:
  - left column = package clone (`com.apengjers.v3`), right column = status label + color (Running=green, Stuck=red, Recovery=yellow, Starting=cyan, Offline=dim).
  - footer rows show real **Memory Usage** (`/proc/meminfo`: % + free MB) and **Storage Available** (`df -h`), best-effort with a 30s cache to avoid shell cost every cycle.
- `managers/monitor.lua`: installs a **SIGINT handler via lua-posix** so Ctrl+C truly stops monitoring on Termux. Root cause fixed: `os.execute("sleep")` swallows SIGINT (POSIX `system()` blocks it), so without a handler Ctrl+C did nothing; the handler flips `running = false`.
- `utils/timer.lua`: new `Timer.sleepInterruptible(seconds, isStopped)` sleeps in 0.25s steps, so once the SIGINT handler fires the monitor exits within ~0.25s instead of waiting out the whole interval. Monitor loop now uses it.
- `main.lua`: after the monitor stops, if `Monitor.interrupted()` is true (Ctrl+C pressed) the program exits cleanly (`os.exit(0)`) instead of returning to the menu.
- **Requires** `pkg install lua-posix` on Termux for Ctrl+C to work.
- Cleanup: removed now-unused `utils/roblox_link.lua`, `debug_normalize.lua`, and `debugging.txt`; updated `README.md` and `docs/roadmap.md` references.

## v0.4.6 — fix misaligned monitor table

- `managers/status.lua`: fixed the status-table layout that rendered with borders "straying" into the middle of rows on Termux:
  - **Border width now equals body width** (they were out by 4 chars, so the `+`/`|` separators never lined up). The border is generated from the same width as a data row.
  - The frame is built as **one single string** and cleared+written in a single `io.write("\27[2J\27[H" .. frame)` + flush, instead of clearing in a separate `io.write` — the earlier cursor-home (`\27[H`) wrote into the middle of later printed rows.
  - `\27[0m` reset is only emitted on colored status cells (no stray escapes on the header/footer rows).
  - Column widths tuned (Instance 24 / Status 18) so values like `com.apengjers.v3`, `38% (2466MB Free)`, and `75G Free` fit without overflow.

## v0.4.7 — flicker-free in-place dashboard + clean console

- `managers/status.lua`: `printSummary` now redraws **in place** instead of full-screen clearing every cycle:
  - Tracks the drawn frame height and moves the cursor back up (`\27[<n>A`) each refresh, then redraws and clears any leftover below (`\27[J`) — no more screen flicker.
  - Rows are joined with **`\r\n` (CRLF)** instead of `\n` — fixes rows drifting rightward on Termux (LF alone doesn't reset the column to 0 when ONLCR is off), which was the root cause of the "stray border" mess visible both on screen and in copy/paste.
  - Hides/shows the cursor around each draw (`\27[?25l`/`\27[?25h`) for a smooth refresh.
  - New `Status.resetDashboard()` resets the frame position at the start of each monitor session.
- `core/logger.lua`: added `Logger.setConsoleVisible(bool)`. When `false`, log lines are written to the file only (not the console), so monitor event logs don't push the dashboard around.
- `managers/monitor.lua`: hides console logging while monitoring (`Logger.setConsoleVisible(false)` + `Status.resetDashboard()`), and restores it plus the cursor (`\27[?25h\r\n`) when the monitor stops.
- Net effect: monitoring shows only a clean, non-flickering status dashboard; full logs still go to `data/rejoin.log`; Ctrl+C stops and returns to a normal console.

## v0.4.8 — box-drawing dashboard + silent launch + "Resetting" status

- `managers/status.lua`:
  - Dashboard now uses **Unicode box-drawing** borders (`╭─┬─╮`, `├─┼─┤`, `╰─┴─╯`, `│`) instead of ASCII `+ - |`, matching `examplecli.txt`.
  - Status cells render as **`Label (Color)`** (e.g. `Resetting (Yellow)`, `Running (Green)`), with the label colored by status.
  - `Starting` now renders **blue** (was cyan); added a **color legend** under the table (Resetting/Recovery = Yellow, Stuck = Red, Starting = Blue, Running = Green) plus the Ctrl+C footer hint.
- New internal status **`resetting`** (`STATUS_UI["resetting"] = Resetting, yellow`): `Status.beginResetting(id)` / `Status.endResetting(id)` mark an instance while it is being force-stopped / relaunched / joined, and `Status.check` holds it (like `recovery`) so the dashboard shows "Resetting (Yellow)" until the operation finishes.
- `managers/recovery.lua`:
  - `launchAndJoin` and `relaunch` now set/unset the `resetting` status around their work.
  - Launch progress logs (`launchAndJoin`, `relaunch`, `waitUntilRunning`) downgraded from `Logger.info` to `Logger.debug` (kept in the log file, not shown on the console).
- `main.lua`:
  - Removed the startup debug prints (`monitorInterval`, `instance count`).
  - Option `1) Launch All + Monitor` now hides console logging for the whole launch phase (`Logger.setConsoleVisible(false)`), strips all per-clone progress text, and goes **straight to the dashboard** once the (still sequential, still waiting) launch finishes.

## v0.4.9 — clean start + exact process detection (closed app now reopens)

- `managers/monitor.lua`:
  - `Monitor.start` now **clears the screen** (`\27[2J\27[H`) right before the dashboard so leftover menu text doesn't sit above it — picking `1)` goes straight to a clean full-screen dashboard.
  - Instance health is now based on the **real process state every cycle** (`apkManager.isRunning`), no longer inherited from a stale status memory (`ingame/starting/freeze`). This ensures a closed app is detected and recovered instead of staying "healthy" forever.
- `managers/apk.lua` — `isRunning`:
  - Root cause of "app closed but not reopening": the process match included sub-processes (`com.apengjers.v3:p0`) that keep running as background services after the UI is swiped away, so `isRunning` stayed `true` → status stuck at `ingame` → recovery was never triggered.
  - Now matches the clone's **exact main process name only** (`com.apengjers.v3`, no trailing `:`), so once the UI is closed (main process gone) the instance is seen as not-running and the monitor reopens/re-covers it.
- `managers/status.lua`:
  - Status cells no longer append the color name (`Resetting (Yellow)` → **`Resetting`**), still colorized by status.
  - Removed the legend block (`* ... = ...`) — the Ctrl+C footer hint is kept.

## v0.5.0 — RSS-based health (force-close detected & reopened)

- Root cause: force-closing a floating-window clone leaves a low-RSS stub process alive (~7 MB vs ~235 MB for a running clone), so process-based detection (`isRunning`) reported it as running forever and never recovered it.
- Confirmed on-device that `dumpsys activity`/`dumpsys window` do NOT list the App Cloner floating-window clones at all (even when fully running), so UI-visibility cannot be used as a health signal here.
- `managers/apk.lua`: new `APK.getRSSinKB(pkg)` (parses resident memory from `ps -A`) and `APK.isActive(pkg)` = process exists AND RSS >= `config.minRss` (default 50 MB).
- New setting `minRss` (MB) in `config/config.lua` and `config/template.lua` — a running clone is `isActive`, a force-close stub is not.
- `managers/monitor.lua`: health (does the clone need recovery) uses `isActive` instead of `isRunning`.
- `managers/recovery.lua`: post-launch success check uses `isActive`, so recovery only completes once the clone has genuinely loaded (real memory).
- `managers/status.lua`: dashboard "running/ingame/offline" classification uses `isActive` so a force-closed clone shows `offline` instead of a stale `ingame`.
- New diagnostic tool `debug_probe.lua` (run `lua debug_probe.lua`) printing per-clone `pidof`/`ps` RSS/state plus the `isActive` decision vs the RSS threshold.
- `utils/shell.lua`: every shell command now runs under `timeout` (default 10s, configurable via `shellTimeout`) so a hung `su`/`dumpsys` call can no longer freeze the tool and stop Termux accepting input.
- `debug_probe.lua`: removed all `dumpsys` calls — on this device they never list the clones and the heavy calls hung the terminal.
- Automatic diagnostics on Menu 1 (Launch + Monitor): new `utils/probe_log.lua` writes one line per clone per monitor cycle to `launch.log` (time, status, running, isActive, pid, RSS, RSS threshold) plus recovery/relaunch event lines. No manual debug tool needed — after reproducing a bug, just read `launch.log`. New settings: `launchLogPath` (default `launch.log`), `launchLogEnabled`.

## v0.6.0 — RAM/CPU optimization

- **RSS threshold tuned for real device**: observed running clones at ~1 GB and a force-close stub at ~188 MB, so `minRss` default raised 50 → **300 MB** (kept clean separation below real running, above the stub).
- New `managers/optimizer.lua`: deprioritizes every Roblox clone with `renice 19` (lowest CPU priority) + `ionice -c 3` (idle I/O) so four floating windows stop fighting for CPU/RAM. JSON config `optimizer` (`enabled`, `renice`, `ionice`).
- Optimizer is re-applied after every launch AND every recovery/relaunch — each clone restart gets a new pid, so tuning must be re-run each time.
- Fix: `Shell.exec` returns `(ok, output)`; any `pcall(function() return Shell.exec(...) end)` previously captured the boolean as the "output string" (crashes with `attempt to index a boolean value`) and would have crashed `optimizer.lua`/`probe_log.lua` during Menu 1. All sites now capture the 3rd pcall value (`local ok, _, out = pcall(...)`).
- Removed the experimental auto-resize (2×2 grid / `windowLayout` / `debug_resize.lua` / `display.md`) — results were poor, reverted to keep only the optimizer.
- `main.lua`: new `--auto-launch` flag — `lua main.lua --headless --start-monitor --auto-launch` behaves exactly like Menu 1 (launch all clones + optimizer, then monitor) without a terminal prompt.
- New `termux-boot.sh` template + README section: auto-open Termux and run Menu 1 on every device boot via the Termux:Boot plugin (`~/termux/boot/start-rejoin.sh`).

## v0.7.0 — AutoExecute Script Manager + no-restart-if-not-logged-in

- **AutoExecute is now a Script Manager (not per-package injection)**:
  - `managers/autoexecute.lua` rebuilt: `dir` / `list` / `save` / `read` / `remove` / `deployOne` / `deployAll`. Scripts are stored GLOBALLY under `autoExecuteDeployPath` (default `data/autoexecute`) and copied as-is (root, `su`) into each application's `appAutoExecutePath/<name>.lua`. Removed the old single-file `inject`/`deployScriptForInstance` model.
  - New `core/autoexecute_cli.lua`: Script Manager submenu (List / Create / Edit / Delete / Deploy / Exit). Code is typed line-by-line and ends with a bare `END` line (which is NOT saved); after a create it asks "Mau tambah lagi? (y/n)" and loops. Deploy requires `config.appAutoExecutePath` (set it — the app's autoexecute folder; root needed to write app data).
  - `main.lua`: new menu option `6) AutoExecute Manager` (Exit moved to `7)`).
  - `config/template.lua` + `core/settings_cli.lua`: removed the obsolete global `config.autoExecute`; added/edited `appAutoExecutePath` setting.
  - `managers/recovery.lua`: removed the old `AutoExecute.inject` call during recovery.
  - `utils/file.lua`: new `File.listDir(path, ext)` used to list global scripts.

- **Do not restart a clone that has no logged-in account**:
  - New `managers/auth.lua`: `Auth.isLoggedIn(instance)` reads the clone's WebView cookie DB (default `/data/data/<pkg>/app_webview/Default/Cookies`, override per-instance via `cookiePath`) and looks for a `.ROBLOSECURITY` token (via root `grep -a`). Returns `true`/`false`/`nil`.
  - `managers/status.lua`: when a clone is low-RSS AND not logged-in (`isLoggedIn == false`) it is marked **`nologin`** instead of `freeze` — the freeze/relaunch clock never starts for it.
  - `managers/monitor.lua`: a `nologin` clone is not recovered/relaunched (low RSS is expected on the login screen). On a failed detection (`nil`) behavior falls back to the normal freeze/relaunch so nothing regresses.
  - Dashboard shows the new `NoLogin` (dim) status.

- **Tuned values**: `freezeTimeout` 60 → **300 s** (uniform for all freeze cases) in `config/config.lua`, `config/template.lua`, and the `managers/status.lua` default; `minRss` 300 → **200 MB** in `config/template.lua` (running `~1 GB` vs stub `~188 MB`).

## v0.7.1 — Ctrl+C actually stops the program

- **Root cause**: `Timer.sleep` fell back to `os.execute("sleep ...")`. POSIX `system()` **blocks SIGINT** while the child `sleep` runs, so Ctrl+C (SIGINT) never reached the Lua process while the monitor was waiting — the tool looked unstoppable (and without `lua-posix` the signal was effectively swallowed).
- `utils/timer.lua`: the no-socket fallback is now a **busy-wait** on `os.clock()` (still uses `socket.sleep` when luasocket is present). No `os.execute("sleep")` anymore → signals are never blocked, so Ctrl+C is delivered immediately.
- Result: Ctrl+C stops the monitor and exits the program right away (cleanly with `lua-posix`; via default SIGINT termination without it). Tradeoff: a little CPU spin during the waits, no extra install needed.

## v0.7.2 — Fix "not logged in" detection + never relaunch no-login clones

- `managers/auth.lua` rewritten: `Auth.isLoggedIn` no longer depends on one hardcoded cookie path (`app_webview/Default/Cookies`). It now **recursively greps the clone's data dir** (`/data/data/<pkg>`, or a per-instance `cookiePath` override) for a `.ROBLOSECURITY` token via root — this handles Lite/Floating/mod clones that store the session elsewhere. Short per-instance TTL cache (30s) avoids grepping every monitor cycle. Returns `true`/`false`/`nil`; `nil` (couldn't probe) keeps the old restart-safe behavior.
- **Hard anti-restart guard for no-login clones** (`managers/monitor.lua` + `managers/recovery.lua`): if `Auth.isLoggedIn(instance) == false` then the clone is treated as idle (low RSS is expected on the login screen) and is **never force-relaunched** — on the freeze-timeout path, on the healthy/recovery path (`checkAndRecover`), and inside `Recovery.relaunch`/`checkAndRecover` themselves. Reason is logged ("skipped restart/recovery ... not logged in"). Previously the guard only triggered when the transient status was `nologin` and detection could silently return `true`/`nil`, so a no-login clone could still be relaunched.

## v0.7.3 — Fix crash in Auth.lua (pcall + Shell.exec multi-return)

- `managers/auth.lua` used `local ok, out = pcall(function() return Shell.exec(cmd) end)` in `countToken` and `baseDirExists`. `Shell.exec` returns `(ok, output)`, so `pcall` returns `(true, ok, output)` — capturing only two values made `out` the boolean `Shell`'s ok, so `out:find(...)` crashed with "attempt to index a boolean value" right after launch (see errorlogs.md). Fixed both to capture the third value (`local ok, _, out = ...`), matching the rest of the codebase (optimizer/probe_log). Audited: no other `pcall(Shell.exec)` site is affected.

## v0.7.4 — Ctrl+C fix: require lua-posix, revert busy-wait

- **Root cause of Ctrl+C not stopping the program**: the SIGINT handler needs `lua-posix`, which was absent on the device → no handler installed → the default SIGINT action does not kill the program in Termux, so Ctrl+C did nothing. (Confirmed: device runs Lua PUC-Rio 5.4.8, so lua-posix is installable.)
- `managers/monitor.lua`: the SIGINT callback now calls `os.exit(0)` directly (plus sets `running=false`/`interrupted`), so Ctrl+C exits the program decisively the moment the signal is received. Clearer warning when lua-posix is missing.
- `utils/timer.lua`: **reverted the busy-wait fallback** back to `os.execute("sleep")`. The busy-wait pinned a core at 100% CPU (hot/unresponsive device) and did NOT fix Ctrl+C (which needs the handler, not non-blocked signals). With lua-posix the signal is only delayed by ≤ the current 0.25s chunk, so Ctrl+C still stops quickly.
- Requires on device: `pkg install lua-posix` (auto-installed by setup.sh for Lua PUC-Rio). README prerequisites updated.

## v0.7.5 — Ctrl+C via run.sh shell wrapper (no lua-posix needed)

- **`lua-posix` is NOT available in Termux's repos** for this setup (`pkg search posix` returns nothing), so the in-process SIGINT handler can't be used there. The real blocker is structural: the monitor loop (`managers/monitor.lua`) spends nearly all of each cycle inside `os.execute`/`io.popen` (`Status.check`, `apkManager.isActive`, `Auth.isLoggedIn`, `ProbeLog.scan`), and POSIX **blocks SIGINT while inside `system()`/`popen()`** — so the default SIGINT action (which works fine in most other tools, e.g. one-shot setup scripts that idle on `io.read`) is swallowed here.
- Added **`run.sh`**             : a one-file shell wrapper that launches `lua main.lua "$@"` as a child, installs a `trap INT TERM` that `kill -TERM` the child, and `wait`s on it. `kill(1)` from outside the process is unaffected by the child's internal SIGINT blocking, so Ctrl+C stops the engine reliably **in the same terminal** — no extra session needed. Usage: `sh run.sh [flags...]`.
- `managers/monitor.lua`: `installSignalHandler` warning updated — instead of telling the user to `pkg install lua-posix` (unavailable), it now points to `sh run.sh`. The handler itself is kept (used automatically when lua-posix exists on another device).
- README: prerequisites + quickstart + headless sections updated to run via `run.sh`; lua-posix demoted to optional. `termux-boot.sh` unchanged (boot service has no interactive terminal, so Ctrl+C is not relevant there).
- README: added "Matikan auto-boot" section (`rm ~/.termux/boot/start-rejoin.sh`) under the auto-start docs.

## v0.7.6 — AutoExecute Deploy fix: Delta path, mkdir -p, quoting

- **Root cause of AutoExecute Deploy not working**: `appAutoExecutePath` was commented out in `config/config.lua` → deploy always failed with "appAutoExecutePath is empty". Additionally, the destination path was not per-instance but the actual Delta mod autoexecute folder lives at `/sdcard/Delta/Autoexecute` (internal storage, shared across all instances) — not inside `/data/data/<pkg>/` as assumed.
- `config/config.lua` + `config/template.lua`: `appAutoExecutePath` set to `/sdcard/Delta/Autoexecute` (Delta mod default). Comment updated to reflect internal storage path.
- `managers/autoexecute.lua`: rewrote `suCopyIntoApp` — removed manual `su -c` wrapping (caused double-wrapping + quote-breaking when `Shell.exec` also wraps with `su -c`); added `mkdir -p` before `cp` to ensure the destination folder exists; single `cp` attempt with Shell.exec handling root wrapping automatically. Updated module header and `appDestBase` comments.
- `core/settings_cli.lua`: Settings menu item 7 prompt updated to show Delta path example (`/sdcard/Delta/Autoexecute`).

## v0.7.7 — AutoExecute simplified: manage /sdcard/Delta/Autoexecute directly

- **Real root-cause of Deploy still failing after v0.7.6**: the source path was **relative** (`data/autoexecute/<name>.lua`). When executed through `su -c`, the working directory is `/` (root's), not `$HOME/rejoin`, so the relative path wasn't found → `cp` failed silently → `copy_failed`; the "Deploy failed: table: 0x..." display bug (CLI printed the result table instead of its `errors` contents) masked the real reason.
- **UI simplified (`core/autoexecute_cli.lua`)**: entering menu 6 now shows the current contents of the app autoexecute folder at the top, with a simple menu below: `1) Add / 2) Edit / 3) Delete / 4) Exit`. List refreshes after each action. Remove the `deployFlow` (and its `table: 0x` bug) entirely — no deploy step anymore.
- **`managers/autoexecute.lua` rewritten** to manage the app folder directly: `dir()` returns the absolute `appAutoExecutePath`; `save()` writes straight into the folder (mkdir -p + io.open, no `cp`/`su` → immune to the relative-path-in-su bug); `list/read/remove` target the same folder. Removed obsolete `appDestBase`, `suCopyIntoApp`, `deployOne`, `deployAll` (and the global staging model).
- **Cleanup of unused staging model**: removed `autoExecuteDeployPath` from config/template/settings (Settings menu renumbered 8–15 → 7–14); removed `config/sample_AutoExecute.lua`; setup.sh no longer creates `data/autoexecute` or seeds the sample; setup help updated to `sh run.sh` and notes Delta folder + lua-posix-optional.
- Config default: `appAutoExecutePath = "/sdcard/Delta/Autoexecute"` (shared folder, internal storage, no root needed).
- README AutoExecute sections and file tree updated.

## v0.7.8 — AutoExecute menu: remove su/popen from menu path, anti-spin input

- **Root cause of "can't type anything after choosing menu 6" + messy display**: entering menu 6 ran `resolveDir()` → `Shell.exec("mkdir -p ...")` (wrapped as `su -c` via `io.popen`) **on every loop iteration, before the menu choice was read**. After that shell call the terminal's stdin could return EOF (`io.read()` → `nil`), so every choice read came back empty → the menu loop re-printed the banner+list+options in a tight spin (messy screen, keystrokes got swallowed).
- `managers/autoexecute.lua`: removed `resolveDir()` and its `Shell.exec(mkdir -p)` call entirely — **no `su`/shell anywhere in this module** now. `list()` is a pure read (`File.listDir`); the folder is created lazily on `save()` via `File.write` (os.execute/lfs mkdir, no su, no popen, and only during Add/Edit). Removed the `require("utils.shell")` usage; header comment updated.
- `core/autoexecute_cli.lua`: banner now shows the actual folder path (`AutoExecute Manager — folder: <appAutoExecutePath>`); menu choice read uses `nil`(=EOF/Ctrl+D) as **clean exit** (`break`) instead of looping; list/error output made tolerant (empty folder → hint to Add). Add/Edit/Delete flows unchanged.

## v0.7.9 — AutoExecute Edit/Delete memakai nomor, bukan nama

- Menampilkan isi folder diseragamkan jadi list **bernomor** (` 1)`, ` 2)`, ... di kedua printList menu dan saat Edit/Delete).
- Helper baru `pickFromList(promptLabel)`: list ulang bernomor, baca nomor, validasi 1..N → balikin entry terpilih; nomor invalid → pesan jelas; EOF/batal → balik tanpa aksi.
- Edit & Delete: ganti prompt ketik nama → **pilih nomor urut** dari list (nama `*.lua` dibersihkan saat tampil). Alur Add tetap minta nama (untuk script baru).

## v0.7.10 — Username di dashboard monitoring

- **Username Roblox per clone di dashboard**: `Status.printSummary` kini menampilkan `package (username)` (mis. `com.apengjers.v3 (apengjers)`), kolom Instance dilebarkan (LCOL 23 → 33) agar muat; ketika username tidak diketahui, cukup menampilkan `package`.
- **Modul baru `managers/username.lua`** (pola `auth.lua`):
  - `get(instance)` menyelesaikan username via **cookie `.ROBLOSECURITY`** → API Roblox (`https://users.roblox.com/v1/users/authenticated`), karena token cookie TIDAK mengandung username — hanya bisa di-resolve via API. Di-cache per instance (TTL 600s; hasil gagal 60s anti-hammer).
  - Fallback **scan lokal** (`shared_prefs`/`files` XML/JSON/TXT/LOG untuk key `username|userName|displayName|accountName|playerName`) jika API gagal/offline; override manual lewat field per-instance `usernamePath` (baris pertama file = username).
  - **Bukti scan** ditulis ke `data/username_scan.log` (token length, hasil API, hasil lokal) per sesi agar mudah dituning bila ada clone kosong.
- `managers/monitor.lua`: `Username.reset()` saat monitor start + `Username.prefetch(instances)` sekali sebelum loop utama (dashboard pertama sudah menampilkan username, tanpa block di tiap draw).
- `config/template.lua`: contoh instance kini punya field opsional `usernamePath = ""` + komentar. README fitur / monitoring / file tree diperbarui.

## Upcoming

- Shell Wrapper
- Android Wrapper
- Config System
- Setup Wizard
