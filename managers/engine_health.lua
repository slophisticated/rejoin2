-- Separate from Roblox heartbeat: only the monitor owns this liveness signal.
local Health = {}
local last = 0
function Health.touch()
    local pid = os.getenv("REJOIN_ENGINE_PID")
    local now = os.time()
    if not pid or now - last < 10 then return end
    local f = io.open("data/engine_health.tmp", "w")
    if not f then return end
    f:write(pid, " ", tostring(now), "\n")
    f:close()
    if os.rename("data/engine_health.tmp", "data/engine_health.txt") then last = now end
end
return Health
