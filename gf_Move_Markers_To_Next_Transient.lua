-- @description Move project markers to the next transient in a selected item
-- @version 1.0.3
-- @author Giacomo Frega
-- @about
--   Moves markers inside the selected item using REAPER's transient detection.

-- Move project markers to next audio transient of selected media item
-- Uses REAPER's built-in transient detection (sensitivity set in Project Settings > Media Item Defaults)

local function main()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then
    reaper.ShowMessageBox("Please select a media item.", "No Selection", 0)
    return
  end

  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  -- Collect project markers that intersect with the selected item (skip regions)
  local markers = {}
  for i = 0, reaper.CountProjectMarkers(0) - 1 do
    local _, isrgn, pos, _, name, idx = reaper.EnumProjectMarkers(i)
    if not isrgn and pos >= item_start and pos <= item_end then
      markers[#markers + 1] = { idx = idx, pos = pos, name = name }
    end
  end

  if #markers == 0 then
    reaper.ShowMessageBox("No project markers found.", "No Markers", 0)
    return
  end

  local saved_cursor = reaper.GetCursorPosition()

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Action 40375: "Item navigation: Move cursor to next transient in items"
  local ACT_NEXT_TRANSIENT = 40375
  local moved = 0

  for _, m in ipairs(markers) do
    reaper.SetEditCurPos(m.pos, false, false)
    reaper.Main_OnCommand(ACT_NEXT_TRANSIENT, 0)
    local transient_pos = reaper.GetCursorPosition()

    -- Move marker only if a transient was found within the item bounds
    if transient_pos ~= m.pos and transient_pos >= item_start and transient_pos <= item_end then
      reaper.SetProjectMarker(m.idx, false, transient_pos, 0, m.name)
      moved = moved + 1
    end
  end

  reaper.SetEditCurPos(saved_cursor, false, false)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Move markers to next transients", -1)

  reaper.ShowConsoleMsg("Moved " .. moved .. " of " .. #markers .. " markers to next transient.\n")
end

main()
