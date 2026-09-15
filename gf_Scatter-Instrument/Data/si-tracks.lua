-- @noindex
-- Scatter Instrument: Voice track creation and management

function SI.getVoiceTrackName(containerGUID, voiceIndex)
    return string.format("SI %s V%d", containerGUID, voiceIndex)
end

function SI.getVoiceFolderName(containerGUID)
    return string.format("SI %s", containerGUID)
end

function SI.findTrackByName(name)
    local trackCount = r.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = r.GetTrack(0, i)
        local _, trackName = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if trackName == name then
            return track
        end
    end
    return nil
end

function SI.getOrCreateVoiceFolderTrack(containerTrack, containerGUID)
    -- Use the container item's own track as the parent folder
    return containerTrack
end

function SI.ensureVoiceTracksInFolder(containerTrack, containerGUID, maxVoices)
    local folderTrack = SI.getOrCreateVoiceFolderTrack(containerTrack, containerGUID)
    if not folderTrack then return {} end

    local folderIdx = SI.getTrackIndex(folderTrack)
    local voiceTracks = {}

    for v = 1, maxVoices do
        local name = SI.getVoiceTrackName(containerGUID, v)
        local voiceTrack = SI.findTrackByName(name)
        if not voiceTrack then
            local insertIndex = folderIdx + v
            r.InsertTrackAtIndex(insertIndex, true)
            voiceTrack = r.GetTrack(0, insertIndex)
            if voiceTrack then
                r.GetSetMediaTrackInfo_String(voiceTrack, "P_NAME", name, true)
            end
        end
        voiceTracks[v] = voiceTrack
    end

    r.SetMediaTrackInfo_Value(folderTrack, "I_FOLDERDEPTH", 1)
    for v = 1, maxVoices do
        local depth = (v == maxVoices) and -1 or 0
        if voiceTracks[v] then
            r.SetMediaTrackInfo_Value(voiceTracks[v], "I_FOLDERDEPTH", depth)
        end
    end

    return voiceTracks
end

function SI.findVoiceTracksByGUID(containerGUID)
    local voicePrefix = SI.getVoiceFolderName(containerGUID) .. " V"
    local tracks = {}
    local trackCount = r.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = r.GetTrack(0, i)
        local _, trackName = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if trackName:sub(1, #voicePrefix) == voicePrefix then
            tracks[#tracks + 1] = track
        end
    end
    return tracks
end

function SI.setVoiceTracksVisible(containerGUID, visible)
    local tracks = SI.findVoiceTracksByGUID(containerGUID)
    for _, track in ipairs(tracks) do
        local selfSelected = r.IsTrackSelected(track)
        local showVal = (visible or selfSelected) and 1 or 0
        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", showVal)
        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", showVal)
    end
end

function SI.updateAllVoiceTrackVisibility()
    local numItems = r.CountMediaItems(0)
    for i = 0, numItems - 1 do
        local item = r.GetMediaItem(0, i)
        local notes = SI.getItemNotes(item)
        if SI.isScatterContainer(notes) and not notes:find(SI.SPAWNED_TAG, 1, true) then
            local guid = SI.getItemGUID(item)
            local track = r.GetMediaItem_Track(item)
            local params = SI.readParams(notes)
            local hide = (params.hideVoiceTracks == 1)
            local selected = track and r.IsTrackSelected(track)
            local visible = (not hide) and selected
            SI.setVoiceTracksVisible(guid, visible)
        end
    end
end

function SI.pruneEmptyVoiceTracks(containerTrack, containerGUID)
    local voiceTracks = SI.findVoiceTracksByGUID(containerGUID)
    local tracksToDelete = {}

    for _, track in ipairs(voiceTracks) do
        if r.CountTrackMediaItems(track) == 0 then
            tracksToDelete[#tracksToDelete + 1] = track
        end
    end

    for i = #tracksToDelete, 1, -1 do
        r.DeleteTrack(tracksToDelete[i])
    end

    local remaining = SI.findVoiceTracksByGUID(containerGUID)
    if not containerTrack then return end

    if #remaining == 0 then
        r.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 0)
        return
    end

    r.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 1)
    for i, track in ipairs(remaining) do
        local depth = (i == #remaining) and -1 or 0
        r.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", depth)
    end
end
