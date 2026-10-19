-- JSON helper: prefer cjson if available, else a small pure-Lua encoder/decoder
-- (enough for the remote bot protocol: objects, arrays, strings, numbers, booleans).
local ok, cjson = pcall(require, "cjson")
local JSON = {}

-- Mark a table as a JSON array (so an empty table encodes as [] instead of {}).
local ARRAY = setmetatable({}, { __mode = "k" })
function JSON.array(t)
    t = t or {}
    ARRAY[t] = true
    return t
end

if ok and cjson then
    function JSON.encode(t) return cjson.encode(t) end
    function JSON.decode(s)
        local okD, v = pcall(cjson.decode, s)
        if okD then return v end
        return nil, tostring(v)
    end
    return JSON
end

local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
              ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESC[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function isArray(t)
    if ARRAY[t] then return true end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    return n > 0 and n == #t
end

local encode
encode = function(v, seen)
    local tp = type(v)
    if tp == "nil" then return "null" end
    if tp == "boolean" then return tostring(v) end
    if tp == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v % 1 == 0 and v >= -2^53 and v <= 2^53 then return string.format("%d", v) end
        return string.format("%.14g", v)
    end
    if tp == "string" then return encodeString(v) end
    if tp == "table" then
        seen = seen or {}
        if seen[v] then error("JSON.encode: circular table") end
        seen[v] = true
        local parts = {}
        if isArray(v) then
            for i = 1, #v do parts[#parts + 1] = encode(v[i], seen) end
            seen[v] = nil
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local val = v[k]
            if val == nil then val = v[tonumber(k)] end
            if type(val) ~= "function" then
                parts[#parts + 1] = encodeString(k) .. ":" .. encode(val, seen)
            end
        end
        seen[v] = nil
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

function JSON.encode(v) return encode(v) end

-- Decoder ------------------------------------------------------------------------
local function decodeError(s, i, msg)
    error(string.format("JSON.decode: %s at %d", msg, i), 0)
end

local function skip(s, i)
    return s:find("[^ \t\r\n]", i) or #s + 1
end

local decodeValue

local function decodeString(s, i)
    local out, j = {}, i + 1
    while true do
        local c = s:sub(j, j)
        if c == "" then decodeError(s, j, "unterminated string") end
        if c == '"' then return table.concat(out), j + 1 end
        if c == "\\" then
            local e = s:sub(j + 1, j + 1)
            local map = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
            if map[e] then
                out[#out + 1] = map[e]
                j = j + 2
            elseif e == "u" then
                local hex = s:sub(j + 2, j + 5)
                local cp = tonumber(hex, 16)
                if not cp then decodeError(s, j, "bad \\u escape") end
                j = j + 6
                -- surrogate pair
                if cp >= 0xD800 and cp <= 0xDBFF and s:sub(j, j + 1) == "\\u" then
                    local lo = tonumber(s:sub(j + 2, j + 5), 16)
                    if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                        j = j + 6
                    end
                end
                out[#out + 1] = utf8.char(cp)
            else
                decodeError(s, j, "bad escape")
            end
        else
            local k = s:find('["\\]', j) or #s + 1
            out[#out + 1] = s:sub(j, k - 1)
            j = k
        end
    end
end

decodeValue = function(s, i)
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "{" then
        local obj = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            if s:sub(i, i) ~= '"' then decodeError(s, i, "expected key") end
            local key
            key, i = decodeString(s, i)
            i = skip(s, i)
            if s:sub(i, i) ~= ":" then decodeError(s, i, "expected ':'") end
            local val
            val, i = decodeValue(s, i + 1)
            obj[key] = val
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "}" then return obj, i + 1 end
            if d ~= "," then decodeError(s, i, "expected ',' or '}'") end
            i = skip(s, i + 1)
        end
    elseif c == "[" then
        local arr = JSON.array({})
        i = skip(s, i + 1)
        if s:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            local val
            val, i = decodeValue(s, i)
            arr[#arr + 1] = val
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "]" then return arr, i + 1 end
            if d ~= "," then decodeError(s, i, "expected ',' or ']'") end
            i = i + 1
        end
    elseif c == '"' then
        return decodeString(s, i)
    elseif s:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif s:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif s:sub(i, i + 3) == "null" then
        return nil, i + 4
    else
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
        if not num or num == "" then decodeError(s, i, "unexpected character") end
        return tonumber(num), i + #num
    end
end

-- Returns the value, or nil plus an error message.
function JSON.decode(s)
    if type(s) ~= "string" then return nil, "not a string" end
    local okD, v, i = pcall(decodeValue, s, 1)
    if not okD then return nil, tostring(v) end
    if skip(s, i) <= #s then return nil, "trailing data" end
    return v
end

return JSON
