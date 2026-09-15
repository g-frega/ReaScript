-- @noindex

local TrackFXMatrixSnapshot = {}
TrackFXMatrixSnapshot.__index = TrackFXMatrixSnapshot

local function is_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function normalized_clamp_bounds(minimum, maximum)
    minimum = is_number(minimum) and math.max(0, math.min(1, minimum)) or 0
    maximum = is_number(maximum) and math.max(0, math.min(1, maximum)) or 1
    if minimum > maximum then
        return 0, 1
    end
    return minimum, maximum
end

function TrackFXMatrixSnapshot.new()
    return setmetatable({
        parameters = {},
        cursor = {x = 0.5, y = 0.5},
        baseline_learning = false,
    }, TrackFXMatrixSnapshot)
end

function TrackFXMatrixSnapshot:has_provisional_baselines()
    for _, parameter in pairs(self.parameters) do
        if not parameter.baseline_saved then
            return true
        end
    end
    return false
end

function TrackFXMatrixSnapshot:_refresh_baseline_learning()
    self.baseline_learning = self:has_provisional_baselines()
end

function TrackFXMatrixSnapshot:set_baseline_learning(enabled)
    self.baseline_learning = enabled == true
    if not enabled then
        self:lock_baseline_learning()
    end
end

function TrackFXMatrixSnapshot:lock_baseline_learning()
    for _, parameter in pairs(self.parameters) do
        parameter.baseline_saved = true
    end
    self.baseline_learning = false
end

function TrackFXMatrixSnapshot:is_parameter_baseline_saved(parameter_index)
    local parameter = self.parameters[parameter_index]
    return parameter ~= nil and parameter.baseline_saved == true
end

function TrackFXMatrixSnapshot:lock_parameter_baseline(parameter_index)
    local parameter = self.parameters[parameter_index]
    if not parameter then
        return false
    end

    parameter.baseline_saved = true
    self:_refresh_baseline_learning()
    return true
end

function TrackFXMatrixSnapshot:update_parameter_baseline(parameter_index, baseline)
    local parameter = self.parameters[parameter_index]
    if not parameter or parameter.baseline_saved then
        return false
    end

    parameter.baseline = baseline
    for corner_id = 1, 4 do
        parameter.corners[corner_id] = baseline
    end
    return true
end

function TrackFXMatrixSnapshot:add_parameter(parameter_index, parameter_info, baseline)
    self.parameters[parameter_index] = {
        index = parameter_index,
        name = parameter_info.name or "",
        ident = parameter_info.ident,
        minimum = parameter_info.minimum,
        maximum = parameter_info.maximum,
        clamp_min = 0,
        clamp_max = 1,
        baseline = baseline,
        baseline_saved = false,
        bypassed = false,
        corners = {
            [1] = baseline,
            [2] = baseline,
            [3] = baseline,
            [4] = baseline,
        },
        corner_saved = {
            [1] = false,
            [2] = false,
            [3] = false,
            [4] = false,
        },
    }
end

function TrackFXMatrixSnapshot:set_parameter_clamp(parameter_index, minimum, maximum)
    local parameter = self.parameters[parameter_index]
    if not parameter or not is_number(minimum) or not is_number(maximum) then
        return false
    end
    if minimum < 0 or minimum > 1 or maximum < 0 or maximum > 1 or minimum > maximum then
        return false
    end

    parameter.clamp_min = minimum
    parameter.clamp_max = maximum
    return true
end

function TrackFXMatrixSnapshot:remove_parameter(parameter_index)
    if not self.parameters[parameter_index] then
        return false
    end

    self.parameters[parameter_index] = nil
    return true
end

function TrackFXMatrixSnapshot:set_bypass(parameter_index, bypassed)
    local parameter = self.parameters[parameter_index]
    if not parameter then
        return false
    end

    parameter.bypassed = bypassed == true
    return true
end

function TrackFXMatrixSnapshot:remove_parameter_from_corner(parameter_index, corner_id)
    if corner_id < 1 or corner_id > 4 then
        return false
    end

    local parameter = self.parameters[parameter_index]
    if not parameter
        or type(parameter.corner_saved) ~= "table"
        or parameter.corner_saved[corner_id] ~= true then
        return false
    end

    parameter.corner_saved[corner_id] = false
    parameter.corners[corner_id] = parameter.baseline
    return true
end

function TrackFXMatrixSnapshot:remove_all_parameters_from_corner(corner_id)
    if corner_id < 1 or corner_id > 4 then
        return false
    end

    local removed_indices = {}
    for parameter_index, parameter in pairs(self.parameters) do
        if type(parameter.corner_saved) == "table"
            and parameter.corner_saved[corner_id] == true then
            parameter.corner_saved[corner_id] = false
            parameter.corners[corner_id] = parameter.baseline
            removed_indices[parameter_index] = true
        end
    end

    local removed_count = 0
    for _ in pairs(removed_indices) do
        removed_count = removed_count + 1
    end
    return removed_count, removed_indices
end

function TrackFXMatrixSnapshot:clear_mappings()
    local cleared_count = 0
    for _, parameter in pairs(self.parameters) do
        local parameter_changed = false
        parameter.corners = parameter.corners or {}
        parameter.corner_saved = parameter.corner_saved or {}
        if parameter.clamp_min ~= 0 or parameter.clamp_max ~= 1 then
            parameter_changed = true
        end
        for corner_id = 1, 4 do
            if parameter.corner_saved[corner_id] == true
                or parameter.corners[corner_id] ~= parameter.baseline then
                parameter_changed = true
            end
            parameter.corner_saved[corner_id] = false
            parameter.corners[corner_id] = parameter.baseline
        end
        parameter.clamp_min = 0
        parameter.clamp_max = 1
        if parameter_changed then
            cleared_count = cleared_count + 1
        end
    end

    self.cursor.x = 0.5
    self.cursor.y = 0.5
    return cleared_count
end

function TrackFXMatrixSnapshot:save_corner(corner_id, values)
    if corner_id < 1 or corner_id > 4 then
        return false
    end

    local saved_count = 0
    for parameter_index, parameter in pairs(self.parameters) do
        if not parameter.bypassed and values[parameter_index] ~= nil then
            parameter.corners[corner_id] = values[parameter_index]
            parameter.corner_saved = parameter.corner_saved or {}
            parameter.corner_saved[corner_id] = true
            parameter.baseline_saved = true
            saved_count = saved_count + 1
        end
    end

    self:_refresh_baseline_learning()
    return saved_count
end

function TrackFXMatrixSnapshot:randomize_corner(corner_id, random_value)
    if corner_id < 1 or corner_id > 4 then
        return false
    end

    local randomized_count = 0
    for _, parameter in pairs(self.parameters) do
        if not parameter.bypassed then
            parameter.corners[corner_id] = math.max(0, math.min(1, random_value()))
            parameter.corner_saved = parameter.corner_saved or {}
            parameter.corner_saved[corner_id] = true
            parameter.baseline_saved = true
            randomized_count = randomized_count + 1
        end
    end

    self:_refresh_baseline_learning()
    return randomized_count
end

function TrackFXMatrixSnapshot:reset_corners_to_baseline()
    local reset_count = 0
    for _, parameter in pairs(self.parameters) do
        for corner_id = 1, 4 do
            parameter.corners[corner_id] = parameter.baseline
        end
        reset_count = reset_count + 1
    end
    self.cursor.x = 0.5
    self.cursor.y = 0.5
    return reset_count
end

function TrackFXMatrixSnapshot:get_effective_value(parameter_index)
    local parameter = self.parameters[parameter_index]
    if not parameter then
        return nil
    end

    local x = self.cursor.x
    local y = self.cursor.y
    local top_left = parameter.corners[1] or parameter.baseline
    local top_right = parameter.corners[2] or parameter.baseline
    local bottom_left = parameter.corners[3] or parameter.baseline
    local bottom_right = parameter.corners[4] or parameter.baseline
    local top = top_left + (top_right - top_left) * x
    local bottom = bottom_left + (bottom_right - bottom_left) * x

    local value = top + (bottom - top) * y
    local clamp_min, clamp_max = normalized_clamp_bounds(
        parameter.clamp_min,
        parameter.clamp_max
    )
    local normalized_value = math.max(0, math.min(1, value))
    return clamp_min + normalized_value * (clamp_max - clamp_min)
end

function TrackFXMatrixSnapshot:to_data()
    local parameters = {}
    for parameter_index, parameter in pairs(self.parameters) do
        parameters[#parameters + 1] = {
            index = parameter_index,
            name = parameter.name,
            ident = parameter.ident,
            minimum = parameter.minimum,
            maximum = parameter.maximum,
            clamp_min = parameter.clamp_min,
            clamp_max = parameter.clamp_max,
            baseline = parameter.baseline,
            baseline_saved = parameter.baseline_saved == true,
            bypassed = parameter.bypassed,
            corners = {
                parameter.corners[1],
                parameter.corners[2],
                parameter.corners[3],
                parameter.corners[4],
            },
            corner_saved = {
                parameter.corner_saved and parameter.corner_saved[1] == true or false,
                parameter.corner_saved and parameter.corner_saved[2] == true or false,
                parameter.corner_saved and parameter.corner_saved[3] == true or false,
                parameter.corner_saved and parameter.corner_saved[4] == true or false,
            },
        }
    end
    table.sort(parameters, function(left, right)
        return left.index < right.index
    end)

    return {
        schema_version = 1,
        baseline_learning = self:has_provisional_baselines(),
        cursor = {x = self.cursor.x, y = self.cursor.y},
        parameters = parameters,
    }
end

function TrackFXMatrixSnapshot.from_data(data)
    if type(data) ~= "table" or type(data.parameters) ~= "table" then
        return nil
    end

    local snapshot = TrackFXMatrixSnapshot.new()
    local legacy_baseline_learning = data.baseline_learning == true
    if type(data.cursor) == "table" and is_number(data.cursor.x) and is_number(data.cursor.y) then
        snapshot:set_cursor(data.cursor.x, data.cursor.y)
    end

    for _, parameter_data in ipairs(data.parameters) do
        if type(parameter_data) == "table"
            and is_number(parameter_data.index)
            and parameter_data.index >= 0
            and is_number(parameter_data.baseline)
            and not snapshot.parameters[parameter_data.index] then
            local parameter_info = {
                name = parameter_data.name or "",
                ident = type(parameter_data.ident) == "string" and parameter_data.ident or nil,
                minimum = parameter_data.minimum,
                maximum = parameter_data.maximum,
            }
            snapshot:add_parameter(parameter_data.index, parameter_info, parameter_data.baseline)
            local parameter = snapshot.parameters[parameter_data.index]
            parameter.clamp_min, parameter.clamp_max = normalized_clamp_bounds(
                parameter_data.clamp_min,
                parameter_data.clamp_max
            )
            if type(parameter_data.baseline_saved) == "boolean" then
                parameter.baseline_saved = parameter_data.baseline_saved
            else
                parameter.baseline_saved = not legacy_baseline_learning
            end
            parameter.bypassed = parameter_data.bypassed == true
            local has_saved_corner_data = type(parameter_data.corner_saved) == "table"
            for corner_id = 1, 4 do
                local corner_value = parameter_data.corners and parameter_data.corners[corner_id]
                parameter.corners[corner_id] = is_number(corner_value)
                    and corner_value
                    or parameter_data.baseline
                if has_saved_corner_data then
                    parameter.corner_saved[corner_id] = parameter_data.corner_saved[corner_id] == true
                else
                    parameter.corner_saved[corner_id] = false
                end
            end
        end
    end

    snapshot:_refresh_baseline_learning()
    return snapshot
end

function TrackFXMatrixSnapshot:set_cursor(x, y)
    self.cursor.x = math.max(0, math.min(1, x))
    self.cursor.y = math.max(0, math.min(1, y))
end

return TrackFXMatrixSnapshot
