-- @description Scatter Instrument for REAPER (FMOD-style Scatterer)
-- @author gf
-- @version 1.0.2
-- @about
--   Replicates FMOD's Scatterer Instrument in REAPER.
--   Tags a multi-take item as a scatter container. During playback, spawns
--   scattered child items on track lanes at randomized intervals with
--   per-spawn volume/pitch randomization for true polyphony.
-- @provides
--   [nomain] Data/*.lua
-- @changelog
--   - Initial release
SCRIPT_FOLDER = 'gf_Scatter-Instrument'
r = reaper
SEP = package.config:sub(1, 1)
DATA_PATH = debug.getinfo(1, 'S').source:match '@(.+[/\\])' .. 'Data' .. SEP
dofile(DATA_PATH .. 'si-main.lua')
