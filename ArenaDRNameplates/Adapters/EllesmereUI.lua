local _, ns = ...
ns = ns or {}

local Registry = ns.NameplateAdapters
if not Registry then
    return
end

local isFrame = Registry.IsFrame
local isNameplateToken = Registry.IsNameplateToken
local getDefaultTokenFromPlate = Registry.GetDefaultTokenFromPlate

local function isEllesmereUILoaded()
    if type(_G.EllesmereNameplates_NS) == "table" then
        return true
    end

    return Registry:IsAddOnLoaded("EllesmereUINameplates")
end

local function getEllesmereRuntime()
    local runtime = _G.EllesmereNameplates_NS
    if type(runtime) ~= "table" or type(runtime.plates) ~= "table" then
        return nil
    end

    return runtime
end

local function isEllesmerePlate(frame, plate, token)
    return isFrame(frame)
        and isFrame(frame.health)
        and frame.nameplate == plate
        and (not token or frame.unit == token)
end

local function getEllesmerePlate(plate, token)
    if not isFrame(plate) then
        return nil
    end

    local runtime = getEllesmereRuntime()
    if not runtime then
        return nil
    end

    token = token or getDefaultTokenFromPlate(plate)
    if token then
        local frame = runtime.plates[token]
        if isEllesmerePlate(frame, plate, token) then
            return frame
        end
    end

    -- EllesmereUI keeps its custom plate table keyed by unit token. Scan it as
    -- a fallback while Blizzard is still assigning UnitFrame.unit on a freshly
    -- displayed nameplate.
    for unit, frame in pairs(runtime.plates) do
        local runtimeToken = isNameplateToken(unit)
        if runtimeToken and isEllesmerePlate(frame, plate, runtimeToken) then
            return frame, runtimeToken
        end
    end

    return nil
end

Registry:RegisterAdapter({
    id = "EllesmereUI",
    priority = 120,
    IsAvailable = function()
        return isEllesmereUILoaded()
    end,
    GetTokenFromPlate = function(_, plate)
        local token = getDefaultTokenFromPlate(plate)
        if token then
            return token
        end

        local _, ellesmereToken = getEllesmerePlate(plate)
        return ellesmereToken
    end,
    MatchesPlate = function(_, plate, token)
        return getEllesmerePlate(plate, token) ~= nil
    end,
    GetAnchorParent = function(_, plate, token)
        local ellesmerePlate = getEllesmerePlate(plate, token)
        if not ellesmerePlate then
            return nil
        end

        return ellesmerePlate.health
    end,
})
