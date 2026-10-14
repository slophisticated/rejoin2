#!/data/data/com.termux/files/usr/bin/sh
# Device tweaks for running many Roblox clones (needs root).
#
# Usage:   sh ~/rejoin/device_setup.sh          apply
#          sh ~/rejoin/device_setup.sh --undo   back to Android defaults
#
# Applies (all persist across reboots):
#   - animations off (window / transition / animator scale = 0)
#   - Developer options: force allow apps on external, force activities to be
#     resizable, enable freeform windows, enable non-resizable in multi-window
#   - Smallest width SMALLEST_WIDTH dp (default 600), via `wm density`
# Freeform / resizable take effect after a reboot.
#
# Prints one "[OK]" / "[!!]" line per item. Never exits with an error, so the
# installer can carry on.

SW=${SMALLEST_WIDTH:-600}
MODE=apply
[ "$1" = "--undo" ] && MODE=undo

ok()   { printf '  [OK] %s\n' "$*"; }
warn() { printf '  [!!] %s\n' "$*"; }

root() { su -c "$1" </dev/null 2>/dev/null; }

if ! root id | grep -q 'uid=0'; then
    warn "root belum aktif; tweak device dilewati (izinkan Termux di Magisk/KernelSU)"
    exit 0
fi

# settings put global KEY VALUE, then read it back.
set_global() {
    key=$1; want=$2; label=$3
    have=$(root "settings get global $key" | tr -d '\r')
    if [ "$have" = "$want" ]; then
        ok "$label (sudah)"
        return
    fi
    root "settings put global $key $want" >/dev/null
    have=$(root "settings get global $key" | tr -d '\r')
    if [ "$have" = "$want" ]; then
        ok "$label"
    else
        warn "$label gagal di-set (sekarang: ${have:-kosong})"
    fi
}

# Background permission for the Termux apps: battery-optimization whitelist (what the
# "Let app always run in background?" dialog asks for, so it no longer shows up) plus
# the run-in-background app ops. Apps that are not installed are skipped.
BG_PKGS="com.termux com.termux.boot com.termux.api"
PKGS_INSTALLED=$(root "pm list packages")
installed() { printf '%s\n' "$PKGS_INSTALLED" | grep -qx "package:$1"; }
whitelisted() { root "dumpsys deviceidle whitelist" | grep -q ",$1,"; }
background() {
    for p in $BG_PKGS; do
        installed "$p" || continue
        if [ "$1" = off ]; then
            root "dumpsys deviceidle whitelist -$p" >/dev/null
            root "cmd appops set $p RUN_IN_BACKGROUND default" >/dev/null
            root "cmd appops set $p RUN_ANY_IN_BACKGROUND default" >/dev/null
            ok "$p: izin background dikembalikan"
            continue
        fi
        root "cmd appops set $p RUN_IN_BACKGROUND allow" >/dev/null
        root "cmd appops set $p RUN_ANY_IN_BACKGROUND allow" >/dev/null
        if whitelisted "$p"; then
            ok "$p boleh jalan di background (sudah)"
            continue
        fi
        root "dumpsys deviceidle whitelist +$p" >/dev/null
        if whitelisted "$p"; then
            ok "$p boleh jalan di background"
        else
            warn "$p gagal dikecualikan dari optimasi baterai"
        fi
    done
}

if [ "$MODE" = undo ]; then
    background off
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do
        set_global "$k" 1 "animasi $k = 1"
    done
    for k in force_allow_on_external force_resizable_activities enable_freeform_support \
             enable_non_resizable_multi_window; do
        set_global "$k" 0 "$k = 0"
    done
    root "wm density reset" >/dev/null && ok "density dikembalikan ke bawaan"
    echo "  (reboot supaya semua perubahan aktif)"
    exit 0
fi

# 1. Animations -----------------------------------------------------------------
set_global window_animation_scale 0 "animasi jendela mati"
set_global transition_animation_scale 0 "animasi transisi mati"
set_global animator_duration_scale 0 "animasi durasi mati"

# 2. Developer options --------------------------------------------------------------
set_global development_settings_enabled 1 "Developer options aktif"
set_global force_allow_on_external 1 "Force allow apps on external"
set_global force_resizable_activities 1 "Force activities to be resizable"
set_global enable_freeform_support 1 "Enable freeform windows"
set_global enable_non_resizable_multi_window 1 "Enable non-resizable in multi-window"

# 3. Background permission ---------------------------------------------------------
background on

# 4. Smallest width -------------------------------------------------------------------
SIZE=$(root "wm size")
DIM=$(printf '%s\n' "$SIZE" | grep -i 'override' | grep -oE '[0-9]+x[0-9]+' | head -1)
[ -z "$DIM" ] && DIM=$(printf '%s\n' "$SIZE" | grep -oE '[0-9]+x[0-9]+' | head -1)
W=${DIM%x*}; H=${DIM#*x}
if [ -z "$DIM" ] || [ -z "$W" ] || [ -z "$H" ]; then
    warn "ukuran layar tidak terbaca; smallest width dilewati"
else
    SHORT=$W; [ "$H" -lt "$W" ] && SHORT=$H
    WANT=$(( (SHORT * 160 + SW / 2) / SW ))
    DENS=$(root "wm density")
    CUR=$(printf '%s\n' "$DENS" | grep -i 'override' | grep -oE '[0-9]+' | tail -1)
    [ -z "$CUR" ] && CUR=$(printf '%s\n' "$DENS" | grep -oE '[0-9]+' | tail -1)
    if [ "$CUR" = "$WANT" ]; then
        ok "Smallest width ${SW}dp (density $WANT, sudah)"
    else
        root "wm density $WANT" >/dev/null
        NEW=$(root "wm density" | grep -oE '[0-9]+' | tail -1)
        if [ "$NEW" = "$WANT" ]; then
            ok "Smallest width ${SW}dp (density $CUR -> $WANT)"
        else
            warn "density gagal diubah ke $WANT (sekarang: ${NEW:-?})"
        fi
    fi
fi

echo "  (freeform & resizable aktif setelah reboot)"
exit 0
