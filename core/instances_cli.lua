local Logger = require("core.logger")
local InstanceManager = require("managers.instance")

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
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

function CLI.run()
    while true do
        print("\nInstances Manager:\n  1) List instances\n  2) Add instance\n  3) Edit instance\n  4) Delete instance\n  5) Exit\n")
        local choice = prompt("Choose an option: ") or ""
        choice = choice:match("^%s*(.-)%s*$")
        if choice == "1" then
            printInstances()
        elseif choice == "2" then
            local pkg = prompt("Package name (e.g. com.roblox.client): ") or ""
            pkg = pkg:match("^%s*(.-)%s*$")
            if pkg == "" then print("Package is required.") else
                local name = prompt("Instance name (press Enter to use package): ") or ""
                if name == "" then name = pkg end
                local server = prompt("Private Server URL (optional): ") or ""
                if server == "" then server = nil end
                local ok, res = InstanceManager.add({ name = name, package = pkg, privateServer = server })
                if ok then print("Added instance id=" .. tostring(res.id)) else print("Failed to add: " .. tostring(res)) end
            end
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
