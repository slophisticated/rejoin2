local Logger = require("core.logger")
local InstanceManager = require("managers.instance")

local CLI = {}

local function prompt(msg)
    io.write(msg)
    io.flush()
    return io.read()
end

local SOURCE_LABEL = { khusus = "khusus", default = "ikut default", link = "link sendiri", none = "belum ada link" }

local function gameLabel(inst)
    local key, source = InstanceManager.presetOf(inst)
    local okC, Config = pcall(require, "core.config")
    local ps = okC and type(Config.get().presets) == "table" and Config.get().presets or {}
    local game = key and ("[" .. key .. "] " .. tostring(ps[key] and ps[key].name or "")) or (source == "link" and tostring(inst.privateServer) or "-")
    return game .. " (" .. (SOURCE_LABEL[source] or source) .. ")"
end

-- Ask how a clone picks its game. Returns the fields to set, or nil to keep.
-- New clone: Enter = follow the default preset. Edit: Enter = keep, "d" = follow the
-- default. A preset key = that preset; "-" = own link.
local function askGame(inst)
    local okC, Config = pcall(require, "core.config")
    local conf = okC and Config.get() or {}
    local ps = type(conf.presets) == "table" and conf.presets or {}
    local keys = {}
    for k in pairs(ps) do keys[#keys + 1] = k end
    table.sort(keys)
    local def = conf.defaultPreset
    if #keys == 0 then
        local server = prompt("Link game / private server (kosong = nanti; atur preset di Main Menu 11): ") or ""
        server = server:match("^%s*(.-)%s*$")
        if server == "" then return nil end
        return { privateServer = server, preset = "-" }
    end
    print("Preset: " .. table.concat(keys, ", ") .. ((def and def ~= "") and ("  (default: " .. def .. ")") or ""))
    local v
    if inst then
        v = prompt("Game: Enter = tetap, 'd' = ikut default, kode preset = khusus, '-' = link sendiri: ") or ""
    else
        v = prompt("Game: Enter = ikut default, kode preset = khusus, '-' = link sendiri: ") or ""
    end
    v = v:match("^%s*(.-)%s*$")
    if v == "" then return inst and nil or {} end
    if v == "d" or v == "D" then return { preset = "" } end
    if v == "-" then
        local server = prompt("Link sendiri [" .. tostring(inst and inst.privateServer or "") .. "]: ") or ""
        server = server:match("^%s*(.-)%s*$")
        if server == "" and not (inst and inst.privateServer) then print("Link kosong, tetap ikut default."); return {} end
        return { preset = "-", privateServer = server ~= "" and server or nil }
    end
    if ps[v] then return { preset = v } end
    print("Preset '" .. v .. "' tidak ada; ikut default.")
    return {}
end

local function printInstances()
    local list = InstanceManager.getAll()
    if #list == 0 then
        print("(no instances configured)")
        return
    end
    print("Instances:")
    for _, inst in ipairs(list) do
        print(string.format("  id=%s name=%s package=%s game=%s", tostring(inst.id), tostring(inst.name or ""),
            tostring(inst.package or ""), gameLabel(inst)))
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
                local inst = { name = name, package = pkg }
                for k, v in pairs(askGame(nil) or {}) do inst[k] = v end
                if inst.preset == "" then inst.preset = nil end
                local ok, res = InstanceManager.add(inst)
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
                    print("Game sekarang: " .. gameLabel(inst))
                    local game = askGame(inst)
                    local updates = {}
                    if name and name ~= "" then updates.name = name end
                    if pkg and pkg ~= "" then updates.package = pkg end
                    if game then
                        for k, v in pairs(game) do updates[k] = v end
                    end
                    -- An empty preset means follow default. Keep the update explicit
                    -- so changing only this field still reaches persist().
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
