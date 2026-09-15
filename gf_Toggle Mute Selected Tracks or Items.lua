-- @description Toggle mute for selected tracks or items
-- @version 1.0.3
-- @author Giacomo Frega
-- @about
--   Toggles selected items when any are selected; otherwise toggles selected tracks.

-- Toggle mute state for selected tracks or items in REAPER

-- Function to toggle mute state for selected tracks
local function toggle_mute_selected_tracks()
    local num_tracks = reaper.CountSelectedTracks(0)
    for i = 0, num_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then
            local is_muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
            reaper.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted == 0 and 1 or 0) -- Toggle mute state
        end
    end
end

-- Function to toggle mute state for selected items
local function toggle_mute_selected_items()
    local num_items = reaper.CountSelectedMediaItems(0)
    for i = 0, num_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local is_muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
            reaper.SetMediaItemInfo_Value(item, "B_MUTE", is_muted == 0 and 1 or 0) -- Toggle mute state
        end
    end
end

local function main()
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- Check if there are selected items first
    if reaper.CountSelectedMediaItems(0) > 0 then
        toggle_mute_selected_items()
    else
        toggle_mute_selected_tracks()
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Toggle mute selected tracks or items", -1)
end

main()

