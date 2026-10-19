-- One loading slot shared by Launch All, automatic recovery and remote requests.
-- tick() never waits for a game: the monitor remains responsive while work is held.
local Queue = {}
Queue.__index = Queue

Queue.DEFAULTS = {
    stableHeartbeats = 3, stableSeconds = 20, retryCooldown = 120, maxAttempts = 3,
}

function Queue.new(conf, deps)
    deps = deps or {}
    local self = setmetatable({ conf = conf or {}, pending = {}, active = nil,
        states = {}, attempts = {}, healthySince = {}, seenAt = {}, lastEmpty = {} }, Queue)
    for key, mod in pairs({ hb = "heartbeat", apk = "apk", auth = "auth", recovery = "recovery",
        key = "delta_key", optimizer = "optimizer" }) do
        self[key] = deps[key] or require("managers." .. mod)
    end
    self.log = deps.log or require("core.logger")
    self.now = deps.now or os.time
    self.onRecovery = deps.onRecovery
    return self
end

function Queue:setting(key)
    local s = type(self.conf.launchSafety) == "table" and self.conf.launchSafety or {}
    local minimum = ({ stableHeartbeats = 2, stableSeconds = 5, retryCooldown = 30, maxAttempts = 1 })[key] or 0
    return math.max(minimum, math.floor(tonumber(s[key]) or Queue.DEFAULTS[key]))
end

function Queue:keyStatus()
    local now = self.now()
    if not self.keyAt or now - self.keyAt >= 5 then
        local ok, value = pcall(self.key.present)
        self.keyValue, self.keyAt = ok and value or nil, now
        -- Lua's `and/or` idiom loses false; missing is different from unknown.
        if ok and value == false then self.keyValue = false end
    end
    return self.keyValue
end

function Queue:set(job, state, detail)
    self.states[job.inst.package] = state
    if job.state ~= state then
        job.state = state
        self.log.info(string.format("[QUEUE] %s: %s%s", tostring(job.inst.name or job.inst.package), state,
            detail and (" (" .. detail .. ")") or ""))
    end
end

function Queue:contains(pkg)
    if self.active and self.active.inst.package == pkg then return true end
    for _, job in ipairs(self.pending) do if job.inst.package == pkg then return true end end
    return false
end

function Queue:request(instances, manual)
    local ordered, later = {}, {}
    for _, inst in ipairs(instances or {}) do
        local target = self.auth.isLoggedIn(inst) == false and later or ordered
        target[#target + 1] = inst
    end
    for _, inst in ipairs(later) do ordered[#ordered + 1] = inst end
    for _, inst in ipairs(ordered) do
        local pkg = inst.package
        if pkg then
            if manual and self.active and self.active.inst.package == pkg and self.active.state == "needs_check" then
                -- Retry the held clone in place: moving it behind others would open a
                -- second game while this one may still be loading.
                self.attempts[pkg] = nil
                self.active = { inst = inst, manual = true }
                self.states[pkg] = "queued"
            end
            if not self:contains(pkg) then
                if manual then self.attempts[pkg] = nil end
                self.pending[#self.pending + 1] = { inst = inst, manual = manual == true, recovering = manual ~= true }
                self.states[pkg] = "queued"
            end
        end
    end
end

function Queue:finish(job, state)
    self:set(job, state)
    self.active = nil
end

function Queue:retry(job, reason)
    job.started, job.firstBeatTime, job.lastSeq, job.samples = nil, nil, nil, 0
    job.retryAt = self.now() + math.max(1, self:setting("retryCooldown"))
    self:set(job, "cooldown", reason)
end

function Queue:process(inst)
    local ok, value = pcall(self.apk.isRunning, inst.package)
    if ok and type(value) == "boolean" then return value end
    return nil
end

function Queue:advance(job)
    local inst, now = job.inst, self.now()
    local process = self:process(inst)
    if self.auth.isLoggedIn(inst) == false then
        -- Logging out during a wait must never lead to a force-stop/rejoin.
        if process == nil then self:set(job, "needs_check", "proses tidak terbaca"); return end
        local closed = process == false
        if process and self.apk.hasWindow then
            local ok, window = pcall(self.apk.hasWindow, inst.package)
            closed = ok and window == false
        end
        if closed and self.conf.relaunchNoLogin ~= false then
            if now - (self.lastEmpty[inst.package] or -math.huge) < (tonumber(self.conf.noLoginCooldown) or 120) then
                self:set(job, "cooldown"); return
            end
            self.lastEmpty[inst.package] = now
            self.recovery.reopenNoLogin(inst)
            job.emptyAt = now
        end
        job.emptyAt = job.emptyAt or now
        self:set(job, "nologin")
        if now - job.emptyAt >= (tonumber(self.conf.launchEmptyDelay) or 5) then self:finish(job, "nologin") end
        return
    end

    local alive, why = self.hb.alive(inst)
    if self.hb.isEnabled() and self:keyStatus() == false and (alive ~= true or process ~= true) then
        job.keyWait = true
        job.samples, job.firstBeatTime, job.lastSeq = 0, nil, nil
        self:set(job, "wait_key", "license tidak tersedia; perlu dicek/diisi manual")
        return
    end
    if job.keyWait then
        job.keyWait = nil
        if job.started then job.started = now end -- key entry time is not loading time
    end
    if self.hb.isEnabled() then
        local name, err = self.hb.identity(inst)
        if not name then
            job.identityWait = true
            self:set(job, "wait_identity", err)
            return
        end
        if job.identityWait then
            job.identityWait = nil
            if job.started then job.started = now end
        end
    end
    if not job.started then
        if job.state == "needs_check" then return end
        if job.retryAt and now < job.retryAt then self:set(job, "cooldown"); return end
        local attempt = self.attempts[inst.package] or { count = 0, last = -math.huge }
        if attempt.count >= math.max(1, self:setting("maxAttempts")) then
            self:set(job, "needs_check", "batas percobaan tercapai; restart manual untuk coba lagi"); return
        end
        if not job.manual and now - attempt.last < self:setting("retryCooldown") then
            self:set(job, "cooldown"); return
        end
        attempt.count, attempt.last = attempt.count + 1, now
        self.attempts[inst.package] = attempt
        local ok, launched, err = pcall(self.recovery.launchAndJoin, inst)
        if not ok or not launched then self:retry(job, tostring(ok and err or launched)); return end
        if (attempt.count > 1 or job.recovering) and self.onRecovery then
            pcall(self.onRecovery, inst.id)
        end
        job.started, job.samples = self.now(), 0
        job.manual, job.retryAt = false, nil
        self.healthySince[inst.package] = nil
        pcall(self.optimizer.applyForInstance, inst)
        self:set(job, "starting")
        return
    end

    if process == nil then self:set(job, "needs_check", "proses tidak terbaca"); return end
    if process == false then self:retry(job, "proses mati"); return end
    if not self.hb.isEnabled() then
        self:set(job, "starting", "heartbeat dimatikan; hanya menunggu proses")
        if now - job.started >= math.max(20, tonumber(self.conf.launchSettleDelay) or 20) then
            self:finish(job, "running")
        end
        return
    end
    if alive == false then self:retry(job, why); return end
    local hb = self.hb.read(inst)
    if alive == true and hb and hb.current and hb.fresh then
        if job.session ~= hb.session then
            job.samples, job.lastSeq, job.firstBeatTime = 0, nil, nil
            job.session = hb.session
        end
        if job.lastSeq and (hb.seq < job.lastSeq or hb.time < job.lastBeatTime) then
            job.samples, job.firstBeatTime = 0, nil
        end
        if not job.lastSeq or hb.seq ~= job.lastSeq then
            job.samples = (job.samples or 0) + 1
            job.lastSeq, job.lastBeatTime = hb.seq, hb.time
            job.firstBeatTime = job.firstBeatTime or hb.time
        end
        self:set(job, "stabilizing")
        if job.samples >= math.max(1, self:setting("stableHeartbeats"))
            and hb.time - job.firstBeatTime >= self:setting("stableSeconds") then
            self.healthySince[inst.package] = now
            self:finish(job, "ingame")
        end
        return
    end
    job.samples, job.lastSeq, job.firstBeatTime = 0, nil, nil
    if job.state ~= "needs_check" then self:set(job, "starting") end
    local timeout = math.max(30, tonumber(self.conf.launchJoinTimeout) or 240)
    if now - job.started >= timeout then
        self:set(job, "needs_check", "heartbeat belum siap; antrean ditahan, tanpa restart otomatis")
    end
end

function Queue:tick(instances)
    local byPackage = {}
    for _, inst in ipairs(instances) do byPackage[inst.package] = inst end
    -- Reconcile edits/removal from the menu or bot, even while a job is held.
    if self.active then
        local fresh = byPackage[self.active.inst.package]
        if fresh then self.active.inst = fresh else self.active = nil end
    end
    for i = #self.pending, 1, -1 do
        local fresh = byPackage[self.pending[i].inst.package]
        if fresh then self.pending[i].inst = fresh else table.remove(self.pending, i) end
    end
    for _, inst in ipairs(instances) do
        local pkg, now = inst.package, self.now()
        if not self:contains(pkg) then
            local loggedIn = self.auth.isLoggedIn(inst)
            -- A clone that was gently opened at its login screen has no queued job
            -- after the nologin settle period. Once the owner logs in, queue a fresh
            -- cold launch so the configured game link is actually opened.
            if loggedIn == true and self.states[pkg] == "nologin" then
                self:request({ inst }, true)
            else
                local process = self:process(inst)
                local alive = self.hb.alive(inst)
                if loggedIn == false then
                    self.states[pkg] = "nologin"
                    local closed = process == false
                    if process and self.apk.hasWindow then
                        local ok, window = pcall(self.apk.hasWindow, pkg)
                        closed = ok and window == false
                    end
                    if closed and self.conf.relaunchNoLogin ~= false then self:request({ inst }, false) end
                elseif process == nil then
                    self.states[pkg] = "needs_check"
                elseif process == false or alive == false then
                    self.healthySince[pkg] = nil
                    self:request({ inst }, false)
                elseif alive == true then
                    self.states[pkg] = "ingame"
                    self.healthySince[pkg] = self.healthySince[pkg] or now
                    if now - self.healthySince[pkg] >= 60 then self.attempts[pkg] = nil end
                elseif not self.hb.isEnabled() then
                    self.states[pkg] = "running"
                else
                    self.seenAt[pkg] = self.seenAt[pkg] or now
                    self.states[pkg] = self:keyStatus() == false and "wait_key" or "starting"
                    -- Adopt a running clone without restarting it just because HB is absent.
                    if not self.active then self.active = { inst = inst, started = self.seenAt[pkg], samples = 0 } end
                end
            end
        end
    end
    if not self.active then self.active = table.remove(self.pending, 1) end
    if self.active then self:advance(self.active) end
end

return Queue
