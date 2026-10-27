-- Run from the repository root: lua tests/launch_queue_test.lua
local now, files, events, logs = 1000, {}, {}, {}
os.time = function() return now end
local function stub(name, value) package.loaded[name] = value end
local noop = function() end
stub("core.logger", { info = function(s) logs[#logs + 1] = s end, warn = noop, error = noop, debug = noop })
stub("utils.file", { read = function(p) return files[p] end,
    write = function(p, s) files[p] = s; return true end })
os.remove = function(p) files[p] = nil end
local instances = { { id = 1, package = "clone.a", name = "A" },
    { id = 2, package = "clone.b", name = "B" }, { id = 3, package = "clone.c", name = "C" } }
local ready, starts = {}, {}
local loginProbe = function() return true end
local processUp = true
stub("managers.auth", { isLoggedIn = function(...) return loginProbe(...) end })
stub("managers.username", { get = function(i) return i.name end })
stub("utils.probe_log", { line = noop })
stub("managers.window_layout", {})
stub("managers.webhook", {})
stub("managers.delta_key", { present = function() return false end })
stub("managers.status", { setProgress = noop, beginStarting = noop, endStarting = noop,
    printSummary = noop, setLaunchNotice = noop })
stub("utils.timer", {})
stub("managers.heartbeat", { isEnabled = function() return true end,
    alive = function(i) return ready[i.id] end, launchedAt = function(i) return starts[i.id] end,
    isUp = function() return true end })
local onWait
stub("managers.remote", { tick = noop, idle = function(seconds)
    now = now + seconds
    onWait()
end })
local Monitor = require("managers.monitor")
local Control = require("managers.launch_control")
local function up(fn, name)
    for n = 1, 100 do
        local key, value = debug.getupvalue(fn, n)
        if not key then break end
        if key == name then return value, n end
    end
    error("Missing upvalue " .. name)
end
local launch = up(Monitor.start, "runSequentialLaunch")
local order = up(launch, "launchInOrder")
local function set(fn, name, value)
    local _, n = up(fn, name); debug.setupvalue(fn, n, value)
end
local manager = { getAll = function() return instances end, find = function(id)
    for _, i in ipairs(instances) do if tostring(i.id) == tostring(id) then return i end end
end }
set(Monitor.start, "instanceManager", manager)
set(Monitor.start, "apkManager", { isRunning = function() return processUp end })
set(Monitor.start, "Optimizer", { applyForInstance = noop })
set(Monitor.start, "recoveryManager", { launchAndJoin = function(i)
    events[#events + 1] = i.id; starts[i.id] = now; return true
end })
-- checkWindow is irrelevant to the queue tests.
set(order, "checkWindow", noop)
local conf = { launchJoinTimeout = 12, launchWaitTimeout = 3, launchWaitInterval = 3 }
local function reset()
    events, starts, ready = {}, {}, {}
    loginProbe = function() return true end
    processUp = true
    Control.clear()
    set(Monitor.start, "running", true)
    set(Monitor.requestRejoin, "pendingJoin", {})
    set(Monitor.requestRejoin, "pausedJoin", {})
    set(Monitor.requestRejoin, "rejoinQueue", {})
    set(order, "wasNoLogin", {})
end

reset()
onWait = function()
    assert(#events == 1, "RSS/timeout opened another clone without heartbeat")
    if now - starts[1] >= 30 then Control.request("cancel") end
end
launch(conf)
assert(#events == 1, "cancel must keep B/C closed")

reset()
onWait = function()
    if #events == 1 and now - starts[1] >= 15 then Control.request("skip") end
    if #events == 2 and now - starts[2] >= 15 then
        assert(events[2] == 2 and #events == 2, "skip released more than one clone")
        Control.request("cancel")
    end
end
launch(conf)
assert(#events == 2 and events[2] == 2)
assert(up(Monitor.requestRejoin, "pausedJoin")[instances[1].package], "skip protection missing")
assert(up(Monitor.requestRejoin, "pausedJoin")[instances[3].package], "cancelled tail can be recovered immediately")

reset()
onWait = function()
    local id = events[#events]
    if now - starts[id] >= 15 then ready[id] = true end
end
launch(conf)
assert(#events == 3, "fresh heartbeat should release each successor")

reset()
Monitor.requestRejoin({ 1, 1 })
assert(#up(Monitor.requestRejoin, "rejoinQueue") == 1, "duplicate target queued")
launch(conf, { instances[1] })
assert(#events == 1 and events[1] == 1, "target join touched another clone")
print("PASS: timeout/key hold, one-at-a-time skip, cancel, heartbeat release, target dedup")

reset()
local joinAfterLogin = up(Monitor.start, "joinAfterLogin")
set(joinAfterLogin, "wasNoLogin", { [instances[1].package] = true })
joinAfterLogin(instances[1], 1, "A", instances[1].package, "starting")
assert(up(Monitor.requestRejoin, "pendingJoin")[instances[1].package])
assert(not up(Monitor.requestRejoin, "pendingJoin")[instances[2].package])
print("PASS: newly logged-in target protected and other clones not queued")

Control.publish(instances[1], "hold")
local old = Control.read().token
Control.publish(instances[2], "hold")
assert(not Control.request("skip", old), "stale menu skipped another clone")
Control.clear()
print("PASS: stale control rejected")

reset()
local recovery = up(order, "recoveryManager")
local launchTarget = recovery.launchAndJoin
recovery.launchAndJoin = function(i)
    events[#events + 1] = i.id; starts[i.id] = now; return false, "simulated failure"
end
onWait = function()
    assert(#events == 1, "launch failure released another clone")
    Control.request("cancel")
end
launch(conf)
assert(#events == 1)
recovery.launchAndJoin = launchTarget
print("PASS: launch failure holds the batch")

-- Logout on a live login screen releases only that target after the short pause.
reset()
local checkedAt
loginProbe = function(i, fresh)
    if i.id == 1 and fresh then checkedAt = now; return false end
    return true
end
onWait = function()
    assert(now - starts[events[#events]] <= 40, "logout did not release the heartbeat gate")
    if #events > 1 then ready[events[#events]] = true end
end
launch(conf)
assert(#events == 3 and checkedAt - starts[1] == 30, "live logout must be rechecked at 30s")
assert(starts[2] - checkedAt == 5, "logout must retain the short login-screen pause")
assert(up(order, "wasNoLogin")[instances[1].package], "manual login transition must remain tracked")
assert(not up(Monitor.requestRejoin, "pausedJoin")[instances[1].package], "logout is not a manual skip")
assert(Control.read() == nil, "logout left stale launch controls")
print("PASS: periodic logout check releases the queue without heartbeat")

reset()
processUp = false
loginProbe = function(i, fresh)
    if i.id == 1 and fresh then checkedAt = now; return false end
    return true
end
launch(conf)
assert(#events == 3 and checkedAt - starts[1] == 6, "two absent-process checks must trigger early login verification")
print("PASS: FC triggers early logout verification")

-- FC, unknown login and probe errors must never become automatic skip.
for _, result in ipairs({ "valid", "unknown", "error" }) do
    reset()
    processUp = false
    local probes = 0
    loginProbe = function(i, fresh)
        if fresh then
            probes = probes + 1
            if result == "error" then error("simulated login probe failure") end
            if result == "unknown" then return nil end
        end
        return true
    end
    onWait = function()
        assert(#events == 1, "FC/uncertain login released another clone")
        assert(now - starts[1] <= 45, "test failed to cancel")
        if now - starts[1] >= 42 then Control.request("cancel") end
    end
    launch(conf)
    assert(#events == 1 and probes == 2, "FC checks must be bounded and periodically repeated")
end
print("PASS: FC with valid/unknown/failed login check holds the queue")

-- Unknown states and previous-session files are not proof of a fresh in-game join.
package.loaded["managers.heartbeat"] = nil
stub("core.config", { get = function() return { heartbeat = { enabled = true } } end })
stub("utils.shell", {})
local HB = require("managers.heartbeat")
HB.read = function() return { current = false, fresh = true, state = "ingame" } end
assert(HB.alive(instances[1]) == nil)
HB.read = function() return { current = true, fresh = true, state = "loading" } end
assert(HB.alive(instances[1]) == nil)
HB.read = function() return { current = true, fresh = true, state = "ingame" } end
assert(HB.alive(instances[1]) == true)
print("PASS: stale-session and non-ingame heartbeat rejected")

-- Bot inject queues exactly the selected target and refuses a busy queue.
package.loaded["managers.remote"] = nil
stub("managers.instance", manager)
stub("managers.cookie_injector", { inject = function(i)
    assert(i.id == 1); return true, "injected"
end })
local marked
package.loaded["managers.auth"].markLoggedIn = function(pkg) marked = pkg end
set(Monitor.requestRejoin, "pendingJoin", {})
local Remote = require("managers.remote")
local requested
local ok = Remote.handlers.cookie_inject({ clone = 1, token = string.rep("x", 30) },
    { requestRejoin = function(ids) requested = ids end })
assert(ok and marked == instances[1].package and #requested == 1 and requested[1] == 1)
Monitor.requestRejoin({ 1 })
assert(not Remote.handlers.cookie_inject({ clone = 2, token = string.rep("x", 30) }, {}))
print("PASS: bot inject target only and busy queue blocked")
