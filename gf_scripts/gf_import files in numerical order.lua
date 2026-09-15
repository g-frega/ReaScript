-- @description Import files into tracks grouped by their four-digit filename prefix
-- @version 1.0.1
-- @author Giacomo Frega
-- @about
--   Prompts for a folder, imports its files, and creates one track per filename prefix.

-- Import and sort files by prefix
-- This script will import all files in a folder and sort them by the first 4 digits of their filenames
-- For example: all files starting with 1001 will go on a new track called 1001, and so on

-- Get the folder path from the user
local retval, folder = reaper.GetUserInputs("Import and sort files by prefix", 1, "Enter folder path:", "")
if not retval then return end -- Exit if user cancels

-- Get all files in the folder
local files = {}
local i = 0
repeat
  local file = reaper.EnumerateFiles(folder, i) -- Get the file name at index i
  if file then -- If the file exists
    table.insert(files, file) -- Add it to the files table
    i = i + 1 -- Increment the index
  end
until not file -- Repeat until no more files

-- Sort the files by their prefixes
local prefixes = {} -- A table to store the prefixes and their corresponding files
for _, file in ipairs(files) do -- Loop through all files
  local prefix = file:sub(1, 4) -- Get the first 4 characters of the file name as the prefix
  if not prefixes[prefix] then -- If the prefix is not in the table yet
    prefixes[prefix] = {} -- Create a new table for it
  end
  table.insert(prefixes[prefix], file) -- Add the file to the prefix table
end

-- Sort the prefixes in ascending order
local sorted_prefixes = {} -- A table to store the sorted prefixes
for prefix, _ in pairs(prefixes) do -- Loop through all prefixes
  table.insert(sorted_prefixes, prefix) -- Add them to the sorted table
end
table.sort(sorted_prefixes) -- Sort them in ascending order

-- Import and sort the files by tracks
reaper.Undo_BeginBlock() -- Start an undo block
reaper.PreventUIRefresh(1) -- Prevent UI refreshing
local track_index = 0 -- A variable to keep track of the track index

for _, prefix in ipairs(sorted_prefixes) do -- Loop through all sorted prefixes
  
  local files = prefixes[prefix] -- Get the files for this prefix
  
  local track = reaper.GetTrack(0, track_index) -- Get the track at the current index
  
  if not track then -- If the track does not exist
    
    reaper.InsertTrackAtIndex(track_index, true) -- Create a new track at the current index
    
    track = reaper.GetTrack(0, track_index) -- Get the new track
    
  end
  
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", prefix, true) -- Set the track name to the prefix
  
  local cursor_pos = reaper.GetCursorPosition() -- Get the current cursor position
  
  for _, file in ipairs(files) do -- Loop through all files for this prefix
    
    local file_path = folder .. "/" .. file -- Get the full file path
    
    reaper.SetMediaTrackInfo_Value(track, "I_SELECTED", 1) -- Select the current track
    
    reaper.SetEditCurPos(cursor_pos, false, false) -- Set the cursor position to where we want to import
    
    reaper.InsertMedia(file_path, 0) -- Import the file to the current track at the cursor position
    
    local item = reaper.GetSelectedMediaItem(0, 0) -- Get the imported item
    
    local item_len = 0
    if item then
      item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") -- Get the item length
    end
    
    cursor_pos = cursor_pos + item_len + 0.1 -- Update the cursor position to after the item plus a small gap
    
    reaper.SetMediaTrackInfo_Value(track, "I_SELECTED", 0) -- Unselect the current track
    
  end
  
  track_index = track_index + 1 -- Increment the track index
  
end

reaper.PreventUIRefresh(-1) -- Restore UI refreshing
reaper.UpdateArrange() -- Update the arrange view
reaper.Undo_EndBlock("Import and sort files by prefix", -1) -- End the undo block


