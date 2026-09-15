-- @noindex
-- Scatter Instrument: Tag system for item notes (read/write parameters)

function SI.isScatterContainer(notes)
    return notes:find(SI.TAG_HEADER, 1, true) ~= nil
end

function SI.readTag(notes, tagName, default)
    local pattern = SI.TAG_PREFIX .. tagName .. "%(([^)]+)%)"
    local match = notes:match(pattern)
    if match then
        local num = tonumber(match)
        if num then return num end
        return match
    end
    return default
end

function SI.writeTag(notes, tagName, value)
    local tagStr = SI.TAG_PREFIX .. tagName .. "(" .. tostring(value) .. ")"
    local pattern = SI.TAG_PREFIX .. tagName .. "%([^)]*%)"
    if notes:match(pattern) then
        notes = notes:gsub(pattern, SI.TAG_PREFIX .. tagName .. "(" .. tostring(value) .. ")")
    else
        notes = notes .. "\n" .. tagStr
    end
    return notes
end

function SI.readParams(notes)
    local params = {}
    for key, default in pairs(SI.DEFAULTS) do
        params[key] = SI.readTag(notes, key, default)
    end
    return params
end

function SI.writeAllParams(notes, params)
    for key, val in pairs(params) do
        notes = SI.writeTag(notes, key, val)
    end
    return notes
end

function SI.stripContainerNoteImage(notes)
    notes = notes or ""
    notes = notes:gsub("!%[SI_BG%]%([^\n]*%)\n?", "")
    notes = notes:gsub("^\n+", "")
    return notes
end

function SI.tagItemAsScatterContainer(item)
    if not item then return end

    -- Ensure container is easy to identify regardless of which take is active.
    local takeCount = r.CountTakes(item)
    for i = 0, takeCount - 1 do
        local take = r.GetTake(item, i)
        if take then
            local _, takeName = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            takeName = takeName or ""
            if takeName == "" then
                takeName = "Container"
            end
            if takeName:sub(1, 8) ~= "SCATTER-" then
                if takeName:sub(1, 8) == "Scatter-" then
                    takeName = takeName:sub(9)
                end
                r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "SCATTER-" .. takeName, true)
            end
        end
    end

    -- Highlight scatter containers with a fixed custom item color.
    local color = r.ColorToNative(255, 170, 40) | 0x1000000
    r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)

    local notes = SI.getItemNotes(item)
    if not SI.isScatterContainer(notes) then
        notes = SI.TAG_HEADER .. "\n" .. notes
    end
    local params = SI.readParams(notes)
    notes = SI.writeAllParams(notes, params)
    notes = SI.stripContainerNoteImage(notes)
    SI.setItemNotes(item, notes)
    SI.setContainerImage(item, params.playMode)
end
