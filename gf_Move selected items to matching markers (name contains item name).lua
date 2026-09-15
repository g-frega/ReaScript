-- @description Move selected items to matching markers (name contains item name)
-- @version 1.0.3
-- @author gf
-- @about
--   For each selected item, finds project markers whose name contains the item name
--   (case-insensitive, plain-text match). If multiple markers match, uses nearest by time.
--   Moves each item start position to the matched marker position.

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function get_item_name(item)
  local take = reaper.GetActiveTake(item)
  if not take then return "" end
  local name = reaper.GetTakeName(take) or ""
  return trim(name)
end

local function collect_markers()
  local markers = {}
  local idx = 0

  while true do
    local ok, is_region, pos, _, name, markrgnindexnumber = reaper.EnumProjectMarkers3(0, idx)
    if ok == 0 then break end

    if not is_region then
      markers[#markers + 1] = {
        pos = pos,
        name = name or "",
        lower = (name or ""):lower(),
        id = markrgnindexnumber,
      }
    end

    idx = idx + 1
  end

  return markers
end

local function find_best_marker_for_item(item_name, item_pos, markers)
  local query = item_name:lower()
  local best = nil
  local best_dist = nil

  for _, marker in ipairs(markers) do
    if marker.lower:find(query, 1, true) then
      local dist = math.abs(marker.pos - item_pos)
      if not best_dist or dist < best_dist then
        best = marker
        best_dist = dist
      elseif dist == best_dist and marker.pos < best.pos then
        best = marker
      end
    end
  end

  return best
end

local function validate_context()
  local item_count = reaper.CountSelectedMediaItems(0)
  if item_count == 0 then
    reaper.ShowMessageBox("Select at least one media item.", "Move items to matching markers", 0)
    return false
  end

  local marker_count, region_count = reaper.CountProjectMarkers(0)
  if (marker_count + region_count) == 0 then
    reaper.ShowMessageBox("Project has no markers/regions.", "Move items to matching markers", 0)
    return false
  end

  return true
end

local function run()
  local markers = collect_markers()
  if #markers == 0 then
    reaper.ShowMessageBox("Project has no markers.", "Move items to matching markers", 0)
    return
  end

  local selected_count = reaper.CountSelectedMediaItems(0)
  local moved = 0
  local skipped_empty_name = 0
  local unmatched = 0

  for i = 0, selected_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local item_name = get_item_name(item)

    if item_name == "" then
      skipped_empty_name = skipped_empty_name + 1
    else
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local marker = find_best_marker_for_item(item_name, item_pos, markers)

      if marker then
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", marker.pos)
        moved = moved + 1
      else
        unmatched = unmatched + 1
      end
    end
  end

  local msg = string.format(
    "Moved: %d\nUnmatched: %d\nSkipped (empty item name): %d",
    moved,
    unmatched,
    skipped_empty_name
  )
  reaper.ShowMessageBox(msg, "Move items to matching markers", 0)
end

local function main()
  if not validate_context() then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local ok, err = pcall(run)

  reaper.PreventUIRefresh(-1)

  if ok then
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Move selected items to matching markers", -1)
  else
    reaper.Undo_EndBlock("Move selected items to matching markers (failed)", -1)
    reaper.ShowMessageBox(tostring(err), "Script Error", 0)
  end
end

main()
