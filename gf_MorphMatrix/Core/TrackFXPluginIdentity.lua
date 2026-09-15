-- @noindex

local TrackFXPluginIdentity = {}

local function has_value(value)
    return type(value) == "string" and value ~= ""
end

function TrackFXPluginIdentity.matches(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end
    if has_value(left.portable_uid) ~= has_value(right.portable_uid) then
        return false
    end
    if has_value(left.portable_uid) and left.portable_uid ~= right.portable_uid then
        return false
    end
    if left.format ~= right.format or left.factory_name ~= right.factory_name then
        return false
    end
    return has_value(left.factory_name)
end

function TrackFXPluginIdentity.is_weak(identity)
    return type(identity) ~= "table" or not has_value(identity.portable_uid)
end

return TrackFXPluginIdentity