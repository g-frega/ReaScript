-- @description Safe script template
-- @version 1.0.0
-- @author Giacomo Frega
-- @about
--   Starter template for REAPER Lua scripts.
--   Includes safe undo and UI refresh handling.

local function validate_context()
  return true
end

local function run()
  -- Implement script behavior here.
end

local function main()
  if not validate_context() then
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local ok, err = pcall(run)

  reaper.PreventUIRefresh(-1)

  if ok then
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Safe script template", -1)
  else
    reaper.Undo_EndBlock("Safe script template (failed)", -1)
    reaper.ShowMessageBox(tostring(err), "Script Error", 0)
  end
end

main()
