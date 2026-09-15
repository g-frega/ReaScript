-- @noindex
-- Scatter Instrument: Plan generation, apply, cleanup, and build

---------------------------------------------------------
--          Scatter Generation Engine                  --
---------------------------------------------------------

function SI.generateScatterPlan(containerItem, params)
    local itemPos = r.GetMediaItemInfo_Value(containerItem, "D_POSITION")
    local itemLen = r.GetMediaItemInfo_Value(containerItem, "D_LENGTH")
    local itemEnd = itemPos + itemLen

    local takeCount = r.CountTakes(containerItem)
    if takeCount < 1 then return {} end

    local containerGUID = SI.getItemGUID(containerItem)
    local plan = {}

    if params.playMode == "single" then
        local takeIdx = SI.pickTake(containerGUID, takeCount, params.playlistMode)
        local volDB = SI.randomFloat(params.volRnd, 0)
        local pitchST = SI.randomFloat(-params.pitchRnd, params.pitchRnd)
        plan[#plan + 1] = {
            time = itemPos,
            takeIdx = takeIdx,
            volDB = volDB,
            pitchST = pitchST,
        }
        return plan
    end

    local rate = (params.spawnRate or 100) / 100
    if rate <= 0 then rate = 0.01 end
    local minInt = (params.minInterval / 1000) / rate
    local maxInt = (params.maxInterval / 1000) / rate

    local currentTime = itemPos
    local spawnCount = 0

    -- First spawn is always immediate at item start
    for _ = 1, 1 do
        local takeIdx = SI.pickTake(containerGUID, takeCount, params.playlistMode)
        local volDB = SI.randomFloat(params.volRnd, 0)
        local pitchST = SI.randomFloat(-params.pitchRnd, params.pitchRnd)

        plan[#plan + 1] = {
            time = itemPos,
            takeIdx = takeIdx,
            volDB = volDB,
            pitchST = pitchST,
        }
        spawnCount = spawnCount + 1
    end

    while currentTime < itemEnd do
        if spawnCount == 0 then
            currentTime = itemPos
        else
            local progress = (currentTime - itemPos) / math.max(itemLen, 0.000001)
            local interval = SI.getStartBiasedInterval(minInt, maxInt, progress)
            currentTime = currentTime + interval
        end

        if currentTime >= itemEnd then break end

        local takeIdx = SI.pickTake(containerGUID, takeCount, params.playlistMode)
        local volDB = SI.randomFloat(params.volRnd, 0)
        local pitchST = SI.randomFloat(-params.pitchRnd, params.pitchRnd)

        plan[#plan + 1] = {
            time = currentTime,
            takeIdx = takeIdx,
            volDB = volDB,
            pitchST = pitchST,
        }
        spawnCount = spawnCount + 1
    end

    return plan
end

---------------------------------------------------------
--              Cleanup                                --
---------------------------------------------------------

function SI.cleanupScatteredItems(containerItem)
    local containerGUID = SI.getItemGUID(containerItem)
    local searchTag = SI.SPAWNED_TAG .. "(" .. containerGUID .. ")"
    local itemsToDelete = {}

    local numItems = r.CountMediaItems(0)
    for i = 0, numItems - 1 do
        local item = r.GetMediaItem(0, i)
        local notes = SI.getItemNotes(item)
        if notes:find(searchTag, 1, true) then
            itemsToDelete[#itemsToDelete + 1] = item
        end
    end

    for _, item in ipairs(itemsToDelete) do
        local track = r.GetMediaItem_Track(item)
        if track then
            r.DeleteTrackMediaItem(track, item)
        end
    end

    -- Delete voice tracks (container track is the parent folder, keep it)
    local tracksToDelete = {}
    local voicePrefix = SI.getVoiceFolderName(containerGUID) .. " V"
    local trackCount = r.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = r.GetTrack(0, i)
        local _, trackName = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if trackName:sub(1, #voicePrefix) == voicePrefix then
            tracksToDelete[#tracksToDelete + 1] = track
        end
    end

    for i = #tracksToDelete, 1, -1 do
        r.DeleteTrack(tracksToDelete[i])
    end

    -- Show voice tracks back before deleting (in case they were hidden)
    SI.setVoiceTracksVisible(containerGUID, true)

    -- Reset container track folder depth since children are gone
    local containerTrack = r.GetMediaItem_Track(containerItem)
    if containerTrack then
        r.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 0)
    end
end

---------------------------------------------------------
--     Apply Scatter Plan to Tracks                    --
---------------------------------------------------------

function SI.applyScatterToTrack(containerItem, plan)
    if #plan == 0 then return end

    local containerTrack = r.GetMediaItem_Track(containerItem)
    if not containerTrack then return end

    local containerGUID = SI.getItemGUID(containerItem)
    local spawnedTag = SI.SPAWNED_TAG .. "(" .. containerGUID .. ")"
    local containerNotes = SI.getItemNotes(containerItem)
    local params = SI.readParams(containerNotes)

    local maxVoices = math.max(1, math.floor(params.polyphony or 1))
    if params.playMode == "single" then
        maxVoices = math.huge
    end
    local FADE_OUT_MS = 15

    -- Get take sources from container
    local takeSources = {}
    local takeLengths = {}
    local takeCount = r.CountTakes(containerItem)
    for i = 0, takeCount - 1 do
        local take = r.GetTake(containerItem, i)
        if take then
            local source = r.GetMediaItemTake_Source(take)
            takeSources[i] = source
            if source then
                local length = r.GetMediaSourceLength(source)
                takeLengths[i] = length
            else
                takeLengths[i] = 1.0
            end
        end
    end

    local containerPos = r.GetMediaItemInfo_Value(containerItem, "D_POSITION")
    local containerLen = r.GetMediaItemInfo_Value(containerItem, "D_LENGTH")
    local containerEnd = containerPos + containerLen

    -- Create voice tracks lazily only when a spawn actually places an item
    local voiceTracks = {}

    local placed = {}

    r.SelectAllMediaItems(0, false)

    for spawnIdx, spawn in ipairs(plan) do
        local source = takeSources[spawn.takeIdx]
        if not source then goto continue end

        local sourceLen = takeLengths[spawn.takeIdx] or 1.0
        local playrate, finalDuration
        if params.pitchMode == "pitch" then
            playrate = 1.0
            finalDuration = sourceLen
        else
            playrate = 2 ^ (spawn.pitchST / 12)
            finalDuration = sourceLen / playrate
        end
        if finalDuration <= 0 then goto continue end

        -- Enforce polyphony: count concurrent at this spawn's start time
        local concurrent = {}
        for _, p in ipairs(placed) do
            if p.endTime > spawn.time then
                concurrent[#concurrent + 1] = p
            end
        end

        if #concurrent >= maxVoices then
            if params.stealing == "none" then
                goto continue
            end
            -- Steal: trim the oldest concurrent item
            table.sort(concurrent, function(a, b) return a.pos < b.pos end)
            local victim = concurrent[1]
            if victim and victim.item then
                local newLen = spawn.time - victim.pos
                if newLen > 0 then
                    r.SetMediaItemInfo_Value(victim.item, "D_LENGTH", newLen)
                    local fadeLen = math.min(FADE_OUT_MS / 1000, newLen * 0.5)
                    r.SetMediaItemInfo_Value(victim.item, "D_FADEOUTLEN", fadeLen)
                    victim.endTime = spawn.time
                else
                    local vTrack = r.GetMediaItem_Track(victim.item)
                    if vTrack then
                        r.DeleteTrackMediaItem(vTrack, victim.item)
                    end
                    victim.endTime = -math.huge
                end
            end
        end

        local targetIndex = #voiceTracks + 1
        if not voiceTracks[targetIndex] then
            voiceTracks = SI.ensureVoiceTracksInFolder(containerTrack, containerGUID, targetIndex)
        end

        local targetTrack = voiceTracks[targetIndex]
        if not targetTrack then goto continue end

        local newItem = r.AddMediaItemToTrack(targetTrack)
        if not newItem then goto continue end

        r.SetMediaItemInfo_Value(newItem, "D_POSITION", spawn.time)
        r.SetMediaItemInfo_Value(newItem, "D_LENGTH", finalDuration)

        local newTake = r.AddTakeToMediaItem(newItem)
        if newTake then
            r.SetMediaItemTake_Source(newTake, source)
            local amplitude = 10 ^ (spawn.volDB / 20)
            r.SetMediaItemInfo_Value(newItem, "D_VOL", amplitude)
            r.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
            if params.pitchMode == "pitch" then
                r.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 1)
                r.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", spawn.pitchST)
            else
                r.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)
                r.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", 0)
            end
        end

        SI.setItemNotes(newItem, spawnedTag)
        r.SetMediaItemSelected(newItem, true)

        placed[#placed + 1] = {
            pos = spawn.time,
            endTime = spawn.time + finalDuration,
            item = newItem,
        }

        ::continue::
    end

    -- Safety net: remove any empty runtime tracks left by skipped/trimmed spawns
    SI.pruneEmptyVoiceTracks(containerTrack, containerGUID)

    -- Hide voice tracks initially; monitor will reveal selected ones
    local activeVoiceTracks = SI.findVoiceTracksByGUID(containerGUID)
    for _, vt in ipairs(activeVoiceTracks) do
        if vt then
            r.SetMediaTrackInfo_Value(vt, "B_SHOWINTCP", 0)
            r.SetMediaTrackInfo_Value(vt, "B_SHOWINMIXER", 0)
        end
    end

    -- Wrap tails when repeat/loop mode is on
    local repeatOn = (r.GetSetRepeat(-1) == 1)
    if repeatOn then
        local wraps = {}
        for _, p in ipairs(placed) do
            if p.endTime > containerEnd and p.item then
                local tailLen = p.endTime - containerEnd
                wraps[#wraps + 1] = { item = p.item, tailLen = tailLen }
            end
        end

        if #wraps > 0 then
            local allTracks = voiceTracks
            local wrapTrackCount = #allTracks

            for wi, w in ipairs(wraps) do
                local origTake = r.GetActiveTake(w.item)
                if not origTake then goto wrapContinue end
                local origSource = r.GetMediaItemTake_Source(origTake)
                if not origSource then goto wrapContinue end
                local origPlayrate = r.GetMediaItemTakeInfo_Value(origTake, "D_PLAYRATE")
                local origPitch = r.GetMediaItemTakeInfo_Value(origTake, "D_PITCH")
                local origPreservePitch = r.GetMediaItemTakeInfo_Value(origTake, "B_PPITCH")
                local origVol = r.GetMediaItemInfo_Value(w.item, "D_VOL")

                local nextWrapIndex = wrapTrackCount + 1
                if not allTracks[nextWrapIndex] then
                    allTracks = SI.ensureVoiceTracksInFolder(containerTrack, containerGUID, nextWrapIndex)
                end

                local wrapTrack = allTracks[nextWrapIndex]
                if not wrapTrack then goto wrapContinue end

                local origPos = r.GetMediaItemInfo_Value(w.item, "D_POSITION")
                local sourceOffset = (containerEnd - origPos) * origPlayrate

                local wrapItem = r.AddMediaItemToTrack(wrapTrack)
                if not wrapItem then goto wrapContinue end

                r.SetMediaItemInfo_Value(wrapItem, "D_POSITION", containerPos)
                r.SetMediaItemInfo_Value(wrapItem, "D_LENGTH", w.tailLen)
                r.SetMediaItemInfo_Value(wrapItem, "D_VOL", origVol)

                local wrapTake = r.AddTakeToMediaItem(wrapItem)
                if wrapTake then
                    r.SetMediaItemTake_Source(wrapTake, origSource)
                    r.SetMediaItemTakeInfo_Value(wrapTake, "D_PLAYRATE", origPlayrate)
                    r.SetMediaItemTakeInfo_Value(wrapTake, "D_PITCH", origPitch)
                    r.SetMediaItemTakeInfo_Value(wrapTake, "B_PPITCH", origPreservePitch)
                    r.SetMediaItemTakeInfo_Value(wrapTake, "D_STARTOFFS", sourceOffset)
                end

                -- Trim original to container boundary
                local origLen = containerEnd - origPos
                if origLen > 0 then
                    r.SetMediaItemInfo_Value(w.item, "D_LENGTH", origLen)
                end

                SI.setItemNotes(wrapItem, spawnedTag)
                r.SetMediaItemSelected(wrapItem, true)
                wrapTrackCount = nextWrapIndex

                ::wrapContinue::
            end
            voiceTracks = allTracks
        end
    end
end

---------------------------------------------------------
--     Scatter / Cleanup All Containers                --
---------------------------------------------------------

function SI.scatterAllContainers()
    local numItems = r.CountMediaItems(0)
    if numItems == 0 then return end

    local containers = {}
    for i = 0, numItems - 1 do
        local item = r.GetMediaItem(0, i)
        local notes = SI.getItemNotes(item)
        if SI.isScatterContainer(notes) and not notes:find(SI.SPAWNED_TAG, 1, true) then
            containers[#containers + 1] = item
        end
    end

    for _, container in ipairs(containers) do
        local params = SI.readParams(SI.getItemNotes(container))
        if params.realtimePlayback == 1 then
            SI.setContainerImage(container, params.playMode)
            SI.cleanupScatteredItems(container)
            local plan = SI.generateScatterPlan(container, params)
            SI.applyScatterToTrack(container, plan)
        end
    end
end

function SI.cleanupAllScattered(onlyCleanupOnStop)
    local numItems = r.CountMediaItems(0)
    if numItems == 0 then return end

    local containers = {}
    for i = 0, numItems - 1 do
        local item = r.GetMediaItem(0, i)
        local notes = SI.getItemNotes(item)
        if SI.isScatterContainer(notes) and not notes:find(SI.SPAWNED_TAG, 1, true) then
            containers[#containers + 1] = item
        end
    end

    for _, container in ipairs(containers) do
        if onlyCleanupOnStop then
            local params = SI.readParams(SI.getItemNotes(container))
            if params.cleanupOnStop == 1 then
                SI.cleanupScatteredItems(container)
            end
        else
            SI.cleanupScatteredItems(container)
        end
    end
end

---------------------------------------------------------
--        Build Scatter Container from Selection       --
---------------------------------------------------------

function SI.buildScatterContainerFromSelection()
    local numSelected = r.CountSelectedMediaItems(0)
    if numSelected < 2 then
        r.ShowMessageBox(
            "Select at least 2 items to build a Scatter Container.",
            "Scatter Instrument", 0)
        return nil
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local firstItem = r.GetSelectedMediaItem(0, 0)
    local firstPos = r.GetMediaItemInfo_Value(firstItem, "D_POSITION")
    local track = r.GetMediaItem_Track(firstItem)
    local maxLen = 0

    local sources = {}
    local sourceItems = {}
    for i = 0, numSelected - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local take = r.GetActiveTake(item)
        if take then
            local source = r.GetMediaItemTake_Source(take)
            local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            if len > maxLen then maxLen = len end
            sources[#sources + 1] = source
            sourceItems[#sourceItems + 1] = item
        end
    end

    if #sources == 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Scatter Instrument: Build (failed)", -1)
        return nil
    end

    local newItem = r.AddMediaItemToTrack(track)
    r.SetMediaItemInfo_Value(newItem, "D_POSITION", firstPos)
    r.SetMediaItemInfo_Value(newItem, "D_LENGTH", maxLen)

    for i, source in ipairs(sources) do
        local newTake = r.AddTakeToMediaItem(newItem)
        if newTake and source then
            r.SetMediaItemTake_Source(newTake, source)
            local sourceFn = r.GetMediaSourceFileName(source)
            local name = sourceFn:match("([^/\\]+)$") or ("Take " .. i)
            r.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", name, true)
        end
    end

    local firstTake = r.GetTake(newItem, 0)
    if firstTake then r.SetActiveTake(firstTake) end

    SI.tagItemAsScatterContainer(newItem)
    r.SetMediaItemInfo_Value(newItem, "B_MUTE", 1)

    -- Delete original source items
    for i = #sourceItems, 1, -1 do
        local srcTrack = r.GetMediaItem_Track(sourceItems[i])
        if srcTrack then
            r.DeleteTrackMediaItem(srcTrack, sourceItems[i])
        end
    end

    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(newItem, true)

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("Scatter Instrument: Build Container", -1)

    return newItem
end

function SI.revertScatterContainer(containerItem)
    if not containerItem then return false end

    local notes = SI.getItemNotes(containerItem)
    if not SI.isScatterContainer(notes) then return false end

    local containerTrack = r.GetMediaItem_Track(containerItem)
    if not containerTrack then return false end

    local containerPos = r.GetMediaItemInfo_Value(containerItem, "D_POSITION")
    local containerLen = r.GetMediaItemInfo_Value(containerItem, "D_LENGTH")
    local takeCount = r.CountTakes(containerItem)
    if takeCount < 1 then return false end

    local runningPos = containerPos

    -- Remove all spawned runtime items/tracks linked to this container first.
    SI.cleanupScatteredItems(containerItem)

    for i = 1, takeCount do
        local take = r.GetTake(containerItem, i - 1)
        if take then
            local source = r.GetMediaItemTake_Source(take)
            if source then
                local len = nil

                if not len or len <= 0 then
                    local sourceLen = r.GetMediaSourceLength(source)
                    if sourceLen and sourceLen > 0 then
                        len = sourceLen
                    else
                        len = containerLen
                    end
                end

                local newItem = r.AddMediaItemToTrack(containerTrack)
                if newItem then
                    r.SetMediaItemInfo_Value(newItem, "D_POSITION", runningPos)
                    r.SetMediaItemInfo_Value(newItem, "D_LENGTH", len)
                    r.SetMediaItemInfo_Value(newItem, "B_MUTE", 0)
                    SI.setItemNotes(newItem, "")

                    local newTake = r.AddTakeToMediaItem(newItem)
                    if newTake then
                        r.SetMediaItemTake_Source(newTake, source)
                        local _, takeName = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                        takeName = takeName or ""
                        if takeName:sub(1, 8) == "SCATTER-" then
                            takeName = takeName:sub(9)
                        end
                        if takeName ~= "" then
                            r.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", takeName, true)
                        end
                    end

                    runningPos = runningPos + len
                end
            end
        end
    end

    local scatterTrack = r.GetMediaItem_Track(containerItem)
    if scatterTrack then
        r.DeleteTrackMediaItem(scatterTrack, containerItem)
    end

    return true
end
