-- @noindex
-- Scatter Instrument: Take picking (shuffle bag, random, sequential)

function SI.pickTakeShuffle(containerGUID, takeCount)
    if takeCount <= 1 then return 0 end

    local bag = SI.shuffleBags[containerGUID]
    local needsRefill = (not bag) or (bag.takeCount ~= takeCount) or (#bag.values == 0)

    if needsRefill then
        local lastPick = bag and bag.lastPick or nil
        local values = {}
        for i = 0, takeCount - 1 do
            values[#values + 1] = i
        end

        -- Fisher-Yates shuffle
        for i = #values, 2, -1 do
            local j = math.random(i)
            values[i], values[j] = values[j], values[i]
        end

        -- Avoid repeating last pick at bag boundary
        if takeCount > 1 and lastPick ~= nil and values[#values] == lastPick then
            local swapIdx = math.random(1, #values - 1)
            values[#values], values[swapIdx] = values[swapIdx], values[#values]
        end

        bag = {
            values = values,
            takeCount = takeCount,
            lastPick = lastPick,
        }
        SI.shuffleBags[containerGUID] = bag
    end

    local pick = table.remove(bag.values)
    bag.lastPick = pick
    return pick
end

function SI.pickTakeRandom(takeCount)
    if takeCount <= 1 then return 0 end
    return math.random(0, takeCount - 1)
end

function SI.pickTakeSequential(containerGUID, takeCount)
    if takeCount <= 1 then return 0 end
    local idx = (SI.sequentialIndices[containerGUID] or -1) + 1
    if idx >= takeCount then idx = 0 end
    SI.sequentialIndices[containerGUID] = idx
    return idx
end

function SI.pickTake(containerGUID, takeCount, mode)
    if mode == "shuffle" then
        return SI.pickTakeShuffle(containerGUID, takeCount)
    elseif mode == "sequential" then
        return SI.pickTakeSequential(containerGUID, takeCount)
    else
        return SI.pickTakeRandom(takeCount)
    end
end
