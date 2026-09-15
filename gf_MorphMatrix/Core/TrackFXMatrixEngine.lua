-- @noindex

local TrackFXMatrixSnapshot = require("Core.TrackFXMatrixSnapshot")

local TrackFXMatrixEngine = {}
TrackFXMatrixEngine.__index = TrackFXMatrixEngine

function TrackFXMatrixEngine.new(adapter, options)
    if not adapter then
        error("TrackFXMatrixEngine requires an adapter")
    end

    return setmetatable({
        adapter = adapter,
        snapshot = nil,
        snapshot_class = options and options.snapshot_class or TrackFXMatrixSnapshot,
        last_applied_values = {},
        random_value = options and options.random_value or math.random,
    }, TrackFXMatrixEngine)
end

function TrackFXMatrixEngine:register(snapshot)
    if self.snapshot then
        return false
    end

    self.snapshot = snapshot or self.snapshot_class.new()
    self.last_applied_values = {}
    return true
end

function TrackFXMatrixEngine:get_snapshot()
    return self.snapshot
end

function TrackFXMatrixEngine:reconcile_parameters()
    if not self.snapshot or type(self.adapter.is_parameter_available) ~= "function" then
        return 0
    end

    local removed_count = 0
    for parameter_index in pairs(self.snapshot.parameters) do
        local parameter = self.snapshot.parameters[parameter_index]
        if not self.adapter:is_parameter_available(parameter_index, parameter.ident) then
            self.snapshot:remove_parameter(parameter_index)
            self.last_applied_values[parameter_index] = nil
            removed_count = removed_count + 1
        end
    end
    return removed_count
end

function TrackFXMatrixEngine:learn_parameter(parameter_index)
    if not self.snapshot or self.snapshot.parameters[parameter_index] then
        return false
    end

    if type(self.adapter.is_parameter_available) == "function"
        and not self.adapter:is_parameter_available(parameter_index) then
        return false
    end

    local parameter_info = self.adapter:get_parameter_info(parameter_index)
    local value = self.adapter:get_parameter_normalized(parameter_index)
    if not parameter_info or value == nil then
        return false
    end

    self.snapshot:add_parameter(parameter_index, parameter_info, value)
    if not self.snapshot:is_parameter_baseline_saved(parameter_index) then
        self.last_applied_values[parameter_index] = value
    end
    return true
end

function TrackFXMatrixEngine:update_provisional_baselines()
    if not self.snapshot then
        return 0
    end

    local pending_updates = {}
    for parameter_index, parameter in pairs(self.snapshot.parameters) do
        if not parameter.bypassed and not parameter.baseline_saved then
            local value = self.adapter:get_parameter_normalized(parameter_index)
            if type(value) ~= "number" then
                return false, "unable to read Track-FX parameter " .. tostring(parameter_index)
            end
            local expected_value = self.last_applied_values[parameter_index]
            if value ~= parameter.baseline and value ~= expected_value then
                pending_updates[parameter_index] = value
            end
        end
    end

    local updated_count = 0
    for parameter_index, value in pairs(pending_updates) do
        if self.snapshot:update_parameter_baseline(parameter_index, value) then
            self.last_applied_values[parameter_index] = nil
            updated_count = updated_count + 1
        end
    end
    return updated_count
end

function TrackFXMatrixEngine:release_parameter(parameter_index)
    if not self.snapshot then
        return false
    end

    local released = self.snapshot:remove_parameter(parameter_index)
    self.last_applied_values[parameter_index] = nil
    return released
end

function TrackFXMatrixEngine:clear_mappings()
    if not self.snapshot then
        return false
    end

    local cleared_count = self.snapshot:clear_mappings()
    self.last_applied_values = {}
    local applied, error_message = self:apply_current_values()
    if applied == false then
        return false, error_message
    end
    return cleared_count
end

function TrackFXMatrixEngine:clear_parameters()
    return self:clear_mappings()
end

function TrackFXMatrixEngine:set_parameter_value(parameter_index, value, user_edit)
    if not self.snapshot or not self.snapshot.parameters[parameter_index] then
        return false
    end
    if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
        return false
    end

    local parameter = self.snapshot.parameters[parameter_index]
    local clamp_min = type(parameter.clamp_min) == "number"
            and math.max(0, math.min(1, parameter.clamp_min))
        or 0
    local clamp_max = type(parameter.clamp_max) == "number"
            and math.max(0, math.min(1, parameter.clamp_max))
        or 1
    local expanded_minimum = user_edit == true and math.min(clamp_min, value) or clamp_min
    local expanded_maximum = user_edit == true and math.max(clamp_max, value) or clamp_max
    local clamp_changed = expanded_minimum ~= clamp_min
        or expanded_maximum ~= clamp_max
    if clamp_changed and not self.snapshot:set_parameter_clamp(
        parameter_index,
        expanded_minimum,
        expanded_maximum
    ) then
        return false
    end

    local written = self.adapter:set_parameter_normalized(parameter_index, value)
    if written == false then
        if clamp_changed then
            self.snapshot:set_parameter_clamp(parameter_index, clamp_min, clamp_max)
        end
        return false, "unable to write Track-FX parameter " .. tostring(parameter_index)
    end
    if self.snapshot:is_parameter_baseline_saved(parameter_index) then
        self.last_applied_values[parameter_index] = value
    end
    return true
end

function TrackFXMatrixEngine:set_parameter_clamp(parameter_index, minimum, maximum)
    if not self.snapshot then
        return false
    end
    if type(minimum) ~= "number" or minimum ~= minimum
        or type(maximum) ~= "number" or maximum ~= maximum then
        return false
    end

    local changed = self.snapshot:set_parameter_clamp(
        parameter_index,
        minimum,
        maximum
    )
    if not changed then
        return false
    end

    local applied, error_message = self:apply_current_values()
    if applied == false then
        return false, error_message
    end
    return true
end

function TrackFXMatrixEngine:set_bypass(parameter_index, bypassed)
    if not self.snapshot then
        return false
    end

    local changed = self.snapshot:set_bypass(parameter_index, bypassed)
    if not changed then
        return false
    end

    self.last_applied_values[parameter_index] = nil
    if bypassed ~= true then
        local applied, error_message = self:apply_current_values()
        if applied == false then
            return false, error_message
        end
    end

    return true
end

function TrackFXMatrixEngine:remove_parameter_from_corner(parameter_index, corner_id)
    if not self.snapshot then
        return false
    end

    local removed = self.snapshot:remove_parameter_from_corner(
        parameter_index,
        corner_id
    )
    if not removed then
        return false
    end

    self.last_applied_values[parameter_index] = nil
    local applied, error_message = self:apply_current_values()
    if applied == false then
        return false, error_message
    end
    return true
end

function TrackFXMatrixEngine:remove_all_parameters_from_corner(corner_id)
    if not self.snapshot then
        return false
    end

    local removed_count, removed_indices = self.snapshot:remove_all_parameters_from_corner(corner_id)
    if removed_count == false then
        return false
    end
    for parameter_index in pairs(removed_indices or {}) do
        self.last_applied_values[parameter_index] = nil
    end

    if removed_count == 0 then
        return 0
    end

    local applied, error_message = self:apply_current_values()
    if applied == false then
        return false, error_message
    end
    return removed_count
end

function TrackFXMatrixEngine:save_corner(corner_id)
    if not self.snapshot or corner_id < 1 or corner_id > 4 then
        return false
    end

    local updated, update_error = self:update_provisional_baselines()
    if updated == false then
        return false, update_error
    end

    local values = {}
    for parameter_index, parameter in pairs(self.snapshot.parameters) do
        if not parameter.bypassed then
            local value = self.adapter:get_parameter_normalized(parameter_index)
            if type(value) ~= "number" then
                return false, "unable to read Track-FX parameter " .. tostring(parameter_index)
            end
            values[parameter_index] = value
        end
    end

    return self.snapshot:save_corner(corner_id, values)
end

function TrackFXMatrixEngine:save_parameter_to_corner(parameter_index, corner_id)
    if not self.snapshot or corner_id < 1 or corner_id > 4 then
        return false
    end

    local updated, update_error = self:update_provisional_baselines()
    if updated == false then
        return false, update_error
    end

    local parameter = self.snapshot.parameters[parameter_index]
    if not parameter or parameter.bypassed then
        return false
    end

    local value = self.adapter:get_parameter_normalized(parameter_index)
    if type(value) ~= "number" then
        return false, "unable to read Track-FX parameter " .. tostring(parameter_index)
    end

    parameter.corners[corner_id] = value
    parameter.corner_saved = parameter.corner_saved or {}
    parameter.corner_saved[corner_id] = true
    self.snapshot:lock_parameter_baseline(parameter_index)
    return true
end

function TrackFXMatrixEngine:randomize_corner(corner_id)
    if not self.snapshot then
        return false
    end

    local updated, update_error = self:update_provisional_baselines()
    if updated == false then
        return false, update_error
    end

    local randomized_count = self.snapshot:randomize_corner(corner_id, self.random_value)
    if randomized_count == false then
        return false
    end

    local applied, error_message = self:apply_current_values()
    if applied == false then
        return false, error_message
    end
    return randomized_count
end

function TrackFXMatrixEngine:randomize_all()
    if not self.snapshot then
        return false
    end

    local updated, update_error = self:update_provisional_baselines()
    if updated == false then
        return false, update_error
    end

    local randomized_count = 0
    for corner_id = 1, 4 do
        local corner_count = self.snapshot:randomize_corner(corner_id, self.random_value)
        if corner_count == false then
            return false
        end
        randomized_count = randomized_count + corner_count
    end
    self.snapshot:set_cursor(self.random_value(), self.random_value())

    local applied, error_message = self:apply_current_values()
    if applied == false then
        return false, error_message
    end
    return randomized_count
end

function TrackFXMatrixEngine:reset_corners_to_baseline()
    if not self.snapshot then
        return false
    end

    local reset_count = self.snapshot:reset_corners_to_baseline()
    self.last_applied_values = {}
    local applied, error_message = self:apply_current_values()
    if applied == false then
        return false, error_message
    end
    return reset_count
end

function TrackFXMatrixEngine:load_preset(parameters, cursor)
    if not self.snapshot or type(parameters) ~= "table" then
        return false
    end

    local loaded_snapshot = self.snapshot_class.from_data({
        cursor = cursor or {
            x = self.snapshot.cursor.x,
            y = self.snapshot.cursor.y,
        },
        parameters = parameters,
    })
    if not loaded_snapshot then
        return false
    end

    local previous_snapshot = self.snapshot
    local previous_last_applied_values = {}
    for parameter_index, value in pairs(self.last_applied_values) do
        previous_last_applied_values[parameter_index] = value
    end
    self.snapshot = loaded_snapshot
    self.last_applied_values = {}
    local applied, error_message = self:apply_current_values()
    if applied == false then
        self.snapshot = previous_snapshot
        self.last_applied_values = previous_last_applied_values
        return false, error_message
    end

    local parameter_count = 0
    for _ in pairs(loaded_snapshot.parameters) do
        parameter_count = parameter_count + 1
    end
    return parameter_count
end

function TrackFXMatrixEngine:move_cursor(x, y)
    if not self.snapshot then
        return false
    end

    local updated, update_error = self:update_provisional_baselines()
    if updated == false then
        return false, update_error
    end
    self.snapshot:set_cursor(x, y)
    local applied, error_message = self:apply_current_values()
    if applied == false then
        return false, error_message
    end
    return true
end

function TrackFXMatrixEngine:apply_current_values()
    if not self.snapshot then
        return false
    end

    local applied_count = 0
    for parameter_index, parameter in pairs(self.snapshot.parameters) do
        if not parameter.bypassed then
            local value = self.snapshot:get_effective_value(parameter_index)
            if self.last_applied_values[parameter_index] ~= value then
                local written = self.adapter:set_parameter_normalized(parameter_index, value)
                if written == false then
                    return false, "unable to write Track-FX parameter " .. tostring(parameter_index)
                end
                self.last_applied_values[parameter_index] = value
                applied_count = applied_count + 1
            end
        end
    end

    return applied_count
end

return TrackFXMatrixEngine
