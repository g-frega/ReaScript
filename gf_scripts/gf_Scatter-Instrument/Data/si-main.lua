-- @noindex
--[[
  Module loader for the Scatter Instrument script.
  Loads all SI modules in dependency order.
--]]

-- Load modules (order matters: each may depend on previous ones)
dofile(DATA_PATH .. 'si-utils.lua')     -- SI table, state, constants, helpers
dofile(DATA_PATH .. 'si-tracks.lua')    -- Voice track creation/management
dofile(DATA_PATH .. 'si-tags.lua')      -- Tag read/write system
dofile(DATA_PATH .. 'si-picker.lua')    -- Take picking (shuffle, random, sequential)
dofile(DATA_PATH .. 'si-engine.lua')    -- Plan generation, apply, cleanup, build
dofile(DATA_PATH .. 'si-monitor.lua')   -- Playback monitor loop
dofile(DATA_PATH .. 'si-gui.lua')       -- ReaImGui interface

-- Seed RNG
math.randomseed(os.time())

-- Resume monitoring if it was running before
if SI.isRunning then
    SI.mainLoop()
end

-- Start the GUI
SI.guiLoop()
