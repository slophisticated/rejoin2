#!/bin/sh
# Send the update logs that a push added or bumped (run by .github/workflows/update-log.yml).
#
#   sh tools/send_new_update_logs.sh <before-sha> <after-sha>
#
# A log file in tools/update_logs/ is sent when it is new in the push, or when its
# `version` changed. Edits that keep the same version (typo fixes) are not re-sent.
# The webhook comes from $UPDATE_LOG_WEBHOOK (a GitHub Actions secret); without it
# nothing is sent and the job still succeeds.

BEFORE=$1
AFTER=${2:-HEAD}
LUA=${LUA:-lua5.3}
command -v "$LUA" >/dev/null 2>&1 || LUA=lua

if [ -z "$UPDATE_LOG_WEBHOOK" ]; then
    echo "secret UPDATE_LOG_WEBHOOK belum diisi, update log tidak dikirim"
    exit 0
fi

# A new branch / first push has no usable "before": look at the last commit only.
if [ -z "$BEFORE" ] || ! git cat-file -e "$BEFORE^{commit}" 2>/dev/null; then
    BEFORE=$(git rev-parse "$AFTER^" 2>/dev/null) || BEFORE=""
fi

if [ -n "$BEFORE" ]; then
    FILES=$(git diff --name-only --diff-filter=AM "$BEFORE" "$AFTER" -- 'tools/update_logs/*.lua')
else
    FILES=$(git ls-tree -r --name-only "$AFTER" -- tools/update_logs | grep '\.lua$')
fi

version_of() { # file contents on stdin -> version
    "$LUA" -e 'local f = load(io.read("a")); local ok, t = pcall(f or error)
               print(ok and type(t) == "table" and t.version or "")' 2>/dev/null
}

sent=0
failed=0
for f in $FILES; do
    new=$(git show "$AFTER:$f" | version_of)
    old=""
    if [ -n "$BEFORE" ] && git cat-file -e "$BEFORE:$f" 2>/dev/null; then
        old=$(git show "$BEFORE:$f" | version_of)
        if [ "$old" = "$new" ]; then
            echo "$f: version sama ($new), tidak dikirim ulang"
            continue
        fi
    fi
    echo "$f: kirim ${new:-?}${old:+ (sebelumnya $old)}"
    if "$LUA" tools/update_log.lua "$f" --send >/dev/null; then
        sent=$((sent + 1))
    else
        failed=$((failed + 1))
    fi
done

echo "update log terkirim: $sent, gagal: $failed"
[ "$failed" -eq 0 ]
