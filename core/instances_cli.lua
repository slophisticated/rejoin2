local Logger = require("core.logger")
local InstanceManager = require("managers.instance")
local Config = require("core.config")
local Shell = require("utils.shell")
local APK = require("managers.apk")

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local function promptGameUrl()
    while true do
        local input = prompt("Game / Private Server URL (wajib): ")
        if input == nil then return nil end
        local value = input:match("^%s*(.-)%s*$")
        if value ~= "" then return value end
        print("Link game atau private server wajib diisi.")
    end
end

local function printInstances()
    local list = InstanceManager.getAll()
    if #list == 0 then
        print("(no instances configured)")
        return
    end
    print("Instances:")
    for _, inst in ipairs(list) do
        print(string.format("  id=%s name=%s package=%s server=%s", tostring(inst.id), tostring(inst.name or ""), tostring(inst.package or ""), tostring(inst.privateServer or "")))
    end
end

local function packageConfigured(packageName)
    local normalized = tostring(packageName or ""):match("^%s*(.-)%s*$"):lower()
    for _, inst in ipairs(InstanceManager.getAll()) do
        if tostring(inst.package or ""):match("^%s*(.-)%s*$"):lower() == normalized then
            return true
        end
    end
    return false
end

local function detectRobloxPackages()
    local conf = Config.get() or {}
    local prefix = type(conf.clonePackagePrefix) == "string" and conf.clonePackagePrefix:lower() or ""
    local ok, out = Shell.exec("pm list packages")
    if not ok or not out or out == "(dry-run)" then return nil, "Tidak bisa membaca daftar package Android." end

    local found, seen = {}, {}
    for line in out:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(%S+)")
        if pkg and not seen[pkg] then
            local match = pkg:lower():find("roblox", 1, true) ~= nil
                or (prefix ~= "" and pkg:lower():find(prefix, 1, true) == 1)
            if not match then
                local component = APK.resolveLaunchComponent(pkg)
                match = component and component:lower():find("roblox", 1, true) ~= nil
            end
            if match then
                seen[pkg] = true
                found[#found + 1] = pkg
            end
        end
    end
    table.sort(found)
    return found
end

local function addWithPreview(pkg)
    if packageConfigured(pkg) then
        print("Package sudah terdaftar sebagai instance: " .. pkg)
        return
    end
    local name = prompt("Instance name (Enter = " .. pkg .. "): ") or ""
    name = name:match("^%s*(.-)%s*$")
    if name == "" then name = pkg end
    local server = promptGameUrl()
    if not server then print("Add dibatalkan."); return end

    print("\nPreview instance:")
    print("  Name: " .. name)
    print("  Package: " .. pkg)
    print("  Game / Private Server URL: " .. server)
    local confirm = prompt("Save this instance? [y/N]: ") or ""
    if confirm:lower():match("^%s*y") then
        local ok, res = InstanceManager.add({ name = name, package = pkg, privateServer = server })
        if ok then print("Added instance id=" .. tostring(res.id)) else print("Failed to add: " .. tostring(res)) end
    else
        print("Not saved.")
    end
end

local function addInstance()
    print("\nAdd Instance:\n  1) Auto Detect Roblox\n  2) Manual Input\n  0) Cancel")
    local mode = (prompt("Choose a mode: ") or ""):match("^%s*(.-)%s*$")
    if mode == "0" or mode == "" then return end

    if mode == "2" then
        local pkg = (prompt("Package name (e.g. com.roblox.client): ") or ""):match("^%s*(.-)%s*$")
        if pkg == "" then print("Package is required.") else addWithPreview(pkg) end
        return
    end
    if mode ~= "1" then print("Unknown mode."); return end

    local packages, err = detectRobloxPackages()
    if not packages then print(err); return end
    local available = {}
    for _, pkg in ipairs(packages) do
        if packageConfigured(pkg) then
            print("Skip package yang sudah terdaftar: " .. pkg)
        else
            available[#available + 1] = pkg
        end
    end
    packages = available
    if #packages == 0 then print("Tidak ada package baru untuk ditambahkan. Coba Manual Input jika perlu."); return end

    print("Detected Roblox packages:")
    for i, pkg in ipairs(packages) do print(string.format("  %d) %s", i, pkg)) end
    local selection = (prompt("Select package indices (e.g. 1,2) or 'all': ") or ""):lower()
    selection = selection:match("^%s*(.-)%s*$")
    local indices, seen = {}, {}
    if selection == "all" or selection == "a" then
        for i = 1, #packages do indices[#indices + 1] = i end
    else
        for value in selection:gmatch("%d+") do
            local i = tonumber(value)
            if i and packages[i] and not seen[i] then indices[#indices + 1] = i; seen[i] = true end
        end
    end
    if #indices == 0 then print("No valid package selected."); return end

    for _, i in ipairs(indices) do addWithPreview(packages[i]) end
end

function CLI.run()
    while true do
        print("\nInstances Manager:\n  1) List instances\n  2) Add instance\n  3) Edit instance\n  4) Delete instance\n  5) Exit\n")
        local choice = prompt("Choose an option: ") or ""
        choice = choice:match("^%s*(.-)%s*$")
        if choice == "1" then
            printInstances()
        elseif choice == "2" then
            addInstance()
        elseif choice == "3" then
            local id = prompt("Instance id to edit: ") or ""
            id = tonumber(id)
            if not id then print("Invalid id") else
                local inst = InstanceManager.findById(id)
                if not inst then print("Instance not found") else
                    print("Leave blank to keep current value")
                    local name = prompt("Name [" .. tostring(inst.name or "") .. "]: ")
                    local pkg = prompt("Package [" .. tostring(inst.package or "") .. "]: ")
                    local server = prompt("Private Server [" .. tostring(inst.privateServer or "") .. "]: ")
                    local updates = {}
                    if name and name ~= "" then updates.name = name end
                    if pkg and pkg ~= "" then updates.package = pkg end
                    if server and server ~= "" then updates.privateServer = server end
                    if next(updates) == nil then print("No changes") else
                        local ok, res = InstanceManager.update(id, updates)
                        if ok then print("Updated instance id=" .. tostring(res.id)) else print("Failed to update: " .. tostring(res)) end
                    end
                end
            end
        elseif choice == "4" then
            local id = prompt("Instance id to delete: ") or ""
            id = tonumber(id)
            if not id then print("Invalid id") else
                local confirm = prompt("Are you sure? type 'yes' to confirm: ") or ""
                if confirm:lower() == "yes" then
                    local ok, err = InstanceManager.remove(id)
                    if ok then print("Deleted") else print("Failed to delete: " .. tostring(err)) end
                else
                    print("Aborted")
                end
            end
        elseif choice == "5" then
            print("Exiting Instances Manager")
            break
        else
            print("Unknown choice")
        end
    end
end

return CLI
