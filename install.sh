#!/data/data/com.termux/files/usr/bin/sh
# Rejoin installer / re-installer for Termux.
#
#   curl -sL https://raw.githubusercontent.com/slophisticated/rejoin2/main/install.sh | sh
#
# Safe to run again on a device that already has rejoin: your config/config.lua and
# logs are kept. What it does:
#   1. installs/updates the Termux packages (lua53 sqlite curl git)
#   2. makes `lua` available
#   3. checks root
#   4. downloads rejoin to ~/rejoin (fresh copy, settings kept)
#   5. checks that the clones in config/config.lua are installed
#   6. installs the boot script (auto-update + start on every boot)
#   7. checks/activates the Termux:Boot app
#
# When piped into sh, stdin is this script itself, so every command below reads
# from /dev/null instead.

REPO_URL=${REPO_URL:-https://github.com/slophisticated/rejoin2}
BRANCH=${REJOIN_BRANCH:-main}
DIR=${REJOIN_DIR:-$HOME/rejoin}
BACKUP="$HOME/.rejoin-backup"
PROBLEMS=0

ok()   { printf '  [OK] %s\n' "$*"; }
warn() { printf '  [!!] %s\n' "$*"; PROBLEMS=$((PROBLEMS + 1)); }
die()  { printf '  [XX] %s\n' "$*"; printf '\nInstall berhenti. Perbaiki yang di atas lalu jalankan ulang.\n'; exit 1; }
step() { printf '\n== %s\n' "$*"; }

if [ -z "$PREFIX" ] || [ ! -d "$PREFIX" ]; then
    echo "Jalankan installer ini di dalam Termux."
    exit 1
fi

# ---------------------------------------------------------------------------
step "1/7 Paket Termux"
export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
# apt instead of pkg: pkg itself needs a working curl, which a half-upgraded
# Termux may not have (libcurl/openssl mismatch).
if apt-get update </dev/null >/dev/null 2>&1; then
    ok "daftar paket ter-update"
else
    die "apt update gagal. Jalankan: termux-change-repo -> Mirror group -> Mirrors in Asia, lalu ulangi."
fi
echo "  upgrade paket (bisa beberapa menit)..."
# shellcheck disable=SC2086
apt-get $APT_OPTS full-upgrade </dev/null >/dev/null 2>&1 || warn "upgrade paket ada yang gagal (lanjut)"
# shellcheck disable=SC2086
if apt-get $APT_OPTS install lua53 sqlite curl git </dev/null >/dev/null 2>&1; then
    ok "lua53 sqlite curl git terpasang"
else
    die "gagal install lua53/sqlite/curl/git. Coba: termux-change-repo (Mirrors in Asia), lalu ulangi."
fi

# ---------------------------------------------------------------------------
step "2/7 Lua"
if ! command -v lua >/dev/null 2>&1 && [ -x "$PREFIX/bin/lua5.3" ]; then
    ln -sf "$PREFIX/bin/lua5.3" "$PREFIX/bin/lua"
fi
if command -v lua >/dev/null 2>&1; then
    ok "$(lua -v </dev/null 2>&1 | head -1)"
else
    die "perintah lua tidak ada"
fi

# ---------------------------------------------------------------------------
step "3/7 Root"
if su -c id </dev/null 2>/dev/null | grep -q 'uid=0'; then
    ok "root aktif"
else
    warn "root belum aktif. Buka Magisk/KernelSU -> Superuser -> izinkan Termux, lalu ulangi."
fi

# ---------------------------------------------------------------------------
step "4/7 Download rejoin ke $DIR"
mkdir -p "$BACKUP"
OLD=""
if [ -e "$DIR" ]; then
    # Stop an engine started by a previous install/boot before replacing its files.
    if [ -f "$DIR/data/monitor.pid" ]; then
        kill "$(cat "$DIR/data/monitor.pid")" 2>/dev/null && ok "engine lama dihentikan"
    fi
    [ -f "$DIR/config/config.lua" ] && cp -f "$DIR/config/config.lua" "$BACKUP/config.lua"
    [ -d "$DIR/data" ] && rm -rf "$BACKUP/data" && cp -R "$DIR/data" "$BACKUP/data"
    OLD="$DIR.old"
    rm -rf "$OLD"
    mv "$DIR" "$OLD" || die "tidak bisa memindahkan folder lama $DIR"
fi
if git clone -q --depth 1 -b "$BRANCH" "$REPO_URL" "$DIR" </dev/null >/dev/null 2>&1; then
    ok "rejoin $(git -C "$DIR" rev-parse --short HEAD 2>/dev/null) terunduh"
    if [ -n "$OLD" ]; then
        [ -f "$BACKUP/config.lua" ] && cp -f "$BACKUP/config.lua" "$DIR/config/config.lua" && ok "config lama dipakai lagi"
        [ -d "$BACKUP/data" ] && cp -R "$BACKUP/data/." "$DIR/data/" 2>/dev/null
        rm -rf "$OLD"
    fi
else
    [ -n "$OLD" ] && mv "$OLD" "$DIR"
    die "git clone gagal (internet / GitHub). Folder lama dikembalikan."
fi
chmod +x "$DIR"/*.sh 2>/dev/null

# ---------------------------------------------------------------------------
step "5/7 Cek clone di config"
PKGS=$(cd "$DIR" && lua -e '
    local ok, c = pcall(dofile, "config/config.lua")
    if ok and type(c) == "table" then
        for _, i in ipairs(c.instances or {}) do
            if type(i) == "table" and i.package then print(i.package) end
        end
    end' </dev/null 2>/dev/null)
INSTALLED=$(su -c "pm list packages" </dev/null 2>/dev/null)
if [ -z "$PKGS" ]; then
    warn "tidak ada clone di config. Atur lewat: cd ~/rejoin && lua main.lua -> 2) Instances Manager"
else
    for p in $PKGS; do
        if printf '%s\n' "$INSTALLED" | grep -qx "package:$p"; then
            ok "$p"
        else
            warn "$p TIDAK terpasang di device ini -> ubah lewat menu 2) Instances Manager"
        fi
    done
fi

# ---------------------------------------------------------------------------
step "6/7 Script boot"
mkdir -p "$HOME/.termux/boot"
BOOT_SCRIPT="$HOME/.termux/boot/start-rejoin.sh"
cat > "$BOOT_SCRIPT" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
# Generated by rejoin install.sh. On every boot: update rejoin from GitHub, then
# start it (see $DIR/termux-boot.sh). Turn auto-update off with:
#   touch $DIR/data/no-auto-update
REJOIN_DIR="$DIR"
export REJOIN_DIR
if [ -f "\$REJOIN_DIR/update.sh" ] && [ ! -f "\$REJOIN_DIR/data/no-auto-update" ]; then
    sh "\$REJOIN_DIR/update.sh" --boot </dev/null >/dev/null 2>&1
fi
exec sh "\$REJOIN_DIR/termux-boot.sh"
EOF
chmod +x "$BOOT_SCRIPT"
ok "terpasang: $BOOT_SCRIPT (auto-update tiap boot)"

# ---------------------------------------------------------------------------
step "7/7 Termux:Boot"
if printf '%s\n' "$INSTALLED" | grep -qx "package:com.termux.boot"; then
    state=$(su -c "dumpsys package com.termux.boot" </dev/null 2>/dev/null | grep -o 'stopped=[a-z]*' | head -1)
    if [ "$state" = "stopped=true" ]; then
        su -c "am start -n com.termux.boot/.BootActivity" </dev/null >/dev/null 2>&1
        sleep 3
        state=$(su -c "dumpsys package com.termux.boot" </dev/null 2>/dev/null | grep -o 'stopped=[a-z]*' | head -1)
    fi
    if [ "$state" = "stopped=false" ]; then
        ok "Termux:Boot aktif (kembali ke Termux kalau layar Termux:Boot terbuka)"
    else
        warn "Termux:Boot belum aktif ($state). Tap ikon Termux:Boot sekali, lalu jalankan installer lagi."
    fi
else
    warn "aplikasi Termux:Boot belum terpasang. Install APK-nya (sumber sama dengan Termux), tap ikonnya sekali, lalu jalankan installer lagi."
fi

# ---------------------------------------------------------------------------
echo
if [ "$PROBLEMS" -eq 0 ]; then
    echo "SELESAI tanpa masalah. Reboot cloud phone: rejoin update + jalan sendiri."
else
    echo "SELESAI dengan $PROBLEMS peringatan [!!] di atas. Beresin dulu, lalu jalankan ulang installer."
fi
echo "Jalankan manual: cd ~/rejoin && lua main.lua   |   Update manual: sh ~/rejoin/update.sh"
