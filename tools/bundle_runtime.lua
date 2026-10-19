_G.__YA_SUPERVISOR = [[
#!/data/data/com.termux/files/usr/bin/sh
# Rejoin single-file terminal supervisor (embedded in yanamin.lua).
#
# Derived from run.sh: the monitor loop spends nearly all its time inside
# os.execute/io.popen, and POSIX blocks SIGINT there. This shell wrapper owns the
# terminal so Ctrl+C stops the engine, and restarts it when the cookie-paste
# flow exits 75.
#
# The working directory is preserved. core.paths resolves config and data under
# /sdcard/yanamin (or YANAMIN_HOME), independent of the loader location.

TARGET=__TARGET__

# Interpreter may be named lua, lua5.3, lua5.4 or luajit depending on which
# package the device installed, so never assume the bare name "lua".
LUA_BIN=$(command -v lua5.3 2>/dev/null || command -v lua 2>/dev/null || command -v lua5.4 2>/dev/null || command -v luajit 2>/dev/null || echo lua)

exec 3<&0
TTY_STATE=
if [ -t 3 ]; then
    stty sane <&3 2>/dev/null
    stty echo icanon opost onlcr <&3 2>/dev/null
    TTY_STATE=$(stty -g <&3 2>/dev/null) || TTY_STATE=
fi
PID=
restore_tty() {
    if [ -n "$TTY_STATE" ]; then
        stty "$TTY_STATE" <&3 2>/dev/null || stty sane <&3 2>/dev/null
    elif [ -t 3 ]; then
        stty sane <&3 2>/dev/null
    fi
    if [ -t 3 ]; then stty echo icanon opost onlcr <&3 2>/dev/null; fi
}
stop_child() {
    if [ -n "$PID" ]; then
        kill -TERM "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null
    fi
    restore_tty
    exit "$1"
}
trap 'stop_child 130' INT
trap 'stop_child 143' TERM
while :; do
    # Explicit stdin redirection keeps the background Lua off /dev/null;
    # fd 3 holds the original terminal even without /dev/tty.
    REJOIN_WRAPPER=1 "$LUA_BIN" "$TARGET" "$@" <&3 &
    PID=$!
    wait "$PID"
    STATUS=$?
    PID=
    restore_tty
    if [ "$STATUS" -ne 75 ]; then exit "$STATUS"; fi
    # Cookie input used a long paste. Redraw a fresh menu in a new Lua process.
    if [ -t 3 ]; then printf '\033[2J\033[H'; fi
done
]]

local __ya_real_require = require
local __ya_loaded = {}

local function __ya_source(name)
    return __ya_sources[name]
end

local function __ya_require(name)
    local cached = __ya_loaded[name]
    if cached ~= nil then return cached end
    local src = __ya_sources[name]
    if src == nil then
        -- Optional C modules (lfs, socket, posix.signal) stay external so the
        -- pcall fallbacks in utils/ keep working.
        return __ya_real_require(name)
    end
    local chunk, err
    if load then
        chunk, err = load(src, "@" .. name, "t", _G)
    else
        chunk, err = loadstring(src, "@" .. name)
        if chunk then setfenv(chunk, _G) end
    end
    if not chunk then
        error("yanamin bundle: cannot compile module " .. tostring(name) .. ": " .. tostring(err), 0)
    end
    local ok, mod = pcall(chunk)
    if not ok then
        error("yanamin bundle: module " .. tostring(name) .. " failed: " .. tostring(mod), 0)
    end
    __ya_loaded[name] = mod
    return mod
end

_G.require = __ya_require
_G.__ya_require = __ya_require
_G.__ya_source = __ya_source
