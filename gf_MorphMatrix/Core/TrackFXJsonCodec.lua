-- @noindex

local TrackFXJsonCodec = {}

local function encode_string(value)
    local escapes = {
        ["\""] = "\\\"",
        ["\\"] = "\\\\",
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t",
    }

    return '"' .. value:gsub('[%z\1-\31"\\]', function(character)
        return escapes[character] or string.format("\\u%04x", character:byte())
    end) .. '"'
end

local function is_array(value)
    local length = #value
    if length == 0 then
        return false
    end

    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > length or key ~= math.floor(key) then
            return false
        end
    end

    return true
end

local encode_value
encode_value = function(value)
    local value_type = type(value)
    if value == nil then
        return "null"
    end
    if value_type == "boolean" then
        return value and "true" or "false"
    end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return string.format("%.14g", value)
    end
    if value_type == "string" then
        return encode_string(value)
    end
    if value_type ~= "table" then
        return "null"
    end

    if is_array(value) then
        local values = {}
        for index = 1, #value do
            values[index] = encode_value(value[index])
        end
        return "[" .. table.concat(values, ",") .. "]"
    end

    local fields = {}
    for key, field_value in pairs(value) do
        if type(key) == "string" then
            fields[#fields + 1] = encode_string(key) .. ":" .. encode_value(field_value)
        end
    end
    return "{" .. table.concat(fields, ",") .. "}"
end

function TrackFXJsonCodec.encode(value)
    return encode_value(value)
end

function TrackFXJsonCodec.decode(serialized)
    if type(serialized) ~= "string" then
        error("JSON input must be a string")
    end

    local position = 1

    local function skip_whitespace()
        position = serialized:match("^%s*()", position)
    end

    local function current_character()
        skip_whitespace()
        return serialized:sub(position, position)
    end

    local function consume(character)
        skip_whitespace()
        if serialized:sub(position, position) ~= character then
            error("JSON expected '" .. character .. "' at " .. position)
        end
        position = position + 1
    end

    local parse_value

    local function parse_string()
        consume('"')
        local characters = {}
        while position <= #serialized do
            local character = serialized:sub(position, position)
            if character == '"' then
                position = position + 1
                return table.concat(characters)
            end
            if character == "\\" then
                position = position + 1
                local escape = serialized:sub(position, position)
                position = position + 1
                if escape == '"' or escape == "\\" or escape == "/" then
                    characters[#characters + 1] = escape
                elseif escape == "b" then
                    characters[#characters + 1] = "\b"
                elseif escape == "f" then
                    characters[#characters + 1] = "\f"
                elseif escape == "n" then
                    characters[#characters + 1] = "\n"
                elseif escape == "r" then
                    characters[#characters + 1] = "\r"
                elseif escape == "t" then
                    characters[#characters + 1] = "\t"
                elseif escape == "u" then
                    local hexadecimal = serialized:sub(position, position + 3)
                    if not hexadecimal:match("^%x%x%x%x$") then
                        error("JSON invalid Unicode escape at " .. position)
                    end
                    position = position + 4
                    local codepoint = tonumber(hexadecimal, 16)
                    local ok, character_value = pcall(utf8.char, codepoint)
                    characters[#characters + 1] = ok and character_value or "?"
                else
                    error("JSON invalid escape at " .. position)
                end
            else
                characters[#characters + 1] = character
                position = position + 1
            end
        end

        error("JSON unterminated string")
    end

    local function parse_number()
        local start = position
        if serialized:sub(position, position) == "-" then
            position = position + 1
        end
        while serialized:sub(position, position):match("%d") do
            position = position + 1
        end
        if serialized:sub(position, position) == "." then
            position = position + 1
            while serialized:sub(position, position):match("%d") do
                position = position + 1
            end
        end
        if serialized:sub(position, position):match("[eE]") then
            position = position + 1
            if serialized:sub(position, position):match("[+%-]") then
                position = position + 1
            end
            while serialized:sub(position, position):match("%d") do
                position = position + 1
            end
        end

        local number = tonumber(serialized:sub(start, position - 1))
        if not number then
            error("JSON invalid number at " .. start)
        end
        return number
    end

    local function parse_array()
        consume("[")
        local values = {}
        if current_character() == "]" then
            position = position + 1
            return values
        end

        while true do
            values[#values + 1] = parse_value()
            if current_character() == "]" then
                position = position + 1
                return values
            end
            consume(",")
        end
    end

    local function parse_object()
        consume("{")
        local fields = {}
        if current_character() == "}" then
            position = position + 1
            return fields
        end

        while true do
            local key = parse_string()
            consume(":")
            fields[key] = parse_value()
            if current_character() == "}" then
                position = position + 1
                return fields
            end
            consume(",")
        end
    end

    parse_value = function()
        local character = current_character()
        if character == '"' then
            return parse_string()
        end
        if character == "{" then
            return parse_object()
        end
        if character == "[" then
            return parse_array()
        end
        if serialized:sub(position, position + 3) == "true" then
            position = position + 4
            return true
        end
        if serialized:sub(position, position + 4) == "false" then
            position = position + 5
            return false
        end
        if serialized:sub(position, position + 3) == "null" then
            position = position + 4
            return nil
        end
        if character == "-" or character:match("%d") then
            return parse_number()
        end
        error("JSON unexpected '" .. character .. "' at " .. position)
    end

    local value = parse_value()
    skip_whitespace()
    if position <= #serialized then
        error("JSON trailing data at " .. position)
    end
    return value
end

return TrackFXJsonCodec
