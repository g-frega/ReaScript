-- @noindex

local TrackFXProjectStore = {}
TrackFXProjectStore.__index = TrackFXProjectStore
TrackFXProjectStore.KEY = "P_EXT:gf_MorphMatrix_TrackFX"

local function new_document()
    return {
        schema_version = 1,
        instances = {},
    }
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

function TrackFXProjectStore.new(track, api, codec)
    if not track then
        error("TrackFXProjectStore requires a track")
    end

    return setmetatable({
        track = track,
        api = api or reaper,
        codec = codec or require("Core.TrackFXJsonCodec"),
    }, TrackFXProjectStore)
end

function TrackFXProjectStore.new_document()
    return new_document()
end

function TrackFXProjectStore:load()
    if not is_valid_track(self.api, self.track) then
        return nil, "Track-FX project track is unavailable"
    end

    local ok, exists, serialized = pcall(
        self.api.GetSetMediaTrackInfo_String,
        self.track,
        self.KEY,
        "",
        false
    )
    if not ok then
        return nil, "unable to read Track-FX project state: " .. tostring(exists)
    end
    if not exists or not serialized or serialized == "" then
        return new_document()
    end

    local ok, document = pcall(self.codec.decode, serialized)
    if not ok or type(document) ~= "table" then
        return nil, "invalid Track-FX project state"
    end
    if type(document.instances) ~= "table" then
        return nil, "Track-FX project state has no instance container"
    end

    return document
end

function TrackFXProjectStore:save(document)
    if type(document) ~= "table" then
        return false, "Track-FX project state must be a table"
    end
    if not is_valid_track(self.api, self.track) then
        return false, "Track-FX project track is unavailable"
    end

    local ok, serialized = pcall(self.codec.encode, document)
    if not ok or type(serialized) ~= "string" then
        return false, "unable to encode Track-FX project state"
    end

    local ok, result, result_error = pcall(
        self.api.GetSetMediaTrackInfo_String,
        self.track,
        self.KEY,
        serialized,
        true
    )
    if not ok or result ~= true then
        return false, (not ok and tostring(result) or result_error)
            or "unable to save Track-FX project state"
    end
    return true
end

function TrackFXProjectStore:clear()
    if not is_valid_track(self.api, self.track) then
        return false, "Track-FX project track is unavailable"
    end

    local ok, result, result_error = pcall(
        self.api.GetSetMediaTrackInfo_String,
        self.track,
        self.KEY,
        "",
        true
    )
    if not ok or result ~= true then
        return false, (not ok and tostring(result) or result_error)
            or "unable to clear Track-FX project state"
    end
    return true
end

return TrackFXProjectStore
