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

local function isPlaterLoaded()
    if type(_G.Plater) == "table" then
        return true
    end

    return Registry:IsAddOnLoaded("Plater")
end

local function isFrameShown(frame)
    return isFrame(frame)
        and (type(frame.IsShown) ~= "function" or frame:IsShown())
end

local function isPlaterUnitFrame(frame)
    return isFrame(frame)
        and frame.Plater == true
        and isFrame(frame.healthBar)
        and isFrame(frame.castBar)
        and type(frame.PlateFrame) == "table"
end

local function getPlaterUnitFrame(plate)
    if not isFrame(plate) then
        return nil
    end

    for _, candidate in ipairs({
        plate.unitFrame,
        plate.unitFramePlater,
    }) do
        if isPlaterUnitFrame(candidate) and candidate.PlateFrame == plate then
            return candidate
        end
    end

    return nil
end

local function getPlaterTokenFromFrame(unitFrame)
    if not isPlaterUnitFrame(unitFrame) then
        return nil
    end

    return isNameplateToken(unitFrame.unit)
        or isNameplateToken(unitFrame.displayedUnit)
end

local function isPlaterPlateVisible(plate, token)
    local unitFrame = getPlaterUnitFrame(plate)
    if not unitFrame then
        return false
    end

    local frameToken = getPlaterTokenFromFrame(unitFrame)
    if token and frameToken and frameToken ~= token then
        return false
    end

    if unitFrame.PlaterOnScreen ~= nil then
        return unitFrame.PlaterOnScreen == true
    end

    return isFrameShown(unitFrame)
end

local function getPlaterHealthBar(unitFrame)
    if not isPlaterUnitFrame(unitFrame) then
        return nil
    end

    local plater = _G.Plater
    if type(plater) == "table" and type(plater.GetHealthBar) == "function" then
        local healthBar = safeCall(plater.GetHealthBar, unitFrame)
        if isFrame(healthBar) then
            return healthBar
        end
    end

    if isFrame(unitFrame.healthBar) then
        return unitFrame.healthBar
    end

    return nil
end

local function getPlaterNameAnchor(plate, unitFrame)
    if isFrame(plate.CurrentUnitNameString)
        and (type(plate.CurrentUnitNameString.IsShown) ~= "function" or plate.CurrentUnitNameString:IsShown()) then
        return plate.CurrentUnitNameString
    end

    if isFrame(plate.ActorNameSpecial)
        and (type(plate.ActorNameSpecial.IsShown) ~= "function" or plate.ActorNameSpecial:IsShown()) then
        return plate.ActorNameSpecial
    end

    if isFrame(unitFrame.healthBar)
        and isFrame(unitFrame.healthBar.unitName)
        and (type(unitFrame.healthBar.unitName.IsShown) ~= "function" or unitFrame.healthBar.unitName:IsShown()) then
        return unitFrame.healthBar.unitName
    end

    return nil
end

Registry:RegisterAdapter({
    id = "Plater",
    priority = 110,
    IsAvailable = function()
        return isPlaterLoaded()
    end,
    GetTokenFromPlate = function(_, plate)
        local unitFrame = getPlaterUnitFrame(plate)
        local token = getPlaterTokenFromFrame(unitFrame)
        if token then
            return token
        end

        return getDefaultTokenFromPlate(plate)
    end,
    MatchesPlate = function(_, plate, token)
        return isPlaterPlateVisible(plate, token)
    end,
    GetAnchorParent = function(_, plate)
        local unitFrame = getPlaterUnitFrame(plate)
        if not unitFrame then
            return nil
        end

        local healthBar = getPlaterHealthBar(unitFrame)
        if isFrameShown(healthBar) then
            return healthBar
        end

        local nameAnchor = getPlaterNameAnchor(plate, unitFrame)
        if isFrame(nameAnchor) then
            return nameAnchor
        end

        return healthBar or unitFrame
    end,
})
