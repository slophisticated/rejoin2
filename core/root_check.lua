-- Is root granted to Termux? Rejoin needs it for nearly everything (force-stop,
-- cookies, window layout, device settings), so main.lua stops early without it.

local RootCheck = {}

function RootCheck.ok()
    -- stdin /dev/null: su must never take the terminal (keeps Ctrl+C working).
    -- timeout: a root manager waiting on its prompt must not hang the start.
    local cmd = "if command -v timeout >/dev/null 2>&1; then timeout 15 su -c id; else su -c id; fi"
    local p = io.popen("sh -c '" .. cmd .. "' </dev/null 2>/dev/null")
    if not p then return false end
    local out = p:read("*a") or ""
    p:close()
    return out:find("uid=0", 1, true) ~= nil
end

RootCheck.MESSAGE = table.concat({
    "[XX] Root belum aktif. Rejoin butuh root (Magisk / KernelSU).",
    "     Buka Magisk -> Superuser -> izinkan Termux (Grant), lalu jalankan lagi.",
    "     Cek: su -c id  (harus muncul uid=0)",
}, "\n")

return RootCheck
