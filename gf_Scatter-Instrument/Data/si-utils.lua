-- @noindex
-- Scatter Instrument: Shared state, constants, and utility functions

SI = SI or {}

---------------------------------------------------------
--                 Global State                        --
---------------------------------------------------------

SI.scriptID = "ScatterInstrument"
SI.isRunning = true
SI.runInBackground = (r.GetExtState(SI.scriptID, "RunInBackground") == "1")

SI.lastPlayState = -1
SI.lastPlayPos = 0
SI.shuffleBags = {}       -- containerGUID -> {values={}, takeCount=n, lastPick=index}
SI.sequentialIndices = {}  -- containerGUID -> integer

---------------------------------------------------------
--           Constants & Defaults                      --
---------------------------------------------------------

SI.TAG_HEADER = "#---------Scatter Instrument---------"
SI.TAG_PREFIX = "#si_"
SI.SPAWNED_TAG = "#si_spawned"
SI.ITEM_IMAGE_FLAGS = 3 -- Stretch image mode
SI.ROOT_PATH = DATA_PATH:match("^(.*[\\/])Data[\\/]$") or DATA_PATH
SI.IMAGES_PATH = SI.ROOT_PATH .. "Images" .. SEP
SI.IMAGE_SCATTERMODE = SI.IMAGES_PATH .. "si-bg-scattermode.png"
SI.IMAGE_SINGLEMODE = SI.IMAGES_PATH .. "si-bg-singlemode.png"

SI.DEFAULTS = {
    minInterval = 300,      -- ms
    maxInterval = 1500,     -- ms
    spawnRate = 100,        -- percent (divides interval)
    volRnd = -6,            -- dB (range: 0 to this value)
    pitchRnd = 2.0,         -- semitones (±)
    pitchMode = "rate",     -- "rate" = Playback Rate, "pitch" = Item Pitch adjust
    playMode = "scatter",  -- "scatter" or "single"
    polyphony = 4,          -- max simultaneous voices
    stealing = "oldest",    -- "oldest" or "none"
    playlistMode = "shuffle", -- "shuffle", "random", "sequential"
    realtimePlayback = 1,   -- 1 = generate/cleanup automatically during transport playback
    cleanupOnStop = 1,      -- 1 = remove spawned items on stop
    hideVoiceTracks = 0,    -- 1 = hide voice tracks in TCP/MCP during playback
}

---------------------------------------------------------
--           Utility Functions                         --
---------------------------------------------------------

function SI.getItemGUID(item)
    return r.BR_GetMediaItemGUID(item)
end

function SI.getItemNotes(item)
    local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    return notes or ""
end

function SI.setItemNotes(item, notes)
    r.GetSetMediaItemInfo_String(item, "P_NOTES", notes, true)
end

function SI.randomFloat(low, high)
    return low + (high - low) * math.random()
end

function SI.getStartBiasedInterval(minInt, maxInt, progress)
    if maxInt <= minInt then
        return minInt
    end
    local t = math.max(0, math.min(1, progress or 0))
    local exponent = 3.6 - (2.6 * t)
    local u = math.random() ^ exponent
    return minInt + ((maxInt - minInt) * u)
end

function SI.clamp(val, lo, hi)
    if val < lo then return lo end
    if val > hi then return hi end
    return val
end

function SI.round(x)
    return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
end

function SI.getTrackIndex(track)
    if not track then return -1 end
    local id = r.CSurf_TrackToID(track, false)
    if id < 1 then return -1 end
    return id - 1
end

function SI.setContainerImage(item, mode)
    if not item or not r.BR_SetMediaItemImageResource then return end

    local imagePath = SI.IMAGE_SCATTERMODE
    if mode == "single" then
        imagePath = SI.IMAGE_SINGLEMODE
    end

    r.BR_SetMediaItemImageResource(item, imagePath, SI.ITEM_IMAGE_FLAGS)
    r.UpdateItemInProject(item)
    r.UpdateArrange()
end
