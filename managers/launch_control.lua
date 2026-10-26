-- Session-scoped controls shared by the dashboard and a second Termux menu.
local File = require("utils.file")
local Json = require("utils.json")
local Control = {}
local STATE = "data/launch_wait.json"
local ACTION = "data/launch_action.json"
local serial = 0

function Control.clear()
    os.remove(STATE)
    os.remove(ACTION)
end

function Control.read()
    local ok, state = pcall(Json.decode, File.read(STATE) or "")
    if ok and type(state) == "table" then return state end
end

function Control.publish(instance, reason, token)
    if not token then
        serial = serial + 1
        token = tostring(os.time()) .. ":" .. tostring(serial) .. ":" .. instance.package
    end
    File.write(STATE, Json.encode({ token = token, name = instance.name or instance.package,
        package = instance.package, reason = reason }))
    return token
end

function Control.request(action, expectedToken)
    if action ~= "skip" and action ~= "cancel" then return false, "tindakan tidak valid" end
    local state = Control.read()
    if not state then return false, "Tidak ada clone yang sedang ditunggu." end
    if expectedToken and state.token ~= expectedToken then return false, "Clone yang ditunggu sudah berubah." end
    return File.write(ACTION, Json.encode({ token = state.token, action = action }))
end

function Control.take(token)
    local text = File.read(ACTION)
    if not text then return end
    os.remove(ACTION)
    local ok, action = pcall(Json.decode, text)
    if ok and type(action) == "table" and action.token == token then return action.action end
end

return Control
