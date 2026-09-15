-- @noindex
-- Scatter Instrument: ReaImGui GUI

---------------------------------------------------------
--                  ReaImGui Setup                     --
---------------------------------------------------------

local ok, ImGui = pcall(function()
    package.path = r.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
    return require('imgui')('0.9.2')
end)

if not ok or not ImGui then
    r.ShowMessageBox(
        "Could not load ReaImGui. Please install/update 'reaper_imgui' via ReaPack.",
        "Scatter Instrument - Error", 0)
    return
end

local ctx = ImGui.CreateContext("gf_Scatter Instrument")

---------------------------------------------------------
--                 GUI State                           --
---------------------------------------------------------

local guiState = {
    selectedItem = nil,
    isContainer = false,
    params = {},
    minInterval = SI.DEFAULTS.minInterval,
    maxInterval = SI.DEFAULTS.maxInterval,
    spawnRate = SI.DEFAULTS.spawnRate,
    volRnd = SI.DEFAULTS.volRnd,
    pitchRnd = SI.DEFAULTS.pitchRnd,
    pitchMode = 0,      -- 0=rate, 1=pitch
    playMode = 0,       -- 0=scatter, 1=single
    polyphony = SI.DEFAULTS.polyphony,
    stealing = 0,       -- 0=oldest, 1=none
    playlistMode = 0,   -- 0=shuffle, 1=random, 2=sequential
    runInBackground = SI.runInBackground,
    realtimePlayback = true,
    cleanupOnStop = true,
    hideVoiceTracks = false,
    readabilityComp = tonumber(r.GetExtState(SI.scriptID, "ReadabilityComp")) or 0.3,
}

local stealingModes = {"oldest", "none"}
local playlistModes = {"shuffle", "random", "sequential"}
local playModes = {"scatter", "single"}

-- Readability compensation is now controlled via the in-GUI slider (guiState.readabilityComp).

local function isValidItem(item)
    return item and r.ValidatePtr2(0, item, "MediaItem*")
end

local function getFirstSelectedScatterItem()
    local selCount = r.CountSelectedMediaItems(0)
    for i = 0, selCount - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item then
            local notes = SI.getItemNotes(item)
            if SI.isScatterContainer(notes) then
                return item
            end
        end
    end
    return nil
end

local function getItemDisplayInfo(item)
    if not isValidItem(item) then
        return "None", "None"
    end

    local trackName = "(unnamed track)"
    local track = r.GetMediaItem_Track(item)
    if track then
        local trackNum = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
        local _, tn = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if tn and tn ~= "" then
            if trackNum > 0 then
                trackName = tostring(trackNum) .. " - " .. tn
            else
                trackName = tn
            end
        elseif trackNum > 0 then
            trackName = "Track " .. tostring(trackNum)
        end
    end

    local itemName = "(unnamed item)"
    local take = r.GetActiveTake(item)
    if take then
        local _, takeName = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        if takeName and takeName ~= "" then
            itemName = takeName
        end
    end

    return trackName, itemName
end

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function rgbaToU32(rf, gf, bf, af)
    local r8 = math.floor(clamp01(rf) * 255 + 0.5)
    local g8 = math.floor(clamp01(gf) * 255 + 0.5)
    local b8 = math.floor(clamp01(bf) * 255 + 0.5)
    local a8 = math.floor(clamp01(af) * 255 + 0.5)
    return (r8 << 24) | (g8 << 16) | (b8 << 8) | a8
end

local function mix3(r, g, b, tr, tg, tb, t)
    return r + (tr - r) * t, g + (tg - g) * t, b + (tb - b) * t
end

local function toLinear(v)
    if v <= 0.04045 then return v / 12.92 end
    return ((v + 0.055) / 1.055) ^ 2.4
end

local function relLuminance(r, g, b)
    local rl, gl, bl = toLinear(r), toLinear(g), toLinear(b)
    return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
end

local function contrastRatio(r1, g1, b1, r2, g2, b2)
    local l1 = relLuminance(r1, g1, b1)
    local l2 = relLuminance(r2, g2, b2)
    if l1 < l2 then l1, l2 = l2, l1 end
    return (l1 + 0.05) / (l2 + 0.05)
end

local function pushTrackTheme(item)
    if not isValidItem(item) then return 0 end

    local track = r.GetMediaItem_Track(item)
    if not track then return 0 end

    local nativeColor = r.GetTrackColor(track)
    if not nativeColor or nativeColor == 0 then return 0 end

    local r8, g8, b8 = r.ColorFromNative(nativeColor)
    local baseR, baseG, baseB = r8 / 255.0, g8 / 255.0, b8 / 255.0

    -- Lift overall brightness by 10% while preserving hue.
    local brightnessBoost = 0.10
    baseR, baseG, baseB = mix3(baseR, baseG, baseB, 1, 1, 1, brightnessBoost)

    local lum = 0.2126 * baseR + 0.7152 * baseG + 0.0722 * baseB

    -- Boost tonal distance by 15% so UI elements separate more clearly.
    local contrastBoost = 1.15
    -- sep: how much the slider amplifies gaps BETWEEN element levels.
    -- Window base stays fixed; frames go darker, hover/active go lighter from it.
    local sep = clamp01(guiState.readabilityComp)

    -- Window and title: fixed, slider does not darken these.
    local windowR, windowG, windowB = mix3(baseR, baseG, baseB, 0, 0, 0, 0.28 * contrastBoost)
    local titleR, titleG, titleB = mix3(baseR, baseG, baseB, 0, 0, 0, 0.24 * contrastBoost)
    local titleActiveR, titleActiveG, titleActiveB = mix3(baseR, baseG, baseB, 1, 1, 1, 0.16 * contrastBoost)

    -- Buttons/headers: base panel level, slider pushes hover/active further light.
    local panelR, panelG, panelB = mix3(baseR, baseG, baseB, 0, 0, 0, 0.18 * contrastBoost)
    local panelHoverR, panelHoverG, panelHoverB = mix3(baseR, baseG, baseB, 1, 1, 1, clamp01(0.14 * contrastBoost + 0.28 * sep))
    local panelActiveR, panelActiveG, panelActiveB = mix3(baseR, baseG, baseB, 1, 1, 1, clamp01(0.26 * contrastBoost + 0.32 * sep))

    local buttonR, buttonG, buttonB = mix3(panelR, panelG, panelB, 0, 0, 0, 0.08)
    local buttonHoverR, buttonHoverG, buttonHoverB = panelHoverR, panelHoverG, panelHoverB
    local buttonActiveR, buttonActiveG, buttonActiveB = mix3(panelActiveR, panelActiveG, panelActiveB, 1, 1, 1, 0.08)

    local headerR, headerG, headerB = mix3(panelR, panelG, panelB, 1, 1, 1, 0.06)
    local headerHoverR, headerHoverG, headerHoverB = mix3(panelHoverR, panelHoverG, panelHoverB, 1, 1, 1, 0.06)
    local headerActiveR, headerActiveG, headerActiveB = mix3(panelActiveR, panelActiveG, panelActiveB, 1, 1, 1, 0.06)

    -- Frames (checkboxes/sliders): slider pushes these further dark from the window,
    -- increasing the gap rather than shifting the whole palette.
    local frameBase = 0.54
    local frameR, frameG, frameB = mix3(baseR, baseG, baseB, 0, 0, 0, clamp01(frameBase + 0.26 * sep))
    local frameHoverR, frameHoverG, frameHoverB = mix3(baseR, baseG, baseB, 0, 0, 0, clamp01(0.40 + 0.22 * sep))
    local frameActiveR, frameActiveG, frameActiveB = mix3(baseR, baseG, baseB, 0, 0, 0, clamp01(0.28 + 0.18 * sep))

    local whiteContrast = contrastRatio(1, 1, 1, windowR, windowG, windowB)
    local blackContrast = contrastRatio(0, 0, 0, windowR, windowG, windowB)
    local useWhite = whiteContrast >= blackContrast
    -- At sep=0: soft text (0.88). At sep=1: full contrast text (1.0 or 0.0).
    local textBright = 0.88 + 0.12 * sep
    local textDark = 0.12 - 0.12 * sep
    local textVal = useWhite and textBright or textDark
    local textR, textG, textB = textVal, textVal, textVal

    local accentR, accentG, accentB = baseR, baseG, baseB

    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, rgbaToU32(windowR, windowG, windowB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, rgbaToU32(titleR, titleG, titleB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, rgbaToU32(titleActiveR, titleActiveG, titleActiveB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_Separator, rgbaToU32(accentR, accentG, accentB, 1.0))

    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, rgbaToU32(frameR, frameG, frameB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, rgbaToU32(frameHoverR, frameHoverG, frameHoverB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, rgbaToU32(frameActiveR, frameActiveG, frameActiveB, 1.0))

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, rgbaToU32(buttonR, buttonG, buttonB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, rgbaToU32(buttonHoverR, buttonHoverG, buttonHoverB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, rgbaToU32(buttonActiveR, buttonActiveG, buttonActiveB, 1.0))

    ImGui.PushStyleColor(ctx, ImGui.Col_Header, rgbaToU32(headerR, headerG, headerB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, rgbaToU32(headerHoverR, headerHoverG, headerHoverB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, rgbaToU32(headerActiveR, headerActiveG, headerActiveB, 1.0))

    ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark, rgbaToU32(accentR, accentG, accentB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, rgbaToU32(accentR, accentG, accentB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, rgbaToU32(accentR, accentG, accentB, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, rgbaToU32(textR, textG, textB, 1.0))

    return 17
end

---------------------------------------------------------
--          Refresh / Write Helpers                    --
---------------------------------------------------------

local function refreshFromSelection(item)
    item = item or r.GetSelectedMediaItem(0, 0)
    if not item then
        guiState.selectedItem = nil
        guiState.isContainer = false
        return
    end

    guiState.selectedItem = item
    local notes = SI.getItemNotes(item)
    guiState.isContainer = SI.isScatterContainer(notes)

    if guiState.isContainer then
        local p = SI.readParams(notes)
        guiState.minInterval = p.minInterval
        guiState.maxInterval = p.maxInterval
        guiState.spawnRate = p.spawnRate
        guiState.volRnd = p.volRnd
        guiState.pitchRnd = p.pitchRnd
        guiState.pitchMode = (p.pitchMode == "pitch") and 1 or 0
        guiState.playMode = 0
        for i, m in ipairs(playModes) do
            if p.playMode == m then guiState.playMode = i - 1; break end
        end
        guiState.polyphony = p.polyphony
        guiState.realtimePlayback = (p.realtimePlayback == 1)
        guiState.cleanupOnStop = (p.cleanupOnStop == 1)
        guiState.hideVoiceTracks = (p.hideVoiceTracks == 1)

        guiState.stealing = 0
        for i, m in ipairs(stealingModes) do
            if p.stealing == m then guiState.stealing = i - 1; break end
        end
        guiState.playlistMode = 0
        for i, m in ipairs(playlistModes) do
            if p.playlistMode == m then guiState.playlistMode = i - 1; break end
        end
    end
end

local function writeToItem()
    local item = guiState.selectedItem
    if not isValidItem(item) then return end

    local notes = SI.getItemNotes(item)
    if not SI.isScatterContainer(notes) then return end

    local params = {
        minInterval = guiState.minInterval,
        maxInterval = guiState.maxInterval,
        spawnRate = guiState.spawnRate,
        volRnd = guiState.volRnd,
        pitchRnd = guiState.pitchRnd,
        pitchMode = (guiState.pitchMode == 1) and "pitch" or "rate",
        playMode = playModes[guiState.playMode + 1],
        polyphony = guiState.polyphony,
        stealing = stealingModes[guiState.stealing + 1],
        playlistMode = playlistModes[guiState.playlistMode + 1],
        realtimePlayback = guiState.realtimePlayback and 1 or 0,
        cleanupOnStop = guiState.cleanupOnStop and 1 or 0,
        hideVoiceTracks = guiState.hideVoiceTracks and 1 or 0,
    }

    notes = SI.writeAllParams(notes, params)
    notes = SI.stripContainerNoteImage(notes)
    SI.setItemNotes(item, notes)
end

---------------------------------------------------------
--                  GUI Render Loop                    --
---------------------------------------------------------

local lastSelectedItem = nil
local windowFlags = ImGui.WindowFlags_NoCollapse

local function renderGUI()
    local curScatterItem = getFirstSelectedScatterItem()
    local targetItem = curScatterItem

    -- While no scatter container has been chosen yet, still allow selecting
    -- a regular item to access container creation/tagging actions.
    if not targetItem and not guiState.selectedItem then
        targetItem = r.GetSelectedMediaItem(0, 0)
    end

    if targetItem and targetItem ~= lastSelectedItem then
        lastSelectedItem = targetItem
        guiState.selectedItem = targetItem
        refreshFromSelection(targetItem)
    elseif not targetItem and guiState.selectedItem and not isValidItem(guiState.selectedItem) then
        guiState.selectedItem = nil
        guiState.isContainer = false
        lastSelectedItem = nil
    end

    local pushedThemeColors = pushTrackTheme(guiState.selectedItem)

    local visible, open = ImGui.Begin(ctx, "Scatter Instrument###ScatterInstrument", true, windowFlags)
    if not visible then
        if not open then
            if pushedThemeColors > 0 then
                ImGui.PopStyleColor(ctx, pushedThemeColors)
            end
            return false
        end
        ImGui.End(ctx)
        if pushedThemeColors > 0 then
            ImGui.PopStyleColor(ctx, pushedThemeColors)
        end
        return true
    end

    local compChanged
    compChanged, guiState.readabilityComp = ImGui.SliderDouble(ctx, "Readability##comp", guiState.readabilityComp, 0.0, 1.0, "%.2f")
    if compChanged then
        r.SetExtState(SI.scriptID, "ReadabilityComp", tostring(guiState.readabilityComp), true)
    end
    ImGui.Separator(ctx)

    local selectedTrackName, selectedItemName = getItemDisplayInfo(guiState.selectedItem)
    ImGui.Text(ctx, "Selected Track: " .. selectedTrackName)
    ImGui.Text(ctx, "Selected Item: " .. selectedItemName)
    ImGui.Separator(ctx)

    -- Realtime Playback + Cleanup on Stop (top row)
    local runChanged, runVal = ImGui.Checkbox(ctx, "Realtime Playback", guiState.realtimePlayback)
    if runChanged then
        guiState.realtimePlayback = runVal
        writeToItem()
        SI.setContainerImage(guiState.selectedItem, playModes[guiState.playMode + 1])
        if runVal then SI.startMonitoring() else SI.stopMonitoring() end
    end

    ImGui.SameLine(ctx)

    local changed
    changed, guiState.cleanupOnStop = ImGui.Checkbox(ctx, "Cleanup on Stop", guiState.cleanupOnStop)
    if changed then
        writeToItem()
    end

    ImGui.SameLine(ctx)

    changed, guiState.runInBackground = ImGui.Checkbox(ctx, "Run in Background", guiState.runInBackground)
    if changed then
        SI.runInBackground = guiState.runInBackground
        r.SetExtState(SI.scriptID, "RunInBackground", SI.runInBackground and "1" or "0", true)
    end

    -- Offline controls
    if ImGui.Button(ctx, "Generate Offline") then
        guiState.realtimePlayback = false
        writeToItem()
        SI.setContainerImage(guiState.selectedItem, playModes[guiState.playMode + 1])
        if SI.isRunning then SI.stopMonitoring() end
        local containerItem = guiState.selectedItem
        r.PreventUIRefresh(1)
        r.Undo_BeginBlock()
        SI.cleanupScatteredItems(containerItem)
        local params = SI.readParams(SI.getItemNotes(containerItem))
        local plan = SI.generateScatterPlan(containerItem, params)
        SI.applyScatterToTrack(containerItem, plan)
        SI.updateAllVoiceTrackVisibility()
        -- Keep the scatter container focused after offline generation.
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(containerItem, true)
        r.Undo_EndBlock("Scatter Instrument: Regenerate", -1)
        r.PreventUIRefresh(-1)
        r.UpdateArrange()
    end

    ImGui.SameLine(ctx)

    if ImGui.Button(ctx, "Cleanup") then
        if SI.isRunning then SI.stopMonitoring() end
        r.PreventUIRefresh(1)
        r.Undo_BeginBlock()
        SI.cleanupScatteredItems(guiState.selectedItem)
        r.Undo_EndBlock("Scatter Instrument: Cleanup", -1)
        r.PreventUIRefresh(-1)
        r.UpdateArrange()
    end

    if guiState.selectedItem and guiState.isContainer then
        ImGui.Spacing(ctx)

        changed, guiState.hideVoiceTracks = ImGui.Checkbox(ctx, "Hide Voice Tracks", guiState.hideVoiceTracks)
        if changed then writeToItem() end

        ImGui.SameLine(ctx)

        if ImGui.Button(ctx, "Revert to Original Items") then
            r.PreventUIRefresh(1)
            r.Undo_BeginBlock()
            local reverted = SI.revertScatterContainer(guiState.selectedItem)
            r.Undo_EndBlock("Scatter Instrument: Revert Container", -1)
            r.PreventUIRefresh(-1)
            r.UpdateArrange()
            if not reverted then
                r.ShowMessageBox("Could not revert the selected Scatter Container.", "Scatter Instrument", 0)
            else
                refreshFromSelection()
            end
        end
    end

    ImGui.Separator(ctx)

    if not guiState.selectedItem then
        ImGui.Text(ctx, "No item selected.")
    elseif not guiState.isContainer then
        ImGui.Text(ctx, "Selected takes are not a Scatter Container.")
        ImGui.Spacing(ctx)
        if ImGui.Button(ctx, "Tag Selected Takes as Scatter Container") then
            if r.CountTakes(guiState.selectedItem) < 2 then
                r.ShowMessageBox("Select an item that contains at least 2 takes.", "Scatter Instrument", 0)
            else
                SI.tagItemAsScatterContainer(guiState.selectedItem)
                r.SetMediaItemInfo_Value(guiState.selectedItem, "B_MUTE", 1)
                refreshFromSelection()
                r.UpdateArrange()
            end
        end
        ImGui.Spacing(ctx)
        if ImGui.Button(ctx, "Build Container from Selected Items") then
            local built = SI.buildScatterContainerFromSelection()
            if built then refreshFromSelection() end
        end
    else
        local takeCount = r.CountTakes(guiState.selectedItem)
        ImGui.Text(ctx, "Scatter Container (" .. takeCount .. " takes)")
        ImGui.Separator(ctx)

        changed, guiState.playMode = ImGui.Combo(ctx, "Mode", guiState.playMode, "scatter\0single\0")
        if changed then
            writeToItem()
            SI.setContainerImage(guiState.selectedItem, playModes[guiState.playMode + 1])
        end

        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        ImGui.Text(ctx, "Playlist")

        changed, guiState.playlistMode = ImGui.Combo(ctx, "Selection Mode", guiState.playlistMode, "shuffle\0random\0sequential\0")
        if changed then writeToItem() end

        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)

        -- Spawn Interval
        local changed
        if guiState.playMode == 0 then
            ImGui.Text(ctx, "Spawn Interval (ms)")

            changed, guiState.minInterval = ImGui.SliderInt(ctx, "Min##interval", guiState.minInterval, 1, 1000)
            if changed then
                if guiState.minInterval > guiState.maxInterval then
                    guiState.maxInterval = guiState.minInterval
                end
                writeToItem()
            end

            changed, guiState.maxInterval = ImGui.SliderInt(ctx, "Max##interval", guiState.maxInterval, 1, 5000)
            if changed then
                if guiState.maxInterval < guiState.minInterval then
                    guiState.minInterval = guiState.maxInterval
                end
                writeToItem()
            end

            ImGui.Spacing(ctx)

            changed, guiState.spawnRate = ImGui.SliderInt(ctx, "Spawn Rate (%)", guiState.spawnRate, 1, 300)
            if changed then writeToItem() end

            ImGui.Spacing(ctx)
            ImGui.Separator(ctx)
        end

        ImGui.Text(ctx, "Randomization")

        changed, guiState.volRnd = ImGui.SliderDouble(ctx, "Vol Rnd (dB)", guiState.volRnd, -24.0, 0.0, "%.1f")
        if changed then writeToItem() end

        changed, guiState.pitchRnd = ImGui.SliderDouble(ctx, "Pitch Rnd (±st)", guiState.pitchRnd, 0.0, 12.0, "%.1f")
        if changed then writeToItem() end

        changed, guiState.pitchMode = ImGui.Combo(ctx, "Pitch Mode", guiState.pitchMode, "Playback Rate\0Item Pitch\0")
        if changed then writeToItem() end

        if guiState.playMode == 0 then
            ImGui.Spacing(ctx)
            ImGui.Separator(ctx)
            ImGui.Text(ctx, "Polyphony")

            changed, guiState.polyphony = ImGui.SliderInt(ctx, "Max Voices", guiState.polyphony, 1, 16)
            if changed then writeToItem() end

            changed, guiState.stealing = ImGui.Combo(ctx, "Stealing", guiState.stealing, "oldest\0none\0")
            if changed then writeToItem() end
        end

    end

    ImGui.End(ctx)
    if pushedThemeColors > 0 then
        ImGui.PopStyleColor(ctx, pushedThemeColors)
    end
    return open
end

---------------------------------------------------------
--                 GUI Loop & Entry                    --
---------------------------------------------------------

function SI.guiLoop()
    local continueRunning = renderGUI()
    if continueRunning then
        r.defer(SI.guiLoop)
    else
        if not SI.runInBackground then
            SI.stopMonitoring()
        end
    end
end
