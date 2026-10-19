# Rejoin publish branch

This branch (`rejoinversifinal`) starts from apengjers/rejoin main d0de119 and ports
slophisticated/rejoin2's presets, bot, fixes and heartbeat v3. It is intentionally
separate from dev main. Do not edit or push dev main when working on this port.
The user explicitly chose the branch name rejoinversifinal instead of publish/*.

- Lua 5.3 engine runs in Termux on rooted Redfinger Android; in-game heartbeat runs
  in Delta. Never claim local simulations are real-device tests.
- main.lua is the source entrypoint. yanamin.lua is generated: edit source, run
  `node tools/bundle_loader.js`, verify `node tools/bundle_loader.js --check`.
- Preserve publish boot/uninstall, autodetect and grid/status-bar behavior.
- core.paths owns /sdcard/yanamin or YANAMIN_HOME. Every engine state file uses it.
  Config survives updates. New launchSafety defaults work at runtime on old configs.
- Menu: 1 Launch All, 2 Instances, 3 Settings, 4 Scripts, 5 Cookie, 6 Boot,
  7 Uninstall, 8 Discord, 9 Display/Saver, 10 Exit, 11 Presets, 12 Queue, 13 Monitor.
- All launches/recovery/preset/bot restarts share managers.launch_queue's ONE slot.
  Timeout holds needs_check. Missing key + no ready heartbeat waits without retries.
  No key bypass; manual key entry only. Unknown key is not proof of Get Key UI.
- Username -> package mapping plus a fresh session token and increasing sequence
  identify heartbeat v3. Loading/unknown/old/duplicate-account reports never release
  another clone. Default 3 reports spanning 20 s; 120 s retry cooldown, 3 attempts.
- No RAM limit or gate. RSS is diagnostic only. Logged-out clones are never
  force-stopped; use gentle open. Do not enable mode saver without user preference.
- Shell.exec wraps su/timeout/stdin redirects; compound commands require sh -c.
  Never log cookies, webhook URLs, bot secrets or tokens. curl webhook runs as Termux.
- Game links use InstanceManager.gameLink; new remote settings require SCHEMA,
  DEFAULTS and docs/discord_bot_prd.md. Bot only changes explicitly allowed settings.
- Scripts are written to Scripts; Autoexecute receives copies only. Reserved
  rejoin_heartbeat.lua cannot be edited/deleted through menus/bot.
- Validation: Lua syntax + tests/regressions.lua + tests/publish.lua; npm test in bot;
  sh -n shell scripts; bundle check and git diff --check. Keep tests isolated.
- Feature changes update README.md, setup.md and docs/changelog.md. Release webhook
  content lives in tools/update_logs; workflow only sends when merged/pushed to main.
- User-facing text Indonesian, code comments English, commit messages English.
- Before publish, fetch latest apeng main, verify it is an ancestor and simulate
  merge. Push only this branch on slophisticated/rejoin2; never force push.
