# Research: Delta (apengjers) "Get Key" / keysystem

Status: investigasi selesai (focus/read-only). Dipakai sebagai fondasi fitur **Auto Get Key** ke depan.

## Fakta inti

- Tombol "Get Key" / "Receive Key" di Delta apengjers membuka browser ke:

  ```
  https://auth.platorelay.com/a?d=<TOKEN>
  ```

- **Domain keysystem**: `auth.platorelay.com` (bukan deltaexecutor / linkvertise / work.ink).
  - DNS: `104.21.58.119` dan `172.67.159.107` (Cloudflare).
  - `GET/HEAD https://auth.platorelay.com/a` → `HTTP 200`, `Content-Type: text/html` — **tanpa redirect HTTP**; alur checkpoint (countdown, task) berjalan via JS client-side di halaman itu sendiri.
- **`d=` = token per-device, dibuat saat runtime**. URL beda di tiap tekanan tombol → tidak pernah muncul sebagai string statis di APK.

## Kenapa tidak ketemu lewat statis

- Scan penuh `DeltaNonLiteFloatingA10 (1).apk` (194,678,181 B): 5 dex, `libroblox.so` (109 MB, engine Roblox murni), semua .so (termasuk `libtrampoline.so` = crashpad, bukan injector), `assets/` (konten Roblox stock), string pool `resources.arsc` + varian UTF-16 — tidak ada URL keysystem.
- Payload executor (menu + logika key) di-unpack saat runtime dari `assets/natives_sec_blob.dat` (563,952 B).
  - Head `144d6b0f8ebb5234...`, high-entropy.
  - Bukan zlib (magic 78 9C), bukan XOR-zlib single-byte, bukan base64-zlib run, bukan UTF-16 `https`.
  - sha256 **identik di 8 varian proyek** (Lite/NonLite + Floating, 4 salinan tiap) → executor & keysystem satu family.
- `DeltaLiteA12 (1|2).apk` tidak punya blob (build berbeda, urutan analisis terpisah).

## Tangkapan nyata

- `adb shell dumpsys activity activities` pada browser yang terbuka setelah tekan tombol menangkap:
  `Intent { act=android.intent.action.VIEW dat=https://auth.platorelay.com/a?d=... cmp=com.android.chrome/...ChromeTabbedActivity }`.
- Metode pasif ini (= rekam intent browser saja) adalah rute tercepat; user hanya perlu tekan tombol seperti biasa.

## Catatan untuk Auto Get Key

Belum diekskusi; arah yang mungkin (belum diverifikasi):

1. **Intent relay / otomasi browser**: tangkap URL via ACTION_VIEW, buka halaman, jalankan JS checkpoint countdown lalu ekstrak key; key di-paste balik ke app (perlu BACA input field di executor). Key umum 24 jam & bound device.
2. **Unpack blob** `natives_sec_blob.dat` dulu (RE nyata: perlu cari kunci/algoritma di native loader) supaya simpanan config/URL key bisa dibaca tanpa buka app.
3. **Sesuaikan per build**: keluarga apengjers ini shared blob → URL sama; build Delta resmi/bermerek lain bisa punya domain keysystem sendiri.
4. Verifikasi sesi/device: key di-generate oleh server `auth.platorelay.com` (Cloudflare) → otomasi harus meniru fingerprint browser Touch (dan lulus checkpoint JS), bukan sekadar HTTP GET.