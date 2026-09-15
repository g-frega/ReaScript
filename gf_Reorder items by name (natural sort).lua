-- @description Reorder items by name (natural sort)
-- @version 1.0.3
-- @author gf
-- @about
--   Reorders selected items in-place by active take name using natural sort.
--   Alphabetical order, but embedded numbers compare numerically
--   (e.g. "Commission-52" before "Commission-165").
--   Items keep their lengths; only start positions are reassigned.

-- Natural sort: split name into text/number chunks, compare chunk by chunk
local function natural_sort_key(name)
  local key = {}
  for text, num in name:gmatch("(%D*)(%d*)") do
    if text ~= "" then
      key[#key + 1] = text:lower()
    end
    if num ~= "" then
      key[#key + 1] = tonumber(num)
    end
  end
  return key
end

local function compare_natural(a, b)
  local ka, kb = natural_sort_key(a), natural_sort_key(b)
  for i = 1, math.max(#ka, #kb) do
    local va, vb = ka[i], kb[i]
    if va == nil then return true end
    if vb == nil then return false end
    local ta, tb = type(va), type(vb)
    if ta ~= tb then
      -- strings before numbers
      return ta == "string"
    end
    if va ~= vb then
      return va < vb
    end
  end
  return false
end

local function validate_context()
  local count = reaper.CountSelectedMediaItems(0)
  if count < 2 then
    reaper.ShowMessageBox("Select at least 2 items to reorder.", "Reorder items", 0)
    return false
  end
  -- Ensure all selected items are on the same track
  local track = reaper.GetMediaItemTrack(reaper.GetSelectedMediaItem(0, 0))
  for i = 1, count - 1 do
    if reaper.GetMediaItemTrack(reaper.GetSelectedMediaItem(0, i)) ~= track then
      reaper.ShowMessageBox("All selected items must be on the same track.", "Reorder items", 0)
      return false
    end
  end
  return true
end

local function run()
  local count = reaper.CountSelectedMediaItems(0)

  -- Collect items with names and current positions
  local items = {}
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    local name = ""
    if take then
      name = reaper.GetTakeName(take) or ""
    end
    items[#items + 1] = {
      item = item,
      name = name,
      pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
      len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
    }
  end

  -- Sort items by name (natural)
  table.sort(items, function(a, b) return compare_natural(a.name, b.name) end)

  -- Place sorted items end-to-end starting at earliest original position
  local pos = items[1].pos
  for _, v in ipairs(items) do
    -- use earliest original position as starting point
    if v.pos < pos then pos = v.pos end
  end
  for _, v in ipairs(items) do
    reaper.SetMediaItemInfo_Value(v.item, "D_POSITION", pos)
    pos = pos + v.len
  end
end

local function main()
  if not validate_context() then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local ok, err = pcall(run)

  reaper.PreventUIRefresh(-1)

  if ok then
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Reorder items by name (natural sort)", -1)
  else
    reaper.Undo_EndBlock("Reorder items by name (failed)", -1)
    reaper.ShowMessageBox(tostring(err), "Script Error", 0)
  end
end

main()
