-- @description Toggle parent collapse state and mute its child tracks
-- @version 1.0.0
-- @author Giacomo Frega
-- @about
--   Collapses or expands the selected parent track and toggles its child-track mute state.

local function get_selected_tracks()
  local selected = {}
  local count = reaper.CountSelectedTracks(0)
  for i = 0, count - 1 do
    selected[#selected + 1] = reaper.GetSelectedTrack(0, i)
  end
  return selected
end

local function restore_selected_tracks(selected)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    reaper.SetMediaTrackInfo_Value(track, "I_SELECTED", 0)
  end

  for i = 1, #selected do
    if selected[i] then
      reaper.SetMediaTrackInfo_Value(selected[i], "I_SELECTED", 1)
    end
  end
end

local function sel_first_level_children_of_parent(tr_id)
  -- Get the parent track of the currently selected track
  local parent = reaper.GetParentTrack(tr_id)
  
  if not parent then return end -- Exit if there is no parent track
  
  -- Unselect all tracks first
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    reaper.SetMediaTrackInfo_Value(track, "I_SELECTED", 0)
  end
  
  -- Iterate through all tracks to find first-level children of the parent track
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local track_parent = reaper.GetParentTrack(track)
    
    -- Check if the track is a child of the parent and is a first-level child
    if track_parent == parent and reaper.GetTrackDepth(track) == 1 then
      reaper.SetMediaTrackInfo_Value(track, "I_SELECTED", 1) -- Select the first-level child track
    end
  end
end

local function toggle_track_collapse()
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local isCollapsed = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT")
    for j = 0, reaper.CountTracks(0) - 1 do
      local child_track = reaper.GetTrack(0, j)
      local child_track_parent = reaper.GetParentTrack(child_track)
      if child_track_parent == track then
        if isCollapsed == 0 then
          reaper.SetMediaTrackInfo_Value(child_track, "B_MUTE", 1) -- Mute children tracks
        else
          reaper.SetMediaTrackInfo_Value(child_track, "B_MUTE", 0) -- Unmute children tracks
        end
      end
    end
  end
  reaper.Main_OnCommand(1042, 0) -- Toggle track collapse
end

local function main()
  local saved_selection = get_selected_tracks()
  local tr_id = reaper.GetSelectedTrack(0, 0)
  if not tr_id then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  sel_first_level_children_of_parent(tr_id)
  local isCollapsed = reaper.GetMediaTrackInfo_Value(tr_id, "I_FOLDERCOMPACT")
  for i = 0, reaper.CountTracks(0) - 1 do
    local child_track = reaper.GetTrack(0, i)
    local child_track_parent = reaper.GetParentTrack(child_track)
    if child_track_parent == tr_id then
      if isCollapsed == 0 then
        reaper.SetMediaTrackInfo_Value(child_track, "B_MUTE", 1) -- Mute children tracks
      else
        reaper.SetMediaTrackInfo_Value(child_track, "B_MUTE", 0) -- Unmute children tracks
      end
    end
  end
  toggle_track_collapse()

  restore_selected_tracks(saved_selection)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Toggle collapse and mute child tracks", -1)
end

main()

