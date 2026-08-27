local _, ns = ...
ns = ns or {}

local Registry = ns.NameplateAdapters
if not Registry then
    return
end

local isFrame = Registry.IsFrame
local safeBooleanCall = Registry.SafeBooleanCall
local getDefaultTokenFromPlate = Registry.GetDefaultTokenFromPlate

-- Aura containers Platynator hangs off each display. The adapter never anchors
-- to them, they are only used as a fingerprint, so a rename must not be fatal.
local AURA_DISPLAY_KEYS = { "BuffDisplay", "DebuffDisplay", "CrowdControlDisplay" }

-- Keys a display may use to record the unit it is currently bound to.
local DISPLAY_UNIT_KEYS = { "unit", "interactUnit", "displayedUnit" }

local function isPlatynatorLoaded()
    if _G.Platynator then
        return true
    end

    return Registry:IsAddOnLoaded("Platynator")
end

local function isShown(frame)
    return frame:IsShown()
end

local function hasAuraDisplay(frame)
    for _, key in ipairs(AURA_DISPLAY_KEYS) do
        if isFrame(frame[key]) then
            return true
        end
    end

    return false
end

local function hasWidgetList(frame)
    -- Platynator drives each display from a numeric list of widget frames that
    -- carry a `details` descriptor table.
    if type(frame.widgets) ~= "table" then
        return false
    end

    for _, widget in ipairs(frame.widgets) do
        if isFrame(widget) and type(widget.details) == "table" then
            return true
        end
    end

    return false
end

-- Accept on either signal rather than requiring both. Demanding the full field
-- set means one renamed member drops us to the Blizzard adapter, which matches
-- unconditionally and anchors to a hidden unit frame, so the breakage is
-- silent instead of loud.
local function isPlatynatorDisplay(frame)
    if not isFrame(frame) or type(frame.SetUnit) ~= "function" then
        return false
    end

    return hasAuraDisplay(frame) or hasWidgetList(frame)
end

local function displayMatchesToken(display, token)
    for _, key in ipairs(DISPLAY_UNIT_KEYS) do
        if display[key] == token then
            return true
        end
    end

    return false
end

local function getPlatynatorDisplay(plate, token)
    if not isFrame(plate) then
        return nil
    end

    token = token or getDefaultTokenFromPlate(plate)
    local fallbackDisplay

    for _, child in ipairs({ plate:GetChildren() }) do
        if isPlatynatorDisplay(child) then
            if token and displayMatchesToken(child, token) then
                return child
            end

            if not fallbackDisplay and safeBooleanCall(isShown, true, child) then
                fallbackDisplay = child
            end
        end
    end

    return fallbackDisplay
end

local function getWidgetKind(widget)
    local details = widget.details
    if type(details) == "table" and details.kind ~= nil then
        return details.kind
    end

    return widget.kind
end

local function getPlatynatorPrimaryWidget(display)
    if not isPlatynatorDisplay(display) or type(display.widgets) ~= "table" then
        return nil
    end

    local firstBar
    for _, widget in ipairs(display.widgets) do
        if isFrame(widget) then
            local kind = getWidgetKind(widget)
            if kind == "health" then
                return widget
            end

            if not firstBar and kind == "bars" then
                firstBar = widget
            end
        end
    end

    return firstBar
end

Registry:RegisterAdapter({
    id = "Platynator",
    priority = 100,
    IsAvailable = function()
        return isPlatynatorLoaded()
    end,
    GetTokenFromPlate = function(_, plate)
        return getDefaultTokenFromPlate(plate)
    end,
    MatchesPlate = function(_, plate, token)
        return getPlatynatorDisplay(plate, token) ~= nil
    end,
    GetAnchorParent = function(_, plate, token)
        local display = getPlatynatorDisplay(plate, token)
        if not display then
            return nil
        end

        return getPlatynatorPrimaryWidget(display) or display
    end,
})
