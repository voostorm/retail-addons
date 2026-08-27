local _, ns = ...
ns = ns or {}

local Shared = ns.Shared or {}
ns.Shared = Shared

local BLIZZARD_DEFAULT_FONT = "__BLIZZARD_DEFAULT__"

local issecretvalue_fn = _G.issecretvalue

-- Midnight protects some values during combat; touching them raises an error.
local function IsSecretValue(value)
    if type(issecretvalue_fn) ~= "function" then
        return false
    end

    local ok, result = pcall(issecretvalue_fn, value)
    return ok and result == true
end

Shared.IsSecretValue = IsSecretValue

local defaults = {
    enabled = true,
    scale = 1.0,
    scaleWithNameplate = true,
    opacity = 1.0,
    iconLayout = "HORIZONTAL",
    iconGrowth = "RIGHT",
    iconVerticalGrowth = "UP",
    iconPadding = 2,
    textFont = BLIZZARD_DEFAULT_FONT,
    textOutline = "OUTLINE",
    timerTextColor = { 1, 1, 1 },
    timerTextScale = 1.0,
    timerTextOffsetX = 0,
    timerTextOffsetY = 0,
    showTimerText = true,
    showTimerDecimals = true,
    timerDecimalThreshold = 5,
    showTimerSwipe = true,
    showTimerSwipeEdge = false,
    showDRText = true,
    showImmunityIndicator = false,
    drTextAnchor = "BOTTOMRIGHT",
    drTextScale = 1.0,
    drTextOffsetX = 4,
    drTextOffsetY = -4,
    drTextColor = { 0, 1, 0 },
    drTextImmuneColor = { 1, 0, 0 },
    drBorderStyle = "SOLID",
    drBorderColor = { 0, 1, 0 },
    drBorderImmuneColor = { 1, 0, 0 },
    drBorderWidth = 1.5,
    anchorPreset = "BELOW",
    point = "TOP",
    relativePoint = "BOTTOM",
    offsetX = 0,
    offsetY = 0,
    trinket = {
        enabled = false,
        visibility = "COOLDOWN_ONLY",
        size = 22,
        opacity = 1.0,
        borderStyle = "SOLID",
        borderColor = { 0.95, 0.82, 0.24 },
        borderWidth = 1,
        anchorPreset = "ABOVE",
        point = "BOTTOM",
        relativePoint = "TOP",
        offsetX = 34,
        offsetY = 0,
    },
    selfDR = {
        enabled = false,
        locked = false,
        showInArena = true,
        showInBattleground = true,
        showInWorld = true,
        size = 32,
        opacity = 1.0,
        iconPadding = 4,
        iconLayout = "HORIZONTAL",
        iconGrowth = "RIGHT",
        iconVerticalGrowth = "DOWN",
        -- DR stage text follows the DR Text tab unless override is turned on.
        drText = {
            override = false,
            showDRText = true,
            drTextAnchor = "BOTTOMRIGHT",
            drTextScale = 1.0,
            drTextOffsetX = 4,
            drTextOffsetY = -4,
            drTextColor = { 0, 1, 0 },
            drTextImmuneColor = { 1, 0, 0 },
        },
        -- Timer styling follows the Timers tab unless override is turned on,
        -- in which case these values are used instead. Key names deliberately
        -- match the top-level ones so one resolver can serve both.
        timers = {
            override = false,
            showTimerSwipe = true,
            showTimerSwipeEdge = false,
            showTimerText = true,
            showTimerDecimals = true,
            timerDecimalThreshold = 5,
            timerTextColor = { 1, 1, 1 },
            timerTextScale = 1.0,
            timerTextOffsetX = 0,
            timerTextOffsetY = 0,
        },
        borderStyle = "SOLID",
        borderWidth = 1.5,
        borderColor = { 0, 1, 0 },
        borderImmuneColor = { 1, 0, 0 },
        relativeFrame = "PlayerFrame",
        point = "TOP",
        relativePoint = "BOTTOM",
        offsetX = 0,
        offsetY = -8,
        track = {
            stun = true,
            incapacitate = true,
            disorient = true,
            root = false,
            silence = false,
            disarm = false,
        },
    },
    targetFocusDR = {
        enabled = false,
        locked = false,
        showTarget = true,
        showFocus = true,
        size = 32,
        opacity = 1.0,
        iconPadding = 4,
        iconLayout = "HORIZONTAL",
        iconGrowth = "RIGHT",
        iconVerticalGrowth = "DOWN",
        borderStyle = "SOLID",
        borderWidth = 1.5,
        borderColor = { 0, 1, 0 },
        borderImmuneColor = { 1, 0, 0 },
        target = {
            scale = 1.0,
            timers = {
                override = false,
                timerTextColor = { 1, 1, 1 },
                timerTextScale = 1.0,
            },
            relativeFrame = "TargetFrame",
            point = "TOP",
            relativePoint = "BOTTOM",
            offsetX = 0,
            offsetY = -8,
        },
        focus = {
            scale = 1.0,
            timers = {
                override = false,
                timerTextColor = { 1, 1, 1 },
                timerTextScale = 1.0,
            },
            relativeFrame = "FocusFrame",
            point = "TOP",
            relativePoint = "BOTTOM",
            offsetX = 0,
            offsetY = -8,
        },
    },
}

-- Categories the Loss of Control API can actually report for the player.
-- Knockbacks are deliberately absent: C_LossOfControl never surfaces them.
local selfDRCategories = { "stun", "incapacitate", "disorient", "root", "silence", "disarm" }

local validDRTextAnchors = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local validBasicAnchorPoints = {
    TOP = true,
    BOTTOM = true,
    LEFT = true,
    RIGHT = true,
    CENTER = true,
}

local validAnchorPresets = {
    ABOVE = true,
    BELOW = true,
    LEFT = true,
    RIGHT = true,
    CENTER = true,
    ADVANCED = true,
}

local validIconGrowth = {
    LEFT = true,
    RIGHT = true,
    CENTER = true,
}

local validIconLayouts = {
    HORIZONTAL = true,
    VERTICAL = true,
}

local validVerticalIconGrowth = {
    UP = true,
    DOWN = true,
}

local validDRBorderStyles = {
    NONE = true,
    SOLID = true,
    CLASSIC = true,
}

local validTextOutlines = {
    NONE = true,
    OUTLINE = true,
    THICKOUTLINE = true,
    MONOCHROME = true,
    MONOCHROMEOUTLINE = true,
    MONOCHROMETHICKOUTLINE = true,
}

local validTrinketVisibilityModes = {
    ALWAYS = true,
    COOLDOWN_ONLY = true,
}

local validTrinketBorderStyles = {
    NONE = true,
    SOLID = true,
    CLASSIC = true,
}

local validSelfDRCategories = {}
for _, category in ipairs(selfDRCategories) do
    validSelfDRCategories[category] = true
end

local blizzardDRCVars = {
    enemiesEnabled = {
        cvar = "spellDiminishPVPEnemiesEnabled",
        defaultValue = true,
    },
    onlyTriggerableByMe = {
        cvar = "spellDiminishPVPOnlyTriggerableByMe",
        defaultValue = false,
    },
}

local frameNameCounter = 0
local deprecatedDBKeys = {
    timerColor = true,
    timerPosition = true,
    drBorderPadding = true,
}

Shared.defaults = defaults
Shared.iconBaseSizes = {
    nameplate = 26,
    trinket = defaults.trinket.size,
    selfDR = defaults.selfDR.size,
    targetFocusDR = defaults.targetFocusDR.size,
}

local validMovableAnchorFrames = {
    UIParent = true,
    PlayerFrame = true,
    TargetFrame = true,
    FocusFrame = true,
}

function Shared.ResolveMovableAnchorFrame(frameName)
    if validMovableAnchorFrames[frameName] then
        local frame = rawget(_G, frameName)
        if frame then
            return frame
        end
    end
    return UIParent
end
Shared.validDRTextAnchors = validDRTextAnchors
Shared.validIconGrowth = validIconGrowth
Shared.validIconLayouts = validIconLayouts
Shared.validVerticalIconGrowth = validVerticalIconGrowth
Shared.validDRBorderStyles = validDRBorderStyles
Shared.validTextOutlines = validTextOutlines
Shared.validTrinketVisibilityModes = validTrinketVisibilityModes
Shared.validTrinketBorderStyles = validTrinketBorderStyles
Shared.selfDRCategories = selfDRCategories
Shared.validSelfDRCategories = validSelfDRCategories
Shared.blizzardDRCVars = blizzardDRCVars
Shared.BLIZZARD_DEFAULT_FONT = BLIZZARD_DEFAULT_FONT
Shared.EXPORT_PREFIX = "ArenaDRNameplates:1:"

-- Midnight Season 2 PvP diminishing returns reset window, shared by the enemy
-- nameplate mirror and the personal DR tray.
Shared.DR_RESET_DURATION = 20

function Shared.S(key)
    local localeTable = ns and ns.L
    if type(localeTable) == "table" then
        local value = localeTable[key]
        if value ~= nil then
            return value
        end
    end
    return key
end

local function SanitizeFrameNamePart(value, fallback)
    value = tostring(value or fallback or "Frame"):gsub("[^%w_]", "")
    if value == "" then
        return fallback or "Frame"
    end
    return value
end

function Shared.NextFrameName(scope, kind, explicitID)
    local scopePart = SanitizeFrameNamePart(scope, "General")
    local kindPart = SanitizeFrameNamePart(kind, "Frame")

    if explicitID ~= nil then
        return string.format(
            "ArenaDrNP_%s_%s_%s",
            scopePart,
            kindPart,
            SanitizeFrameNamePart(explicitID, "0")
        )
    end

    frameNameCounter = frameNameCounter + 1
    return string.format("ArenaDrNP_%s_%s_%03d", scopePart, kindPart, frameNameCounter)
end

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            copy[key] = CopyTable(value)
        else
            copy[key] = value
        end
    end
    return copy
end

Shared.CopyTable = CopyTable

function Shared.CopyDefaultsIntoTable(target, clearExisting)
    if type(target) ~= "table" then
        return target
    end

    if clearExisting then
        for key in pairs(target) do
            target[key] = nil
        end
    end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = CopyTable(value)
        else
            target[key] = value
        end
    end

    return target
end

function Shared.ClampColorChannel(value, fallback)
    value = tonumber(value)
    if value == nil then
        value = fallback
    end

    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return value
end

function Shared.NormalizeColorTable(color, fallback)
    fallback = fallback or { 1, 1, 1 }
    local source = type(color) == "table" and color or fallback

    return {
        Shared.ClampColorChannel(source[1] or source.r, fallback[1] or 1),
        Shared.ClampColorChannel(source[2] or source.g, fallback[2] or 1),
        Shared.ClampColorChannel(source[3] or source.b, fallback[3] or 1),
    }
end

function Shared.ClampNumber(value, minimum, maximum, fallback)
    value = tonumber(value)
    if value == nil then
        value = fallback
    end

    if minimum ~= nil and value < minimum then
        value = minimum
    end
    if maximum ~= nil and value > maximum then
        value = maximum
    end

    return value
end

local function GetEffectiveFrameScale(frame, fallback)
    if frame and type(frame.GetEffectiveScale) == "function" then
        local ok, scale = pcall(frame.GetEffectiveScale, frame)
        if ok and not IsSecretValue(scale) and type(scale) == "number" and scale > 0 then
            return scale
        end
    end

    return fallback or 1
end

-- Every addon icon is authored at a fixed logical size. This returns the
-- multiplier callers apply to physical child sizes, text, borders, and
-- spacing without scaling the positioned parent frame or its anchor offsets.
-- Passing inheritParentScale=false compensates for the parent's effective
-- scale, which is how nameplate DR trays can keep a fixed visual size.
function Shared.ResolveIconScale(
    baseIconSize,
    desiredIconSize,
    componentScale,
    parent,
    inheritParentScale
)
    baseIconSize = math.max(1, tonumber(baseIconSize) or 1)
    desiredIconSize = math.max(1, tonumber(desiredIconSize) or baseIconSize)
    componentScale = tonumber(componentScale) or 1
    if componentScale <= 0 then
        componentScale = 1
    end

    local resolvedScale = (desiredIconSize / baseIconSize) * componentScale
    if inheritParentScale == false then
        local uiScale = GetEffectiveFrameScale(UIParent, 1)
        local parentScale = GetEffectiveFrameScale(parent, uiScale)
        resolvedScale = resolvedScale * (uiScale / parentScale)
    end

    return resolvedScale
end

function Shared.NormalizeIconGrowth(value)
    value = tostring(value or "")
    if validIconGrowth[value] then
        return value
    end
    return defaults.iconGrowth
end

function Shared.NormalizeIconLayout(value)
    value = tostring(value or "")
    if validIconLayouts[value] then
        return value
    end
    return defaults.iconLayout
end

function Shared.NormalizeVerticalIconGrowth(value)
    value = tostring(value or "")
    if validVerticalIconGrowth[value] then
        return value
    end
    return defaults.iconVerticalGrowth
end

function Shared.NormalizeDRBorderStyle(value)
    value = tostring(value or "")
    if validDRBorderStyles[value] then
        return value
    end
    return defaults.drBorderStyle
end

function Shared.NormalizeTrinketVisibility(value)
    value = tostring(value or "")
    if validTrinketVisibilityModes[value] then
        return value
    end
    return defaults.trinket.visibility
end

local function GetLibSharedMedia()
    if type(LibStub) ~= "table" or type(LibStub.GetLibrary) ~= "function" then
        return nil
    end

    local ok, sharedMedia = pcall(LibStub.GetLibrary, LibStub, "LibSharedMedia-3.0", true)
    if ok and type(sharedMedia) == "table" then
        return sharedMedia
    end
end

Shared.GetLibSharedMedia = GetLibSharedMedia

local function GetBlizzardDefaultFontPath()
    if type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT ~= "" then
        return STANDARD_TEXT_FONT
    end

    if GameFontNormal and type(GameFontNormal.GetFont) == "function" then
        local ok, path = pcall(GameFontNormal.GetFont, GameFontNormal)
        if ok and type(path) == "string" and path ~= "" then
            return path
        end
    end

    return [[Fonts\FRIZQT__.TTF]]
end

Shared.GetBlizzardDefaultFontPath = GetBlizzardDefaultFontPath

local function NormalizeFontPath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    return string.lower(path:gsub("/", "\\"))
end

Shared.NormalizeFontPath = NormalizeFontPath

local function GetSharedMediaFontTable()
    local sharedMedia = GetLibSharedMedia()
    if not sharedMedia or type(sharedMedia.HashTable) ~= "function" then
        return nil
    end

    local ok, fonts = pcall(sharedMedia.HashTable, sharedMedia, "font")
    if ok and type(fonts) == "table" then
        return fonts
    end
end

-- Resolving a font key walked LibStub and rebuilt LibSharedMedia's hash table on
-- every styled font string. The DR trays restyle whole rows of icons at a time,
-- so the answer is cached until a font is registered or the settings change.
local resolvedFontPaths = {}

function Shared.InvalidateFontCache()
    for key in pairs(resolvedFontPaths) do
        resolvedFontPaths[key] = nil
    end
end

function Shared.ResolveTextFontPath(fontKey)
    local fallbackPath = GetBlizzardDefaultFontPath()
    if fontKey == nil or fontKey == "" or fontKey == BLIZZARD_DEFAULT_FONT then
        return fallbackPath, true
    end

    local cached = resolvedFontPaths[fontKey]
    if cached ~= nil then
        return cached, true
    end

    local fonts = GetSharedMediaFontTable()
    local path = fonts and fonts[fontKey]
    if type(path) == "string" and path ~= "" then
        -- Only a resolved font is remembered. A key that is not registered yet
        -- belongs to an addon that may still load.
        resolvedFontPaths[fontKey] = path
        return path, true
    end

    return fallbackPath, false
end

function Shared.GetTextFontOptions()
    local fallbackPath = GetBlizzardDefaultFontPath()
    local fallbackNormalizedPath = NormalizeFontPath(fallbackPath)
    local options = {
        {
            value = BLIZZARD_DEFAULT_FONT,
            text = Shared.S("UI_TEXT_FONT_BLIZZARD_DEFAULT"),
            path = fallbackPath,
            normalizedPath = fallbackNormalizedPath,
        },
    }
    local seenPaths = {}
    if fallbackNormalizedPath then
        seenPaths[fallbackNormalizedPath] = true
    end

    local fonts = GetSharedMediaFontTable()
    if not fonts then
        return options
    end

    local keys = {}
    for key, path in pairs(fonts) do
        if type(key) == "string" and key ~= "" and type(path) == "string" and path ~= "" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        local path = fonts[key]
        local normalizedPath = NormalizeFontPath(path)
        if normalizedPath and not seenPaths[normalizedPath] then
            seenPaths[normalizedPath] = true
            options[#options + 1] = {
                value = key,
                text = key,
                path = path,
                normalizedPath = normalizedPath,
            }
        end
    end

    return options
end
function Shared.GetTextFontDropdownValue(fontKey)
    if fontKey == nil or fontKey == "" or fontKey == BLIZZARD_DEFAULT_FONT then
        return BLIZZARD_DEFAULT_FONT, true
    end

    local path, available = Shared.ResolveTextFontPath(fontKey)
    if not available then
        return BLIZZARD_DEFAULT_FONT, false
    end

    local normalizedPath = NormalizeFontPath(path)
    for _, option in ipairs(Shared.GetTextFontOptions()) do
        if option.normalizedPath == normalizedPath then
            return option.value, true
        end
    end

    return BLIZZARD_DEFAULT_FONT, false
end

function Shared.GetTextFontDisplayText(fontKey)
    local dropdownValue, available = Shared.GetTextFontDropdownValue(fontKey)
    if not available then
        return Shared.S("UI_TEXT_FONT_UNAVAILABLE")
    end

    for _, option in ipairs(Shared.GetTextFontOptions()) do
        if option.value == dropdownValue then
            return option.text
        end
    end

    return Shared.S("UI_TEXT_FONT_BLIZZARD_DEFAULT")
end

-- SetFont takes a comma separated flag string and spells "no outline" as an
-- empty string, so the stored display key is mapped instead of being passed
-- through.
local textOutlineFlagStrings = {
    NONE = "",
    OUTLINE = "OUTLINE",
    THICKOUTLINE = "THICKOUTLINE",
    MONOCHROME = "MONOCHROME",
    MONOCHROMEOUTLINE = "MONOCHROME,OUTLINE",
    MONOCHROMETHICKOUTLINE = "MONOCHROME,THICKOUTLINE",
}

function Shared.NormalizeTextOutline(value)
    value = string.upper(tostring(value or ""))
    if validTextOutlines[value] then
        return value
    end
    return defaults.textOutline
end

function Shared.GetTextOutlineFlags(outlineKey)
    if outlineKey == nil then
        local currentDB = rawget(_G, "ArenaDRNameplatesDB")
        outlineKey = type(currentDB) == "table" and currentDB.textOutline or defaults.textOutline
    end

    return textOutlineFlagStrings[Shared.NormalizeTextOutline(outlineKey)]
end

function Shared.GetTextOutlineOptions()
    return {
        { value = "NONE", text = Shared.S("UI_TEXT_OUTLINE_NONE") },
        { value = "OUTLINE", text = Shared.S("UI_TEXT_OUTLINE_THIN") },
        { value = "THICKOUTLINE", text = Shared.S("UI_TEXT_OUTLINE_THICK") },
        { value = "MONOCHROME", text = Shared.S("UI_TEXT_OUTLINE_MONOCHROME") },
        { value = "MONOCHROMEOUTLINE", text = Shared.S("UI_TEXT_OUTLINE_MONOCHROME_THIN") },
        { value = "MONOCHROMETHICKOUTLINE", text = Shared.S("UI_TEXT_OUTLINE_MONOCHROME_THICK") },
    }
end

function Shared.GetTextOutlineDisplayText(outlineKey)
    local normalized = Shared.NormalizeTextOutline(outlineKey)
    for _, option in ipairs(Shared.GetTextOutlineOptions()) do
        if option.value == normalized then
            return option.text
        end
    end

    return Shared.S("UI_TEXT_OUTLINE_THIN")
end

function Shared.ApplyTextFont(fontString, fontSize, flags, fontKey)
    if not fontString or type(fontString.SetFont) ~= "function" then
        return false
    end

    if fontKey == nil then
        local currentDB = rawget(_G, "ArenaDRNameplatesDB")
        fontKey = type(currentDB) == "table" and currentDB.textFont or defaults.textFont
    end

    if flags == nil then
        flags = Shared.GetTextOutlineFlags()
    end

    local path = Shared.ResolveTextFontPath(fontKey)
    local ok, applied = pcall(fontString.SetFont, fontString, path, fontSize, flags)
    if ok and applied ~= false then
        return true
    end

    local fallbackPath = GetBlizzardDefaultFontPath()
    if path ~= fallbackPath then
        ok, applied = pcall(fontString.SetFont, fontString, fallbackPath, fontSize, flags)
        if ok and applied ~= false then
            return true
        end
    end

    return false
end

function Shared.NormalizeTrinketBorderStyle(value)
    value = tostring(value or "")
    if validTrinketBorderStyles[value] then
        return value
    end
    return defaults.trinket.borderStyle
end

-- Movable trays share one deliberately lightweight empty-state treatment.
-- The returned regions can also be shown behind preview/live icons while a
-- tray is unlocked, so callers only decide visibility rather than rebuilding
-- their own placeholder widgets.
function Shared.CreateMovableTrayPlaceholder(frame, labelText)
    if not frame then
        return nil, nil
    end

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0.45, 0.75, 0.22)
    background:Hide()

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", frame, "TOP", 0, 4)
    label:SetText(tostring(labelText or ""))
    label:Hide()

    return background, label
end

-- Anchor points split into their two axis components, and back again.
local ANCHOR_POINT_AXES = {
    TOPLEFT = { "TOP", "LEFT" },
    TOP = { "TOP", "CENTER" },
    TOPRIGHT = { "TOP", "RIGHT" },
    LEFT = { "MIDDLE", "LEFT" },
    CENTER = { "MIDDLE", "CENTER" },
    RIGHT = { "MIDDLE", "RIGHT" },
    BOTTOMLEFT = { "BOTTOM", "LEFT" },
    BOTTOM = { "BOTTOM", "CENTER" },
    BOTTOMRIGHT = { "BOTTOM", "RIGHT" },
}

local ANCHOR_POINTS_BY_AXES = {
    TOP = { LEFT = "TOPLEFT", CENTER = "TOP", RIGHT = "TOPRIGHT" },
    MIDDLE = { LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT" },
    BOTTOM = { LEFT = "BOTTOMLEFT", CENTER = "BOTTOM", RIGHT = "BOTTOMRIGHT" },
}

local ANCHOR_POINT_FACTORS = {
    TOPLEFT = { -0.5, 0.5 },
    TOP = { 0, 0.5 },
    TOPRIGHT = { 0.5, 0.5 },
    LEFT = { -0.5, 0 },
    CENTER = { 0, 0 },
    RIGHT = { 0.5, 0 },
    BOTTOMLEFT = { -0.5, -0.5 },
    BOTTOM = { 0, -0.5 },
    BOTTOMRIGHT = { 0.5, -0.5 },
}

-- Where a given point of a frame sits relative to that frame's center.
function Shared.GetPointOffset(point, width, height)
    local factors = ANCHOR_POINT_FACTORS[tostring(point or "CENTER")] or ANCHOR_POINT_FACTORS.CENTER
    return (width * factors[1]), (height * factors[2])
end

-- A tray is sized to fit its icons exactly, so the edge it is anchored from is
-- what decides which way it expands. Growing left keeps the right edge fixed.
local HORIZONTAL_GROWTH_ANCHORS = { LEFT = "RIGHT", RIGHT = "LEFT", CENTER = "CENTER" }
local VERTICAL_GROWTH_ANCHORS = { UP = "BOTTOM", DOWN = "TOP" }

function Shared.ResolveGrowthAnchorPoint(point, iconLayout, growth)
    local axes = ANCHOR_POINT_AXES[tostring(point or "CENTER")] or ANCHOR_POINT_AXES.CENTER
    local vertical, horizontal = axes[1], axes[2]

    -- Only the stacking axis is forced. The tray is exactly one icon wide on
    -- the other one, so the caller's compensation cancels out there.
    if Shared.NormalizeIconLayout(iconLayout) == "VERTICAL" then
        vertical = VERTICAL_GROWTH_ANCHORS[Shared.NormalizeVerticalIconGrowth(growth)]
    else
        horizontal = HORIZONTAL_GROWTH_ANCHORS[Shared.NormalizeIconGrowth(growth)]
    end

    return ANCHOR_POINTS_BY_AXES[vertical][horizontal]
end

-- Anchoring a frame from a different point of itself also moves it, so the
-- offsets are compensated on a single-icon tray: only the fixed edge changes.
function Shared.ResolveGrowthAnchor(point, iconLayout, growth, baseSize, offsetX, offsetY)
    local resolvedPoint = Shared.ResolveGrowthAnchorPoint(point, iconLayout, growth)
    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 0

    if resolvedPoint == point then
        return resolvedPoint, offsetX, offsetY
    end

    baseSize = math.max(1, tonumber(baseSize) or 1)
    local oldX, oldY = Shared.GetPointOffset(point, baseSize, baseSize)
    local newX, newY = Shared.GetPointOffset(resolvedPoint, baseSize, baseSize)

    return resolvedPoint, offsetX + (newX - oldX), offsetY + (newY - oldY)
end

-- Dragging saves a position measured from the frame's center, while the layout
-- anchors from its growth edge. Drag handlers fold this difference into the
-- saved offsets so a dragged tray does not jump on the next layout pass.
function Shared.GetGrowthAnchorSaveOffset(iconLayout, growth, baseSize, width, height)
    local resolvedPoint = Shared.ResolveGrowthAnchorPoint("CENTER", iconLayout, growth)
    baseSize = math.max(1, tonumber(baseSize) or 1)
    local baseX, baseY = Shared.GetPointOffset(resolvedPoint, baseSize, baseSize)
    local sizeX, sizeY = Shared.GetPointOffset(resolvedPoint, width, height)

    return sizeX - baseX, sizeY - baseY
end

function Shared.CalculateTrayLayout(iconCount, iconSize, spacing, iconLayout)
    iconCount = math.max(tonumber(iconCount) or 0, 0)
    iconSize = math.max(1, tonumber(iconSize) or 1)
    spacing = math.max(0, tonumber(spacing) or 0)
    iconLayout = tostring(iconLayout or "HORIZONTAL")

    local totalLength = iconSize
    if iconCount > 0 then
        totalLength = (iconCount * iconSize) + (math.max(iconCount - 1, 0) * spacing)
    end

    if iconLayout == "VERTICAL" then
        return iconSize, totalLength, iconSize + spacing
    end

    return totalLength, iconSize, iconSize + spacing
end

function Shared.AnchorChildByGrowth(child, tray, iconLayout, growth, index, childCount, iconPitch)
    child:ClearAllPoints()

    if iconLayout == "VERTICAL" then
        if growth == "UP" then
            child:SetPoint("BOTTOM", tray, "BOTTOM", 0, (index - 1) * iconPitch)
            return
        end

        if growth == "DOWN" then
            child:SetPoint("TOP", tray, "TOP", 0, -((index - 1) * iconPitch))
            return
        end

        local centerOffsetY = (((childCount + 1) / 2) - index) * iconPitch
        child:SetPoint("CENTER", tray, "CENTER", 0, centerOffsetY)
        return
    end

    -- Like the vertical branch above: the first child sits on the anchored edge.
    if growth == "LEFT" then
        child:SetPoint("RIGHT", tray, "RIGHT", -((index - 1) * iconPitch), 0)
        return
    end

    if growth == "RIGHT" then
        child:SetPoint("LEFT", tray, "LEFT", (index - 1) * iconPitch, 0)
        return
    end

    local centerOffset = (index - ((childCount + 1) / 2)) * iconPitch
    child:SetPoint("CENTER", tray, "CENTER", centerOffset, 0)
end

local function CVarValueToBool(value, fallback)
    if value == nil then
        return fallback == true
    end
    if value == true or value == 1 then
        return true
    end
    if value == false or value == 0 then
        return false
    end

    value = string.lower(tostring(value))
    if value == "1" or value == "true" then
        return true
    end
    if value == "0" or value == "false" then
        return false
    end

    return fallback == true
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local ok, result = pcall(func, ...)
    if ok then
        return result
    end
end

function Shared.IsCVarAvailable(cvarName)
    cvarName = tostring(cvarName or "")
    if cvarName == "" then
        return false
    end

    return SafeCall(C_CVar.GetCVarInfo, cvarName) ~= nil
end

function Shared.GetCVarBool(cvarName, fallback)
    cvarName = tostring(cvarName or "")
    if cvarName == "" then
        return fallback == true
    end

    local value = SafeCall(C_CVar.GetCVarBool, cvarName)
    if value ~= nil then
        return CVarValueToBool(value, fallback)
    end

    value = SafeCall(C_CVar.GetCVar, cvarName)
    if value ~= nil then
        return CVarValueToBool(value, fallback)
    end

    return fallback == true
end

function Shared.GetCVarDefaultBool(cvarName, fallback)
    cvarName = tostring(cvarName or "")
    if cvarName == "" then
        return fallback == true
    end

    local value = SafeCall(C_CVar.GetCVarDefault, cvarName)
    if value ~= nil then
        return CVarValueToBool(value, fallback)
    end

    return fallback == true
end

function Shared.SetCVarBool(cvarName, enabled)
    cvarName = tostring(cvarName or "")
    if cvarName == "" then
        return false
    end

    local value = enabled and "1" or "0"
    return pcall(C_CVar.SetCVar, cvarName, value) == true
end

function Shared.ResetBlizzardDRCVarsToDefaults()
    for _, info in pairs(blizzardDRCVars) do
        if type(info) == "table" and Shared.IsCVarAvailable(info.cvar) then
            Shared.SetCVarBool(info.cvar, Shared.GetCVarDefaultBool(info.cvar, info.defaultValue))
        end
    end
end

local exportDBFields = {
    { key = "scale", path = { "scale" }, kind = "number" },
    { key = "scaleWithNameplate", path = { "scaleWithNameplate" }, kind = "boolean" },
    { key = "opacity", path = { "opacity" }, kind = "number" },
    { key = "iconLayout", path = { "iconLayout" }, kind = "string", valid = validIconLayouts },
    { key = "iconGrowthDirection", path = { "iconGrowth" }, kind = "string", valid = validIconGrowth },
    { key = "iconVerticalGrowth", path = { "iconVerticalGrowth" }, kind = "string", valid = validVerticalIconGrowth },
    { key = "iconPadding", path = { "iconPadding" }, kind = "number" },
    { key = "textFont", path = { "textFont" }, kind = "string" },
    { key = "textOutline", path = { "textOutline" }, kind = "string", valid = validTextOutlines },
    { key = "anchorPreset", path = { "anchorPreset" }, kind = "string", valid = validAnchorPresets },
    { key = "point", path = { "point" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "relativePoint", path = { "relativePoint" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "offsetX", path = { "offsetX" }, kind = "number" },
    { key = "offsetY", path = { "offsetY" }, kind = "number" },
    { key = "showTimerSwipe", path = { "showTimerSwipe" }, kind = "boolean" },
    { key = "showTimerSwipeEdge", path = { "showTimerSwipeEdge" }, kind = "boolean" },
    { key = "showTimerText", path = { "showTimerText" }, kind = "boolean" },
    { key = "showTimerDecimals", path = { "showTimerDecimals" }, kind = "boolean" },
    { key = "timerDecimalThreshold", path = { "timerDecimalThreshold" }, kind = "number" },
    { key = "timerTextColor", path = { "timerTextColor" }, kind = "color" },
    { key = "timerTextScale", path = { "timerTextScale" }, kind = "number" },
    { key = "timerTextOffsetX", path = { "timerTextOffsetX" }, kind = "number" },
    { key = "timerTextOffsetY", path = { "timerTextOffsetY" }, kind = "number" },
    { key = "showDRText", path = { "showDRText" }, kind = "boolean" },
    { key = "drTextAnchor", path = { "drTextAnchor" }, kind = "string", valid = validDRTextAnchors },
    { key = "drTextScale", path = { "drTextScale" }, kind = "number" },
    { key = "drTextOffsetX", path = { "drTextOffsetX" }, kind = "number" },
    { key = "drTextOffsetY", path = { "drTextOffsetY" }, kind = "number" },
    { key = "drTextColor", path = { "drTextColor" }, kind = "color" },
    { key = "drTextImmuneColor", path = { "drTextImmuneColor" }, kind = "color" },
    { key = "showImmunityIndicator", path = { "showImmunityIndicator" }, kind = "boolean" },
    { key = "drBorderStyle", path = { "drBorderStyle" }, kind = "string", valid = validDRBorderStyles },
    { key = "drBorderColor", path = { "drBorderColor" }, kind = "color" },
    { key = "drBorderImmuneColor", path = { "drBorderImmuneColor" }, kind = "color" },
    { key = "drBorderWidth", path = { "drBorderWidth" }, kind = "number" },
    { key = "trinket.enabled", path = { "trinket", "enabled" }, kind = "boolean" },
    { key = "trinket.visibility", path = { "trinket", "visibility" }, kind = "string", valid = validTrinketVisibilityModes },
    { key = "trinket.size", path = { "trinket", "size" }, kind = "number" },
    { key = "trinket.opacity", path = { "trinket", "opacity" }, kind = "number" },
    { key = "trinket.borderStyle", path = { "trinket", "borderStyle" }, kind = "string", valid = validTrinketBorderStyles },
    { key = "trinket.borderColor", path = { "trinket", "borderColor" }, kind = "color" },
    { key = "trinket.borderWidth", path = { "trinket", "borderWidth" }, kind = "number" },
    { key = "trinket.anchorPreset", path = { "trinket", "anchorPreset" }, kind = "string", valid = validAnchorPresets },
    { key = "trinket.point", path = { "trinket", "point" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "trinket.relativePoint", path = { "trinket", "relativePoint" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "trinket.offsetX", path = { "trinket", "offsetX" }, kind = "number" },
    { key = "trinket.offsetY", path = { "trinket", "offsetY" }, kind = "number" },
    { key = "selfDR.enabled", path = { "selfDR", "enabled" }, kind = "boolean" },
    { key = "selfDR.locked", path = { "selfDR", "locked" }, kind = "boolean" },
    { key = "selfDR.showInArena", path = { "selfDR", "showInArena" }, kind = "boolean" },
    { key = "selfDR.showInBattleground", path = { "selfDR", "showInBattleground" }, kind = "boolean" },
    { key = "selfDR.showInWorld", path = { "selfDR", "showInWorld" }, kind = "boolean" },
    { key = "selfDR.size", path = { "selfDR", "size" }, kind = "number" },
    { key = "selfDR.opacity", path = { "selfDR", "opacity" }, kind = "number" },
    { key = "selfDR.iconPadding", path = { "selfDR", "iconPadding" }, kind = "number" },
    { key = "selfDR.iconLayout", path = { "selfDR", "iconLayout" }, kind = "string", valid = validIconLayouts },
    { key = "selfDR.iconGrowthDirection", path = { "selfDR", "iconGrowth" }, kind = "string", valid = validIconGrowth },
    { key = "selfDR.iconVerticalGrowth", path = { "selfDR", "iconVerticalGrowth" }, kind = "string", valid = validVerticalIconGrowth },
    { key = "selfDR.timers.override", path = { "selfDR", "timers", "override" }, kind = "boolean" },
    { key = "selfDR.timers.showTimerSwipe", path = { "selfDR", "timers", "showTimerSwipe" }, kind = "boolean" },
    { key = "selfDR.timers.showTimerSwipeEdge", path = { "selfDR", "timers", "showTimerSwipeEdge" }, kind = "boolean" },
    { key = "selfDR.timers.showTimerText", path = { "selfDR", "timers", "showTimerText" }, kind = "boolean" },
    { key = "selfDR.timers.showTimerDecimals", path = { "selfDR", "timers", "showTimerDecimals" }, kind = "boolean" },
    { key = "selfDR.timers.timerDecimalThreshold", path = { "selfDR", "timers", "timerDecimalThreshold" }, kind = "number" },
    { key = "selfDR.timers.timerTextColor", path = { "selfDR", "timers", "timerTextColor" }, kind = "color" },
    { key = "selfDR.timers.timerTextScale", path = { "selfDR", "timers", "timerTextScale" }, kind = "number" },
    { key = "selfDR.timers.timerTextOffsetX", path = { "selfDR", "timers", "timerTextOffsetX" }, kind = "number" },
    { key = "selfDR.timers.timerTextOffsetY", path = { "selfDR", "timers", "timerTextOffsetY" }, kind = "number" },
    { key = "selfDR.drText.override", path = { "selfDR", "drText", "override" }, kind = "boolean" },
    { key = "selfDR.drText.showDRText", path = { "selfDR", "drText", "showDRText" }, kind = "boolean" },
    { key = "selfDR.drText.drTextAnchor", path = { "selfDR", "drText", "drTextAnchor" }, kind = "string", valid = validDRTextAnchors },
    { key = "selfDR.drText.drTextScale", path = { "selfDR", "drText", "drTextScale" }, kind = "number" },
    { key = "selfDR.drText.drTextOffsetX", path = { "selfDR", "drText", "drTextOffsetX" }, kind = "number" },
    { key = "selfDR.drText.drTextOffsetY", path = { "selfDR", "drText", "drTextOffsetY" }, kind = "number" },
    { key = "selfDR.drText.drTextColor", path = { "selfDR", "drText", "drTextColor" }, kind = "color" },
    { key = "selfDR.drText.drTextImmuneColor", path = { "selfDR", "drText", "drTextImmuneColor" }, kind = "color" },
    { key = "selfDR.borderStyle", path = { "selfDR", "borderStyle" }, kind = "string", valid = validDRBorderStyles },
    { key = "selfDR.borderWidth", path = { "selfDR", "borderWidth" }, kind = "number" },
    { key = "selfDR.borderColor", path = { "selfDR", "borderColor" }, kind = "color" },
    { key = "selfDR.borderImmuneColor", path = { "selfDR", "borderImmuneColor" }, kind = "color" },
    { key = "selfDR.relativeFrame", path = { "selfDR", "relativeFrame" }, kind = "string", valid = validMovableAnchorFrames },
    { key = "selfDR.point", path = { "selfDR", "point" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "selfDR.relativePoint", path = { "selfDR", "relativePoint" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "selfDR.offsetX", path = { "selfDR", "offsetX" }, kind = "number" },
    { key = "selfDR.offsetY", path = { "selfDR", "offsetY" }, kind = "number" },
    { key = "selfDR.track.stun", path = { "selfDR", "track", "stun" }, kind = "boolean" },
    { key = "selfDR.track.incapacitate", path = { "selfDR", "track", "incapacitate" }, kind = "boolean" },
    { key = "selfDR.track.disorient", path = { "selfDR", "track", "disorient" }, kind = "boolean" },
    { key = "selfDR.track.root", path = { "selfDR", "track", "root" }, kind = "boolean" },
    { key = "selfDR.track.silence", path = { "selfDR", "track", "silence" }, kind = "boolean" },
    { key = "selfDR.track.disarm", path = { "selfDR", "track", "disarm" }, kind = "boolean" },
    { key = "targetFocusDR.enabled", path = { "targetFocusDR", "enabled" }, kind = "boolean" },
    { key = "targetFocusDR.locked", path = { "targetFocusDR", "locked" }, kind = "boolean" },
    { key = "targetFocusDR.showTarget", path = { "targetFocusDR", "showTarget" }, kind = "boolean" },
    { key = "targetFocusDR.showFocus", path = { "targetFocusDR", "showFocus" }, kind = "boolean" },
    { key = "targetFocusDR.size", path = { "targetFocusDR", "size" }, kind = "number" },
    { key = "targetFocusDR.opacity", path = { "targetFocusDR", "opacity" }, kind = "number" },
    { key = "targetFocusDR.iconPadding", path = { "targetFocusDR", "iconPadding" }, kind = "number" },
    { key = "targetFocusDR.iconLayout", path = { "targetFocusDR", "iconLayout" }, kind = "string", valid = validIconLayouts },
    { key = "targetFocusDR.iconGrowthDirection", path = { "targetFocusDR", "iconGrowth" }, kind = "string", valid = validIconGrowth },
    { key = "targetFocusDR.iconVerticalGrowth", path = { "targetFocusDR", "iconVerticalGrowth" }, kind = "string", valid = validVerticalIconGrowth },
    { key = "targetFocusDR.borderStyle", path = { "targetFocusDR", "borderStyle" }, kind = "string", valid = validDRBorderStyles },
    { key = "targetFocusDR.borderWidth", path = { "targetFocusDR", "borderWidth" }, kind = "number" },
    { key = "targetFocusDR.borderColor", path = { "targetFocusDR", "borderColor" }, kind = "color" },
    { key = "targetFocusDR.borderImmuneColor", path = { "targetFocusDR", "borderImmuneColor" }, kind = "color" },
    { key = "targetFocusDR.target.scale", path = { "targetFocusDR", "target", "scale" }, kind = "number" },
    { key = "targetFocusDR.target.timers.override", path = { "targetFocusDR", "target", "timers", "override" }, kind = "boolean" },
    { key = "targetFocusDR.target.timers.timerTextColor", path = { "targetFocusDR", "target", "timers", "timerTextColor" }, kind = "color" },
    { key = "targetFocusDR.target.timers.timerTextScale", path = { "targetFocusDR", "target", "timers", "timerTextScale" }, kind = "number" },
    { key = "targetFocusDR.target.relativeFrame", path = { "targetFocusDR", "target", "relativeFrame" }, kind = "string", valid = validMovableAnchorFrames },
    { key = "targetFocusDR.target.point", path = { "targetFocusDR", "target", "point" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "targetFocusDR.target.relativePoint", path = { "targetFocusDR", "target", "relativePoint" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "targetFocusDR.target.offsetX", path = { "targetFocusDR", "target", "offsetX" }, kind = "number" },
    { key = "targetFocusDR.target.offsetY", path = { "targetFocusDR", "target", "offsetY" }, kind = "number" },
    { key = "targetFocusDR.focus.scale", path = { "targetFocusDR", "focus", "scale" }, kind = "number" },
    { key = "targetFocusDR.focus.timers.override", path = { "targetFocusDR", "focus", "timers", "override" }, kind = "boolean" },
    { key = "targetFocusDR.focus.timers.timerTextColor", path = { "targetFocusDR", "focus", "timers", "timerTextColor" }, kind = "color" },
    { key = "targetFocusDR.focus.timers.timerTextScale", path = { "targetFocusDR", "focus", "timers", "timerTextScale" }, kind = "number" },
    { key = "targetFocusDR.focus.relativeFrame", path = { "targetFocusDR", "focus", "relativeFrame" }, kind = "string", valid = validMovableAnchorFrames },
    { key = "targetFocusDR.focus.point", path = { "targetFocusDR", "focus", "point" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "targetFocusDR.focus.relativePoint", path = { "targetFocusDR", "focus", "relativePoint" }, kind = "string", valid = validBasicAnchorPoints },
    { key = "targetFocusDR.focus.offsetX", path = { "targetFocusDR", "focus", "offsetX" }, kind = "number" },
    { key = "targetFocusDR.focus.offsetY", path = { "targetFocusDR", "focus", "offsetY" }, kind = "number" },
}

-- Growth used to be exported as the tray edge the icons started from, which is
-- the mirror of the direction it grows. Old profile strings still land right.
local legacyGrowthExportFields = {
    { key = "iconGrowth", path = { "iconGrowth" }, kind = "string", valid = validIconGrowth },
    { key = "selfDR.iconGrowth", path = { "selfDR", "iconGrowth" }, kind = "string", valid = validIconGrowth },
    { key = "targetFocusDR.iconGrowth", path = { "targetFocusDR", "iconGrowth" }, kind = "string", valid = validIconGrowth },
}

local mirroredHorizontalGrowth = { LEFT = "RIGHT", RIGHT = "LEFT" }

local function MirrorHorizontalGrowth(growth)
    return mirroredHorizontalGrowth[growth] or growth
end

local importErrorMessageKeys = {
    EMPTY = "ERR_IMPORT_EMPTY",
    INVALID_PREFIX = "ERR_IMPORT_INVALID_PREFIX",
    UNSUPPORTED_VERSION = "ERR_IMPORT_UNSUPPORTED_VERSION",
    INVALID_FORMAT = "ERR_IMPORT_INVALID_FORMAT",
    NO_SETTINGS = "ERR_IMPORT_NO_SETTINGS",
}

local function TrimString(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function FormatExportNumber(value)
    value = tonumber(value) or 0
    if math.floor(value) == value then
        return tostring(value)
    end

    return string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function EncodeExportString(value)
    return tostring(value or ""):gsub("([^%w_%.%-])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
end

local function DecodeExportString(value)
    return tostring(value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function GetPathValue(source, path)
    local current = source
    for _, segment in ipairs(path) do
        if type(current) ~= "table" then
            return nil
        end
        current = current[segment]
    end
    return current
end

local function SetPathValue(target, path, value)
    local current = target
    for index = 1, #path - 1 do
        local segment = path[index]
        if type(current[segment]) ~= "table" then
            current[segment] = {}
        end
        current = current[segment]
    end
    current[path[#path]] = value
end

local function SerializeExportValue(field, value)
    if field.kind == "boolean" then
        return value == true and "1" or "0"
    end

    if field.kind == "number" then
        return FormatExportNumber(value)
    end

    if field.kind == "color" then
        local color = Shared.NormalizeColorTable(value, { 1, 1, 1 })
        return table.concat({
            FormatExportNumber(color[1]),
            FormatExportNumber(color[2]),
            FormatExportNumber(color[3]),
        }, ",")
    end

    return EncodeExportString(value)
end

local function DeserializeExportValue(field, value)
    if field.kind == "boolean" then
        value = string.lower(tostring(value or ""))
        if value == "1" or value == "true" then
            return true
        end
        if value == "0" or value == "false" then
            return false
        end
        return nil
    end

    if field.kind == "number" then
        return tonumber(value)
    end

    if field.kind == "color" then
        local r, g, b = tostring(value or ""):match("^([^,]+),([^,]+),([^,]+)$")
        r, g, b = tonumber(r), tonumber(g), tonumber(b)
        if r == nil or g == nil or b == nil then
            return nil
        end
        return { r, g, b }
    end

    value = DecodeExportString(value)
    if field.valid and not field.valid[value] then
        return nil
    end
    return value
end

local function ParseExportString(serialized)
    serialized = TrimString(serialized)
    if serialized == "" then
        return nil, "EMPTY"
    end

    if serialized:sub(1, #Shared.EXPORT_PREFIX) ~= Shared.EXPORT_PREFIX then
        if serialized:match("^ArenaDRNameplates:%d+:") then
            return nil, "UNSUPPORTED_VERSION"
        end
        return nil, "INVALID_PREFIX"
    end

    local payload = serialized:sub(#Shared.EXPORT_PREFIX + 1)
    local values = {}
    for entry in payload:gmatch("[^;]+") do
        local key, value = entry:match("^([^=]+)=(.*)$")
        if key and key ~= "" then
            values[key] = value
        end
    end

    if not next(values) then
        return nil, "INVALID_FORMAT"
    end

    return values
end

function Shared.GetImportErrorMessageKey(reason)
    return importErrorMessageKeys[reason] or "ERR_IMPORT_INVALID_FORMAT"
end

function Shared.ExportSettings()
    local db = Shared.EnsureDB()
    local parts = { "defaults=1" }

    for _, field in ipairs(exportDBFields) do
        local value = GetPathValue(db, field.path)
        local defaultValue = GetPathValue(defaults, field.path)
        local serializedValue = SerializeExportValue(field, value)
        if serializedValue ~= SerializeExportValue(field, defaultValue) then
            parts[#parts + 1] = field.key .. "=" .. serializedValue
        end
    end

    return Shared.EXPORT_PREFIX .. table.concat(parts, ";")
end

function Shared.ImportSettings(serialized)
    local values, reason = ParseExportString(serialized)
    if not values then
        return false, reason
    end

    local importedDB = CopyTable(defaults)
    local appliedSettings = 0

    for _, field in ipairs(exportDBFields) do
        local rawValue = values[field.key]
        if rawValue ~= nil then
            local parsedValue = DeserializeExportValue(field, rawValue)
            if parsedValue ~= nil then
                SetPathValue(importedDB, field.path, parsedValue)
                appliedSettings = appliedSettings + 1
            end
        end
    end

    -- A pre-fix string names the starting edge, so it reads through the mirror.
    for _, field in ipairs(legacyGrowthExportFields) do
        local rawValue = values[field.key]
        if rawValue ~= nil then
            local parsedValue = DeserializeExportValue(field, rawValue)
            if parsedValue ~= nil then
                SetPathValue(importedDB, field.path, MirrorHorizontalGrowth(parsedValue))
                appliedSettings = appliedSettings + 1
            end
        end
    end

    -- Already in the current vocabulary, so it must not be migrated again.
    importedDB.growthDirectionMigrated = true

    if appliedSettings == 0 and values.defaults ~= "1" then
        return false, "NO_SETTINGS"
    end

    local db = Shared.EnsureDB()
    for key in pairs(db) do
        db[key] = nil
    end
    for key, value in pairs(importedDB) do
        if type(value) == "table" then
            db[key] = CopyTable(value)
        else
            db[key] = value
        end
    end

    -- The import wrote raw values straight into the saved variables, so the
    -- cached normalization is stale by definition.
    Shared.InvalidateDB()
    Shared.EnsureDB()

    return true, "IMPORTED", appliedSettings
end

function Shared.DetectAnchorPreset(point, relativePoint)
    if point == "BOTTOM" and relativePoint == "TOP" then
        return "ABOVE"
    end
    if point == "TOP" and relativePoint == "BOTTOM" then
        return "BELOW"
    end
    if point == "RIGHT" and relativePoint == "LEFT" then
        return "LEFT"
    end
    if point == "LEFT" and relativePoint == "RIGHT" then
        return "RIGHT"
    end
    if point == "CENTER" and relativePoint == "CENTER" then
        return "CENTER"
    end
    return "ADVANCED"
end

function Shared.GetEffectiveHorizontalIconGrowthForValues(anchorPreset, iconGrowth)
    anchorPreset = tostring(anchorPreset or "")

    if anchorPreset == "LEFT" then
        return "LEFT"
    end
    if anchorPreset == "RIGHT" then
        return "RIGHT"
    end
    if anchorPreset == "ABOVE" or anchorPreset == "BELOW" or anchorPreset == "CENTER" then
        return "CENTER"
    end

    return Shared.NormalizeIconGrowth(iconGrowth)
end

function Shared.GetEffectiveVerticalIconGrowthForValues(anchorPreset, iconVerticalGrowth)
    return Shared.NormalizeVerticalIconGrowth(iconVerticalGrowth)
end

function Shared.GetEffectiveIconLayoutForTable(source)
    if type(source) ~= "table" then
        return defaults.iconLayout
    end

    return Shared.NormalizeIconLayout(source.iconLayout)
end

function Shared.GetEffectiveIconGrowthForValues(anchorPreset, iconLayout, iconGrowth, iconVerticalGrowth)
    if Shared.NormalizeIconLayout(iconLayout) == "VERTICAL" then
        return Shared.GetEffectiveVerticalIconGrowthForValues(anchorPreset, iconVerticalGrowth)
    end

    return Shared.GetEffectiveHorizontalIconGrowthForValues(anchorPreset, iconGrowth)
end

function Shared.GetEffectiveIconGrowthForTable(source)
    if type(source) ~= "table" then
        return Shared.GetEffectiveIconGrowthForValues(
            nil,
            defaults.iconLayout,
            defaults.iconGrowth,
            defaults.iconVerticalGrowth
        )
    end

    return Shared.GetEffectiveIconGrowthForValues(
        source.anchorPreset,
        source.iconLayout,
        source.iconGrowth,
        source.iconVerticalGrowth
    )
end

function Shared.ApplyAnchorPresetToTable(targetDB, preset)
    if type(targetDB) ~= "table" then
        return targetDB
    end

    local previousLayout = Shared.GetEffectiveIconLayoutForTable(targetDB)
    local previousHorizontalGrowth = Shared.GetEffectiveHorizontalIconGrowthForValues(
        targetDB.anchorPreset,
        targetDB.iconGrowth
    )
    local previousVerticalGrowth = Shared.GetEffectiveVerticalIconGrowthForValues(
        targetDB.anchorPreset,
        targetDB.iconVerticalGrowth
    )
    preset = tostring(preset or "")
    targetDB.anchorPreset = preset

    if preset == "ADVANCED" then
        if previousLayout == "VERTICAL" then
            targetDB.iconVerticalGrowth = previousVerticalGrowth
        else
            targetDB.iconGrowth = previousHorizontalGrowth
        end
    elseif preset == "ABOVE" then
        targetDB.point = "BOTTOM"
        targetDB.relativePoint = "TOP"
    elseif preset == "BELOW" then
        targetDB.point = "TOP"
        targetDB.relativePoint = "BOTTOM"
    elseif preset == "LEFT" then
        targetDB.point = "RIGHT"
        targetDB.relativePoint = "LEFT"
    elseif preset == "RIGHT" then
        targetDB.point = "LEFT"
        targetDB.relativePoint = "RIGHT"
    elseif preset == "CENTER" then
        targetDB.point = "CENTER"
        targetDB.relativePoint = "CENTER"
    elseif preset ~= "ADVANCED" then
        targetDB.anchorPreset = Shared.DetectAnchorPreset(targetDB.point, targetDB.relativePoint)
    end

    return targetDB
end

-- The nameplate mirror and the Target/Focus bars have to agree on this. They
-- used to disagree: the mirror waited for a match that was actually running
-- while the bars accepted the arena gates, so the bars kept forcing a full
-- source resync for a mirror that was deliberately idle.
function Shared.IsInArena()
    if C_PvP and type(C_PvP.IsMatchConsideredArena) == "function" then
        local okConsidered, consideredArena = pcall(C_PvP.IsMatchConsideredArena)
        if okConsidered and not IsSecretValue(consideredArena) and consideredArena == true then
            local okActive, matchActive = pcall(C_PvP.IsMatchActive)
            local okComplete, matchComplete = pcall(C_PvP.IsMatchComplete)
            if (okActive and not IsSecretValue(matchActive) and matchActive == true)
                or (okComplete and not IsSecretValue(matchComplete) and matchComplete == true) then
                return true
            end
        end
    end

    local ok, _, instanceType = pcall(IsInInstance)
    return ok and not IsSecretValue(instanceType) and instanceType == "arena"
end

-- EnsureDB used to run the whole validation pass below on every call, and the
-- DR trays call it once per icon and per category. Normalization now runs only
-- when the saved variables actually changed; every other call hands back the
-- table that was already validated. Anything writing to the saved variables
-- outside of this pass has to announce it through Shared.InvalidateDB.
local dbRevision = 1
local normalizedDB
local normalizedRevision

function Shared.GetDBRevision()
    return dbRevision
end

function Shared.InvalidateDB()
    dbRevision = dbRevision + 1
    normalizedDB = nil
    normalizedRevision = nil
    Shared.InvalidateFontCache()
end

-- Growth used to name the tray edge the icons started from instead of the
-- direction the tray grows, with the options UI mirroring its labels to hide
-- it. Saved values are flipped once so a bar keeps growing the way it did.
local function MirrorSavedGrowth(source)
    if type(source) == "table" and source.iconGrowth ~= nil then
        source.iconGrowth = MirrorHorizontalGrowth(source.iconGrowth)
    end
end

local function MigrateGrowthDirection(db)
    if db.growthDirectionMigrated == true then
        return
    end

    db.growthDirectionMigrated = true
    MirrorSavedGrowth(db)
    MirrorSavedGrowth(db.selfDR)
    MirrorSavedGrowth(db.targetFocusDR)
end

local function NormalizeDB()
    if not ArenaDRNameplatesDB then
        ArenaDRNameplatesDB = {}
    end

    local db = ArenaDRNameplatesDB

    for key in pairs(deprecatedDBKeys) do
        db[key] = nil
    end

    -- Before the defaults below are filled in, so only saved values are moved.
    MigrateGrowthDirection(db)

    for key, value in pairs(defaults) do
        if db[key] == nil then
            if type(value) == "table" then
                db[key] = CopyTable(value)
            else
                db[key] = value
            end
        end
    end

    db.enabled = true
    if type(db.scale) ~= "number" then
        db.scale = defaults.scale
    end
    if type(db.scaleWithNameplate) ~= "boolean" then
        db.scaleWithNameplate = defaults.scaleWithNameplate
    end
    if type(db.opacity) ~= "number" then
        db.opacity = defaults.opacity
    end
    if type(db.textFont) ~= "string" or db.textFont == "" then
        db.textFont = defaults.textFont
    end
    db.textOutline = Shared.NormalizeTextOutline(db.textOutline)
    if type(db.timerTextScale) ~= "number" then
        db.timerTextScale = defaults.timerTextScale
    end
    if type(db.timerTextOffsetX) ~= "number" then
        db.timerTextOffsetX = defaults.timerTextOffsetX
    end
    if type(db.timerTextOffsetY) ~= "number" then
        db.timerTextOffsetY = defaults.timerTextOffsetY
    end
    if type(db.showTimerText) ~= "boolean" then
        db.showTimerText = defaults.showTimerText
    end
    if type(db.showTimerDecimals) ~= "boolean" then
        db.showTimerDecimals = defaults.showTimerDecimals
    end
    db.timerDecimalThreshold = math.floor(
        Shared.ClampNumber(db.timerDecimalThreshold, 1, 20, defaults.timerDecimalThreshold) + 0.5
    )
    db.iconLayout = Shared.NormalizeIconLayout(db.iconLayout)
    db.iconGrowth = Shared.NormalizeIconGrowth(db.iconGrowth)
    db.iconVerticalGrowth = Shared.NormalizeVerticalIconGrowth(db.iconVerticalGrowth)
    db.iconPadding = Shared.ClampNumber(db.iconPadding, 0, 20, defaults.iconPadding)
    if type(db.offsetX) ~= "number" then
        db.offsetX = defaults.offsetX
    end
    if type(db.offsetY) ~= "number" then
        db.offsetY = defaults.offsetY
    end
    if type(db.showTimerSwipe) ~= "boolean" then
        db.showTimerSwipe = defaults.showTimerSwipe
    end
    if type(db.showTimerSwipeEdge) ~= "boolean" then
        db.showTimerSwipeEdge = defaults.showTimerSwipeEdge
    end
    if type(db.showDRText) ~= "boolean" then
        db.showDRText = defaults.showDRText
    end
    if type(db.showImmunityIndicator) ~= "boolean" then
        db.showImmunityIndicator = defaults.showImmunityIndicator
    end
    if type(db.trinket) ~= "table" then
        db.trinket = CopyTable(defaults.trinket)
    end
    db.timerTextColor = Shared.NormalizeColorTable(db.timerTextColor, defaults.timerTextColor)
    if type(db.drTextAnchor) ~= "string"
        or db.drTextAnchor == ""
        or not validDRTextAnchors[db.drTextAnchor] then
        db.drTextAnchor = defaults.drTextAnchor
    end
    if type(db.drTextScale) ~= "number" then
        db.drTextScale = defaults.drTextScale
    end
    if type(db.drTextOffsetX) ~= "number" then
        db.drTextOffsetX = defaults.drTextOffsetX
    end
    if type(db.drTextOffsetY) ~= "number" then
        db.drTextOffsetY = defaults.drTextOffsetY
    end
    db.drTextColor = Shared.NormalizeColorTable(db.drTextColor, defaults.drTextColor)
    db.drTextImmuneColor = Shared.NormalizeColorTable(db.drTextImmuneColor, defaults.drTextImmuneColor)
    db.drBorderStyle = Shared.NormalizeDRBorderStyle(db.drBorderStyle)
    db.drBorderColor = Shared.NormalizeColorTable(db.drBorderColor, defaults.drBorderColor)
    db.drBorderImmuneColor = Shared.NormalizeColorTable(db.drBorderImmuneColor, defaults.drBorderImmuneColor)
    db.drBorderWidth = Shared.ClampNumber(db.drBorderWidth, 1, 8, defaults.drBorderWidth)
    if type(db.anchorPreset) ~= "string" or db.anchorPreset == "" then
        db.anchorPreset = Shared.DetectAnchorPreset(db.point, db.relativePoint)
    end

    db.trinket.enabled = db.trinket.enabled == true
    db.trinket.visibility = Shared.NormalizeTrinketVisibility(db.trinket.visibility)
    db.trinket.size = Shared.ClampNumber(db.trinket.size, 12, 80, defaults.trinket.size)
    db.trinket.opacity = Shared.ClampNumber(db.trinket.opacity, 0.1, 1.0, defaults.trinket.opacity)
    db.trinket.borderStyle = Shared.NormalizeTrinketBorderStyle(db.trinket.borderStyle)
    db.trinket.borderColor = Shared.NormalizeColorTable(db.trinket.borderColor, defaults.trinket.borderColor)
    db.trinket.borderWidth = Shared.ClampNumber(db.trinket.borderWidth, 1, 8, defaults.trinket.borderWidth)
    if type(db.trinket.offsetX) ~= "number" then
        db.trinket.offsetX = defaults.trinket.offsetX
    end
    if type(db.trinket.offsetY) ~= "number" then
        db.trinket.offsetY = defaults.trinket.offsetY
    end
    if type(db.trinket.point) ~= "string" or db.trinket.point == "" then
        db.trinket.point = defaults.trinket.point
    end
    if type(db.trinket.relativePoint) ~= "string" or db.trinket.relativePoint == "" then
        db.trinket.relativePoint = defaults.trinket.relativePoint
    end
    if type(db.trinket.anchorPreset) ~= "string" or db.trinket.anchorPreset == "" then
        db.trinket.anchorPreset = Shared.DetectAnchorPreset(db.trinket.point, db.trinket.relativePoint)
    end

    if type(db.selfDR) ~= "table" then
        db.selfDR = CopyTable(defaults.selfDR)
    end

    local selfDR = db.selfDR
    selfDR.enabled = selfDR.enabled == true
    if type(selfDR.locked) ~= "boolean" then
        selfDR.locked = defaults.selfDR.locked
    end
    if type(selfDR.showInArena) ~= "boolean" then
        selfDR.showInArena = defaults.selfDR.showInArena
    end
    if type(selfDR.showInBattleground) ~= "boolean" then
        selfDR.showInBattleground = defaults.selfDR.showInBattleground
    end
    if type(selfDR.showInWorld) ~= "boolean" then
        selfDR.showInWorld = defaults.selfDR.showInWorld
    end
    selfDR.size = Shared.ClampNumber(selfDR.size, 16, 80, defaults.selfDR.size)
    selfDR.opacity = Shared.ClampNumber(selfDR.opacity, 0.1, 1.0, defaults.selfDR.opacity)
    selfDR.iconPadding = Shared.ClampNumber(selfDR.iconPadding, 0, 20, defaults.selfDR.iconPadding)
    selfDR.iconLayout = Shared.NormalizeIconLayout(selfDR.iconLayout)
    selfDR.iconGrowth = Shared.NormalizeIconGrowth(selfDR.iconGrowth)
    selfDR.iconVerticalGrowth = Shared.NormalizeVerticalIconGrowth(selfDR.iconVerticalGrowth)
    if type(selfDR.drText) ~= "table" then
        selfDR.drText = CopyTable(defaults.selfDR.drText)
    end
    local selfDRText = selfDR.drText
    local drTextDefaults = defaults.selfDR.drText
    selfDRText.override = selfDRText.override == true
    if type(selfDRText.showDRText) ~= "boolean" then
        selfDRText.showDRText = drTextDefaults.showDRText
    end
    if type(selfDRText.drTextAnchor) ~= "string" or not validDRTextAnchors[selfDRText.drTextAnchor] then
        selfDRText.drTextAnchor = drTextDefaults.drTextAnchor
    end
    selfDRText.drTextScale = Shared.ClampNumber(selfDRText.drTextScale, 0.5, 3.0, drTextDefaults.drTextScale)
    if type(selfDRText.drTextOffsetX) ~= "number" then
        selfDRText.drTextOffsetX = drTextDefaults.drTextOffsetX
    end
    if type(selfDRText.drTextOffsetY) ~= "number" then
        selfDRText.drTextOffsetY = drTextDefaults.drTextOffsetY
    end
    selfDRText.drTextColor = Shared.NormalizeColorTable(selfDRText.drTextColor, drTextDefaults.drTextColor)
    selfDRText.drTextImmuneColor = Shared.NormalizeColorTable(
        selfDRText.drTextImmuneColor,
        drTextDefaults.drTextImmuneColor
    )

    if type(selfDR.timers) ~= "table" then
        selfDR.timers = CopyTable(defaults.selfDR.timers)
    end
    local selfTimers = selfDR.timers
    local timerDefaults = defaults.selfDR.timers
    selfTimers.override = selfTimers.override == true
    for _, key in ipairs({ "showTimerSwipe", "showTimerSwipeEdge", "showTimerText", "showTimerDecimals" }) do
        if type(selfTimers[key]) ~= "boolean" then
            selfTimers[key] = timerDefaults[key]
        end
    end
    selfTimers.timerDecimalThreshold = math.floor(
        Shared.ClampNumber(selfTimers.timerDecimalThreshold, 1, 20, timerDefaults.timerDecimalThreshold) + 0.5
    )
    selfTimers.timerTextColor = Shared.NormalizeColorTable(selfTimers.timerTextColor, timerDefaults.timerTextColor)
    selfTimers.timerTextScale = Shared.ClampNumber(selfTimers.timerTextScale, 0.5, 2.0, timerDefaults.timerTextScale)
    if type(selfTimers.timerTextOffsetX) ~= "number" then
        selfTimers.timerTextOffsetX = timerDefaults.timerTextOffsetX
    end
    if type(selfTimers.timerTextOffsetY) ~= "number" then
        selfTimers.timerTextOffsetY = timerDefaults.timerTextOffsetY
    end
    selfDR.borderStyle = Shared.NormalizeDRBorderStyle(selfDR.borderStyle)
    selfDR.borderWidth = Shared.ClampNumber(selfDR.borderWidth, 1, 8, defaults.selfDR.borderWidth)
    selfDR.borderColor = Shared.NormalizeColorTable(selfDR.borderColor, defaults.selfDR.borderColor)
    selfDR.borderImmuneColor = Shared.NormalizeColorTable(
        selfDR.borderImmuneColor,
        defaults.selfDR.borderImmuneColor
    )
    local usesLegacyDefaultPosition = selfDR.relativeFrame == nil
        and selfDR.point == "CENTER"
        and selfDR.relativePoint == "CENTER"
        and selfDR.offsetX == 0
        and selfDR.offsetY == -180
    if usesLegacyDefaultPosition then
        selfDR.relativeFrame = defaults.selfDR.relativeFrame
        selfDR.point = defaults.selfDR.point
        selfDR.relativePoint = defaults.selfDR.relativePoint
        selfDR.offsetX = defaults.selfDR.offsetX
        selfDR.offsetY = defaults.selfDR.offsetY
        selfDR.locked = false
    elseif selfDR.relativeFrame == nil then
        -- Positions saved before relative-frame support used UIParent. Keep a
        -- custom placement visually stable instead of silently moving it.
        selfDR.relativeFrame = "UIParent"
    elseif not validMovableAnchorFrames[selfDR.relativeFrame] then
        selfDR.relativeFrame = defaults.selfDR.relativeFrame
    end
    if type(selfDR.point) ~= "string" or not validBasicAnchorPoints[selfDR.point] then
        selfDR.point = defaults.selfDR.point
    end
    if type(selfDR.relativePoint) ~= "string" or not validBasicAnchorPoints[selfDR.relativePoint] then
        selfDR.relativePoint = defaults.selfDR.relativePoint
    end
    if type(selfDR.offsetX) ~= "number" then
        selfDR.offsetX = defaults.selfDR.offsetX
    end
    if type(selfDR.offsetY) ~= "number" then
        selfDR.offsetY = defaults.selfDR.offsetY
    end

    if type(selfDR.track) ~= "table" then
        selfDR.track = CopyTable(defaults.selfDR.track)
    end
    for _, category in ipairs(selfDRCategories) do
        if type(selfDR.track[category]) ~= "boolean" then
            selfDR.track[category] = defaults.selfDR.track[category] == true
        end
    end
    -- Drop any category that is no longer supported (e.g. knockback from older builds).
    for category in pairs(selfDR.track) do
        if not validSelfDRCategories[category] then
            selfDR.track[category] = nil
        end
    end

    if type(db.targetFocusDR) ~= "table" then
        db.targetFocusDR = CopyTable(defaults.targetFocusDR)
    end

    local targetFocusDR = db.targetFocusDR
    local targetFocusDefaults = defaults.targetFocusDR
    targetFocusDR.enabled = targetFocusDR.enabled == true
    for _, key in ipairs({ "locked", "showTarget", "showFocus" }) do
        if type(targetFocusDR[key]) ~= "boolean" then
            targetFocusDR[key] = targetFocusDefaults[key]
        end
    end
    targetFocusDR.size = Shared.ClampNumber(targetFocusDR.size, 16, 80, targetFocusDefaults.size)
    targetFocusDR.opacity = Shared.ClampNumber(targetFocusDR.opacity, 0.1, 1.0, targetFocusDefaults.opacity)
    targetFocusDR.iconPadding = Shared.ClampNumber(
        targetFocusDR.iconPadding,
        0,
        20,
        targetFocusDefaults.iconPadding
    )
    targetFocusDR.iconLayout = Shared.NormalizeIconLayout(targetFocusDR.iconLayout)
    targetFocusDR.iconGrowth = Shared.NormalizeIconGrowth(targetFocusDR.iconGrowth)
    targetFocusDR.iconVerticalGrowth = Shared.NormalizeVerticalIconGrowth(targetFocusDR.iconVerticalGrowth)
    targetFocusDR.borderStyle = Shared.NormalizeDRBorderStyle(targetFocusDR.borderStyle)
    targetFocusDR.borderWidth = Shared.ClampNumber(
        targetFocusDR.borderWidth,
        1,
        8,
        targetFocusDefaults.borderWidth
    )
    targetFocusDR.borderColor = Shared.NormalizeColorTable(
        targetFocusDR.borderColor,
        targetFocusDefaults.borderColor
    )
    targetFocusDR.borderImmuneColor = Shared.NormalizeColorTable(
        targetFocusDR.borderImmuneColor,
        targetFocusDefaults.borderImmuneColor
    )

    local migratedLegacyTargetFocusPositions = 0
    local legacyTargetFocusOffsets = { target = -115, focus = -65 }
    for _, unitKey in ipairs({ "target", "focus" }) do
        if type(targetFocusDR[unitKey]) ~= "table" then
            targetFocusDR[unitKey] = CopyTable(targetFocusDefaults[unitKey])
        end
        local position = targetFocusDR[unitKey]
        local positionDefaults = targetFocusDefaults[unitKey]
        position.scale = Shared.ClampNumber(position.scale, 0.5, 3.0, positionDefaults.scale)
        if type(position.timers) ~= "table" then
            position.timers = CopyTable(positionDefaults.timers)
        end
        local timers = position.timers
        local timerDefaults = positionDefaults.timers
        timers.override = timers.override == true
        timers.timerTextColor = Shared.NormalizeColorTable(
            timers.timerTextColor,
            timerDefaults.timerTextColor
        )
        timers.timerTextScale = Shared.ClampNumber(
            timers.timerTextScale,
            0.5,
            3.0,
            timerDefaults.timerTextScale
        )
        local usesLegacyDefaultUnitPosition = position.relativeFrame == nil
            and position.point == "CENTER"
            and position.relativePoint == "CENTER"
            and position.offsetX == 0
            and position.offsetY == legacyTargetFocusOffsets[unitKey]
        if usesLegacyDefaultUnitPosition then
            position.relativeFrame = positionDefaults.relativeFrame
            position.point = positionDefaults.point
            position.relativePoint = positionDefaults.relativePoint
            position.offsetX = positionDefaults.offsetX
            position.offsetY = positionDefaults.offsetY
            migratedLegacyTargetFocusPositions = migratedLegacyTargetFocusPositions + 1
        elseif position.relativeFrame == nil then
            position.relativeFrame = "UIParent"
        elseif not validMovableAnchorFrames[position.relativeFrame] then
            position.relativeFrame = positionDefaults.relativeFrame
        end
        if type(position.point) ~= "string" or not validBasicAnchorPoints[position.point] then
            position.point = positionDefaults.point
        end
        if type(position.relativePoint) ~= "string"
            or not validBasicAnchorPoints[position.relativePoint] then
            position.relativePoint = positionDefaults.relativePoint
        end
        if type(position.offsetX) ~= "number" then
            position.offsetX = positionDefaults.offsetX
        end
        if type(position.offsetY) ~= "number" then
            position.offsetY = positionDefaults.offsetY
        end
    end
    if migratedLegacyTargetFocusPositions == 2 then
        targetFocusDR.locked = false
    end

    return db
end

Shared.NormalizeDB = NormalizeDB

function Shared.EnsureDB()
    -- The identity check covers a profile swap or a reload handing over a
    -- different saved-variables table without going through InvalidateDB.
    if normalizedDB ~= nil
        and normalizedRevision == dbRevision
        and normalizedDB == rawget(_G, "ArenaDRNameplatesDB") then
        return normalizedDB
    end

    normalizedDB = NormalizeDB()
    normalizedRevision = dbRevision
    return normalizedDB
end
