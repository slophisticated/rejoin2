local Logger = require("core.logger")
local File = require("utils.file")
local Config = require("core.config")

-- AutoExecute manager — manages configuration.
--
-- The user writes `.lua` scripts that Delta executes on launch. Rejoin manages them
-- DIRECTLY inside the app's autoexecute folder (`conf.appAutoExecutePath`, e.g.
-- `/sdcard/Delta/Autoexecute`). No separate staging folder, no deploy step:
-- Add / Edit / Delete write straight to that folder via absolute paths.
--
-- No shell / su is used anywhere in this module: listing is a pure read, and the
-- folder is created lazily on save (File.write ensures its parent dir exists).

local AutoExecute = {}

-- Absolute path of the app autoexecute folder managed by this module.
local function appDir()
    local conf = Config.get() or {}
    local dir = conf.appAutoExecutePath
    if not dir or dir == "" then
        return nil, "appAutoExecutePath is empty (set it in config/config.lua)"
    end
    -- Expect absolute paths. Relative paths break when commands later run through
    -- su -c (whose working dir is /, not the Lua cwd).
    if not dir:match("^/") then
        Logger.warn("AutoExecute: appAutoExecutePath should be absolute (got: " .. tostring(dir) .. ")")
    end
    return dir
end

-- List scripts (names of *.lua) in the app autoexecute folder.
function AutoExecute.list()
    local dir, err = appDir()
    if not dir then return nil, err end
    local names, lerr = File.listDir(dir, "lua")
    if not names then return nil, lerr end
    local out = {}
    for _, n in ipairs(names) do
        local p = dir .. "/" .. n
        local size = 0
        local content = File.read(p)
        if content then size = #content end
        table.insert(out, { name = n, size = size, path = p })
    end
    return out
end

-- Save (create or overwrite) a script directly into the app folder.
function AutoExecute.save(name, content)
    name = name and name:gsub("[^%w%._%-]", "_") or ""
    name = name:gsub("%.lua$", "")
    if name == "" then return false, "invalid_name" end
    local dir, err = appDir()
    if not dir then return false, err end
    local file = dir .. "/" .. name .. ".lua"
    local ok, werr = File.write(file, content)
    if not ok then return false, werr or "write_failed" end
    Logger.info(string.format("AutoExecute: saved %s", file))
    return true, file
end

-- Read a script's content back.
function AutoExecute.read(name)
    name = name and name:gsub("%.lua$", "") or ""
    if name == "" then return nil, "invalid_name" end
    local dir, err = appDir()
    if not dir then return nil, err end
    return File.read(dir .. "/" .. name .. ".lua")
end

-- Remove a script from the app folder. Returns (true) or (false, err).
function AutoExecute.remove(name)
    name = name and name:gsub("%.lua$", "") or ""
    if name == "" then return false, "invalid_name" end
    local dir, err = appDir()
    if not dir then return false, err end
    local file = dir .. "/" .. name .. ".lua"
    if not File.exists(file) then return false, "not_found" end
    local ok = os.remove(file)
    if not ok then return false, "remove_failed" end
    Logger.info(string.format("AutoExecute: removed %s", file))
    return true
end

-- Scripts folder ------------------------------------------------------------------
-- Delta keeps a "Scripts" folder (a library run by hand) next to "Autoexecute". The
-- bot and Menu 4 store scripts there; Autoexecute only ever gets a COPY of a script
-- from Scripts (autoAdd) and loses it again with autoRemove — scripts are never
-- written straight into Autoexecute. The Delta folder is shared by every clone on the
-- device, so all of this applies to all clones at once.

local MAX_SIZE = 200 * 1024
local MANAGED = { ["rejoin_heartbeat.lua"] = true }
AutoExecute.MAX_SIZE = MAX_SIZE

local function isDir(path)
    local p = io.popen("[ -d '" .. path:gsub("'", "'\\''") .. "' ] && echo Y")
    local out = p and p:read("*a") or ""
    if p then p:close() end
    return out:find("Y", 1, true) ~= nil
end

-- Absolute path of the Scripts folder (config scriptsPath, else Scripts / scripts next
-- to the Autoexecute folder; the first is used when neither exists yet).
function AutoExecute.scriptsDir()
    local conf = Config.get() or {}
    if type(conf.scriptsPath) == "string" and conf.scriptsPath ~= "" then
        return (conf.scriptsPath:gsub("/+$", ""))
    end
    local ae, err = appDir()
    if not ae then return nil, err end
    local parent = ae:gsub("/+$", ""):match("^(.*)/[^/]+$") or ae
    for _, n in ipairs({ "Scripts", "scripts" }) do
        if isDir(parent .. "/" .. n) then return parent .. "/" .. n end
    end
    return parent .. "/Scripts"
end

-- "egg farm" -> nil; "egg_farm" -> "egg_farm.lua"; "x.txt" stays. nil, err when invalid.
local function cleanName(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or not name:match("^[%w_%-%.]+$") or name:match("^%.") or #name > 64 then
        return nil, "nama script hanya huruf/angka/_-. (maks 64)"
    end
    if not name:match("%.lua$") and not name:match("%.txt$") then name = name .. ".lua" end
    return name
end
AutoExecute.cleanName = cleanName

local function scriptFiles(dir)
    local out = {}
    local names = dir and File.listDir(dir) or nil
    for _, n in ipairs(names or {}) do
        if n:match("%.lua$") or n:match("%.txt$") then
            local c = File.read(dir .. "/" .. n)
            out[#out + 1] = { name = n, size = c and #c or 0 }
        end
    end
    return out
end

-- Scripts folder: { name, size, auto } (auto = also in Autoexecute).
function AutoExecute.scriptsList()
    local sd, err = AutoExecute.scriptsDir()
    if not sd then return nil, err end
    local ae = appDir()
    local list = scriptFiles(sd)
    for _, e in ipairs(list) do e.auto = ae and File.exists(ae .. "/" .. e.name) or false end
    return list
end

-- Autoexecute folder: { name, size, fromScripts, managed }.
function AutoExecute.autoList()
    local ae, err = appDir()
    if not ae then return nil, err end
    local sd = AutoExecute.scriptsDir()
    local list = scriptFiles(ae)
    for _, e in ipairs(list) do
        e.managed = MANAGED[e.name] or false
        e.fromScripts = sd and File.exists(sd .. "/" .. e.name) or false
    end
    return list
end

-- Save into Scripts. When the script is also in Autoexecute its copy there is
-- refreshed so both stay the same. Returns name, replaced(bool), autoUpdated(bool).
function AutoExecute.scriptSave(name, content)
    local n, err = cleanName(name)
    if not n then return nil, err end
    if MANAGED[n] then return nil, n .. " diatur rejoin (heartbeat), pakai nama lain" end
    content = tostring(content or "")
    if content:match("^%s*$") then return nil, "isi script kosong" end
    if #content > MAX_SIZE then return nil, "script terlalu besar (maks 200 KB)" end
    local sd, derr = AutoExecute.scriptsDir()
    if not sd then return nil, derr end
    local path = sd .. "/" .. n
    local replaced = File.exists(path)
    local ok, werr = File.write(path, content)
    if not ok then return nil, "gagal menulis " .. path .. ": " .. tostring(werr) end
    local autoUpdated = false
    local ae = appDir()
    if ae and File.exists(ae .. "/" .. n) then
        autoUpdated = File.write(ae .. "/" .. n, content) and true or false
    end
    Logger.info("Scripts: saved " .. path)
    return n, replaced, autoUpdated
end

function AutoExecute.scriptRead(name)
    local n, err = cleanName(name)
    if not n then return nil, err end
    local sd = AutoExecute.scriptsDir()
    local c = sd and File.read(sd .. "/" .. n)
    if not c then return nil, "script " .. n .. " tidak ada di Scripts" end
    return c, n
end

-- Remove from Scripts only. Returns name, stillInAutoexecute(bool).
function AutoExecute.scriptRemove(name)
    local n, err = cleanName(name)
    if not n then return nil, err end
    local sd = AutoExecute.scriptsDir()
    local path = sd and (sd .. "/" .. n)
    if not path or not File.exists(path) then return nil, "script " .. n .. " tidak ada di Scripts" end
    if not os.remove(path) then return nil, "gagal menghapus " .. n end
    local ae = appDir()
    Logger.info("Scripts: removed " .. path)
    return n, ae and File.exists(ae .. "/" .. n) or false
end

-- Copy a script from Scripts into Autoexecute.
function AutoExecute.autoAdd(name)
    local n, err = cleanName(name)
    if not n then return nil, err end
    if MANAGED[n] then return nil, n .. " diatur rejoin" end
    local c, rerr = AutoExecute.scriptRead(n)
    if not c then return nil, rerr end
    local ae, aerr = appDir()
    if not ae then return nil, aerr end
    local ok, werr = File.write(ae .. "/" .. n, c)
    if not ok then return nil, "gagal menyalin ke Autoexecute: " .. tostring(werr) end
    Logger.info("AutoExecute: copied " .. n .. " from Scripts")
    return n
end

-- Remove a script's copy from Autoexecute (the one in Scripts stays).
function AutoExecute.autoRemove(name)
    local n, err = cleanName(name)
    if not n then return nil, err end
    if MANAGED[n] then return nil, n .. " diatur rejoin (matikan lewat setting heartbeat)" end
    local ae, aerr = appDir()
    if not ae then return nil, aerr end
    if not File.exists(ae .. "/" .. n) then return nil, n .. " tidak ada di Autoexecute" end
    if not os.remove(ae .. "/" .. n) then return nil, "gagal menghapus " .. n .. " dari Autoexecute" end
    Logger.info("AutoExecute: removed " .. n)
    return n
end

-- One-line loader for a script hosted at an https URL.
function AutoExecute.loaderFor(url)
    url = tostring(url or "")
    if not url:match("^https://[%w%.%-]+/") or url:find('["\\%c]') then return nil, "URL harus https:// yang valid" end
    return 'loadstring(game:HttpGet("' .. url .. '"))()'
end

return AutoExecute