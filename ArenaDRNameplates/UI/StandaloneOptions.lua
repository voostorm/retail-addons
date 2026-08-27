local addonName, ns = ...
ns = ns or {}

local Shared = ns.Shared
local S = Shared.S

local SettingsUI = {}
ns.SettingsUI = SettingsUI

local WINDOW_NAME = "ArenaDRNameplatesStandaloneOptionsFrame"
local WINDOW_WIDTH = 856
local WINDOW_HEIGHT = 670
local PAGE_WIDTH = 650
local NAV_WIDTH = 140
local NAV_BUTTON_HEIGHT = 30
local NAV_BUTTON_GAP = 4
local NAV_GROUP_GAP = 10
local NAV_CONTENT_GAP = 14
local SCROLLBAR_GUTTER = 28
local SCROLLBAR_RIGHT_OFFSET = 2
local SCROLLBAR_VERTICAL_INSET = 18
local PAGE_HORIZONTAL_INSET = 6
local CARD_WIDTH = PAGE_WIDTH - (PAGE_HORIZONTAL_INSET * 2)
local CARD_INSET = 18
local CARD_BOTTOM_PADDING = 18
local ROW_WIDTH = CARD_WIDTH - (CARD_INSET * 2)
local DESCRIPTION_WIDTH = ROW_WIDTH
local LABEL_WIDTH = 214
local CONTROL_OFFSET = 254
local CHECKBOX_LABEL_WIDTH = ROW_WIDTH - 32
local ZONE_LABEL_WIDTH = 70
local DEFAULT_PAGE_CONTENT_HEIGHT = 640
local TITLEBAR_HEIGHT = 36
local MODERN_DROPDOWN_WIDTH = 228
local MODERN_DROPDOWN_ENTRY_HEIGHT = 20

local COLOR_ACCENT = { r = 0.04, g = 0.76, b = 1.0 }
local COLOR_HEADER = { r = 0.25, g = 0.45, b = 0.65 }
local COLOR_BG = { r = 0.06, g = 0.07, b = 0.09 }
local COLOR_TITLEBAR = { r = 0.04, g = 0.06, b = 0.08 }
local COLOR_BORDER = { r = 0.15, g = 0.30, b = 0.45 }
local COLOR_PANEL = { r = 0.08, g = 0.10, b = 0.13 }
local COLOR_PANEL_TOP = { r = 0.10, g = 0.18, b = 0.26 }
local COLOR_PANEL_BOTTOM = { r = 0.02, g = 0.03, b = 0.05 }
local COLOR_TEXT = { r = 0.80, g = 0.90, b = 0.96 }

local defaults = Shared.defaults
local blizzardDRCVars = Shared.blizzardDRCVars or {}
local NextFrameName = Shared.NextFrameName
local issecretvalue_fn = _G.issecretvalue

SettingsUI.addonName = addonName
SettingsUI.NextFrameName = NextFrameName
SettingsUI.controls = {}
SettingsUI.refreshables = {}
SettingsUI.pages = {}
SettingsUI.pageButtons = {}
SettingsUI.initialized = false
SettingsUI.windowInitialized = false
SettingsUI.isRefreshing = false
SettingsUI.refreshAllPending = false
SettingsUI.refreshControlsPending = false
SettingsUI.selectedPage = "general"

local controls = SettingsUI.controls

local function IsSecretValue(value)
    if value == nil or type(issecretvalue_fn) ~= "function" then
        return false
    end

    local ok, result = pcall(issecretvalue_fn, value)
    return ok and result == true
end

local function AsSafeNumber(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge or IsSecretValue(value) then
        return nil
    end
    return value
end

local function GetCheckboxLabel(check)
    return check.text or check.Text
end

local function TrackRefreshable(widget)
    SettingsUI.refreshables[#SettingsUI.refreshables + 1] = widget
    return widget
end

local function RegisterSettingsCategory(frame)
    local category = Settings.RegisterCanvasLayoutCategory(frame, frame.name)
    Settings.RegisterAddOnCategory(category)
    return category
end

local function OpenSettingsCategory(category)
    if not category then
        return false
    end

    local categoryID = category:GetID()
    if not categoryID then
        return false
    end

    Settings.OpenToCategory(categoryID)
    return true
end

local function HideSystemSettingsPanels()
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    end
end

local function ApplyPanelBorders(frame)
    local function MakeLine(p1, p2, isHorizontal)
        local texture = frame:CreateTexture(nil, "BORDER")
        texture:SetColorTexture(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.9)
        if isHorizontal then
            texture:SetHeight(1)
        else
            texture:SetWidth(1)
        end
        texture:SetPoint(p1)
        texture:SetPoint(p2)
    end

    MakeLine("TOPLEFT", "TOPRIGHT", true)
    MakeLine("BOTTOMLEFT", "BOTTOMRIGHT", true)
    MakeLine("TOPLEFT", "BOTTOMLEFT", false)
    MakeLine("TOPRIGHT", "BOTTOMRIGHT", false)
end

local function AttachWindowDragHandle(frame, window)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        if window and window:IsMovable() then
            window:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function()
        if window then
            window:StopMovingOrSizing()
        end
    end)
end

function SettingsUI.EnsureDB()
    return Shared.EnsureDB()
end

function SettingsUI.RefreshAll()
    -- Every option writes straight into the saved variables and then lands
    -- here, so this is the one funnel that has to drop the cached
    -- normalization. It runs now, not on the coalesced tick: a caller may read
    -- the setting back before the frame ends.
    Shared.InvalidateDB()

    if SettingsUI.refreshAllPending then
        return
    end

    SettingsUI.refreshAllPending = true
    C_Timer.After(0, function()
        SettingsUI.refreshAllPending = false
        if _G.ArenaDRNameplates_RefreshAll then
            _G.ArenaDRNameplates_RefreshAll()
        end
        if _G.ArenaDRNameplates_RefreshSelfDR then
            _G.ArenaDRNameplates_RefreshSelfDR()
        end
        if _G.ArenaDRNameplates_RefreshTargetFocusDR then
            _G.ArenaDRNameplates_RefreshTargetFocusDR()
        end
    end)
end

function SettingsUI.ApplyAnchorPreset(preset)
    local db = SettingsUI.EnsureDB()

    if _G.ArenaDRNameplates_ApplyAnchorPreset then
        _G.ArenaDRNameplates_ApplyAnchorPreset(preset)
    else
        Shared.ApplyAnchorPresetToTable(db, preset)
        SettingsUI.RefreshAll()
    end
end

function SettingsUI.ApplyAdvancedAnchor(point, relativePoint)
    local db = SettingsUI.EnsureDB()
    -- Presets derive the growth direction, so pin it down before dropping one.
    Shared.ApplyAnchorPresetToTable(db, "ADVANCED")
    db.point = point
    db.relativePoint = relativePoint

    if _G.ArenaDRNameplates_SetAdvancedAnchor then
        _G.ArenaDRNameplates_SetAdvancedAnchor(point, relativePoint)
    else
        SettingsUI.RefreshAll()
    end
end

function SettingsUI.ApplyTrinketAnchorPreset(preset)
    local db = SettingsUI.EnsureDB()
    db.trinket = db.trinket or Shared.CopyTable(defaults.trinket)
    Shared.ApplyAnchorPresetToTable(db.trinket, preset)
    SettingsUI.RefreshAll()
end

function SettingsUI.ApplyAdvancedTrinketAnchor(point, relativePoint)
    local db = SettingsUI.EnsureDB()
    db.trinket = db.trinket or Shared.CopyTable(defaults.trinket)
    db.trinket.point = point
    db.trinket.relativePoint = relativePoint
    db.trinket.anchorPreset = "ADVANCED"
    SettingsUI.RefreshAll()
end

local function GetBlizzardDRCVarInfo(key)
    local info = blizzardDRCVars[key]
    if type(info) == "table" and type(info.cvar) == "string" then
        return info
    end
end

local function IsBlizzardDRCVarAvailable(key)
    local info = GetBlizzardDRCVarInfo(key)
    return info and Shared.IsCVarAvailable(info.cvar) == true
end

local function GetBlizzardDRCVarBool(key)
    local info = GetBlizzardDRCVarInfo(key)
    if not info then
        return false
    end

    return Shared.GetCVarBool(info.cvar, info.defaultValue)
end

local function SetBlizzardDRCVarBool(key, value)
    local info = GetBlizzardDRCVarInfo(key)
    if not info then
        return
    end

    if Shared.SetCVarBool(info.cvar, value) then
        SettingsUI.RefreshAll()
    end
end

function SettingsUI.ResetAllSettings()
    local db = SettingsUI.EnsureDB()

    if _G.ArenaDRNameplates_ResetAllSettings then
        _G.ArenaDRNameplates_ResetAllSettings()
    else
        Shared.CopyDefaultsIntoTable(db, true)
        Shared.ResetBlizzardDRCVarsToDefaults()
        SettingsUI.RefreshAll()
    end

    SettingsUI.RefreshControls()
end

StaticPopupDialogs["ARENADRNAMEPLATES_CONFIRM_RESET"] = {
    text = S("UI_RESET_CONFIRMATION"),
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        SettingsUI.ResetAllSettings()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateTitle(parent, text, point, relativeTo, relativePoint, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint(point, relativeTo, relativePoint, x, y)
    fs:SetText("|cff00c0ff" .. tostring(text or "") .. "|r")
    return fs
end

local function CreateDescription(parent, text, point, relativeTo, relativePoint, x, y, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint(point, relativeTo, relativePoint, x, y)
    fs:SetWidth(width or DESCRIPTION_WIDTH)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetText("|cff778899" .. tostring(text or "") .. "|r")
    return fs
end

local function CreateSectionTitle(parent, text, point, relativeTo, relativePoint, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint(point, relativeTo, relativePoint, x, y)
    fs:SetText("|cff99d6ff" .. tostring(text or "") .. "|r")
    return fs
end

local function CreateDivider(parent, point, relativeTo, relativePoint, x, y, width)
    local divider = parent:CreateTexture(nil, "BORDER")
    divider:SetColorTexture(COLOR_HEADER.r, COLOR_HEADER.g, COLOR_HEADER.b, 0.7)
    divider:SetPoint(point, relativeTo, relativePoint, x, y)
    divider:SetSize(width, 1)
    return divider
end

local function CreateStyledPanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height or 10)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = true,
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    panel:SetBackdropColor(COLOR_PANEL.r, COLOR_PANEL.g, COLOR_PANEL.b, 0.94)
    panel:SetBackdropBorderColor(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.78)

    panel.topShade = panel:CreateTexture(nil, "ARTWORK")
    panel.topShade:SetTexture("Interface\\Buttons\\WHITE8x8")
    panel.topShade:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    panel.topShade:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    panel.topShade:SetHeight(30)
    panel.topShade:SetGradient(
        "VERTICAL",
        CreateColor(COLOR_PANEL_TOP.r, COLOR_PANEL_TOP.g, COLOR_PANEL_TOP.b, 0.22),
        CreateColor(COLOR_PANEL_TOP.r, COLOR_PANEL_TOP.g, COLOR_PANEL_TOP.b, 0.04)
    )

    panel.bottomShade = panel:CreateTexture(nil, "ARTWORK")
    panel.bottomShade:SetTexture("Interface\\Buttons\\WHITE8x8")
    panel.bottomShade:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 1, 1)
    panel.bottomShade:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
    panel.bottomShade:SetHeight(52)
    panel.bottomShade:SetGradient(
        "VERTICAL",
        CreateColor(COLOR_PANEL_BOTTOM.r, COLOR_PANEL_BOTTOM.g, COLOR_PANEL_BOTTOM.b, 0.02),
        CreateColor(COLOR_PANEL_BOTTOM.r, COLOR_PANEL_BOTTOM.g, COLOR_PANEL_BOTTOM.b, 0.30)
    )

    return panel
end

local function CreateCard(parent, titleText, descriptionText, height)
    local card = CreateStyledPanel(parent, CARD_WIDTH, height)
    card.minHeight = height or 10
    card.Title = CreateSectionTitle(card, titleText, "TOPLEFT", card, "TOPLEFT", 18, -18)

    local dividerAnchor = card.Title
    if descriptionText and descriptionText ~= "" then
        card.Description = CreateDescription(card, descriptionText, "TOPLEFT", card.Title, "BOTTOMLEFT", 0, -6, DESCRIPTION_WIDTH)
        dividerAnchor = card.Description
    end

    card.Divider = CreateDivider(card, "TOPLEFT", dividerAnchor, "BOTTOMLEFT", 0, -12, DESCRIPTION_WIDTH)
    card.UpdateLayout = function()
        local top = AsSafeNumber(card:GetTop())
        if not top then
            card:SetHeight(card.minHeight)
            return
        end

        local lowestBottom
        for _, child in ipairs({ card:GetChildren() }) do
            if child:IsShown() then
                local bottom = AsSafeNumber(child:GetBottom())
                if bottom and (not lowestBottom or bottom < lowestBottom) then
                    lowestBottom = bottom
                end
            end
        end

        if not lowestBottom then
            card:SetHeight(card.minHeight)
            return
        end

        local requiredHeight = math.ceil((top - lowestBottom) + CARD_BOTTOM_PADDING)
        card:SetHeight(math.max(card.minHeight, requiredHeight))
    end
    return card
end

local function CreateNavButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or NAV_WIDTH, NAV_BUTTON_HEIGHT)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = true,
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    button.SelectionIndicator = button:CreateTexture(nil, "ARTWORK")
    button.SelectionIndicator:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -3)
    button.SelectionIndicator:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 3)
    button.SelectionIndicator:SetWidth(3)
    button.SelectionIndicator:SetColorTexture(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 1)
    button.SelectionIndicator:Hide()

    button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.Text:SetPoint("LEFT", button, "LEFT", 14, 0)
    button.Text:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button.Text:SetJustifyH("LEFT")
    button.Text:SetWordWrap(false)
    button.Text:SetText(label)

    button:SetScript("OnEnter", function(self)
        if self.selected then
            return
        end
        self:SetBackdropColor(0.09, 0.14, 0.18, 0.98)
        self:SetBackdropBorderColor(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.48)
        self.Text:SetTextColor(1.00, 1.00, 1.00)
    end)
    button:SetScript("OnLeave", function(self)
        if self.selected then
            return
        end
        self:SetBackdropColor(0.06, 0.08, 0.11, 0.82)
        self:SetBackdropBorderColor(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.52)
        self.Text:SetTextColor(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b)
    end)

    return button
end

local function SetNavButtonState(button, selected)
    if not button then
        return
    end

    button.selected = selected
    if selected then
        button:SetBackdropColor(0.07, 0.15, 0.21, 0.98)
        button:SetBackdropBorderColor(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.92)
        button.Text:SetTextColor(1.00, 1.00, 1.00)
        button.SelectionIndicator:Show()
    else
        button:SetBackdropColor(0.06, 0.08, 0.11, 0.82)
        button:SetBackdropBorderColor(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.52)
        button.Text:SetTextColor(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b)
        button.SelectionIndicator:Hide()
    end
end

local function AnchorBelow(frame, relativeTo, spacing)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, -(spacing or 8))
end

local function CreateActionButton(parent, label, width, onClick)
    local button = CreateFrame("Button", NextFrameName("Settings", "Button"), parent, "UIPanelButtonTemplate")
    button:SetSize(width or 160, 24)
    button:SetText(label)
    button:SetScript("OnClick", function(self)
        if onClick then
            onClick(self)
        end
    end)
    return button
end

local function CreateTextInput(parent, width)
    local editBox = CreateFrame("EditBox", NextFrameName("Settings", "EditBox"), parent, "InputBoxTemplate")
    editBox:SetSize(width or ROW_WIDTH, 26)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetMaxLetters(4096)
    if editBox.SetTextInsets then
        editBox:SetTextInsets(4, 4, 0, 0)
    end
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    return editBox
end

local function FocusAndSelectEditBox(editBox)
    if not editBox then
        return
    end

    editBox:SetFocus()
    editBox:HighlightText()
    if editBox.SetCursorPosition then
        editBox:SetCursorPosition(0)
    end
end

function SettingsUI.SetShareStatus(text, isError)
    if not controls.shareStatusText then
        return
    end

    local color = isError and "|cffff6060" or "|cff00ff00"
    controls.shareStatusText:SetText(color .. tostring(text or "") .. "|r")
end

function SettingsUI.GenerateExportString(selectText)
    local exportString = Shared.ExportSettings()
    if controls.exportStringBox then
        controls.exportStringBox:SetText(exportString)
        if selectText then
            FocusAndSelectEditBox(controls.exportStringBox)
        end
    end
    return exportString
end

function SettingsUI.ImportSettingsFromInput()
    local importString = controls.importStringBox and controls.importStringBox:GetText() or ""
    local ok, reason = Shared.ImportSettings(importString)

    if ok then
        SettingsUI.RefreshAll()
        SettingsUI.RefreshControls()
        SettingsUI.GenerateExportString(false)
        if controls.importStringBox then
            controls.importStringBox:ClearFocus()
        end
        SettingsUI.SetShareStatus(S("MSG_IMPORT_SUCCESS"), false)
        print(S("MSG_IMPORT_SUCCESS"))
        return true
    end

    local message = S(Shared.GetImportErrorMessageKey(reason))
    SettingsUI.SetShareStatus(message, true)
    print(message)
    return false
end

StaticPopupDialogs["ARENADRNAMEPLATES_CONFIRM_IMPORT"] = {
    text = S("UI_IMPORT_CONFIRMATION"),
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        SettingsUI.ImportSettingsFromInput()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ResolveTooltipText(value, owner)
    if type(value) == "function" then
        return value(owner)
    end

    return value
end

local function ShowTooltip(owner, title, text, anchor)
    local resolvedTitle = ResolveTooltipText(title, owner)
    local resolvedText = ResolveTooltipText(text, owner)

    if (not resolvedTitle or resolvedTitle == "") and (not resolvedText or resolvedText == "") then
        return
    end

    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    if resolvedTitle and resolvedTitle ~= "" then
        GameTooltip:SetText(resolvedTitle, COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 1, true)
        if resolvedText and resolvedText ~= "" then
            GameTooltip:AddLine(resolvedText, COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, true)
        end
    else
        GameTooltip:SetText(resolvedText, COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 1, true)
    end
    GameTooltip:Show()
end

local function AttachTooltip(target, title, text, anchor)
    if not target or target._arenaDRTooltipAttached then
        return
    end

    target._arenaDRTooltipAttached = true
    target:HookScript("OnEnter", function(self)
        ShowTooltip(self, title, text, anchor)
    end)
    target:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    target:HookScript("OnHide", function()
        GameTooltip:Hide()
    end)
end

local function AttachRowTooltip(row, text, anchor)
    if not row then
        return
    end

    local function GetRowTitle()
        if row.Label and row.Label.GetText then
            return row.Label:GetText()
        end
    end

    AttachTooltip(row, GetRowTitle, text, anchor)
    if row.Control and row.Control ~= row then
        AttachTooltip(row.Control, GetRowTitle, text, anchor)
    end
end

local function CreateCheckboxRow(parent, labelText, getter, setter)
    local row = CreateFrame("Frame", NextFrameName("Settings", "CheckboxRow"), parent)
    row:SetSize(ROW_WIDTH, 28)

    local checkbox = CreateFrame("CheckButton", NextFrameName("Settings", "Checkbox"), row, "UICheckButtonTemplate")
    checkbox:SetPoint("LEFT", row, "LEFT", 0, 0)

    local text = GetCheckboxLabel(checkbox)
    if text then
        text:SetText(labelText)
        text:SetWidth(CHECKBOX_LABEL_WIDTH)
        text:SetJustifyH("LEFT")
    end

    checkbox:SetScript("OnClick", function(self)
        setter(self:GetChecked() == true)
        SettingsUI.RefreshControls()
    end)

    row.Refresh = function()
        checkbox:SetChecked(getter())
    end

    row.SetEnabled = function(self, enabled)
        enabled = enabled ~= false
        self:SetAlpha(enabled and 1 or 0.45)
        checkbox:SetEnabled(enabled)
    end

    row.Control = checkbox
    row.Label = text
    return TrackRefreshable(row)
end

-- Shrinks a checkbox row so several can share one line. The checkbox keeps its
-- native size; only the row and its label are narrowed.
local function SetCompactCheckboxWidth(row, width)
    row:SetWidth(width)
    if row.Label then
        row.Label:SetWidth(math.max(width - 32, 20))
    end
    return row
end

local function CreateSliderRow(parent, labelText, minValue, maxValue, step, formatter, getter, setter)
    local row = CreateFrame("Frame", NextFrameName("Settings", "SliderRow"), parent)
    row:SetSize(ROW_WIDTH, 42)

    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Label:SetJustifyH("LEFT")
    row.Label:SetText(labelText)
    row.Label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Label:SetWidth(LABEL_WIDTH)

    local slider = CreateFrame("Frame", NextFrameName("Settings", "Slider"), row, "MinimalSliderWithSteppersTemplate")
    slider.Slider:SetWidth(264)
    slider.Slider:ClearAllPoints()
    slider.Slider:SetPoint("LEFT", row, "LEFT", CONTROL_OFFSET, 3)
    slider:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    slider:SetSize(ROW_WIDTH - CONTROL_OFFSET, 26)

    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter or tostring)
    slider:Init(getter(), options.minValue, options.maxValue, options.steps, options.formatters)
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if row._suspend then
            return
        end

        setter(value)
        SettingsUI.RefreshControls()
    end)

    row.Refresh = function()
        row._suspend = true
        local value = getter()
        if slider.SetValue then
            slider:SetValue(value)
        else
            slider:Init(value, options.minValue, options.maxValue, options.steps, options.formatters)
        end
        row._suspend = false
    end

    row.SetEnabled = function(self, enabled)
        enabled = enabled ~= false
        self:SetAlpha(enabled and 1 or 0.45)

        if slider.SetEnabled then
            slider:SetEnabled(enabled)
        end
        if slider.EnableMouse then
            slider:EnableMouse(enabled)
        end
        if slider.Slider and slider.Slider.SetEnabled then
            slider.Slider:SetEnabled(enabled)
        end

        for _, child in ipairs({ slider:GetChildren() }) do
            if child.SetEnabled then
                child:SetEnabled(enabled)
            end
            if child.EnableMouse then
                child:EnableMouse(enabled)
            end
        end
    end

    row.Control = slider
    return TrackRefreshable(row)
end

local function GetDropdownSelectedText(options, value)
    for _, entry in ipairs(options) do
        if entry.value == value then
            return entry.text
        end
    end
end

local function CreateDropdownRow(parent, labelText, optionsProvider, getter, setter, selectedTextProvider)
    local row = CreateFrame("Frame", NextFrameName("Settings", "DropdownRow"), parent)
    row:SetSize(ROW_WIDTH, 56)

    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Label:SetJustifyH("LEFT")
    row.Label:SetText(labelText)
    row.Label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.Label:SetWidth(LABEL_WIDTH)

    if MenuUtil and MenuUtil.CreateRadioMenu then
        local dropdown = CreateFrame("DropdownButton", NextFrameName("Settings", "Dropdown"), row, "WowStyle1DropdownTemplate")
        dropdown:SetPoint("TOPLEFT", row.Label, "BOTTOMLEFT", -2, -8)
        dropdown:SetWidth(MODERN_DROPDOWN_WIDTH)
        dropdown:SetHeight(28)
        dropdown:SetupMenu(function(_, rootDescription)
            -- In restricted content, compositor attachment rectangles can be
            -- secret. Give every entry an explicit size so Blizzard_Menu does
            -- not need to perform arithmetic on those rectangles.
            if rootDescription.SetMinimumWidth then
                rootDescription:SetMinimumWidth(MODERN_DROPDOWN_WIDTH)
            end

            for _, entry in ipairs(optionsProvider()) do
                local optionText = entry.text
                local optionValue = entry.value
                local optionDescription = rootDescription:CreateRadio(optionText, function(selectedValue)
                    return selectedValue == getter()
                end, function()
                    setter(optionValue)
                    SettingsUI.RefreshControls()
                end, optionValue)

                if optionDescription and optionDescription.AddInitializer then
                    optionDescription:AddInitializer(function()
                        return MODERN_DROPDOWN_WIDTH, MODERN_DROPDOWN_ENTRY_HEIGHT
                    end)
                end
            end
        end)

        row.Refresh = function()
            local value = getter()
            local text = selectedTextProvider and selectedTextProvider(value)
                or GetDropdownSelectedText(optionsProvider(), value)
            if dropdown.OverrideText then
                dropdown:OverrideText(text or tostring(value or ""))
            elseif dropdown.Update then
                dropdown:Update()
            end
        end

        row.SetEnabled = function(self, enabled)
            enabled = enabled ~= false
            self:SetAlpha(enabled and 1 or 0.45)
            if dropdown.SetEnabled then
                dropdown:SetEnabled(enabled)
            end
            if dropdown.EnableMouse then
                dropdown:EnableMouse(enabled)
            end
        end

        row.Control = dropdown
        return TrackRefreshable(row)
    end

    local dropdown = CreateFrame("Frame", NextFrameName("Settings", "Dropdown"), row, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", row.Label, "BOTTOMLEFT", -16, -6)

    UIDropDownMenu_SetWidth(dropdown, 196)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        for _, entry in ipairs(optionsProvider()) do
            local optionText = entry.text
            local optionValue = entry.value
            local info = UIDropDownMenu_CreateInfo()
            info.text = optionText
            info.value = optionValue
            info.func = function()
                setter(optionValue)
                UIDropDownMenu_SetSelectedValue(dropdown, optionValue)
                UIDropDownMenu_SetText(dropdown, optionText)
                SettingsUI.RefreshControls()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    row.Refresh = function()
        local value = getter()
        UIDropDownMenu_SetSelectedValue(dropdown, value)
        local text = selectedTextProvider and selectedTextProvider(value)
            or GetDropdownSelectedText(optionsProvider(), value)
        UIDropDownMenu_SetText(dropdown, text or tostring(value or ""))
    end

    row.SetEnabled = function(self, enabled)
        enabled = enabled ~= false
        self:SetAlpha(enabled and 1 or 0.45)

        if enabled then
            UIDropDownMenu_EnableDropDown(dropdown)
        else
            UIDropDownMenu_DisableDropDown(dropdown)
        end
    end

    row.Control = dropdown
    return TrackRefreshable(row)
end

local function CreateColorRow(parent, labelText, getter, setter)
    local row = CreateFrame("Frame", NextFrameName("Settings", "ColorRow"), parent)
    row:SetSize(ROW_WIDTH, 36)

    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Label:SetJustifyH("LEFT")
    row.Label:SetText(labelText)
    row.Label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Label:SetWidth(LABEL_WIDTH)

    local swatch = CreateFrame("Button", NextFrameName("Settings", "ColorSwatch"), row)
    swatch:SetSize(25, 20)
    swatch:SetPoint("LEFT", row, "LEFT", CONTROL_OFFSET, 0)

    local border = swatch:CreateTexture(nil, "BORDER")
    border:SetColorTexture(0, 0, 0, 1)
    border:SetPoint("TOPLEFT", swatch, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 1, -1)
    swatch.Border = border

    local preview = swatch:CreateTexture(nil, "ARTWORK")
    preview:SetAllPoints()
    swatch.Preview = preview

    local highlight = swatch:CreateTexture(nil, "OVERLAY")
    highlight:SetColorTexture(1, 1, 1, 0.12)
    highlight:SetAllPoints()
    highlight:Hide()
    swatch.Highlight = highlight

    local function OpenPicker()
        local r, g, b = getter()

        local function UpdateColor(newR, newG, newB)
            setter(newR, newG, newB)
            SettingsUI.RefreshControls()
        end

        local function swatchFunc()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            UpdateColor(newR, newG, newB)
        end

        local function cancelFunc(previousValues)
            if previousValues then
                UpdateColor(previousValues.r, previousValues.g, previousValues.b)
            end
        end

        ColorPickerFrame.previousValues = { r = r, g = g, b = b, a = 1 }
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r,
            g = g,
            b = b,
            hasOpacity = false,
            swatchFunc = swatchFunc,
            cancelFunc = cancelFunc,
        })
    end

    swatch:SetScript("OnClick", OpenPicker)
    swatch:SetScript("OnEnter", function(self)
        self.Border:SetColorTexture(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 1)
        self.Highlight:Show()
    end)
    swatch:SetScript("OnLeave", function(self)
        self.Border:SetColorTexture(0, 0, 0, 1)
        self.Highlight:Hide()
    end)

    row.Refresh = function()
        local r, g, b = getter()
        swatch.Preview:SetColorTexture(r, g, b, 1)
    end

    row.SetEnabled = function(self, enabled)
        enabled = enabled ~= false
        self:SetAlpha(enabled and 1 or 0.45)
        swatch:EnableMouse(enabled)
        if not enabled then
            swatch.Border:SetColorTexture(0, 0, 0, 1)
            swatch.Highlight:Hide()
        end
    end

    row.Control = swatch
    return TrackRefreshable(row)
end

local function CreatePage(parent, defaultContentHeight)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    page.defaultContentHeight = math.max(tonumber(defaultContentHeight) or DEFAULT_PAGE_CONTENT_HEIGHT, 10)

    local scrollFrame = CreateFrame("ScrollFrame", NextFrameName("Settings", "ScrollFrame"), page, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -SCROLLBAR_GUTTER, 0)

    local scrollGutter = page:CreateTexture(nil, "BACKGROUND")
    scrollGutter:SetPoint("TOPRIGHT", page, "TOPRIGHT", -1, -1)
    scrollGutter:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -1, 1)
    scrollGutter:SetWidth(SCROLLBAR_GUTTER - 4)
    scrollGutter:SetColorTexture(COLOR_TITLEBAR.r, COLOR_TITLEBAR.g, COLOR_TITLEBAR.b, 0.32)

    local scrollDivider = page:CreateTexture(nil, "BORDER")
    scrollDivider:SetPoint("TOPRIGHT", page, "TOPRIGHT", -(SCROLLBAR_GUTTER - 2), 0)
    scrollDivider:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -(SCROLLBAR_GUTTER - 2), 0)
    scrollDivider:SetWidth(1)
    scrollDivider:SetColorTexture(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.52)

    local scrollBar = scrollFrame.ScrollBar
    if not scrollBar and scrollFrame.GetName then
        scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
    end
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", page, "TOPRIGHT", SCROLLBAR_RIGHT_OFFSET, -SCROLLBAR_VERTICAL_INSET)
        scrollBar:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", SCROLLBAR_RIGHT_OFFSET, SCROLLBAR_VERTICAL_INSET)
    end

    local function UpdateScrollChrome()
        local range = scrollFrame.GetVerticalScrollRange and AsSafeNumber(scrollFrame:GetVerticalScrollRange()) or nil
        local shouldShow = range == nil or range > 0.5
        scrollGutter:SetShown(shouldShow)
        scrollDivider:SetShown(shouldShow)
        if scrollBar then
            scrollBar:SetShown(shouldShow)
        end
    end

    local content = CreateFrame("Frame", NextFrameName("Settings", "ContentFrame"), scrollFrame)
    content:SetSize(PAGE_WIDTH, page.defaultContentHeight)
    scrollFrame:SetScrollChild(content)

    page.scrollFrame = scrollFrame
    page.content = content
    page.ResetScroll = function()
        scrollFrame:SetVerticalScroll(0)
    end
    page.UpdateHeight = function()
        local top = AsSafeNumber(content:GetTop())
        if not top then
            content:SetHeight(page.defaultContentHeight)
            if scrollFrame.UpdateScrollChildRect then
                scrollFrame:UpdateScrollChildRect()
            end
            UpdateScrollChrome()
            return
        end

        for _, child in ipairs({ content:GetChildren() }) do
            if child:IsShown() and child.UpdateLayout then
                child:UpdateLayout()
            end
        end

        local maxHeight = page.defaultContentHeight
        local foundPublicGeometry = false
        for _, child in ipairs({ content:GetChildren() }) do
            if child:IsShown() then
                local bottom = AsSafeNumber(child:GetBottom())
                local height = bottom and (top - bottom) or nil
                if height and height > maxHeight then
                    maxHeight = height
                end
                if height then
                    foundPublicGeometry = true
                end
            end
        end

        if foundPublicGeometry then
            content:SetHeight(math.max(page.defaultContentHeight, maxHeight + 24))
        else
            content:SetHeight(page.defaultContentHeight)
        end
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
        UpdateScrollChrome()
        C_Timer.After(0, function()
            if page:IsShown() then
                UpdateScrollChrome()
            end
        end)
    end

    page:HookScript("OnShow", function()
        C_Timer.After(0.01, function()
            page:ResetScroll()
            page.UpdateHeight()
        end)
    end)

    return page
end

local function CreatePageHeader(parent, titleText, descriptionText)
    local title = CreateTitle(parent, titleText, "TOPLEFT", parent, "TOPLEFT", PAGE_HORIZONTAL_INSET, -4)
    local description = CreateDescription(parent, descriptionText, "TOPLEFT", title, "BOTTOMLEFT", 0, -6, CARD_WIDTH)
    return title, description
end

local function GetAnchorPresetOptions()
    return {
        { value = "BELOW", text = S("UI_PRESET_BELOW") },
        { value = "ABOVE", text = S("UI_PRESET_ABOVE") },
        { value = "LEFT", text = S("UI_PRESET_LEFT") },
        { value = "RIGHT", text = S("UI_PRESET_RIGHT") },
        { value = "CENTER", text = S("UI_PRESET_CENTER") },
        { value = "ADVANCED", text = S("UI_PRESET_ADVANCED") },
    }
end

local function GetTextFontOptions()
    return Shared.GetTextFontOptions()
end

local function GetTextOutlineOptions()
    return Shared.GetTextOutlineOptions()
end

local function GetBasicAnchorOptions()
    return {
        { value = "TOP", text = S("UI_TOP") },
        { value = "BOTTOM", text = S("UI_BOTTOM") },
        { value = "LEFT", text = S("UI_LEFT") },
        { value = "RIGHT", text = S("UI_RIGHT") },
        { value = "CENTER", text = S("UI_CENTER") },
    }
end

local function GetIconLayoutOptions()
    return {
        { value = "HORIZONTAL", text = S("UI_LAYOUT_HORIZONTAL") },
        { value = "VERTICAL", text = S("UI_LAYOUT_VERTICAL") },
    }
end

local function GetGrowthOptions()
    local db = SettingsUI.EnsureDB()
    if Shared.NormalizeIconLayout(db.iconLayout) == "VERTICAL" then
        return {
            { value = "UP", text = S("UI_GROWTH_UP") },
            { value = "DOWN", text = S("UI_GROWTH_DOWN") },
        }
    end

    return {
        { value = "CENTER", text = S("UI_GROWTH_CENTER") },
        { value = "LEFT", text = S("UI_GROWTH_LEFT") },
        { value = "RIGHT", text = S("UI_GROWTH_RIGHT") },
    }
end

local function GetSelectedGrowthValue()
    local db = SettingsUI.EnsureDB()
    if Shared.NormalizeIconLayout(db.iconLayout) == "VERTICAL" then
        return Shared.NormalizeVerticalIconGrowth(db.iconVerticalGrowth)
    end

    return Shared.GetEffectiveHorizontalIconGrowthForValues(db.anchorPreset, db.iconGrowth)
end

local function SetSelectedGrowthValue(value)
    local db = SettingsUI.EnsureDB()
    if Shared.NormalizeIconLayout(db.iconLayout) == "VERTICAL" then
        db.iconVerticalGrowth = value
    else
        db.iconGrowth = value
    end

    SettingsUI.RefreshAll()
end

local function GetBorderStyleOptions()
    return {
        { value = "SOLID", text = S("UI_BORDER_STYLE_SOLID") },
        { value = "CLASSIC", text = S("UI_BORDER_STYLE_CLASSIC") },
        { value = "NONE", text = S("UI_BORDER_STYLE_NONE") },
    }
end

local function GetDRTextAnchorOptions()
    return {
        { value = "TOPLEFT", text = S("UI_TOP_LEFT") },
        { value = "TOP", text = S("UI_TOP") },
        { value = "TOPRIGHT", text = S("UI_TOP_RIGHT") },
        { value = "LEFT", text = S("UI_LEFT") },
        { value = "CENTER", text = S("UI_CENTER") },
        { value = "RIGHT", text = S("UI_RIGHT") },
        { value = "BOTTOMLEFT", text = S("UI_BOTTOM_LEFT") },
        { value = "BOTTOM", text = S("UI_BOTTOM") },
        { value = "BOTTOMRIGHT", text = S("UI_BOTTOM_RIGHT") },
    }
end

local function GetTrinketVisibilityOptions()
    return {
        { value = "COOLDOWN_ONLY", text = S("UI_TRINKET_VISIBILITY_COOLDOWN_ONLY") },
        { value = "ALWAYS", text = S("UI_TRINKET_VISIBILITY_ALWAYS") },
    }
end

local function GetTrinketBorderStyleOptions()
    return {
        { value = "SOLID", text = S("UI_BORDER_STYLE_SOLID") },
        { value = "CLASSIC", text = S("UI_BORDER_STYLE_CLASSIC") },
        { value = "NONE", text = S("UI_BORDER_STYLE_NONE") },
    }
end

local function CreateBlizzardDRCard(parent)
    local card = CreateCard(parent, S("UI_BLIZZARD_DR_FRAMES_TITLE"), S("UI_BLIZZARD_DR_FRAMES_HELP"), 144)

    controls.blizzardDREnemiesEnabledRow = CreateCheckboxRow(
        card,
        S("UI_SHOW_BLIZZARD_ARENA_DR_FRAMES"),
        function()
            return GetBlizzardDRCVarBool("enemiesEnabled")
        end,
        function(value)
            SetBlizzardDRCVarBool("enemiesEnabled", value)
        end
    )
    controls.blizzardDREnemiesEnabledRow:SetPoint("TOPLEFT", card.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.blizzardDREnemiesEnabledRow,
        "Turns Blizzard's built-in enemy arena-frame DR indicators on or off. ArenaDR nameplate icons still use this addon's settings."
    )

    controls.blizzardDROnlyTriggerableByMeRow = CreateCheckboxRow(
        card,
        S("UI_ONLY_SHOW_TRIGGERABLE_DR_CATEGORIES"),
        function()
            return GetBlizzardDRCVarBool("onlyTriggerableByMe")
        end,
        function(value)
            SetBlizzardDRCVarBool("onlyTriggerableByMe", value)
        end
    )
    AnchorBelow(controls.blizzardDROnlyTriggerableByMeRow, controls.blizzardDREnemiesEnabledRow, 8)
    AttachRowTooltip(
        controls.blizzardDROnlyTriggerableByMeRow,
        "Hides DR categories your character cannot personally cause, so Blizzard's arena frames focus on crowd control you can apply."
    )

    return card
end

local function CreateGeneralPage(parent)
    local page = CreatePage(parent, 1254)
    local content = page.content

    local _, description = CreatePageHeader(content, S("UI_MAIN_HEADER"), S("UI_MAIN_SUBHEADER"))

    TrackRefreshable({
        Refresh = function()
            local isTestModeActive = _G.ArenaDRNameplates_IsTestModeActive and _G.ArenaDRNameplates_IsTestModeActive()
            if controls.previewButton then
                controls.previewButton:SetText(isTestModeActive and S("UI_STOP_PREVIEW_BUTTON") or S("UI_PREVIEW_BUTTON"))
            end
            if controls.launcherPreviewButton then
                controls.launcherPreviewButton:SetText(isTestModeActive and S("UI_STOP_PREVIEW_BUTTON") or S("UI_PREVIEW_BUTTON"))
            end
        end,
    })

    local blizzardDRCard = CreateBlizzardDRCard(content)
    blizzardDRCard:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)

    local textAppearanceCard = CreateCard(
        content,
        S("UI_TEXT_APPEARANCE_TITLE"),
        S("UI_TEXT_APPEARANCE_HELP"),
        214
    )
    AnchorBelow(textAppearanceCard, blizzardDRCard, 14)

    controls.textFontRow = CreateDropdownRow(
        textAppearanceCard,
        S("UI_TEXT_FONT"),
        GetTextFontOptions,
        function()
            local db = SettingsUI.EnsureDB()
            return Shared.GetTextFontDropdownValue(db.textFont)
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.textFont = value
            SettingsUI.RefreshAll()
        end,
        function()
            local db = SettingsUI.EnsureDB()
            return Shared.GetTextFontDisplayText(db.textFont)
        end
    )
    controls.textFontRow:SetPoint("TOPLEFT", textAppearanceCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(controls.textFontRow, S("UI_TEXT_FONT_HELP"))

    controls.textOutlineRow = CreateDropdownRow(
        textAppearanceCard,
        S("UI_TEXT_OUTLINE"),
        GetTextOutlineOptions,
        function()
            local db = SettingsUI.EnsureDB()
            return Shared.NormalizeTextOutline(db.textOutline)
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.textOutline = Shared.NormalizeTextOutline(value)
            SettingsUI.RefreshAll()
        end,
        function()
            local db = SettingsUI.EnsureDB()
            return Shared.GetTextOutlineDisplayText(db.textOutline)
        end
    )
    AnchorBelow(controls.textOutlineRow, controls.textFontRow, 8)
    AttachRowTooltip(controls.textOutlineRow, S("UI_TEXT_OUTLINE_HELP"))

    local displayCard = CreateCard(content, S("UI_DR_ICONS_TITLE"), S("UI_DR_ICONS_HELP"), 286)
    AnchorBelow(displayCard, textAppearanceCard, 14)

    controls.scaleRow = CreateSliderRow(
        displayCard,
        S("UI_ICON_SIZE"),
        0.5,
        3.0,
        0.1,
        function(value)
            return string.format("%.1fx", value)
        end,
        function()
            return SettingsUI.EnsureDB().scale
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.scale = value
            SettingsUI.RefreshAll()
        end
    )
    controls.scaleRow:SetPoint("TOPLEFT", displayCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.scaleRow,
        "Changes the size of every DR icon. Use Preview in the footer to check readability on nearby enemy nameplates."
    )

    controls.scaleWithNameplateRow = CreateCheckboxRow(
        displayCard,
        S("UI_SCALE_WITH_NAMEPLATE"),
        function()
            return SettingsUI.EnsureDB().scaleWithNameplate
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.scaleWithNameplate = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.scaleWithNameplateRow, controls.scaleRow, 8)
    AttachRowTooltip(
        controls.scaleWithNameplateRow,
        "When enabled, target and off-target nameplate scale changes also resize the DR tray. Turn it off to keep DR icons visually consistent between nameplates."
    )

    controls.opacityRow = CreateSliderRow(
        displayCard,
        S("UI_ICON_OPACITY"),
        0.1,
        1.0,
        0.05,
        function(value)
            return string.format("%d%%", value * 100)
        end,
        function()
            return SettingsUI.EnsureDB().opacity
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.opacity = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.opacityRow, controls.scaleWithNameplateRow, 8)
    AttachRowTooltip(
        controls.opacityRow,
        "Lowers or raises icon transparency without changing their size. Useful if the tray feels too dominant on the nameplate."
    )

    controls.iconPaddingRow = CreateSliderRow(
        displayCard,
        S("UI_ICON_PADDING"),
        0,
        20,
        0.5,
        function(value)
            return string.format("%.1f", value)
        end,
        function()
            return SettingsUI.EnsureDB().iconPadding
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.iconPadding = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.iconPaddingRow, controls.opacityRow, 8)
    AttachRowTooltip(
        controls.iconPaddingRow,
        "Adds or removes space between icons. Extra spacing can make overlapping DR categories easier to read at a glance."
    )

    controls.iconLayoutRow = CreateDropdownRow(
        displayCard,
        S("UI_ICON_LAYOUT"),
        GetIconLayoutOptions,
        function()
            return SettingsUI.EnsureDB().iconLayout
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.iconLayout = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.iconLayoutRow, controls.iconPaddingRow, 8)
    AttachRowTooltip(
        controls.iconLayoutRow,
        "Switches between the original horizontal tray and a vertical stack. Vertical mode enables its own growth order control."
    )

    local placementCard = CreateCard(content, S("UI_ICON_POSITION_TITLE"), S("UI_ICON_POSITION_HELP"), 296)
    AnchorBelow(placementCard, displayCard, 14)

    controls.presetRow = CreateDropdownRow(
        placementCard,
        S("UI_POSITION_PRESET"),
        GetAnchorPresetOptions,
        function()
            return SettingsUI.EnsureDB().anchorPreset
        end,
        function(value)
            SettingsUI.ApplyAnchorPreset(value)
        end
    )
    controls.presetRow:SetPoint("TOPLEFT", placementCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.presetRow,
        "Start with a preset for fast placement. Choose Custom only when the preset positions are close but not precise enough."
    )

    controls.offsetXRow = CreateSliderRow(
        placementCard,
        S("UI_HORIZONTAL_OFFSET"),
        -150,
        150,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return SettingsUI.EnsureDB().offsetX
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.offsetX = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.offsetXRow, controls.presetRow, 8)

    controls.offsetYRow = CreateSliderRow(
        placementCard,
        S("UI_VERTICAL_OFFSET"),
        -150,
        150,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return SettingsUI.EnsureDB().offsetY
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.offsetY = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.offsetYRow, controls.offsetXRow, 8)

    controls.growthRow = CreateDropdownRow(
        placementCard,
        S("UI_ICON_GROWTH"),
        GetGrowthOptions,
        GetSelectedGrowthValue,
        SetSelectedGrowthValue
    )
    AnchorBelow(controls.growthRow, controls.offsetYRow, 8)
    AttachRowTooltip(
        controls.growthRow,
        function()
            local db = SettingsUI.EnsureDB()
            if Shared.NormalizeIconLayout(db.iconLayout) == "VERTICAL" then
                return "Controls whether the vertical stack expands upward or downward. The tray now anchors from the matching edge so the stack grows from the correct fixed side."
            end

            return "Controls how the tray expands when several DR categories are active at once. Horizontal presets handle this automatically, so switch to Custom if you want to override it."
        end
    )

    local advancedCard = CreateCard(content, S("UI_CUSTOM_ANCHOR_TITLE"), S("UI_CUSTOM_ANCHOR_HELP"), 164)
    AnchorBelow(advancedCard, placementCard, 14)
    controls.advancedCard = advancedCard

    controls.pointRow = CreateDropdownRow(
        advancedCard,
        S("UI_ICONS_ANCHOR_POINT"),
        GetBasicAnchorOptions,
        function()
            return SettingsUI.EnsureDB().point
        end,
        function(value)
            SettingsUI.ApplyAdvancedAnchor(value, SettingsUI.EnsureDB().relativePoint)
        end
    )
    controls.pointRow:SetPoint("TOPLEFT", advancedCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.pointRow,
        "Sets which point of the DR icon tray is used as the anchor when you switch to Custom positioning."
    )

    controls.relativePointRow = CreateDropdownRow(
        advancedCard,
        S("UI_ATTACH_TO"),
        GetBasicAnchorOptions,
        function()
            return SettingsUI.EnsureDB().relativePoint
        end,
        function(value)
            SettingsUI.ApplyAdvancedAnchor(SettingsUI.EnsureDB().point, value)
        end
    )
    AnchorBelow(controls.relativePointRow, controls.pointRow, 8)
    AttachRowTooltip(
        controls.relativePointRow,
        "Sets which point on the enemy nameplate the tray attaches to. Combine it with offsets for exact placement."
    )

    return page
end

local function CreateTrinketPage(parent)
    local page = CreatePage(parent, 900)
    local content = page.content

    local _, description = CreatePageHeader(content, S("UI_TRINKET_HEADER"), S("UI_TRINKET_SUBHEADER"))

    local featureCard = CreateCard(content, S("UI_TRINKET_FEATURE_TITLE"), S("UI_TRINKET_FEATURE_HELP"), 140)
    featureCard:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)

    controls.trinketEnabledRow = CreateCheckboxRow(
        featureCard,
        S("UI_ENABLE_TRINKET"),
        function()
            return SettingsUI.EnsureDB().trinket.enabled
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.trinket.enabled = value
            SettingsUI.RefreshAll()
        end
    )
    controls.trinketEnabledRow:SetPoint("TOPLEFT", featureCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.trinketEnabledRow,
        "Shows the enemy crowd-control remover cooldown on the mapped arena nameplate. This feature is disabled by default to keep the default layout clean."
    )

    controls.trinketVisibilityRow = CreateDropdownRow(
        featureCard,
        S("UI_TRINKET_VISIBILITY"),
        GetTrinketVisibilityOptions,
        function()
            return SettingsUI.EnsureDB().trinket.visibility
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.trinket.visibility = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.trinketVisibilityRow, controls.trinketEnabledRow, 8)
    AttachRowTooltip(
        controls.trinketVisibilityRow,
        "Cooldown only reduces clutter and shows the icon only while the enemy trinket is unavailable. Always keeps the icon visible even when it is ready."
    )

    local appearanceCard = CreateCard(content, S("UI_TRINKET_APPEARANCE_TITLE"), S("UI_TRINKET_APPEARANCE_HELP"), 140)
    AnchorBelow(appearanceCard, featureCard, 14)

    controls.trinketSizeRow = CreateSliderRow(
        appearanceCard,
        S("UI_ICON_SIZE"),
        12,
        80,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return SettingsUI.EnsureDB().trinket.size
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.trinket.size = value
            SettingsUI.RefreshAll()
        end
    )
    controls.trinketSizeRow:SetPoint("TOPLEFT", appearanceCard.Divider, "BOTTOMLEFT", 0, -14)

    controls.trinketOpacityRow = CreateSliderRow(
        appearanceCard,
        S("UI_ICON_OPACITY"),
        0.1,
        1.0,
        0.05,
        function(value)
            return string.format("%d%%", value * 100)
        end,
        function()
            return SettingsUI.EnsureDB().trinket.opacity
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.trinket.opacity = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.trinketOpacityRow, controls.trinketSizeRow, 8)
    AttachRowTooltip(
        controls.trinketOpacityRow,
        "Adjusts the trinket icon transparency without changing the main DR tray. Countdown swipe and timer styling are shared with the Timers tab."
    )

    local borderCard = CreateCard(content, S("UI_TRINKET_BORDER_TITLE"), S("UI_TRINKET_BORDER_HELP"), 190)
    AnchorBelow(borderCard, appearanceCard, 14)

    controls.trinketBorderStyleRow = CreateDropdownRow(
        borderCard,
        S("UI_BORDER_STYLE"),
        GetTrinketBorderStyleOptions,
        function()
            return SettingsUI.EnsureDB().trinket.borderStyle
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.trinket.borderStyle = value
            SettingsUI.RefreshAll()
        end
    )
    controls.trinketBorderStyleRow:SetPoint("TOPLEFT", borderCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.trinketBorderStyleRow,
        "Solid keeps a visible outline around the trinket icon. None removes the border completely."
    )

    controls.trinketBorderWidthRow = CreateSliderRow(
        borderCard,
        S("UI_BORDER_WIDTH"),
        1,
        8,
        0.5,
        function(value)
            return string.format("%.1f", value)
        end,
        function()
            return SettingsUI.EnsureDB().trinket.borderWidth
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.trinket.borderWidth = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.trinketBorderWidthRow, controls.trinketBorderStyleRow, 8)
    AttachRowTooltip(
        controls.trinketBorderWidthRow,
        "Makes the trinket border thinner or thicker without changing the icon size."
    )

    controls.trinketBorderColorRow = CreateColorRow(
        borderCard,
        S("UI_BORDER_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                SettingsUI.EnsureDB().trinket.borderColor,
                defaults.trinket.borderColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            local db = SettingsUI.EnsureDB()
            db.trinket.borderColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.trinketBorderColorRow, controls.trinketBorderWidthRow, 8)

    local positionCard = CreateCard(content, S("UI_TRINKET_POSITION_TITLE"), S("UI_TRINKET_POSITION_HELP"), 214)
    AnchorBelow(positionCard, borderCard, 14)

    controls.trinketPresetRow = CreateDropdownRow(
        positionCard,
        S("UI_POSITION_PRESET"),
        GetAnchorPresetOptions,
        function()
            return SettingsUI.EnsureDB().trinket.anchorPreset
        end,
        function(value)
            SettingsUI.ApplyTrinketAnchorPreset(value)
        end
    )
    controls.trinketPresetRow:SetPoint("TOPLEFT", positionCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.trinketPresetRow,
        "Start with a preset, then use offsets to land the trinket exactly where you want it around the nameplate."
    )

    controls.trinketOffsetXRow = CreateSliderRow(
        positionCard,
        S("UI_HORIZONTAL_OFFSET"),
        -150,
        150,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return SettingsUI.EnsureDB().trinket.offsetX
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.trinket.offsetX = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.trinketOffsetXRow, controls.trinketPresetRow, 8)

    controls.trinketOffsetYRow = CreateSliderRow(
        positionCard,
        S("UI_VERTICAL_OFFSET"),
        -150,
        150,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return SettingsUI.EnsureDB().trinket.offsetY
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.trinket.offsetY = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.trinketOffsetYRow, controls.trinketOffsetXRow, 8)

    local advancedCard = CreateCard(content, S("UI_CUSTOM_ANCHOR_TITLE"), S("UI_TRINKET_CUSTOM_ANCHOR_HELP"), 164)
    AnchorBelow(advancedCard, positionCard, 14)
    controls.trinketAdvancedCard = advancedCard

    controls.trinketPointRow = CreateDropdownRow(
        advancedCard,
        S("UI_ICONS_ANCHOR_POINT"),
        GetBasicAnchorOptions,
        function()
            return SettingsUI.EnsureDB().trinket.point
        end,
        function(value)
            SettingsUI.ApplyAdvancedTrinketAnchor(value, SettingsUI.EnsureDB().trinket.relativePoint)
        end
    )
    controls.trinketPointRow:SetPoint("TOPLEFT", advancedCard.Divider, "BOTTOMLEFT", 0, -14)

    controls.trinketRelativePointRow = CreateDropdownRow(
        advancedCard,
        S("UI_ATTACH_TO"),
        GetBasicAnchorOptions,
        function()
            return SettingsUI.EnsureDB().trinket.relativePoint
        end,
        function(value)
            SettingsUI.ApplyAdvancedTrinketAnchor(SettingsUI.EnsureDB().trinket.point, value)
        end
    )
    AnchorBelow(controls.trinketRelativePointRow, controls.trinketPointRow, 8)

    return page
end

local function GetSelfDRSettings()
    return SettingsUI.EnsureDB().selfDR
end

local function GetSelfDRTimers()
    return SettingsUI.EnsureDB().selfDR.timers
end

local function GetSelfDRText()
    return SettingsUI.EnsureDB().selfDR.drText
end

local function GetSelfDRGrowthOptions()
    local settings = GetSelfDRSettings()
    if Shared.NormalizeIconLayout(settings.iconLayout) == "VERTICAL" then
        return {
            { value = "UP", text = S("UI_GROWTH_UP") },
            { value = "DOWN", text = S("UI_GROWTH_DOWN") },
        }
    end

    return {
        { value = "CENTER", text = S("UI_GROWTH_CENTER") },
        { value = "LEFT", text = S("UI_GROWTH_LEFT") },
        { value = "RIGHT", text = S("UI_GROWTH_RIGHT") },
    }
end

local function GetSelfDRGrowthValue()
    local settings = GetSelfDRSettings()
    if Shared.NormalizeIconLayout(settings.iconLayout) == "VERTICAL" then
        return Shared.NormalizeVerticalIconGrowth(settings.iconVerticalGrowth)
    end
    return Shared.NormalizeIconGrowth(settings.iconGrowth)
end

local function SetSelfDRGrowthValue(value)
    local settings = GetSelfDRSettings()
    if Shared.NormalizeIconLayout(settings.iconLayout) == "VERTICAL" then
        settings.iconVerticalGrowth = value
    else
        settings.iconGrowth = value
    end
    SettingsUI.RefreshAll()
end

local function CreateSelfDRPage(parent)
    local page = CreatePage(parent, 1780)
    local content = page.content

    local _, description = CreatePageHeader(content, S("UI_SELFDR_HEADER"), S("UI_SELFDR_SUBHEADER"))

    local featureCard = CreateCard(content, S("UI_SELFDR_FEATURE_TITLE"), S("UI_SELFDR_FEATURE_HELP"), 180)
    featureCard:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)

    controls.selfDREnabledRow = CreateCheckboxRow(
        featureCard,
        S("UI_SELFDR_ENABLE"),
        function()
            return GetSelfDRSettings().enabled
        end,
        function(value)
            GetSelfDRSettings().enabled = value
            SettingsUI.RefreshAll()
        end
    )
    SetCompactCheckboxWidth(controls.selfDREnabledRow, math.floor(ROW_WIDTH / 2))
    controls.selfDREnabledRow:SetPoint("TOPLEFT", featureCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.selfDREnabledRow,
        "Shows a personal bar with the diminishing returns currently applied to you, so you can tell when you are immune to a category."
    )

    controls.selfDRLockedRow = CreateCheckboxRow(
        featureCard,
        S("UI_SELFDR_LOCK"),
        function()
            return GetSelfDRSettings().locked
        end,
        function(value)
            GetSelfDRSettings().locked = value
            SettingsUI.RefreshAll()
        end
    )
    SetCompactCheckboxWidth(controls.selfDRLockedRow, math.floor(ROW_WIDTH / 2))
    controls.selfDRLockedRow:SetPoint("LEFT", controls.selfDREnabledRow, "RIGHT", 0, 0)
    AttachRowTooltip(
        controls.selfDRLockedRow,
        "While unlocked the bar stays on screen and can be dragged with the mouse, even when no diminishing return is running."
    )

    -- "Show in:" followed by the three zone toggles on a single line.
    local zoneLabel = featureCard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    zoneLabel:SetPoint("TOPLEFT", controls.selfDREnabledRow, "BOTTOMLEFT", 0, -12)
    zoneLabel:SetText(S("UI_SELFDR_SHOW_IN"))
    zoneLabel:SetJustifyH("LEFT")
    controls.selfDRZoneLabel = zoneLabel

    local zoneDefinitions = {
        { control = "selfDRArenaRow", key = "showInArena", label = "UI_SELFDR_ZONE_ARENA" },
        { control = "selfDRBattlegroundRow", key = "showInBattleground", label = "UI_SELFDR_ZONE_BATTLEGROUND" },
        { control = "selfDRWorldRow", key = "showInWorld", label = "UI_SELFDR_ZONE_WORLD" },
    }

    local zoneColumnWidth = math.floor((ROW_WIDTH - ZONE_LABEL_WIDTH) / #zoneDefinitions)
    local previousZone
    for _, zone in ipairs(zoneDefinitions) do
        local settingKey = zone.key
        local row = CreateCheckboxRow(
            featureCard,
            S(zone.label),
            function()
                return GetSelfDRSettings()[settingKey]
            end,
            function(value)
                GetSelfDRSettings()[settingKey] = value
                SettingsUI.RefreshAll()
            end
        )
        SetCompactCheckboxWidth(row, zoneColumnWidth)

        if previousZone then
            row:SetPoint("LEFT", previousZone, "RIGHT", 0, 0)
        else
            row:SetPoint("LEFT", zoneLabel, "RIGHT", 10, 0)
        end

        controls[zone.control] = row
        previousZone = row
    end

    AttachRowTooltip(
        controls.selfDRWorldRow,
        "Covers everything that is not an arena or a battleground, including world PvP and duels."
    )

    local categoryCard = CreateCard(content, S("UI_SELFDR_CATEGORIES_TITLE"), S("UI_SELFDR_CATEGORIES_HELP"), 150)
    AnchorBelow(categoryCard, featureCard, 14)

    -- Six categories laid out on two rows of three rather than one tall stack.
    controls.selfDRCategoryRows = {}
    local categoryColumns = 3
    local categoryColumnWidth = math.floor(ROW_WIDTH / categoryColumns)
    local firstInPreviousRow
    for index, category in ipairs(Shared.selfDRCategories) do
        local trackedCategory = category
        local row = CreateCheckboxRow(
            categoryCard,
            S(ns.SelfDR.categoryLocaleKeys[trackedCategory]),
            function()
                return GetSelfDRSettings().track[trackedCategory]
            end,
            function(value)
                GetSelfDRSettings().track[trackedCategory] = value
                SettingsUI.RefreshAll()
            end
        )
        SetCompactCheckboxWidth(row, categoryColumnWidth)

        local column = (index - 1) % categoryColumns
        if column == 0 then
            if firstInPreviousRow then
                AnchorBelow(row, firstInPreviousRow, 8)
            else
                row:SetPoint("TOPLEFT", categoryCard.Divider, "BOTTOMLEFT", 0, -14)
            end
            firstInPreviousRow = row
        else
            row:SetPoint("LEFT", controls.selfDRCategoryRows[Shared.selfDRCategories[index - 1]], "RIGHT", 0, 0)
        end

        controls.selfDRCategoryRows[trackedCategory] = row
    end

    AttachRowTooltip(
        controls.selfDRCategoryRows.disarm,
        "Knockbacks are not listed because the Loss of Control API never reports them, so they cannot be tracked."
    )

    local appearanceCard = CreateCard(content, S("UI_SELFDR_APPEARANCE_TITLE"), S("UI_SELFDR_APPEARANCE_HELP"), 268)
    AnchorBelow(appearanceCard, categoryCard, 14)

    controls.selfDRSizeRow = CreateSliderRow(
        appearanceCard,
        S("UI_ICON_SIZE"),
        16,
        80,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return GetSelfDRSettings().size
        end,
        function(value)
            GetSelfDRSettings().size = value
            SettingsUI.RefreshAll()
        end
    )
    controls.selfDRSizeRow:SetPoint("TOPLEFT", appearanceCard.Divider, "BOTTOMLEFT", 0, -14)

    controls.selfDROpacityRow = CreateSliderRow(
        appearanceCard,
        S("UI_ICON_OPACITY"),
        0.1,
        1.0,
        0.05,
        function(value)
            return string.format("%d%%", value * 100)
        end,
        function()
            return GetSelfDRSettings().opacity
        end,
        function(value)
            GetSelfDRSettings().opacity = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDROpacityRow, controls.selfDRSizeRow, 8)

    controls.selfDRPaddingRow = CreateSliderRow(
        appearanceCard,
        S("UI_ICON_PADDING"),
        0,
        20,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return GetSelfDRSettings().iconPadding
        end,
        function(value)
            GetSelfDRSettings().iconPadding = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRPaddingRow, controls.selfDROpacityRow, 8)

    controls.selfDRLayoutRow = CreateDropdownRow(
        appearanceCard,
        S("UI_ICON_LAYOUT"),
        GetIconLayoutOptions,
        function()
            return GetSelfDRSettings().iconLayout
        end,
        function(value)
            GetSelfDRSettings().iconLayout = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    AnchorBelow(controls.selfDRLayoutRow, controls.selfDRPaddingRow, 8)

    controls.selfDRGrowthRow = CreateDropdownRow(
        appearanceCard,
        S("UI_ICON_GROWTH"),
        GetSelfDRGrowthOptions,
        GetSelfDRGrowthValue,
        SetSelfDRGrowthValue
    )
    AnchorBelow(controls.selfDRGrowthRow, controls.selfDRLayoutRow, 8)

    -- DR stage text follows the DR Text tab until the override is enabled.
    local textCard = CreateCard(content, S("UI_SELFDR_TEXT_TITLE"), S("UI_SELFDR_TEXT_HELP"), 112)
    AnchorBelow(textCard, appearanceCard, 14)

    controls.selfDRTextOverrideRow = CreateCheckboxRow(
        textCard,
        S("UI_SELFDR_TEXT_OVERRIDE"),
        function()
            return GetSelfDRText().override
        end,
        function(value)
            GetSelfDRText().override = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    controls.selfDRTextOverrideRow:SetPoint("TOPLEFT", textCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.selfDRTextOverrideRow,
        "Off, the personal bar uses everything from the DR Text tab. On, the settings below apply to the personal bar only."
    )

    controls.selfDRDRTextRow = CreateCheckboxRow(
        textCard,
        S("UI_SHOW_DR_STATE_TEXT"),
        function()
            return GetSelfDRText().showDRText
        end,
        function(value)
            GetSelfDRText().showDRText = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    AnchorBelow(controls.selfDRDRTextRow, controls.selfDRTextOverrideRow, 8)
    AttachRowTooltip(
        controls.selfDRDRTextRow,
        "Shows the next reduction on the icon: a half glyph, then the immune marker once the category no longer lands."
    )

    controls.selfDRTextAnchorRow = CreateDropdownRow(
        textCard,
        S("UI_TEXT_ANCHOR"),
        GetDRTextAnchorOptions,
        function()
            return GetSelfDRText().drTextAnchor
        end,
        function(value)
            GetSelfDRText().drTextAnchor = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTextAnchorRow, controls.selfDRDRTextRow, 8)

    controls.selfDRTextScaleRow = CreateSliderRow(
        textCard,
        S("UI_TEXT_SIZE"),
        0.5,
        3.0,
        0.05,
        function(value)
            return string.format("%.2fx", value)
        end,
        function()
            return GetSelfDRText().drTextScale
        end,
        function(value)
            GetSelfDRText().drTextScale = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTextScaleRow, controls.selfDRTextAnchorRow, 8)

    controls.selfDRTextOffsetXRow = CreateSliderRow(
        textCard,
        S("UI_HORIZONTAL_OFFSET"),
        -50,
        50,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return GetSelfDRText().drTextOffsetX
        end,
        function(value)
            GetSelfDRText().drTextOffsetX = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTextOffsetXRow, controls.selfDRTextScaleRow, 8)

    controls.selfDRTextOffsetYRow = CreateSliderRow(
        textCard,
        S("UI_VERTICAL_OFFSET"),
        -50,
        50,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return GetSelfDRText().drTextOffsetY
        end,
        function(value)
            GetSelfDRText().drTextOffsetY = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTextOffsetYRow, controls.selfDRTextOffsetXRow, 8)

    controls.selfDRTextColorRow = CreateColorRow(
        textCard,
        S("UI_DR_TEXT_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                GetSelfDRText().drTextColor,
                defaults.selfDR.drText.drTextColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            GetSelfDRText().drTextColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTextColorRow, controls.selfDRTextOffsetYRow, 8)

    controls.selfDRTextImmuneColorRow = CreateColorRow(
        textCard,
        S("UI_IMMUNE_TEXT_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                GetSelfDRText().drTextImmuneColor,
                defaults.selfDR.drText.drTextImmuneColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            GetSelfDRText().drTextImmuneColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTextImmuneColorRow, controls.selfDRTextColorRow, 8)

    -- Timer styling follows the Timers tab until the override is enabled.
    local timerCard = CreateCard(content, S("UI_SELFDR_TIMERS_TITLE"), S("UI_SELFDR_TIMERS_HELP"), 112)
    AnchorBelow(timerCard, textCard, 14)

    controls.selfDRTimerOverrideRow = CreateCheckboxRow(
        timerCard,
        S("UI_SELFDR_TIMERS_OVERRIDE"),
        function()
            return GetSelfDRTimers().override
        end,
        function(value)
            GetSelfDRTimers().override = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    controls.selfDRTimerOverrideRow:SetPoint("TOPLEFT", timerCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.selfDRTimerOverrideRow,
        "Off, the personal bar uses everything from the Timers tab. On, the settings below apply to the personal bar only."
    )

    controls.selfDRTimerSwipeRow = CreateCheckboxRow(
        timerCard,
        S("UI_SHOW_TIMER_SWIPE"),
        function()
            return GetSelfDRTimers().showTimerSwipe
        end,
        function(value)
            GetSelfDRTimers().showTimerSwipe = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    SetCompactCheckboxWidth(controls.selfDRTimerSwipeRow, math.floor(ROW_WIDTH / 2))
    AnchorBelow(controls.selfDRTimerSwipeRow, controls.selfDRTimerOverrideRow, 8)

    controls.selfDRTimerSwipeEdgeRow = CreateCheckboxRow(
        timerCard,
        S("UI_SHOW_TIMER_SWIPE_EDGE"),
        function()
            return GetSelfDRTimers().showTimerSwipeEdge
        end,
        function(value)
            GetSelfDRTimers().showTimerSwipeEdge = value
            SettingsUI.RefreshAll()
        end
    )
    SetCompactCheckboxWidth(controls.selfDRTimerSwipeEdgeRow, math.floor(ROW_WIDTH / 2))
    controls.selfDRTimerSwipeEdgeRow:SetPoint("LEFT", controls.selfDRTimerSwipeRow, "RIGHT", 0, 0)

    controls.selfDRTimerTextRow = CreateCheckboxRow(
        timerCard,
        S("UI_SHOW_TIMER_TEXT"),
        function()
            return GetSelfDRTimers().showTimerText
        end,
        function(value)
            GetSelfDRTimers().showTimerText = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    SetCompactCheckboxWidth(controls.selfDRTimerTextRow, math.floor(ROW_WIDTH / 2))
    AnchorBelow(controls.selfDRTimerTextRow, controls.selfDRTimerSwipeRow, 8)

    controls.selfDRTimerDecimalsRow = CreateCheckboxRow(
        timerCard,
        S("UI_SHOW_TIMER_DECIMALS"),
        function()
            return GetSelfDRTimers().showTimerDecimals
        end,
        function(value)
            GetSelfDRTimers().showTimerDecimals = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    SetCompactCheckboxWidth(controls.selfDRTimerDecimalsRow, math.floor(ROW_WIDTH / 2))
    controls.selfDRTimerDecimalsRow:SetPoint("LEFT", controls.selfDRTimerTextRow, "RIGHT", 0, 0)

    controls.selfDRTimerThresholdRow = CreateSliderRow(
        timerCard,
        S("UI_TIMER_DECIMAL_THRESHOLD"),
        1,
        20,
        1,
        function(value)
            return string.format("%ds", math.floor(value))
        end,
        function()
            return GetSelfDRTimers().timerDecimalThreshold
        end,
        function(value)
            GetSelfDRTimers().timerDecimalThreshold = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTimerThresholdRow, controls.selfDRTimerTextRow, 8)

    controls.selfDRTimerScaleRow = CreateSliderRow(
        timerCard,
        S("UI_TEXT_SIZE"),
        0.5,
        2.0,
        0.05,
        function(value)
            return string.format("%.2f", value)
        end,
        function()
            return GetSelfDRTimers().timerTextScale
        end,
        function(value)
            GetSelfDRTimers().timerTextScale = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTimerScaleRow, controls.selfDRTimerThresholdRow, 8)

    controls.selfDRTimerColorRow = CreateColorRow(
        timerCard,
        S("UI_TEXT_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                GetSelfDRTimers().timerTextColor,
                defaults.selfDR.timers.timerTextColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            GetSelfDRTimers().timerTextColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTimerColorRow, controls.selfDRTimerScaleRow, 8)

    controls.selfDRTimerOffsetXRow = CreateSliderRow(
        timerCard,
        S("UI_HORIZONTAL_OFFSET"),
        -50,
        50,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return GetSelfDRTimers().timerTextOffsetX
        end,
        function(value)
            GetSelfDRTimers().timerTextOffsetX = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTimerOffsetXRow, controls.selfDRTimerColorRow, 8)

    controls.selfDRTimerOffsetYRow = CreateSliderRow(
        timerCard,
        S("UI_VERTICAL_OFFSET"),
        -50,
        50,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return GetSelfDRTimers().timerTextOffsetY
        end,
        function(value)
            GetSelfDRTimers().timerTextOffsetY = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRTimerOffsetYRow, controls.selfDRTimerOffsetXRow, 8)

    local borderCard = CreateCard(content, S("UI_SELFDR_BORDER_TITLE"), S("UI_SELFDR_BORDER_HELP"), 236)
    AnchorBelow(borderCard, timerCard, 14)

    controls.selfDRBorderStyleRow = CreateDropdownRow(
        borderCard,
        S("UI_BORDER_STYLE"),
        GetBorderStyleOptions,
        function()
            return GetSelfDRSettings().borderStyle
        end,
        function(value)
            GetSelfDRSettings().borderStyle = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    controls.selfDRBorderStyleRow:SetPoint("TOPLEFT", borderCard.Divider, "BOTTOMLEFT", 0, -14)

    controls.selfDRBorderWidthRow = CreateSliderRow(
        borderCard,
        S("UI_BORDER_WIDTH"),
        1,
        8,
        0.5,
        function(value)
            return string.format("%.1f", value)
        end,
        function()
            return GetSelfDRSettings().borderWidth
        end,
        function(value)
            GetSelfDRSettings().borderWidth = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRBorderWidthRow, controls.selfDRBorderStyleRow, 8)

    controls.selfDRBorderColorRow = CreateColorRow(
        borderCard,
        S("UI_BORDER_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                GetSelfDRSettings().borderColor,
                defaults.selfDR.borderColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            GetSelfDRSettings().borderColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRBorderColorRow, controls.selfDRBorderWidthRow, 8)

    controls.selfDRBorderImmuneColorRow = CreateColorRow(
        borderCard,
        S("UI_IMMUNE_BORDER_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                GetSelfDRSettings().borderImmuneColor,
                defaults.selfDR.borderImmuneColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            GetSelfDRSettings().borderImmuneColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDRBorderImmuneColorRow, controls.selfDRBorderColorRow, 8)

    local positionCard = CreateCard(content, S("UI_SELFDR_POSITION_TITLE"), S("UI_SELFDR_POSITION_HELP"), 224)
    AnchorBelow(positionCard, borderCard, 14)

    controls.selfDROffsetXRow = CreateSliderRow(
        positionCard,
        S("UI_HORIZONTAL_OFFSET"),
        -800,
        800,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return GetSelfDRSettings().offsetX
        end,
        function(value)
            GetSelfDRSettings().offsetX = value
            SettingsUI.RefreshAll()
        end
    )
    controls.selfDROffsetXRow:SetPoint("TOPLEFT", positionCard.Divider, "BOTTOMLEFT", 0, -14)

    controls.selfDROffsetYRow = CreateSliderRow(
        positionCard,
        S("UI_VERTICAL_OFFSET"),
        -600,
        600,
        1,
        function(value)
            return tostring(math.floor(value))
        end,
        function()
            return GetSelfDRSettings().offsetY
        end,
        function(value)
            GetSelfDRSettings().offsetY = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.selfDROffsetYRow, controls.selfDROffsetXRow, 8)

    controls.selfDRResetPositionButton = CreateActionButton(
        positionCard,
        S("UI_SELFDR_RESET_POSITION"),
        170,
        function()
            if _G.ArenaDRNameplates_ResetSelfDRPosition then
                _G.ArenaDRNameplates_ResetSelfDRPosition()
            end
            SettingsUI.RefreshControls()
        end
    )
    controls.selfDRResetPositionButton:SetPoint("TOPLEFT", controls.selfDROffsetYRow, "BOTTOMLEFT", 0, -12)

    local dragHint = positionCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dragHint:SetPoint("TOPLEFT", controls.selfDRResetPositionButton, "BOTTOMLEFT", 0, -10)
    dragHint:SetWidth(560)
    dragHint:SetJustifyH("LEFT")
    dragHint:SetText("|cff778899" .. S("UI_SELFDR_DRAG_HINT") .. "|r")

    return page
end

local function GetTargetFocusDRSettings()
    return SettingsUI.EnsureDB().targetFocusDR
end

local function GetTargetFocusDRTimers(kind)
    return GetTargetFocusDRSettings()[kind].timers
end

local function GetTargetFocusDRGrowthOptions()
    local settings = GetTargetFocusDRSettings()
    if Shared.NormalizeIconLayout(settings.iconLayout) == "VERTICAL" then
        return {
            { value = "UP", text = S("UI_GROWTH_UP") },
            { value = "DOWN", text = S("UI_GROWTH_DOWN") },
        }
    end
    return {
        { value = "CENTER", text = S("UI_GROWTH_CENTER") },
        { value = "LEFT", text = S("UI_GROWTH_LEFT") },
        { value = "RIGHT", text = S("UI_GROWTH_RIGHT") },
    }
end

local function GetTargetFocusDRGrowthValue()
    local settings = GetTargetFocusDRSettings()
    if Shared.NormalizeIconLayout(settings.iconLayout) == "VERTICAL" then
        return Shared.NormalizeVerticalIconGrowth(settings.iconVerticalGrowth)
    end
    return Shared.NormalizeIconGrowth(settings.iconGrowth)
end

local function SetTargetFocusDRGrowthValue(value)
    local settings = GetTargetFocusDRSettings()
    if Shared.NormalizeIconLayout(settings.iconLayout) == "VERTICAL" then
        settings.iconVerticalGrowth = value
    else
        settings.iconGrowth = value
    end
    SettingsUI.RefreshAll()
end

local function CreateTargetFocusDRPage(parent)
    local page = CreatePage(parent, 1640)
    local content = page.content
    local settingsDefaults = defaults.targetFocusDR

    local _, description = CreatePageHeader(
        content,
        S("UI_TARGETFOCUS_HEADER"),
        S("UI_TARGETFOCUS_SUBHEADER")
    )

    local featureCard = CreateCard(
        content,
        S("UI_TARGETFOCUS_FEATURE_TITLE"),
        S("UI_TARGETFOCUS_FEATURE_HELP"),
        190
    )
    featureCard:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)

    controls.targetFocusEnabledRow = CreateCheckboxRow(
        featureCard,
        S("UI_TARGETFOCUS_ENABLE"),
        function()
            return GetTargetFocusDRSettings().enabled
        end,
        function(value)
            GetTargetFocusDRSettings().enabled = value
            SettingsUI.RefreshAll()
        end
    )
    SetCompactCheckboxWidth(controls.targetFocusEnabledRow, math.floor(ROW_WIDTH / 2))
    controls.targetFocusEnabledRow:SetPoint("TOPLEFT", featureCard.Divider, "BOTTOMLEFT", 0, -14)

    controls.targetFocusLockedRow = CreateCheckboxRow(
        featureCard,
        S("UI_TARGETFOCUS_LOCK"),
        function()
            return GetTargetFocusDRSettings().locked
        end,
        function(value)
            GetTargetFocusDRSettings().locked = value
            SettingsUI.RefreshAll()
        end
    )
    SetCompactCheckboxWidth(controls.targetFocusLockedRow, math.floor(ROW_WIDTH / 2))
    controls.targetFocusLockedRow:SetPoint("LEFT", controls.targetFocusEnabledRow, "RIGHT")

    controls.targetFocusShowTargetRow = CreateCheckboxRow(
        featureCard,
        S("UI_TARGETFOCUS_SHOW_TARGET"),
        function()
            return GetTargetFocusDRSettings().showTarget
        end,
        function(value)
            GetTargetFocusDRSettings().showTarget = value
            SettingsUI.RefreshAll()
        end
    )
    SetCompactCheckboxWidth(controls.targetFocusShowTargetRow, math.floor(ROW_WIDTH / 2))
    AnchorBelow(controls.targetFocusShowTargetRow, controls.targetFocusEnabledRow, 8)

    controls.targetFocusShowFocusRow = CreateCheckboxRow(
        featureCard,
        S("UI_TARGETFOCUS_SHOW_FOCUS"),
        function()
            return GetTargetFocusDRSettings().showFocus
        end,
        function(value)
            GetTargetFocusDRSettings().showFocus = value
            SettingsUI.RefreshAll()
        end
    )
    SetCompactCheckboxWidth(controls.targetFocusShowFocusRow, math.floor(ROW_WIDTH / 2))
    controls.targetFocusShowFocusRow:SetPoint("LEFT", controls.targetFocusShowTargetRow, "RIGHT")

    controls.targetFocusArenaNote = featureCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    controls.targetFocusArenaNote:SetPoint("TOPLEFT", controls.targetFocusShowTargetRow, "BOTTOMLEFT", 0, -10)
    controls.targetFocusArenaNote:SetWidth(ROW_WIDTH)
    controls.targetFocusArenaNote:SetJustifyH("LEFT")
    controls.targetFocusArenaNote:SetText("|cff778899" .. S("UI_TARGETFOCUS_ARENA_ONLY") .. "|r")

    local appearanceCard = CreateCard(
        content,
        S("UI_TARGETFOCUS_APPEARANCE_TITLE"),
        S("UI_TARGETFOCUS_APPEARANCE_HELP"),
        368
    )
    AnchorBelow(appearanceCard, featureCard, 14)

    controls.targetFocusSizeRow = CreateSliderRow(
        appearanceCard,
        S("UI_ICON_SIZE"),
        16,
        80,
        1,
        function(value) return tostring(math.floor(value)) end,
        function() return GetTargetFocusDRSettings().size end,
        function(value)
            GetTargetFocusDRSettings().size = value
            SettingsUI.RefreshAll()
        end
    )
    controls.targetFocusSizeRow:SetPoint("TOPLEFT", appearanceCard.Divider, "BOTTOMLEFT", 0, -14)

    controls.targetFocusTargetScaleRow = CreateSliderRow(
        appearanceCard,
        S("UI_TARGETFOCUS_TARGET_SCALE"),
        0.5,
        3.0,
        0.1,
        function(value) return string.format("%.1fx", value) end,
        function() return GetTargetFocusDRSettings().target.scale end,
        function(value)
            GetTargetFocusDRSettings().target.scale = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusTargetScaleRow, controls.targetFocusSizeRow, 8)

    controls.targetFocusFocusScaleRow = CreateSliderRow(
        appearanceCard,
        S("UI_TARGETFOCUS_FOCUS_SCALE"),
        0.5,
        3.0,
        0.1,
        function(value) return string.format("%.1fx", value) end,
        function() return GetTargetFocusDRSettings().focus.scale end,
        function(value)
            GetTargetFocusDRSettings().focus.scale = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusFocusScaleRow, controls.targetFocusTargetScaleRow, 8)

    controls.targetFocusOpacityRow = CreateSliderRow(
        appearanceCard,
        S("UI_ICON_OPACITY"),
        0.1,
        1,
        0.05,
        function(value) return string.format("%d%%", value * 100) end,
        function() return GetTargetFocusDRSettings().opacity end,
        function(value)
            GetTargetFocusDRSettings().opacity = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusOpacityRow, controls.targetFocusFocusScaleRow, 8)

    controls.targetFocusPaddingRow = CreateSliderRow(
        appearanceCard,
        S("UI_ICON_PADDING"),
        0,
        20,
        1,
        function(value) return tostring(math.floor(value)) end,
        function() return GetTargetFocusDRSettings().iconPadding end,
        function(value)
            GetTargetFocusDRSettings().iconPadding = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusPaddingRow, controls.targetFocusOpacityRow, 8)

    controls.targetFocusLayoutRow = CreateDropdownRow(
        appearanceCard,
        S("UI_ICON_LAYOUT"),
        GetIconLayoutOptions,
        function() return GetTargetFocusDRSettings().iconLayout end,
        function(value)
            GetTargetFocusDRSettings().iconLayout = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    AnchorBelow(controls.targetFocusLayoutRow, controls.targetFocusPaddingRow, 8)

    controls.targetFocusGrowthRow = CreateDropdownRow(
        appearanceCard,
        S("UI_ICON_GROWTH"),
        GetTargetFocusDRGrowthOptions,
        GetTargetFocusDRGrowthValue,
        SetTargetFocusDRGrowthValue
    )
    AnchorBelow(controls.targetFocusGrowthRow, controls.targetFocusLayoutRow, 8)

    local timersCard = CreateCard(
        content,
        S("UI_TARGETFOCUS_TIMER_STYLE_TITLE"),
        S("UI_TARGETFOCUS_TIMER_STYLE_HELP"),
        350
    )
    AnchorBelow(timersCard, appearanceCard, 14)

    controls.targetFocusTargetTimerOverrideRow = CreateCheckboxRow(
        timersCard,
        S("UI_TARGETFOCUS_TARGET_TIMER_OVERRIDE"),
        function() return GetTargetFocusDRTimers("target").override end,
        function(value)
            GetTargetFocusDRTimers("target").override = value
            SettingsUI.RefreshAll()
        end
    )
    controls.targetFocusTargetTimerOverrideRow:SetPoint(
        "TOPLEFT",
        timersCard.Divider,
        "BOTTOMLEFT",
        0,
        -14
    )

    controls.targetFocusTargetTimerScaleRow = CreateSliderRow(
        timersCard,
        S("UI_TARGETFOCUS_TARGET_TIMER_SIZE"),
        0.5,
        3.0,
        0.05,
        function(value) return string.format("%.2fx", value) end,
        function() return GetTargetFocusDRTimers("target").timerTextScale end,
        function(value)
            GetTargetFocusDRTimers("target").timerTextScale = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(
        controls.targetFocusTargetTimerScaleRow,
        controls.targetFocusTargetTimerOverrideRow,
        8
    )

    controls.targetFocusTargetTimerColorRow = CreateColorRow(
        timersCard,
        S("UI_TARGETFOCUS_TARGET_TIMER_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                GetTargetFocusDRTimers("target").timerTextColor,
                settingsDefaults.target.timers.timerTextColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            GetTargetFocusDRTimers("target").timerTextColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(
        controls.targetFocusTargetTimerColorRow,
        controls.targetFocusTargetTimerScaleRow,
        8
    )

    controls.targetFocusFocusTimerOverrideRow = CreateCheckboxRow(
        timersCard,
        S("UI_TARGETFOCUS_FOCUS_TIMER_OVERRIDE"),
        function() return GetTargetFocusDRTimers("focus").override end,
        function(value)
            GetTargetFocusDRTimers("focus").override = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(
        controls.targetFocusFocusTimerOverrideRow,
        controls.targetFocusTargetTimerColorRow,
        12
    )

    controls.targetFocusFocusTimerScaleRow = CreateSliderRow(
        timersCard,
        S("UI_TARGETFOCUS_FOCUS_TIMER_SIZE"),
        0.5,
        3.0,
        0.05,
        function(value) return string.format("%.2fx", value) end,
        function() return GetTargetFocusDRTimers("focus").timerTextScale end,
        function(value)
            GetTargetFocusDRTimers("focus").timerTextScale = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(
        controls.targetFocusFocusTimerScaleRow,
        controls.targetFocusFocusTimerOverrideRow,
        8
    )

    controls.targetFocusFocusTimerColorRow = CreateColorRow(
        timersCard,
        S("UI_TARGETFOCUS_FOCUS_TIMER_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                GetTargetFocusDRTimers("focus").timerTextColor,
                settingsDefaults.focus.timers.timerTextColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            GetTargetFocusDRTimers("focus").timerTextColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(
        controls.targetFocusFocusTimerColorRow,
        controls.targetFocusFocusTimerScaleRow,
        8
    )

    local borderCard = CreateCard(
        content,
        S("UI_SELFDR_BORDER_TITLE"),
        S("UI_TARGETFOCUS_BORDER_HELP"),
        246
    )
    AnchorBelow(borderCard, timersCard, 14)

    controls.targetFocusBorderStyleRow = CreateDropdownRow(
        borderCard,
        S("UI_BORDER_STYLE"),
        GetBorderStyleOptions,
        function() return GetTargetFocusDRSettings().borderStyle end,
        function(value)
            GetTargetFocusDRSettings().borderStyle = value
            SettingsUI.RefreshAll()
            SettingsUI.RefreshControls()
        end
    )
    controls.targetFocusBorderStyleRow:SetPoint("TOPLEFT", borderCard.Divider, "BOTTOMLEFT", 0, -14)

    controls.targetFocusBorderWidthRow = CreateSliderRow(
        borderCard,
        S("UI_BORDER_WIDTH"),
        1,
        8,
        0.5,
        function(value) return string.format("%.1f", value) end,
        function() return GetTargetFocusDRSettings().borderWidth end,
        function(value)
            GetTargetFocusDRSettings().borderWidth = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusBorderWidthRow, controls.targetFocusBorderStyleRow, 8)

    controls.targetFocusBorderColorRow = CreateColorRow(
        borderCard,
        S("UI_BORDER_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                GetTargetFocusDRSettings().borderColor,
                settingsDefaults.borderColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            GetTargetFocusDRSettings().borderColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusBorderColorRow, controls.targetFocusBorderWidthRow, 8)

    controls.targetFocusBorderImmuneColorRow = CreateColorRow(
        borderCard,
        S("UI_IMMUNE_BORDER_COLOR"),
        function()
            local color = Shared.NormalizeColorTable(
                GetTargetFocusDRSettings().borderImmuneColor,
                settingsDefaults.borderImmuneColor
            )
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            GetTargetFocusDRSettings().borderImmuneColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusBorderImmuneColorRow, controls.targetFocusBorderColorRow, 8)

    local positionCard = CreateCard(
        content,
        S("UI_TARGETFOCUS_POSITION_TITLE"),
        S("UI_TARGETFOCUS_POSITION_HELP"),
        410
    )
    AnchorBelow(positionCard, borderCard, 14)

    local targetLabel = positionCard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    targetLabel:SetPoint("TOPLEFT", positionCard.Divider, "BOTTOMLEFT", 0, -14)
    targetLabel:SetText(S("UI_TARGETFOCUS_TARGET_POSITION"))

    controls.targetFocusTargetXRow = CreateSliderRow(
        positionCard,
        S("UI_HORIZONTAL_OFFSET"),
        -800,
        800,
        1,
        function(value) return tostring(math.floor(value)) end,
        function() return GetTargetFocusDRSettings().target.offsetX end,
        function(value)
            GetTargetFocusDRSettings().target.offsetX = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusTargetXRow, targetLabel, 6)

    controls.targetFocusTargetYRow = CreateSliderRow(
        positionCard,
        S("UI_VERTICAL_OFFSET"),
        -600,
        600,
        1,
        function(value) return tostring(math.floor(value)) end,
        function() return GetTargetFocusDRSettings().target.offsetY end,
        function(value)
            GetTargetFocusDRSettings().target.offsetY = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusTargetYRow, controls.targetFocusTargetXRow, 8)

    local focusLabel = positionCard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    AnchorBelow(focusLabel, controls.targetFocusTargetYRow, 12)
    focusLabel:SetText(S("UI_TARGETFOCUS_FOCUS_POSITION"))

    controls.targetFocusFocusXRow = CreateSliderRow(
        positionCard,
        S("UI_HORIZONTAL_OFFSET"),
        -800,
        800,
        1,
        function(value) return tostring(math.floor(value)) end,
        function() return GetTargetFocusDRSettings().focus.offsetX end,
        function(value)
            GetTargetFocusDRSettings().focus.offsetX = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusFocusXRow, focusLabel, 6)

    controls.targetFocusFocusYRow = CreateSliderRow(
        positionCard,
        S("UI_VERTICAL_OFFSET"),
        -600,
        600,
        1,
        function(value) return tostring(math.floor(value)) end,
        function() return GetTargetFocusDRSettings().focus.offsetY end,
        function(value)
            GetTargetFocusDRSettings().focus.offsetY = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.targetFocusFocusYRow, controls.targetFocusFocusXRow, 8)

    controls.targetFocusResetPositionButton = CreateActionButton(
        positionCard,
        S("UI_TARGETFOCUS_RESET_POSITION"),
        210,
        function()
            if _G.ArenaDRNameplates_ResetTargetFocusDRPositions then
                _G.ArenaDRNameplates_ResetTargetFocusDRPositions()
            end
            SettingsUI.RefreshControls()
        end
    )
    AnchorBelow(controls.targetFocusResetPositionButton, controls.targetFocusFocusYRow, 12)

    local dragHint = positionCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dragHint:SetPoint("TOPLEFT", controls.targetFocusResetPositionButton, "BOTTOMLEFT", 0, -10)
    dragHint:SetWidth(ROW_WIDTH)
    dragHint:SetJustifyH("LEFT")
    dragHint:SetText("|cff778899" .. S("UI_TARGETFOCUS_PREVIEW_DRAG_HINT") .. "|r")

    return page
end

local function CreateTimersPage(parent)
    local page = CreatePage(parent, 650)
    local content = page.content

    local _, description = CreatePageHeader(content, S("UI_TIMERS_HEADER"), S("UI_TIMERS_SUBHEADER"))

    local swipeCard = CreateCard(content, S("UI_SWIPE_TITLE"), S("UI_SWIPE_HELP"), 136)
    swipeCard:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)

    controls.showTimerSwipeRow = CreateCheckboxRow(
        swipeCard,
        S("UI_SHOW_TIMER_SWIPE"),
        function()
            return SettingsUI.EnsureDB().showTimerSwipe
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.showTimerSwipe = value
            SettingsUI.RefreshAll()
        end
    )
    controls.showTimerSwipeRow:SetPoint("TOPLEFT", swipeCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.showTimerSwipeRow,
        "Enables the radial cooldown sweep on each DR icon so you can judge remaining time without reading numbers."
    )

    controls.showTimerSwipeEdgeRow = CreateCheckboxRow(
        swipeCard,
        S("UI_SHOW_TIMER_SWIPE_EDGE"),
        function()
            return SettingsUI.EnsureDB().showTimerSwipeEdge
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.showTimerSwipeEdge = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.showTimerSwipeEdgeRow, controls.showTimerSwipeRow, 8)
    AttachRowTooltip(
        controls.showTimerSwipeEdgeRow,
        "Adds Blizzard's bright edge highlight to the swipe. It is more visible, but can feel busier in combat."
    )

    local countdownCard = CreateCard(content, S("UI_COUNTDOWN_TEXT_TITLE"), S("UI_COUNTDOWN_TEXT_HELP"), 390)
    AnchorBelow(countdownCard, swipeCard, 14)

    controls.showTimerTextRow = CreateCheckboxRow(
        countdownCard,
        S("UI_SHOW_TIMER_TEXT"),
        function()
            return SettingsUI.EnsureDB().showTimerText
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.showTimerText = value
            SettingsUI.RefreshAll()
        end
    )
    controls.showTimerTextRow:SetPoint("TOPLEFT", countdownCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.showTimerTextRow,
        "Shows or hides the countdown number on DR icons while keeping the cooldown swipe available."
    )

    controls.showTimerDecimalsRow = CreateCheckboxRow(
        countdownCard,
        S("UI_SHOW_TIMER_DECIMALS"),
        function()
            return SettingsUI.EnsureDB().showTimerDecimals
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.showTimerDecimals = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.showTimerDecimalsRow, controls.showTimerTextRow, 8)
    AttachRowTooltip(controls.showTimerDecimalsRow, S("UI_SHOW_TIMER_DECIMALS_HELP"))

    controls.timerDecimalThresholdRow = CreateSliderRow(
        countdownCard,
        S("UI_TIMER_DECIMAL_THRESHOLD"),
        1,
        20,
        1,
        function(value)
            return string.format(S("UI_SECONDS_FORMAT"), value)
        end,
        function()
            return SettingsUI.EnsureDB().timerDecimalThreshold
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.timerDecimalThreshold = math.floor(value + 0.5)
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.timerDecimalThresholdRow, controls.showTimerDecimalsRow, 8)
    AttachRowTooltip(controls.timerDecimalThresholdRow, S("UI_TIMER_DECIMAL_THRESHOLD_HELP"))

    controls.timerTextColorRow = CreateColorRow(
        countdownCard,
        S("UI_TEXT_COLOR"),
        function()
            local color = SettingsUI.EnsureDB().timerTextColor or defaults.timerTextColor
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            local db = SettingsUI.EnsureDB()
            db.timerTextColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.timerTextColorRow, controls.timerDecimalThresholdRow, 8)

    controls.timerTextScaleRow = CreateSliderRow(
        countdownCard,
        S("UI_TEXT_SIZE"),
        0.5,
        3.0,
        0.05,
        function(value)
            return string.format("%.2fx", value)
        end,
        function()
            return SettingsUI.EnsureDB().timerTextScale
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.timerTextScale = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.timerTextScaleRow, controls.timerTextColorRow, 8)
    AttachRowTooltip(
        controls.timerTextScaleRow,
        "Adjusts only the countdown text size. This is the easiest way to improve readability without changing icon size."
    )

    controls.timerTextOffsetXRow = CreateSliderRow(
        countdownCard,
        S("UI_HORIZONTAL_OFFSET"),
        -50,
        50,
        0.5,
        function(value)
            return string.format("%.1f", value)
        end,
        function()
            return SettingsUI.EnsureDB().timerTextOffsetX
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.timerTextOffsetX = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.timerTextOffsetXRow, controls.timerTextScaleRow, 8)

    controls.timerTextOffsetYRow = CreateSliderRow(
        countdownCard,
        S("UI_VERTICAL_OFFSET"),
        -50,
        50,
        0.5,
        function(value)
            return string.format("%.1f", value)
        end,
        function()
            return SettingsUI.EnsureDB().timerTextOffsetY
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.timerTextOffsetY = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.timerTextOffsetYRow, controls.timerTextOffsetXRow, 8)

    return page
end

local function CreateDRTextPage(parent)
    local page = CreatePage(parent, 620)
    local content = page.content

    local _, description = CreatePageHeader(content, S("UI_DR_TEXT_HEADER"), S("UI_DR_TEXT_SUBHEADER"))

    local drTextCard = CreateCard(content, S("UI_POSITION_STYLE_TITLE"), S("UI_DR_TEXT_HELP"), 356)
    drTextCard:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    controls.drTextCard = drTextCard

    controls.showDRTextRow = CreateCheckboxRow(
        drTextCard,
        S("UI_SHOW_DR_STATE_TEXT"),
        function()
            return SettingsUI.EnsureDB().showDRText
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.showDRText = value
            SettingsUI.RefreshAll()
        end
    )
    controls.showDRTextRow:SetPoint("TOPLEFT", drTextCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.showDRTextRow,
        "Shows the current DR stage directly on the icon. Turn this off if you prefer a cleaner icon-only look."
    )

    controls.drTextAnchorRow = CreateDropdownRow(
        drTextCard,
        S("UI_TEXT_ANCHOR"),
        GetDRTextAnchorOptions,
        function()
            return SettingsUI.EnsureDB().drTextAnchor
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.drTextAnchor = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drTextAnchorRow, controls.showDRTextRow, 8)
    AttachRowTooltip(
        controls.drTextAnchorRow,
        "Moves the DR text to a preset anchor on the icon before the horizontal and vertical offsets are applied."
    )

    controls.drTextScaleRow = CreateSliderRow(
        drTextCard,
        S("UI_TEXT_SIZE"),
        0.5,
        3.0,
        0.05,
        function(value)
            return string.format("%.2fx", value)
        end,
        function()
            return SettingsUI.EnsureDB().drTextScale
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.drTextScale = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drTextScaleRow, controls.drTextAnchorRow, 8)
    AttachRowTooltip(
        controls.drTextScaleRow,
        "Scales the DR stage text independently from the icon so you can keep the label readable without oversizing the tray."
    )

    controls.drTextOffsetXRow = CreateSliderRow(
        drTextCard,
        S("UI_HORIZONTAL_OFFSET"),
        -50,
        50,
        0.5,
        function(value)
            return string.format("%.1f", value)
        end,
        function()
            return SettingsUI.EnsureDB().drTextOffsetX
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.drTextOffsetX = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drTextOffsetXRow, controls.drTextScaleRow, 8)

    controls.drTextOffsetYRow = CreateSliderRow(
        drTextCard,
        S("UI_VERTICAL_OFFSET"),
        -50,
        50,
        0.5,
        function(value)
            return string.format("%.1f", value)
        end,
        function()
            return SettingsUI.EnsureDB().drTextOffsetY
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.drTextOffsetY = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drTextOffsetYRow, controls.drTextOffsetXRow, 8)

    controls.drTextColorRow = CreateColorRow(
        drTextCard,
        S("UI_DR_TEXT_COLOR"),
        function()
            local color = SettingsUI.EnsureDB().drTextColor or defaults.drTextColor
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            local db = SettingsUI.EnsureDB()
            db.drTextColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drTextColorRow, controls.drTextOffsetYRow, 8)

    controls.drTextImmuneColorRow = CreateColorRow(
        drTextCard,
        S("UI_IMMUNE_TEXT_COLOR"),
        function()
            local color = SettingsUI.EnsureDB().drTextImmuneColor or defaults.drTextImmuneColor
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            local db = SettingsUI.EnsureDB()
            db.drTextImmuneColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drTextImmuneColorRow, controls.drTextColorRow, 8)

    return page
end

local function CreateBordersPage(parent)
    local page = CreatePage(parent, 520)
    local content = page.content

    local _, description = CreatePageHeader(content, S("UI_BORDERS_HEADER"), S("UI_BORDERS_SUBHEADER"))

    local bordersCard = CreateCard(content, S("UI_BORDERS_HEADER"), S("UI_BORDERS_SUBHEADER"), 322)
    bordersCard:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)

    controls.showImmunityIndicatorRow = CreateCheckboxRow(
        bordersCard,
        S("UI_SHOW_BLIZZARD_IMMUNITY_BADGE"),
        function()
            return SettingsUI.EnsureDB().showImmunityIndicator
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.showImmunityIndicator = value
            SettingsUI.RefreshAll()
        end
    )
    controls.showImmunityIndicatorRow:SetPoint("TOPLEFT", bordersCard.Divider, "BOTTOMLEFT", 0, -14)
    AttachRowTooltip(
        controls.showImmunityIndicatorRow,
        "Keeps Blizzard's default immunity badge visible in addition to the addon's DR borders and text."
    )

    controls.drBorderStyleRow = CreateDropdownRow(
        bordersCard,
        S("UI_BORDER_STYLE"),
        GetBorderStyleOptions,
        function()
            return SettingsUI.EnsureDB().drBorderStyle
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.drBorderStyle = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drBorderStyleRow, controls.showImmunityIndicatorRow, 8)
    AttachRowTooltip(
        controls.drBorderStyleRow,
        "Solid uses the addon’s current clean outline. Classic uses the classic debuff overlay texture."
    )

    controls.drBorderWidthRow = CreateSliderRow(
        bordersCard,
        S("UI_BORDER_WIDTH"),
        1,
        8,
        0.5,
        function(value)
            return string.format("%.1f", value)
        end,
        function()
            return SettingsUI.EnsureDB().drBorderWidth
        end,
        function(value)
            local db = SettingsUI.EnsureDB()
            db.drBorderWidth = value
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drBorderWidthRow, controls.drBorderStyleRow, 8)
    AttachRowTooltip(
        controls.drBorderWidthRow,
        "Makes the DR border thinner or thicker. A slightly thicker border is often easier to read during fast arena swaps."
    )

    controls.drBorderColorRow = CreateColorRow(
        bordersCard,
        S("UI_DR_BORDER_COLOR"),
        function()
            local color = SettingsUI.EnsureDB().drBorderColor or defaults.drBorderColor
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            local db = SettingsUI.EnsureDB()
            db.drBorderColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drBorderColorRow, controls.drBorderWidthRow, 8)

    controls.drBorderImmuneColorRow = CreateColorRow(
        bordersCard,
        S("UI_IMMUNE_BORDER_COLOR"),
        function()
            local color = SettingsUI.EnsureDB().drBorderImmuneColor or defaults.drBorderImmuneColor
            return color[1], color[2], color[3]
        end,
        function(r, g, b)
            local db = SettingsUI.EnsureDB()
            db.drBorderImmuneColor = { r, g, b }
            SettingsUI.RefreshAll()
        end
    )
    AnchorBelow(controls.drBorderImmuneColorRow, controls.drBorderColorRow, 8)

    return page
end

local function CreateSharePage(parent)
    local page = CreatePage(parent, 520)
    local content = page.content

    local _, description = CreatePageHeader(content, S("UI_SHARE_HEADER"), S("UI_SHARE_SUBHEADER"))

    local exportCard = CreateCard(content, S("UI_EXPORT_TITLE"), S("UI_EXPORT_HELP"), 154)
    exportCard:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)

    controls.exportStringBox = CreateTextInput(exportCard, ROW_WIDTH)
    controls.exportStringBox:SetPoint("TOPLEFT", exportCard.Divider, "BOTTOMLEFT", 0, -16)

    controls.generateExportButton = CreateActionButton(exportCard, S("UI_GENERATE_EXPORT_BUTTON"), 150, function()
        SettingsUI.GenerateExportString(true)
        SettingsUI.SetShareStatus(S("MSG_EXPORT_READY"), false)
    end)
    controls.generateExportButton:SetPoint("TOPLEFT", controls.exportStringBox, "BOTTOMLEFT", 0, -12)

    controls.selectExportButton = CreateActionButton(exportCard, S("UI_SELECT_EXPORT_BUTTON"), 120, function()
        FocusAndSelectEditBox(controls.exportStringBox)
    end)
    controls.selectExportButton:SetPoint("LEFT", controls.generateExportButton, "RIGHT", 10, 0)

    local importCard = CreateCard(content, S("UI_IMPORT_TITLE"), S("UI_IMPORT_HELP"), 178)
    AnchorBelow(importCard, exportCard, 14)

    controls.importStringBox = CreateTextInput(importCard, ROW_WIDTH)
    controls.importStringBox:SetPoint("TOPLEFT", importCard.Divider, "BOTTOMLEFT", 0, -16)

    controls.importButton = CreateActionButton(importCard, S("UI_IMPORT_BUTTON"), 150, function()
        StaticPopup_Show("ARENADRNAMEPLATES_CONFIRM_IMPORT")
    end)
    controls.importButton:SetPoint("TOPLEFT", controls.importStringBox, "BOTTOMLEFT", 0, -12)

    controls.clearImportButton = CreateActionButton(importCard, S("UI_CLEAR_IMPORT_BUTTON"), 120, function()
        if controls.importStringBox then
            controls.importStringBox:SetText("")
            controls.importStringBox:ClearFocus()
        end
        SettingsUI.SetShareStatus("", false)
    end)
    controls.clearImportButton:SetPoint("LEFT", controls.importButton, "RIGHT", 10, 0)

    controls.shareStatusText = importCard:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    controls.shareStatusText:SetPoint("TOPLEFT", controls.importButton, "BOTTOMLEFT", 0, -14)
    controls.shareStatusText:SetWidth(ROW_WIDTH)
    controls.shareStatusText:SetJustifyH("LEFT")
    controls.shareStatusText:SetText("")

    TrackRefreshable({
        Refresh = function()
            if controls.exportStringBox and not controls.exportStringBox:HasFocus() then
                controls.exportStringBox:SetText(Shared.ExportSettings())
            end
        end,
    })

    return page
end

function SettingsUI.RefreshLayouts()
    for _, page in pairs(SettingsUI.pages) do
        if page and page:IsShown() and page.UpdateHeight then
            C_Timer.After(0.01, page.UpdateHeight)
        end
    end
end

local function RefreshControlsNow()
    if SettingsUI.isRefreshing then
        return
    end

    SettingsUI.isRefreshing = true
    SettingsUI.EnsureDB()

    for _, widget in ipairs(SettingsUI.refreshables) do
        if widget and widget.Refresh then
            widget:Refresh()
        end
    end

    local db = ArenaDRNameplatesDB or defaults
    local showDRText = db.showDRText == true
    local showTimerText = db.showTimerText ~= false
    local showTimerSwipe = db.showTimerSwipe == true
    local isAdvanced = db.anchorPreset == "ADVANCED"
    local isVerticalLayout = Shared.NormalizeIconLayout(db.iconLayout) == "VERTICAL"
    local drBorderStyle = Shared.NormalizeDRBorderStyle(db.drBorderStyle)
    local drBorderVisible = drBorderStyle ~= "NONE"
    local isSolidDRBorder = drBorderStyle == "SOLID"
    local trinketDB = type(db.trinket) == "table" and db.trinket or defaults.trinket
    local trinketEnabled = trinketDB.enabled == true
    local isTrinketAdvanced = trinketDB.anchorPreset == "ADVANCED"
    local trinketBorderStyle = Shared.NormalizeTrinketBorderStyle(trinketDB.borderStyle)
    local trinketBorderVisible = trinketBorderStyle ~= "NONE"
    local isSolidTrinketBorder = trinketBorderStyle == "SOLID"
    local blizzardDREnemiesCVarAvailable = IsBlizzardDRCVarAvailable("enemiesEnabled")
    local blizzardDROnlyTriggerableCVarAvailable = IsBlizzardDRCVarAvailable("onlyTriggerableByMe")

    if controls.drTextCard and controls.drTextCard.Description then
        controls.drTextCard.Description:SetAlpha(showDRText and 1 or 0.65)
    end

    if controls.drTextAnchorRow and controls.drTextAnchorRow.SetEnabled then
        controls.drTextAnchorRow:SetEnabled(showDRText)
    end
    if controls.drTextScaleRow and controls.drTextScaleRow.SetEnabled then
        controls.drTextScaleRow:SetEnabled(showDRText)
    end
    if controls.drTextOffsetXRow and controls.drTextOffsetXRow.SetEnabled then
        controls.drTextOffsetXRow:SetEnabled(showDRText)
    end
    if controls.drTextOffsetYRow and controls.drTextOffsetYRow.SetEnabled then
        controls.drTextOffsetYRow:SetEnabled(showDRText)
    end
    if controls.drTextColorRow and controls.drTextColorRow.SetEnabled then
        controls.drTextColorRow:SetEnabled(showDRText)
    end
    if controls.drTextImmuneColorRow and controls.drTextImmuneColorRow.SetEnabled then
        controls.drTextImmuneColorRow:SetEnabled(showDRText)
    end

    if controls.showTimerSwipeEdgeRow and controls.showTimerSwipeEdgeRow.SetEnabled then
        controls.showTimerSwipeEdgeRow:SetEnabled(showTimerSwipe)
    end
    if controls.showTimerDecimalsRow and controls.showTimerDecimalsRow.SetEnabled then
        controls.showTimerDecimalsRow:SetEnabled(showTimerText)
    end
    if controls.timerDecimalThresholdRow and controls.timerDecimalThresholdRow.SetEnabled then
        controls.timerDecimalThresholdRow:SetEnabled(showTimerText and db.showTimerDecimals == true)
    end
    if controls.timerTextColorRow and controls.timerTextColorRow.SetEnabled then
        controls.timerTextColorRow:SetEnabled(showTimerText)
    end
    if controls.timerTextScaleRow and controls.timerTextScaleRow.SetEnabled then
        controls.timerTextScaleRow:SetEnabled(showTimerText)
    end
    if controls.timerTextOffsetXRow and controls.timerTextOffsetXRow.SetEnabled then
        controls.timerTextOffsetXRow:SetEnabled(showTimerText)
    end
    if controls.timerTextOffsetYRow and controls.timerTextOffsetYRow.SetEnabled then
        controls.timerTextOffsetYRow:SetEnabled(showTimerText)
    end

    if controls.advancedCard then
        controls.advancedCard:SetShown(isAdvanced)
    end
    if controls.pointRow and controls.pointRow.SetEnabled then
        controls.pointRow:SetEnabled(isAdvanced and not isVerticalLayout)
    end
    if controls.relativePointRow and controls.relativePointRow.SetEnabled then
        controls.relativePointRow:SetEnabled(isAdvanced)
    end
    if controls.growthRow and controls.growthRow.SetEnabled then
        controls.growthRow:SetEnabled(isAdvanced or isVerticalLayout)
    end

    if controls.drBorderWidthRow and controls.drBorderWidthRow.SetEnabled then
        controls.drBorderWidthRow:SetEnabled(isSolidDRBorder)
    end
    if controls.drBorderColorRow and controls.drBorderColorRow.SetEnabled then
        controls.drBorderColorRow:SetEnabled(drBorderVisible)
    end
    if controls.drBorderImmuneColorRow and controls.drBorderImmuneColorRow.SetEnabled then
        controls.drBorderImmuneColorRow:SetEnabled(drBorderVisible)
    end

    if controls.blizzardDREnemiesEnabledRow and controls.blizzardDREnemiesEnabledRow.SetEnabled then
        controls.blizzardDREnemiesEnabledRow:SetEnabled(blizzardDREnemiesCVarAvailable)
    end
    if controls.blizzardDROnlyTriggerableByMeRow and controls.blizzardDROnlyTriggerableByMeRow.SetEnabled then
        controls.blizzardDROnlyTriggerableByMeRow:SetEnabled(
            blizzardDREnemiesCVarAvailable
            and blizzardDROnlyTriggerableCVarAvailable
        )
    end

    if controls.trinketVisibilityRow and controls.trinketVisibilityRow.SetEnabled then
        controls.trinketVisibilityRow:SetEnabled(trinketEnabled)
    end
    if controls.trinketSizeRow and controls.trinketSizeRow.SetEnabled then
        controls.trinketSizeRow:SetEnabled(trinketEnabled)
    end
    if controls.trinketOpacityRow and controls.trinketOpacityRow.SetEnabled then
        controls.trinketOpacityRow:SetEnabled(trinketEnabled)
    end
    if controls.trinketBorderStyleRow and controls.trinketBorderStyleRow.SetEnabled then
        controls.trinketBorderStyleRow:SetEnabled(trinketEnabled)
    end
    if controls.trinketBorderWidthRow and controls.trinketBorderWidthRow.SetEnabled then
        controls.trinketBorderWidthRow:SetEnabled(trinketEnabled and isSolidTrinketBorder)
    end
    if controls.trinketBorderColorRow and controls.trinketBorderColorRow.SetEnabled then
        controls.trinketBorderColorRow:SetEnabled(trinketEnabled and trinketBorderVisible)
    end
    if controls.trinketPresetRow and controls.trinketPresetRow.SetEnabled then
        controls.trinketPresetRow:SetEnabled(trinketEnabled)
    end
    if controls.trinketOffsetXRow and controls.trinketOffsetXRow.SetEnabled then
        controls.trinketOffsetXRow:SetEnabled(trinketEnabled)
    end
    if controls.trinketOffsetYRow and controls.trinketOffsetYRow.SetEnabled then
        controls.trinketOffsetYRow:SetEnabled(trinketEnabled)
    end
    if controls.trinketAdvancedCard then
        controls.trinketAdvancedCard:SetShown(trinketEnabled and isTrinketAdvanced)
    end
    if controls.trinketPointRow and controls.trinketPointRow.SetEnabled then
        controls.trinketPointRow:SetEnabled(trinketEnabled and isTrinketAdvanced)
    end
    if controls.trinketRelativePointRow and controls.trinketRelativePointRow.SetEnabled then
        controls.trinketRelativePointRow:SetEnabled(trinketEnabled and isTrinketAdvanced)
    end

    local selfDRSettings = db.selfDR
    local selfDREnabled = selfDRSettings.enabled == true
    local selfDRBorderStyle = Shared.NormalizeDRBorderStyle(selfDRSettings.borderStyle)
    local selfDRBorderVisible = selfDRBorderStyle ~= "NONE"

    local selfDRGatedRows = {
        controls.selfDRLockedRow,
        controls.selfDRArenaRow,
        controls.selfDRBattlegroundRow,
        controls.selfDRWorldRow,
        controls.selfDRSizeRow,
        controls.selfDROpacityRow,
        controls.selfDRPaddingRow,
        controls.selfDRLayoutRow,
        controls.selfDRGrowthRow,
        controls.selfDRTextOverrideRow,
        controls.selfDRTimerOverrideRow,
        controls.selfDRBorderStyleRow,
        controls.selfDROffsetXRow,
        controls.selfDROffsetYRow,
    }
    for _, row in ipairs(selfDRGatedRows) do
        if row and row.SetEnabled then
            row:SetEnabled(selfDREnabled)
        end
    end

    -- Override-dependent rows are hidden outright rather than greyed out, so an
    -- inheriting bar shows only the override toggle and the card shrinks to fit.
    local function ApplyOverrideRows(rows)
        for _, entry in ipairs(rows) do
            local row = entry.row
            if row then
                row:SetShown(entry.shown)
                if row.SetEnabled then
                    row:SetEnabled(entry.shown and entry.enabled ~= false)
                end
            end
        end
    end

    local selfDRTextSettings = selfDRSettings.drText or defaults.selfDR.drText
    local selfDRTextOverride = selfDRTextSettings.override == true
    local selfDRTextShown = selfDRTextSettings.showDRText ~= false

    ApplyOverrideRows({
        { row = controls.selfDRDRTextRow, shown = selfDRTextOverride, enabled = selfDREnabled },
        { row = controls.selfDRTextAnchorRow, shown = selfDRTextOverride, enabled = selfDREnabled and selfDRTextShown },
        { row = controls.selfDRTextScaleRow, shown = selfDRTextOverride, enabled = selfDREnabled and selfDRTextShown },
        { row = controls.selfDRTextOffsetXRow, shown = selfDRTextOverride, enabled = selfDREnabled and selfDRTextShown },
        { row = controls.selfDRTextOffsetYRow, shown = selfDRTextOverride, enabled = selfDREnabled and selfDRTextShown },
        { row = controls.selfDRTextColorRow, shown = selfDRTextOverride, enabled = selfDREnabled and selfDRTextShown },
        { row = controls.selfDRTextImmuneColorRow, shown = selfDRTextOverride, enabled = selfDREnabled and selfDRTextShown },
    })

    local selfTimers = selfDRSettings.timers or defaults.selfDR.timers
    local selfTimersOverride = selfTimers.override == true
    local selfSwipeOn = selfTimers.showTimerSwipe ~= false
    local selfTimerTextOn = selfTimers.showTimerText ~= false

    ApplyOverrideRows({
        { row = controls.selfDRTimerSwipeRow, shown = selfTimersOverride, enabled = selfDREnabled },
        { row = controls.selfDRTimerSwipeEdgeRow, shown = selfTimersOverride, enabled = selfDREnabled and selfSwipeOn },
        { row = controls.selfDRTimerTextRow, shown = selfTimersOverride, enabled = selfDREnabled },
        { row = controls.selfDRTimerDecimalsRow, shown = selfTimersOverride, enabled = selfDREnabled and selfTimerTextOn },
        {
            row = controls.selfDRTimerThresholdRow,
            shown = selfTimersOverride,
            enabled = selfDREnabled and selfTimerTextOn and selfTimers.showTimerDecimals ~= false,
        },
        { row = controls.selfDRTimerScaleRow, shown = selfTimersOverride, enabled = selfDREnabled and selfTimerTextOn },
        { row = controls.selfDRTimerColorRow, shown = selfTimersOverride, enabled = selfDREnabled and selfTimerTextOn },
        { row = controls.selfDRTimerOffsetXRow, shown = selfTimersOverride, enabled = selfDREnabled and selfTimerTextOn },
        { row = controls.selfDRTimerOffsetYRow, shown = selfTimersOverride, enabled = selfDREnabled and selfTimerTextOn },
    })

    if controls.selfDRCategoryRows then
        for _, row in pairs(controls.selfDRCategoryRows) do
            if row and row.SetEnabled then
                row:SetEnabled(selfDREnabled)
            end
        end
    end

    if controls.selfDRBorderWidthRow and controls.selfDRBorderWidthRow.SetEnabled then
        controls.selfDRBorderWidthRow:SetEnabled(selfDREnabled and selfDRBorderStyle == "SOLID")
    end
    if controls.selfDRBorderColorRow and controls.selfDRBorderColorRow.SetEnabled then
        controls.selfDRBorderColorRow:SetEnabled(selfDREnabled and selfDRBorderVisible)
    end
    if controls.selfDRBorderImmuneColorRow and controls.selfDRBorderImmuneColorRow.SetEnabled then
        controls.selfDRBorderImmuneColorRow:SetEnabled(selfDREnabled and selfDRBorderVisible)
    end
    if controls.selfDRResetPositionButton and controls.selfDRResetPositionButton.SetEnabled then
        controls.selfDRResetPositionButton:SetEnabled(selfDREnabled)
    end
    if controls.selfDRZoneLabel then
        controls.selfDRZoneLabel:SetAlpha(selfDREnabled and 1 or 0.45)
    end

    local targetFocusSettings = db.targetFocusDR or defaults.targetFocusDR
    local targetFocusEnabled = targetFocusSettings.enabled == true
    local targetFocusConfigurable = targetFocusEnabled
    local targetFocusBorderStyle = Shared.NormalizeDRBorderStyle(targetFocusSettings.borderStyle)
    local targetFocusBorderVisible = targetFocusBorderStyle ~= "NONE"
    local targetFocusGatedRows = {
        controls.targetFocusLockedRow,
        controls.targetFocusShowTargetRow,
        controls.targetFocusShowFocusRow,
        controls.targetFocusSizeRow,
        controls.targetFocusTargetScaleRow,
        controls.targetFocusFocusScaleRow,
        controls.targetFocusOpacityRow,
        controls.targetFocusPaddingRow,
        controls.targetFocusLayoutRow,
        controls.targetFocusGrowthRow,
        controls.targetFocusTargetTimerOverrideRow,
        controls.targetFocusFocusTimerOverrideRow,
        controls.targetFocusBorderStyleRow,
        controls.targetFocusTargetXRow,
        controls.targetFocusTargetYRow,
        controls.targetFocusFocusXRow,
        controls.targetFocusFocusYRow,
    }
    for _, row in ipairs(targetFocusGatedRows) do
        if row and row.SetEnabled then
            row:SetEnabled(targetFocusConfigurable)
        end
    end
    local targetConfigurable = targetFocusConfigurable
        and targetFocusSettings.showTarget == true
    local focusConfigurable = targetFocusConfigurable
        and targetFocusSettings.showFocus == true
    if controls.targetFocusTargetXRow and controls.targetFocusTargetXRow.SetEnabled then
        controls.targetFocusTargetScaleRow:SetEnabled(targetConfigurable)
        controls.targetFocusTargetTimerOverrideRow:SetEnabled(targetConfigurable)
        controls.targetFocusTargetXRow:SetEnabled(targetConfigurable)
        controls.targetFocusTargetYRow:SetEnabled(targetConfigurable)
    end
    if controls.targetFocusFocusXRow and controls.targetFocusFocusXRow.SetEnabled then
        controls.targetFocusFocusScaleRow:SetEnabled(focusConfigurable)
        controls.targetFocusFocusTimerOverrideRow:SetEnabled(focusConfigurable)
        controls.targetFocusFocusXRow:SetEnabled(focusConfigurable)
        controls.targetFocusFocusYRow:SetEnabled(focusConfigurable)
    end
    if controls.targetFocusTargetTimerScaleRow
        and controls.targetFocusTargetTimerScaleRow.SetEnabled then
        local targetTimers = targetFocusSettings.target.timers
        local focusTimers = targetFocusSettings.focus.timers
        controls.targetFocusTargetTimerScaleRow:SetEnabled(
            targetConfigurable and showTimerText and targetTimers.override == true
        )
        controls.targetFocusTargetTimerColorRow:SetEnabled(
            targetConfigurable and showTimerText and targetTimers.override == true
        )
        controls.targetFocusFocusTimerScaleRow:SetEnabled(
            focusConfigurable and showTimerText and focusTimers.override == true
        )
        controls.targetFocusFocusTimerColorRow:SetEnabled(
            focusConfigurable and showTimerText and focusTimers.override == true
        )
    end
    if controls.targetFocusBorderWidthRow and controls.targetFocusBorderWidthRow.SetEnabled then
        controls.targetFocusBorderWidthRow:SetEnabled(
            targetFocusConfigurable and targetFocusBorderStyle == "SOLID"
        )
    end
    if controls.targetFocusBorderColorRow and controls.targetFocusBorderColorRow.SetEnabled then
        controls.targetFocusBorderColorRow:SetEnabled(targetFocusConfigurable and targetFocusBorderVisible)
        controls.targetFocusBorderImmuneColorRow:SetEnabled(
            targetFocusConfigurable and targetFocusBorderVisible
        )
    end
    if controls.targetFocusResetPositionButton
        and controls.targetFocusResetPositionButton.SetEnabled then
        controls.targetFocusResetPositionButton:SetEnabled(targetFocusConfigurable)
    end
    if controls.targetFocusArenaNote then
        controls.targetFocusArenaNote:SetAlpha(targetFocusConfigurable and 1 or 0.45)
    end

    SettingsUI.RefreshLayouts()
    SettingsUI.isRefreshing = false
end

function SettingsUI.RefreshControls()
    if SettingsUI.refreshControlsPending then
        return
    end

    SettingsUI.refreshControlsPending = true
    C_Timer.After(0, function()
        SettingsUI.refreshControlsPending = false
        RefreshControlsNow()
    end)
end

function SettingsUI.SelectPage(pageKey)
    if not SettingsUI.pages or not next(SettingsUI.pages) then
        return
    end

    if not SettingsUI.pages[pageKey] then
        pageKey = SettingsUI.selectedPage or "general"
    end

    SettingsUI.selectedPage = pageKey

    for key, page in pairs(SettingsUI.pages) do
        page:SetShown(key == pageKey)
    end

    for key, button in pairs(SettingsUI.pageButtons) do
        SetNavButtonState(button, key == pageKey)
    end

    local page = SettingsUI.pages[pageKey]
    if page then
        if page.ResetScroll then
            page:ResetScroll()
        end
        if page.UpdateHeight then
            C_Timer.After(0.01, page.UpdateHeight)
        end
    end
end

function SettingsUI.InitializeStandaloneWindow()
    if SettingsUI.windowInitialized then
        return
    end

    SettingsUI.windowInitialized = true
    local frame = CreateFrame("Frame", WINDOW_NAME, UIParent, "BackdropTemplate")
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 6)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetToplevel(true)
    frame:Hide()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(COLOR_BG.r, COLOR_BG.g, COLOR_BG.b, 0.97)

    ApplyPanelBorders(frame)

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(TITLEBAR_HEIGHT)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(COLOR_TITLEBAR.r, COLOR_TITLEBAR.g, COLOR_TITLEBAR.b, 1)

    local titleBarSep = frame:CreateTexture(nil, "BORDER")
    titleBarSep:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -TITLEBAR_HEIGHT)
    titleBarSep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -TITLEBAR_HEIGHT)
    titleBarSep:SetHeight(1)
    titleBarSep:SetColorTexture(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.9)

    local titleIcon = titleBar:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(20, 20)
    titleIcon:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleIcon:SetTexture("Interface\\Icons\\Ability_Rogue_KidneyShot")
    titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    titleText:SetText("|cff00c0ff" .. S("UI_MAIN_HEADER") .. "|r")

    local tocVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or ""
    if tocVersion ~= "" then
        local versionText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
        versionText:SetPoint("LEFT", titleText, "RIGHT", 8, -1)
        versionText:SetText("|cff888888v" .. tocVersion .. "|r")
    end

    local closeButton = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeButton:SetSize(24, 24)
    closeButton:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    AttachWindowDragHandle(frame, frame)
    AttachWindowDragHandle(titleBar, frame)

    if type(UISpecialFrames) == "table" then
        local isRegistered = false
        for _, frameName in ipairs(UISpecialFrames) do
            if frameName == WINDOW_NAME then
                isRegistered = true
                break
            end
        end
        if not isRegistered then
            table.insert(UISpecialFrames, WINDOW_NAME)
        end
    end

    frame:SetScript("OnShow", function()
        SettingsUI.RefreshControls()
        SettingsUI.SelectPage(SettingsUI.selectedPage or "general")
    end)

    frame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)

    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(TITLEBAR_HEIGHT + 10))
    subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -(TITLEBAR_HEIGHT + 10))
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("|cff778899" .. S("UI_MAIN_SUBHEADER") .. "|r")

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 16)
    hint:SetWidth(320)
    hint:SetJustifyH("LEFT")
    hint:SetText("|cff778899" .. S("UI_STANDALONE_HINT") .. "|r")

    controls.resetAllButton = CreateActionButton(frame, S("UI_RESET_ALL_BUTTON"), 150, function()
        StaticPopup_Show("ARENADRNAMEPLATES_CONFIRM_RESET")
    end)
    controls.resetAllButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 12)
    AttachTooltip(
        controls.resetAllButton,
        function(self)
            return self:GetText()
        end,
        "Restores every option in this window to its default, including the Blizzard DR CVar toggles."
    )

    controls.previewButton = CreateActionButton(frame, S("UI_PREVIEW_BUTTON"), 160, function()
        if _G.ArenaDRNameplates_ToggleTestMode then
            _G.ArenaDRNameplates_ToggleTestMode()
        end
        SettingsUI.RefreshControls()
    end)
    controls.previewButton:SetPoint("RIGHT", controls.resetAllButton, "LEFT", -10, 0)
    AttachTooltip(
        controls.previewButton,
        function(self)
            return self:GetText()
        end,
        function()
            local isTestModeActive = _G.ArenaDRNameplates_IsTestModeActive and _G.ArenaDRNameplates_IsTestModeActive()
            return isTestModeActive and S("UI_ACTIONS_HELP_ACTIVE") or S("UI_ACTIONS_HELP_INACTIVE")
        end
    )

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(TITLEBAR_HEIGHT + 28))
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 40)

    local navBar = CreateFrame("Frame", nil, content)
    navBar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    navBar:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    navBar:SetWidth(NAV_WIDTH)

    local navBackground = navBar:CreateTexture(nil, "BACKGROUND")
    navBackground:SetAllPoints()
    navBackground:SetColorTexture(COLOR_TITLEBAR.r, COLOR_TITLEBAR.g, COLOR_TITLEBAR.b, 0.42)

    local navDivider = content:CreateTexture(nil, "BORDER")
    navDivider:SetPoint("TOPLEFT", navBar, "TOPRIGHT", 7, 0)
    navDivider:SetPoint("BOTTOMLEFT", navBar, "BOTTOMRIGHT", 7, 0)
    navDivider:SetWidth(1)
    navDivider:SetColorTexture(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.75)

    local navDefinitions = {
        { key = "general", text = S("UI_GENERAL_PAGE_NAME"), tooltip = "Core layout settings for the DR icon tray: size, opacity, spacing, and position around the nameplate." },
        { key = "trinket", text = S("UI_TRINKET_PAGE_NAME"), tooltip = "Enemy trinket icon options for the nameplate mirror. Disabled by default." },
        { key = "selfDR", text = S("UI_SELFDR_PAGE_NAME"), tooltip = "Diminishing returns applied to you, shown on a movable personal bar. Disabled by default." },
        { key = "targetFocusDR", text = S("UI_TARGETFOCUS_PAGE_NAME"), tooltip = S("UI_TARGETFOCUS_NAV_HELP") },
        { key = "timers", text = S("UI_TIMERS_PANEL_NAME"), tooltip = "Cooldown swipe and countdown text settings for each DR icon." },
        { key = "drText", text = S("UI_DR_TEXT_PANEL_NAME"), tooltip = "Controls the optional DR stage text that appears directly on the icon." },
        { key = "borders", text = S("UI_NAV_BORDERS"), tooltip = "Border styling and Blizzard immunity marker options." },
        { key = "share", text = S("UI_SHARE_PAGE_NAME"), tooltip = "Export or import this addon's setup string." },
    }

    local navOffset = 3
    for index, nav in ipairs(navDefinitions) do
        if index == 5 or index == 8 then
            navOffset = navOffset + NAV_GROUP_GAP
        end

        local button = CreateNavButton(navBar, nav.text, NAV_WIDTH - 8)
        button:SetPoint("TOPLEFT", navBar, "TOPLEFT", 4, -navOffset)
        navOffset = navOffset + NAV_BUTTON_HEIGHT + NAV_BUTTON_GAP

        button:SetScript("OnClick", function()
            SettingsUI.SelectPage(nav.key)
        end)
        AttachTooltip(
            button,
            function(self)
                return self.Text and self.Text:GetText()
            end,
            nav.tooltip,
            "ANCHOR_RIGHT"
        )

        SettingsUI.pageButtons[nav.key] = button
    end

    local pageContainer = CreateFrame("Frame", nil, content)
    pageContainer:SetPoint("TOPLEFT", navBar, "TOPRIGHT", NAV_CONTENT_GAP, 0)
    pageContainer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    SettingsUI.pages.general = CreateGeneralPage(pageContainer)
    SettingsUI.pages.trinket = CreateTrinketPage(pageContainer)
    SettingsUI.pages.selfDR = CreateSelfDRPage(pageContainer)
    SettingsUI.pages.targetFocusDR = CreateTargetFocusDRPage(pageContainer)
    SettingsUI.pages.timers = CreateTimersPage(pageContainer)
    SettingsUI.pages.drText = CreateDRTextPage(pageContainer)
    SettingsUI.pages.borders = CreateBordersPage(pageContainer)
    SettingsUI.pages.share = CreateSharePage(pageContainer)

    SettingsUI.window = frame
    SettingsUI.windowContent = content
end

function SettingsUI.InitializeSettingsLauncher()
    if SettingsUI.settingsPanel then
        return
    end

    local panel = CreateFrame("Frame")
    panel.name = addonName

    local title = CreateTitle(panel, S("UI_MAIN_HEADER"), "TOPLEFT", panel, "TOPLEFT", 16, -16)
    local description = CreateDescription(
        panel,
        S("UI_LAUNCHER_DESCRIPTION"),
        "TOPLEFT",
        title,
        "BOTTOMLEFT",
        0,
        -8,
        560
    )

    local openButton = CreateActionButton(panel, S("UI_OPEN_OPTIONS_WINDOW"), 200, function()
        SettingsUI.OpenPanel()
    end)
    openButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -18)

    controls.launcherPreviewButton = CreateActionButton(panel, S("UI_PREVIEW_BUTTON"), 160, function()
        if _G.ArenaDRNameplates_ToggleTestMode then
            _G.ArenaDRNameplates_ToggleTestMode()
        end
        SettingsUI.RefreshControls()
    end)
    controls.launcherPreviewButton:SetPoint("LEFT", openButton, "RIGHT", 12, 0)
    AttachTooltip(
        controls.launcherPreviewButton,
        function(self)
            return self:GetText()
        end,
        function()
            local isTestModeActive = _G.ArenaDRNameplates_IsTestModeActive and _G.ArenaDRNameplates_IsTestModeActive()
            return isTestModeActive and S("UI_ACTIONS_HELP_ACTIVE") or S("UI_ACTIONS_HELP_INACTIVE")
        end
    )

    local slashInfo = CreateDescription(
        panel,
        S("UI_LAUNCHER_SLASH_INFO"),
        "TOPLEFT",
        openButton,
        "BOTTOMLEFT",
        0,
        -12,
        560
    )

    local resetButton = CreateActionButton(panel, S("UI_RESET_ALL_BUTTON"), 160, function()
        StaticPopup_Show("ARENADRNAMEPLATES_CONFIRM_RESET")
    end)
    resetButton:SetPoint("TOPLEFT", slashInfo, "BOTTOMLEFT", 0, -18)

    panel.OnCommit = function()
    end

    panel.OnDefault = function()
        SettingsUI.ResetAllSettings()
    end

    panel.OnRefresh = function()
        SettingsUI.RefreshControls()
    end

    SettingsUI.settingsPanel = panel
    SettingsUI.category = RegisterSettingsCategory(panel)
    _G.ArenaDRNameplates_SettingsCategory = SettingsUI.category
end

function SettingsUI.Initialize()
    if SettingsUI.initialized then
        return
    end

    SettingsUI.initialized = true
    SettingsUI.EnsureDB()

    SettingsUI.InitializeSettingsLauncher()

    _G.ArenaDRNameplates_OpenSettingsWindow = function(pageKey)
        SettingsUI.OpenPanel(pageKey)
    end

    _G.ArenaDRNameplates_OpenSettingsLauncher = function()
        SettingsUI.OpenSettingsPanel()
    end

    _G.ArenaDRNameplates_RefreshSettingsUI = function()
        SettingsUI.RefreshControls()
    end

    _G.ArenaDRNameplates_GenerateExportString = function(selectText)
        return SettingsUI.GenerateExportString(selectText)
    end
end

function SettingsUI.EnsureStandaloneWindow()
    if not SettingsUI.initialized then
        SettingsUI.Initialize()
    end
    if SettingsUI.windowInitialized then
        return
    end

    SettingsUI.InitializeStandaloneWindow()
    SettingsUI.SelectPage(SettingsUI.selectedPage or "general")
    SettingsUI.RefreshControls()
end

function SettingsUI.OpenPanel(pageKey)
    if not SettingsUI.initialized then
        SettingsUI.Initialize()
    end

    SettingsUI.EnsureStandaloneWindow()

    if pageKey and SettingsUI.pages[pageKey] then
        SettingsUI.selectedPage = pageKey
    end

    HideSystemSettingsPanels()

    if SettingsUI.window then
        SettingsUI.window:Show()
        if SettingsUI.window.Raise then
            SettingsUI.window:Raise()
        end
    end
end

function SettingsUI.TogglePanel(pageKey)
    if not SettingsUI.initialized then
        SettingsUI.Initialize()
    end

    SettingsUI.EnsureStandaloneWindow()

    if SettingsUI.window and SettingsUI.window:IsShown() then
        SettingsUI.window:Hide()
        return
    end

    SettingsUI.OpenPanel(pageKey)
end

function SettingsUI.OpenSettingsPanel()
    if not SettingsUI.initialized then
        SettingsUI.Initialize()
    end

    if SettingsUI.window then
        SettingsUI.window:Hide()
    end

    if not OpenSettingsCategory(SettingsUI.category) then
        SettingsUI.OpenPanel()
    end
end
