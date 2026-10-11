#!/data/data/com.termux/files/usr/bin/sh
# Find where a clone's floating window stores its position/size.
#
# Usage:  sh tools/float_probe.sh [package]        (default com.apengjers.v3)
#   1. Run it while the clone is open; it snapshots the clone's shared_prefs.
#   2. Move/resize that clone's floating window, wait a few seconds, press Enter.
#   3. It prints only the settings that changed, short enough for one screenshot.
# Read-only: nothing is written to the clone.

PKG=${1:-com.apengjers.v3}
DIR=/data/data/$PKG/shared_prefs
TMP=${TMPDIR:-$HOME}/.float_probe
mkdir -p "$TMP"

snap() {
    # one "file: <tag>" per line, values cut short so tokens never show in full
    su -c "grep -H '' $DIR/*.xml" </dev/null 2>/dev/null \
        | awk -v dir="$DIR/" '{
            i = index($0, ":"); f = substr($0, 1, i - 1); c = substr($0, i + 1)
            sub(dir, "", f); gsub(/></, ">\n<", c)
            n = split(c, parts, "\n")
            for (k = 1; k <= n; k++) if (parts[k] != "") print f ": " parts[k]
          }' \
        | grep -v -iE 'ROBLOSECURITY|cookie|token' \
        | cut -c1-110 | sort -u > "$1"
}

echo "== $PKG"
echo "Android: $(getprop ro.build.version.release)  layar: $(su -c 'wm size' </dev/null 2>/dev/null | sed 's/.*: //')"
FREE=$(su -c "dumpsys activity activities" </dev/null 2>/dev/null | grep -cE "windowingMode=(5|freeform)")
echo "jendela freeform Android: $FREE"
COUNT=$(su -c "ls $DIR" </dev/null 2>/dev/null | wc -l)
echo "file prefs: $COUNT"

snap "$TMP/before"
echo
echo ">> Sekarang geser + resize jendela floating $PKG, tunggu 3 detik, lalu tekan Enter"
read _
sleep 1
snap "$TMP/after"

echo "== BERUBAH (- lama, + baru)"
awk 'NR==FNR { a[$0]=1; next } !($0 in a) { print "+ " $0 }' "$TMP/before" "$TMP/after" > "$TMP/plus"
awk 'NR==FNR { a[$0]=1; next } !($0 in a) { print "- " $0 }' "$TMP/after" "$TMP/before" > "$TMP/minus"
if [ ! -s "$TMP/plus" ] && [ ! -s "$TMP/minus" ]; then
    echo "(tidak ada yang berubah - coba tutup app clone-nya dulu, lalu jalankan ulang)"
else
    cat "$TMP/minus" "$TMP/plus" | head -30
fi
