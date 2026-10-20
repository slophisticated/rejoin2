-- REJOIN_HEARTBEAT v3
-- Installed automatically by rejoin into the executor's autoexecute folder.
-- Edits here are overwritten: change the settings in rejoin (Settings > 13) instead.
--
-- Every few seconds it writes this account's in-game status to
--   <workspace>/rejoin/hb_<username>.txt
-- so rejoin knows the clone is really in a game, and reacts at once to a kick or
-- disconnect. The optional saver mode lowers CPU/GPU/memory use.

local CFG = --[[REJOIN_CFG]]{
    interval = 10,
    folder = "rejoin",
    saver = false,
    disable3d = true,
    fpsCap = 15,
    lowGraphics = true,
    mute = true,
}--[[/REJOIN_CFG]]

local env = (getgenv and getgenv()) or _G
if env.__rejoin_heartbeat then return end
env.__rejoin_heartbeat = true

local function safe(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Stats = game:GetService("Stats")

local lp = Players.LocalPlayer
while not lp do
    task.wait(1)
    lp = Players.LocalPlayer
end

-- Saver mode ---------------------------------------------------------------
if CFG.saver then
    if CFG.disable3d then
        safe(function() RunService:Set3dRenderingEnabled(false) end)
    end
    if CFG.fpsCap and CFG.fpsCap > 0 and setfpscap then
        safe(setfpscap, CFG.fpsCap)
    end
    if CFG.lowGraphics then
        safe(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        safe(function()
            UserSettings():GetService("UserGameSettings").SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        end)
    end
    if CFG.mute then
        safe(function() UserSettings():GetService("UserGameSettings").MasterVolume = 0 end)
    end
end

-- Kick / disconnect detection ------------------------------------------------
local state, reason = "ingame", ""

local function checkError()
    local msg = safe(function() return GuiService:GetErrorMessage() end)
    if msg and msg ~= "" then
        state = "kicked"
        reason = msg
    end
end

-- A dropped connection removes the ClientReplicator from NetworkClient: this catches a
-- disconnect even when no error prompt is seen (or the prompt UI was never found).
local function checkConnection()
    local nc = safe(function() return game:GetService("NetworkClient") end)
    local children = nc and safe(function() return nc:GetChildren() end)
    if children and #children == 0 then
        state = "kicked"
        if reason == "" then reason = "koneksi ke server putus" end
    end
end

safe(function() GuiService.ErrorMessageChanged:Connect(checkError) end)
safe(function()
    game:GetService("NetworkClient").ChildRemoved:Connect(function()
        task.wait(1)
        checkError()
        checkConnection()
    end)
end)
task.spawn(function()
    safe(function()
        -- Slow devices can take minutes before this UI exists; 30 s was too short.
        local prompt = game:GetService("CoreGui"):WaitForChild("RobloxPromptGui", 600)
        local overlay = prompt and prompt:WaitForChild("promptOverlay", 600)
        if overlay then
            overlay.ChildAdded:Connect(function(child)
                if child.Name == "ErrorPrompt" then
                    state = "kicked"
                    task.wait(1)
                    checkError()
                end
            end)
        end
    end)
end)

-- Wait until the game has really finished loading -----------------------------
-- game.Loaded fires before the character spawns and while the game is still
-- downloading assets. rejoin starts the next clone once the first heartbeat shows
-- up, so only write it when the character exists and the asset queue stayed empty
-- for a few seconds (each capped, so a game with a menu or endless streaming still
-- gets a heartbeat). A kick during loading is reported at once.
local ContentProvider = game:GetService("ContentProvider")
local function waitFor(cond, maxSeconds)
    local t = 0
    while t < maxSeconds and state ~= "kicked" and not cond() do
        task.wait(1)
        t = t + 1
    end
end
waitFor(function()
    local ch = lp.Character
    return ch ~= nil and ch:FindFirstChild("HumanoidRootPart") ~= nil
end, 90)
local idle = 0
waitFor(function()
    local q = safe(function() return ContentProvider.RequestQueueSize end) or 0
    idle = (q == 0) and idle + 1 or 0
    return idle >= 5
end, 90)

-- Heartbeat file -------------------------------------------------------------
local frames = 0
RunService.Heartbeat:Connect(function() frames = frames + 1 end)

if makefolder and isfolder and not safe(isfolder, CFG.folder) then
    safe(makefolder, CFG.folder)
end
local path = CFG.folder .. "/hb_" .. string.lower(lp.Name) .. ".txt"

local last = os.clock()
local function write()
    local now = os.clock()
    local fps = math.floor(frames / math.max(now - last, 0.001) + 0.5)
    frames, last = 0, now
    local ping = safe(function() return lp:GetNetworkPing() end) or 0
    local mem = safe(function() return Stats:GetTotalMemoryUsageMb() end) or 0
    local lines = {
        "name=" .. lp.Name,
        "userid=" .. tostring(lp.UserId),
        "placeid=" .. tostring(game.PlaceId),
        "jobid=" .. tostring(game.JobId),
        "time=" .. tostring(os.time()),
        "state=" .. state,
        "reason=" .. (tostring(reason):gsub("[\r\n=]", " ")),
        "fps=" .. tostring(fps),
        "ping=" .. tostring(math.floor(ping * 1000)),
        "mem=" .. tostring(math.floor(mem)),
    }
    if writefile then safe(writefile, path, table.concat(lines, "\n")) end
end

while true do
    -- Events can be missed: look at the error message and the connection every time.
    if state ~= "kicked" then
        checkError()
        checkConnection()
    end
    write()
    task.wait(CFG.interval)
end
