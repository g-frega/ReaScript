-- @noindex
-- Scatter Instrument: Playback monitor and start/stop control

function SI.mainLoop()
    if not SI.isRunning then return end

    local playState = r.GetPlayState()
    local playPos = r.GetPlayPosition()

    -- On playback start: scatter all containers
    if playState == 1 and SI.lastPlayState ~= 1 then
        r.PreventUIRefresh(1)
        r.Undo_BeginBlock()
        SI.scatterAllContainers()
        r.Undo_EndBlock("Scatter Instrument: Generate", -1)
        r.PreventUIRefresh(-1)
        r.UpdateArrange()
    end

    -- On loop detection: regenerate
    if playState == 1 and playPos < SI.lastPlayPos - 0.1 then
        r.PreventUIRefresh(1)
        r.Undo_BeginBlock()
        SI.scatterAllContainers()
        r.Undo_EndBlock("Scatter Instrument: Regenerate (loop)", -1)
        r.PreventUIRefresh(-1)
        r.UpdateArrange()
    end

    -- On playback stop: cleanup if configured
    if playState == 0 and SI.lastPlayState == 1 then
        r.PreventUIRefresh(1)
        r.Undo_BeginBlock()
        SI.cleanupAllScattered(true)
        r.Undo_EndBlock("Scatter Instrument: Cleanup", -1)
        r.PreventUIRefresh(-1)
        r.UpdateArrange()
    end

    SI.lastPlayPos = playPos
    SI.lastPlayState = playState

    SI.updateAllVoiceTrackVisibility()

    r.defer(SI.mainLoop)
end

function SI.startMonitoring()
    SI.isRunning = true
    SI.mainLoop()
end

function SI.stopMonitoring()
    SI.isRunning = false
end

function SI.toggleMonitoring()
    if SI.isRunning then
        SI.stopMonitoring()
    else
        SI.startMonitoring()
    end
end
