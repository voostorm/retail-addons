local _, ns = ...
ns = ns or {}

local Shared = ns.Shared
local S = Shared.S
local Performance = ns.Performance

local SelfDR = ns.SelfDR or {}
ns.SelfDR = SelfDR

local issecretvalue_fn = _G.issecretvalue

-- Midnight protects some values during combat; touching them raises an error.
local function IsSecretValue(value)
    if type(issecretvalue_fn) ~= "function" then
        return false
    end

    local ok, result = pcall(issecretvalue_fn, value)
    return ok and result == true
end

local DR_RESET_DURATION = Shared.DR_RESET_DURATION
local CATEGORIES = Shared.selfDRCategories
local MAX_LOC_SLOTS = 10
-- Midnight 12.1 PvP diminishing returns are two-tier: the first crowd control
-- lands full, the second at half duration, and the third is immune. There is no
-- quarter-duration tier, which matches Blizzard's own enemy tray glyphs.
local MAX_DR_STAGE = 2
local BASE_ICON_SIZE = Shared.iconBaseSizes.selfDR

-- Blizzard's Loss of Control lock types map onto DR categories with one
-- counter-intuitive pair: the generic "STUN" lock is the incapacitate DR,
-- while "STUN_MECHANIC" is the real stun DR.
local locTypeToDRCategory = {
    STUN = "incapacitate",
    STUN_MECHANIC = "stun",
    FEAR = "disorient",
    FEAR_MECHANIC = "disorient",
    CHARM = "disorient",
    CYCLONE = "disorient",
    POSSESS = "disorient",
    CONFUSE = "incapacitate",
    ROOT = "root",
    DISARM = "disarm",
    SILENCE = "silence",
}

-- Spells whose Loss of Control type does not match the DR category they share.
local spellIDToDRCategory = {
    [31661] = "disorient", -- Dragon's Breath reports CONFUSE
    [2094] = "disorient", -- Blind reports CONFUSE
    [105421] = "disorient", -- Blinding Light reports CONFUSE
    [207167] = "disorient", -- Blinding Sleet reports CONFUSE
    [33786] = "disorient", -- Cyclone reports STUN
    [198909] = "disorient", -- Song of Chi-Ji reports STUN
    [51514] = "incapacitate", -- Hex reports NONE
    [277784] = "incapacitate", -- Hex (Wicker Mongrel)
    [196942] = "incapacitate", -- Hex (Voodoo Totem)
    [210873] = "incapacitate", -- Hex (Raptor)
    [211004] = "incapacitate", -- Hex (Spider)
    [211010] = "incapacitate", -- Hex (Snake)
    [211015] = "incapacitate", -- Hex (Cockroach)
    [269352] = "incapacitate", -- Hex (Skeletal Hatchling)
    [309328] = "incapacitate", -- Hex (Living Honey)
    [277778] = "incapacitate", -- Hex (Zandalari Tendonripper)
}

-- Effects that surface in Loss of Control but carry no diminishing return.
local nonDRSpellIDs = {
    [87204] = true, -- Sin and Punishment
    [196364] = true, -- Unstable Affliction silence
    [6789] = true, -- Mortal Coil
    [100] = true, -- Charge
    [105771] = true, -- Charge root
    [78675] = true, -- Solar Beam
    [81261] = true, -- Solar Beam silence
    [358861] = true, -- Cascading Horrors
    [157997] = true, -- Ice Nova
    [370970] = true, -- The Hunt root
    [45334] = true, -- Bear Charge
}

local categoryIcons = {
    stun = "Interface\\Icons\\Ability_Rogue_KidneyShot",
    incapacitate = "Interface\\Icons\\Spell_Nature_Polymorph",
    disorient = "Interface\\Icons\\Spell_Shadow_Possession",
    root = "Interface\\Icons\\Spell_Nature_StrangleVines",
    silence = "Interface\\Icons\\Spell_Shadow_SoulLeech_3",
    disarm = "Interface\\Icons\\Ability_Warrior_Disarm",
}

local categoryLocaleKeys = {
    stun = "UI_SELFDR_CATEGORY_STUN",
    incapacitate = "UI_SELFDR_CATEGORY_INCAPACITATE",
    disorient = "UI_SELFDR_CATEGORY_DISORIENT",
    root = "UI_SELFDR_CATEGORY_ROOT",
    silence = "UI_SELFDR_CATEGORY_SILENCE",
    disarm = "UI_SELFDR_CATEGORY_DISARM",
}

SelfDR.categoryIcons = categoryIcons
SelfDR.categoryLocaleKeys = categoryLocaleKeys

-- Stage text mirrors the enemy nameplate tray vocabulary (Core.lua): a half
-- glyph after the first application, then the immune marker.
local stageText = { "\194\189", "%" }

local container
local iconsByCategory = {}
local stateByCategory = {}
local testMode = false
local eventsRegistered = false
local previewTicker
local previewStart = 0

local function EnsureDB()
    return Shared.EnsureDB()
end

local function GetSettings()
    return EnsureDB().selfDR
end

local function IsFeatureEnabled()
    local settings = GetSettings()
    return settings and settings.enabled == true
end

local function GetTrackedCategories(result)
    wipe(result)
    local track = GetSettings()
    track = track and track.track
    if not track then
        return result
    end

    for _, category in ipairs(CATEGORIES) do
        if track[category] == true then
            result[#result + 1] = category
        end
    end
    return result
end

--- Zone gating -------------------------------------------------------------

local function IsActiveInCurrentZone()
    local settings = GetSettings()
    if not settings then
        return false
    end

    local instanceType = select(2, IsInInstance())
    if instanceType == "arena" then
        return settings.showInArena == true
    end
    if instanceType == "pvp" then
        return settings.showInBattleground == true
    end

    return settings.showInWorld == true
end

--- Loss of Control reading -------------------------------------------------

-- The second return value separates "no crowd control here" from "this read
-- failed". A failed read must never be mistaken for a control that ended, or the
-- reset window starts while the player is still locked down.
local function GetLossOfControlData(index)
    if not C_LossOfControl or not C_LossOfControl.GetActiveLossOfControlDataByUnit then
        return nil, false
    end

    local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlDataByUnit, "player", index)
    if not ok then
        return nil, false
    end
    return data, true
end

-- Falls back to the full slot scan whenever the count is unavailable, so a
-- missing API only costs a few extra reads.
local function GetLossOfControlCount()
    if not C_LossOfControl then
        return MAX_LOC_SLOTS
    end

    local reader = C_LossOfControl.GetActiveLossOfControlDataCountByUnit
    local ok, count
    if reader then
        ok, count = pcall(reader, "player")
    elseif C_LossOfControl.GetActiveLossOfControlDataCount then
        ok, count = pcall(C_LossOfControl.GetActiveLossOfControlDataCount)
    end

    if not ok or IsSecretValue(count) or type(count) ~= "number" then
        return MAX_LOC_SLOTS
    end

    return math.min(count, MAX_LOC_SLOTS)
end

local function GetCategoryForLossOfControl(data)
    if not data then
        return nil
    end

    local lockType = data.lockType or data.locType
    if not lockType then
        return nil
    end

    local spellID = data.spellID
    if spellID and nonDRSpellIDs[spellID] then
        return nil
    end

    if spellID and spellIDToDRCategory[spellID] then
        return spellIDToDRCategory[spellID]
    end

    return locTypeToDRCategory[lockType]
end

--- State -------------------------------------------------------------------

local function GetState(category)
    local state = stateByCategory[category]
    if not state then
        state = {
            isActive = false,
            auraIDs = nil,
            lastStartTime = nil,
            stage = 0,
            expiresAt = nil,
            startedAt = 0,
        }
        stateByCategory[category] = state
    end
    return state
end

local function ResetState(category)
    local state = GetState(category)
    state.isActive = false
    state.auraIDs = nil
    state.lastStartTime = nil
    state.stage = 0
    state.expiresAt = nil
    state.startedAt = 0
end

-- Read-only view of a category state, used by the test harness and useful
-- for debugging what the tracker currently believes.
function SelfDR.GetCategoryState(category)
    return stateByCategory[category]
end

function SelfDR.ResetAllStates()
    for _, category in ipairs(CATEGORIES) do
        ResetState(category)
    end
end

--- Frames -----------------------------------------------------------------

local function GetPositionAnchor(settings)
    return Shared.ResolveMovableAnchorFrame(settings and settings.relativeFrame)
end

local function GetEffectiveScale(frame, fallback)
    if frame and type(frame.GetEffectiveScale) == "function" then
        local scale = frame:GetEffectiveScale()
        if type(scale) == "number" and scale > 0 then
            return scale
        end
    end
    return fallback or 1
end

local function GetGrowthDirection(settings)
    return Shared.GetEffectiveIconGrowthForValues(
        "ADVANCED",
        settings.iconLayout,
        settings.iconGrowth,
        settings.iconVerticalGrowth
    )
end

-- The drag handler and the layout have to anchor the tray the same way: from
-- the edge the icons grow away from, measured on a single-icon tray.
local function AnchorContainer(settings, anchorFrame, growth)
    local point, offsetX, offsetY = Shared.ResolveGrowthAnchor(
        settings.point,
        settings.iconLayout,
        growth or GetGrowthDirection(settings),
        settings.size,
        settings.offsetX,
        settings.offsetY
    )

    container:ClearAllPoints()
    container:SetPoint(
        point,
        anchorFrame or GetPositionAnchor(settings),
        settings.relativePoint,
        offsetX,
        offsetY
    )
end

local function SavePosition()
    if not container then
        return
    end

    local settings = GetSettings()
    local anchorFrame = GetPositionAnchor(settings)
    local uiScale = GetEffectiveScale(UIParent, 1)
    if not uiScale or uiScale <= 0 then
        return
    end

    local scale = GetEffectiveScale(container, uiScale) / uiScale
    local anchorScale = GetEffectiveScale(anchorFrame, uiScale) / uiScale
    local centerX, centerY = container:GetCenter()
    local parentX, parentY = anchorFrame:GetCenter()
    if not centerX or not centerY or not parentX or not parentY then
        return
    end

    -- The layout anchors from the growth edge, not from the center, so without
    -- folding that in the bar would jump by half its length on the next pass.
    local growth = GetGrowthDirection(settings)
    local saveX, saveY = Shared.GetGrowthAnchorSaveOffset(
        settings.iconLayout,
        growth,
        settings.size,
        container:GetWidth(),
        container:GetHeight()
    )

    settings.point = "CENTER"
    settings.relativePoint = "CENTER"
    settings.offsetX = ((centerX * scale) - (parentX * anchorScale)) + (saveX * scale)
    settings.offsetY = ((centerY * scale) - (parentY * anchorScale)) + (saveY * scale)

    -- StartMoving() re-anchors the frame to UIParent on its own, so re-apply
    -- the saved point explicitly to keep the anchor deterministic.
    AnchorContainer(settings, anchorFrame, growth)

    if _G.ArenaDRNameplates_RefreshSettingsUI then
        _G.ArenaDRNameplates_RefreshSettingsUI()
    end
end

local function EnsureContainer()
    if container then
        return container
    end

    container = CreateFrame("Frame", Shared.NextFrameName("SelfDR", "Container"), UIParent)
    container:SetFrameStrata("HIGH")
    container:SetFrameLevel(200)
    container:SetSize(BASE_ICON_SIZE, BASE_ICON_SIZE)
    container:SetClampedToScreen(false)
    container:SetMovable(true)
    container:EnableMouse(false)
    if container.SetIgnoreParentAlpha then
        container:SetIgnoreParentAlpha(true)
    end

    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self)
        -- Checked here as well as through EnableMouse so a stale mouse state
        -- can never let a locked bar be dragged.
        local settings = GetSettings()
        if not settings or settings.locked == true then
            return
        end

        if self:IsMovable() then
            self.isDragging = true
            self:StartMoving()
        end
    end)
    container:SetScript("OnDragStop", function(self)
        self.isDragging = nil
        self:StopMovingOrSizing()
        SavePosition()
    end)

    container.DragHint, container.Label = Shared.CreateMovableTrayPlaceholder(
        container,
        S("UI_SELFDR_PAGE_NAME")
    )

    container:Hide()
    return container
end

local function EnsureBorderRegions(icon)
    if icon.BorderRegions then
        return icon.BorderRegions
    end

    local regions = {}
    for index = 1, 4 do
        local texture = icon.Overlay:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(1, 1, 1, 1)
        texture:SetDrawLayer("OVERLAY", 6)
        regions[index] = texture
    end

    icon.BorderRegions = regions
    return regions
end

local function UpdateBorder(icon, size, style, width, r, g, b)
    local regions = EnsureBorderRegions(icon)
    local visualScale = math.max(0.5, (tonumber(size) or BASE_ICON_SIZE) / BASE_ICON_SIZE)

    if style == "NONE" then
        for _, texture in ipairs(regions) do
            texture:Hide()
        end
        if icon.ClassicBorder then
            icon.ClassicBorder:Hide()
        end
        return
    end

    if style == "CLASSIC" then
        if not icon.ClassicBorder then
            local classic = icon.Overlay:CreateTexture(nil, "OVERLAY")
            classic:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
            classic:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
            classic:SetDrawLayer("OVERLAY", 6)
            icon.ClassicBorder = classic
        end
        for _, texture in ipairs(regions) do
            texture:Hide()
        end
        icon.ClassicBorder:ClearAllPoints()
        icon.ClassicBorder:SetPoint(
            "TOPLEFT",
            icon,
            "TOPLEFT",
            -visualScale,
            visualScale
        )
        icon.ClassicBorder:SetPoint(
            "BOTTOMRIGHT",
            icon,
            "BOTTOMRIGHT",
            visualScale,
            -visualScale
        )
        icon.ClassicBorder:SetVertexColor(r, g, b, 1)
        icon.ClassicBorder:Show()
        return
    end

    if icon.ClassicBorder then
        icon.ClassicBorder:Hide()
    end

    local top, bottom, left, right = regions[1], regions[2], regions[3], regions[4]

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
    top:SetHeight(width)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(width)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, -width)
    left:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, width)
    left:SetWidth(width)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, -width)
    right:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, width)
    right:SetWidth(width)

    for _, texture in ipairs(regions) do
        texture:SetColorTexture(r, g, b, 1)
        texture:Show()
    end
end

local function OnCooldownDone(cooldown)
    local icon = cooldown:GetParent()
    local category = icon and icon.category
    if not category or testMode then
        return
    end

    local state = GetState(category)
    if state.isActive then
        return
    end

    ResetState(category)
    -- Several windows can finish in the same frame; the tray settles once.
    SelfDR.RequestRefresh()
end

local function EnsureIcon(category)
    local icon = iconsByCategory[category]
    if icon then
        return icon
    end

    local parent = EnsureContainer()
    icon = CreateFrame("Frame", Shared.NextFrameName("SelfDR", "Icon", category), parent)
    icon:SetSize(BASE_ICON_SIZE, BASE_ICON_SIZE)
    icon:SetFrameLevel(parent:GetFrameLevel() + 1)
    icon.category = category

    local texture = icon:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetTexture(categoryIcons[category])
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.Texture = texture

    local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.7)
    cooldown:SetReverse(false)
    cooldown:HookScript("OnCooldownDone", OnCooldownDone)
    icon.Cooldown = cooldown

    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(icon:GetFrameLevel() + 10)
    icon.Overlay = overlay

    local stage = overlay:CreateFontString(nil, "OVERLAY")
    Shared.ApplyTextFont(stage, 14, Shared.GetTextOutlineFlags())
    stage:SetShadowOffset(1, -1)
    stage:SetShadowColor(0, 0, 0, 1)
    stage:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    icon.StageText = stage

    icon:Hide()
    iconsByCategory[category] = icon
    return icon
end

--- Rendering --------------------------------------------------------------

local function FindCooldownText(cooldown)
    if cooldown.ArenaDRNameplatesTimerText then
        return cooldown.ArenaDRNameplatesTimerText
    end

    local fontString
    if type(cooldown.GetCountdownFontString) == "function" then
        local ok, result = pcall(cooldown.GetCountdownFontString, cooldown)
        if ok and result then
            fontString = result
        end
    end

    if not fontString and cooldown.Text then
        fontString = cooldown.Text
    end

    if not fontString then
        for _, region in ipairs({ cooldown:GetRegions() }) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                fontString = region
                break
            end
        end
    end

    cooldown.ArenaDRNameplatesTimerText = fontString
    return fontString
end

local visibleBuffer = {}
local trackedBuffer = {}

-- Timer styling comes from the Timers tab unless the personal override is on,
-- and the DR stage text follows the same arrangement with the DR Text tab. Both
-- tables use the same key names, so the caller reads whichever is chosen.
--
-- Everything derived from them is normalized once per settings revision. The
-- tray restyles every visible icon on each refresh, and rebuilding the same
-- colour tables per icon was the bulk of that work.
local styleSnapshot

local function GetStyleSnapshot()
    local revision = Shared.GetDBRevision()
    if styleSnapshot and styleSnapshot.revision == revision then
        return styleSnapshot
    end

    local db = EnsureDB()
    local settings = db.selfDR
    local selfTimers = settings and settings.timers
    local timerStyle = (selfTimers and selfTimers.override == true) and selfTimers or db
    local selfDRText = settings and settings.drText
    local drTextStyle = (selfDRText and selfDRText.override == true) and selfDRText or db

    local anchor = drTextStyle.drTextAnchor
    if type(anchor) ~= "string" or not Shared.validDRTextAnchors[anchor] then
        anchor = Shared.defaults.drTextAnchor
    end

    local selfDefaults = Shared.defaults.selfDR
    styleSnapshot = {
        revision = revision,
        timerStyle = timerStyle,
        drTextStyle = drTextStyle,
        borderColor = Shared.NormalizeColorTable(
            settings and settings.borderColor,
            selfDefaults.borderColor
        ),
        borderImmuneColor = Shared.NormalizeColorTable(
            settings and settings.borderImmuneColor,
            selfDefaults.borderImmuneColor
        ),
        timerTextColor = Shared.NormalizeColorTable(
            timerStyle.timerTextColor,
            Shared.defaults.timerTextColor
        ),
        timerTextScale = Shared.ClampNumber(timerStyle.timerTextScale, 0.5, 2.0, 1.0),
        timerTextOffsetX = tonumber(timerStyle.timerTextOffsetX) or 0,
        timerTextOffsetY = tonumber(timerStyle.timerTextOffsetY) or 0,
        drTextAnchor = anchor,
        drTextColor = Shared.NormalizeColorTable(
            drTextStyle.drTextColor,
            Shared.defaults.drTextColor
        ),
        drTextImmuneColor = Shared.NormalizeColorTable(
            drTextStyle.drTextImmuneColor,
            Shared.defaults.drTextImmuneColor
        ),
        drTextScale = Shared.ClampNumber(drTextStyle.drTextScale, 0.5, 3.0, 1.0),
        drTextOffsetX = tonumber(drTextStyle.drTextOffsetX) or 4,
        drTextOffsetY = tonumber(drTextStyle.drTextOffsetY) or -4,
        textOutlineFlags = Shared.GetTextOutlineFlags(db.textOutline),
    }
    return styleSnapshot
end

local function GetTimerStyle()
    return GetStyleSnapshot().timerStyle
end

local function GetDRTextStyle()
    return GetStyleSnapshot().drTextStyle
end

-- Mirrors ApplyCooldownStyle in Core.lua so both trays behave identically.
local function ApplyCooldownStyle(cooldown, style)
    if not cooldown then
        return
    end

    local showSwipe = style.showTimerSwipe ~= false
    local showSwipeEdge = showSwipe and style.showTimerSwipeEdge == true

    if cooldown.SetDrawSwipe then
        cooldown:SetDrawSwipe(showSwipe)
    end
    if cooldown.SetSwipeColor then
        cooldown:SetSwipeColor(0, 0, 0, showSwipe and 0.7 or 0)
    end
    if cooldown.SetDrawEdge then
        cooldown:SetDrawEdge(showSwipeEdge)
    end
    if cooldown.SetDrawBling then
        cooldown:SetDrawBling(false)
    end
    if cooldown.SetCountdownMillisecondsThreshold then
        local threshold = 0
        if style.showTimerDecimals ~= false then
            threshold = math.floor(
                Shared.ClampNumber(style.timerDecimalThreshold, 1, 20, 5) + 0.5
            )
        end
        cooldown:SetCountdownMillisecondsThreshold(threshold)
    end
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(style.showTimerText == false)
    end
end

local function StyleIcon(icon, settings, isImmune, visualScale)
    local style = GetStyleSnapshot()

    -- Styling depends on the settings revision and the immune stage, and on
    -- nothing else about the DR state. Icon size is applied directly to each
    -- child, so an icon already dressed for that pair needs none of the
    -- widget calls below. This is what turns a refresh per aura event into a
    -- no-op instead of a full restyle.
    if icon.ArenaDRNameplatesStyleRevision == style.revision
        and icon.ArenaDRNameplatesStyleImmune == isImmune
        and icon.ArenaDRNameplatesVisualScale == visualScale then
        return
    end
    icon.ArenaDRNameplatesStyleRevision = style.revision
    icon.ArenaDRNameplatesStyleImmune = isImmune

    local iconSize = BASE_ICON_SIZE * visualScale
    icon:SetSize(iconSize, iconSize)
    icon.ArenaDRNameplatesVisualScale = visualScale
    icon:SetAlpha(settings.opacity)

    local color = isImmune and style.borderImmuneColor or style.borderColor
    UpdateBorder(
        icon,
        iconSize,
        settings.borderStyle,
        settings.borderWidth * visualScale,
        color[1],
        color[2],
        color[3]
    )

    ApplyCooldownStyle(icon.Cooldown, style.timerStyle)

    local timerText = FindCooldownText(icon.Cooldown)
    if timerText then
        local timerColor = style.timerTextColor
        local fontSize = math.max(
            6,
            math.floor(14 * style.timerTextScale * visualScale + 0.5)
        )

        timerText:SetTextColor(timerColor[1], timerColor[2], timerColor[3], 1)
        timerText:ClearAllPoints()
        timerText:SetPoint(
            "CENTER",
            icon,
            "CENTER",
            style.timerTextOffsetX * visualScale,
            style.timerTextOffsetY * visualScale
        )
        if timerText.SetJustifyH then
            timerText:SetJustifyH("CENTER")
        end
        if timerText.SetJustifyV then
            timerText:SetJustifyV("MIDDLE")
        end
        Shared.ApplyTextFont(timerText, fontSize, style.textOutlineFlags)
    end

    -- DR stage text, mirroring ApplyDRTextStyle in Core.lua.
    local stage = icon.StageText
    local stageColor = isImmune and style.drTextImmuneColor or style.drTextColor

    Shared.ApplyTextFont(
        stage,
        math.max(6, math.floor(13 * visualScale + 0.5)),
        style.textOutlineFlags
    )
    stage:SetScale(style.drTextScale)
    stage:ClearAllPoints()
    stage:SetPoint(
        style.drTextAnchor,
        icon,
        style.drTextAnchor,
        style.drTextOffsetX * visualScale,
        style.drTextOffsetY * visualScale
    )
    stage:SetTextColor(stageColor[1], stageColor[2], stageColor[3], 1)
end

-- Hoisted out of Refresh: table.sort takes the comparator by value, and
-- building a fresh closure on every refresh allocated for nothing.
local function CompareIconsByStart(a, b)
    local stateA, stateB = GetState(a.category), GetState(b.category)
    if stateA.startedAt == stateB.startedAt then
        return a.category < b.category
    end
    return stateA.startedAt < stateB.startedAt
end

function SelfDR.Refresh()
    local settings = GetSettings()
    if not settings then
        return
    end

    if not settings.enabled then
        if container then
            container:Hide()
        end
        return
    end

    if not testMode and not IsActiveInCurrentZone() then
        if container then
            container:Hide()
        end
        return
    end

    local metricStartedAt = Performance and Performance.active and Performance:Begin()

    EnsureContainer()

    local visualScale = settings.size / BASE_ICON_SIZE
    local iconSize = BASE_ICON_SIZE * visualScale
    local padding = settings.iconPadding * visualScale
    -- Keep the positioned parent unscaled so changing icon size cannot also
    -- transform its saved anchor offsets.
    container:SetScale(1)
    container.ArenaDRNameplatesVisualScale = visualScale

    local now = GetTime()
    local layout = settings.iconLayout
    local growth = GetGrowthDirection(settings)

    GetTrackedCategories(trackedBuffer)
    wipe(visibleBuffer)

    local showDRText = GetDRTextStyle().showDRText ~= false

    for _, category in ipairs(trackedBuffer) do
        local state = GetState(category)
        local inDRWindow = state.expiresAt and state.expiresAt > now
        if state.isActive or inDRWindow then
            local icon = EnsureIcon(category)
            local isImmune = state.stage >= MAX_DR_STAGE
            StyleIcon(icon, settings, isImmune, visualScale)

            local text = ""
            if showDRText and state.stage > 0 then
                text = stageText[math.min(state.stage, MAX_DR_STAGE)] or ""
            end
            icon.StageText:SetText(text)

            visibleBuffer[#visibleBuffer + 1] = icon
        end
    end

    local track = settings.track
    for category, icon in pairs(iconsByCategory) do
        local state = stateByCategory[category]
        local visible = state and (state.isActive or (state.expiresAt and state.expiresAt > now))
        if not visible or not (track and track[category] == true) then
            icon:Hide()
        end
    end

    -- Unlocking turns the tray into a grab handle. The preview deliberately
    -- does not override this, so the lock behaves the same way in both modes.
    local isUnlocked = settings.locked ~= true
    container:EnableMouse(isUnlocked)
    if container.DragHint then
        container.DragHint:SetShown(isUnlocked)
    end
    if container.Label then
        container.Label:SetShown(isUnlocked)
    end

    if #visibleBuffer == 0 then
        if not isUnlocked then
            container:Hide()
            if metricStartedAt then
                Performance:Finish("selfdr.refresh", metricStartedAt)
            end
            return
        end

        -- Keep the handle on screen while unlocked so the bar stays movable
        -- even when no diminishing return is currently running.
        container:SetSize(iconSize, iconSize)
        if not container.isDragging then
            AnchorContainer(settings, nil, growth)
        end
        container:Show()
        if metricStartedAt then
            Performance:Finish("selfdr.refresh", metricStartedAt)
        end
        return
    end

    table.sort(visibleBuffer, CompareIconsByStart)

    local width, height, pitch = Shared.CalculateTrayLayout(
        #visibleBuffer,
        iconSize,
        padding,
        layout
    )
    container:SetSize(
        math.max(width, iconSize),
        math.max(height, iconSize)
    )
    -- Re-anchoring mid-drag would snap the frame out from under the cursor.
    if not container.isDragging then
        AnchorContainer(settings, nil, growth)
    end

    for index, icon in ipairs(visibleBuffer) do
        Shared.AnchorChildByGrowth(icon, container, layout, growth, index, #visibleBuffer, pitch)
        icon:Show()
    end

    container:Show()
    if metricStartedAt then
        Performance:Finish("selfdr.refresh", metricStartedAt)
    end
end

-- Aura events arrive in bursts, and several of them can land in one frame. The
-- tray only has to settle once per frame, the same way the nameplate runtime
-- coalesces its own refreshes.
local pendingRefresh

function SelfDR.RequestRefresh()
    if pendingRefresh then
        if Performance and Performance.active then
            Performance:Count("selfdr.coalesced")
        end
        return
    end

    if Performance and Performance.active then
        Performance:Count("selfdr.requests")
    end
    pendingRefresh = C_Timer.NewTimer(0, function()
        pendingRefresh = nil
        SelfDR.Refresh()
    end)
end

--- Engine -----------------------------------------------------------------

local activeBuffer = {}
local spellsWithNonRoot = {}

local scanEntries = {}
local scanUpdatedAuraIDs

-- Returns false when a read failed, which is never the same as an empty list.
local function CollectLossOfControlEntries()
    wipe(scanEntries)

    local count = GetLossOfControlCount()
    if count <= 0 then
        -- An empty list is confirmed against the first slot instead of trusted:
        -- guessing wrong starts the reset window while the control still runs.
        local data, ok = GetLossOfControlData(1)
        if not ok then
            return false
        end
        if data == nil then
            return true
        end
        count = MAX_LOC_SLOTS
    end

    for index = 1, count do
        local data, ok = GetLossOfControlData(index)
        if not ok then
            return false
        end
        if data then
            scanEntries[#scanEntries + 1] = data
        end
    end

    return true
end

-- Runs inside a pcall: Midnight can hand out secret tables here and indexing one
-- raises an error.
local function CategorizeLossOfControlEntries()
    -- A single spell can emit both a root and a non-root lock (Warlock Fear).
    -- Only the non-root category drives the DR, so remember those spells first.
    for _, data in ipairs(scanEntries) do
        local category = GetCategoryForLossOfControl(data)
        if category and category ~= "root" and data.spellID then
            spellsWithNonRoot[data.spellID] = true
        end
    end

    for _, data in ipairs(scanEntries) do
        local category = GetCategoryForLossOfControl(data)
        if category and not (category == "root" and spellsWithNonRoot[data.spellID]) then
            local entry = activeBuffer[category]
            if not entry then
                entry = { auraIDs = {}, startTime = 0, refreshed = false }
                activeBuffer[category] = entry
            end
            if data.auraInstanceID then
                entry.auraIDs[data.auraInstanceID] = true
                if scanUpdatedAuraIDs and scanUpdatedAuraIDs[data.auraInstanceID] then
                    entry.refreshed = true
                end
            end
            local startTime = tonumber(data.startTime) or 0
            if startTime > entry.startTime then
                entry.startTime = startTime
            end
        end
    end
end

-- Returns nil when the Loss of Control list could not be read. Callers must
-- leave every tracked state untouched in that case, or a crowd control that is
-- still running looks like one that ended.
local function ScanLossOfControl(updatedAuraIDs)
    wipe(activeBuffer)
    wipe(spellsWithNonRoot)

    if not CollectLossOfControlEntries() then
        return nil
    end

    scanUpdatedAuraIDs = updatedAuraIDs
    local scanned = pcall(CategorizeLossOfControlEntries)
    scanUpdatedAuraIDs = nil

    if not scanned then
        return nil
    end

    return activeBuffer
end

local function StartDRWindow(category)
    local state = GetState(category)
    local icon = EnsureIcon(category)
    local now = GetTime()

    state.expiresAt = now + DR_RESET_DURATION
    icon.Cooldown:SetCooldown(now, DR_RESET_DURATION)
end

local UpdateLossOfControlPoll

local function UpdateFromLossOfControl(updatedAuraIDs)
    -- Zone gating is authoritative here as well as on event registration, so a
    -- settings refresh in a disabled zone cannot repopulate the tracker.
    if testMode or not IsFeatureEnabled() or not IsActiveInCurrentZone() then
        return
    end

    local metricStartedAt = Performance and Performance.active and Performance:Begin()

    local active = ScanLossOfControl(updatedAuraIDs)
    if not active then
        if metricStartedAt then
            Performance:Finish("selfdr.scan", metricStartedAt)
        end
        return
    end
    local now = GetTime()

    -- The player's UNIT_AURA fires for every buff and debuff they carry, and the
    -- fallback poll runs ten times a second. Almost none of those events move a
    -- diminishing return, so the tray is only rebuilt when one actually did.
    local stateChanged = false
    local settings = GetSettings()
    local track = settings and settings.track

    for _, category in ipairs(CATEGORIES) do
        local state = GetState(category)

        if not (track and track[category] == true) then
            if state.isActive or state.stage > 0 or state.expiresAt then
                ResetState(category)
                stateChanged = true
            end
        else
            local entry = active[category]
            local isActive = entry ~= nil
            local isNewApplication = false

            if isActive then
                if not state.isActive then
                    isNewApplication = true
                else
                    for auraID in pairs(entry.auraIDs) do
                        if not state.auraIDs or not state.auraIDs[auraID] then
                            isNewApplication = true
                            break
                        end
                    end
                    -- A crowd control re-applied on top of itself keeps its
                    -- auraInstanceID, so a moved startTime counts too.
                    if not isNewApplication
                        and entry.startTime > (state.lastStartTime or 0) + 0.05 then
                        isNewApplication = true
                    end
                end
            end

            if isNewApplication then
                -- A DR window that already elapsed must not carry its stage over.
                if state.expiresAt and state.expiresAt <= now then
                    state.stage = 0
                end
                state.stage = math.min(state.stage + 1, MAX_DR_STAGE)
                state.startedAt = now
                state.expiresAt = nil
                EnsureIcon(category).Cooldown:SetCooldown(0, 0)
                stateChanged = true
            end

            -- The DR timer only starts once the crowd control actually ends.
            if state.isActive and not isActive then
                StartDRWindow(category)
                stateChanged = true
            end

            if state.isActive ~= isActive then
                stateChanged = true
            end
            state.isActive = isActive
            state.auraIDs = isActive and entry.auraIDs or nil
            state.lastStartTime = isActive and entry.startTime or nil

            if not isActive and state.expiresAt and state.expiresAt <= now then
                ResetState(category)
                stateChanged = true
            end
        end
    end

    UpdateLossOfControlPoll()
    if stateChanged then
        SelfDR.RequestRefresh()
    elseif Performance and Performance.active then
        Performance:Count("selfdr.unchanged")
    end
    if metricStartedAt then
        Performance:Finish("selfdr.scan", metricStartedAt)
    end
end

local LOC_POLL_INTERVAL = 0.1
local locPollTicker

local function StopLossOfControlPoll()
    if locPollTicker then
        locPollTicker:Cancel()
        locPollTicker = nil
    end
end

SelfDR.StopLossOfControlPoll = StopLossOfControlPoll

local function HasActiveTrackedCategory()
    for _, category in ipairs(CATEGORIES) do
        local state = stateByCategory[category]
        if state and state.isActive then
            return true
        end
    end

    return false
end

-- The reset window only starts once the crowd control ends, and Loss of Control
-- can drop its entry without any player aura event to go with it. A missed
-- transition used to leave the icon on screen with no countdown at all, so a
-- short poll runs while a tracked control is active and stops with it.
UpdateLossOfControlPoll = function()
    if testMode or not IsFeatureEnabled() or not IsActiveInCurrentZone() then
        StopLossOfControlPoll()
        return
    end

    if not HasActiveTrackedCategory() then
        StopLossOfControlPoll()
        return
    end

    if not locPollTicker then
        locPollTicker = C_Timer.NewTicker(LOC_POLL_INTERVAL, function()
            UpdateFromLossOfControl(nil)
        end)
    end
end

--- Preview ----------------------------------------------------------------

local function ApplyPreviewStates()
    local settings = GetSettings()
    if not settings or settings.enabled ~= true then
        if container then
            container:Hide()
        end
        return false
    end

    local now = GetTime()
    previewStart = now

    GetTrackedCategories(trackedBuffer)
    for index, category in ipairs(trackedBuffer) do
        local state = GetState(category)
        state.isActive = false
        state.auraIDs = nil
        state.lastStartTime = nil
        -- Stagger the start times so the preview keeps a stable icon order,
        -- and force the first icon to the immune stage to show that styling.
        state.startedAt = now + (index * 0.001)
        state.expiresAt = now + DR_RESET_DURATION
        -- First icon previews the immune styling, the rest the half stage.
        state.stage = (index == 1) and MAX_DR_STAGE or 1

        local icon = EnsureIcon(category)
        icon.Cooldown:SetCooldown(now, DR_RESET_DURATION)
    end

    SelfDR.Refresh()
    return true
end

local function StopPreviewTicker()
    if previewTicker then
        previewTicker:Cancel()
        previewTicker = nil
    end
end

local function StartPreviewTicker()
    if previewTicker then
        return
    end
    previewTicker = C_Timer.NewTicker(DR_RESET_DURATION, function()
        if not testMode then
            StopPreviewTicker()
            return
        end
        if not ApplyPreviewStates() then
            StopPreviewTicker()
        end
    end)
end

function SelfDR.StartPreview()
    if testMode then
        return
    end

    testMode = true
    StopLossOfControlPoll()
    StopPreviewTicker()
    -- A disabled feature owns no preview or placement handle. Keeping local
    -- testMode active lets enabling it while global Preview is running show it
    -- immediately through RefreshAll().
    if ApplyPreviewStates() then
        StartPreviewTicker()
    end
end

function SelfDR.StopPreview()
    if not testMode then
        return
    end

    testMode = false
    StopPreviewTicker()

    SelfDR.ResetAllStates()
    for _, icon in pairs(iconsByCategory) do
        icon.Cooldown:SetCooldown(0, 0)
        icon:Hide()
    end

    UpdateFromLossOfControl(nil)
    SelfDR.Refresh()
end

function SelfDR.IsPreviewActive()
    return testMode
end

--- Position ---------------------------------------------------------------

function SelfDR.ResetPosition()
    local settings = GetSettings()
    local defaultSettings = Shared.defaults.selfDR

    settings.relativeFrame = defaultSettings.relativeFrame
    settings.point = defaultSettings.point
    settings.relativePoint = defaultSettings.relativePoint
    settings.offsetX = defaultSettings.offsetX
    settings.offsetY = defaultSettings.offsetY

    -- Written straight into the saved variables, so the cached normalization
    -- and every style snapshot keyed on its revision have to go.
    Shared.InvalidateDB()
    SelfDR.Refresh()
end

--- Events -----------------------------------------------------------------

local eventFrame = CreateFrame("Frame", Shared.NextFrameName("SelfDR", "EventFrame"))

local function ApplyZoneState()
    local shouldTrack = IsFeatureEnabled() and IsActiveInCurrentZone()

    if shouldTrack and not eventsRegistered then
        eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        -- Aura events alone miss the moment a crowd control clears its Loss of
        -- Control entry, which is exactly when the reset window has to start.
        eventFrame:RegisterEvent("LOSS_OF_CONTROL_ADDED")
        eventFrame:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
        eventsRegistered = true
    elseif not shouldTrack and eventsRegistered then
        eventFrame:UnregisterEvent("UNIT_AURA")
        eventFrame:UnregisterEvent("LOSS_OF_CONTROL_ADDED")
        eventFrame:UnregisterEvent("LOSS_OF_CONTROL_UPDATE")
        eventsRegistered = false
    end

    if not shouldTrack and not testMode then
        SelfDR.StopLossOfControlPoll()
        SelfDR.ResetAllStates()
        for _, icon in pairs(iconsByCategory) do
            icon.Cooldown:SetCooldown(0, 0)
            icon:Hide()
        end
    end
end

local updatedAuraIDBuffer = {}

-- Midnight can hand out secret tables here, which cannot be iterated. When that
-- happens we simply fall back to the startTime heuristic in the state machine.
local function BuildUpdatedAuraSet(updateInfo)
    if not updateInfo then
        return nil
    end

    local ok, updated = pcall(function()
        return updateInfo.updatedAuraInstanceIDs
    end)
    if not ok or type(updated) ~= "table" or IsSecretValue(updated) then
        return nil
    end

    wipe(updatedAuraIDBuffer)
    local filled = pcall(function()
        for _, auraInstanceID in ipairs(updated) do
            if not IsSecretValue(auraInstanceID) then
                updatedAuraIDBuffer[auraInstanceID] = true
            end
        end
    end)
    if not filled then
        wipe(updatedAuraIDBuffer)
        return nil
    end

    return updatedAuraIDBuffer
end

eventFrame:SetScript("OnEvent", function(_, event, unit, updateInfo)
    if event == "UNIT_AURA" then
        if unit ~= "player" then
            return
        end
        UpdateFromLossOfControl(BuildUpdatedAuraSet(updateInfo))
        return
    end

    if event == "LOSS_OF_CONTROL_ADDED" or event == "LOSS_OF_CONTROL_UPDATE" then
        UpdateFromLossOfControl(nil)
        return
    end

    -- Zone changes invalidate every tracked window.
    if not testMode then
        SelfDR.StopLossOfControlPoll()
        SelfDR.ResetAllStates()
    end
    ApplyZoneState()
    SelfDR.Refresh()
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

--- Public bridge ----------------------------------------------------------

function SelfDR.RefreshAll()
    ApplyZoneState()
    if testMode then
        StopPreviewTicker()
        if ApplyPreviewStates() then
            StartPreviewTicker()
        end
        return
    end
    UpdateFromLossOfControl(nil)
    SelfDR.Refresh()
end

_G.ArenaDRNameplates_RefreshSelfDR = SelfDR.RefreshAll
_G.ArenaDRNameplates_ResetSelfDRPosition = SelfDR.ResetPosition
_G.ArenaDRNameplates_StartSelfDRPreview = SelfDR.StartPreview
_G.ArenaDRNameplates_StopSelfDRPreview = SelfDR.StopPreview
