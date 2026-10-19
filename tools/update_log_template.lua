-- Template update log.
--
-- Otomatis: copy file ini ke tools/update_logs/<versi>.lua, isi, lalu push ke main.
-- GitHub Actions langsung mengirimnya ke Discord (secret UPDATE_LOG_WEBHOOK). Bisa juga
-- pakai satu file yang sama terus: ganti `version` = dikirim lagi; edit tanpa ganti
-- version (mis. typo) = tidak dikirim ulang.
--
-- Manual:
--   lua tools/update_log.lua <file>             (preview)
--   lua tools/update_log.lua <file> --send URL  (post to Discord)
--
-- Sent as a Discord components message through the webhook: one box with the title,
-- version and notes, and one box with the sections.
-- Empty sections ({}) are left out automatically.
-- mention: plain text, or a real ping: "<@&ROLE_ID>" (Discord: right-click the
-- role > Copy Role ID, with Developer Mode on).

return {
    title   = "Rejoin Update Logs",
    mention = "",  -- kosong = tanpa mention; ping role: "<@&ROLE_ID>"
    version = "v0.0.0.1",
    color   = 0x5865F2, -- color of the bar on the left of the box

    notes = {
        "Found any bugs or issues? Feel free to report them to the developers!",
        "Got ideas or suggestions for new scripts? We'd love to hear them!",
    },

    added = {
        "Hospital",
        "Auto Treat",
        "Added Auto Treat Patients — check-in + diagnosa (DNA + Analyze + Process) + cure, satu obat per penyakit",
        "Added Auto Reject Skinwalkers — pasien palsu ditolak lewat tutup jendela resepsionis, tanpa kena strike",
    },

    improved = {
        "Improve Auto Drive (Sekarang pas mati langsung naik motor)",
    },

    fixed = {
        "Fix Auto Parry (Working)",
        "Fix Invisible (New Methode)",
    },

    deleted = {
        "Remove Spear Fishing (Wait For New Update :v)",
    },
}
