-- Template update log. Copy this file for every new version, fill it in, then:
--   lua tools/update_log.lua tools/update_log_template.lua            (preview)
--   lua tools/update_log.lua tools/update_log_template.lua --send URL (post to Discord)
--
-- Sent as a Discord components message (a box with a colored bar) through the webhook.
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
