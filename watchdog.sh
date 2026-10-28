#!/data/data/com.termux/files/usr/bin/sh
# Observe one supervised Lua child. Never kill/restart it or launch clones.
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)" || exit 1
pid=$1
case "$pid" in ''|*[!0-9]*) exit 2 ;; esac
reported=0
while kill -0 "$pid" 2>/dev/null; do
    sleep 30
    kill -0 "$pid" 2>/dev/null || exit 0
    if [ -f data/watchdog_pending.txt ]; then
        lua utils/watchdog_report.lua retry "$pid" </dev/null >/dev/null 2>&1
    fi
    read -r owner stamp < data/engine_health.txt 2>/dev/null || continue
    [ "$owner" = "$pid" ] || continue
    case "$stamp" in ''|*[!0-9]*) continue ;; esac
    age=$(($(date +%s) - stamp))
    if [ "$age" -ge 300 ] && [ "$reported" -eq 0 ]; then
        lua utils/watchdog_report.lua hang "$pid" </dev/null >/dev/null 2>&1
        reported=1
    elif [ "$age" -lt 300 ]; then
        reported=0
    fi
done
