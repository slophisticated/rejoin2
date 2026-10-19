# Architecture

Rejoin Engine menggunakan Modular Architecture.

Semua module memiliki satu tanggung jawab.

---

Project Structure

rejoin/

main.lua

core/

managers/

utils/

config/

data/

assets/

docs/

---

Core

Logger

Config

State

Menu

---

Managers

Instance Manager

APK Manager

Monitor Manager

Recovery Manager

AutoExecute Manager

---

Utils

Shell

Android

JSON

File

Timer

---

Flow

Program Start

↓

Load Config

↓

Load Logger

↓

Load State

↓

Dashboard

↓

Start

↓

Monitor

↓

Recovery

↓

Exit

---

Monitor

Loop

↓

Instance 1

↓

Instance 2

↓

Instance 3

↓

Sleep

↓

Repeat

---

Recovery

Force Stop

↓

Launch

↓

Inject

↓

Join Private Server

↓

Continue

## Antrean heartbeat v3

`managers/launch_queue.lua` owns the single loading slot shared by Launch All,
automatic recovery, and menu/bot rejoin requests. `monitor.lua` calls `tick()` every
poll and continues dashboard, remote sync, key notifications and config reloads.
The queue never waits in a game-loading loop. Diagnostics are sampled every 30 s.
RSS is display/probe data only. There is no RAM quota or admission threshold.

Account identity is resolved on Termux (username ↔ package). Before opening a clone,
Heartbeat writes `start_<username>.txt` to Delta Workspace with a fresh session token.
The Autoexecute script binds that token once, echoes package/name/session/sequence,
and reports loading until character + assets are ready. Previous-session and wrong-
account reports cannot release the slot, including same-second restarts. Unknown
or duplicate username mappings hold identification. Manual app starts can report a
self-generated session only when there is no expected engine request.

Default admission to the next clone needs 3 distinct in-order ingame reports spanning
20 seconds. Missing license + no working heartbeat produces wait_key (heuristic,
not proof of Get Key UI); waiting does not spend retries or the loading deadline.
A deadline produces needs_check and holds the slot, while late ready reports can
resume it. Explicit retries restart that held clone in place. Confirmed process
death/kick/stopped ingame heartbeat use bounded retries (120 s, 3 attempts); a live
process with absent/loading heartbeat is never judged crashed by its RSS.

## Publish entrypoints

`main.lua` and generated `yanamin.lua` load the same modules. `core.paths` owns
`/sdcard/yanamin` (or `YANAMIN_HOME`): config, logger, PID/singleton, webhook state,
HWID, logout/rejoin requests, and key-path cache all use that root. Bundle-only
assets are supplied by `__ya_source`; modular startup uses files from the checkout.
Boot/uninstall modules are source-controlled, and `tools/bundle_loader.js --check`
rejects stale generated loaders. The publish menu keeps slots 1–10, then adds
presets (11), queue settings (12), and monitoring without Launch All (13).
