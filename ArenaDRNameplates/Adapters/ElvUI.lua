local _, ns = ...
ns = ns or {}

local Registry = ns.NameplateAdapters
if not Registry then
    return
end

local asPublicString = Registry.AsPublicString
local isFrame = Registry.IsFrame
local safeCall = Registry.SafeCall
local getDefaultTokenFromPlate = Registry.GetDefaultTokenFromPlate

local function isElvUILoaded()
    if type(_G.ElvUI) == "table" then
        return true
    end

    return Registry:IsAddOnLoaded("ElvUI", "ElvUI_Mainline")
end

local function hasNameplateToken(frame, token)
    if not token or not isFrame(frame) then
        return false
    end

    return frame.unit == token
        or frame.displayedUnit == token
        or frame.namePlateUnitToken == token
end

local function hasFrameNamePrefix(frame, prefix)
    if not isFrame(frame) or type(frame.GetName) ~= "function" then
        return false
    end

    local name = asPublicString(safeCall(frame.GetName, frame))
    return type(name) == "string" and name:match("^" .. prefix) ~= nil
end

local function isElvUINameplate(frame)
    return isFrame(frame)
        and frame.isNamePlate == true
        and isFrame(frame.Health)
        and isFrame(frame.Castbar)
        and isFrame(frame.RaisedElement)
        and (hasFrameNamePrefix(frame, "ElvNP_") or type(frame.frameName) == "string")
end

local function getElvUINameplate(plate, token)
    if not isFrame(plate) then
        return nil
    end

    token = token or getDefaultTokenFromPlate(plate)
    local fallbackFrame

    for _, child in ipairs({ plate:GetChildren() }) do
        if isElvUINameplate(child) then
            if hasNameplateToken(child, token) then
                return child
            end

            if not fallbackFrame and (type(child.IsShown) ~= "function" or child:IsShown()) then
                fallbackFrame = child
            end
        end
    end

    return fallbackFrame
end

Registry:RegisterAdapter({
    id = "ElvUI",
    priority = 90,
    IsAvailable = function()
        return isElvUILoaded()
    end,
    GetTokenFromPlate = function(_, plate)
        return getDefaultTokenFromPlate(plate)
    end,
    MatchesPlate = function(_, plate, token)
        return getElvUINameplate(plate, token) ~= nil
    end,
    GetAnchorParent = function(_, plate, token)
        local nameplate = getElvUINameplate(plate, token)
        if not nameplate then
            return nil
        end

        return nameplate.Health or nameplate
    end,
})
