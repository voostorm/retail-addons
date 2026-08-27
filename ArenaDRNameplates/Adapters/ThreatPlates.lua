local _, ns = ...
ns = ns or {}

local Registry = ns.NameplateAdapters
if not Registry then
    return
end

local isFrame = Registry.IsFrame
local isNameplateToken = Registry.IsNameplateToken
local safeCall = Registry.SafeCall
local getDefaultTokenFromPlate = Registry.GetDefaultTokenFromPlate

local function isThreatPlatesLoaded()
    if type(_G.TidyPlatesThreat) == "table" then
        return true
    end

    return Registry:IsAddOnLoaded("TidyPlates_ThreatPlates")
end

local function isFrameShown(frame)
    return isFrame(frame)
        and (type(frame.IsShown) ~= "function" or frame:IsShown())
end

local function isThreatPlateFrame(frame)
    return isFrame(frame)
        and type(frame.visual) == "table"
        and type(frame.style) == "table"
        and type(frame.unit) == "table"
end

local function getThreatPlateFrame(plate, token)
    if not isFrame(plate) then
        return nil
    end

    local tpFrame = plate.TPFrame
    if not isThreatPlateFrame(tpFrame) or tpFrame.Parent ~= plate then
        return nil
    end

    if tpFrame.Active ~= true then
        return nil
    end

    local unitToken = isNameplateToken(tpFrame.unit and tpFrame.unit.unitid)
    if token and unitToken and unitToken ~= token then
        return nil
    end

    return tpFrame
end

local function getThreatPlateAnchor(tpFrame)
    if not isThreatPlateFrame(tpFrame) then
        return nil
    end

    if type(tpFrame.GetAnchor) == "function" then
        local anchor = safeCall(tpFrame.GetAnchor, tpFrame)
        if isFrame(anchor) then
            return anchor
        end
    end

    local visual = tpFrame.visual
    if type(visual) == "table" then
        for _, candidate in ipairs({
            visual.Healthbar,
            visual.NameText,
        }) do
            if isFrameShown(candidate) then
                return candidate
            end
        end
    end

    return tpFrame
end

Registry:RegisterAdapter({
    id = "ThreatPlates",
    priority = 105,
    IsAvailable = function()
        return isThreatPlatesLoaded()
    end,
    GetTokenFromPlate = function(_, plate)
        local tpFrame = getThreatPlateFrame(plate)
        local token = tpFrame and isNameplateToken(tpFrame.unit and tpFrame.unit.unitid)
        if token then
            return token
        end

        return getDefaultTokenFromPlate(plate)
    end,
    MatchesPlate = function(_, plate, token)
        return getThreatPlateFrame(plate, token) ~= nil
    end,
    GetAnchorParent = function(_, plate, token)
        local tpFrame = getThreatPlateFrame(plate, token)
        if not tpFrame then
            return nil
        end

        return getThreatPlateAnchor(tpFrame)
    end,
})
