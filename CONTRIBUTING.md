# Kontribusi ke Rejoin

Makasih udah mau bantu! Rejoin dilisensikan **GPL-3.0-or-later** ([LICENSE](LICENSE)).
Dengan ngirim pull request, kamu setuju kontribusimu dirilis dengan lisensi yang sama.

## Sebelum mulai

- Baca **[AGENTS.md](AGENTS.md)**: isinya konteks project, peta kode, dan aturan teknis
  yang masing-masing lahir dari bug nyata (mis. clone belum login **ga boleh**
  di-force-stop, perintah majemuk lewat `Shell.exec` wajib dibungkus `sh -c`).
- Device target: Termux di cloud phone Android 10 yang sudah di-root (Magisk), Lua 5.3.
  Bot Discord ada di `bot/` (Node.js 24).

## Cara tes

Ga ada device di CI, jadi tes pakai simulasi:

```sh
luac -p <file.lua>          # cek syntax tiap file Lua yang diubah
sh -n <file.sh>             # cek syntax shell script
cd bot && npm ci && npm test   # tes bot (node:test)
```

Buat logika Lua, bikin harness kecil: stub modul pakai `package.preload[...]`, stub
`su` / `curl` / `sqlite3` di `PATH`, dan HOME palsu di folder sementara. Kalau sempat
tes di device, tulis di PR apa yang dites dan potongan `data/rejoin.log`-nya.

## Gaya

- Komentar kode: **Inggris**, ikutin gaya file di sekitarnya.
- Teks menu dan pesan ke user: **Bahasa Indonesia**.
- Commit message: Inggris, singkat, jelasin **kenapa**.
- Tiap fitur: update `README.md`, `setup.md`, dan `docs/changelog.md` (entri baru di atas,
  bagian "Unreleased").
- Config user ga boleh ketimpa pas update; default baru lewat migrasi `update.sh`.

## Jangan

- Commit secret: URL webhook, secret bot, token `.ROBLOSECURITY`, token GitHub.
  Semua itu juga ga boleh masuk log.
- Fitur bypass key system Delta (auto get key lewat situs bypass) — ditolak.
- Nulis langsung ke folder Autoexecute Delta: script cuma lewat folder Scripts
  (`AutoExecute.autoAdd`).
