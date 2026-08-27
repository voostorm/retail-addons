local _, ns = ...
ns = ns or {}

local Registry = ns.NameplateAdapters
if not Registry then
    return
end

local UNIT_FRAME_KEYS = { "UnitFrame", "unitFrame" }

local function isFrame(frame)
    return Registry.IsFrame(frame)
end

local function hasBetterBlizzPlatesMarker(candidate)
    return type(candidate.BetterBlizzPlates) == "table"
end

local function isBetterBlizzPlatesFrame(frame)
    if not isFrame(frame) then
        return false
    end

    return hasBetterBlizzPlatesMarker(frame)
end

local function getParent(frame)
    return frame:GetParent()
end

local function isShown(frame)
    return frame:IsShown()
end

local function getCastBar(frame)
    if isFrame(frame.castBar) then
        return frame.castBar
    end

    if type(frame.CastBarsContainer) == "table"
        and isFrame(frame.CastBarsContainer.castBar) then
        return frame.CastBarsContainer.castBar
    end

    return nil
end

local function getUnitFrameFromPlate(plate)
    if not isFrame(plate) then
        return nil
    end

    for _, key in ipairs(UNIT_FRAME_KEYS) do
        local candidate = plate[key]
        if isBetterBlizzPlatesFrame(candidate) then
            return candidate
        end
    end

    return nil
end

local function getUnitFrameFromAnchor(parent)
    local candidate = parent

    for _ = 1, 4 do
        if isBetterBlizzPlatesFrame(candidate) then
            return candidate
        end

        if not isFrame(candidate) then
            return nil
        end

        local nextCandidate = Registry.SafeCall(getParent, candidate)
        if nextCandidate == candidate then
            return nil
        end
        candidate = nextCandidate
    end

    return nil
end

local function getVisibleCastBar(unitFrame)
    if not isBetterBlizzPlatesFrame(unitFrame) then
        return nil
    end

    local castBar = Registry.SafeCall(getCastBar, unitFrame)

    if isFrame(castBar) and Registry.SafeBooleanCall(isShown, false, castBar) then
        return castBar
    end

    return nil
end

Registry:RegisterAdapter({
    id = "BetterBlizzPlates",
    priority = 10,
    IsAvailable = function()
        return Registry:IsAddOnLoaded("BetterBlizzPlates")
    end,
    GetTokenFromPlate = function(_, plate)
        if not getUnitFrameFromPlate(plate) then
            return nil
        end

        return Registry.GetDefaultTokenFromPlate(plate)
    end,
    MatchesPlate = function(_, plate)
        return getUnitFrameFromPlate(plate) ~= nil
    end,
    GetAnchorParent = function(_, plate)
        if not getUnitFrameFromPlate(plate) then
            return nil
        end

        return Registry.GetDefaultAnchorParent(plate)
    end,
    GetLayoutAnchor = function(_, parent, context)
        if type(context) ~= "table"
            or context.iconLayout ~= "HORIZONTAL"
            or context.anchorPreset ~= "BELOW"
            or context.point ~= "TOP"
            or context.relativePoint ~= "BOTTOM" then
            return nil
        end

        return getVisibleCastBar(getUnitFrameFromAnchor(parent))
    end,
})
