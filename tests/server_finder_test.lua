-- Run with: lua tests/server_finder_test.lua
local ServerFinder = require("managers.server_finder")
local JSON = require("utils.json")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
        print("PASS: " .. name)
    else
        failed = failed + 1
        print("FAIL: " .. name .. "\n" .. tostring(err))
    end
end

-- Stub fetchServers to return mock data
local mockServers = {
    { id = "job-server-1", playing = 1, maxPlayers = 12 },
    { id = "job-server-2", playing = 2, maxPlayers = 12 },
    { id = "job-server-3", playing = 3, maxPlayers = 12 },
    { id = "job-server-full", playing = 12, maxPlayers = 12 },
}

test("findLowPlayerServer picks lowest population server with available slots", function()
    ServerFinder.reset()
    ServerFinder.fetchServers = function() return mockServers end

    local clone1 = { package = "com.apengjers.v3", name = "Clone1" }
    local jobId1 = ServerFinder.findLowPlayerServer("3351674303", clone1)
    assert(jobId1 == "job-server-1", "expected job-server-1, got " .. tostring(jobId1))
end)

test("multiple clones get DIFFERENT servers (mencar)", function()
    ServerFinder.reset()
    ServerFinder.fetchServers = function() return mockServers end

    local clone1 = { package = "com.apengjers.v3", name = "Clone1" }
    local clone2 = { package = "com.apengjers.v4", name = "Clone2" }
    local clone3 = { package = "com.apengjers.v5", name = "Clone3" }

    local job1 = ServerFinder.findLowPlayerServer("3351674303", clone1)
    local job2 = ServerFinder.findLowPlayerServer("3351674303", clone2)
    local job3 = ServerFinder.findLowPlayerServer("3351674303", clone3)

    assert(job1 == "job-server-1", "clone 1 expected job-server-1, got " .. tostring(job1))
    assert(job2 == "job-server-2", "clone 2 expected job-server-2, got " .. tostring(job2))
    assert(job3 == "job-server-3", "clone 3 expected job-server-3, got " .. tostring(job3))
    assert(job1 ~= job2 and job2 ~= job3 and job1 ~= job3, "clones must not share the same server")
end)

test("graceful fallback when API fails", function()
    ServerFinder.reset()
    ServerFinder.fetchServers = function() return nil, "network error" end

    local clone1 = { package = "com.apengjers.v3", name = "Clone1" }
    local job = ServerFinder.findLowPlayerServer("3351674303", clone1)
    assert(job == nil, "expected nil on failure")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
