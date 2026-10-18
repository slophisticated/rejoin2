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

-- Game link of an instance: its preset's link (config `presets`) when it has one,
-- else its own privateServer. nil = no link (launch the app only).
function InstanceManager.gameLink(inst)
    if type(inst) ~= "table" then return nil end
    local key = inst.preset
    if type(key) == "string" and key ~= "" then
        local okC, Config = pcall(require, "core.config")
        local conf = okC and Config.get() or {}
        local p = type(conf.presets) == "table" and conf.presets[key] or nil
        if type(p) == "table" and type(p.link) == "string" and p.link ~= "" then return p.link end
    end
    if type(inst.privateServer) == "string" and inst.privateServer ~= "" then return inst.privateServer end
    return nil
end

-- Find an instance by id (number or "3"), name, package or username-free label.
function InstanceManager.find(ref)
    if ref == nil then return nil end
    local n = tonumber(ref)
    for _, v in ipairs(instances) do
        if (n and v.id == n) or v.name == ref or v.package == ref then return v end
    end
    local low = tostring(ref):lower()
    for _, v in ipairs(instances) do
        if tostring(v.name or ""):lower() == low then return v end
    end
    return nil
end

-- Save the current instance list to config/config.lua.
function InstanceManager.save()
    local Config = require("core.config")
    local conf = Config.get() or {}
    conf.instances = instances
    return Config.save(conf)
end

function InstanceManager.getAll()
    return instances
end

function InstanceManager.count()
    return #instances
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