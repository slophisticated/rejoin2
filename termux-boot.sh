#!/data/data/com.termux/files/usr/bin/sh
# Rejoin Engine auto-start on device boot (Termux:Boot plugin).
#
# Install (on device):
#   1. Install the Termux:Boot APP (not a pkg) from the same source as Termux
#      (F-Droid with F-Droid Termux, GitHub releases with GitHub Termux).
#   2. mkdir -p ~/.termux/boot
#   3. cp termux-boot.sh ~/.termux/boot/start-rejoin.sh
#   4. chmod +x ~/.termux/boot/start-rejoin.sh
#   5. Open the Termux:Boot app once, then restart the phone.
#
# On every boot, Termux:Boot runs every script in ~/.termux/boot/ IN THE BACKGROUND
# (no Termux window opens). This is equivalent to choosing "1) Launch All + Monitor":
# launch all clones, then keep monitoring until the process is stopped.
#
# Everything this script does is logged to <repo>/data/boot.log (or ~/rejoin-boot.log
# when the repo folder is missing), so a boot that "does nothing" can be diagnosed.
# BOOT_DELAY (seconds, default 30) gives Android, root and the network time to come
# up before the clones are launched.

REJOIN_DIR=${REJOIN_DIR:-"$HOME/rejoin"}
BOOT_DELAY=${BOOT_DELAY:-30}
# If the engine crashes it is restarted after RESTART_DELAY seconds, at most
# MAX_RESTARTS times in a row (a clean stop or `kill` is not restarted).
RESTART_DELAY=${RESTART_DELAY:-30}
MAX_RESTARTS=${MAX_RESTARTS:-5}
if [ -f "$REJOIN_DIR/main.lua" ]; then
    mkdir -p "$REJOIN_DIR/data" 2>/dev/null
    BOOT_LOG="$REJOIN_DIR/data/boot.log"
else
    BOOT_LOG="$HOME/rejoin-boot.log"
fi
# Keep the log small: start a fresh one when it passes ~256 KB.
if [ -f "$BOOT_LOG" ] && [ "$(wc -c < "$BOOT_LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
    mv -f "$BOOT_LOG" "$BOOT_LOG.old" 2>/dev/null
fi
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$BOOT_LOG"; }

log "boot script started (dir=$REJOIN_DIR, delay=${BOOT_DELAY}s)"

# Keep the CPU awake so Android does not suspend the engine after boot.
if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock </dev/null && log "wake lock taken"
fi

[ -f "$REJOIN_DIR/main.lua" ] || { log "ERROR: $REJOIN_DIR/main.lua not found (set REJOIN_DIR)"; exit 1; }
cd "$REJOIN_DIR" || { log "ERROR: cannot cd to $REJOIN_DIR"; exit 1; }
command -v lua >/dev/null 2>&1 || { log "ERROR: lua not found (pkg install lua53)"; exit 1; }
[ -f config/config.lua ] || log "WARN: config/config.lua missing"

sleep "$BOOT_DELAY"
if su -c id </dev/null >/dev/null 2>&1; then log "root ok"; else log "WARN: su -c id failed (root not granted yet?)"; fi

# The live dashboard is useless without a window, so stdout is dropped; errors go to
# boot.log and the engine's own log stays in data/rejoin.log. stdin is /dev/null
# because Termux:Boot gives the script no terminal.
restarts=0
while :; do
    log "starting engine: lua main.lua --headless --start-monitor --auto-launch"
    lua main.lua --headless --start-monitor --auto-launch </dev/null >/dev/null 2>>"$BOOT_LOG"
    code=$?
    case "$code" in
        0|130|143)
            log "engine stopped (exit $code)"
            exit "$code"
            ;;
    esac
    restarts=$((restarts + 1))
    if [ "$restarts" -gt "$MAX_RESTARTS" ]; then
        log "ERROR: engine still crashing after $MAX_RESTARTS restarts (exit $code); giving up"
        exit "$code"
    fi
    log "WARN: engine crashed (exit $code); restart $restarts/$MAX_RESTARTS in ${RESTART_DELAY}s"
    sleep "$RESTART_DELAY"
done
