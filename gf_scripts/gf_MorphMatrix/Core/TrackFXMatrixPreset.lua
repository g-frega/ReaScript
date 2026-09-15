-- @noindex

local TrackFXMatrixPreset = {}
TrackFXMatrixPreset.__index = TrackFXMatrixPreset

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

function TrackFXMatrixPreset.new(plugin_identity, parameters, name, cursor)
    if type(plugin_identity) ~= "table" then
        error("TrackFXMatrixPreset requires plugin identity")
    end

    return setmetatable({
        schema_version = 1,
        name = name or "",
        plugin_identity = clone(plugin_identity),
        parameters = clone(parameters or {}),
        cursor = clone(cursor),
    }, TrackFXMatrixPreset)
end

function TrackFXMatrixPreset.from_snapshot(snapshot, plugin_identity, name)
    if not snapshot or type(snapshot.to_data) ~= "function" then
        return nil
    end

    local snapshot_data = snapshot:to_data()
    return TrackFXMatrixPreset.new(plugin_identity, snapshot_data.parameters, name, snapshot_data.cursor)
end

function TrackFXMatrixPreset:to_data()
    return {
        schema_version = self.schema_version,
        name = self.name,
        plugin_identity = clone(self.plugin_identity),
        parameters = clone(self.parameters),
        cursor = clone(self.cursor),
    }
end

function TrackFXMatrixPreset.from_data(data)
    if type(data) ~= "table"
        or type(data.plugin_identity) ~= "table"
        or type(data.parameters) ~= "table" then
        return nil
    end

    return TrackFXMatrixPreset.new(data.plugin_identity, data.parameters, data.name, data.cursor)
end

return TrackFXMatrixPreset
