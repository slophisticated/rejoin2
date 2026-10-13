#!/data/data/com.termux/files/usr/bin/sh
# Update rejoin to the latest version on GitHub, keeping your settings.
#
# Usage:   sh ~/rejoin/update.sh            (manual)
#          sh ~/rejoin/update.sh --boot     (from the boot script; logs to data/boot.log)
#
# config/config.lua and data/rejoin.log are kept as they are; everything else is
# replaced with the version on GitHub. Never fails hard: if GitHub can't be reached
# the current version simply keeps running.

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 0
BRANCH=${REJOIN_BRANCH:-main}
BOOT=0
[ "$1" = "--boot" ] && BOOT=1

say() {
    if [ "$BOOT" = 1 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] update: $*" >> "$DIR/data/boot.log"
    else
        echo "$*"
    fi
}

# One-time config changes for new defaults. Each runs once per device (marker in
# data/, which updates keep), so a setting changed by the user afterwards is never
# overridden. Runs on every exit path: also when already up to date or offline.
migrate() {
    marker="data/.migrated-$1"; shift
    [ -f "$marker" ] && return 0
    command -v lua >/dev/null 2>&1 || return 0
    out=$(REJOIN_WRAPPER=1 lua main.lua "$@" </dev/null 2>/dev/null | tail -1)
    case "$out" in
        OK:*) : > "$marker"; say "migrasi: ${out#OK: }" ;;
        *)    say "migrasi $1 belum berhasil (${out:-tidak ada output}); dicoba lagi lain kali" ;;
    esac
}
run_migrations() {
    migrate window-layout-on --enable-window-layout
}

cd "$DIR" || exit 0
mkdir -p data 2>/dev/null
if ! command -v git >/dev/null 2>&1; then
    say "git tidak ada (pkg install git); update dilewati"
    exit 0
fi
if [ ! -d .git ]; then
    say "folder ini bukan hasil git clone; jalankan install.sh"
    exit 0
fi

before=$(git rev-parse --short HEAD 2>/dev/null)

# Right after boot the network may still be coming up: retry a few times.
tries=1
while :; do
    if timeout 40 git fetch -q origin "$BRANCH" </dev/null >/dev/null 2>&1; then
        break
    fi
    if [ "$tries" -ge 3 ]; then
        say "GitHub tidak bisa dihubungi; tetap pakai versi $before"
        run_migrations
        exit 0
    fi
    tries=$((tries + 1))
    sleep 5
done

after=$(git rev-parse --short FETCH_HEAD 2>/dev/null)
if [ -z "$after" ] || [ "$before" = "$after" ]; then
    say "sudah versi terbaru ($before)"
    run_migrations
    exit 0
fi

# Keep the user's settings and log across the reset.
BACKUP="$HOME/.rejoin-backup"
mkdir -p "$BACKUP"
cp -f config/config.lua "$BACKUP/config.lua" 2>/dev/null
cp -f data/rejoin.log "$BACKUP/rejoin.log" 2>/dev/null

if git reset -q --hard FETCH_HEAD </dev/null >/dev/null 2>&1; then
    [ -f "$BACKUP/config.lua" ] && cp -f "$BACKUP/config.lua" config/config.lua
    [ -f "$BACKUP/rejoin.log" ] && cp -f "$BACKUP/rejoin.log" data/rejoin.log
    say "update $before -> $after (config tetap)"
else
    say "update gagal (git reset); tetap pakai versi $before"
fi

run_migrations
exit 0
