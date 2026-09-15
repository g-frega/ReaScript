-- @noindex

local TrackFXJsonCodec = require("Core.TrackFXJsonCodec")
local TrackFXMatrixPreset = require("Core.TrackFXMatrixPreset")
local TrackFXPluginIdentity = require("Core.TrackFXPluginIdentity")

local TrackFXPresetFile = {}
TrackFXPresetFile.__index = TrackFXPresetFile

function TrackFXPresetFile.new(options)
    options = options or {}
    return setmetatable({
        codec = options.codec or TrackFXJsonCodec,
        file_api = options.file_api or io,
    }, TrackFXPresetFile)
end

function TrackFXPresetFile:save(path, preset)
    if type(path) ~= "string" or type(preset) ~= "table" or type(preset.to_data) ~= "function" then
        return false, "Preset file save requires a path and Preset"
    end

    local ok, data = pcall(preset.to_data, preset)
    if not ok then
        return false, "unable to read Preset data"
    end
    local encode_ok, serialized = pcall(self.codec.encode, data)
    if not encode_ok or type(serialized) ~= "string" then
        return false, "unable to encode Preset"
    end

    if type(self.file_api.open) ~= "function" then
        return false, "Preset file API is unavailable"
    end
    local open_ok, file, open_error = pcall(self.file_api.open, path, "w")
    if not open_ok or not file then
        return false, (not open_ok and tostring(file) or open_error)
            or "unable to open Preset file for writing"
    end

    local write_ok, write_result, write_error = pcall(file.write, file, serialized)
    local close_ok, close_result, close_error = pcall(file.close, file)
    if not write_ok or write_result == false or write_result == nil then
        return false, (not write_ok and tostring(write_result) or write_error)
            or "unable to write Preset file"
    end
    if not close_ok or close_result == false then
        return false, (not close_ok and tostring(close_result) or close_error)
            or "unable to close Preset file"
    end
    return true
end

function TrackFXPresetFile:load(path)
    if type(path) ~= "string" then
        return nil, "Preset file load requires a path"
    end

    if type(self.file_api.open) ~= "function" then
        return nil, "Preset file API is unavailable"
    end
    local open_ok, file, open_error = pcall(self.file_api.open, path, "r")
    if not open_ok or not file then
        return nil, (not open_ok and tostring(file) or open_error)
            or "unable to open Preset file for reading"
    end
    local read_ok, serialized, read_error = pcall(file.read, file, "*a")
    local close_ok, close_result, close_error = pcall(file.close, file)
    if not read_ok or type(serialized) ~= "string" then
        return nil, (not read_ok and tostring(serialized) or read_error)
            or "unable to read Preset file"
    end
    if not close_ok or close_result == false then
        return nil, (not close_ok and tostring(close_result) or close_error)
            or "unable to close Preset file"
    end

    local decode_ok, decoded = pcall(self.codec.decode, serialized)
    if not decode_ok then
        return nil, "invalid Preset JSON"
    end
    local preset = TrackFXMatrixPreset.from_data(decoded)
    if not preset then
        return nil, "invalid Preset document"
    end
    return preset
end

function TrackFXPresetFile:inspect(preset, adapter)
    local report = {
        compatible = false,
        plugin_identity_matches = false,
        warnings = {},
        missing_parameters = {},
    }
    if type(preset) ~= "table" or type(preset.to_data) ~= "function" then
        report.warnings[#report.warnings + 1] = "Preset data is unavailable"
        return report
    end
    if not adapter or type(adapter.get_identity) ~= "function" then
        report.warnings[#report.warnings + 1] = "Track-FX identity is unavailable"
        return report
    end

    local data = preset:to_data()
    local current_identity = adapter:get_identity()
    report.plugin_identity_matches = TrackFXPluginIdentity.matches(
        data.plugin_identity,
        current_identity
    )
    if not report.plugin_identity_matches then
        report.warnings[#report.warnings + 1] = "Preset plugin identity does not match the current FX"
    elseif TrackFXPluginIdentity.is_weak(data.plugin_identity)
        or TrackFXPluginIdentity.is_weak(current_identity) then
        report.warnings[#report.warnings + 1] = "Plugin match relies on format and factory name"
    end

    local parameter_count = adapter:get_parameter_count()
    if type(parameter_count) == "number" then
        for _, parameter in ipairs(data.parameters) do
            local parameter_is_missing = type(parameter.index) ~= "number"
                or parameter.index < 0
                or parameter.index >= parameter_count
            if not parameter_is_missing
                and type(adapter.is_parameter_available) == "function"
                and not adapter:is_parameter_available(parameter.index, parameter.ident) then
                parameter_is_missing = true
            end
            if parameter_is_missing then
                report.missing_parameters[#report.missing_parameters + 1] = {
                    index = parameter.index,
                    name = parameter.name,
                }
            end
        end
    else
        report.warnings[#report.warnings + 1] = "Current FX parameter count is unavailable"
    end

    report.compatible = report.plugin_identity_matches and #report.missing_parameters == 0
    return report
end

return TrackFXPresetFile