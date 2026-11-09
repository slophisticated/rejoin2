#!/bin/sh
# Exercise volume diagnostics without Android or root.
set -eu
cd "$(dirname "$0")/.."
eval "$(sed -n '/^volume() {/,/^}/p' device_setup.sh)"
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[!!] %s\n' "$*"; }
root() {
    case "$1" in
        *--get) printf 'volume is %s in range [0..15]\n' "$HAVE" ;;
        *--set*) : ;;
        *) return 1 ;;
    esac
}
TOOL=media
HAVE=6
out=$(volume 4 0 'Suara: volume alarm 0')
printf '%s' "$out" | grep -Fq 'instalasi tetap lanjut'
printf '%s' "$out" | grep -Fq 'Setelan Android > Suara/Volume'
printf '%s' "$out" | grep -Fq 'media volume --stream 4 --get'
printf '%s' "$out" | grep -Fq 'media volume --stream 4 --set 0'
TOOL='cmd media_session'
out=$(volume 3 0 'Suara: volume media/game 0')
printf '%s' "$out" | grep -Fq 'cmd media_session volume --stream 3 --get'
HAVE=0
out=$(volume 4 0 'Suara: volume alarm 0')
printf '%s' "$out" | grep -Fq '[OK] Suara: volume alarm 0 (sudah)'
if printf '%s' "$out" | grep -Fq 'Coba ulang'; then exit 1; fi
printf 'device volume diagnostics: OK\n'
