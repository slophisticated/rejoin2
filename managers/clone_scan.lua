local Logger = require("core.logger")
local Shell = require("utils.shell")

-- Find the Roblox clones that are actually installed on THIS device, and repair a
-- config whose package names came from another device.
--
-- Configs copied from another device can name packages that never existed here.
-- Package names alone do not identify Roblox; renamed apps need activity checks.
--
-- Detection is read-only; only fix() writes, and only to the in-memory config.

local CloneScan = {}

local function validPackageName(p)
    return type(p) == "string" and p:match("^[%a_][%w_%.]*$") ~= nil
end

local function addSet(set, pkg)
    if validPackageName(pkg) then set[pkg] = true end
end

-- Package names from one probe, or nil when the probe itself failed.
local function probe(cmd, pattern)
    local ok, out = Shell.exec(cmd)
    if not ok or out == nil then return nil end
    local found = {}
    for line in out:gmatch("[^\r\n]+") do
        local pkg = line:match(pattern)
        if pkg then addSet(found, pkg) end
    end
    return found
end

-- Every installed package, merged from several probes. nil = every probe failed.
-- Do not use -u: it includes uninstalled packages with leftover data.
function CloneScan.listInstalled()
    local merged = {}
    local anyOk = false
    local probes = {
        { "pm list packages", "package:(%S+)" },
        { "cmd package list packages", "package:(%S+)" },
    }
    for _, p in ipairs(probes) do
        local found = probe(p[1], p[2])
        if found then
            anyOk = true
            for pkg in pairs(found) do merged[pkg] = true end
        end
    end
    if not anyOk then return nil end
    return merged
end

-- Is one package installed? true / false / nil (could not tell).
function CloneScan.isInstalled(pkg, installed)
    if not validPackageName(pkg) then return false end
    if installed and installed[pkg] then return true end
    if installed then return false end
    return nil
end

-- Launcher components in one bulk call: clones keep Roblox's activity class even
-- though the package is renamed, so the component is a reliable clone fingerprint.
local function robloxComponents()
    local ok, out = Shell.exec("cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER")
    if not ok or not out then return {} end
    local found = {}
    for pkg, comp in out:gmatch("([%a_][%w_%.]*)/([^%s]+)") do
        if comp:lower():find("roblox", 1, true) then addSet(found, pkg) end
    end
    return found
end

-- Installed packages that look like Roblox clones, sorted.
-- `prefix` (config.clonePackagePrefix) is the fast, explicit filter.
function CloneScan.scanClones(prefix, installed)
    installed = installed or CloneScan.listInstalled()
    if not installed then return nil, "detection_failed" end

    local found = {}
    for pkg in pairs(installed) do
        if pkg:lower():find("roblox", 1, true) then addSet(found, pkg) end
    end
    if prefix and prefix ~= "" then
        for pkg in pairs(installed) do
            if pkg:lower():find(prefix:lower(), 1, true) == 1 then addSet(found, pkg) end
        end
    end
    for pkg in pairs(robloxComponents()) do
        if installed[pkg] then addSet(found, pkg) end
    end

    -- Resolve the remaining packages too: finding the original Roblox app does not
    -- mean renamed clones have all been found.
    if not prefix or prefix == "" then
        for pkg in pairs(installed) do
            if not found[pkg] then
                local ok, comp = pcall(function() return require("managers.apk").resolveLaunchComponent(pkg) end)
                if ok and type(comp) == "string" and comp:lower():find("roblox", 1, true) then addSet(found, pkg) end
            end
        end
    end

    local list = {}
    for pkg in pairs(found) do list[#list + 1] = pkg end
    table.sort(list)
    return list
end

-- Prefix family of a package ("com.apengjers.v3" -> "com.apengjers.").
local function family(pkg)
    return tostring(pkg or ""):match("^(.*%.)")
end

-- Repair config.instances in place: a package that is not installed is repointed at
-- an unused detected clone (same prefix family first). Returns one result per
-- instance: { kind = "ok" | "fix" | "missing", pkg = ..., from = ..., to = ... }.
-- nil + reason when detection itself failed (so callers do not "fix" blind).
function CloneScan.fix(conf)
    local installed = CloneScan.listInstalled()
    if not installed then return nil, "detection_failed" end
    local clones, err = CloneScan.scanClones(conf.clonePackagePrefix, installed)
    if not clones then return nil, err end

    local used = {}
    for _, inst in ipairs(conf.instances or {}) do
        if type(inst) == "table" and inst.package then used[inst.package] = true end
    end
    local free = {}
    for _, pkg in ipairs(clones) do
        if not used[pkg] then free[#free + 1] = pkg end
    end

    local results = {}
    for _, inst in ipairs(conf.instances or {}) do
        if type(inst) == "table" then
            local pkg = inst.package
            if CloneScan.isInstalled(pkg, installed) then
                results[#results + 1] = { kind = "ok", pkg = pkg }
            else
                local pick
                local fam = family(pkg)
                for i, candidate in ipairs(free) do
                    if fam and family(candidate) == fam then pick = i break end
                end
                pick = pick or (#free > 0 and 1 or nil)
                if pick then
                    local replacement = table.remove(free, pick)
                    inst.package = replacement
                    -- Identity paths belong to the old app/account, not the new clone.
                    inst.cookiePath = nil
                    inst.usernamePath = nil
                    results[#results + 1] = { kind = "fix", from = pkg, to = replacement }
                    Logger.info("CloneScan: " .. tostring(pkg) .. " -> " .. replacement)
                else
                    results[#results + 1] = { kind = "missing", pkg = pkg }
                end
            end
        end
    end
    return results
end

return CloneScan
