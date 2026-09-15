-- @noindex

local TrackFXAdapter = {}
TrackFXAdapter.__index = TrackFXAdapter

local function trim(value)
    return (value or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function get_dynamic_group(parameter_name)
    local group_name, group_number, parameter_role = parameter_name:match("^(.-)%s+(%d+)%s+(.+)$")
    if not group_name or group_name == "" then
        return nil
    end
    if parameter_role == "Used" then
        return nil
    end
    return group_name .. " " .. group_number
end

local function extract_identity(fx_ident, factory_name)
    local portable_uid = fx_ident and fx_ident:match("<([^>]+)>") or nil
    local format = fx_ident and fx_ident:match("%.([%w]+)%s*<") or nil

    return {
        portable_uid = portable_uid,
        factory_name = trim(factory_name),
        format = format or "unknown",
    }
end

function TrackFXAdapter.new(track, fx_index, api)
    if not track or fx_index == nil then
        error("TrackFXAdapter requires a track and FX index")
    end

    return setmetatable({
        track = track,
        fx_index = fx_index,
        api = api or reaper,
    }, TrackFXAdapter)
end

function TrackFXAdapter:get_parameter_count()
    return self.api.TrackFX_GetNumParams(self.track, self.fx_index)
end

function TrackFXAdapter:get_parameter_normalized(parameter_index)
    return self.api.TrackFX_GetParamNormalized(self.track, self.fx_index, parameter_index)
end

function TrackFXAdapter:set_parameter_normalized(parameter_index, value)
    local result = self.api.TrackFX_SetParamNormalized(self.track, self.fx_index, parameter_index, value)
    return result == true
end

    function TrackFXAdapter:format_parameter_value(parameter_index, value)
        if type(self.api.TrackFX_FormatParamValueNormalized) == "function" then
            local available, formatted = self.api.TrackFX_FormatParamValueNormalized(
                self.track,
                self.fx_index,
                parameter_index,
                value
            )
            if available == true and type(formatted) == "string" and formatted ~= "" then
                return trim(formatted)
            end
        end

        return string.format("%.0f%%", math.max(0, math.min(1, value)) * 100)
    end

    function TrackFXAdapter:get_parameter_step_sizes(parameter_index)
        if type(self.api.TrackFX_GetParameterStepSizes) ~= "function" then
            return nil
        end

        return self.api.TrackFX_GetParameterStepSizes(
            self.track,
            self.fx_index,
            parameter_index
        )
    end

function TrackFXAdapter:get_parameter_info(parameter_index)
    local available, name = self:_get_parameter_name(parameter_index)
    local retval, minimum, maximum, midpoint = self.api.TrackFX_GetParamEx(
        self.track,
        self.fx_index,
        parameter_index
    )
    if not retval then
        minimum, maximum, midpoint = 0, 1, 0.5
    end

    return {
        index = parameter_index,
        available = available,
        name = trim(name),
        ident = self:get_parameter_identity(parameter_index),
        minimum = minimum,
        maximum = maximum,
        midpoint = midpoint,
    }
end

function TrackFXAdapter:_get_parameter_name(parameter_index)
    local available, name = self.api.TrackFX_GetParamName(
        self.track,
        self.fx_index,
        parameter_index,
        ""
    )
    return available == true, trim(name)
end

function TrackFXAdapter:_find_parameter_index_by_name(parameter_name)
    local parameter_count = self:get_parameter_count()
    if type(parameter_count) ~= "number" then
        return nil
    end

    for current_index = 0, parameter_count - 1 do
        local available, current_name = self:_get_parameter_name(current_index)
        if available and current_name == parameter_name then
            return current_index
        end
    end
    return nil
end

function TrackFXAdapter:get_parameter_identity(parameter_index)
    if type(self.api.TrackFX_GetParamIdent) ~= "function" then
        return nil
    end

    local available, identity = self.api.TrackFX_GetParamIdent(
        self.track,
        self.fx_index,
        parameter_index
    )
    if available ~= true or type(identity) ~= "string" then
        return nil
    end

    identity = trim(identity)
    return identity ~= "" and identity or nil
end

function TrackFXAdapter:is_parameter_available(parameter_index, expected_identity)
    local available, parameter_name = self:_get_parameter_name(parameter_index)
    if not available then
        return false
    end

    if type(expected_identity) == "string" and expected_identity ~= "" then
        if self:get_parameter_identity(parameter_index) ~= expected_identity then
            return false
        end
    end

    local dynamic_group = get_dynamic_group(parameter_name)
    if not dynamic_group then
        return true
    end

    local used_parameter_index = self:_find_parameter_index_by_name(dynamic_group .. " Used")
    if used_parameter_index == nil then
        return true
    end

    local used_value = self:get_parameter_normalized(used_parameter_index)
    return type(used_value) == "number" and used_value > 0
end

function TrackFXAdapter:get_instance_id()
    return self.api.TrackFX_GetFXGUID(self.track, self.fx_index)
end

function TrackFXAdapter:get_identity()
    local _, fx_ident = self.api.TrackFX_GetNamedConfigParm(self.track, self.fx_index, "fx_ident")
    local _, factory_name = self.api.TrackFX_GetNamedConfigParm(self.track, self.fx_index, "fx_name")
    return extract_identity(fx_ident, factory_name)
end

function TrackFXAdapter:get_instance_name()
    local available, renamed_name = self.api.TrackFX_GetNamedConfigParm(
        self.track,
        self.fx_index,
        "renamed_name"
    )
    if available and type(renamed_name) == "string" then
        renamed_name = trim(renamed_name)
        if renamed_name ~= "" then
            return renamed_name
        end
    end

    return self:get_identity().factory_name
end

return TrackFXAdapter
