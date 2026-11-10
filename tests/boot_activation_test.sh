#!/bin/sh
# Simulate Android profiles and activity failures without touching a device.
set -eu
cd "$(dirname "$0")/.."
eval "$(sed -n '/^activate_termux_boot() {/,/^}/p' install.sh)"
id() { echo 1012345; }
sleep() { :; }
ok() { printf 'OK: %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*"; }
su() {
    case "$2" in
        'dumpsys package com.termux.boot') printf '%s\n' "$STATE" ;;
        'am start -W --user 10 -n com.termux.boot/.BootActivity')
            printf '%s\n' "$OPEN"
            return "$OPEN_RC" ;;
        *) echo "Unexpected command: $*" >&2; return 1 ;;
    esac
}
OPEN='Status: ok'
OPEN_RC=0
STATE='  User 0: installed=true stopped=false
  User 10: installed=false stopped=false'
out=$(activate_termux_boot; echo "READY=$BOOT_READY")
printf '%s' "$out" | grep -Fq 'READY=0'
printf '%s' "$out" | grep -Fq 'belum terpasang untuk user 10'
STATE='  User 0: installed=false stopped=true
  User 10: installed=true stopped=false'
out=$(activate_termux_boot; echo "READY=$BOOT_READY")
printf '%s' "$out" | grep -Fq 'READY=1'
printf '%s' "$out" | grep -Fq 'boleh reboot'
OPEN='Error type 3: Activity does not exist'
out=$(activate_termux_boot; echo "READY=$BOOT_READY")
printf '%s' "$out" | grep -Fq 'READY=0'
printf '%s' "$out" | grep -Fq 'gagal membuka'
OPEN='Permission denied'
OPEN_RC=1
out=$(activate_termux_boot; echo "READY=$BOOT_READY")
printf '%s' "$out" | grep -Fq 'READY=0'
OPEN='Status: ok'
OPEN_RC=0
STATE='  User 10: installed=true stopped=true'
out=$(activate_termux_boot; echo "READY=$BOOT_READY")
printf '%s' "$out" | grep -Fq 'READY=0'
STATE=''
out=$(activate_termux_boot; echo "READY=$BOOT_READY")
printf '%s' "$out" | grep -Fq 'READY=0'
echo 'boot activation: 6 scenarios passed'
