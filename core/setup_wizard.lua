local Logger = require("core.logger")
local File = require("utils.file")
local Config = require("core.config")

local Wizard = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

-- Installed Roblox clones. managers/clone_scan probes several sources (the bulk
-- `pm list packages` is user-scoped and misses clones in another user space) and
-- applies the optional clonePackagePrefix filter.
local function detectRobloxPackages()
    Logger.info("SetupWizard: detecting installed packages")
    local conf = Config.get() or {}
    local prefix = conf.clonePackagePrefix or ""
    local CloneScan = require("managers.clone_scan")
    return CloneScan.scanClones(prefix)
end

function Wizard.run()
    print("\n=== Rejoin Engine Setup Wizard ===\n")
    print("This wizard will help you create instances and initial configuration.")
    print("Choose mode:")
    print("  1) Auto Detect Roblox apps/clones on device (Termux/Android)")
    print("  2) Manual input (enter package names by hand)")

    local choice = prompt("Select 1 or 2: ") or ""
    choice = choice:match("^%s*(.-)%s*$")

    local conf = Config.get() or {}
    conf.instances = conf.instances or {}

    -- find next available id (pairs + normalization, so string keys don't break it)
    local function nextId()
        local maxid = 0
        for _,v in pairs(conf.instances) do
            if type(v) == "table" and type(v.id) == "number" and v.id > maxid then maxid = v.id end
        end
        return maxid + 1
    end

    if choice == "1" then
        local pkgs, err = detectRobloxPackages()
        if not pkgs or #pkgs == 0 then
            print("No Roblox packages detected or detection failed. Try Manual mode.")
            return false, "no_packages"
        end

        print("Found the following Roblox-related packages:")
        for i,p in ipairs(pkgs) do
            print(string.format("  %d) %s", i, p))
        end

        local sel = prompt("Enter indices to import (e.g. 1,2) or 'all': ") or ""
        sel = sel:lower():match("^%s*(.-)%s*$")
        local indices = {}
        if sel == "all" or sel == "a" then
            for i=1,#pkgs do table.insert(indices, i) end
        else
            for s in sel:gmatch("%d+") do table.insert(indices, tonumber(s)) end
        end

        if #indices == 0 then
            print("No indices selected. Aborting import.")
            return false, "no_selection"
        end

        for _,idx in ipairs(indices) do
            local pkg = pkgs[idx]
            if pkg then
                local id = nextId()
                local defaultName = pkg
                local name = prompt(string.format("Name for %s (press Enter for '%s'): ", pkg, defaultName)) or ""
                if name == "" then name = defaultName end
                local server = prompt("Private Server URL (or blank): ") or ""
                if server == "" then server = nil end
                table.insert(conf.instances, { id = id, name = name, package = pkg, privateServer = server })
                print(string.format("Added instance %s (%s)", name, pkg))
            end
        end

        local ok, serr = Config.save(conf)
        if not ok then
            print("Failed to save config: " .. tostring(serr))
            return false, serr
        end

        print("Setup complete. Instances imported and saved to config/config.lua")
        return true

    else
        -- Manual mode
        print("Manual mode: enter instance details. Leave package name empty to finish.")
        while true do
            local pkg = prompt("Package name (e.g. com.roblox.client) [leave blank to finish]: ") or ""
            pkg = pkg:match("^%s*(.-)%s*$")
            if pkg == "" then break end
            local id = nextId()
            local name = prompt("Instance name (press Enter to use package as name): ") or ""
            if name == "" then name = pkg end
            local server = prompt("Private Server URL (optional): ") or ""
            if server == "" then server = nil end
            table.insert(conf.instances, { id = id, name = name, package = pkg, privateServer = server })
            print(string.format("Added instance %s (%s)", name, pkg))
        end

        if #conf.instances == 0 then
            print("No instances added. Aborting.")
            return false, "no_instances"
        end

        local ok, serr = Config.save(conf)
        if not ok then
            print("Failed to save config: " .. tostring(serr))
            return false, serr
        end

        print("Setup complete. Configuration saved to config/config.lua")
        return true
    end
end

return Wizard
