local addonName, ns = ...

local TRACKED_SPELLS = ns.TRACKED_SPELLS or {}
local addon = CreateFrame("Frame")

-- One private frame pool per Blizzard nameplate aura container.
-- Weak keys let old nameplate frames be garbage collected normally.
local customPools = setmetatable({}, { __mode = "k" })
local hooksInstalled = false

local function IsEnemyPlayer(unit)
    return unit
        and UnitExists(unit)
        and UnitIsPlayer(unit)
        and UnitCanAttack("player", unit)
end

local function ResetAuraFrame(pool, auraFrame)
    Pool_HideAndClearAnchors(pool, auraFrame)
    auraFrame.layoutIndex = nil
    auraFrame:SetParent(nil)
end

local function GetCustomPool(aurasFrame)
    local pool = customPools[aurasFrame]
    if pool then
        return pool
    end

    pool = CreateFramePool(
        "FRAME",
        aurasFrame.DebuffListFrame,
        "NameplateAuraItemTemplate",
        ResetAuraFrame
    )

    customPools[aurasFrame] = pool
    return pool
end

local function AddShownAuraIDsFromList(listFrame, shownAuraIDs)
    if not listFrame then
        return
    end

    for _, child in ipairs({ listFrame:GetChildren() }) do
        if child:IsShown() and child.auraInstanceID then
            shownAuraIDs[child.auraInstanceID] = true
        end
    end
end

local function GetBlizzardDebuffLayoutState(aurasFrame)
    local listFrame = aurasFrame.DebuffListFrame
    local shownAuraIDs = {}
    local shownCount = 0
    local highestLayoutIndex = 0

    -- Avoid duplicating anything Blizzard is already showing anywhere in its
    -- nameplate aura UI.
    AddShownAuraIDsFromList(aurasFrame.DebuffListFrame, shownAuraIDs)
    AddShownAuraIDsFromList(aurasFrame.BuffListFrame, shownAuraIDs)
    AddShownAuraIDsFromList(aurasFrame.CrowdControlListFrame, shownAuraIDs)

    local lossOfControlFrame = aurasFrame.LossOfControlFrame
    local lossOfControlAura = lossOfControlFrame and lossOfControlFrame.AuraItemFrame
    if lossOfControlAura and lossOfControlAura:IsShown() and lossOfControlAura.auraInstanceID then
        shownAuraIDs[lossOfControlAura.auraInstanceID] = true
    end

    -- Find where Blizzard's current debuff row ends so our icons continue on
    -- that exact same row.
    for _, child in ipairs({ listFrame:GetChildren() }) do
        if child:IsShown() and child.layoutIndex then
            shownCount = shownCount + 1
            highestLayoutIndex = math.max(highestLayoutIndex, child.layoutIndex)
        end
    end

    return shownAuraIDs, shownCount, highestLayoutIndex
end

local function RefreshTrackedAuras(aurasFrame)
    if not aurasFrame or not aurasFrame.DebuffListFrame then
        return
    end

    local listFrame = aurasFrame.DebuffListFrame
    local pool = GetCustomPool(aurasFrame)

    -- Always clear our previous pass first. Blizzard owns its frames; this pool
    -- owns only the additional icons created by this addon.
    pool:ReleaseAll()

    local unit = aurasFrame.unitToken
    if not IsEnemyPlayer(unit) or not listFrame:IsShown() then
        listFrame:Layout()
        return
    end

    local shownAuraIDs, shownCount, highestLayoutIndex =
        GetBlizzardDebuffLayoutState(aurasFrame)

    local maxDisplayed = listFrame.maxAuraItemsDisplayed or 12
    if shownCount >= maxDisplayed then
        listFrame:Layout()
        return
    end

    -- Unlike Blizzard's normal enemy-player debuff row, do not restrict these
    -- configured auras to the local player's source. This is what lets teammate
    -- snares appear.
    local harmfulAuras = C_UnitAuras.GetUnitAuras(unit, "HARMFUL", nil)
    if not harmfulAuras then
        listFrame:Layout()
        return
    end

    for _, auraData in ipairs(harmfulAuras) do
        local auraInstanceID = auraData.auraInstanceID
        local spellID = auraData.spellId

        if spellID
            and TRACKED_SPELLS[spellID]
            and auraInstanceID
            and not shownAuraIDs[auraInstanceID] then

            if shownCount >= maxDisplayed then
                break
            end

            local auraFrame = pool:Acquire()
            highestLayoutIndex = highestLayoutIndex + 1
            shownCount = shownCount + 1

            auraFrame.layoutIndex = highestLayoutIndex
            auraFrame:SetParent(listFrame)
            auraFrame:SetAura(auraData)
            auraFrame:SetScale(aurasFrame.auraItemScale or 1)
            auraFrame:SetUnit(unit)
            auraFrame:Show()

            shownAuraIDs[auraInstanceID] = true
        end
    end

    -- Because the custom frames use Blizzard's own NameplateAuraItemTemplate
    -- and are children of DebuffListFrame, Blizzard's layout places them
    -- directly after the normal icons on the same row.
    listFrame:Layout()
end

local function RefreshVisibleNameplates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        return
    end

    for _, nameplate in ipairs(C_NamePlate.GetNamePlates()) do
        local unitFrame = nameplate.UnitFrame
        local aurasFrame = unitFrame and unitFrame.AurasFrame
        if aurasFrame then
            RefreshTrackedAuras(aurasFrame)
        end
    end
end

local function InstallHooks()
    if hooksInstalled then
        return true
    end

    if not NamePlateAurasMixin
        or not NamePlateAurasMixin.RefreshAuras
        or not NamePlateAurasMixin.UpdateAuraScale then
        return false
    end

    -- Blizzard already refreshes this mixin whenever UNIT_AURA changes for the
    -- nameplate unit, so a post-hook keeps our additions synchronized without
    -- replacing Blizzard code.
    hooksecurefunc(NamePlateAurasMixin, "RefreshAuras", function(self)
        RefreshTrackedAuras(self)
    end)

    hooksecurefunc(NamePlateAurasMixin, "UpdateAuraScale", function(self)
        RefreshTrackedAuras(self)
    end)

    hooksInstalled = true
    C_Timer.After(0, RefreshVisibleNameplates)
    return true
end

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")

addon:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == "Blizzard_NamePlates" then
        InstallHooks()
    elseif event == "PLAYER_LOGIN" then
        if not InstallHooks() then
            C_Timer.After(0, InstallHooks)
        end
    end
end)
