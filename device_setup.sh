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
#   - Smallest width SMALLEST_WIDTH dp (default 600), via `wm density`. A value given
#     with SMALLEST_WIDTH=... is remembered in data/smallest_width, so reinstalls and
#     updates keep it; --undo forgets it.
#   - Quiet / lighter device: every volume (music, ring, notification, system, alarm)
#     at 0, touch / lock screen / dial / charging sounds and haptics off, heads-up
#     notifications off (no pop-ups over the clone windows), auto-rotate off, location
#     and background Wi-Fi / Bluetooth scanning off. --undo puts these settings back to
#     the Android defaults (settings delete) and volumes at half.
# Freeform / resizable take effect after a reboot.
#
# Prints one "[OK]" / "[!!]" line per item. Never exits with an error, so the
# installer can carry on.

MODE=apply
[ "$1" = "--undo" ] && MODE=undo

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SW_FILE="$DIR/data/smallest_width"
valid_sw() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 320 ] && [ "$1" -le 1600 ]; }
SW=600
if [ -n "$SMALLEST_WIDTH" ] && valid_sw "$SMALLEST_WIDTH"; then
    SW=$SMALLEST_WIDTH
    [ "$MODE" = apply ] && mkdir -p "$DIR/data" && echo "$SW" > "$SW_FILE"
elif [ -f "$SW_FILE" ] && valid_sw "$(cat "$SW_FILE")"; then
    SW=$(cat "$SW_FILE")
fi

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

# settings put NAMESPACE KEY VALUE, then read it back (set_global for system/secure).
set_ns() {
    ns=$1; key=$2; want=$3; label=$4
    have=$(root "settings get $ns $key" | tr -d '\r')
    if [ "$have" = "$want" ]; then ok "$label (sudah)"; return; fi
    root "settings put $ns $key $want" >/dev/null
    have=$(root "settings get $ns $key" | tr -d '\r')
    if [ "$have" = "$want" ]; then ok "$label"; else warn "$label gagal di-set (sekarang: ${have:-kosong})"; fi
}

# Quiet-mode settings: "namespace key value-when-applied label", one per line.
QUIET_SETTINGS="system sound_effects_enabled 0 suara sentuh mati
system haptic_feedback_enabled 0 getar sentuh mati
system lockscreen_sounds_enabled 0 suara kunci layar mati
system dtmf_tone 0 nada tombol dial mati
global charging_sounds_enabled 0 suara charging mati
global heads_up_notifications_enabled 0 notif pop-up (heads-up) mati
system accelerometer_rotation 0 auto-rotate mati
secure location_mode 0 lokasi mati
global wifi_scan_always_enabled 0 scan Wi-Fi di background mati
global ble_scan_always_enabled 0 scan Bluetooth di background mati"

# Volume of one stream through the `media` tool (cmd media_session on builds without it).
# Streams: 1 system, 2 ring, 3 music (Roblox), 4 alarm, 5 notification.
volume_tool() {
    if root "command -v media" | grep -q media; then echo media; else echo "cmd media_session"; fi
}
volume() {
    stream=$1; want=$2; label=$3
    tool=${TOOL:-$(volume_tool)}
    # "volume is 7 in range [0..15]"
    get() { root "$tool volume --stream $stream --get" | grep -oE 'volume is [0-9]+' | grep -oE '[0-9]+$'; }
    if [ "$want" = half ]; then
        max=$(root "$tool volume --stream $stream --get" | grep -oE '\.\.[0-9]+' | grep -oE '[0-9]+$')
        want=$(( ${max:-10} / 2 ))
    fi
    have=$(get)
    if [ "$have" = "$want" ]; then ok "$label (sudah)"; return; fi
    root "$tool volume --stream $stream --set $want" >/dev/null
    have=$(get)
    if [ "$have" = "$want" ]; then ok "$label"; else warn "$label gagal (sekarang: ${have:-tidak terbaca})"; fi
}
VOLUMES="3 volume media/game
2 volume dering
5 volume notifikasi
1 volume sistem
4 volume alarm"

quiet() {
    TOOL=$(volume_tool)
    printf '%s\n' "$VOLUMES" | while read -r stream label; do
        if [ "$1" = off ]; then volume "$stream" half "$label setengah"; else volume "$stream" 0 "Suara: $label 0"; fi
    done
    printf '%s\n' "$QUIET_SETTINGS" | while read -r ns key value label; do
        if [ "$1" = off ]; then
            root "settings delete $ns $key" >/dev/null
            ok "$key dikembalikan ke bawaan"
        else
            set_ns "$ns" "$key" "$value" "$label"
        fi
    done
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
    quiet off
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do
        set_global "$k" 1 "animasi $k = 1"
    done
    for k in force_allow_on_external force_resizable_activities enable_freeform_support \
             enable_non_resizable_multi_window; do
        set_global "$k" 0 "$k = 0"
    done
    root "wm density reset" >/dev/null && ok "density dikembalikan ke bawaan"
    rm -f "$SW_FILE"
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

# 5. Quiet / lighter device ------------------------------------------------------------
quiet on

echo "  (freeform & resizable aktif setelah reboot)"
exit 0
