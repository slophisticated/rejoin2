local InstanceManager = {}

local instances = {}

-- Load instances from provided config table.
-- Iterates with pairs() (not ipairs) and normalizes both integer and string keys, so
-- instances survive a reload even if a previous save wrote string keys like "1".
function InstanceManager.load(config)
    instances = {}
    if config and type(config.instances) == "table" then
        -- The saved config writes explicit keys ([1] = ..), which Lua keeps in the hash
        -- part, so pairs() order is arbitrary: sort by key to keep the Menu 2 order
        -- (launch order and window slots depend on it).
        local keys = {}
        for k in pairs(config.instances) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            local na, nb = tonumber(a), tonumber(b)
            if na and nb then return na < nb end
            if na then return true end
            if nb then return false end
            return tostring(a) < tostring(b)
        end)
        local seen = {}
        for _, k in ipairs(keys) do
            local v = config.instances[k]
            -- key may be an integer (1) or a string ("1"); v is the instance table
            if type(v) == "table" and not seen[v] then
                seen[v] = true
                table.insert(instances, v)
            end
        end
    end
end

-- Which game a clone joins:
--   inst.preset = "<key>"  -> that preset ("khusus")
--   inst.preset = "-"      -> its own privateServer ("link sendiri")
--   inst.preset = nil / "" -> the default preset (config defaultPreset), else its own
--                             privateServer
-- Returns key or nil, source ("khusus" / "default" / "link" / "none"), link or nil.
function InstanceManager.missingPackages()
    local missing = {}
    if #instances == 0 then return missing end
    local ok, out = require("utils.shell").exec("pm list packages")
    if not ok or not out or out == "(dry-run)" then return missing end
    local installed = {}
    for line in out:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(%S+)")
        if pkg then installed[pkg] = true end
    end
    for _, inst in ipairs(instances) do
        if inst.package and inst.package ~= "" and not installed[inst.package] then
            missing[#missing + 1] = { id = inst.id, name = inst.name or inst.package, package = inst.package }
        end
    end
    return missing
end

function InstanceManager.presetOf(inst)
    if type(inst) ~= "table" then return nil, "none", nil end
    local okC, Config = pcall(require, "core.config")
    local conf = okC and Config.get() or {}
    local ps = type(conf.presets) == "table" and conf.presets or {}
    local own = (type(inst.privateServer) == "string" and inst.privateServer ~= "") and inst.privateServer or nil
    local function link(key)
        local p = ps[key]
        return (type(p) == "table" and type(p.link) == "string" and p.link ~= "") and p.link or nil
    end
    local key = inst.preset
    if key == "-" then return nil, own and "link" or "none", own end
    if type(key) == "string" and key ~= "" and link(key) then return key, "khusus", link(key) end
    local def = conf.defaultPreset
    if type(def) == "string" and def ~= "" and link(def) then return def, "default", link(def) end
    if own then return nil, "link", own end
    return nil, "none", nil
end

-- Game link of an instance (see presetOf). nil = no link (launch the app only).
function InstanceManager.gameLink(inst)
    local _, _, link = InstanceManager.presetOf(inst)
    return link
end

-- Readable game name for a link: ".../games/123/Steal-an-Egg" -> "Steal an Egg".
local function nameFromLink(link, fallback)
    local slug = tostring(link or ""):match("/games/%d+/([^/?#]+)")
    if slug and slug ~= "" then return (slug:gsub("[-_]+", " ")) end
    return fallback
end

-- One-time move to presets (update.sh migration): the clones' own links become presets
-- (one per distinct link); the most used one becomes the default, clones on another
-- link get that preset as their own. Own links stay as a fallback. Returns a message,
-- or nil when there is nothing to do.
function InstanceManager.migrateToPresets(conf)
    if type(conf.presets) == "table" and next(conf.presets) ~= nil then return nil end
    local order, count, keyOf = {}, {}, {}
    for _, inst in ipairs(instances) do
        local l = inst.privateServer
        if type(l) == "string" and l ~= "" and (inst.preset == nil or inst.preset == "") then
            if not count[l] then order[#order + 1] = l; count[l] = 0 end
            count[l] = count[l] + 1
        end
    end
    if #order == 0 then return nil end
    local best = order[1]
    for _, l in ipairs(order) do if count[l] > count[best] then best = l end end
    conf.presets = {}
    local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for i, l in ipairs(order) do
        local key = letters:sub(i, i)
        if key == "" then key = "P" .. i end
        keyOf[l] = key
        conf.presets[key] = { name = nameFromLink(l, "Game " .. key), link = l }
    end
    conf.defaultPreset = keyOf[best]
    for _, inst in ipairs(instances) do
        local l = inst.privateServer
        if keyOf[l] and keyOf[l] ~= conf.defaultPreset and (inst.preset == nil or inst.preset == "") then
            inst.preset = keyOf[l]
        end
    end
    conf.instances = instances
    return string.format("%d preset dibuat dari link clone, default %s (%s)", #order,
        conf.defaultPreset, conf.presets[conf.defaultPreset].name)
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
