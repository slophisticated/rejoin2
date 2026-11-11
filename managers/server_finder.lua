local JSON = require("utils.json")
local Logger = require("core.logger")

-- Finds low-player public servers for a game via Roblox Public Game Servers API.
-- Automatically distributes different servers across clones so they do not crowd the same server.

local ServerFinder = {}

-- Track assigned jobIds: jobId -> { package = pkg, assignedAt = os.time() }
local assignedServers = {}

function ServerFinder.reset()
    assignedServers = {}
end

local function pruneAssignments()
    local now = os.time()
    for jobId, entry in pairs(assignedServers) do
        if now - (entry.assignedAt or 0) > 900 then
            assignedServers[jobId] = nil
        end
    end
end

-- Query public servers list for a placeId sorted by lowest player count (Ascending)
function ServerFinder.fetchServers(placeId)
    placeId = tostring(placeId or ""):match("(%d+)")
    if not placeId or placeId == "" then return nil, "placeId tidak valid" end

    local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100", placeId)
    local cmd = string.format("curl -s -m 10 '%s' </dev/null", url)
    local p = io.popen(cmd)
    if not p then return nil, "popen failed" end
    local output = p:read("*a")
    p:close()

    if not output or output == "" then
        return nil, "curl response kosong"
    end

    local data, err = JSON.decode(output)
    if not data or type(data) ~= "table" or type(data.data) ~= "table" then
        return nil, "JSON decode error: " .. tostring(err)
    end

    return data.data
end

-- Find a low-player server for an instance, prioritizing servers not yet assigned to another clone.
function ServerFinder.findLowPlayerServer(placeId, instance)
    pruneAssignments()
    local pkg = instance and instance.package or "unknown"
    local name = tostring(instance and (instance.name or pkg) or pkg)

    local servers, err = ServerFinder.fetchServers(placeId)
    if not servers or #servers == 0 then
        Logger.warn(string.format("ServerFinder: gagal mengambil daftar server sepi untuk %s (placeId=%s): %s",
            name, tostring(placeId), tostring(err or "daftar kosong")))
        return nil, err
    end

    -- Pick the lowest population server with available slots that is NOT assigned to another clone
    local chosen = nil
    for _, s in ipairs(servers) do
        local id = s.id
        local playing = tonumber(s.playing) or 0
        local maxP = tonumber(s.maxPlayers) or 0
        local available = (maxP == 0) or (maxP - playing > 0)

        if id and available then
            local assigned = assignedServers[id]
            if not assigned or assigned.package == pkg then
                chosen = s
                break
            end
        end
    end

    -- If all servers are occupied by other clones, fallback to the first available server
    if not chosen then
        for _, s in ipairs(servers) do
            local id = s.id
            local playing = tonumber(s.playing) or 0
            local maxP = tonumber(s.maxPlayers) or 0
            if id and ((maxP == 0) or (maxP - playing > 0)) then
                chosen = s
                break
            end
        end
    end

    if chosen and chosen.id then
        assignedServers[chosen.id] = { package = pkg, assignedAt = os.time() }
        Logger.info(string.format("ServerFinder: %s -> server sepi (%d/%d pemain, jobId=%s)",
            name, tonumber(chosen.playing) or 0, tonumber(chosen.maxPlayers) or 0, tostring(chosen.id)))
        return chosen.id
    end

    return nil, "tidak ada server publik yang tersedia"
end

return ServerFinder
