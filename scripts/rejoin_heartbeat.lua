-- REJOIN_HEARTBEAT v3: account identity + per-launch session, loading is explicit.
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

safe(function() GuiService.ErrorMessageChanged:Connect(checkError) end)
checkError()
task.spawn(function()
    safe(function()
        local prompt = game:GetService("CoreGui"):WaitForChild("RobloxPromptGui", 30)
        local overlay = prompt and prompt:WaitForChild("promptOverlay", 30)
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

-- Heartbeat file -------------------------------------------------------------
local frames = 0
RunService.Heartbeat:Connect(function() frames = frames + 1 end)

if makefolder and isfolder and not safe(isfolder, CFG.folder) then
    safe(makefolder, CFG.folder)
end
local path = CFG.folder .. "/hb_" .. string.lower(lp.Name) .. ".txt"
local request = {}
if readfile then
    local text = safe(readfile, CFG.folder .. "/start_" .. string.lower(lp.Name) .. ".txt") or ""
    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^(%w+)=(.*)$")
        if k then request[k] = v end
    end
end
-- Bind once. A script from an old app session must never adopt a later launch token.
local session = request.name == lp.Name:lower() and request.session or nil
if not (session and session:match("^[%w_%-]+$")) then
    session = "manual_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    request.package = ""
end
local sequence = 0
state = state == "kicked" and "kicked" or "loading"

local last = os.clock()
local function write()
    sequence = sequence + 1
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
        "session=" .. session,
        "package=" .. tostring(request.package or ""),
        "seq=" .. tostring(sequence),
        "time=" .. tostring(os.time()),
        "state=" .. state,
        "reason=" .. (tostring(reason):gsub("[\r\n=]", " ")),
        "fps=" .. tostring(fps),
        "ping=" .. tostring(math.floor(ping * 1000)),
        "mem=" .. tostring(math.floor(mem)),
    }
    if writefile then safe(writefile, path, table.concat(lines, "\n")) end
end

-- Publish loading/kick progress while waiting. No timeout is allowed to claim ingame.
task.spawn(function()
    while env.__rejoin_heartbeat do
        write()
        task.wait(CFG.interval)
    end
end)
local ContentProvider = game:GetService("ContentProvider")
local idle = 0
while env.__rejoin_heartbeat and state ~= "kicked" do
    local ch = lp.Character
    local spawned = ch ~= nil and ch:FindFirstChild("HumanoidRootPart") ~= nil
    local q = safe(function() return ContentProvider.RequestQueueSize end)
    idle = (spawned and type(q) == "number" and q == 0) and idle + 1 or 0
    if idle >= 5 then state = "ingame"; break end
    task.wait(1)
end
