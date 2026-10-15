-- Turn an update-log file (see tools/update_log_template.lua) into the post text, and
-- optionally send it to a Discord webhook.
--
--   lua tools/update_log.lua <file>                 print the text
--   lua tools/update_log.lua <file> --send <URL>    print + post to that webhook
--   UPDATE_LOG_WEBHOOK=<URL> lua tools/update_log.lua <file> --send
--
-- Sending uses curl. Discord allows 2000 characters per message; a longer log is
-- split at line boundaries into several messages.

local SECTIONS = {
    { key = "added",    title = "Added",    mark = "[ + ]" },
    { key = "improved", title = "Improved", mark = "[ / ]" },
    { key = "fixed",    title = "Fixed",    mark = "[ ! ]" },
    { key = "deleted",  title = "Deleted",  mark = "[ - ]" },
}

local function usage(msg)
    if msg then io.stderr:write(msg .. "\n") end
    io.stderr:write("Pakai: lua tools/update_log.lua <file> [--send <webhook_url>]\n")
    os.exit(1)
end

local file, send, url = nil, false, nil
local i = 1
while arg[i] do
    local a = arg[i]
    if a == "--send" then
        send = true
        if arg[i + 1] and not arg[i + 1]:match("^%-%-") then
            url = arg[i + 1]
            i = i + 1
        end
    elseif not file then
        file = a
    else
        usage("Argumen tidak dikenal: " .. a)
    end
    i = i + 1
end
if not file then usage() end

local ok, log = pcall(dofile, file)
if not ok then usage("File tidak bisa dibaca: " .. tostring(log)) end
if type(log) ~= "table" then usage("File harus berisi: return { ... }") end

local function list(t)
    if type(t) == "string" then return { t } end
    return type(t) == "table" and t or {}
end

local out = {}
local function add(line) out[#out + 1] = line end

add(log.title or "Script Update Logs")
if log.mention and log.mention ~= "" then add(log.mention) end
add("")
if log.place and log.place ~= "" then add("* Place: " .. log.place) end
if log.version and log.version ~= "" then add("* Version: " .. log.version) end

local notes = list(log.notes)
if #notes > 0 then
    add("* Developer Notes:")
    add("")
    for _, n in ipairs(notes) do add(n) end
end

for _, s in ipairs(SECTIONS) do
    local items = list(log[s.key])
    if #items > 0 then
        add("")
        add("* " .. s.title .. ":")
        add("")
        for _, item in ipairs(items) do add(s.mark .. " " .. item) end
    end
end

local text = table.concat(out, "\n")
print(text)

if not send then return end

url = url or os.getenv("UPDATE_LOG_WEBHOOK")
if not url or not url:match("^https://[%w%.%-]+/api/webhooks/") then
    usage("URL webhook tidak valid (https://discord.com/api/webhooks/...)")
end

local function json(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

-- Split into chunks of at most 2000 characters, at line boundaries.
local chunks, cur = {}, ""
for line in (text .. "\n"):gmatch("(.-)\n") do
    local candidate = (cur == "") and line or (cur .. "\n" .. line)
    if #candidate > 1900 and cur ~= "" then
        chunks[#chunks + 1] = cur
        cur = line
    else
        cur = candidate
    end
end
if cur ~= "" then chunks[#chunks + 1] = cur end

local tmp = os.tmpname()
for n, chunk in ipairs(chunks) do
    local f = assert(io.open(tmp, "w"))
    -- allowed_mentions: role / user pings written as <@&id> / <@id> do ping.
    f:write('{"content":' .. json(chunk) .. ',"allowed_mentions":{"parse":["roles","users"]}}')
    f:close()
    local p = io.popen("curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' "
        .. "-X POST --data-binary @" .. tmp .. " '" .. url:gsub("'", "") .. "'")
    local code = p and p:read("*a") or ""
    if p then p:close() end
    if not code:match("^2") then
        os.remove(tmp)
        io.stderr:write(string.format("\nGagal kirim bagian %d/%d (HTTP %s)\n", n, #chunks, code ~= "" and code or "?"))
        os.exit(1)
    end
end
os.remove(tmp)
print(string.format("\nTerkirim ke Discord (%d pesan).", #chunks))
