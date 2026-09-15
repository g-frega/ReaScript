-- @noindex

local TrackFXAdapter = require("Adapters.TrackFXAdapter")
local TrackFXMatrixEngine = require("Core.TrackFXMatrixEngine")
local TrackFXMatrixPreset = require("Core.TrackFXMatrixPreset")
local TrackFXPluginIdentity = require("Core.TrackFXPluginIdentity")
local TrackFXMatrixSnapshot = require("Core.TrackFXMatrixSnapshot")
local TrackFXProjectStore = require("Persistence.TrackFXProjectStore")
local TrackFXPresetFile = require("Persistence.TrackFXPresetFile")

local TrackFXMatrixController = {}
TrackFXMatrixController.__index = TrackFXMatrixController

local function identities_match(left, right)
    return TrackFXPluginIdentity.matches(left, right)
end

local function descriptors_match(left, right)
    return left
        and right
        and left.track_guid == right.track_guid
        and left.fx_guid == right.fx_guid
        and identities_match(left.plugin_identity, right.plugin_identity)
end

local function get_track_guid(api, track)
    if type(api.GetTrackGUID) == "function" then
        return api.GetTrackGUID(track)
    end
    if type(api.GetSetMediaTrackInfo_String) == "function" then
        local exists, guid = api.GetSetMediaTrackInfo_String(track, "GUID", "", false)
        if exists then
            return guid
        end
    end
    return nil
end

local function resolve_track(api, track_number)
    if track_number == 0 and type(api.GetMasterTrack) == "function" then
        return api.GetMasterTrack(0)
    end
    if type(api.GetTrack) == "function" then
        return api.GetTrack(0, track_number - 1)
    end
    return nil
end

local function is_valid_track(api, track)
    if not track then
        return false
    end
    if type(api.ValidatePtr2) ~= "function" then
        return true
    end

    local ok, valid = pcall(api.ValidatePtr2, 0, track, "MediaTrack*")
    return ok and valid == true
end

local function get_track_number(api, track)
    if type(api.GetMediaTrackInfo_Value) ~= "function" then
        return nil
    end
    local track_number = api.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    return type(track_number) == "number" and track_number or nil
end

local function get_track_name(api, track)
    if type(api.GetTrackName) == "function" then
        local available, track_name = api.GetTrackName(track, "")
        if available and type(track_name) == "string" then
            return track_name
        end
    end
    if type(api.GetSetMediaTrackInfo_String) == "function" then
        local available, track_name = api.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if available and type(track_name) == "string" then
            return track_name
        end
    end
    return nil
end

local function count_matches(matches)
    local count = 0
    for _ in pairs(matches) do
        count = count + 1
    end
    return count
end

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nested_value in pairs(value) do
        copy[key] = clone(nested_value)
    end
    return copy
end

local function restore_table(target, source)
    for key in pairs(target) do
        target[key] = nil
    end
    for key, value in pairs(source) do
        target[key] = clone(value)
    end
end

local function snapshot_parameter_indices(snapshot)
    local indices = {}
    if snapshot and type(snapshot.parameters) == "table" then
        for parameter_index in pairs(snapshot.parameters) do
            indices[parameter_index] = true
        end
    end
    return indices
end

local function capture_parameter_values(adapter, parameter_indices)
    local values = {}
    if not adapter or type(adapter.get_parameter_normalized) ~= "function" then
        return values
    end

    for parameter_index in pairs(parameter_indices) do
        local ok, value = pcall(adapter.get_parameter_normalized, adapter, parameter_index)
        if ok and value ~= nil then
            values[parameter_index] = value
        end
    end
    return values
end

local function restore_parameter_values(adapter, values)
    if not adapter or type(adapter.set_parameter_normalized) ~= "function" then
        return false
    end

    local restored = true
    for parameter_index, value in pairs(values) do
        local ok, result = pcall(adapter.set_parameter_normalized, adapter, parameter_index, value)
        if not ok or result == false then
            restored = false
        end
    end
    return restored
end

local function restore_engine_state(engine, snapshot, last_applied_values, parameter_values)
    engine.snapshot = snapshot
    engine.last_applied_values = clone(last_applied_values)
    restore_parameter_values(engine.adapter, parameter_values)
end

local function preset_name_from_path(path)
    local file_name = path:match("([^\\/]+)$") or ""
    return (file_name:gsub("%.[^%.]+$", ""))
end

local function format_preset_report(report)
    local details = {}
    for _, warning in ipairs(report.warnings or {}) do
        details[#details + 1] = warning
    end

    if #(report.missing_parameters or {}) > 0 then
        local missing = {}
        for _, parameter in ipairs(report.missing_parameters) do
            local label = parameter.name or "unknown parameter"
            if parameter.index ~= nil then
                label = label .. " (#" .. tostring(parameter.index) .. ")"
            end
            missing[#missing + 1] = label
        end
        details[#details + 1] = "Missing parameters: " .. table.concat(missing, ", ")
    end

    if #details == 0 then
        return report.compatible and nil or "Preset is incompatible with the active Track-FX"
    end

    local prefix = report.compatible
            and "Preset warning"
        or "Preset is incompatible with the active Track-FX"
    return prefix .. ": " .. table.concat(details, "; ")
end

local function has_focus_flag(result, flag)
    return type(result) == "number"
        and math.floor(result / flag) % 2 == 1
end

function TrackFXMatrixController.new(options)
    options = options or {}
    return setmetatable({
        api = options.api or reaper,
        adapter_class = options.adapter_class or TrackFXAdapter,
        engine_class = options.engine_class or TrackFXMatrixEngine,
        snapshot_class = options.snapshot_class or TrackFXMatrixSnapshot,
        store_class = options.store_class or TrackFXProjectStore,
        preset_file_class = options.preset_file_class or TrackFXPresetFile,
        preset_file = options.preset_file,
        codec = options.codec,
        engine_options = options.engine_options,
        generate_record_id = options.generate_record_id,
        next_record_number = 0,
        track = nil,
        store = nil,
        document = nil,
        active = nil,
            last_focused_fx = nil,
            loaded_preset_name = nil,
        cursor_dirty = false,
        parameters_dirty = false,
            last_preset_report = nil,
    }, TrackFXMatrixController)
end

function TrackFXMatrixController:get_document()
    return self.document
end

function TrackFXMatrixController:get_active()
    return self.active
end

    function TrackFXMatrixController:get_loaded_preset_name()
        return self.loaded_preset_name
    end

    function TrackFXMatrixController:get_last_preset_report()
        return self.last_preset_report
    end

function TrackFXMatrixController:_get_preset_file()
    if self.preset_file then
        return self.preset_file
    end
    return self.preset_file_class.new({codec = self.codec})
end

function TrackFXMatrixController:_load_track(track)
    if self.track == track and self.store and self.document then
        return true
    end

    if self.active then
        local reconciled, reconcile_error = self:reconcile_active_parameters()
        if reconciled == false then
            return false, reconcile_error
        end
    end

    if self.active and (self.cursor_dirty or self.parameters_dirty) then
        local saved, error_message = self:save()
        if not saved then
            return false, error_message
        end
    end

    local store = self.store_class.new(track, self.api, self.codec)
    local document, error_message = store:load()
    if not document then
        return false, error_message
    end

    self.track = track
    self.store = store
    self.document = document
    self.active = nil
    self.cursor_dirty = false
    self.parameters_dirty = false
    return true
end

function TrackFXMatrixController:_new_record_id()
    if self.generate_record_id then
        return self.generate_record_id(self.document)
    end

    if type(self.api.genGuid) == "function" then
        return self.api.genGuid()
    end

    repeat
        self.next_record_number = self.next_record_number + 1
        local record_id = "track-fx-instance-" .. tostring(self.next_record_number)
        if not self.document.instances[record_id] then
            return record_id
        end
    until false
end

function TrackFXMatrixController:list_track_fx(track)
    local descriptors = {}
    local count = self.api.TrackFX_GetCount(track)
    local track_guid = get_track_guid(self.api, track)
    local track_number = get_track_number(self.api, track)
    local track_name = get_track_name(self.api, track)

    for fx_index = 0, count - 1 do
        local adapter = self.adapter_class.new(track, fx_index, self.api)
        local identity = adapter:get_identity()
        local occurrence = 0
        for previous_index = 0, fx_index do
            local previous_adapter = previous_index == fx_index
                and adapter
                or self.adapter_class.new(track, previous_index, self.api)
            if identities_match(identity, previous_adapter:get_identity()) then
                occurrence = occurrence + 1
            end
        end

        descriptors[#descriptors + 1] = {
            track = track,
            track_guid = track_guid,
            fx_index = fx_index,
            fx_guid = adapter:get_instance_id(),
            plugin_identity = identity,
            instance_name = adapter:get_instance_name(),
            track_number = track_number,
            track_name = track_name,
            plugin_occurrence = occurrence,
            adapter = adapter,
        }
    end

    return descriptors
end

function TrackFXMatrixController:_get_current_cached_fx()
    if not self.last_focused_fx then
        return nil
    end

    local descriptors = self:list_track_fx(self.last_focused_fx.track)
    for _, descriptor in ipairs(descriptors) do
        if descriptor.fx_guid == self.last_focused_fx.fx_guid then
            if identities_match(descriptor.plugin_identity, self.last_focused_fx.plugin_identity) then
                self.last_focused_fx = descriptor
                return descriptor
            end
            break
        end
    end

    self.last_focused_fx = nil
    return nil
end

function TrackFXMatrixController:_remember_focused_fx(descriptor)
    local previous = self.last_focused_fx
    local focus_changed = previous and not descriptors_match(previous, descriptor)
    local active_is_different = self.active and not descriptors_match(self.active.descriptor, descriptor)
    if self.active and (focus_changed or (not previous and active_is_different)) then
        local reconciled, reconcile_error = self:reconcile_active_parameters()
        if reconciled == false then
            return nil, reconcile_error
        end
        if reconciled == 0 then
            local saved, save_error = self:save()
            if not saved then
                return nil, save_error
            end
        end
    end

    self.last_focused_fx = descriptor
    return descriptor
end

function TrackFXMatrixController:discover_focused_fx()
    local get_focused_fx = self.api.GetFocusedFX2 or self.api.GetFocusedFX
    if type(get_focused_fx) ~= "function" then
        return nil, "REAPER focused-FX API is unavailable"
    end

    local result, track_number, _, fx_index = get_focused_fx()
    if not has_focus_flag(result, 1) then
        if result == 0 then
            local cached_fx = self:_get_current_cached_fx()
            if cached_fx then
                return cached_fx
            end
        end
        return nil, has_focus_flag(result, 2)
                and "focused FX is a Take FX"
            or "no focused Track-FX instance"
    end

    local track = resolve_track(self.api, track_number)
    if not track then
        return nil, "focused Track-FX track is unavailable"
    end

    local descriptors = self:list_track_fx(track)
    local descriptor = descriptors[(fx_index or -1) + 1]
    if not descriptor then
        return nil, "focused Track-FX instance is unavailable"
    end
    return self:_remember_focused_fx(descriptor)
end

function TrackFXMatrixController:is_active_fx_focused()
    if not self.active then
        return false
    end

    local get_focused_fx = self.api.GetFocusedFX2 or self.api.GetFocusedFX
    if type(get_focused_fx) ~= "function" then
        return false
    end

    local result, track_number, _, fx_index = get_focused_fx()
    if not has_focus_flag(result, 1) then
        return false
    end

    local track = resolve_track(self.api, track_number)
    if not track then
        return false
    end

    local descriptors = self:list_track_fx(track)
    local descriptor = descriptors[(fx_index or -1) + 1]
    return descriptor ~= nil and descriptors_match(self.active.descriptor, descriptor)
end

function TrackFXMatrixController:_find_record_for_descriptor(descriptor, document)
    document = document or self.document
    if not document then
        return nil, "no Track-FX project state is loaded"
    end

    local exact_matches = {}
    for record_id, record in pairs(document.instances) do
        if record.track_guid == descriptor.track_guid
            and record.fx_instance_guid == descriptor.fx_guid then
            exact_matches[record_id] = record
        end
    end

    if count_matches(exact_matches) > 1 then
        return nil, "ambiguous Track-FX instance record"
    end
    for record_id, record in pairs(exact_matches) do
        if not identities_match(record.plugin_identity, descriptor.plugin_identity) then
            return nil, "Track-FX instance identity changed"
        end
        return record, record_id
    end

    local fallback_matches = {}
    for record_id, record in pairs(document.instances) do
        if record.track_guid == descriptor.track_guid
            and record.plugin_occurrence == descriptor.plugin_occurrence
            and identities_match(record.plugin_identity, descriptor.plugin_identity) then
            fallback_matches[record_id] = record
        end
    end

    if count_matches(fallback_matches) > 1 then
        return nil, "ambiguous Track-FX instance reconnection"
    end
    for record_id, record in pairs(fallback_matches) do
        return record, record_id
    end
    return nil
end

function TrackFXMatrixController:_activate_record(descriptor, record, record_id, persist, provisional_baseline)
    local snapshot
    if record.snapshot then
        snapshot = self.snapshot_class.from_data(record.snapshot)
        if not snapshot then
            return nil, "invalid Snapshot for Track-FX instance"
        end
    end

    local engine = self.engine_class.new(descriptor.adapter, self.engine_options)
    if not engine:register(snapshot) then
        return nil, "Track-FX engine registration failed"
    end
    if provisional_baseline and not snapshot then
        engine:get_snapshot():set_baseline_learning(true)
    end

    local removed_count = 0
    if type(engine.reconcile_parameters) == "function" then
        removed_count = engine:reconcile_parameters()
    end

    local candidate = {
        record_id = record_id,
        record = record,
        descriptor = descriptor,
        engine = engine,
    }

    local record_before_activation = clone(record)
    local parameter_values = capture_parameter_values(
        descriptor.adapter,
        snapshot_parameter_indices(engine:get_snapshot())
    )
    local provisional_updates = 0
    if type(engine.update_provisional_baselines) == "function" then
        local update_result, update_error = engine:update_provisional_baselines()
        if update_result == false then
            restore_parameter_values(descriptor.adapter, parameter_values)
            return nil, update_error
        end
        provisional_updates = update_result or 0
    end
    local applied, application_error = engine:apply_current_values()
    if applied == false then
        restore_parameter_values(descriptor.adapter, parameter_values)
        return nil, application_error or "unable to apply Track-FX Snapshot"
    end

    if persist ~= false or removed_count > 0 or provisional_updates > 0 then
        self:_sync_record(candidate)
        local saved, save_error = self.store:save(self.document)
        if not saved then
            restore_table(record, record_before_activation)
            restore_parameter_values(descriptor.adapter, parameter_values)
            return nil, save_error
        end
    end

    self.active = candidate
    self.loaded_preset_name = nil
    self.cursor_dirty = false
    self.parameters_dirty = false
    return candidate
end

function TrackFXMatrixController:_save_active_before_switch(descriptor)
    if not self.active or descriptors_match(self.active.descriptor, descriptor) then
        return true
    end

    local reconciled, reconcile_error = self:reconcile_active_parameters()
    if reconciled == false then
        return false, reconcile_error
    end
    if not self.cursor_dirty and not self.parameters_dirty then
        return true
    end

    local saved, error_message = self:save()
    if not saved then
        return false, error_message
    end
    return true
end

function TrackFXMatrixController:activate_registered_fx(descriptor)
    if not descriptor then
        return nil, "focused Track-FX instance is unavailable"
    end
    if self.active and descriptors_match(self.active.descriptor, descriptor) then
        return self.active
    end

    local previous_track = self.track
    local previous_store = self.store
    local previous_document = self.document
    local previous_active = self.active
    local previous_cursor_dirty = self.cursor_dirty
    local previous_parameters_dirty = self.parameters_dirty

    local record, record_id_or_error
    if self.track == descriptor.track and self.document then
        record, record_id_or_error = self:_find_record_for_descriptor(descriptor)
    else
        local target_store = self.store_class.new(descriptor.track, self.api, self.codec)
        local target_document, load_error = target_store:load()
        if not target_document then
            return nil, load_error
        end
        record, record_id_or_error = self:_find_record_for_descriptor(descriptor, target_document)
    end

    if not record then
        if record_id_or_error then
            return nil, record_id_or_error
        end
        return nil
    end

    local saved, save_error = self:_save_active_before_switch(descriptor)
    if not saved then
        return nil, save_error
    end

    if self.track ~= descriptor.track or not self.document then
        local loaded, load_error = self:_load_track(descriptor.track)
        if not loaded then
            return nil, load_error
        end
        record, record_id_or_error = self:_find_record_for_descriptor(descriptor)
        if not record then
            self.track = previous_track
            self.store = previous_store
            self.document = previous_document
            self.active = previous_active
            self.cursor_dirty = previous_cursor_dirty
            self.parameters_dirty = previous_parameters_dirty
            return nil, record_id_or_error or "registered Track-FX instance is unavailable"
        end
    end

    local activated, activation_error = self:_activate_record(
        descriptor,
        record,
        record_id_or_error,
        false
    )
    if not activated then
        self.track = previous_track
        self.store = previous_store
        self.document = previous_document
        self.active = previous_active
        self.cursor_dirty = previous_cursor_dirty
        self.parameters_dirty = previous_parameters_dirty
    end
    return activated, activation_error
end

function TrackFXMatrixController:_find_descriptor_for_record(record, descriptors)
    if #descriptors == 0 then
        return nil, "Track-FX instance is missing"
    end
    if record.track_guid ~= descriptors[1].track_guid then
        return nil, "track identity mismatch"
    end

    local exact_matches = {}
    for _, descriptor in ipairs(descriptors) do
        if descriptor.fx_guid == record.fx_instance_guid then
            exact_matches[#exact_matches + 1] = descriptor
        end
    end
    if #exact_matches > 1 then
        return nil, "ambiguous Track-FX instance GUID"
    end
    if #exact_matches == 1 then
        if not identities_match(record.plugin_identity, exact_matches[1].plugin_identity) then
            return nil, "Track-FX instance identity changed"
        end
        return exact_matches[1]
    end

    if type(record.plugin_occurrence) ~= "number" then
        return nil, "Track-FX instance has no reconnection occurrence"
    end

    local fallback_matches = {}
    for _, descriptor in ipairs(descriptors) do
        if descriptor.plugin_occurrence == record.plugin_occurrence
            and identities_match(record.plugin_identity, descriptor.plugin_identity) then
            fallback_matches[#fallback_matches + 1] = descriptor
        end
    end
    if #fallback_matches > 1 then
        return nil, "ambiguous Track-FX instance reconnection"
    end
    if #fallback_matches == 1 then
        return fallback_matches[1]
    end
    return nil, "Track-FX instance is missing"
end

function TrackFXMatrixController:reconcile_track(track)
    local loaded, error_message = self:_load_track(track)
    if not loaded then
        return nil, error_message
    end

    local descriptors = self:list_track_fx(track)
    local results = {}
    local descriptor_match_counts = {}
    local track_guid = get_track_guid(self.api, track)
    for record_id, record in pairs(self.document.instances) do
        if record.track_guid ~= track_guid then
            results[#results + 1] = {
                record_id = record_id,
                status = "track identity mismatch",
            }
        else
            local descriptor, status = self:_find_descriptor_for_record(record, descriptors)
            if descriptor then
                descriptor_match_counts[descriptor.fx_guid] = (descriptor_match_counts[descriptor.fx_guid] or 0) + 1
            end
            results[#results + 1] = {
                record_id = record_id,
                status = descriptor and "resolved" or status,
                descriptor = descriptor,
            }
        end
    end
    for _, result in ipairs(results) do
        if result.descriptor and descriptor_match_counts[result.descriptor.fx_guid] > 1 then
            result.status = "ambiguous Track-FX instance reconnection"
            result.descriptor = nil
        end
    end
    table.sort(results, function(left, right)
        return left.record_id < right.record_id
    end)
    return results
end

function TrackFXMatrixController:_sync_record(active)
    if not active then
        return false
    end

    local record = active.record
    local descriptor = active.descriptor
    record.record_id = active.record_id
    record.track_guid = descriptor.track_guid
    record.fx_instance_guid = descriptor.fx_guid
    record.plugin_identity = descriptor.plugin_identity
    record.plugin_occurrence = descriptor.plugin_occurrence
    record.snapshot = active.engine:get_snapshot():to_data()
    return true
end

function TrackFXMatrixController:_sync_active_record()
    return self:_sync_record(self.active)
end

function TrackFXMatrixController:save()
    if not self.store or not self.document then
        return false, "no Track-FX project state is loaded"
    end
    self:_sync_active_record()
    local saved, error_message = self.store:save(self.document)
    if saved then
        self.cursor_dirty = false
        self.parameters_dirty = false
    end
    return saved, error_message
end

function TrackFXMatrixController:reconcile_active_parameters()
    if not self.active then
        return 0
    end

    local removed_count = 0
    if type(self.active.engine.reconcile_parameters) == "function" then
        removed_count = self.active.engine:reconcile_parameters()
    end
    if removed_count > 0 then
        self.parameters_dirty = true
    end
    if not self.parameters_dirty
        and type(self.active.engine.update_provisional_baselines) == "function" then
        local updated_count, update_error = self.active.engine:update_provisional_baselines()
        if updated_count == false then
            return false, update_error
        end
        if updated_count > 0 then
            self.parameters_dirty = true
        end
    end
    if not self.parameters_dirty then
        return removed_count
    end

    local saved, error_message = self:save()
    if not saved then
        return false, error_message
    end
    return removed_count
end

function TrackFXMatrixController:_register_descriptor(descriptor)
    local loaded, error_message = self:_load_track(descriptor.track)
    if not loaded then
        return nil, error_message
    end

    local saved, save_error = self:_save_active_before_switch(descriptor)
    if not saved then
        return nil, save_error
    end

    local record, record_id = self:_find_record_for_descriptor(descriptor)
    local new_record = false
    if record == nil and record_id ~= nil then
        return nil, record_id
    end
    if not record then
        record_id = self:_new_record_id()
        record = {
            record_id = record_id,
            track_guid = descriptor.track_guid,
            fx_instance_guid = descriptor.fx_guid,
            plugin_identity = descriptor.plugin_identity,
            plugin_occurrence = descriptor.plugin_occurrence,
        }
        self.document.instances[record_id] = record
        new_record = true
    end

    local active, activation_error = self:_activate_record(
        descriptor,
        record,
        record_id,
        nil,
        new_record
    )
    if not active and new_record then
        self.document.instances[record_id] = nil
    end
    return active, activation_error
end

function TrackFXMatrixController:register_fx(track, fx_index)
    local descriptors = self:list_track_fx(track)
    local descriptor = descriptors[(fx_index or -1) + 1]
    if not descriptor then
        return nil, "Track-FX instance is unavailable"
    end
    return self:_register_descriptor(descriptor)
end

function TrackFXMatrixController:register_focused_fx()
    local descriptor, error_message = self:discover_focused_fx()
    if not descriptor then
        return nil, error_message
    end
    return self:_register_descriptor(descriptor)
end

function TrackFXMatrixController:deregister_active_fx()
    if not self.active then
        return false, "no Track-FX instance is registered"
    end

    local record_id = self.active.record_id
    local record = self.document and self.document.instances[record_id]
    if not record then
        return false, "active Track-FX instance record is unavailable"
    end

    self.document.instances[record_id] = nil
    local saved, save_error = self.store:save(self.document)
    if not saved then
        self.document.instances[record_id] = record
        return false, save_error
    end

    self.active = nil
    self.cursor_dirty = false
    self.parameters_dirty = false
    return true
end

function TrackFXMatrixController:get_last_touched_parameter()
    if not self.active or type(self.api.GetLastTouchedFX) ~= "function" then
        return nil, "no Track-FX instance is registered"
    end

    local result, track_number, fx_index, parameter_index = self.api.GetLastTouchedFX()
    if result == 0 then
        return nil, "no Track-FX parameter has been touched"
    end
    if type(track_number) == "number" and math.floor(track_number / 0x10000) > 0 then
        return nil, "last touched parameter belongs to a Take FX"
    end

    local track = resolve_track(self.api, track_number)
    if track ~= self.active.descriptor.track then
        return nil, "last touched parameter belongs to another track"
    end
    if self.api.TrackFX_GetFXGUID(track, fx_index) ~= self.active.descriptor.fx_guid then
        return nil, "last touched parameter belongs to another FX"
    end
    return parameter_index
end

function TrackFXMatrixController:learn_last_touched_parameter()
    local parameter_index, error_message = self:get_last_touched_parameter()
    if parameter_index == nil then
        return false, error_message
    end
    return self:learn_parameter(parameter_index)
end

function TrackFXMatrixController:_mutate(method_name, ...)
    if not self.active then
        return false, "no Track-FX instance is registered"
    end

    local reconciled, reconcile_error = self:reconcile_active_parameters()
    if reconciled == false then
        return false, reconcile_error
    end

    local engine = self.active.engine
    local previous_snapshot_data = engine:get_snapshot():to_data()
    local previous_last_applied_values = clone(engine.last_applied_values)
    local previous_parameter_values = capture_parameter_values(
        engine.adapter,
        snapshot_parameter_indices(engine:get_snapshot())
    )
    local previous_record = clone(self.active.record)
    local previous_cursor_dirty = self.cursor_dirty
    local previous_parameters_dirty = self.parameters_dirty
    local result, result_error = engine[method_name](engine, ...)
    if result == false then
        restore_engine_state(
            engine,
            self.snapshot_class.from_data(previous_snapshot_data),
            previous_last_applied_values,
            previous_parameter_values
        )
        restore_table(self.active.record, previous_record)
        self.cursor_dirty = previous_cursor_dirty
        self.parameters_dirty = previous_parameters_dirty
        return false, result_error
    end
    local saved, error_message = self:save()
    if not saved then
        restore_engine_state(
            engine,
            self.snapshot_class.from_data(previous_snapshot_data),
            previous_last_applied_values,
            previous_parameter_values
        )
        restore_table(self.active.record, previous_record)
        self.cursor_dirty = previous_cursor_dirty
        self.parameters_dirty = previous_parameters_dirty
        return false, error_message
    end
    return result
end

function TrackFXMatrixController:learn_parameter(parameter_index)
    return self:_mutate("learn_parameter", parameter_index)
end

function TrackFXMatrixController:release_parameter(parameter_index)
    return self:_mutate("release_parameter", parameter_index)
end

function TrackFXMatrixController:clear_parameters()
    return self:clear_mappings()
end

function TrackFXMatrixController:clear_mappings()
    return self:_mutate("clear_mappings")
end

function TrackFXMatrixController:set_parameter_value(parameter_index, value, user_edit)
    if not self.active then
        return false, "no Track-FX instance is registered"
    end

    local reconciled, reconcile_error = self:reconcile_active_parameters()
    if reconciled == false then
        return false, reconcile_error
    end

    local engine = self.active.engine
    local previous_snapshot_data = engine:get_snapshot():to_data()
    local previous_last_applied_values = clone(engine.last_applied_values)
    local previous_parameter_values = capture_parameter_values(
        engine.adapter,
        snapshot_parameter_indices(engine:get_snapshot())
    )
    local previous_record = clone(self.active.record)
    local previous_cursor_dirty = self.cursor_dirty
    local previous_parameters_dirty = self.parameters_dirty
    local result, result_error = engine:set_parameter_value(
        parameter_index,
        value,
        user_edit
    )
    if result == false then
        restore_engine_state(
            engine,
            self.snapshot_class.from_data(previous_snapshot_data),
            previous_last_applied_values,
            previous_parameter_values
        )
        restore_table(self.active.record, previous_record)
        self.cursor_dirty = previous_cursor_dirty
        self.parameters_dirty = previous_parameters_dirty
        return false, result_error
    end

    self:_sync_active_record()
    self.parameters_dirty = true
    return true
end

function TrackFXMatrixController:set_parameter_clamp(parameter_index, minimum, maximum)
    if not self.active then
        return false, "no Track-FX instance is registered"
    end

    local reconciled, reconcile_error = self:reconcile_active_parameters()
    if reconciled == false then
        return false, reconcile_error
    end

    local engine = self.active.engine
    local previous_snapshot_data = engine:get_snapshot():to_data()
    local previous_last_applied_values = clone(engine.last_applied_values)
    local previous_parameter_values = capture_parameter_values(
        engine.adapter,
        snapshot_parameter_indices(engine:get_snapshot())
    )
    local previous_record = clone(self.active.record)
    local previous_cursor_dirty = self.cursor_dirty
    local previous_parameters_dirty = self.parameters_dirty
    local result, result_error = engine:set_parameter_clamp(
        parameter_index,
        minimum,
        maximum
    )
    if result == false then
        restore_engine_state(
            engine,
            self.snapshot_class.from_data(previous_snapshot_data),
            previous_last_applied_values,
            previous_parameter_values
        )
        restore_table(self.active.record, previous_record)
        self.cursor_dirty = previous_cursor_dirty
        self.parameters_dirty = previous_parameters_dirty
        return false, result_error
    end

    self:_sync_active_record()
    self.parameters_dirty = true
    return true
end

function TrackFXMatrixController:set_bypass(parameter_index, bypassed)
    return self:_mutate("set_bypass", parameter_index, bypassed)
end

function TrackFXMatrixController:remove_parameter_from_corner(parameter_index, corner_id)
    return self:_mutate("remove_parameter_from_corner", parameter_index, corner_id)
end

function TrackFXMatrixController:remove_all_parameters_from_corner(corner_id)
    return self:_mutate("remove_all_parameters_from_corner", corner_id)
end

function TrackFXMatrixController:save_corner(corner_id)
    return self:_mutate("save_corner", corner_id)
end

function TrackFXMatrixController:save_parameter_to_corner(parameter_index, corner_id)
    return self:_mutate("save_parameter_to_corner", parameter_index, corner_id)
end

function TrackFXMatrixController:randomize_corner(corner_id)
    return self:_mutate("randomize_corner", corner_id)
end

function TrackFXMatrixController:randomize_all()
    return self:_mutate("randomize_all")
end

function TrackFXMatrixController:save_preset(path, name)
    if not self.active then
        return false, "no Track-FX instance is registered"
    end
    if type(path) ~= "string" or path == "" then
        return false, "Preset save path is unavailable"
    end

    local reconciled, reconcile_error = self:reconcile_active_parameters()
    if reconciled == false then
        return false, reconcile_error
    end

    local preset = TrackFXMatrixPreset.from_snapshot(
        self.active.engine:get_snapshot(),
        self.active.descriptor.plugin_identity,
        name or preset_name_from_path(path)
    )
    if not preset then
        return false, "unable to create Preset from the active Track-FX"
    end
        local saved, save_error = self:_get_preset_file():save(path, preset)
        if saved then
            self.loaded_preset_name = preset.name ~= "" and preset.name or nil
        end
        return saved, save_error
end

function TrackFXMatrixController:load_preset(path)
    if not self.active then
        return false, "no Track-FX instance is registered"
    end
    if type(path) ~= "string" or path == "" then
        return false, "Preset load path is unavailable"
    end

    local reconciled, reconcile_error = self:reconcile_active_parameters()
    if reconciled == false then
        return false, reconcile_error
    end

    local preset_file = self:_get_preset_file()
    local preset, load_error = preset_file:load(path)
    if not preset then
        return false, load_error
    end

    local report = preset_file:inspect(preset, self.active.descriptor.adapter)
    self.last_preset_report = report
    local report_message = format_preset_report(report)
    if not report.compatible then
        return false, report_message
    end

    local engine = self.active.engine
    local previous_snapshot = engine:get_snapshot()
    local previous_last_applied_values = clone(engine.last_applied_values)
    local parameter_indices = snapshot_parameter_indices(previous_snapshot)
    for _, parameter in ipairs(preset.parameters) do
        if type(parameter) == "table" and parameter.index ~= nil then
            parameter_indices[parameter.index] = true
        end
    end
    local previous_parameter_values = capture_parameter_values(engine.adapter, parameter_indices)
    local previous_record = clone(self.active.record)
    local previous_cursor_dirty = self.cursor_dirty
    local previous_parameters_dirty = self.parameters_dirty
    local previous_loaded_preset_name = self.loaded_preset_name
    local function rollback()
        restore_engine_state(
            engine,
            previous_snapshot,
            previous_last_applied_values,
            previous_parameter_values
        )
        restore_table(self.active.record, previous_record)
        self.cursor_dirty = previous_cursor_dirty
        self.parameters_dirty = previous_parameters_dirty
        self.loaded_preset_name = previous_loaded_preset_name
    end

    local loaded_count, load_error = engine:load_preset(preset.parameters, preset.cursor)
    if loaded_count == false then
        rollback()
        return false, load_error or "unable to load Preset parameters"
    end

    local saved, save_error = self:save()
    if not saved then
        rollback()
        return false, save_error
    end
    self.loaded_preset_name = preset.name ~= "" and preset.name or nil
    return loaded_count, report_message
end

function TrackFXMatrixController:reset_corners_to_baseline()
    return self:_mutate("reset_corners_to_baseline")
end

function TrackFXMatrixController:move_cursor(x, y)
    if not self.active then
        return false, "no Track-FX instance is registered"
    end

    local reconciled, reconcile_error = self:reconcile_active_parameters()
    if reconciled == false then
        return false, reconcile_error
    end

    local engine = self.active.engine
    local previous_snapshot_data = engine:get_snapshot():to_data()
    local previous_last_applied_values = clone(engine.last_applied_values)
    local previous_parameter_values = capture_parameter_values(
        engine.adapter,
        snapshot_parameter_indices(engine:get_snapshot())
    )
    local previous_cursor_dirty = self.cursor_dirty
    local previous_parameters_dirty = self.parameters_dirty
    local result, result_error = engine:move_cursor(x, y)
    if not result then
        restore_engine_state(
            engine,
            self.snapshot_class.from_data(previous_snapshot_data),
            previous_last_applied_values,
            previous_parameter_values
        )
        self.cursor_dirty = previous_cursor_dirty
        self.parameters_dirty = previous_parameters_dirty
        return false, result_error
    end

    self:_sync_active_record()
    self.cursor_dirty = true
    return true
end

function TrackFXMatrixController:commit_cursor()
    if not self.active then
        return true
    end
    if not self.cursor_dirty and not self.parameters_dirty then
        return true
    end
    if not is_valid_track(self.api, self.track) then
        self.cursor_dirty = false
        self.parameters_dirty = false
        return true
    end

    local reconciled, reconcile_error = self:reconcile_active_parameters()
    if reconciled == false then
        return false, reconcile_error
    end
    if not self.cursor_dirty and not self.parameters_dirty then
        return true
    end
    return self:save()
end

function TrackFXMatrixController:apply_current_values()
    if not self.active then
        return false
    end

    local reconciled, reconcile_error = self:reconcile_active_parameters()
    if reconciled == false then
        return false, reconcile_error
    end
    return self.active.engine:apply_current_values()
end

return TrackFXMatrixController