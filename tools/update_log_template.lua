-- Template update log. Copy this file for every new version, fill it in, then:
--   lua tools/update_log.lua tools/update_log_template.lua            (show the text)
--   lua tools/update_log.lua tools/update_log_template.lua --send URL (post to Discord)
--
-- Empty sections ({}) are left out of the text automatically.
-- mention: plain text, or a real ping: "<@&ROLE_ID>" (Discord: right-click the
-- role > Copy Role ID, with Developer Mode on).

return {
    title   = "Atomicals Script Update Logs",
    mention = "@Script Buyer",
    place   = "Animal Hospital",
    version = "v0.0.0.1",

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
