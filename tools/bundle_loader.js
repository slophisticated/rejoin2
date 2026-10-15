#!/usr/bin/env node
"use strict";
/*
 * Rejoin single-file loader bundler.
 * ---------------------------------------------------------------
 * Generates `yanamin.lua`: the whole engine (main.lua + core/ + managers/ +
 * utils/) collapsed into ONE self-contained Lua 5.3 script that a device can
 * fetch with a single curl line:
 *
 *   curl -L -o /sdcard/download/yanamin.lua \
 *     https://raw.githubusercontent.com/apengjers/rejoin/main/yanamin.lua
 *   lua /sdcard/download/yanamin.lua
 *
 * The repository sources are NEVER modified. Everything the single-file
 * distribution needs on top of them (embedded config template, embedded
 * terminal supervisor, require shim) is applied to the generated artifact
 * only, so `lua main.lua` in the working tree keeps behaving exactly as before.
 *
 * Usage:  node tools/bundle_loader.js
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const ENTRY_FILE = "main.lua";
const TEMPLATE_FILE = "config/template.lua";
const OUT_FILE = path.join(ROOT, "yanamin.lua");
const REPO_URL = "https://github.com/apengjers/rejoin";

const REQUIRE_RE = /require\s*\(\s*["']([^"']+)["']\s*\)/g;

/* Names that must stay external (optional C modules, all behind pcall). */
const EXTERNAL = new Set(["lfs", "socket", "posix.signal"]);

function toRel(p) {
  return p.split(path.sep).join("/");
}

/* "core/logger.lua" -> "core.logger" (require name) */
function toModuleName(rel) {
  return rel.replace(/\.lua$/, "").replace(/\//g, ".");
}

function readSource(rel) {
  const full = path.join(ROOT, rel);
  if (!fs.existsSync(full)) return null;
  // Normalise line endings so the patch needles below always match.
  return fs.readFileSync(full, "utf8").replace(/\r\n/g, "\n");
}

/* Replace `needle` exactly once; hard-fail when the anchor moved. */
function mustReplace(src, needle, replacement, label) {
  const first = src.indexOf(needle);
  if (first === -1) {
    throw new Error(`patch "${label}" did not apply (anchor not found)`);
  }
  if (src.indexOf(needle, first + needle.length) !== -1) {
    throw new Error(`patch "${label}" is ambiguous (anchor matches twice)`);
  }
  return src.slice(0, first) + replacement + src.slice(first + needle.length);
}

/*
 * ---------------------------------------------------------------------------
 * 1. Walk the require graph starting at main.lua
 * ---------------------------------------------------------------------------
 */
const modules = new Map(); // module name -> { rel, src }
const unresolved = new Set();

function addModule(name) {
  if (modules.has(name)) return;
  const rel = name.replace(/\./g, "/") + ".lua";
  const src = readSource(rel);
  if (src === null) {
    unresolved.add(name);
    return;
  }
  modules.set(name, { rel, src });

  REQUIRE_RE.lastIndex = 0;
  let m;
  while ((m = REQUIRE_RE.exec(src)) !== null) {
    addModule(m[1]);
  }
}

addModule(toModuleName(ENTRY_FILE));

// The config template is loaded with dofile(), never require(), but the bundle
// still needs it: it is the fallback when a device has no config/ folder.
const templateSrc = readSource(TEMPLATE_FILE);
if (templateSrc === null) {
  throw new Error("missing " + TEMPLATE_FILE);
}
modules.set(toModuleName(TEMPLATE_FILE), { rel: TEMPLATE_FILE, src: templateSrc });

/* ---------------------------------------------------------------------------
 * 2. Bundle-only patches
 * --------------------------------------------------------------------------- */

// 2a) core/config.lua — fall back to the embedded template module.
const CONFIG_ANCHOR = `local function loadFromFile(path)
    if not File.exists(path) then return nil end`;

const CONFIG_PATCH = `-- yanamin bundle: a device may have no config/ folder at all, so the
-- packaged template ships inside this file as the fallback source.
local __yaTemplate = __ya_require("config.template")

local function loadFromFile(path)
    if not File.exists(path) then
        if path == templatePath then return __yaTemplate end
        return nil
    end`;

// 2b) core/setup.lua — same fallback, but it needs the template *source* text
//     because it copies the file to config/config.lua on first run.
const SETUP_ANCHOR = `    if not File.exists(tplPath) then
        Logger.error("Setup: template not found: " .. tplPath)
        return false, "no_template"
    end

    local content, err = File.read(tplPath)`;

const SETUP_PATCH = `    -- yanamin bundle: use the embedded template when config/template.lua is absent.
    local content, err
    if not File.exists(tplPath) then
        content = __ya_source("config.template")
    else
        content, err = File.read(tplPath)
    end`;

// 2c) main.lua — run.sh does not ship with the single-file loader, so the
//     terminal supervisor (Ctrl+C while os.execute runs, restart on exit 75)
//     is generated next to the engine state instead.
const WRAPPER_ANCHOR = `    local scriptDir = (arg and arg[0] and arg[0]:match("^(.*[/\\\\])")) or ""
    local command = "sh " .. shellQuote(scriptDir .. "run.sh")`;

const WRAPPER_PATCH = `    -- yanamin bundle: no run.sh next to this file. Write the supervisor once
    -- into the shared data root and hand the terminal over to it.
    local Paths = require("core.paths")
    local supervisor = Paths.data("yanamin_wrapper.sh")
    local supervisorFile = io.open(supervisor, "w")
    if supervisorFile then
        local target = (arg and arg[0]) or "yanamin.lua"
        if not target:match("^[/\\\\]") then
            target = (os.getenv("PWD") or ".") .. "/" .. target
        end
        supervisorFile:write(
            __YA_SUPERVISOR:gsub("__TARGET__", function() return shellQuote(target) end)
        )
        supervisorFile:close()
    end
    local command = "sh " .. shellQuote(supervisor)`;

/* Shell supervisor — same contract as run.sh, but the child is this file.
   Kept in a raw template so backslashes survive verbatim. */
const SUPERVISOR_SH = String.raw`#!/data/data/com.termux/files/usr/bin/sh
# Rejoin single-file terminal supervisor (embedded in yanamin.lua).
#
# Derived from run.sh: the monitor loop spends nearly all its time inside
# os.execute/io.popen, and POSIX blocks SIGINT there. This shell wrapper owns the
# terminal so Ctrl+C stops the engine, and restarts it when the cookie-paste
# flow exits 75.
#
# NOTE: the working directory is intentionally NOT changed — config/ and data/
# stay relative to wherever the user started the loader.

TARGET='__TARGET__'

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
`;

if (/\]=*\]/.test(SUPERVISOR_SH)) {
  throw new Error("supervisor template contains a long-bracket terminator");
}

for (const [name, mod] of modules) {
  if (name === toModuleName("core/config.lua")) {
    mod.src = mustReplace(mod.src, CONFIG_ANCHOR, CONFIG_PATCH, "core/config.lua template fallback");
  } else if (name === toModuleName("core/setup.lua")) {
    mod.src = mustReplace(mod.src, SETUP_ANCHOR, SETUP_PATCH, "core/setup.lua template fallback");
  }
}

let entrySrc = readSource(ENTRY_FILE);
entrySrc = mustReplace(entrySrc, WRAPPER_ANCHOR, WRAPPER_PATCH, "main.lua embedded supervisor");
// The entry is inlined as straight-line code below, so drop it from the
// module registry (nothing requires "main").
modules.delete(toModuleName(ENTRY_FILE));

/* ---------------------------------------------------------------------------
 * 3. Emit the bundle
 * --------------------------------------------------------------------------- */

/* Long-bracket string that cannot be terminated by the payload. */
function luaLongString(src) {
  let eq = 0;
  const runs = src.match(/\]=*\]/g) || [];
  for (const r of runs) {
    // "]]" needs at least one "=", "]==]" needs at least two, and so on.
    eq = Math.max(eq, r.length - 1);
  }
  const open = "[" + "=".repeat(eq) + "[";
  const close = "]" + "=".repeat(eq) + "]";
  return open + "\n" + src + close;
}

const moduleEntries = [...modules.entries()]
  .sort((a, b) => (a[0] < b[0] ? -1 : 1))
  .map(([name, mod]) => {
    const key = JSON.stringify(name);
    const body = luaLongString(mod.src);
    return `__ya_sources[${key}] = ${body}`;
  })
  .join("\n");

const supervisorLongString = luaLongString(SUPERVISOR_SH);

const bundle = `--[[
  yanamin.lua — Rejoin Engine, single-file loader bundle.
  ------------------------------------------------------------------
  Generated by tools/bundle_loader.js — do not edit this file by hand,
  edit the sources in the repository and rebuild:

      node tools/bundle_loader.js

  Source:  ${REPO_URL}
  Bundled: ${modules.size} modules, entry ${ENTRY_FILE}

  Install (one line) and run:

      curl -L -o /sdcard/download/yanamin.lua ${REPO_URL.replace("https://github.com/", "https://raw.githubusercontent.com/")}/main/yanamin.lua
      lua /sdcard/download/yanamin.lua

  Android 12+ devices use /sdcard/Download instead of /sdcard/download.

  Everything lives in this file: engine, terminal supervisor and config
  template. config/ and data/ are still read/written relative to the working
  directory, exactly like the multi-file engine.
--]]

local __ya_sources = {}

${moduleEntries}

-- config/template.lua ships as a module too (the bundle needs it when a
-- device has no config folder at all).
__ya_sources["config.template"] = __ya_sources["${toModuleName(TEMPLATE_FILE)}"]

-- Terminal supervisor used when this file starts without REJOIN_WRAPPER.
local __YA_SUPERVISOR = ${supervisorLongString}

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

-- ==========================================================================
-- Entry point (main.lua)
-- ==========================================================================

${entrySrc}
`;

fs.writeFileSync(OUT_FILE, bundle.replace(/\r\n/g, "\n"), "utf8");

/* ---------------------------------------------------------------------------
 * 4. Report
 * --------------------------------------------------------------------------- */
const bytes = Buffer.byteLength(bundle, "utf8");
const lines = bundle.split("\n").length;

console.log("bundled " + modules.size + " modules -> " + toRel(path.relative(ROOT, OUT_FILE)));
for (const [name, mod] of [...modules.entries()].sort()) {
  console.log("  " + name.padEnd(28) + mod.rel);
}

const external = [...unresolved].sort();
if (external.length) {
  const known = external.filter((n) => EXTERNAL.has(n));
  const unknown = external.filter((n) => !EXTERNAL.has(n));
  console.log("external require(s) kept at runtime: " + known.join(", "));
  if (unknown.length) {
    console.log("  WARNING unresolved require(s): " + unknown.join(", "));
  }
} else {
  console.log("external require(s) kept at runtime: (none)");
}

console.log("output: " + lines + " lines, " + bytes + " bytes");