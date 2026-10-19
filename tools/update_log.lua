-- Turn an update-log file (see tools/update_log_template.lua) into a Discord post.
--
--   lua tools/update_log.lua <file>                 preview the text
--   lua tools/update_log.lua <file> --send <URL>    preview + post to that webhook
--   UPDATE_LOG_WEBHOOK=<URL> lua tools/update_log.lua <file> --send
--
-- The post is a components message (Components V2): two boxes with a colored bar,
-- the header (title, version, notes) and the body (Added / Improved / ...), sent through the webhook with ?with_components=true.
-- If Discord refuses it, the same text is sent as a plain message instead.
-- Sending uses curl.

local SECTIONS = {
    { key = "added",    title = "Added",    mark = "[ + ]" },
    { key = "improved", title = "Improved", mark = "[ / ]" },
    { key = "fixed",    title = "Fixed",    mark = "[ ! ]" },
    { key = "deleted",  title = "Deleted",  mark = "[ - ]" },
}
local IS_COMPONENTS_V2 = 32768
local TEXT_LIMIT = 3800 -- Discord: 4000 characters of text per components message

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

-- Two boxes: the header (title, mention, version, notes) and the body (sections).
-- A block is { text = "..." } or { separator = true }.
local header, body = {}, {}
local function text(t, s) t[#t + 1] = { text = s } end
local function separator(t) t[#t + 1] = { separator = true } end

local head = "# " .. (log.title or "Rejoin Update Logs")
if log.mention and log.mention ~= "" then head = head .. "\n" .. log.mention end
text(header, head)

local info = {}
if log.version and log.version ~= "" then info[#info + 1] = "**Version:** " .. log.version end
local notes = list(log.notes)
if #notes > 0 then
    info[#info + 1] = "**Developer Notes:**"
    for _, n in ipairs(notes) do info[#info + 1] = n end
end
if #info > 0 then
    separator(header)
    text(header, table.concat(info, "\n"))
end

for _, s in ipairs(SECTIONS) do
    local items = list(log[s.key])
    if #items > 0 then
        local lines = { "### " .. s.title }
        for _, item in ipairs(items) do lines[#lines + 1] = s.mark .. " " .. item end
        if #body > 0 then separator(body) end
        text(body, table.concat(lines, "\n"))
    end
end

-- Preview in the terminal.
local function preview(t)
    for _, b in ipairs(t) do
        if b.separator then print("────────────────────") else print(b.text) end
    end
end
preview(header)
if #body > 0 then
    print("════════════════════")
    preview(body)
end

if not send then return end

url = url or os.getenv("UPDATE_LOG_WEBHOOK")
if not url or not url:match("^https://[%w%.%-]+/api/webhooks/") then
    usage("URL webhook tidak valid (https://discord.com/api/webhooks/...)")
end
url = url:gsub("'", ""):gsub("%?.*$", "")

local function json(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

-- Messages: the first carries the header box; the body box is split across messages
-- when it would pass Discord's text limit.
local function textSize(t)
    local n = 0
    for _, b in ipairs(t) do n = n + (b.text and #b.text or 0) end
    return n
end
local messages = {}
local cur, size = {}, textSize(header)
for _, b in ipairs(body) do
    local len = b.text and #b.text or 0
    if b.text and size + len > TEXT_LIMIT and #cur > 0 then
        while #cur > 0 and cur[#cur].separator do cur[#cur] = nil end
        messages[#messages + 1] = { body = cur }
        cur, size = {}, 0
    end
    if not (b.separator and #cur == 0) then
        cur[#cur + 1] = b
        size = size + len
    end
end
if #cur > 0 or #messages == 0 then messages[#messages + 1] = { body = cur } end
messages[1].header = header

local color = tonumber(log.color) or 0x5865F2
local mentions = ',"allowed_mentions":{"parse":["roles","users"]}'

local function container(t)
    local parts = {}
    for _, b in ipairs(t) do
        if b.separator then
            parts[#parts + 1] = '{"type":14,"divider":true,"spacing":1}'
        else
            parts[#parts + 1] = '{"type":10,"content":' .. json(b.text) .. '}'
        end
    end
    return '{"type":17,"accent_color":' .. math.floor(color)
        .. ',"components":[' .. table.concat(parts, ",") .. ']}'
end

local function componentsPayload(msg)
    local boxes = {}
    if msg.header then boxes[#boxes + 1] = container(msg.header) end
    if #msg.body > 0 then boxes[#boxes + 1] = container(msg.body) end
    return '{"flags":' .. IS_COMPONENTS_V2 .. mentions
        .. ',"components":[' .. table.concat(boxes, ",") .. ']}'
end

local function plainPayload(msg)
    local lines = {}
    for _, part in ipairs({ msg.header or {}, msg.body }) do
        if #lines > 0 and #part > 0 then lines[#lines + 1] = "" end
        for _, b in ipairs(part) do lines[#lines + 1] = b.separator and "" or b.text end
    end
    return '{"content":' .. json(table.concat(lines, "\n"):sub(1, 2000)) .. mentions .. '}'
end

local tmp = os.tmpname()
local function post(payload, target)
    local f = assert(io.open(tmp, "w"))
    f:write(payload)
    f:close()
    local p = io.popen("curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' "
        .. "-X POST --data-binary @" .. tmp .. " '" .. target .. "'")
    local code = p and p:read("*a") or ""
    if p then p:close() end
    return code
end

local plain = false
for n, msg in ipairs(messages) do
    local code = plain and post(plainPayload(msg), url)
        or post(componentsPayload(msg), url .. "?with_components=true")
    if not plain and code:match("^4") then
        io.stderr:write("Discord menolak format components (HTTP " .. code .. "); dikirim sebagai pesan biasa.\n")
        plain = true
        code = post(plainPayload(msg), url)
    end
    if not code:match("^2") then
        os.remove(tmp)
        io.stderr:write(string.format("\nGagal kirim bagian %d/%d (HTTP %s)\n", n, #messages, code ~= "" and code or "?"))
        os.exit(1)
    end
end
os.remove(tmp)
print(string.format("\nTerkirim ke Discord (%d pesan%s).", #messages, plain and ", format biasa" or ""))
