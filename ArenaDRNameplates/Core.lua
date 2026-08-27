local _, ns = ...
ns = ns or {}

local Shared = ns.Shared
local S = Shared.S
local Performance = ns.Performance

local ARENA_IDS = { 1, 2, 3 }
local TEST_SPELLS = {
    { spellID = 408, duration = 18 },
    { spellID = 5782, duration = 15 },
    { spellID = 118, duration = 12, isImmune = true },
}
local PREVIEW_MIN_DR_COUNT = 1
local PREVIEW_MAX_DR_COUNT = 3
local PREVIEW_MIN_DURATION = 8
local PREVIEW_MAX_DURATION = 24

local defaults = Shared.defaults
local LIVE_ICON_SIZE = Shared.iconBaseSizes.nameplate
local TRINKET_BASE_ICON_SIZE = Shared.iconBaseSizes.trinket
local validDRTextAnchors = Shared.validDRTextAnchors
local NextFrameName = Shared.NextFrameName
local NormalizeTrinketVisibility = Shared.NormalizeTrinketVisibility
local issecretvalue_fn = _G.issecretvalue

local db
local liveContainers = {}
local sourceInfoByArenaID = {}
local trinketMirrors = {}
local recoveryTicker
local previewTicker
local styleRevision = 1
local styleSnapshot
local pendingLiveLayouts = {}
local resolvedArenaParents = {}
local runtimeRefreshState = {
    forceSourceResync = false,
    recoveryTickCount = 0,
}
local testMode = false
local testTrays = {}
local testConfigsByKey = {}
local testTrinketIcon
local testModeStartedAt
local helperCallbackOwner = {}
local sharedMediaCallbackOwner = {}
local parkingRoot
local GetStyleSnapshot
local UpdateRecoveryTicker
local RefreshLiveRuntime
local RefreshLiveRuntimeLight
local RequestLiveRuntimeRefresh
local CancelPendingRuntimeRefresh
local UpdateLiveSlotVisibility

local function GetParkingRoot()
    if parkingRoot then
        return parkingRoot
    end

    parkingRoot = CreateFrame("Frame", NextFrameName("Core", "ParkingRoot"), UIParent)
    parkingRoot:SetSize(1, 1)
    parkingRoot:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -4096, -4096)
    parkingRoot:Show()
    return parkingRoot
end

local function ParkFrameOffscreen(frame)
    if not frame then
        return
    end

    if frame.ArenaDRNameplatesParked then
        return
    end

    local root = GetParkingRoot()
    if frame:GetParent() ~= root then
        frame:SetParent(root)
    end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", root, "CENTER", 0, 0)
    frame.ArenaDRNameplatesParked = true
    frame.ArenaDRNameplatesAnchorParent = nil
    frame.ArenaDRNameplatesAnchorRelativeFrame = nil
end

local function InvalidateStyleSnapshot()
    styleRevision = styleRevision + 1
    styleSnapshot = nil
end

local function IgnoreParentAlpha(frame)
    if frame and type(frame.SetIgnoreParentAlpha) == "function" then
        frame:SetIgnoreParentAlpha(true)
    end
end

local function GetHelper()
    return ns and ns.ArenaNameplateHelper
end

local function NotifySettingsUIRefresh()
    if type(_G.ArenaDRNameplates_RefreshSettingsUI) == "function" then
        _G.ArenaDRNameplates_RefreshSettingsUI()
    end
end

runtimeRefreshState.arenaDRMirrorCallbacks = {}
runtimeRefreshState.NotifyArenaDRMirrorChanged = function(arenaID)
    for owner, callback in pairs(runtimeRefreshState.arenaDRMirrorCallbacks) do
        local ok = pcall(callback, owner, arenaID, liveContainers[arenaID])
        if not ok then
            -- A consumer must never interrupt Blizzard tray mirroring.
        end
    end
end

local NormalizeColorTable = Shared.NormalizeColorTable
local ClampNumber = Shared.ClampNumber

local function IsSecretValue(value)
    if type(issecretvalue_fn) ~= "function" then
        return false
    end

    local ok, result = pcall(issecretvalue_fn, value)
    return ok and result == true
end

local function Trim(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetEffectiveIconGrowth()
    return db and Shared.GetEffectiveIconGrowthForTable(db) or defaults.iconGrowth
end

local function GetIconLayout()
    return db and Shared.GetEffectiveIconLayoutForTable(db) or defaults.iconLayout
end

local function GetIconPadding()
    if not db then
        return defaults.iconPadding
    end

    return ClampNumber(db.iconPadding, 0, 20, defaults.iconPadding)
end

local function ShouldScaleWithNameplate()
    if not db then
        return defaults.scaleWithNameplate == true
    end

    return db.scaleWithNameplate ~= false
end

local function GetDRTrayScale(parent)
    local scaleValue = ClampNumber(db and db.scale, 0.5, 3.0, defaults.scale)
    return Shared.ResolveIconScale(
        LIVE_ICON_SIZE,
        LIVE_ICON_SIZE,
        scaleValue,
        parent,
        ShouldScaleWithNameplate()
    )
end

local function GetTrinketSettings()
    if db and type(db.trinket) == "table" then
        return db.trinket
    end

    return defaults.trinket
end

local function IsTrinketEnabled()
    return GetTrinketSettings().enabled == true
end

local function GetTrinketVisibilityMode()
    return NormalizeTrinketVisibility(GetTrinketSettings().visibility)
end

local function GetTrinketSize()
    return GetStyleSnapshot().trinketSize
end

local function GetTrinketOpacity()
    return GetStyleSnapshot().trinketOpacity
end

local function GetTrinketBorderStyle()
    return GetStyleSnapshot().trinketBorderStyle
end

local function GetTrinketBorderWidth()
    return GetStyleSnapshot().trinketBorderWidth
end

local function GetTrinketBorderColorRGB()
    local color = GetStyleSnapshot().trinketBorderColor
    return color[1], color[2], color[3]
end

local function GetEffectiveTrinketAnchor()
    local settings = GetTrinketSettings()
    return
        settings.point or defaults.trinket.point,
        settings.relativePoint or defaults.trinket.relativePoint,
        ClampNumber(settings.offsetX, -150, 150, defaults.trinket.offsetX),
        ClampNumber(settings.offsetY, -150, 150, defaults.trinket.offsetY)
end

local function GetTrinketTimerBaseFontSize()
    return math.max(10, math.floor(TRINKET_BASE_ICON_SIZE * 0.55 + 0.5))
end

local function GetFrameVisualScale(frame)
    local visualScale = tonumber(frame and frame.ArenaDRNameplatesVisualScale) or 1
    if visualScale <= 0 then
        return 1
    end
    return visualScale
end

-- Shared owns this so the Target/Focus bars cannot drift to a looser reading of
-- the same match state than the tray mirror they consume.
local IsInArena = Shared.IsInArena

local function IsEnemyTarget()
    return UnitExists("target")
        and not UnitIsUnit("target", "player")
        and UnitCanAttack("player", "target")
end

local function GetTimerColorRGB()
    local color = GetStyleSnapshot().timerTextColor
    return color[1], color[2], color[3]
end

local function GetTimerTextScale()
    return GetStyleSnapshot().timerTextScale
end

local function GetTimerTextOffsets()
    local snapshot = GetStyleSnapshot()
    return snapshot.timerTextOffsetX, snapshot.timerTextOffsetY
end

local function IsTimerTextEnabled()
    if not db then
        return defaults.showTimerText
    end

    if type(db.showTimerText) ~= "boolean" then
        return defaults.showTimerText
    end

    return db.showTimerText
end

local function AreTimerDecimalsEnabled()
    if not db then
        return defaults.showTimerDecimals
    end

    if type(db.showTimerDecimals) ~= "boolean" then
        return defaults.showTimerDecimals
    end

    return db.showTimerDecimals
end

local function GetTimerDecimalThreshold()
    local threshold = db and db.timerDecimalThreshold or defaults.timerDecimalThreshold
    return math.floor(ClampNumber(threshold, 1, 20, defaults.timerDecimalThreshold) + 0.5)
end

local function IsTimerSwipeEnabled()
    if not db then
        return defaults.showTimerSwipe
    end

    if type(db.showTimerSwipe) ~= "boolean" then
        return defaults.showTimerSwipe
    end

    return db.showTimerSwipe
end

local function IsTimerSwipeEdgeEnabled()
    if not db then
        return defaults.showTimerSwipeEdge
    end

    if type(db.showTimerSwipeEdge) ~= "boolean" then
        return defaults.showTimerSwipeEdge
    end

    return db.showTimerSwipeEdge
end

local function ApplyCooldownStyle(cooldown)
    if not cooldown then
        return
    end

    local showSwipe = IsTimerSwipeEnabled()
    local showSwipeEdge = showSwipe and IsTimerSwipeEdgeEnabled()

    if cooldown.SetDrawSwipe then
        cooldown:SetDrawSwipe(showSwipe)
    end

    if cooldown.SetSwipeColor then
        if showSwipe then
            cooldown:SetSwipeColor(0, 0, 0, 0.7)
        else
            cooldown:SetSwipeColor(0, 0, 0, 0)
        end
    end

    if cooldown.SetDrawEdge then
        cooldown:SetDrawEdge(showSwipeEdge)
    end

    if cooldown.SetDrawBling then
        cooldown:SetDrawBling(false)
    end

    if cooldown.SetCountdownMillisecondsThreshold then
        cooldown:SetCountdownMillisecondsThreshold(
            AreTimerDecimalsEnabled() and GetTimerDecimalThreshold() or 0
        )
    end

    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(not IsTimerTextEnabled())
    end
end

local function ClearCooldown(cooldown)
    if cooldown then
        cooldown:Clear()
    end
end

local function GetDRTextColorRGB(isImmune)
    local snapshot = GetStyleSnapshot()
    local color = isImmune and snapshot.drTextImmuneColor or snapshot.drTextColor
    return color[1], color[2], color[3]
end

local function GetDRBorderColorRGB(isImmune)
    local snapshot = GetStyleSnapshot()
    local color = isImmune and snapshot.drBorderImmuneColor or snapshot.drBorderColor
    return color[1], color[2], color[3]
end

GetStyleSnapshot = function()
    if styleSnapshot and styleSnapshot.revision == styleRevision then
        return styleSnapshot
    end

    local settings = db or defaults
    local trinketSettings = GetTrinketSettings()
    local normalBorder = NormalizeColorTable(settings.drBorderColor, defaults.drBorderColor)
    local immuneBorder = NormalizeColorTable(settings.drBorderImmuneColor, defaults.drBorderImmuneColor)

    styleSnapshot = {
        revision = styleRevision,
        timerTextColor = NormalizeColorTable(settings.timerTextColor, defaults.timerTextColor),
        timerTextScale = ClampNumber(settings.timerTextScale, 0.5, 3.0, defaults.timerTextScale),
        timerTextOffsetX = ClampNumber(settings.timerTextOffsetX, -50, 50, defaults.timerTextOffsetX),
        timerTextOffsetY = ClampNumber(settings.timerTextOffsetY, -50, 50, defaults.timerTextOffsetY),
        drTextColor = NormalizeColorTable(settings.drTextColor, defaults.drTextColor),
        drTextImmuneColor = NormalizeColorTable(settings.drTextImmuneColor, defaults.drTextImmuneColor),
        drBorderColor = normalBorder,
        drBorderImmuneColor = immuneBorder,
        drBorderStyle = Shared.NormalizeDRBorderStyle(settings.drBorderStyle),
        drBorderWidth = ClampNumber(settings.drBorderWidth, 1, 8, defaults.drBorderWidth),
        normalBorderColorObject = CreateColor(normalBorder[1], normalBorder[2], normalBorder[3], 1),
        immuneBorderColorObject = CreateColor(immuneBorder[1], immuneBorder[2], immuneBorder[3], 1),
        trinketBorderColor = NormalizeColorTable(trinketSettings.borderColor, defaults.trinket.borderColor),
        trinketSize = ClampNumber(trinketSettings.size, 12, 80, defaults.trinket.size),
        trinketOpacity = ClampNumber(trinketSettings.opacity, 0.1, 1.0, defaults.trinket.opacity),
        trinketBorderStyle = Shared.NormalizeTrinketBorderStyle(trinketSettings.borderStyle),
        trinketBorderWidth = ClampNumber(trinketSettings.borderWidth, 1, 8, defaults.trinket.borderWidth),
        textFont = settings.textFont,
        textOutlineFlags = Shared.GetTextOutlineFlags(settings.textOutline),
        anchorContext = {
            anchorPreset = settings.anchorPreset or defaults.anchorPreset,
            iconLayout = GetIconLayout(),
            point = settings.point or defaults.point,
            relativePoint = settings.relativePoint or defaults.relativePoint,
        },
    }
    return styleSnapshot
end

local function GetDRBorderWidth()
    return GetStyleSnapshot().drBorderWidth
end

local function GetDRBorderStyle()
    return GetStyleSnapshot().drBorderStyle
end

local function FindCooldownText(frame)
    if not frame then
        return nil
    end

    if frame.timerFontString
        and frame.timerFontString.GetObjectType
        and frame.timerFontString:GetObjectType() == "FontString" then
        return frame.timerFontString
    end

    if frame.Cooldown then
        local cooldown = frame.Cooldown

        if cooldown.GetCountdownFontString then
            local ok, countdownFontString = pcall(cooldown.GetCountdownFontString, cooldown)
            if ok
                and countdownFontString
                and countdownFontString.GetObjectType
                and countdownFontString:GetObjectType() == "FontString" then
                frame.timerFontString = countdownFontString
                return frame.timerFontString
            end
        end

        if cooldown.Text
            and cooldown.Text.GetObjectType
            and cooldown.Text:GetObjectType() == "FontString" then
            frame.timerFontString = cooldown.Text
            return frame.timerFontString
        end

        for _, region in ipairs({ cooldown:GetRegions() }) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                frame.timerFontString = region
                return region
            end
        end
    end

    return nil
end

local function FindCooldownFrame(frame)
    if not frame then
        return nil
    end

    if frame.Cooldown and frame.Cooldown.GetCooldownTimes then
        return frame.Cooldown
    end

    if frame.cooldown and frame.cooldown.GetCooldownTimes then
        return frame.cooldown
    end

    if frame.CooldownFrame and frame.CooldownFrame.GetCooldownTimes then
        return frame.CooldownFrame
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        if child and child.GetCooldownTimes and child.SetCooldown then
            return child
        end
    end

    return nil
end

local function FindTextureRegion(frame)
    if not frame then
        return nil
    end

    if frame.Icon and frame.Icon.GetTexture then
        return frame.Icon
    end

    if frame.icon and frame.icon.GetTexture then
        return frame.icon
    end

    for _, region in ipairs({ frame:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            return region
        end
    end

    return nil
end

local function ApplyTimerTextStyle(timerText, parent, fontSize, visualScale)
    if not timerText or not parent then
        return
    end

    local timerR, timerG, timerB = GetTimerColorRGB()
    local offsetX, offsetY = GetTimerTextOffsets()
    local textScale = GetTimerTextScale()
    visualScale = tonumber(visualScale) or GetFrameVisualScale(parent)
    local actualFontSize = math.max(
        6,
        math.floor((tonumber(fontSize) or 14) * textScale * visualScale + 0.5)
    )

    timerText:SetTextColor(timerR, timerG, timerB, 1)
    timerText:ClearAllPoints()
    timerText:SetPoint(
        "CENTER",
        parent,
        "CENTER",
        offsetX * visualScale,
        offsetY * visualScale
    )

    if timerText.SetJustifyH then
        timerText:SetJustifyH("CENTER")
    end
    if timerText.SetJustifyV then
        timerText:SetJustifyV("MIDDLE")
    end

    local textStyle = GetStyleSnapshot()
    Shared.ApplyTextFont(timerText, actualFontSize, textStyle.textOutlineFlags, textStyle.textFont)
end

-- Midnight Season 2 increases the PvP DR reset window from 16 to 20 seconds.
-- The source values are secret in combat, so the mirror uses a public fallback.
-- Blizzard's source OnCooldownDone still clears the mirror at the exact expiry.
local LIVE_DR_RESET_DURATION = Shared.DR_RESET_DURATION
local LIVE_DR_TIMER_DURATION = LIVE_DR_RESET_DURATION + 0.1

-- Blizzard zeroes the source cooldown while the crowd control is still running
-- and only sets the reset window once it breaks, so a slot without a window is a
-- normal state: the icon shows with no countdown until the control ends.
local function ResetLiveSlotWindow(slot)
    if not slot then
        return
    end

    slot.ArenaDRNameplatesLiveWindowEndsAt = nil
    slot.ArenaDRNameplatesLiveWindowExpired = false
end

-- A source item shown again carries a new crowd control, so a stale expiry has
-- to go without disturbing a window that is still counting.
local function ClearLiveSlotWindowExpiry(slot)
    if slot and slot.ArenaDRNameplatesLiveCooldownActive ~= true then
        ResetLiveSlotWindow(slot)
    end
end

local function IsLiveSlotWindowExpired(slot)
    if not slot then
        return false
    end

    if slot.ArenaDRNameplatesLiveWindowExpired == true then
        return true
    end

    local endsAt = slot.ArenaDRNameplatesLiveWindowEndsAt
    return type(endsAt) == "number" and endsAt <= GetTime()
end

local function StartLiveSlotCooldown(slot, durationSeconds, startedAtSeconds)
    if not slot or not slot.Cooldown then
        return
    end

    local cooldown = slot.Cooldown
    local now = GetTime()
    local trackedDuration = tonumber(durationSeconds) or LIVE_DR_TIMER_DURATION
    if trackedDuration <= 0 then
        trackedDuration = LIVE_DR_TIMER_DURATION
    end

    -- A start time read from the source keeps the mirror aligned with a window
    -- that began before this slot learned about it. It can never sit in the
    -- future, which would leave the countdown frozen.
    local startedAt = tonumber(startedAtSeconds) or now
    if startedAt <= 0 or startedAt > now then
        startedAt = now
    end

    ResetLiveSlotWindow(slot)
    pcall(function()
        cooldown:SetCooldown(startedAt, trackedDuration)
    end)
    slot.ArenaDRNameplatesLiveCooldownActive = true
    slot.ArenaDRNameplatesLiveWindowEndsAt = startedAt + trackedDuration
end

-- Reads the source window without ever comparing a secret value: in combat
-- Blizzard hands out protected numbers here and the mirror falls back to the
-- public reset duration instead.
local function GetPublicSourceCooldownTimes(sourceCooldown)
    if not sourceCooldown or type(sourceCooldown.GetCooldownTimes) ~= "function" then
        return nil
    end

    local ok, startMS, durationMS = pcall(sourceCooldown.GetCooldownTimes, sourceCooldown)
    if not ok or IsSecretValue(startMS) or IsSecretValue(durationMS) then
        return nil
    end
    if type(startMS) ~= "number" or type(durationMS) ~= "number" or durationMS <= 0 then
        return nil
    end

    return startMS / 1000, durationMS / 1000
end

local function EnsureVisualOverlay(frame)
    if not frame then
        return nil
    end

    local overlay = frame.ArenaDRNameplatesVisualOverlay
    if not overlay then
        overlay = CreateFrame("Frame", NextFrameName("Core", "VisualOverlay"), frame)
        overlay:SetAllPoints(frame)
        overlay:EnableMouse(false)
        frame.ArenaDRNameplatesVisualOverlay = overlay
    end

    local targetLevel = frame.GetFrameLevel and frame:GetFrameLevel() or 0
    if frame.Cooldown and frame.Cooldown.GetFrameLevel then
        targetLevel = math.max(targetLevel, frame.Cooldown:GetFrameLevel())
    end
    if overlay.SetFrameLevel then
        overlay:SetFrameLevel(targetLevel + 10)
    end

    return overlay
end

local CLASSIC_BORDER_TEXTURE = "Interface\\Buttons\\UI-Debuff-Overlays"
local CLASSIC_BORDER_TEX_COORDS = {
    0.296875,
    0.5703125,
    0,
    0.515625,
}

local function EnsureSolidDRBorderRegions(overlay)
    if not overlay then
        return nil
    end

    if not overlay.ArenaDRNameplatesBorderSegments then
        local function CreateBorderSegment()
            local segment = overlay:CreateTexture(nil, "ARTWORK")
            segment:SetTexture("Interface\\Buttons\\WHITE8X8")
            return segment
        end

        local top = CreateBorderSegment()
        local bottom = CreateBorderSegment()
        local left = CreateBorderSegment()
        local right = CreateBorderSegment()

        overlay.ArenaDRNameplatesBorderSegments = {
            top,
            bottom,
            left,
            right,
        }
    end

    return overlay.ArenaDRNameplatesBorderSegments
end

local function UpdateSolidDRBorderLayout(overlay, visualScale)
    local borderSegments = EnsureSolidDRBorderRegions(overlay)
    if not borderSegments then
        return nil
    end

    local borderWidth = GetDRBorderWidth() * visualScale
    local extent = borderWidth / 2
    local top = borderSegments[1]
    local bottom = borderSegments[2]
    local left = borderSegments[3]
    local right = borderSegments[4]

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", overlay, "TOPLEFT", -extent, extent)
    top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", extent, extent)
    top:SetHeight(borderWidth)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -extent, -extent)
    bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", extent, -extent)
    bottom:SetHeight(borderWidth)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", overlay, "TOPLEFT", -extent, extent)
    left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -extent, -extent)
    left:SetWidth(borderWidth)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", extent, extent)
    right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", extent, -extent)
    right:SetWidth(borderWidth)

    return borderSegments
end

local function EnsureClassicDRBorderRegion(overlay)
    if not overlay then
        return nil
    end

    if not overlay.ArenaDRNameplatesClassicBorder then
        local border = overlay:CreateTexture(nil, "OVERLAY")
        border:SetTexture(CLASSIC_BORDER_TEXTURE)
        border:SetTexCoord(unpack(CLASSIC_BORDER_TEX_COORDS))
        overlay.ArenaDRNameplatesClassicBorder = border
    end

    return overlay.ArenaDRNameplatesClassicBorder
end

local function UpdateClassicDRBorderLayout(overlay, visualScale)
    local border = EnsureClassicDRBorderRegion(overlay)
    if not border then
        return nil
    end

    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", overlay, "TOPLEFT", -visualScale, visualScale)
    border:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", visualScale, -visualScale)
    return border
end

local function HideDRBorderVisuals(overlay)
    if not overlay then
        return
    end

    if overlay.ArenaDRNameplatesBorderSegments then
        for _, segment in ipairs(overlay.ArenaDRNameplatesBorderSegments) do
            segment:Hide()
        end
    end

    if overlay.ArenaDRNameplatesClassicBorder then
        overlay.ArenaDRNameplatesClassicBorder:Hide()
    end
end

local function GetDRBorderVisual(frame)
    local overlay = EnsureVisualOverlay(frame)
    if not overlay then
        return nil, nil
    end

    local borderStyle = GetDRBorderStyle()
    local visualScale = GetFrameVisualScale(frame)
    if borderStyle == "NONE" then
        HideDRBorderVisuals(overlay)
        return borderStyle, nil
    end

    if borderStyle == "CLASSIC" then
        local border = UpdateClassicDRBorderLayout(overlay, visualScale)
        if overlay.ArenaDRNameplatesBorderSegments then
            for _, segment in ipairs(overlay.ArenaDRNameplatesBorderSegments) do
                segment:Hide()
            end
        end
        return borderStyle, border
    end

    local borderSegments = UpdateSolidDRBorderLayout(overlay, visualScale)
    if overlay.ArenaDRNameplatesClassicBorder then
        overlay.ArenaDRNameplatesClassicBorder:Hide()
    end
    return borderStyle, borderSegments
end

local function ApplyDRBorderColor(frame, isImmune)
    local borderStyle, borderVisual = GetDRBorderVisual(frame)
    if not borderVisual then
        return
    end

    local snapshot = GetStyleSnapshot()
    local normalR, normalG, normalB = GetDRBorderColorRGB(false)
    local immuneR, immuneG, immuneB = GetDRBorderColorRGB(true)
    local normalColor = snapshot.normalBorderColorObject
    local immuneColor = snapshot.immuneBorderColorObject

    local function ApplyTextureColor(texture)
        if texture.SetVertexColorFromBoolean then
            texture:SetVertexColorFromBoolean(isImmune, immuneColor, normalColor)
        elseif not IsSecretValue(isImmune) then
            local r, g, b = normalR, normalG, normalB
            if isImmune then
                r, g, b = immuneR, immuneG, immuneB
            end
            texture:SetVertexColor(r, g, b, 1)
        else
            texture:SetVertexColor(normalR, normalG, normalB, 1)
        end
    end

    if borderStyle == "CLASSIC" then
        ApplyTextureColor(borderVisual)
        borderVisual:Show()
        return
    end

    for _, segment in ipairs(borderVisual) do
        ApplyTextureColor(segment)
        segment:Show()
    end
end

local function EnsureDRTextRegions(frame)
    if not frame then
        return nil, nil
    end

    local overlay = EnsureVisualOverlay(frame)
    if not overlay then
        return nil, nil
    end

    local textStyle = GetStyleSnapshot()

    if not frame.ArenaDRNameplatesDRText then
        local drText = overlay:CreateFontString(nil, "OVERLAY")
        Shared.ApplyTextFont(drText, 14, textStyle.textOutlineFlags, textStyle.textFont)
        drText:SetShadowOffset(1, -1)
        drText:SetShadowColor(0, 0, 0, 1)
        if drText.SetDrawLayer then
            drText:SetDrawLayer("OVERLAY", 7)
        end
        drText:SetText("½")
        frame.ArenaDRNameplatesDRText = drText
    end

    if not frame.ArenaDRNameplatesDRTextImmune then
        local drTextImmune = overlay:CreateFontString(nil, "OVERLAY")
        Shared.ApplyTextFont(drTextImmune, 14, textStyle.textOutlineFlags, textStyle.textFont)
        drTextImmune:SetShadowOffset(1, -1)
        drTextImmune:SetShadowColor(0, 0, 0, 1)
        if drTextImmune.SetDrawLayer then
            drTextImmune:SetDrawLayer("OVERLAY", 7)
        end
        drTextImmune:SetText("%")
        frame.ArenaDRNameplatesDRTextImmune = drTextImmune
    end

    return frame.ArenaDRNameplatesDRText, frame.ArenaDRNameplatesDRTextImmune
end

local function EnsureImmunityIndicatorRegion(frame)
    if not frame then
        return nil
    end

    local overlay = EnsureVisualOverlay(frame)
    if not overlay then
        return nil
    end

    if not frame.ImmunityIndicator then
        local immunityIndicator = overlay:CreateTexture(nil, "OVERLAY")
        immunityIndicator:SetTexture("Interface\\AddOns\\ArenaDRNameplates\\Images\\shield.tga")
        if immunityIndicator.SetDrawLayer then
            immunityIndicator:SetDrawLayer("OVERLAY", 7)
        end
        immunityIndicator:Hide()
        frame.ImmunityIndicator = immunityIndicator
    end

    local immunityIndicator = frame.ImmunityIndicator
    local visualScale = GetFrameVisualScale(frame)
    if immunityIndicator.ArenaDRNameplatesVisualScale ~= visualScale then
        immunityIndicator.ArenaDRNameplatesVisualScale = visualScale
        immunityIndicator:SetSize(12 * visualScale, 12 * visualScale)
        immunityIndicator:ClearAllPoints()
        immunityIndicator:SetPoint("CENTER", overlay, "TOP", 0, 2 * visualScale)
    end

    return immunityIndicator
end

local function SetDRTextAlpha(frame, normalAlpha, immuneAlpha)
    local drText, drTextImmune = EnsureDRTextRegions(frame)
    if not drText or not drTextImmune then
        return
    end

    drText:SetAlpha(normalAlpha or 0)
    drTextImmune:SetAlpha(immuneAlpha or 0)
end

local function SetImmunityIndicatorAlpha(frame)
    local indicator = EnsureImmunityIndicatorRegion(frame)
    if not indicator or not indicator.SetAlpha then
        return
    end

    local visibleAlpha = (db and db.showImmunityIndicator) and 1 or 0

    if frame and frame.ArenaDRNameplatesLiveTracksImmunity and indicator.SetAlphaFromBoolean then
        indicator:Show()
        indicator:SetAlphaFromBoolean(frame.ArenaDRNameplatesLiveIsImmune, visibleAlpha, 0)
        return
    end

    indicator:SetAlpha(visibleAlpha)
end

local function SetDRBorderColor(frame, isImmune)
    ApplyDRBorderColor(frame, isImmune)
end

local function ApplyDRBorderVisibilityFromImmune(frame, shown)
    ApplyDRBorderColor(frame, shown)
end

local function ApplyDRVisualStateFromImmune(frame, shown)
    SetImmunityIndicatorAlpha(frame)
    ApplyDRBorderVisibilityFromImmune(frame, shown)

    if not db or not db.showDRText then
        SetDRTextAlpha(frame, 0, 0)
        return
    end

    local drText, drTextImmune = EnsureDRTextRegions(frame)
    if not drText or not drTextImmune then
        return
    end

    drText:SetAlphaFromBoolean(shown, 0, 1)
    drTextImmune:SetAlphaFromBoolean(shown, 1, 0)
end

local function ApplyDRTextStyle(frame, baseFontSize, isImmuneOverride)
    if not frame then
        return
    end

    local overlay = EnsureVisualOverlay(frame)
    local drText, drTextImmune = EnsureDRTextRegions(frame)
    if not overlay or not drText or not drTextImmune then
        return
    end

    SetImmunityIndicatorAlpha(frame)

    local visualScale = GetFrameVisualScale(frame)
    local fontSize = math.max(
        6,
        math.floor((tonumber(baseFontSize) or 14) * visualScale + 0.5)
    )
    local anchor = db.drTextAnchor
    if not validDRTextAnchors[anchor] then
        anchor = defaults.drTextAnchor
    end
    local offsetX = tonumber(db.drTextOffsetX) or 4
    local offsetY = tonumber(db.drTextOffsetY) or -4
    local scale = tonumber(db.drTextScale) or 1.0
    local textStyle = GetStyleSnapshot()

    Shared.ApplyTextFont(drText, fontSize, textStyle.textOutlineFlags, textStyle.textFont)
    drText:SetText("½")
    drText:SetScale(scale)
    drText:ClearAllPoints()
    drText:SetPoint(
        anchor,
        overlay,
        anchor,
        offsetX * visualScale,
        offsetY * visualScale
    )
    drText:SetTextColor(GetDRTextColorRGB(false))

    Shared.ApplyTextFont(drTextImmune, fontSize, textStyle.textOutlineFlags, textStyle.textFont)
    drTextImmune:SetText("%")
    drTextImmune:SetScale(scale)
    drTextImmune:ClearAllPoints()
    drTextImmune:SetPoint("CENTER", drText, "CENTER", 0, 0)
    drTextImmune:SetTextColor(GetDRTextColorRGB(true))

    if not db.showDRText then
        SetDRTextAlpha(frame, 0, 0)
    else
        SetDRTextAlpha(frame, 1, 0)
    end

    if IsSecretValue(isImmuneOverride) or isImmuneOverride ~= nil then
        ApplyDRVisualStateFromImmune(frame, isImmuneOverride)
        return
    end

    if frame.ImmunityIndicator and frame.ImmunityIndicator.IsShown then
        ApplyDRVisualStateFromImmune(frame, frame.ImmunityIndicator:IsShown())
    else
        ApplyDRVisualStateFromImmune(frame, false)
    end
end

local function ApplyLiveDRTextStyle(frame, baseFontSize)
    ApplyDRTextStyle(frame, baseFontSize, false)
    ApplyDRVisualStateFromImmune(frame, frame and frame.ArenaDRNameplatesLiveIsImmune)
end

local function EnsureDB()
    db = Shared.EnsureDB()
end

local function CreateDRIconFrame(parent, explicitID)
    local icon = CreateFrame("Frame", NextFrameName("Core", "DRIcon", explicitID), parent)
    icon:SetSize(LIVE_ICON_SIZE, LIVE_ICON_SIZE)
    icon:EnableMouse(false)

    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.Icon = texture

    local cooldown = CreateFrame(
        "Cooldown",
        NextFrameName("Core", "DRCooldown", explicitID),
        icon,
        "CooldownFrameTemplate"
    )
    cooldown:SetAllPoints(icon)
    cooldown:SetReverse(false)
    icon.Cooldown = cooldown

    EnsureDRTextRegions(icon)
    EnsureImmunityIndicatorRegion(icon)
    return icon
end

local function GetLiveContainer(arenaID)
    local frame = liveContainers[arenaID]
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", NextFrameName("Core", "LiveContainer", arenaID), UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(200)
    frame:EnableMouse(false)
    IgnoreParentAlpha(frame)
    frame.slots = {}
    frame:Hide()
    liveContainers[arenaID] = frame
    return frame
end

ns.ArenaDRMirror = ns.ArenaDRMirror or {}

function ns.ArenaDRMirror:GetContainer(arenaID)
    return liveContainers[tonumber(arenaID)]
end

function ns.ArenaDRMirror:RegisterCallback(owner, callback)
    if owner and type(callback) == "function" then
        runtimeRefreshState.arenaDRMirrorCallbacks[owner] = callback
    end
end

function ns.ArenaDRMirror:UnregisterCallback(owner)
    runtimeRefreshState.arenaDRMirrorCallbacks[owner] = nil
end

function ns.ArenaDRMirror:RequestRefresh(forceSourceResync)
    if RequestLiveRuntimeRefresh then
        RequestLiveRuntimeRefresh(forceSourceResync == true)
    end
end

local function EnsureLiveSlot(arenaID, slotIndex)
    local container = GetLiveContainer(arenaID)
    container.slots = container.slots or {}

    if container.slots[slotIndex] then
        return container.slots[slotIndex]
    end

    local slot = CreateDRIconFrame(container, "Live" .. tostring(arenaID) .. "_" .. tostring(slotIndex))
    slot:SetFrameLevel(201)
    slot:Hide()
    slot.ArenaDRNameplatesLiveArenaID = arenaID
    slot.ArenaDRNameplatesLiveTracksImmunity = true
    slot.ArenaDRNameplatesLiveSourceShown = false
    slot.ArenaDRNameplatesLiveHasTexture = false
    slot.ArenaDRNameplatesLiveHasAtlas = false
    slot.ArenaDRNameplatesLiveIsImmune = false
    slot.ArenaDRNameplatesLiveCooldownActive = false
    slot.ArenaDRNameplatesStyleRevision = 0
    ResetLiveSlotWindow(slot)

    -- The mirror owns its own expiry. Blizzard's tray keeps its icon shown when
    -- another addon hides the arena frames, which used to leave a timerless DR
    -- icon parked on the nameplate for the rest of the match.
    slot.Cooldown:HookScript("OnCooldownDone", function()
        if slot.ArenaDRNameplatesLiveCooldownActive ~= true then
            return
        end

        slot.ArenaDRNameplatesLiveCooldownActive = false
        slot.ArenaDRNameplatesLiveWindowEndsAt = nil
        slot.ArenaDRNameplatesLiveWindowExpired = true
        UpdateLiveSlotVisibility(slot.ArenaDRNameplatesLiveArenaID, slot, false, true)
    end)

    container.slots[slotIndex] = slot
    return slot
end

local function EnsureSourceInfo(arenaID)
    local info = sourceInfoByArenaID[arenaID]
    local arenaFrame = _G["CompactArenaFrameMember" .. arenaID]
    local tray = arenaFrame and arenaFrame.SpellDiminishStatusTray
    if info and info.tray == tray and tray then
        return info
    end
    if not tray then
        sourceInfoByArenaID[arenaID] = nil
        return nil
    end

    info = {
        arenaID = arenaID,
        arenaFrame = arenaFrame,
        tray = tray,
        children = info and info.children or {},
    }

    sourceInfoByArenaID[arenaID] = info
    return info
end

local function GetLiveSourceChildren(tray, children)
    children = children or {}
    wipe(children)
    if not tray then
        return children
    end

    for _, child in ipairs({ tray:GetChildren() }) do
        if child then
            table.insert(children, child)
        end
    end

    return children
end

local function SafeGetShownState(frame)
    if not frame or type(frame.IsShown) ~= "function" then
        return nil
    end

    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or IsSecretValue(shown) or type(shown) ~= "boolean" then
        return nil
    end

    return shown
end

local function GetAdapterLayoutAnchor(parent)
    local adapters = ns and ns.NameplateAdapters
    if not adapters or type(adapters.ResolveLayoutAnchor) ~= "function" then
        return nil
    end

    return adapters:ResolveLayoutAnchor(parent, GetStyleSnapshot().anchorContext)
end

local function GetEffectiveContainerAnchor(parent)
    local point = db and db.point or defaults.point
    local relativePoint = db and db.relativePoint or defaults.relativePoint
    local offsetX = tonumber(db and db.offsetX) or defaults.offsetX
    local offsetY = tonumber(db and db.offsetY) or defaults.offsetY
    local iconLayout = GetIconLayout()
    local relativeFrame = GetAdapterLayoutAnchor(parent)
    local baseSize = LIVE_ICON_SIZE * GetDRTrayScale(parent)

    -- Growth only reaches the screen through the edge the tray is anchored from.
    local growthPoint, growthX, growthY = Shared.ResolveGrowthAnchor(
        point,
        iconLayout,
        GetEffectiveIconGrowth(),
        baseSize,
        offsetX,
        offsetY
    )

    return growthPoint, relativePoint, growthX, growthY, relativeFrame
end

local CalculateTrayLayout = Shared.CalculateTrayLayout
local AnchorChildByGrowth = Shared.AnchorChildByGrowth

local function GetVisibleLiveSlots(container)
    local visibleSlots = container and container.visibleSlots or {}
    wipe(visibleSlots)
    if not container or type(container.slots) ~= "table" then
        return visibleSlots
    end
    container.visibleSlots = visibleSlots

    for _, slot in ipairs(container.slots) do
        if slot and slot:IsShown() then
            table.insert(visibleSlots, slot)
        end
    end

    return visibleSlots
end

local function ApplyLiveSlotStyle(slot)
    if not slot then
        return
    end

    ApplyCooldownStyle(slot.Cooldown)

    local timerText = FindCooldownText(slot)
    if timerText then
        ApplyTimerTextStyle(timerText, slot, 14)
    end

    ApplyLiveDRTextStyle(slot, 14)
    slot.ArenaDRNameplatesStyleRevision = styleRevision
end

local function LayoutLiveContainer(arenaID)
    local container = liveContainers[arenaID]
    if not container then
        return 0
    end

    local visibleSlots = GetVisibleLiveSlots(container)
    local childCount = #visibleSlots
    local scaleValue = GetDRTrayScale(container:GetParent())
    local iconSize = LIVE_ICON_SIZE * scaleValue
    local iconSpacing = GetIconPadding() * scaleValue
    local iconLayout = GetIconLayout()
    local layoutWidth, layoutHeight, iconPitch = CalculateTrayLayout(
        childCount,
        iconSize,
        iconSpacing,
        iconLayout
    )
    local growth = GetEffectiveIconGrowth()

    local opacity = tonumber(db and db.opacity) or 1.0
    if container.ArenaDRNameplatesLayoutWidth ~= layoutWidth
        or container.ArenaDRNameplatesLayoutHeight ~= layoutHeight then
        container:SetSize(layoutWidth, layoutHeight)
        container.ArenaDRNameplatesLayoutWidth = layoutWidth
        container.ArenaDRNameplatesLayoutHeight = layoutHeight
    end
    container:SetScale(1)
    container.ArenaDRNameplatesVisualScale = scaleValue
    if container.ArenaDRNameplatesLayoutAlpha ~= opacity then
        container:SetAlpha(opacity)
        container.ArenaDRNameplatesLayoutAlpha = opacity
    end

    for index, slot in ipairs(visibleSlots) do
        if slot.ArenaDRNameplatesStyleRevision ~= styleRevision
            or slot.ArenaDRNameplatesVisualScale ~= scaleValue then
            slot.ArenaDRNameplatesVisualScale = scaleValue
            slot:SetSize(iconSize, iconSize)
            ApplyLiveSlotStyle(slot)
        end
        AnchorChildByGrowth(slot, container, iconLayout, growth, index, childCount, iconPitch)
    end

    if childCount == 0 then
        container:Hide()
    end

    return childCount
end

local function RequestLiveLayout(arenaID)
    if pendingLiveLayouts[arenaID] then
        return
    end

    pendingLiveLayouts[arenaID] = C_Timer.NewTimer(0, function()
        pendingLiveLayouts[arenaID] = nil
        local container = liveContainers[arenaID]
        if container and LayoutLiveContainer(arenaID) > 0 then
            container:Show()
        end
    end)
end

local function ClearLiveSlotCooldown(slot)
    if not slot or not slot.Cooldown or not slot.ArenaDRNameplatesLiveCooldownActive then
        return
    end

    -- Drop the flag before clearing: Clear() can fire OnCooldownDone, and that
    -- must not be mistaken for a window that ran to its end.
    slot.ArenaDRNameplatesLiveCooldownActive = false
    slot.ArenaDRNameplatesLiveWindowEndsAt = nil
    ClearCooldown(slot.Cooldown)
end

-- contentChanged reports that the caller already changed something a consumer
-- mirrors (icon, countdown, immunity) even though the slot stays as visible as
-- it was. Notifying unconditionally here turned a single runtime tick into one
-- full rebuild of every secondary tray per hooked icon.
UpdateLiveSlotVisibility = function(arenaID, slot, deferLayout, contentChanged)
    if not slot then
        return false
    end

    arenaID = arenaID or slot.ArenaDRNameplatesLiveArenaID
    if not arenaID then
        return false
    end

    local hasVisual = slot.ArenaDRNameplatesLiveHasTexture == true
        or slot.ArenaDRNameplatesLiveHasAtlas == true
    local shouldShow = slot.ArenaDRNameplatesLiveSourceShown ~= false
        and hasVisual
        and not IsLiveSlotWindowExpired(slot)

    local currentShown = SafeGetShownState(slot)
    if currentShown == shouldShow then
        if contentChanged then
            runtimeRefreshState.NotifyArenaDRMirrorChanged(arenaID)
        end
        return false
    end

    slot:SetShown(shouldShow)
    runtimeRefreshState.NotifyArenaDRMirrorChanged(arenaID)
    if not deferLayout then
        RequestLiveLayout(arenaID)
    end
    return true
end

-- Nothing else drives the mirror once a window ends while Blizzard's own tray is
-- hidden, so the runtime tick sweeps finished windows off the nameplates.
local function SweepExpiredLiveWindows()
    for _, arenaID in ipairs(ARENA_IDS) do
        local container = liveContainers[arenaID]
        local slots = container and container.slots
        if type(slots) == "table" then
            for _, slot in ipairs(slots) do
                if slot
                    and SafeGetShownState(slot) ~= false
                    and IsLiveSlotWindowExpired(slot) then
                    ClearLiveSlotCooldown(slot)
                    slot.ArenaDRNameplatesLiveWindowExpired = true
                    UpdateLiveSlotVisibility(arenaID, slot)
                end
            end
        end
    end
end

-- A slot can be bound to a source item whose reset window is already running:
-- Blizzard creates its tray icons on demand, so a short crowd control can start
-- and end before the mirror ever sees the frame. Adopting the running window
-- keeps that icon from sitting on the nameplate with no countdown at all.
local function AdoptSourceCooldownState(arenaID, slot, sourceCooldown)
    if not slot or not sourceCooldown then
        return false
    end

    local startedAt, duration = GetPublicSourceCooldownTimes(sourceCooldown)
    if startedAt and duration then
        if startedAt + duration > GetTime() then
            StartLiveSlotCooldown(slot, duration, startedAt)
        else
            ClearLiveSlotCooldown(slot)
        end
        return UpdateLiveSlotVisibility(arenaID, slot, true, true)
    end

    -- In combat the source times are secret. A source cooldown that still
    -- reports itself shown is running, so the mirror falls back to the public
    -- reset window and lets the source expiry cut it short.
    if slot.ArenaDRNameplatesLiveCooldownActive ~= true
        and not IsLiveSlotWindowExpired(slot)
        and SafeGetShownState(sourceCooldown) == true then
        StartLiveSlotCooldown(slot, LIVE_DR_TIMER_DURATION)
        return UpdateLiveSlotVisibility(arenaID, slot, true, true)
    end

    return false
end

local function SetLiveSlotTexture(arenaID, slot, texture, deferLayout)
    if not slot or not slot.Icon or not slot.Icon.SetTexture then
        return false
    end

    local secret = IsSecretValue(texture)
    if not secret and (texture == "" or texture == 0) then
        texture = nil
    end

    local hasTexture = secret or texture ~= nil
    local cachedTexture = slot.ArenaDRNameplatesLiveMirroredTexture
    local unchanged = not secret
        and not IsSecretValue(cachedTexture)
        and cachedTexture == texture
        and slot.ArenaDRNameplatesLiveHasTexture == hasTexture
    if not unchanged then
        slot.Icon:SetTexture(texture)
        if secret then
            slot.ArenaDRNameplatesLiveMirroredTexture = nil
        else
            slot.ArenaDRNameplatesLiveMirroredTexture = texture
        end
        if hasTexture and slot.Icon.SetTexCoord then
            slot.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    slot.ArenaDRNameplatesLiveHasTexture = hasTexture
    if hasTexture then
        slot.ArenaDRNameplatesLiveHasAtlas = false
        slot.ArenaDRNameplatesLiveMirroredAtlas = nil
    end
    return UpdateLiveSlotVisibility(arenaID, slot, deferLayout, not unchanged)
end

local function SetLiveSlotAtlas(arenaID, slot, atlas, deferLayout)
    if not slot or not slot.Icon or not slot.Icon.SetAtlas then
        return false
    end

    local secret = IsSecretValue(atlas)
    if not secret and atlas == "" then
        atlas = nil
    end

    local hasAtlas = secret or atlas ~= nil
    local cachedAtlas = slot.ArenaDRNameplatesLiveMirroredAtlas
    local unchanged = not secret
        and not IsSecretValue(cachedAtlas)
        and cachedAtlas == atlas
        and slot.ArenaDRNameplatesLiveHasAtlas == hasAtlas
    if hasAtlas and not unchanged then
        slot.Icon:SetAtlas(atlas, true)
        if secret then
            slot.ArenaDRNameplatesLiveMirroredAtlas = nil
        else
            slot.ArenaDRNameplatesLiveMirroredAtlas = atlas
        end
        if slot.Icon.SetTexCoord then
            slot.Icon:SetTexCoord(0, 1, 0, 1)
        end
    elseif not hasAtlas then
        slot.ArenaDRNameplatesLiveMirroredAtlas = nil
    end
    slot.ArenaDRNameplatesLiveHasAtlas = hasAtlas
    if hasAtlas then
        slot.ArenaDRNameplatesLiveHasTexture = false
        slot.ArenaDRNameplatesLiveMirroredTexture = nil
    end
    return UpdateLiveSlotVisibility(arenaID, slot, deferLayout, not unchanged)
end

local function SetLiveSlotImmunity(_, slot, isShown)
    if not slot or not slot.ImmunityIndicator then
        return false
    end

    local cachedIsImmune = slot.ArenaDRNameplatesLiveIsImmune
    if not IsSecretValue(isShown)
        and not IsSecretValue(cachedIsImmune)
        and cachedIsImmune == isShown then
        return false
    end

    slot.ArenaDRNameplatesLiveIsImmune = isShown
    if slot.ArenaDRNameplatesStyleRevision ~= styleRevision then
        ApplyLiveSlotStyle(slot)
    else
        ApplyDRVisualStateFromImmune(slot, isShown)
    end
    return true
end

local function GetLiveAnchorParent(arenaID)
    local helper = GetHelper()
    if not helper or type(helper.GetAnchorParentByArenaID) ~= "function" then
        return nil
    end
    return helper:GetAnchorParentByArenaID(arenaID)
end

local function HookLiveSourceItem(arenaID, slotIndex, sourceItem, forceSourceResync)
    if not sourceItem then
        return
    end

    local slot = EnsureLiveSlot(arenaID, slotIndex)
    if not forceSourceResync
        and slot.ArenaDRNameplatesLiveSourceItem == sourceItem
        and slot.ArenaDRNameplatesLiveSourceReady == true then
        return false
    end

    -- Rebinding a slot to a different tray item drops whatever the previous item
    -- left behind, so the new source state is read from scratch below.
    if slot.ArenaDRNameplatesLiveSourceItem ~= sourceItem then
        ClearLiveSlotCooldown(slot)
        ResetLiveSlotWindow(slot)
    end

    slot.ArenaDRNameplatesLiveSourceReady = false
    slot.ArenaDRNameplatesLiveSourceItem = sourceItem
    sourceItem.ArenaDRNameplatesLiveMirrorArenaID = arenaID
    sourceItem.ArenaDRNameplatesLiveMirrorSlot = slot

    local sourceIcon = FindTextureRegion(sourceItem)
    local sourceCooldown = FindCooldownFrame(sourceItem)
    local sourceIndicator = sourceItem.ImmunityIndicator

    local shown = SafeGetShownState(sourceItem)
    if shown ~= nil then
        slot.ArenaDRNameplatesLiveSourceShown = shown
    end

    local mirroredAtlas = false
    if sourceIcon and sourceIcon.GetAtlas and slot.Icon.SetAtlas then
        local okAtlas, atlas = pcall(sourceIcon.GetAtlas, sourceIcon)
        if okAtlas and (IsSecretValue(atlas) or atlas ~= nil) then
            SetLiveSlotAtlas(arenaID, slot, atlas, true)
            mirroredAtlas = true
        end
    end

    if not mirroredAtlas and sourceIcon and sourceIcon.GetTexture then
        local okTexture, texture = pcall(sourceIcon.GetTexture, sourceIcon)
        if okTexture and (IsSecretValue(texture) or texture ~= nil) then
            SetLiveSlotTexture(arenaID, slot, texture, true)
        end
    end

    local indicatorShown = SafeGetShownState(sourceIndicator)
    if indicatorShown ~= nil then
        SetLiveSlotImmunity(arenaID, slot, indicatorShown)
    end

    if not sourceItem.ArenaDRNameplatesLiveMirrorHooked then
        sourceItem.ArenaDRNameplatesLiveMirrorHooked = true

        -- The hook callback's self argument can be a secret table while in
        -- combat. Use the non-secret frame reference captured when the hook
        -- was installed instead of indexing that callback argument.
        hooksecurefunc(sourceItem, "Show", function()
            local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
            local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
            if not hookedSlot or not hookedArenaID
                or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem then
                return
            end

            hookedSlot.ArenaDRNameplatesLiveSourceShown = true
            ClearLiveSlotWindowExpiry(hookedSlot)
            UpdateLiveSlotVisibility(hookedArenaID, hookedSlot)
        end)

        hooksecurefunc(sourceItem, "Hide", function()
            local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
            local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
            if not hookedSlot or not hookedArenaID
                or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem then
                return
            end

            hookedSlot.ArenaDRNameplatesLiveSourceShown = false
            ClearLiveSlotCooldown(hookedSlot)
            ResetLiveSlotWindow(hookedSlot)
            local immunityChanged = SetLiveSlotImmunity(hookedArenaID, hookedSlot, false)
            UpdateLiveSlotVisibility(hookedArenaID, hookedSlot, false, immunityChanged)
        end)

        -- Blizzard reaches for SetShown in places, and a C level SetShown never
        -- runs the Lua Show or Hide hooks above.
        if sourceItem.SetShown then
            hooksecurefunc(sourceItem, "SetShown", function(_, shown)
                local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
                local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
                if not hookedSlot or not hookedArenaID
                    or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem
                    or IsSecretValue(shown) then
                    return
                end

                local immunityChanged = false
                if shown then
                    hookedSlot.ArenaDRNameplatesLiveSourceShown = true
                    ClearLiveSlotWindowExpiry(hookedSlot)
                else
                    hookedSlot.ArenaDRNameplatesLiveSourceShown = false
                    ClearLiveSlotCooldown(hookedSlot)
                    ResetLiveSlotWindow(hookedSlot)
                    immunityChanged = SetLiveSlotImmunity(hookedArenaID, hookedSlot, false)
                end
                UpdateLiveSlotVisibility(hookedArenaID, hookedSlot, false, immunityChanged)
            end)
        end
    end

    if sourceIcon and sourceItem.ArenaDRNameplatesLiveIconHookTarget ~= sourceIcon then
        sourceItem.ArenaDRNameplatesLiveIconHookTarget = sourceIcon

        if sourceIcon.SetTexture then
            hooksecurefunc(sourceIcon, "SetTexture", function(_, texture)
                local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
                local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
                if not hookedSlot or not hookedArenaID
                    or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem
                    or sourceItem.ArenaDRNameplatesLiveIconHookTarget ~= sourceIcon then
                    return
                end

                SetLiveSlotTexture(hookedArenaID, hookedSlot, texture)
            end)
        end

        if sourceIcon.SetAtlas and slot.Icon.SetAtlas then
            hooksecurefunc(sourceIcon, "SetAtlas", function(_, atlas)
                local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
                local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
                if not hookedSlot or not hookedArenaID
                    or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem
                    or sourceItem.ArenaDRNameplatesLiveIconHookTarget ~= sourceIcon then
                    return
                end

                SetLiveSlotAtlas(hookedArenaID, hookedSlot, atlas)
            end)
        end
    end

    if sourceCooldown and sourceItem.ArenaDRNameplatesLiveCooldownHookTarget ~= sourceCooldown then
        sourceItem.ArenaDRNameplatesLiveCooldownHookTarget = sourceCooldown

        if sourceCooldown.SetCooldown then
            hooksecurefunc(sourceCooldown, "SetCooldown", function(_, startTime, duration)
                local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
                local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
                if not hookedSlot or not hookedArenaID or not hookedSlot.Cooldown
                    or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem
                    or sourceItem.ArenaDRNameplatesLiveCooldownHookTarget ~= sourceCooldown then
                    return
                end

                local publicDuration = not IsSecretValue(duration) and tonumber(duration) or nil

                -- Blizzard zeroes the swipe when the crowd control lands and only
                -- sets the reset window when it breaks. Treating that zero as a
                -- window start made the mirror count down during the crowd
                -- control instead of after it.
                if duration == nil or (publicDuration and publicDuration <= 0) then
                    ClearLiveSlotCooldown(hookedSlot)
                    ResetLiveSlotWindow(hookedSlot)
                    UpdateLiveSlotVisibility(hookedArenaID, hookedSlot, false, true)
                    return
                end

                local publicStart = not IsSecretValue(startTime) and tonumber(startTime) or nil
                if publicDuration and publicStart then
                    StartLiveSlotCooldown(hookedSlot, publicDuration, publicStart)
                else
                    StartLiveSlotCooldown(hookedSlot, LIVE_DR_TIMER_DURATION)
                end
                UpdateLiveSlotVisibility(hookedArenaID, hookedSlot, false, true)
            end)
        end

        if sourceCooldown.Clear then
            hooksecurefunc(sourceCooldown, "Clear", function()
                local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
                local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
                if not hookedSlot or not hookedArenaID
                    or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem
                    or sourceItem.ArenaDRNameplatesLiveCooldownHookTarget ~= sourceCooldown then
                    return
                end

                ClearLiveSlotCooldown(hookedSlot)
                ResetLiveSlotWindow(hookedSlot)
                UpdateLiveSlotVisibility(hookedArenaID, hookedSlot, false, true)
            end)
        end

        sourceCooldown:HookScript("OnCooldownDone", function()
            local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
            local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
            if not hookedSlot or not hookedArenaID
                or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem
                or sourceItem.ArenaDRNameplatesLiveCooldownHookTarget ~= sourceCooldown then
                return
            end

            ClearLiveSlotCooldown(hookedSlot)
            hookedSlot.ArenaDRNameplatesLiveWindowExpired = true
            UpdateLiveSlotVisibility(hookedArenaID, hookedSlot, false, true)
        end)

        sourceCooldown:HookScript("OnHide", function()
            local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
            local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
            if not hookedSlot or not hookedArenaID
                or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem
                or sourceItem.ArenaDRNameplatesLiveCooldownHookTarget ~= sourceCooldown then
                return
            end

            -- Other unit frame addons hide Blizzard's arena frames, and that
            -- fires OnHide on every source cooldown while their windows keep
            -- running. Only a cooldown that stopped itself reports its own state
            -- as hidden, so an ancestor hiding must not wipe the countdown.
            if SafeGetShownState(sourceCooldown) ~= false then
                return
            end

            ClearLiveSlotCooldown(hookedSlot)
            UpdateLiveSlotVisibility(hookedArenaID, hookedSlot, false, true)
        end)
    end

    if sourceIndicator and sourceItem.ArenaDRNameplatesLiveIndicatorHookTarget ~= sourceIndicator then
        sourceItem.ArenaDRNameplatesLiveIndicatorHookTarget = sourceIndicator

        if sourceIndicator.SetShown then
            hooksecurefunc(sourceIndicator, "SetShown", function(_, shown)
                local hookedSlot = sourceItem.ArenaDRNameplatesLiveMirrorSlot
                local hookedArenaID = sourceItem.ArenaDRNameplatesLiveMirrorArenaID
                if not hookedSlot or not hookedArenaID
                    or hookedSlot.ArenaDRNameplatesLiveSourceItem ~= sourceItem
                    or sourceItem.ArenaDRNameplatesLiveIndicatorHookTarget ~= sourceIndicator then
                    return
                end

                -- Immunity only paints the icon. Blizzard toggles this indicator
                -- while it sets up a fresh crowd control, and restarting the
                -- countdown here made the timer run during the control and reset
                -- itself mid window.
                local immunityChanged = SetLiveSlotImmunity(hookedArenaID, hookedSlot, shown)
                UpdateLiveSlotVisibility(hookedArenaID, hookedSlot, false, immunityChanged)
            end)
        end
    end

    local visibilityChanged = AdoptSourceCooldownState(arenaID, slot, sourceCooldown)

    slot.ArenaDRNameplatesLiveSourceReady = true
    if UpdateLiveSlotVisibility(arenaID, slot, true) then
        visibilityChanged = true
    end
    return visibilityChanged
end

local function ReconcileLiveContainerAnchor(arenaID, parent, container)
    if not parent or not container then
        return false
    end

    local needsLayout = container.ArenaDRNameplatesStyleRevision ~= styleRevision
    container.ArenaDRNameplatesRuntimeInactive = false
    if container:GetParent() ~= parent then
        container:SetParent(parent)
        container.ArenaDRNameplatesParked = false
        needsLayout = true
    end
    if container.ArenaDRNameplatesVisualScale ~= GetDRTrayScale(parent) then
        needsLayout = true
    end

    local point, relativePoint, offsetX, offsetY, relativeFrame = GetEffectiveContainerAnchor(parent)
    relativeFrame = relativeFrame or parent
    if container.ArenaDRNameplatesAnchorParent ~= parent
        or container.ArenaDRNameplatesAnchorRelativeFrame ~= relativeFrame
        or container.ArenaDRNameplatesAnchorPoint ~= point
        or container.ArenaDRNameplatesAnchorRelativePoint ~= relativePoint
        or container.ArenaDRNameplatesAnchorX ~= offsetX
        or container.ArenaDRNameplatesAnchorY ~= offsetY then
        container:ClearAllPoints()
        container:SetPoint(point, relativeFrame, relativePoint, offsetX, offsetY)
        container.ArenaDRNameplatesAnchorParent = parent
        container.ArenaDRNameplatesAnchorRelativeFrame = relativeFrame
        container.ArenaDRNameplatesAnchorPoint = point
        container.ArenaDRNameplatesAnchorRelativePoint = relativePoint
        container.ArenaDRNameplatesAnchorX = offsetX
        container.ArenaDRNameplatesAnchorY = offsetY
        needsLayout = true
    end

    return needsLayout
end

local function AnchorLiveTray(arenaID, parent, forceSourceResync)
    local info = EnsureSourceInfo(arenaID)
    local container = GetLiveContainer(arenaID)
    local pendingLayout = pendingLiveLayouts[arenaID]
    if pendingLayout then
        pendingLayout:Cancel()
        pendingLiveLayouts[arenaID] = nil
    end

    if not info or not info.tray then
        container:Hide()
        return
    end
    container.ArenaDRNameplatesRuntimeInactive = false

    local needsLayout = false
    if parent then
        needsLayout = ReconcileLiveContainerAnchor(arenaID, parent, container)
    else
        -- Target/Focus can still resolve an arena opponent while its nameplate
        -- is absent. Keep the source hooks alive offscreen so secondary mirrors
        -- continue to receive Blizzard's protected DR state.
        ParkFrameOffscreen(container)
    end

    local sourceChildren = GetLiveSourceChildren(info.tray, info.children)
    if info.childCount ~= #sourceChildren then
        info.childCount = #sourceChildren
        needsLayout = true
    end
    for slotIndex, sourceItem in ipairs(sourceChildren) do
        if HookLiveSourceItem(arenaID, slotIndex, sourceItem, forceSourceResync) then
            needsLayout = true
        end
    end

    if type(container.slots) == "table" then
        for slotIndex = #sourceChildren + 1, #container.slots do
            local slot = container.slots[slotIndex]
            if slot then
                slot.ArenaDRNameplatesLiveSourceShown = false
                slot.ArenaDRNameplatesLiveSourceItem = nil
                slot.ArenaDRNameplatesLiveSourceReady = false
                ClearLiveSlotCooldown(slot)
                ResetLiveSlotWindow(slot)
                local immunityChanged = SetLiveSlotImmunity(arenaID, slot, false)
                if UpdateLiveSlotVisibility(arenaID, slot, true, immunityChanged) then
                    needsLayout = true
                end
            end
        end
    end

    if needsLayout and parent then
        container.ArenaDRNameplatesStyleRevision = styleRevision
        if LayoutLiveContainer(arenaID) > 0 then
            container:Show()
        end
    end
end

local function RestoreAllLiveTrays()
    for _, arenaID in ipairs(ARENA_IDS) do
        local pendingLayout = pendingLiveLayouts[arenaID]
        if pendingLayout then
            pendingLayout:Cancel()
            pendingLiveLayouts[arenaID] = nil
        end
        local container = liveContainers[arenaID]
        -- A container that was already parked has nothing new to report, and
        -- announcing it anyway rebuilt every secondary tray on each runtime
        -- tick spent outside an arena.
        if container and not container.ArenaDRNameplatesRuntimeInactive then
            container.ArenaDRNameplatesRuntimeInactive = true
            if type(container.slots) == "table" then
                for _, slot in ipairs(container.slots) do
                    if slot then
                        slot.ArenaDRNameplatesLiveSourceItem = nil
                    end
                end
            end
            if SafeGetShownState(container) ~= false then
                container:Hide()
            end
            runtimeRefreshState.NotifyArenaDRMirrorChanged(arenaID)
        end
    end
end

local function RefreshLiveTrays(parents, forceSourceResync, inArena)
    local metricStartedAt = Performance and Performance.active and Performance:Begin()
    if not db or not db.enabled or not inArena then
        RestoreAllLiveTrays()
        if metricStartedAt then Performance:Finish("runtime.dr", metricStartedAt) end
        return
    end

    for _, arenaID in ipairs(ARENA_IDS) do
        local parent = parents ~= nil and parents[arenaID] or nil
        if parents == nil then
            parent = GetLiveAnchorParent(arenaID)
        end
        AnchorLiveTray(arenaID, parent, forceSourceResync)
    end
    if metricStartedAt then Performance:Finish("runtime.dr", metricStartedAt) end
end

local TRINKET_ALLIANCE_ICON = 133452
local TRINKET_HORDE_ICON = 133453

local function GetArenaMember(arenaID)
    return _G["CompactArenaFrameMember" .. tostring(arenaID)]
end

local function IsArenaMatchEngaged(inArena)
    if inArena == nil then
        inArena = IsInArena()
    end
    if not inArena then
        return false
    end

    local ok, state = pcall(C_PvP.GetActiveMatchState)
    if ok and type(state) == "number" then
        return state == Enum.PvPMatchState.Engaged
    end

    return true
end

local function GetTrinketSourceFrame(arenaID)
    local arenaFrame = GetArenaMember(arenaID)
    if not arenaFrame then
        return nil
    end

    return arenaFrame.CcRemoverFrame
end

local function GetUnitTrinketFallbackTexture(unit)
    local faction = UnitFactionGroup(unit)
    if faction == "Alliance" then
        return TRINKET_ALLIANCE_ICON
    end

    return TRINKET_HORDE_ICON
end

local function EnsureTrinketBorder(frame)
    if not frame then
        return nil
    end

    local borderStyle = GetTrinketBorderStyle()
    if borderStyle == "NONE" then
        if frame.ArenaDRNameplatesTrinketBorderSegments then
            for _, segment in ipairs(frame.ArenaDRNameplatesTrinketBorderSegments) do
                segment:Hide()
            end
        end
        if frame.ArenaDRNameplatesTrinketClassicBorder then
            frame.ArenaDRNameplatesTrinketClassicBorder:Hide()
        end
        return nil
    end

    local r, g, b = GetTrinketBorderColorRGB()
    local borderParent = EnsureVisualOverlay(frame) or frame
    local visualScale = GetFrameVisualScale(frame)
    if borderStyle == "CLASSIC" then
        if frame.ArenaDRNameplatesTrinketBorderSegments then
            for _, segment in ipairs(frame.ArenaDRNameplatesTrinketBorderSegments) do
                segment:Hide()
            end
        end

        if not frame.ArenaDRNameplatesTrinketClassicBorder then
            local border = borderParent:CreateTexture(nil, "OVERLAY")
            border:SetTexture(CLASSIC_BORDER_TEXTURE)
            border:SetTexCoord(unpack(CLASSIC_BORDER_TEX_COORDS))
            frame.ArenaDRNameplatesTrinketClassicBorder = border
        end

        local border = frame.ArenaDRNameplatesTrinketClassicBorder
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", borderParent, "TOPLEFT", -visualScale, visualScale)
        border:SetPoint(
            "BOTTOMRIGHT",
            borderParent,
            "BOTTOMRIGHT",
            visualScale,
            -visualScale
        )
        border:SetVertexColor(r, g, b, 1)
        border:Show()
        return border
    end

    if frame.ArenaDRNameplatesTrinketClassicBorder then
        frame.ArenaDRNameplatesTrinketClassicBorder:Hide()
    end

    if not frame.ArenaDRNameplatesTrinketBorderSegments then
        local function CreateSegment()
            local segment = borderParent:CreateTexture(nil, "OVERLAY")
            segment:SetTexture("Interface\\Buttons\\WHITE8X8")
            return segment
        end

        frame.ArenaDRNameplatesTrinketBorderSegments = {
            CreateSegment(),
            CreateSegment(),
            CreateSegment(),
            CreateSegment(),
        }
    end

    local borderSegments = frame.ArenaDRNameplatesTrinketBorderSegments
    local borderWidth = GetTrinketBorderWidth() * visualScale
    local extent = borderWidth / 2
    local top = borderSegments[1]
    local bottom = borderSegments[2]
    local left = borderSegments[3]
    local right = borderSegments[4]

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", borderParent, "TOPLEFT", -extent, extent)
    top:SetPoint("TOPRIGHT", borderParent, "TOPRIGHT", extent, extent)
    top:SetHeight(borderWidth)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", borderParent, "BOTTOMLEFT", -extent, -extent)
    bottom:SetPoint("BOTTOMRIGHT", borderParent, "BOTTOMRIGHT", extent, -extent)
    bottom:SetHeight(borderWidth)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", borderParent, "TOPLEFT", -extent, extent)
    left:SetPoint("BOTTOMLEFT", borderParent, "BOTTOMLEFT", -extent, -extent)
    left:SetWidth(borderWidth)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", borderParent, "TOPRIGHT", extent, extent)
    right:SetPoint("BOTTOMRIGHT", borderParent, "BOTTOMRIGHT", extent, -extent)
    right:SetWidth(borderWidth)

    for _, segment in ipairs(borderSegments) do
        segment:SetVertexColor(r, g, b, 1)
        segment:Show()
    end

    return borderSegments
end

local function CreateTrinketIconFrame(parent, explicitID)
    local frame = CreateFrame("Frame", NextFrameName("Core", "TrinketIcon", explicitID), parent)
    frame:SetSize(TRINKET_BASE_ICON_SIZE, TRINKET_BASE_ICON_SIZE)
    frame:EnableMouse(false)
    frame.hasActiveCooldown = false
    frame.hasSourceTexture = false
    frame.hasFallbackTexture = false

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0, 0, 0, 0.45)
    frame.Background = background

    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(frame)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.Icon = texture

    local cooldown = CreateFrame(
        "Cooldown",
        NextFrameName("Core", "TrinketCooldown", explicitID),
        frame,
        "CooldownFrameTemplate"
    )
    cooldown:SetAllPoints(frame)
    frame.Cooldown = cooldown

    EnsureTrinketBorder(frame)
    return frame
end

local function ClearLiveTrinketMirrorCooldown(frame)
    if not frame or not frame.hasActiveCooldown then
        return
    end

    frame.hasActiveCooldown = false
    ClearCooldown(frame.Cooldown)
end

local function UpdateLiveTrinketMirrorVisibility(frame, inArena, matchEngaged, trinketEnabled)
    if not frame then
        return
    end

    if inArena == nil then
        inArena = IsInArena()
    end
    if matchEngaged == nil then
        matchEngaged = IsArenaMatchEngaged(inArena)
    end
    if trinketEnabled == nil then
        trinketEnabled = IsTrinketEnabled()
    end

    local hasTexture = frame.hasSourceTexture == true or frame.hasFallbackTexture == true
    local shouldShow = trinketEnabled
        and inArena
        and matchEngaged
        and hasTexture
        and (GetTrinketVisibilityMode() == "ALWAYS" or frame.hasActiveCooldown == true)

    if SafeGetShownState(frame) ~= shouldShow then
        frame:SetShown(shouldShow)
    end
end

local function ApplyLiveTrinketFallback(frame, arenaUnit)
    if not frame then
        return
    end

    frame.fallbackUnit = arenaUnit
    if frame.hasSourceTexture == true then
        frame.hasFallbackTexture = false
        return
    end

    local fallbackTexture = GetUnitTrinketFallbackTexture(arenaUnit)
    if frame.ArenaDRNameplatesMirroredTexture == fallbackTexture
        and frame.hasFallbackTexture == (fallbackTexture ~= nil) then
        return
    end
    if fallbackTexture then
        frame.Icon:SetTexture(fallbackTexture)
        frame.ArenaDRNameplatesMirroredTexture = fallbackTexture
        frame.hasFallbackTexture = true
    else
        frame.Icon:SetTexture(nil)
        frame.ArenaDRNameplatesMirroredTexture = nil
        frame.hasFallbackTexture = false
    end
end

local function SetLiveTrinketMirrorTexture(frame, texture, inArena, matchEngaged, trinketEnabled)
    if not frame then
        return
    end

    if IsSecretValue(texture) then
        frame.Icon:SetTexture(texture)
        frame.ArenaDRNameplatesMirroredTexture = nil
        frame.hasSourceTexture = true
        frame.hasFallbackTexture = false
        UpdateLiveTrinketMirrorVisibility(frame, inArena, matchEngaged, trinketEnabled)
        return
    end

    if texture == nil or texture == "" or texture == 0 then
        frame.hasSourceTexture = false
        ApplyLiveTrinketFallback(frame, frame.fallbackUnit)
        UpdateLiveTrinketMirrorVisibility(frame, inArena, matchEngaged, trinketEnabled)
        return
    end

    if frame.ArenaDRNameplatesMirroredTexture ~= texture then
        frame.Icon:SetTexture(texture)
        frame.ArenaDRNameplatesMirroredTexture = texture
    end
    frame.hasSourceTexture = true
    frame.hasFallbackTexture = false
    UpdateLiveTrinketMirrorVisibility(frame, inArena, matchEngaged, trinketEnabled)
end

local function ApplyLiveTrinketCooldown(
    frame,
    arenaUnit,
    startTime,
    duration,
    inArena,
    matchEngaged,
    trinketEnabled
)
    if not frame or not frame.Cooldown then
        return
    end

    local usedDurationObject = false
    local okObj, durationObject = pcall(C_PvP.GetArenaCrowdControlDuration, arenaUnit)
    if okObj and durationObject then
        local okSet = pcall(function()
            frame.Cooldown:SetCooldownFromDurationObject(durationObject)
        end)
        usedDurationObject = okSet == true
    end

    local hasStartTime = IsSecretValue(startTime) or startTime ~= nil
    local hasDuration = IsSecretValue(duration) or duration ~= nil
    if not usedDurationObject and hasStartTime and hasDuration then
        pcall(function()
            frame.Cooldown:SetCooldown(startTime, duration)
        end)
    end

    if frame.Cooldown.SetReverse then
        frame.Cooldown:SetReverse(false)
    end

    frame.hasActiveCooldown = true
    UpdateLiveTrinketMirrorVisibility(frame, inArena, matchEngaged, trinketEnabled)
end

local function HookLiveTrinketSource(
    arenaID,
    frame,
    sourceFrame,
    forceSourceResync,
    inArena,
    matchEngaged,
    trinketEnabled
)
    if not frame or not sourceFrame then
        return
    end

    local arenaUnit = "arena" .. tostring(arenaID)
    if not forceSourceResync
        and frame.sourceFrame == sourceFrame
        and frame.sourceReady == true then
        return
    end

    frame.sourceReady = false
    frame.sourceFrame = sourceFrame
    local sourceIcon = FindTextureRegion(sourceFrame)
    local sourceCooldown = FindCooldownFrame(sourceFrame)

    if sourceIcon and sourceIcon.GetTexture then
        local ok, texture = pcall(sourceIcon.GetTexture, sourceIcon)
        if ok then
            SetLiveTrinketMirrorTexture(frame, texture, inArena, matchEngaged, trinketEnabled)
        end
    end

    if sourceIcon and frame.sourceIconHookTarget ~= sourceIcon then
        frame.sourceIconHookTarget = sourceIcon

        if sourceIcon.SetTexture then
            hooksecurefunc(sourceIcon, "SetTexture", function(_, texture)
                if frame.sourceFrame ~= sourceFrame or frame.sourceIconHookTarget ~= sourceIcon then
                    return
                end
                SetLiveTrinketMirrorTexture(frame, texture)
            end)
        end
    end

    if sourceCooldown and frame.sourceCooldownHookTarget ~= sourceCooldown then
        frame.sourceCooldownHookTarget = sourceCooldown

        if sourceCooldown.SetCooldown then
            hooksecurefunc(sourceCooldown, "SetCooldown", function(_, startTime, duration)
                if frame.sourceFrame ~= sourceFrame or frame.sourceCooldownHookTarget ~= sourceCooldown then
                    return
                end
                local currentlyInArena = IsInArena()
                if not IsTrinketEnabled()
                    or not currentlyInArena
                    or not IsArenaMatchEngaged(currentlyInArena) then
                    ClearLiveTrinketMirrorCooldown(frame)
                    UpdateLiveTrinketMirrorVisibility(frame)
                    return
                end

                local durationIsSecret = IsSecretValue(duration)
                if not durationIsSecret and (duration == nil or duration <= 0) then
                    ClearLiveTrinketMirrorCooldown(frame)
                    UpdateLiveTrinketMirrorVisibility(frame)
                    return
                end

                ApplyLiveTrinketCooldown(frame, arenaUnit, startTime, duration)
            end)
        end

        sourceCooldown:HookScript("OnCooldownDone", function()
            if frame.sourceFrame ~= sourceFrame or frame.sourceCooldownHookTarget ~= sourceCooldown then
                return
            end
            ClearLiveTrinketMirrorCooldown(frame)
            UpdateLiveTrinketMirrorVisibility(frame)
        end)
    end
    frame.sourceReady = true
end

local function ApplyTrinketFrameStyle(frame)
    if not frame then
        return
    end

    local size = GetTrinketSize()
    local visualScale = size / TRINKET_BASE_ICON_SIZE
    frame:SetScale(1)
    frame.ArenaDRNameplatesVisualScale = visualScale
    frame:SetSize(size, size)
    frame:SetAlpha(GetTrinketOpacity())

    ApplyCooldownStyle(frame.Cooldown)
    if frame.Cooldown and frame.Cooldown.SetReverse then
        frame.Cooldown:SetReverse(false)
    end

    local timerText = FindCooldownText(frame)
    if timerText then
        ApplyTimerTextStyle(
            timerText,
            frame,
            GetTrinketTimerBaseFontSize(),
            visualScale
        )
    end

    EnsureTrinketBorder(frame)
    frame.ArenaDRNameplatesStyleRevision = styleRevision
end

local function GetLiveTrinketMirror(arenaID)
    if trinketMirrors[arenaID] then
        return trinketMirrors[arenaID]
    end

    local frame = CreateTrinketIconFrame(UIParent, "Live" .. tostring(arenaID))
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(220)
    IgnoreParentAlpha(frame)
    frame:Hide()
    trinketMirrors[arenaID] = frame
    return frame
end

local function HideLiveTrinketMirror(arenaID)
    local frame = trinketMirrors[arenaID]
    if not frame then
        return
    end

    frame.sourceFrame = nil
    frame.sourceReady = false
    if frame.ArenaDRNameplatesHiddenReset then
        return
    end

    frame.ArenaDRNameplatesHiddenReset = true
    frame.hasSourceTexture = false
    frame.hasFallbackTexture = false
    ClearLiveTrinketMirrorCooldown(frame)
    frame.Icon:SetTexture(nil)
    frame.ArenaDRNameplatesMirroredTexture = nil
    frame:Hide()
end

local function HideAllLiveTrinketMirrors()
    for _, arenaID in ipairs(ARENA_IDS) do
        HideLiveTrinketMirror(arenaID)
    end
end

local function UpdateLiveTrinketMirror(
    arenaID,
    parent,
    forceSourceResync,
    inArena,
    matchEngaged,
    trinketEnabled
)
    if not parent then
        local existing = trinketMirrors[arenaID]
        if existing then
            ParkFrameOffscreen(existing)
        end
        return
    end

    local frame = GetLiveTrinketMirror(arenaID)
    frame.ArenaDRNameplatesHiddenReset = false
    if frame:GetParent() ~= parent then
        frame:SetParent(parent)
        frame.ArenaDRNameplatesParked = false
    end

    if frame.ArenaDRNameplatesStyleRevision ~= styleRevision then
        ApplyTrinketFrameStyle(frame)
    end

    do
        local point, relativePoint, offsetX, offsetY = GetEffectiveTrinketAnchor()
        if frame.ArenaDRNameplatesAnchorParent ~= parent
            or frame.ArenaDRNameplatesAnchorPoint ~= point
            or frame.ArenaDRNameplatesAnchorRelativePoint ~= relativePoint
            or frame.ArenaDRNameplatesAnchorX ~= offsetX
            or frame.ArenaDRNameplatesAnchorY ~= offsetY then
            frame:ClearAllPoints()
            frame:SetPoint(point, parent, relativePoint, offsetX, offsetY)
            frame.ArenaDRNameplatesAnchorParent = parent
            frame.ArenaDRNameplatesAnchorPoint = point
            frame.ArenaDRNameplatesAnchorRelativePoint = relativePoint
            frame.ArenaDRNameplatesAnchorX = offsetX
            frame.ArenaDRNameplatesAnchorY = offsetY
        end
    end

    ApplyLiveTrinketFallback(frame, "arena" .. tostring(arenaID))

    local sourceFrame = GetTrinketSourceFrame(arenaID)
    if sourceFrame then
        HookLiveTrinketSource(
            arenaID,
            frame,
            sourceFrame,
            forceSourceResync,
            inArena,
            matchEngaged,
            trinketEnabled
        )
    else
        frame.sourceFrame = nil
        frame.sourceReady = false
        ClearLiveTrinketMirrorCooldown(frame)
    end

    if not matchEngaged then
        ClearLiveTrinketMirrorCooldown(frame)
    end

    UpdateLiveTrinketMirrorVisibility(frame, inArena, matchEngaged, trinketEnabled)
end

local function RefreshLiveTrinketMirrors(
    parents,
    forceSourceResync,
    inArena,
    matchEngaged,
    trinketEnabled
)
    local metricStartedAt = Performance and Performance.active and Performance:Begin()
    if not db or not db.enabled or not inArena or not trinketEnabled then
        HideAllLiveTrinketMirrors()
        if metricStartedAt then Performance:Finish("runtime.trinket", metricStartedAt) end
        return
    end

    for _, arenaID in ipairs(ARENA_IDS) do
        local parent = parents ~= nil and parents[arenaID] or nil
        if parents == nil then
            parent = GetLiveAnchorParent(arenaID)
        end
        UpdateLiveTrinketMirror(
            arenaID,
            parent,
            forceSourceResync,
            inArena,
            matchEngaged,
            trinketEnabled
        )
    end
    if metricStartedAt then Performance:Finish("runtime.trinket", metricStartedAt) end
end

local function GetNameplateAnchorParentForTarget()
    local helper = GetHelper()
    if helper and type(helper.GetAnchorParentByUnit) == "function" then
        local parent = helper:GetAnchorParentByUnit("target")
        if parent then
            return parent
        end
    end

    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not plate then
        return nil
    end

    local unitFrame = nil
    if type(plate.UnitFrame) == "table" then
        unitFrame = plate.UnitFrame
    elseif type(plate.unitFrame) == "table" then
        unitFrame = plate.unitFrame
    end

    if unitFrame then
        for _, key in ipairs({
            "HealthBarsContainer",
            "healthBarsContainer",
            "healthBar",
            "HealthBar",
        }) do
            if type(unitFrame[key]) == "table" then
                return unitFrame[key]
            end
        end

        return unitFrame
    end

    return plate
end

local function CreateTestIcon(parent)
    return CreateDRIconFrame(parent)
end

local function GetVisiblePreviewNameplates()
    local helper = GetHelper()
    if helper and type(helper.GetVisibleEnemyNameplates) == "function" then
        local entries = helper:GetVisibleEnemyNameplates()
        if type(entries) == "table" and #entries > 0 then
            return entries
        end
    end

    if IsEnemyTarget() then
        local parent = GetNameplateAnchorParentForTarget()
        if parent then
            local guid = UnitGUID("target")
            if IsSecretValue(guid) or type(guid) ~= "string" or guid == "" then
                guid = nil
            end

            return {
                {
                    token = "target",
                    guid = guid,
                    parent = parent,
                },
            }
        end
    end

    return {}
end

local function EnsureTestTray(previewKey)
    previewKey = tostring(previewKey or "Default")

    local tray = testTrays[previewKey]
    if tray then
        return tray
    end

    tray = CreateFrame("Frame", NextFrameName("Core", "TestTray", previewKey), UIParent)
    tray:SetSize(1, 1)
    tray:SetFrameStrata("HIGH")
    tray:SetFrameLevel(250)
    IgnoreParentAlpha(tray)
    tray.previewIcons = {}
    tray.previewKey = previewKey
    tray:Hide()
    testTrays[previewKey] = tray
    return tray
end

local function EnsureTestTrinketIcon()
    if testTrinketIcon then
        return testTrinketIcon
    end

    testTrinketIcon = CreateTrinketIconFrame(UIParent, "Test")
    testTrinketIcon:SetFrameStrata("HIGH")
    testTrinketIcon:SetFrameLevel(260)
    IgnoreParentAlpha(testTrinketIcon)
    testTrinketIcon:Hide()
    return testTrinketIcon
end

local function ClearPreviewConfigs()
    for key in pairs(testConfigsByKey) do
        testConfigsByKey[key] = nil
    end
end

local function CreatePreviewSpellSet()
    local pool = {}
    for index, spellData in ipairs(TEST_SPELLS) do
        pool[index] = spellData
    end

    for index = #pool, 2, -1 do
        local swapIndex = math.random(index)
        pool[index], pool[swapIndex] = pool[swapIndex], pool[index]
    end

    local count = math.random(PREVIEW_MIN_DR_COUNT, math.min(PREVIEW_MAX_DR_COUNT, #pool))
    local spells = {}
    for index = 1, count do
        local source = pool[index]
        local duration = math.random(PREVIEW_MIN_DURATION, PREVIEW_MAX_DURATION)
        local spellInfo = C_Spell.GetSpellInfo(source.spellID)
        spells[index] = {
            spellID = source.spellID,
            duration = duration,
            isImmune = source.isImmune == true,
            previewOffset = math.random(0, math.max(duration - 2, 0)),
            iconTexture = spellInfo
                and (spellInfo.iconID or spellInfo.originalIconID)
                or "Interface\\Icons\\INV_Misc_QuestionMark",
        }
    end

    return spells
end

local function GetPreviewTrayKey(entry, index)
    if type(entry) == "table" then
        if type(entry.token) == "string" and entry.token ~= "" and not IsSecretValue(entry.token) then
            return entry.token
        end
        if type(entry.guid) == "string" and entry.guid ~= "" and not IsSecretValue(entry.guid) then
            return entry.guid
        end
    end

    return "Preview" .. tostring(index or 0)
end

local function GetPreviewConfigKey(entry, index)
    if type(entry) == "table" then
        if type(entry.guid) == "string" and entry.guid ~= "" and not IsSecretValue(entry.guid) then
            return entry.guid
        end
        if type(entry.token) == "string" and entry.token ~= "" and not IsSecretValue(entry.token) then
            return entry.token
        end
    end

    return "Preview" .. tostring(index or 0)
end

local function GetPreviewConfig(previewKey)
    previewKey = tostring(previewKey or "Default")
    local config = testConfigsByKey[previewKey]
    if config then
        return config
    end

    config = {
        spells = CreatePreviewSpellSet(),
    }
    testConfigsByKey[previewKey] = config
    return config
end

local function ResetPreviewIconTimerCache(icon)
    if not icon then
        return
    end

    icon.ArenaDRPreviewCooldownCycle = nil
    icon.ArenaDRPreviewCooldownDuration = nil
    icon.ArenaDRPreviewCooldownOffset = nil
    icon.ArenaDRPreviewShowSwipe = nil
    icon.ArenaDRPreviewShowSwipeEdge = nil
end

local function ResetPreviewTimerCache()
    for _, tray in pairs(testTrays) do
        if tray and type(tray.previewIcons) == "table" then
            for _, icon in ipairs(tray.previewIcons) do
                ResetPreviewIconTimerCache(icon)
            end
        end
    end
end

local function HideAllTestTrays()
    for _, tray in pairs(testTrays) do
        if tray then
            tray:Hide()
        end
    end
end

local function ApplyPreviewCooldown(icon, spellData)
    if not icon or not icon.Cooldown or not icon.Cooldown.SetCooldown then
        return
    end

    local duration = math.max(1, tonumber(spellData and spellData.duration) or 18)
    if not testModeStartedAt then
        ClearCooldown(icon.Cooldown)
        return
    end

    local now = GetTime()
    local previewOffset = ClampNumber(spellData and spellData.previewOffset, 0, duration, 0)
    local elapsed = math.max(0, now - testModeStartedAt + previewOffset)
    local cycle = math.floor(elapsed / duration)
    local showSwipe = IsTimerSwipeEnabled()
    local showSwipeEdge = showSwipe and IsTimerSwipeEdgeEnabled()

    if icon.ArenaDRPreviewCooldownCycle == cycle
        and icon.ArenaDRPreviewCooldownDuration == duration
        and icon.ArenaDRPreviewCooldownOffset == previewOffset
        and icon.ArenaDRPreviewShowSwipe == showSwipe
        and icon.ArenaDRPreviewShowSwipeEdge == showSwipeEdge then
        return
    end

    local cycleStart = testModeStartedAt - previewOffset + (cycle * duration)
    icon.Cooldown:SetCooldown(cycleStart, duration)
    icon.ArenaDRPreviewCooldownCycle = cycle
    icon.ArenaDRPreviewCooldownDuration = duration
    icon.ArenaDRPreviewCooldownOffset = previewOffset
    icon.ArenaDRPreviewShowSwipe = showSwipe
    icon.ArenaDRPreviewShowSwipeEdge = showSwipeEdge
end

local function ApplyTestTrayLayout(tray, parent, spells)
    if not tray then
        return 1, 1
    end

    spells = type(spells) == "table" and spells or TEST_SPELLS

    local scaleValue = GetDRTrayScale(parent or tray:GetParent())
    local iconSize = LIVE_ICON_SIZE * scaleValue
    local spacing = GetIconPadding() * scaleValue
    local iconCount = #spells
    local iconLayout = GetIconLayout()
    local layoutWidth, layoutHeight, iconPitch = CalculateTrayLayout(
        iconCount,
        iconSize,
        spacing,
        iconLayout
    )
    local growth = GetEffectiveIconGrowth()

    tray:SetScale(1)
    tray.ArenaDRNameplatesVisualScale = scaleValue
    tray:SetSize(layoutWidth, layoutHeight)
    tray:SetAlpha(tonumber(db.opacity) or 1.0)

    tray.previewIcons = tray.previewIcons or {}
    for index, spellData in ipairs(spells) do
        local icon = tray.previewIcons[index] or CreateTestIcon(tray)
        tray.previewIcons[index] = icon
        icon:Show()
        icon:SetScale(1)
        icon.ArenaDRNameplatesVisualScale = scaleValue
        icon:SetSize(iconSize, iconSize)

        icon.Icon:SetTexture(
            spellData.iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark"
        )

        AnchorChildByGrowth(icon, tray, iconLayout, growth, index, iconCount, iconPitch)
        ApplyCooldownStyle(icon.Cooldown)
        ApplyPreviewCooldown(icon, spellData)

        SetDRBorderColor(icon, spellData.isImmune == true)

        if icon.ImmunityIndicator then
            if spellData.isImmune == true then
                icon.ImmunityIndicator:Show()
            else
                icon.ImmunityIndicator:Hide()
            end
            SetImmunityIndicatorAlpha(icon)
        end

        local timerText = FindCooldownText(icon)
        if timerText then
            ApplyTimerTextStyle(timerText, icon, 14)
        end

        ApplyDRTextStyle(icon, 14, spellData.isImmune == true)
    end

    for index = iconCount + 1, #tray.previewIcons do
        local icon = tray.previewIcons[index]
        if icon then
            ResetPreviewIconTimerCache(icon)
            icon:Hide()
        end
    end

    return layoutWidth, layoutHeight
end

local function RefreshTestTrays()
    if not testMode then
        HideAllTestTrays()
        return
    end

    local activeKeys = {}
    local entries = GetVisiblePreviewNameplates()
    for index, entry in ipairs(entries) do
        local parent = type(entry) == "table" and entry.parent or nil
        if parent then
            local trayKey = GetPreviewTrayKey(entry, index)
            local configKey = GetPreviewConfigKey(entry, index)
            activeKeys[trayKey] = true

            local tray = EnsureTestTray(trayKey)
            local parentChanged = tray:GetParent() ~= parent
            if parentChanged then
                tray:SetParent(parent)
            end

            local config = GetPreviewConfig(configKey)
            local scaleValue = GetDRTrayScale(parent)
            local needsLayout = parentChanged
                or tray.previewConfig ~= config
                or tray.ArenaDRNameplatesStyleRevision ~= styleRevision
                or tray.ArenaDRNameplatesVisualScale ~= scaleValue
            if needsLayout then
                ApplyTestTrayLayout(tray, parent, config.spells)
                tray:ClearAllPoints()
                local point, relativePoint, offsetX, offsetY, relativeFrame = GetEffectiveContainerAnchor(parent)
                tray:SetPoint(point, relativeFrame or parent, relativePoint, offsetX, offsetY)
                tray:SetFrameStrata("HIGH")
                tray:SetFrameLevel(210)
                tray.previewConfig = config
                tray.ArenaDRNameplatesStyleRevision = styleRevision
            end
            tray:Show()
        end
    end

    for trayKey, tray in pairs(testTrays) do
        if tray and not activeKeys[trayKey] then
            tray:Hide()
        end
    end
end

local function RefreshTestTrinket()
    local frame = EnsureTestTrinketIcon()

    if not testMode or not IsTrinketEnabled() or not IsEnemyTarget() then
        frame.previewCooldownCycle = nil
        frame.previewCooldownDuration = nil
        ClearCooldown(frame.Cooldown)
        frame:Hide()
        return
    end

    local parent = GetNameplateAnchorParentForTarget()
    if not parent then
        frame:Hide()
        return
    end

    if frame:GetParent() ~= parent then
        frame:SetParent(parent)
    end

    if frame.ArenaDRNameplatesStyleRevision ~= styleRevision then
        ApplyTrinketFrameStyle(frame)
    end

    local point, relativePoint, offsetX, offsetY = GetEffectiveTrinketAnchor()
    if frame.ArenaDRNameplatesAnchorParent ~= parent
        or frame.ArenaDRNameplatesAnchorPoint ~= point
        or frame.ArenaDRNameplatesAnchorRelativePoint ~= relativePoint
        or frame.ArenaDRNameplatesAnchorX ~= offsetX
        or frame.ArenaDRNameplatesAnchorY ~= offsetY then
        frame:ClearAllPoints()
        frame:SetPoint(point, parent, relativePoint, offsetX, offsetY)
        frame.ArenaDRNameplatesAnchorParent = parent
        frame.ArenaDRNameplatesAnchorPoint = point
        frame.ArenaDRNameplatesAnchorRelativePoint = relativePoint
        frame.ArenaDRNameplatesAnchorX = offsetX
        frame.ArenaDRNameplatesAnchorY = offsetY
    end

    local texture = GetUnitTrinketFallbackTexture("target")
    if frame.lastTexture ~= texture then
        frame.Icon:SetTexture(texture)
        frame.lastTexture = texture
    end

    frame.previewSpellData = frame.previewSpellData or { duration = 30 }
    ApplyPreviewCooldown(frame, frame.previewSpellData)
    if frame.Cooldown and frame.Cooldown.SetReverse then
        frame.Cooldown:SetReverse(false)
    end

    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(260)
    frame:Show()
end

runtimeRefreshState.RefreshPreview = function()
    local metricStartedAt = Performance and Performance.active and Performance:Begin()
    RefreshTestTrays()
    RefreshTestTrinket()
    if metricStartedAt then Performance:Finish("preview.reconcile", metricStartedAt) end
end

runtimeRefreshState.UpdatePreviewCooldowns = function()
    for _, tray in pairs(testTrays) do
        if tray and tray:IsShown() and tray.previewConfig then
            local spells = tray.previewConfig.spells or {}
            for index, spellData in ipairs(spells) do
                local icon = tray.previewIcons and tray.previewIcons[index]
                if icon and icon:IsShown() then
                    ApplyPreviewCooldown(icon, spellData)
                end
            end
        end
    end

    if testTrinketIcon and testTrinketIcon:IsShown() then
        testTrinketIcon.previewSpellData = testTrinketIcon.previewSpellData or { duration = 30 }
        ApplyPreviewCooldown(testTrinketIcon, testTrinketIcon.previewSpellData)
    end
end

runtimeRefreshState.QueuePreviewRefresh = function()
    if not testMode then
        return
    end

    if runtimeRefreshState.pendingPreview then
        if Performance and Performance.active then Performance:Count("preview.coalesced") end
        return
    end

    runtimeRefreshState.pendingPreview = C_Timer.NewTimer(0, function()
        runtimeRefreshState.pendingPreview = nil
        if testMode then
            runtimeRefreshState.RefreshPreview()
        end
    end)
end

runtimeRefreshState.SetPreviewEventsActive = function(active)
    local frame = runtimeRefreshState.previewEventFrame
    if active and not frame then
        frame = CreateFrame("Frame", NextFrameName("Core", "PreviewEventFrame"))
        frame:SetScript("OnEvent", function()
            runtimeRefreshState.QueuePreviewRefresh()
        end)
        runtimeRefreshState.previewEventFrame = frame
    end

    if not frame or runtimeRefreshState.previewEventsActive == active then
        return
    end

    runtimeRefreshState.previewEventsActive = active
    if active then
        frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        frame:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_ADDED")
        frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        frame:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_REMOVED")
    else
        frame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        frame:UnregisterEvent("FORBIDDEN_NAME_PLATE_UNIT_ADDED")
        frame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
        frame:UnregisterEvent("FORBIDDEN_NAME_PLATE_UNIT_REMOVED")
    end
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

    previewTicker = C_Timer.NewTicker(1, function()
        if not testMode then
            StopPreviewTicker()
            return
        end
        runtimeRefreshState.UpdatePreviewCooldowns()
    end)
end

local function StartTestMode()
    if testMode then
        return
    end

    testMode = true
    testModeStartedAt = GetTime()
    ClearPreviewConfigs()
    ResetPreviewTimerCache()
    runtimeRefreshState.SetPreviewEventsActive(true)
    runtimeRefreshState.RefreshPreview()
    StartPreviewTicker()
    if _G.ArenaDRNameplates_StartSelfDRPreview then
        _G.ArenaDRNameplates_StartSelfDRPreview()
    end
    if _G.ArenaDRNameplates_StartTargetFocusDRPreview then
        _G.ArenaDRNameplates_StartTargetFocusDRPreview()
    end
    NotifySettingsUIRefresh()
end

local function StopTestMode()
    local wasActive = testMode
    testMode = false
    StopPreviewTicker()
    runtimeRefreshState.SetPreviewEventsActive(false)
    if runtimeRefreshState.pendingPreview
        and type(runtimeRefreshState.pendingPreview.Cancel) == "function" then
        runtimeRefreshState.pendingPreview:Cancel()
    end
    runtimeRefreshState.pendingPreview = nil
    testModeStartedAt = nil
    ResetPreviewTimerCache()
    ClearPreviewConfigs()
    HideAllTestTrays()

    if _G.ArenaDRNameplates_StopSelfDRPreview then
        _G.ArenaDRNameplates_StopSelfDRPreview()
    end
    if _G.ArenaDRNameplates_StopTargetFocusDRPreview then
        _G.ArenaDRNameplates_StopTargetFocusDRPreview()
    end

    if testTrinketIcon then
        testTrinketIcon.previewCooldownCycle = nil
        testTrinketIcon.previewCooldownDuration = nil
        ClearCooldown(testTrinketIcon.Cooldown)
        testTrinketIcon:Hide()
    end

    if wasActive then
        NotifySettingsUIRefresh()
    end
end

local function ToggleTestMode()
    if testMode then
        StopTestMode()
    else
        StartTestMode()
    end
end

local function RefreshAll(forceSourceResync)
    RefreshLiveRuntime(forceSourceResync == true)
    if testMode then
        runtimeRefreshState.RefreshPreview()
    end
end

local function RefreshAllWithStyle()
    -- Every settings change lands here. Dropping the cached normalization bumps
    -- the shared revision, which is what tells the personal and Target/Focus
    -- trays their own style snapshots have expired.
    Shared.InvalidateDB()
    db = Shared.EnsureDB()
    InvalidateStyleSnapshot()
    if UpdateRecoveryTicker then
        UpdateRecoveryTicker()
    end
    RefreshAll(true)
end

local function ResetPosition()
    if not db then
        return
    end

    Shared.CopyDefaultsIntoTable(db, true)
    Shared.ResetBlizzardDRCVarsToDefaults()

    StopTestMode()
    RefreshAllWithStyle()

    if _G.ArenaDRNameplates_RefreshSelfDR then
        _G.ArenaDRNameplates_RefreshSelfDR()
    end
    if _G.ArenaDRNameplates_RefreshTargetFocusDR then
        _G.ArenaDRNameplates_RefreshTargetFocusDR()
    end
end

local function ApplyAnchorPreset(preset)
    if not db then
        return
    end

    Shared.ApplyAnchorPresetToTable(db, preset)
    RefreshAllWithStyle()
end

local function SetAdvancedAnchor(point, relativePoint)
    if not db then
        return
    end

    -- Presets derive the growth direction, so pin it down before dropping one.
    Shared.ApplyAnchorPresetToTable(db, "ADVANCED")
    db.point = point or db.point or defaults.point
    db.relativePoint = relativePoint or db.relativePoint or defaults.relativePoint
    RefreshAllWithStyle()
end

local function StopRecoveryTicker()
    if recoveryTicker then
        recoveryTicker:Cancel()
        recoveryTicker = nil
    end
    runtimeRefreshState.recoveryTickCount = 0
end

UpdateRecoveryTicker = function()
    local helper = GetHelper()
    if helper and type(helper.UpdateArenaActivity) == "function" then
        helper:UpdateArenaActivity()
    end

    if not db or not db.enabled or not IsInArena() then
        StopRecoveryTicker()
        return
    end

    if recoveryTicker then
        return
    end

    recoveryTicker = C_Timer.NewTicker(1, function()
        if not db or not db.enabled or not IsInArena() then
            StopRecoveryTicker()
            RequestLiveRuntimeRefresh(true)
            return
        end

        local changed = false
        local activeHelper = GetHelper()
        local mappingValid = true
        if activeHelper and type(activeHelper.ValidateMappings) == "function" then
            mappingValid = activeHelper:ValidateMappings() == true
        end
        if not mappingValid
            and activeHelper
            and type(activeHelper.RefreshMappings) == "function" then
            changed = activeHelper:RefreshMappings() == true
        end

        if changed then
            runtimeRefreshState.recoveryTickCount = 0
            return
        end

        runtimeRefreshState.recoveryTickCount = runtimeRefreshState.recoveryTickCount + 1
        if runtimeRefreshState.recoveryTickCount >= 5 then
            runtimeRefreshState.recoveryTickCount = 0
            if Performance and Performance.active then Performance:Count("runtime.fullWatchdogs") end
            RequestLiveRuntimeRefresh(true)
        elseif not RefreshLiveRuntimeLight() then
            RequestLiveRuntimeRefresh(true)
        end
    end)
end

local function RegisterHelperCallback()
    local helper = GetHelper()
    if not helper or type(helper.RegisterCallback) ~= "function" then
        print(S("WARN_HELPER_NOT_FOUND"))
        return
    end

    helper:RegisterCallback(helperCallbackOwner, function()
        RequestLiveRuntimeRefresh(false)
    end)

    if type(helper.UpdateArenaActivity) == "function" then
        helper:UpdateArenaActivity()
    end

    if type(helper.QueueBurstRefresh) == "function" then
        helper:QueueBurstRefresh()
    elseif type(helper.RefreshMappings) == "function" then
        helper:RefreshMappings()
    end
end

local function OpenSettings(pageKey)
    if type(_G.ArenaDRNameplates_OpenSettingsWindow) == "function" then
        _G.ArenaDRNameplates_OpenSettingsWindow(pageKey)
        return
    end

    local category = _G.ArenaDRNameplates_SettingsCategory
    if not category then
        print(S("WARN_SETTINGS_MENU_NOT_AVAILABLE"))
        return
    end

    Settings.OpenToCategory(category:GetID())
end

local function ResolveLiveArenaParents()
    wipe(resolvedArenaParents)
    for _, arenaID in ipairs(ARENA_IDS) do
        resolvedArenaParents[arenaID] = GetLiveAnchorParent(arenaID)
    end
    return resolvedArenaParents
end

-- Blizzard builds its tray icons on demand, so a category seen for the first
-- time appears as a brand new child that no hook covers yet. Catching the count
-- change here promotes the next tick to a full resync instead of waiting for the
-- watchdog, which is what left late hooked icons without a countdown.
local function HasNewLiveSourceChildren()
    for _, arenaID in ipairs(ARENA_IDS) do
        local info = sourceInfoByArenaID[arenaID]
        local tray = info and info.tray
        if tray and type(info.childCount) == "number" and type(tray.GetNumChildren) == "function" then
            local ok, count = pcall(tray.GetNumChildren, tray)
            if ok and type(count) == "number" and count ~= info.childCount then
                return true
            end
        end
    end

    return false
end

RefreshLiveRuntimeLight = function()
    local metricStartedAt = Performance and Performance.active and Performance:Begin()
    if not db or not db.enabled or not IsInArena() then
        if metricStartedAt then Performance:Finish("runtime.light", metricStartedAt) end
        return false
    end

    SweepExpiredLiveWindows()

    if HasNewLiveSourceChildren() then
        if metricStartedAt then Performance:Finish("runtime.light", metricStartedAt) end
        return false
    end

    local helper = GetHelper()
    local mappingIsComplete = helper
        and type(helper.IsMappingComplete) == "function"
        and helper:IsMappingComplete()

    for _, arenaID in ipairs(ARENA_IDS) do
        local parent = resolvedArenaParents[arenaID]
        local container = liveContainers[arenaID]
        local expectsParent = mappingIsComplete
            and type(helper.GetArenaToken) == "function"
            and helper:GetArenaToken(arenaID) ~= nil
        if expectsParent and not parent then
            if metricStartedAt then Performance:Finish("runtime.light", metricStartedAt) end
            return false
        end

        if parent and not container then
            if metricStartedAt then Performance:Finish("runtime.light", metricStartedAt) end
            return false
        end

        if parent and container then
            local needsLayout = ReconcileLiveContainerAnchor(arenaID, parent, container)
            if needsLayout then
                container.ArenaDRNameplatesStyleRevision = styleRevision
                if LayoutLiveContainer(arenaID) > 0 then
                    container:Show()
                end
            end
        end
    end

    if metricStartedAt then Performance:Finish("runtime.light", metricStartedAt) end
    return true
end

RefreshLiveRuntime = function(forceSourceResync)
    local metricStartedAt = Performance and Performance.active and Performance:Begin()
    local inArena = IsInArena()
    if not db or not db.enabled or not inArena then
        wipe(resolvedArenaParents)
        RestoreAllLiveTrays()
        HideAllLiveTrinketMirrors()
        if metricStartedAt then Performance:Finish("runtime.full", metricStartedAt) end
        return
    end

    SweepExpiredLiveWindows()

    local matchEngaged = IsArenaMatchEngaged(inArena)
    local trinketEnabled = IsTrinketEnabled()
    local parents = ResolveLiveArenaParents()
    RefreshLiveTrays(parents, forceSourceResync == true, inArena)
    RefreshLiveTrinketMirrors(
        parents,
        forceSourceResync == true,
        inArena,
        matchEngaged,
        trinketEnabled
    )
    if metricStartedAt then Performance:Finish("runtime.full", metricStartedAt) end
end

CancelPendingRuntimeRefresh = function()
    if runtimeRefreshState.pending
        and type(runtimeRefreshState.pending.Cancel) == "function" then
        runtimeRefreshState.pending:Cancel()
    end
    runtimeRefreshState.pending = nil
    runtimeRefreshState.forceSourceResync = false
end

RequestLiveRuntimeRefresh = function(forceSourceResync)
    runtimeRefreshState.forceSourceResync = runtimeRefreshState.forceSourceResync
        or forceSourceResync == true

    if runtimeRefreshState.pending then
        if Performance and Performance.active then Performance:Count("runtime.coalesced") end
        return
    end

    if Performance and Performance.active then Performance:Count("runtime.requests") end
    runtimeRefreshState.pending = C_Timer.NewTimer(0, function()
        runtimeRefreshState.pending = nil
        local forceResync = runtimeRefreshState.forceSourceResync
        runtimeRefreshState.forceSourceResync = false
        RefreshLiveRuntime(forceResync)
    end)
end

local function RegisterSharedMediaCallback()
    if sharedMediaCallbackOwner.registered then
        return
    end

    local sharedMedia = Shared.GetLibSharedMedia and Shared.GetLibSharedMedia()
    if not sharedMedia or type(sharedMedia.RegisterCallback) ~= "function" then
        return
    end

    sharedMedia.RegisterCallback(
        sharedMediaCallbackOwner,
        "LibSharedMedia_Registered",
        function(_, mediaType, key)
            if mediaType ~= "font" then
                return
            end

            -- A font that registers late changes what a cached key resolves to.
            if type(Shared.InvalidateFontCache) == "function" then
                Shared.InvalidateFontCache()
            end
            NotifySettingsUIRefresh()
            if db and db.textFont == key then
                RefreshAllWithStyle()
            end
        end
    )
    sharedMediaCallbackOwner.registered = true
end

runtimeRefreshState.performanceMetricOrder = {
    "mapping.validate",
    "mapping.full",
    "runtime.light",
    "runtime.full",
    "runtime.dr",
    "runtime.trinket",
    "preview.reconcile",
    "selfdr.scan",
    "selfdr.refresh",
    "targetfocus.refresh",
}

runtimeRefreshState.performanceCounterOrder = {
    "runtime.requests",
    "runtime.coalesced",
    "runtime.fullWatchdogs",
    "mapping.coalesced",
    "mapping.burstRetries",
    "preview.coalesced",
    "selfdr.requests",
    "selfdr.coalesced",
    "selfdr.unchanged",
    "targetfocus.requests",
    "targetfocus.coalesced",
}

runtimeRefreshState.PrintPerformanceReport = function(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    print(string.format(S("MSG_PERF_REPORT_HEADER"), tonumber(snapshot.elapsed) or 0))

    local metrics = type(snapshot.metrics) == "table" and snapshot.metrics or {}
    for _, metric in ipairs(runtimeRefreshState.performanceMetricOrder) do
        local stats = metrics[metric]
        if type(stats) == "table" and (stats.calls or 0) > 0 then
            local calls = stats.calls or 0
            local total = stats.total or 0
            print(string.format(
                S("MSG_PERF_METRIC"),
                metric,
                calls,
                total,
                calls > 0 and total / calls or 0,
                stats.maximum or 0
            ))
        end
    end

    local counters = type(snapshot.counters) == "table" and snapshot.counters or {}
    for _, counter in ipairs(runtimeRefreshState.performanceCounterOrder) do
        local value = counters[counter]
        if type(value) == "number" and value > 0 then
            print(string.format(S("MSG_PERF_COUNTER"), counter, value))
        end
    end
end

runtimeRefreshState.StartPerformanceSession = function()
    if not Performance then
        print(S("MSG_PERF_UNAVAILABLE"))
        return
    end

    if Performance:IsActive() then
        print(string.format(S("MSG_PERF_RUNNING"), math.ceil(Performance:GetRemaining())))
        return
    end

    local started, duration = Performance:Start(60, runtimeRefreshState.PrintPerformanceReport)
    if started then
        print(string.format(S("MSG_PERF_STARTED"), duration))
    end
end

local function SlashHandler(msg)
    local rawMsg = Trim(msg or "")
    local lowerMsg = string.lower(rawMsg)

    if lowerMsg == "" or lowerMsg == "config" or lowerMsg == "settings" or lowerMsg == "menu" then
        OpenSettings()
    elseif lowerMsg == "share" then
        OpenSettings("share")
        if type(_G.ArenaDRNameplates_GenerateExportString) == "function" then
            _G.ArenaDRNameplates_GenerateExportString(false)
        end
    elseif lowerMsg == "export" then
        OpenSettings("share")
        local exportString
        if type(_G.ArenaDRNameplates_GenerateExportString) == "function" then
            exportString = _G.ArenaDRNameplates_GenerateExportString(true)
        else
            exportString = Shared.ExportSettings()
        end
        print(S("MSG_EXPORT_READY"))
        print(exportString)
    elseif lowerMsg:match("^import%s+") then
        local importString = Trim(rawMsg:match("^%S+%s+(.+)$") or "")
        local ok, reason = Shared.ImportSettings(importString)
        if ok then
            db = Shared.EnsureDB()
            RefreshAllWithStyle()
            if _G.ArenaDRNameplates_RefreshSelfDR then
                _G.ArenaDRNameplates_RefreshSelfDR()
            end
            if _G.ArenaDRNameplates_RefreshTargetFocusDR then
                _G.ArenaDRNameplates_RefreshTargetFocusDR()
            end
            NotifySettingsUIRefresh()
            print(S("MSG_IMPORT_SUCCESS"))
        else
            print(S(Shared.GetImportErrorMessageKey(reason)))
        end
    elseif lowerMsg == "perf" then
        runtimeRefreshState.StartPerformanceSession()
    elseif lowerMsg == "test" then
        ToggleTestMode()
    elseif lowerMsg == "reset" then
        ResetPosition()
        print(S("MSG_SETTINGS_RESET"))
    elseif lowerMsg:match("^scale%s+") then
        local value = tonumber(lowerMsg:match("^scale%s+([%d%.]+)"))
        if value and value >= 0.5 and value <= 3.0 then
            EnsureDB()
            db.scale = value
            RefreshAllWithStyle()
            print(string.format(S("MSG_SCALE_SET_TO"), value))
        else
            print(S("ERR_INVALID_SCALE"))
        end
    else
        print(S("MSG_COMMANDS_HEADER"))
        print(S("MSG_COMMAND_CONFIG"))
        print(S("MSG_COMMAND_TEST"))
        print(S("MSG_COMMAND_RESET"))
        print(S("MSG_COMMAND_SCALE"))
        print(S("MSG_COMMAND_SHARE"))
        print(S("MSG_COMMAND_EXPORT"))
        print(S("MSG_COMMAND_IMPORT"))
        print(S("MSG_COMMAND_PERF"))
    end
end

SLASH_ArenaDRNameplates1 = "/ArenaDRNameplates"
SLASH_ArenaDRNameplates2 = "/arenadr"
SLASH_ArenaDRNameplates3 = "/adr"
SlashCmdList["ArenaDRNameplates"] = SlashHandler

local eventFrame = CreateFrame("Frame", NextFrameName("Core", "EventFrame"))
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
eventFrame:RegisterEvent("ARENA_COOLDOWNS_UPDATE")
eventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        local adapters = ns and ns.NameplateAdapters
        if adapters and type(adapters.RefreshAvailability) == "function" then
            adapters:RefreshAvailability()
        end
        RegisterSharedMediaCallback()
        RegisterHelperCallback()
        UpdateRecoveryTicker()
        RefreshAllWithStyle()
    elseif event == "ADDON_LOADED" then
        local adapters = ns and ns.NameplateAdapters
        if adapters and type(adapters.InvalidateAvailabilityCache) == "function" then
            adapters:InvalidateAvailabilityCache()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        StopTestMode()
        UpdateRecoveryTicker()
        RequestLiveRuntimeRefresh(true)
    elseif event == "PLAYER_LEAVING_WORLD" then
        StopTestMode()
        StopRecoveryTicker()
        CancelPendingRuntimeRefresh()
        RestoreAllLiveTrays()
        HideAllLiveTrinketMirrors()
    elseif event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS"
        or event == "ZONE_CHANGED_NEW_AREA" then
        StopTestMode()
        UpdateRecoveryTicker()
        RequestLiveRuntimeRefresh(true)
    elseif event == "ARENA_OPPONENT_UPDATE"
        or event == "ARENA_COOLDOWNS_UPDATE"
        or event == "PVP_MATCH_STATE_CHANGED" then
        UpdateRecoveryTicker()
        RequestLiveRuntimeRefresh(event == "ARENA_COOLDOWNS_UPDATE")
    elseif event == "PLAYER_TARGET_CHANGED" and testMode then
        runtimeRefreshState.QueuePreviewRefresh()
    end
end)

_G.ArenaDRNameplates_UpdateScale = RefreshAllWithStyle
_G.ArenaDRNameplates_UpdateOpacity = RefreshAllWithStyle
_G.ArenaDRNameplates_UpdateIconGrowth = RefreshAllWithStyle
_G.ArenaDRNameplates_UpdateBorderWidth = RefreshAllWithStyle
_G.ArenaDRNameplates_UpdateTimerColor = RefreshAllWithStyle
_G.ArenaDRNameplates_UpdateTimerPosition = RefreshAllWithStyle
_G.ArenaDRNameplates_RefreshAll = RefreshAllWithStyle
_G.ArenaDRNameplates_ToggleTestMode = ToggleTestMode
_G.ArenaDRNameplates_IsTestModeActive = function()
    return testMode
end
_G.ArenaDRNameplates_ResetAllAnchors = ResetPosition
_G.ArenaDRNameplates_ResetAnchor = ResetPosition
_G.ArenaDRNameplates_ResetAllSettings = ResetPosition
_G.ArenaDRNameplates_ApplyAnchorPreset = ApplyAnchorPreset
_G.ArenaDRNameplates_SetAdvancedAnchor = SetAdvancedAnchor
