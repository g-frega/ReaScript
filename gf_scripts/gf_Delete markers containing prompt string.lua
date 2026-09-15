-- @description Delete markers/regions by name with filter options
-- @version 1.1.0
-- @author gf
-- @about
--   Prompts for a text fragment and options, then finds matching markers/regions
--   by name and optionally deletes them.
--   Supports case sensitivity, include regions, dry-run, and match mode:
--   contains / starts-with / ends-with / exact.

local SCRIPT_TITLE = "Delete markers containing prompt string"

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_yes_no(value, default_value)
  local v = trim((value or ""):lower())
  if v == "" then return default_value end
  if v == "y" or v == "yes" or v == "1" or v == "true" then return true end
  if v == "n" or v == "no" or v == "0" or v == "false" then return false end
  return nil
end

local function parse_match_mode(value)
  local v = trim((value or ""):lower())
  if v == "" or v == "contains" or v == "c" then return "contains" end
  if v == "starts" or v == "start" or v == "startswith" or v == "s" then return "starts" end
  if v == "ends" or v == "end" or v == "endswith" or v == "e" then return "ends" end
  if v == "exact" or v == "x" then return "exact" end
  return nil
end

local function name_matches(marker_name, query, case_sensitive, match_mode)
  local target = marker_name or ""
  local needle = query or ""

  if not case_sensitive then
    target = target:lower()
    needle = needle:lower()
  end

  if match_mode == "contains" then
    return target:find(needle, 1, true) ~= nil
  elseif match_mode == "starts" then
    return target:sub(1, #needle) == needle
  elseif match_mode == "ends" then
    return target:sub(-#needle) == needle
  elseif match_mode == "exact" then
    return target == needle
  end

  return false
end

local function collect_matches(query, case_sensitive, include_regions, match_mode)
  local matches = {}
  local idx = 0

  while true do
    local ok, is_region, pos, _, name, marker_id = reaper.EnumProjectMarkers3(0, idx)
    if ok == 0 then break end

    if (not is_region) or include_regions then
      local marker_name = name or ""
      if name_matches(marker_name, query, case_sensitive, match_mode) then
        matches[#matches + 1] = {
          id = marker_id,
          pos = pos,
          name = marker_name,
          is_region = is_region,
        }
      end
    end

    idx = idx + 1
  end

  return matches
end

local function build_preview(matches)
  local max_lines = 10
  local lines = {}
  local shown = math.min(#matches, max_lines)

  for i = 1, shown do
    local m = matches[i]
    local kind = m.is_region and "REG" or "MRK"
    lines[#lines + 1] = string.format("%d) [%s] %.3fs | %s", i, kind, m.pos, m.name)
  end

  if #matches > max_lines then
    lines[#lines + 1] = string.format("...and %d more", #matches - max_lines)
  end

  return table.concat(lines, "\n")
end

local function validate_context()
  local marker_count, region_count = reaper.CountProjectMarkers(0)
  if (marker_count + region_count) == 0 then
    reaper.ShowMessageBox("Project has no markers/regions.", SCRIPT_TITLE, 0)
    return false
  end

  return true
end

local function run()
  local captions = table.concat({
    "Search text  (e.g. _end)",
    "Match mode  contains | starts | ends | exact",
    "Case sensitive  y = match case, n = ignore case",
    "Include regions  y = markers + regions, n = markers only",
    "Dry run  y = preview only (no delete), n = delete",
    "extrawidth=380",
  }, ",")

  local defaults = table.concat({"", "contains", "n", "n", "n"}, ",")
  local ok, input = reaper.GetUserInputs(SCRIPT_TITLE, 5, captions, defaults)
  if not ok then return end

  local parts = {}
  for part in (input .. ","):gmatch("(.-),") do
    parts[#parts + 1] = part
  end

  local query = trim(parts[1] or "")
  if query == "" then
    reaper.ShowMessageBox("Search text cannot be empty.", SCRIPT_TITLE, 0)
    return
  end

  local match_mode = parse_match_mode(parts[2])
  if not match_mode then
    reaper.ShowMessageBox("Invalid match mode. Use: contains, starts, ends, exact.", SCRIPT_TITLE, 0)
    return
  end

  local case_sensitive = parse_yes_no(parts[3], false)
  if case_sensitive == nil then
    reaper.ShowMessageBox("Invalid value for case sensitive. Use y or n.", SCRIPT_TITLE, 0)
    return
  end

  local include_regions = parse_yes_no(parts[4], false)
  if include_regions == nil then
    reaper.ShowMessageBox("Invalid value for include regions. Use y or n.", SCRIPT_TITLE, 0)
    return
  end

  local dry_run = parse_yes_no(parts[5], false)
  if dry_run == nil then
    reaper.ShowMessageBox("Invalid value for dry run. Use y or n.", SCRIPT_TITLE, 0)
    return
  end

  local matches = collect_matches(query, case_sensitive, include_regions, match_mode)

  if #matches == 0 then
    reaper.ShowMessageBox("No matches for: " .. query, SCRIPT_TITLE, 0)
    return
  end

  local kind_scope = include_regions and "markers + regions" or "markers only"
  local cs_text = case_sensitive and "yes" or "no"
  local dry_text = dry_run and "yes" or "no"

  local confirm_msg = string.format(
    "Query: %s\nMode: %s\nCase sensitive: %s\nScope: %s\nDry run: %s\n\nMatched: %d\n\n%s\n\n%s",
    query,
    match_mode,
    cs_text,
    kind_scope,
    dry_text,
    #matches,
    build_preview(matches),
    dry_run and "Dry run active: nothing will be deleted." or "Delete these matches?"
  )

  local confirm = reaper.ShowMessageBox(confirm_msg, SCRIPT_TITLE, 4)
  if confirm ~= 6 then return end

  if dry_run then
    return
  end

  local deleted = 0
  for i = #matches, 1, -1 do
    if reaper.DeleteProjectMarker(0, matches[i].id, matches[i].is_region) then
      deleted = deleted + 1
    end
  end

  reaper.ShowMessageBox(string.format("Deleted %d match(es).", deleted), SCRIPT_TITLE, 0)
end

local function main()
  if not validate_context() then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local ok, err = pcall(run)

  reaper.PreventUIRefresh(-1)

  if ok then
    reaper.UpdateArrange()
    reaper.Undo_EndBlock(SCRIPT_TITLE, -1)
  else
    reaper.Undo_EndBlock(SCRIPT_TITLE .. " (failed)", -1)
    reaper.ShowMessageBox(tostring(err), "Script Error", 0)
  end
end

main()
