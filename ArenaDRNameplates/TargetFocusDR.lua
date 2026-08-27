local _, ns = ...
ns = ns or {}

local Shared = ns.Shared
local S = Shared.S
local Performance = ns.Performance

local TargetFocusDR = ns.TargetFocusDR or {}
ns.TargetFocusDR = TargetFocusDR

local issecretvalue_fn = _G.issecretvalue
local UNIT_KINDS = { "target", "focus" }
local MAX_DR_SLOTS = 10
local BASE_ICON_SIZE = Shared.iconBaseSizes.targetFocusDR
local BASE_FONT_SIZE = 14
local PREVIEW_ICONS = {
    "Interface\\Icons\\Ability_Rogue_KidneyShot",
    "Interface\\Icons\\Spell_Nature_Polymorph",
    "Interface\\Icons\\Spell_Shadow_Possession",
}

local bars = {}
local testMode = false
local previewStartedAt
local previewTicker
local mirrorCallbackOwner = {}

local function IsSecretValue(value)
    if type(issecretvalue_fn) ~= "function" then
        return false
    end
    local ok, result = pcall(issecretvalue_fn, value)
    return ok and result == true
end

local function GetDB()
    return Shared.EnsureDB()
end

local function GetSettings()
    return GetDB().targetFocusDR
end

-- Timer and DR text styling both come from the shared tabs, and everything the
-- bars derive from them is normalized once per settings revision. Restyling a
-- bar touches every slot, and rebuilding these colour tables per slot was the
-- bulk of that work.
local styleSnapshot

local function GetStyleSnapshot()
    local revision = Shared.GetDBRevision()
    if styleSnapshot and styleSnapshot.revision == revision then
        return styleSnapshot
    end

    local db = GetDB()
    local settings = db.targetFocusDR
    local barDefaults = Shared.defaults.targetFocusDR

    local anchor = db.drTextAnchor
    if not Shared.validDRTextAnchors[anchor] then
        anchor = Shared.defaults.drTextAnchor
    end

    local iconLayout = Shared.NormalizeIconLayout(settings.iconLayout)

    styleSnapshot = {
        revision = revision,
        settings = settings,
        size = settings.size,
        opacity = settings.opacity,
        iconLayout = iconLayout,
        iconPadding = settings.iconPadding,
        iconGrowth = iconLayout == "VERTICAL"
            and Shared.NormalizeVerticalIconGrowth(settings.iconVerticalGrowth)
            or Shared.NormalizeIconGrowth(settings.iconGrowth),
        borderStyle = Shared.NormalizeDRBorderStyle(settings.borderStyle),
        borderWidth = Shared.ClampNumber(settings.borderWidth, 1, 8, 1.5),
        borderColor = Shared.NormalizeColorTable(settings.borderColor, barDefaults.borderColor),
        borderImmuneColor = Shared.NormalizeColorTable(
            settings.borderImmuneColor,
            barDefaults.borderImmuneColor
        ),
        showDRText = db.showDRText ~= false,
        showTimerSwipe = db.showTimerSwipe ~= false,
        showTimerSwipeEdge = db.showTimerSwipeEdge == true,
        showTimerText = db.showTimerText ~= false,
        showTimerDecimals = db.showTimerDecimals ~= false,
        timerDecimalThreshold = math.floor(
            Shared.ClampNumber(db.timerDecimalThreshold, 1, 20, 5) + 0.5
        ),
        timerTextColor = Shared.NormalizeColorTable(db.timerTextColor, Shared.defaults.timerTextColor),
        timerTextScale = Shared.ClampNumber(db.timerTextScale, 0.5, 3.0, 1),
        timerTextOffsetX = tonumber(db.timerTextOffsetX) or 0,
        timerTextOffsetY = tonumber(db.timerTextOffsetY) or 0,
        drTextAnchor = anchor,
        drTextColor = Shared.NormalizeColorTable(db.drTextColor, Shared.defaults.drTextColor),
        drTextImmuneColor = Shared.NormalizeColorTable(
            db.drTextImmuneColor,
            Shared.defaults.drTextImmuneColor
        ),
        drTextScale = Shared.ClampNumber(db.drTextScale, 0.5, 3.0, 1),
        drTextOffsetX = tonumber(db.drTextOffsetX) or 0,
        drTextOffsetY = tonumber(db.drTextOffsetY) or 0,
        textOutlineFlags = Shared.GetTextOutlineFlags(db.textOutline),
    }
    styleSnapshot.timerStyles = {}
    for _, kind in ipairs(UNIT_KINDS) do
        local unitSettings = settings[kind]
        local unitTimers = unitSettings and unitSettings.timers
        local useOverride = unitTimers and unitTimers.override == true
        styleSnapshot.timerStyles[kind] = {
            timerTextColor = useOverride
                and Shared.NormalizeColorTable(
                    unitTimers.timerTextColor,
                    barDefaults[kind].timers.timerTextColor
                )
                or styleSnapshot.timerTextColor,
            timerTextScale = useOverride
                and Shared.ClampNumber(
                    unitTimers.timerTextScale,
                    0.5,
                    3.0,
                    barDefaults[kind].timers.timerTextScale
                )
                or styleSnapshot.timerTextScale,
        }
    end
    return styleSnapshot
end

-- Shared owns the arena test so the bars cannot read the match state more
-- loosely than the tray mirror they consume. They used to: the bars accepted
-- the arena gates while the mirror waited for a running match, and every miss
-- forced a full source resync for a mirror that was deliberately idle.
local IsInArena = Shared.IsInArena

local function IsUnitEnabled(kind, settings)
    if kind == "target" then
        return settings.showTarget == true
    end
    return settings.showFocus == true
end

local function SetBooleanAlpha(region, value, trueAlpha, falseAlpha)
    if not region then
        return
    end

    if type(region.SetAlphaFromBoolean) == "function" then
        region:SetAlphaFromBoolean(value, trueAlpha, falseAlpha)
        return
    end

    if not IsSecretValue(value) then
        region:SetAlpha(value and trueAlpha or falseAlpha)
    end
end

local function SetRegionsAlpha(regions, value, trueAlpha, falseAlpha)
    if not regions then
        return
    end
    for _, region in ipairs(regions) do
        SetBooleanAlpha(region, value, trueAlpha, falseAlpha)
    end
end

local function EnsureBorderLayer(slot, key)
    slot.BorderLayers = slot.BorderLayers or {}
    if slot.BorderLayers[key] then
        return slot.BorderLayers[key]
    end

    local layer = { solid = {} }
    for index = 1, 4 do
        local texture = slot.Overlay:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(1, 1, 1, 1)
        texture:SetDrawLayer("OVERLAY", 6)
        layer.solid[index] = texture
    end

    layer.classic = slot.Overlay:CreateTexture(nil, "OVERLAY")
    layer.classic:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    layer.classic:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    layer.classic:SetDrawLayer("OVERLAY", 6)
    -- Built once so the classic style can hand back a region list without
    -- allocating a table on every immunity update.
    layer.classicOnly = { layer.classic }
    slot.BorderLayers[key] = layer
    return layer
end

local function LayoutSolidBorder(layer, slot, width, r, g, b)
    local top, bottom, left, right = layer.solid[1], layer.solid[2], layer.solid[3], layer.solid[4]

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", slot, "TOPLEFT")
    top:SetPoint("TOPRIGHT", slot, "TOPRIGHT")
    top:SetHeight(width)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT")
    bottom:SetHeight(width)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -width)
    left:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 0, width)
    left:SetWidth(width)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -width)
    right:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, width)
    right:SetWidth(width)

    for _, texture in ipairs(layer.solid) do
        texture:SetColorTexture(r, g, b, 1)
        texture:Show()
    end
end

local function StyleBorderLayer(layer, slot, style, width, color, visualScale)
    local r, g, b = color[1], color[2], color[3]
    if style == "SOLID" then
        LayoutSolidBorder(layer, slot, width, r, g, b)
        layer.classic:Hide()
    elseif style == "CLASSIC" then
        local padding = math.max(0.5, tonumber(visualScale) or 1)
        for _, texture in ipairs(layer.solid) do
            texture:Hide()
        end
        layer.classic:ClearAllPoints()
        layer.classic:SetPoint("TOPLEFT", slot, "TOPLEFT", -padding, padding)
        layer.classic:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", padding, -padding)
        layer.classic:SetVertexColor(r, g, b, 1)
        layer.classic:Show()
    else
        for _, texture in ipairs(layer.solid) do
            texture:Hide()
        end
        layer.classic:Hide()
    end
end

local function GetActiveBorderRegions(layer, style)
    if style == "SOLID" then
        return layer.solid
    end
    if style == "CLASSIC" then
        return layer.classicOnly
    end
    return nil
end

local function ApplyImmunityVisuals(slot, style)
    local isImmune = slot.isImmune

    -- A secret immunity flag cannot be compared, so it is reapplied every time.
    -- A public one is remembered: the mirror re-announces a slot far more often
    -- than its immunity actually flips.
    if not IsSecretValue(isImmune) then
        local key = isImmune == true
        if slot.ArenaDRNameplatesImmuneRevision == style.revision
            and slot.ArenaDRNameplatesImmuneState == key then
            return
        end
        slot.ArenaDRNameplatesImmuneRevision = style.revision
        slot.ArenaDRNameplatesImmuneState = key
    else
        slot.ArenaDRNameplatesImmuneRevision = nil
        slot.ArenaDRNameplatesImmuneState = nil
    end

    local borderStyle = style.borderStyle
    local normalRegions = GetActiveBorderRegions(EnsureBorderLayer(slot, "normal"), borderStyle)
    local immuneRegions = GetActiveBorderRegions(EnsureBorderLayer(slot, "immune"), borderStyle)

    SetRegionsAlpha(normalRegions, isImmune, 0, 1)
    SetRegionsAlpha(immuneRegions, isImmune, 1, 0)

    if not style.showDRText then
        slot.StageText:SetAlpha(0)
        slot.ImmuneText:SetAlpha(0)
    else
        SetBooleanAlpha(slot.StageText, isImmune, 0, 1)
        SetBooleanAlpha(slot.ImmuneText, isImmune, 1, 0)
    end
end

local function FindCooldownText(cooldown)
    if cooldown.ArenaDRNameplatesTargetFocusTimerText then
        return cooldown.ArenaDRNameplatesTargetFocusTimerText
    end

    local fontString
    if type(cooldown.GetCountdownFontString) == "function" then
        local ok, result = pcall(cooldown.GetCountdownFontString, cooldown)
        if ok then
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

    cooldown.ArenaDRNameplatesTargetFocusTimerText = fontString
    return fontString
end

local function ApplyCooldownStyle(cooldown, style)
    local showSwipe = style.showTimerSwipe
    if cooldown.SetDrawSwipe then
        cooldown:SetDrawSwipe(showSwipe)
    end
    if cooldown.SetSwipeColor then
        cooldown:SetSwipeColor(0, 0, 0, showSwipe and 0.7 or 0)
    end
    if cooldown.SetDrawEdge then
        cooldown:SetDrawEdge(showSwipe and style.showTimerSwipeEdge)
    end
    if cooldown.SetDrawBling then
        cooldown:SetDrawBling(false)
    end
    if cooldown.SetCountdownMillisecondsThreshold then
        cooldown:SetCountdownMillisecondsThreshold(
            style.showTimerDecimals and style.timerDecimalThreshold or 0
        )
    end
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(not style.showTimerText)
    end
end

local function ApplyTextStyle(slot, style, timerStyle, visualScale)
    local timerText = FindCooldownText(slot.Cooldown)
    if timerText then
        local color = timerStyle.timerTextColor
        local fontSize = math.max(
            6,
            math.floor(BASE_FONT_SIZE * timerStyle.timerTextScale * visualScale + 0.5)
        )
        Shared.ApplyTextFont(timerText, fontSize, style.textOutlineFlags)
        timerText:SetTextColor(color[1], color[2], color[3], 1)
        timerText:ClearAllPoints()
        timerText:SetPoint(
            "CENTER",
            slot,
            "CENTER",
            style.timerTextOffsetX * visualScale,
            style.timerTextOffsetY * visualScale
        )
    end

    local anchor = style.drTextAnchor
    local normalColor = style.drTextColor
    local immuneColor = style.drTextImmuneColor
    local scale = style.drTextScale

    local drFontSize = math.max(6, math.floor(BASE_FONT_SIZE * visualScale + 0.5))
    Shared.ApplyTextFont(slot.StageText, drFontSize, style.textOutlineFlags)
    slot.StageText:SetText("\194\189")
    slot.StageText:SetScale(scale)
    slot.StageText:SetTextColor(normalColor[1], normalColor[2], normalColor[3], 1)
    slot.StageText:ClearAllPoints()
    slot.StageText:SetPoint(
        anchor,
        slot.Overlay,
        anchor,
        style.drTextOffsetX * visualScale,
        style.drTextOffsetY * visualScale
    )

    Shared.ApplyTextFont(slot.ImmuneText, drFontSize, style.textOutlineFlags)
    slot.ImmuneText:SetText("%")
    slot.ImmuneText:SetScale(scale)
    slot.ImmuneText:SetTextColor(immuneColor[1], immuneColor[2], immuneColor[3], 1)
    slot.ImmuneText:ClearAllPoints()
    slot.ImmuneText:SetPoint("CENTER", slot.StageText, "CENTER")
end

local function EnsureSlot(bar, index)
    if bar.slots[index] then
        return bar.slots[index]
    end

    local slot = CreateFrame(
        "Frame",
        Shared.NextFrameName("TargetFocusDR", bar.kind .. "Slot", index),
        bar.frame
    )
    slot:SetFrameLevel(bar.frame:GetFrameLevel() + 1)
    slot:Hide()

    slot.Texture = slot:CreateTexture(nil, "BACKGROUND")
    slot.Texture:SetAllPoints()
    slot.Texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    slot.Cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.Cooldown:SetAllPoints()
    slot.Cooldown:SetReverse(false)

    slot.Overlay = CreateFrame("Frame", nil, slot)
    slot.Overlay:SetAllPoints()
    slot.Overlay:SetFrameLevel(slot:GetFrameLevel() + 10)

    slot.StageText = slot.Overlay:CreateFontString(nil, "OVERLAY")
    slot.StageText:SetShadowOffset(1, -1)
    slot.StageText:SetShadowColor(0, 0, 0, 1)

    slot.ImmuneText = slot.Overlay:CreateFontString(nil, "OVERLAY")
    slot.ImmuneText:SetShadowOffset(1, -1)
    slot.ImmuneText:SetShadowColor(0, 0, 0, 1)

    slot.isImmune = false
    bar.slots[index] = slot
    return slot
end

local function GetPositionAnchor(position)
    return Shared.ResolveMovableAnchorFrame(position and position.relativeFrame)
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

-- The bar is sized to its icons, so both the layout and the drag handler
-- measure the growth edge on a single-icon bar.
local function GetBarBaseIconSize(position, style)
    local visualScale = (style.size / BASE_ICON_SIZE)
        * Shared.ClampNumber(position.scale, 0.5, 3.0, 1.0)

    return BASE_ICON_SIZE * visualScale
end

local function AnchorBarFrame(bar, position, style)
    local point, offsetX, offsetY = Shared.ResolveGrowthAnchor(
        position.point,
        style.iconLayout,
        style.iconGrowth,
        GetBarBaseIconSize(position, style),
        position.offsetX,
        position.offsetY
    )

    bar.frame:ClearAllPoints()
    bar.frame:SetPoint(
        point,
        GetPositionAnchor(position),
        position.relativePoint,
        offsetX,
        offsetY
    )
end

local function SavePosition(kind)
    local bar = bars[kind]
    if not bar or not bar.frame then
        return
    end

    local position = GetSettings()[kind]
    local anchorFrame = GetPositionAnchor(position)
    local centerX, centerY = bar.frame:GetCenter()
    local parentX, parentY = anchorFrame:GetCenter()
    if not centerX or not centerY or not parentX or not parentY then
        return
    end

    local uiScale = GetEffectiveScale(UIParent, 1)
    if not uiScale or uiScale <= 0 then
        return
    end
    local scale = GetEffectiveScale(bar.frame, uiScale) / uiScale
    local anchorScale = GetEffectiveScale(anchorFrame, uiScale) / uiScale

    -- The layout anchors from the growth edge, not from the center, so without
    -- folding that in the bar would jump by half its length on the next pass.
    local style = GetStyleSnapshot()
    local saveX, saveY = Shared.GetGrowthAnchorSaveOffset(
        style.iconLayout,
        style.iconGrowth,
        GetBarBaseIconSize(position, style),
        bar.frame:GetWidth(),
        bar.frame:GetHeight()
    )

    position.point = "CENTER"
    position.relativePoint = "CENTER"
    position.offsetX = ((centerX * scale) - (parentX * anchorScale)) + (saveX * scale)
    position.offsetY = ((centerY * scale) - (parentY * anchorScale)) + (saveY * scale)

    AnchorBarFrame(bar, position, style)
    if _G.ArenaDRNameplates_RefreshSettingsUI then
        _G.ArenaDRNameplates_RefreshSettingsUI()
    end
end

local function EnsureBar(kind)
    if bars[kind] then
        return bars[kind]
    end

    local frame = CreateFrame("Frame", Shared.NextFrameName("TargetFocusDR", kind .. "Bar"), UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(220)
    frame:SetMovable(true)
    frame:SetClampedToScreen(false)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    local bar = { kind = kind, frame = frame, slots = {}, visibleSlots = {} }
    bars[kind] = bar

    frame:SetScript("OnDragStart", function(self)
        if GetSettings().locked == true then
            return
        end
        self.isDragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self.isDragging = nil
        self:StopMovingOrSizing()
        SavePosition(kind)
    end)

    local labelText = kind == "target"
        and S("UI_TARGETFOCUS_TARGET_LABEL")
        or S("UI_TARGETFOCUS_FOCUS_LABEL")
    bar.DragHint, bar.Label = Shared.CreateMovableTrayPlaceholder(frame, labelText)
    return bar
end

-- Styling a slot depends on the settings revision and nothing else, so a slot
-- already dressed for this revision needs none of the widget calls below. This
-- used to run unconditionally over every slot the bar had ever created, on
-- every mirror announcement.
local function ApplySlotStyle(slot, style, timerStyle, visualScale)
    if slot.ArenaDRNameplatesStyleRevision ~= style.revision
        or slot.ArenaDRNameplatesVisualScale ~= visualScale then
        slot.ArenaDRNameplatesStyleRevision = style.revision
        slot.ArenaDRNameplatesVisualScale = visualScale
        local iconSize = BASE_ICON_SIZE * visualScale
        slot:SetSize(iconSize, iconSize)
        ApplyCooldownStyle(slot.Cooldown, style)
        ApplyTextStyle(slot, style, timerStyle, visualScale)
        StyleBorderLayer(
            EnsureBorderLayer(slot, "normal"),
            slot,
            style.borderStyle,
            style.borderWidth * visualScale,
            style.borderColor,
            visualScale
        )
        StyleBorderLayer(
            EnsureBorderLayer(slot, "immune"),
            slot,
            style.borderStyle,
            style.borderWidth * visualScale,
            style.borderImmuneColor,
            visualScale
        )
    end

    ApplyImmunityVisuals(slot, style)
end

local function ApplyBarStyle(bar)
    local style = GetStyleSnapshot()
    local timerStyle = style.timerStyles[bar.kind]
    local settings = style.settings
    local position = settings[bar.kind]
    local unlocked = settings.locked == false
    local visualScale = (style.size / BASE_ICON_SIZE)
        * Shared.ClampNumber(position.scale, 0.5, 3.0, 1.0)

    if bar.ArenaDRNameplatesStyleRevision ~= style.revision
        or bar.ArenaDRNameplatesStyleTestMode ~= testMode then
        -- Mirror and preview callbacks can refresh several times while the
        -- mouse is held down. Re-applying layout transforms here would snap the
        -- bar back under the cursor before OnDragStop saves its new point, so
        -- the revision is only stamped once the transforms actually landed.
        if not bar.frame.isDragging then
            -- Scaling the positioned parent also scales its anchor space in
            -- WoW, which makes the whole bar drift as its scale changes. Keep
            -- the parent at 1 and resize its children/layout in UI units.
            bar.frame:SetScale(1)
            bar.ArenaDRNameplatesVisualScale = visualScale
            AnchorBarFrame(bar, position, style)
            bar.ArenaDRNameplatesStyleRevision = style.revision
            bar.ArenaDRNameplatesStyleTestMode = testMode
        end
        bar.frame:SetAlpha(style.opacity)
        bar.frame:EnableMouse(unlocked)
        bar.DragHint:SetShown(unlocked)
        bar.Label:SetShown(testMode or unlocked)
    end

    -- Only what the player can see is styled. A hidden slot is dressed on the
    -- refresh that shows it, because the revision guard above still applies.
    for _, slot in ipairs(bar.slots) do
        if slot:IsShown() then
            ApplySlotStyle(
                slot,
                style,
                timerStyle,
                bar.ArenaDRNameplatesVisualScale or visualScale
            )
        end
    end
end

local function LayoutBar(bar)
    local style = GetStyleSnapshot()
    local position = style.settings[bar.kind]
    local visualScale = bar.ArenaDRNameplatesVisualScale
        or ((style.size / BASE_ICON_SIZE)
            * Shared.ClampNumber(position.scale, 0.5, 3.0, 1.0))
    local iconSize = BASE_ICON_SIZE * visualScale
    local iconPadding = style.iconPadding * visualScale
    wipe(bar.visibleSlots)
    for _, slot in ipairs(bar.slots) do
        if slot:IsShown() then
            table.insert(bar.visibleSlots, slot)
        end
    end

    local count = #bar.visibleSlots
    local layout = style.iconLayout
    local growth = style.iconGrowth
    local width, height, pitch = Shared.CalculateTrayLayout(
        count,
        iconSize,
        iconPadding,
        layout
    )
    bar.frame:SetSize(width, height)
    for index, slot in ipairs(bar.visibleSlots) do
        Shared.AnchorChildByGrowth(slot, bar.frame, layout, growth, index, count, pitch)
    end
    bar.frame:SetShown(count > 0)
end

local function ClearCooldown(cooldown)
    if type(cooldown.Clear) == "function" then
        cooldown:Clear()
    else
        cooldown:SetCooldown(0, 0)
    end
    cooldown.ArenaDRNameplatesCopiedStart = nil
    cooldown.ArenaDRNameplatesCopiedDuration = nil
end

local function HideBarSlots(bar)
    for _, slot in ipairs(bar.slots) do
        ClearCooldown(slot.Cooldown)
        slot:Hide()
    end
end

local function CopyCooldown(sourceSlot, destination)
    if sourceSlot.ArenaDRNameplatesLiveCooldownActive ~= true then
        if destination.ArenaDRNameplatesCopiedStart then
            ClearCooldown(destination)
        end
        return
    end

    local startTime, duration
    local sourceCooldown = sourceSlot.Cooldown
    if sourceCooldown and type(sourceCooldown.GetCooldownTimes) == "function" then
        local ok, startMS, durationMS = pcall(sourceCooldown.GetCooldownTimes, sourceCooldown)
        if ok
            and not IsSecretValue(startMS)
            and not IsSecretValue(durationMS)
            and type(startMS) == "number"
            and type(durationMS) == "number"
            and durationMS > 0 then
            startTime = startMS / 1000
            duration = durationMS / 1000
        end
    end

    if not startTime or not duration then
        duration = Shared.DR_RESET_DURATION + 0.1
        local endsAt = sourceSlot.ArenaDRNameplatesLiveWindowEndsAt
        startTime = type(endsAt) == "number" and (endsAt - duration) or GetTime()
    end

    if destination.ArenaDRNameplatesCopiedStart ~= startTime
        or destination.ArenaDRNameplatesCopiedDuration ~= duration then
        destination:SetCooldown(startTime, duration)
        destination.ArenaDRNameplatesCopiedStart = startTime
        destination.ArenaDRNameplatesCopiedDuration = duration
    end
end

local function CopyTexture(sourceSlot, destination)
    local sourceTexture = sourceSlot.Icon
    if not sourceTexture then
        return
    end

    if sourceSlot.ArenaDRNameplatesLiveHasAtlas == true
        and type(sourceTexture.GetAtlas) == "function"
        and type(destination.SetAtlas) == "function" then
        local ok, atlas = pcall(sourceTexture.GetAtlas, sourceTexture)
        if ok then
            pcall(destination.SetAtlas, destination, atlas, true)
            destination:SetTexCoord(0, 1, 0, 1)
            return
        end
    end

    if type(sourceTexture.GetTexture) == "function" then
        local ok, texture = pcall(sourceTexture.GetTexture, sourceTexture)
        if ok then
            destination:SetTexture(texture)
            destination:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
end

local function SyncBarFromArena(bar, arenaID, allowResync)
    local mirror = ns.ArenaDRMirror
    local source = mirror and mirror:GetContainer(arenaID)
    if not source
        or source.ArenaDRNameplatesRuntimeInactive == true
        or type(source.slots) ~= "table" then
        bar.frame:Hide()
        -- Asking the mirror for a forced resync from inside a mirror
        -- announcement is a loop: the resync announces again, this misses
        -- again, and the runtime never settles. Only a refresh that came from a
        -- game event is allowed to nudge the mirror.
        if allowResync and mirror and mirror.RequestRefresh then
            mirror:RequestRefresh(true)
        end
        return
    end

    for index = 1, math.min(#source.slots, MAX_DR_SLOTS) do
        local sourceSlot = source.slots[index]
        local slot = EnsureSlot(bar, index)
        local shown = false
        if sourceSlot and type(sourceSlot.IsShown) == "function" then
            local ok, value = pcall(sourceSlot.IsShown, sourceSlot)
            shown = ok and not IsSecretValue(value) and value == true
        end

        if shown then
            CopyTexture(sourceSlot, slot.Texture)
            CopyCooldown(sourceSlot, slot.Cooldown)
            slot.isImmune = sourceSlot.ArenaDRNameplatesLiveIsImmune
            slot:Show()
        else
            ClearCooldown(slot.Cooldown)
            slot.isImmune = false
            slot:Hide()
        end
    end

    for index = #source.slots + 1, #bar.slots do
        ClearCooldown(bar.slots[index].Cooldown)
        bar.slots[index]:Hide()
    end

    ApplyBarStyle(bar)
    LayoutBar(bar)
end

local function ShowPreviewBar(bar)
    previewStartedAt = previewStartedAt or GetTime()
    for index, texture in ipairs(PREVIEW_ICONS) do
        local slot = EnsureSlot(bar, index)
        slot.Texture:SetTexture(texture)
        slot.Texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.isImmune = index == #PREVIEW_ICONS
        slot.Cooldown:SetCooldown(previewStartedAt - index, 22 + index)
        slot:Show()
    end
    for index = #PREVIEW_ICONS + 1, #bar.slots do
        bar.slots[index]:Hide()
    end
    ApplyBarStyle(bar)
    LayoutBar(bar)
end

local function ShowPlaceholderBar(bar)
    HideBarSlots(bar)
    ApplyBarStyle(bar)
    local visualScale = bar.ArenaDRNameplatesVisualScale or 1
    local iconSize = BASE_ICON_SIZE * visualScale
    bar.frame:SetSize(iconSize, iconSize)
    bar.frame:Show()
end

local function HideBar(bar)
    if not bar then
        return
    end
    HideBarSlots(bar)
    bar.DragHint:Hide()
    bar.Label:Hide()
    bar.frame:Hide()
end

local function HideAllBars()
    for _, bar in pairs(bars) do
        HideBar(bar)
    end
end

local function StopPreviewTicker()
    if previewTicker then
        previewTicker:Cancel()
        previewTicker = nil
    end
end

local function UpdatePreviewTicker()
    if not testMode then
        StopPreviewTicker()
        return
    end
    if previewTicker then
        return
    end
    previewTicker = C_Timer.NewTicker(Shared.DR_RESET_DURATION, function()
        if not testMode then
            StopPreviewTicker()
            return
        end
        previewStartedAt = GetTime()
        TargetFocusDR.Refresh()
    end)
end

-- The bars only consume the mirror while the feature is on. The callback used
-- to be installed at login and left there for the session, so a disabled
-- Target/Focus tracker still paid for every mirror announcement.
local mirrorCallbackRegistered = false

local function OnArenaDRMirrorChanged()
    TargetFocusDR.RequestRefresh(true)
end

local function ApplyMirrorSubscription(settings)
    local mirror = ns.ArenaDRMirror
    if not mirror or type(mirror.RegisterCallback) ~= "function" then
        return
    end

    local shouldSubscribe = settings ~= nil and settings.enabled == true
    if shouldSubscribe == mirrorCallbackRegistered then
        return
    end

    if shouldSubscribe then
        mirror:RegisterCallback(mirrorCallbackOwner, OnArenaDRMirrorChanged)
    else
        mirror:UnregisterCallback(mirrorCallbackOwner)
    end
    mirrorCallbackRegistered = shouldSubscribe
end

-- allowResync stays false for a refresh the mirror itself asked for. Anything
-- else -- a game event, the options panel, the preview -- may ask the mirror to
-- rebuild its source hooks.
function TargetFocusDR.Refresh(allowResync)
    local settings = GetSettings()
    ApplyMirrorSubscription(settings)

    local preview = testMode
    local unlocked = settings.locked == false

    if settings.enabled ~= true then
        StopPreviewTicker()
        HideAllBars()
        return
    end

    if preview then
        local metricStartedAt = Performance and Performance.active and Performance:Begin()
        local hasPreviewBar = false
        for _, kind in ipairs(UNIT_KINDS) do
            if IsUnitEnabled(kind, settings) then
                hasPreviewBar = true
                ShowPreviewBar(EnsureBar(kind))
            else
                HideBar(bars[kind])
            end
        end
        if hasPreviewBar then
            UpdatePreviewTicker()
        else
            StopPreviewTicker()
        end
        if metricStartedAt then
            Performance:Finish("targetfocus.refresh", metricStartedAt)
        end
        return
    end

    StopPreviewTicker()

    if not IsInArena() then
        HideAllBars()
        return
    end

    local metricStartedAt = Performance and Performance.active and Performance:Begin()

    local helper = ns.ArenaNameplateHelper
    for _, kind in ipairs(UNIT_KINDS) do
        local bar = EnsureBar(kind)
        if not IsUnitEnabled(kind, settings) then
            HideBar(bar)
        elseif unlocked then
            ShowPlaceholderBar(bar)
        else
            local arenaID = helper
                and type(helper.GetArenaIDForUnit) == "function"
                and helper:GetArenaIDForUnit(kind)
            if arenaID then
                SyncBarFromArena(bar, arenaID, allowResync ~= false)
            else
                bar.frame:Hide()
            end
        end
    end

    if metricStartedAt then
        Performance:Finish("targetfocus.refresh", metricStartedAt)
    end
end

-- The mirror can announce every hooked icon of every opponent in a single
-- runtime tick. The bars only have to settle once per frame.
local pendingRefresh
local pendingFromMirrorOnly = true

function TargetFocusDR.RequestRefresh(fromMirror)
    if not fromMirror then
        pendingFromMirrorOnly = false
    end

    if pendingRefresh then
        if Performance and Performance.active then
            Performance:Count("targetfocus.coalesced")
        end
        return
    end

    if Performance and Performance.active then
        Performance:Count("targetfocus.requests")
    end
    pendingRefresh = C_Timer.NewTimer(0, function()
        pendingRefresh = nil
        local allowResync = not pendingFromMirrorOnly
        pendingFromMirrorOnly = true
        TargetFocusDR.Refresh(allowResync)
    end)
end

function TargetFocusDR.RefreshAll()
    local mirror = ns.ArenaDRMirror
    if mirror and mirror.RequestRefresh then
        mirror:RequestRefresh(true)
    end
    TargetFocusDR.Refresh()
end

function TargetFocusDR.StartPreview()
    testMode = true
    previewStartedAt = GetTime()
    TargetFocusDR.Refresh()
end

function TargetFocusDR.StopPreview()
    testMode = false
    previewStartedAt = nil
    StopPreviewTicker()
    HideAllBars()
    TargetFocusDR.Refresh()
end

function TargetFocusDR.ResetPositions()
    local settings = GetSettings()
    for _, kind in ipairs(UNIT_KINDS) do
        local defaults = Shared.defaults.targetFocusDR[kind]
        settings[kind].relativeFrame = defaults.relativeFrame
        settings[kind].point = defaults.point
        settings[kind].relativePoint = defaults.relativePoint
        settings[kind].offsetX = defaults.offsetX
        settings[kind].offsetY = defaults.offsetY
    end
    -- Written straight into the saved variables, so the cached normalization
    -- and every style snapshot keyed on its revision have to go.
    Shared.InvalidateDB()
    TargetFocusDR.Refresh()
    if _G.ArenaDRNameplates_RefreshSettingsUI then
        _G.ArenaDRNameplates_RefreshSettingsUI()
    end
end

local eventFrame = CreateFrame(
    "Frame",
    Shared.NextFrameName("TargetFocusDR", "EventFrame")
)
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
eventFrame:RegisterEvent("ARENA_COOLDOWNS_UPDATE")
eventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEAVING_WORLD" then
        testMode = false
        previewStartedAt = nil
        StopPreviewTicker()
        HideAllBars()
        return
    end
    -- Target and focus changes arrive in bursts of their own, so events go
    -- through the same coalescing tick as the mirror announcements.
    TargetFocusDR.RequestRefresh()
end)

_G.ArenaDRNameplates_RefreshTargetFocusDR = TargetFocusDR.RefreshAll
_G.ArenaDRNameplates_StartTargetFocusDRPreview = TargetFocusDR.StartPreview
_G.ArenaDRNameplates_StopTargetFocusDRPreview = TargetFocusDR.StopPreview
_G.ArenaDRNameplates_ResetTargetFocusDRPositions = TargetFocusDR.ResetPositions
