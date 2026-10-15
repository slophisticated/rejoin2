local InstanceManager = {}

local instances = {}

-- Load instances from provided config table.
-- Iterates with pairs() (not ipairs) and normalizes both integer and string keys, so
-- instances survive a reload even if a previous save wrote string keys like "1".
function InstanceManager.load(config)
    instances = {}
    if config and type(config.instances) == "table" then
        local seen = {}
        for k, v in pairs(config.instances) do
            -- key may be an integer (1) or a string ("1"); v is the instance table
            if type(v) == "table" and not seen[v] then
                seen[v] = true
                table.insert(instances, v)
            end
        end
    end
end

function InstanceManager.getAll()
    return instances
end

function InstanceManager.count()
    return #instances
end

-- Which configured packages are not installed on this device?
-- A leftover placeholder from the config template (com.roblox.client) is the usual
-- cause: it looks like a real instance but can never run. Best-effort: one
-- `pm list packages` call; on failure we report nothing rather than guessing.
function InstanceManager.missingPackages()
    local missing = {}
    if #instances == 0 then return missing end

    local Shell = require("utils.shell")
    local _, out = Shell.exec("pm list packages")
    if not out or out == "(dry-run)" then return missing end

    local installed = {}
    for line in out:gmatch("[^\n]+") do
        local pkg = line:match("package:(%S+)")
        if pkg then installed[pkg] = true end
    end

    for _, inst in ipairs(instances) do
        local pkg = inst and inst.package
        if pkg and pkg ~= "" and not installed[pkg] then
            missing[#missing + 1] = { id = inst.id, name = inst.name or pkg, package = pkg }
        end
    end
    return missing
end

function InstanceManager.findById(id)
    for _, v in ipairs(instances) do
        if v.id == id then return v end
    end
    return nil
end

local function persist()
    local Config = require("core.config")
    local conf = Config.get() or {}
    conf.instances = instances
    return Config.save(conf)
end

function InstanceManager.add(instance)
    instance = instance or {}
    -- compute next id
    local maxid = 0
    for _, v in ipairs(instances) do
        if type(v.id) == "number" and v.id > maxid then maxid = v.id end
    end
    instance.id = (instance.id and tonumber(instance.id)) or (maxid + 1)

    table.insert(instances, instance)
    local ok, err = persist()
    if not ok then return false, err end
    return true, instance
end

function InstanceManager.update(id, updates)
    id = tonumber(id)
    local inst = InstanceManager.findById(id)
    if not inst then return false, "not_found" end
    for k, v in pairs(updates) do inst[k] = v end
    local ok, err = persist()
    if not ok then return false, err end
    return true, inst
end

function InstanceManager.remove(id)
    id = tonumber(id)
    for i, v in ipairs(instances) do
        if v.id == id then
            table.remove(instances, i)
            local ok, err = persist()
            if not ok then return false, err end
            return true
        end
    end
    return false, "not_found"
end

return InstanceManager