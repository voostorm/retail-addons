-- Drives the live enemy DR mirror against a stubbed Blizzard arena tray.
-- Run from the addon root with: lua Tests/DRMirrorHarness.lua
--
-- The stub reproduces the tray sequence Blizzard uses for a diminishing return:
-- the item is shown and its cooldown zeroed while the crowd control runs, and the
-- reset window is only set once the control breaks.

local failures = 0

local function check(condition, message)
    if condition then
        io.write("PASS: ", message, "\n")
        return
    end
    failures = failures + 1
    io.write("FAIL: ", message, "\n")
end

local function loadAddonFile(path, namespace)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk("ArenaDRNameplates", namespace)
end

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

-- Midnight protects arena values during combat. The harness flips this on to
-- exercise the paths that cannot read the source window at all. Blizzard's own
-- zeroes stay public: they are literals in its code, not protected data.
local combatSecrets = false

function issecretvalue(value)
    return combatSecrets and type(value) == "number" and value ~= 0
end

--- Clock and timers --------------------------------------------------------

local now = 1000
local timers = {}

function GetTime()
    return now
end

C_Timer = {
    NewTimer = function(delay, callback)
        local timer = { at = now + delay, callback = callback }
        function timer:Cancel()
            self.cancelled = true
        end
        timers[#timers + 1] = timer
        return timer
    end,
    NewTicker = function(delay, callback)
        local timer = { at = now + delay, interval = delay, callback = callback }
        function timer:Cancel()
            self.cancelled = true
        end
        timers[#timers + 1] = timer
        return timer
    end,
    After = function(delay, callback)
        return C_Timer.NewTimer(delay, callback)
    end,
}

-- Runs everything scheduled up to the current clock, repeatedly, so a callback
-- that schedules another zero-delay timer still settles before assertions.
local function runTimers()
    for _ = 1, 20 do
        local ran = false
        for _, timer in ipairs(timers) do
            if not timer.cancelled and not timer.fired and timer.at <= now then
                if timer.interval then
                    timer.at = now + timer.interval
                else
                    timer.fired = true
                end
                timer.callback()
                ran = true
            end
        end
        if not ran then
            return
        end
    end
end

local function advance(seconds)
    now = now + seconds
    runTimers()
end

--- Widgets -----------------------------------------------------------------

local framesByName = {}

local Frame = {}
Frame.__index = Frame

local function RunScript(frame, script, ...)
    local handlers = frame.scriptHandlers and frame.scriptHandlers[script]
    if not handlers then
        return
    end
    for _, handler in ipairs(handlers) do
        handler(frame, ...)
    end
end

function Frame:SetScript(script, handler)
    self.scriptHandlers = self.scriptHandlers or {}
    self.scriptHandlers[script] = { handler }
end

function Frame:HookScript(script, handler)
    self.scriptHandlers = self.scriptHandlers or {}
    self.scriptHandlers[script] = self.scriptHandlers[script] or {}
    table.insert(self.scriptHandlers[script], handler)
end

function Frame:GetScript(script)
    local handlers = self.scriptHandlers and self.scriptHandlers[script]
    return handlers and handlers[1]
end

function Frame:Show()
    self:SetShown(true)
end

function Frame:Hide()
    self:SetShown(false)
end

function Frame:SetShown(shown)
    shown = shown and true or false
    if self.shown == shown then
        return
    end
    self.shown = shown
    RunScript(self, shown and "OnShow" or "OnHide")
end

function Frame:IsShown()
    return self.shown == true
end

function Frame:IsVisible()
    return self:IsShown()
end

function Frame:IsForbidden()
    return false
end

function Frame:GetObjectType()
    return self.objectType or "Frame"
end

function Frame:GetParent()
    return self.parent
end

function Frame:SetParent(parent)
    self.parent = parent
end

function Frame:GetChildren()
    return table.unpack(self.children or {})
end

function Frame:GetNumChildren()
    return #(self.children or {})
end

function Frame:GetRegions()
    return table.unpack(self.regions or {})
end

function Frame:GetName()
    return self.frameName
end

function Frame:SetText(text)
    self.text = text
end

function Frame:SetFont(path, size, flags)
    self.fontPath = path
    self.fontSize = size
    self.fontFlags = flags
    return true
end

function Frame:SetTextColor(r, g, b, a)
    self.textColor = { r, g, b, a }
end

function Frame:SetSize(width, height)
    self.width = width
    self.height = height
end

function Frame:SetScale(scale)
    self.scale = scale
end

function Frame:SetPoint(point, relativeFrame, relativePoint, offsetX, offsetY)
    self.anchorPoint = point
    self.anchorRelativeFrame = relativeFrame
    self.anchorRelativePoint = relativePoint
    self.anchorOffsetX = offsetX
    self.anchorOffsetY = offsetY
end

function Frame:CreateTexture()
    local texture = setmetatable({
        objectType = "Texture",
        parent = self,
        shown = true,
        scriptHandlers = {},
    }, Frame)
    self.regions = self.regions or {}
    table.insert(self.regions, texture)
    return texture
end

function Frame:CreateFontString()
    local fontString = setmetatable({
        objectType = "FontString",
        parent = self,
        shown = true,
        text = "",
        scriptHandlers = {},
    }, Frame)
    self.regions = self.regions or {}
    table.insert(self.regions, fontString)
    return fontString
end

-- Everything the addon calls on a widget purely for looks. The mirror logic
-- under test never reads these back.
local NOOP_METHODS = {
    "SetSize", "SetWidth", "SetHeight", "SetPoint", "SetAllPoints", "ClearAllPoints",
    "SetFrameStrata", "SetFrameLevel", "EnableMouse", "SetAlpha", "SetScale",
    "SetIgnoreParentAlpha", "SetIgnoreParentScale", "SetTexture", "SetAtlas",
    "SetTexCoord", "SetColorTexture", "SetVertexColor", "SetDrawLayer",
    "SetTextColor", "SetText", "SetFont", "SetJustifyH", "SetJustifyV",
    "SetShadowOffset", "SetShadowColor", "SetReverse", "SetDrawSwipe",
    "SetSwipeColor", "SetDrawEdge", "SetDrawBling", "SetHideCountdownNumbers",
    "SetCountdownMillisecondsThreshold", "SetAlphaFromBoolean", "SetMovable",
    "SetClampedToScreen", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
    "SetUserPlaced", "SetToplevel", "SetPropagateMouseClicks", "SetPropagateMouseMotion",
    "SetFixedFrameStrata", "SetFixedFrameLevel", "SetMouseClickEnabled",
    "SetMouseMotionEnabled", "SetClipsChildren", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "Raise", "SetSwipeTexture", "SetEdgeTexture",
    "SetBlendMode", "SetDesaturated", "SetRotation", "SetSnapToPixelGrid",
    "SetTexelSnappingBias", "SetGradient", "SetHeight", "SetMinResize",
    "SetMaxResize", "SetResizeBounds", "SetAttribute", "RegisterEvent",
    "UnregisterEvent", "RegisterUnitEvent", "RegisterAllEvents",
}

for _, name in ipairs(NOOP_METHODS) do
    if not Frame[name] then
        Frame[name] = function() end
    end
end

function Frame:GetWidth()
    return self.width or 26
end

function Frame:GetHeight()
    return self.height or 26
end

function Frame:GetEffectiveScale()
    return 1
end

function Frame:GetCenter()
    return self.centerX or 500, self.centerY or 400
end

function Frame:GetFrameLevel()
    return self.frameLevel or 1
end

function Frame:GetAtlas()
    return self.atlas
end

function Frame:GetTexture()
    return self.texture
end

function Frame:GetText()
    return self.text
end

function Frame:GetPoint()
    return "CENTER", self.parent, "CENTER", 0, 0
end

function Frame:GetNumPoints()
    return 1
end

--- Cooldown ----------------------------------------------------------------
-- Mirrors the widget behaviour the addon depends on: a cooldown shows itself
-- while it runs and hides itself when it is cleared or reaches its end.

local Cooldown = setmetatable({}, { __index = Frame })
Cooldown.__index = Cooldown

function Cooldown:SetCooldown(start, duration)
    self.setCooldownCalls = (self.setCooldownCalls or 0) + 1
    if not start or not duration or duration <= 0 then
        self.start = nil
        self.duration = nil
        self:Hide()
        return
    end

    self.start = start
    self.duration = duration
    self:Show()
end

function Cooldown:Clear()
    self.start = nil
    self.duration = nil
    self:Hide()
end

function Cooldown:GetCooldownTimes()
    if not self.start then
        return 0, 0
    end
    return self.start * 1000, self.duration * 1000
end

function Cooldown:GetCooldownDuration()
    if not self.start then
        return 0
    end
    return math.max(0, (self.start + self.duration - now)) * 1000
end

function Cooldown:GetCountdownFontString()
    return nil
end

function Cooldown:IsRunning()
    return self.start ~= nil and (self.start + self.duration) > now
end

-- The engine fires OnCooldownDone at the end of a window; the harness drives it
-- from the clock.
local cooldowns = {}

local function TickCooldowns()
    for _, cooldown in ipairs(cooldowns) do
        if cooldown.start and (cooldown.start + cooldown.duration) <= now then
            cooldown.start = nil
            cooldown.duration = nil
            cooldown:Hide()
            RunScript(cooldown, "OnCooldownDone")
        end
    end
end

local frameCount = 0

function CreateFrame(frameType, name, parent, _)
    frameCount = frameCount + 1
    local metatable = frameType == "Cooldown" and Cooldown or Frame
    local frame = setmetatable({
        frameType = frameType,
        frameName = name or ("HarnessFrame" .. frameCount),
        parent = parent,
        shown = true,
        children = {},
        regions = {},
        scriptHandlers = {},
    }, metatable)

    if frameType == "Cooldown" then
        frame.Text = frame:CreateFontString()
        table.insert(cooldowns, frame)
    end

    if parent and parent.children then
        table.insert(parent.children, frame)
    end

    if name then
        framesByName[name] = frame
        _G[name] = frame
    end

    return frame
end

function hooksecurefunc(object, method, hook)
    local original = object[method]
    object[method] = function(...)
        local results = { original(...) }
        hook(...)
        return table.unpack(results)
    end
end

UIParent = CreateFrame("Frame", "UIParent")
WorldFrame = CreateFrame("Frame", "WorldFrame")
PlayerFrame = CreateFrame("Frame", "PlayerFrame", UIParent)
TargetFrame = CreateFrame("Frame", "TargetFrame", UIParent)
FocusFrame = CreateFrame("Frame", "FocusFrame", UIParent)

--- Game API ----------------------------------------------------------------

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UIFontHeight = 12

function CreateColor(r, g, b, a)
    local color = { r = r, g = g, b = b, a = a }
    function color:GetRGB()
        return self.r, self.g, self.b
    end
    function color:GetRGBA()
        return self.r, self.g, self.b, self.a
    end
    return color
end

local arenaActive = true
local plateVisible = true

function IsInInstance()
    return arenaActive, arenaActive and "arena" or "none"
end

function IsActiveBattlefieldArena()
    return arenaActive
end

function InCombatLockdown()
    return false
end

function GetLocale()
    return "enUS"
end

function GetCVarBool()
    return true
end

function GetCVar()
    return "1"
end

function GetCVarDefault()
    return "1"
end

C_CVar = {
    GetCVarBool = GetCVarBool,
    GetCVar = GetCVar,
    GetCVarDefault = GetCVarDefault,
    SetCVar = function() end,
}

C_PvP = {
    IsMatchConsideredArena = function()
        return arenaActive
    end,
    IsMatchActive = function()
        return arenaActive
    end,
    IsMatchComplete = function()
        return false
    end,
    GetArenaCrowdControlInfo = function()
        return nil
    end,
}

C_LossOfControl = {
    GetActiveLossOfControlDataCount = function()
        return 0
    end,
    GetActiveLossOfControlDataByUnit = function()
        return nil
    end,
}

local identities = {
    arena1 = "enemy-1",
    nameplate1 = "enemy-1",
    player = "player-1",
    target = "enemy-1",
    focus = "enemy-1",
}

function UnitExists(unit)
    if unit == "arena1" then
        return arenaActive
    end
    if unit == "nameplate1" then
        return arenaActive and plateVisible
    end
    return identities[unit] ~= nil
end

function UnitGUID(unit)
    return identities[unit]
end

function UnitName(unit)
    return identities[unit] and unit or nil
end

function UnitClass(unit)
    if identities[unit] then
        return "Rogue", "ROGUE"
    end
end

function UnitIsUnit(unitA, unitB)
    return identities[unitA] ~= nil and identities[unitA] == identities[unitB]
end

function UnitIsProbablyUnit(unitA, unitB)
    return UnitIsUnit(unitA, unitB)
end

function UnitCanAttack(_, unit)
    return unit == "nameplate1" or unit == "target" or unit == "focus"
end

function UnitIsEnemy(_, unit)
    return unit == "nameplate1"
end

function UnitIsPlayer(unit)
    return unit == "nameplate1"
end

function UnitFactionGroup()
    return "Alliance", "Alliance"
end

function UnitTokenFromGUID(guid)
    if plateVisible and guid == "enemy-1" then
        return "nameplate1"
    end
end

function GetNumArenaOpponentSpecs()
    return 1
end

function GetArenaOpponentSpec()
    return nil
end

function GetSpecializationInfoByID()
    return nil
end

function GetInventoryItemTexture()
    return nil
end

function GetItemInfoInstant()
    return nil
end

C_Spell = {
    GetSpellTexture = function()
        return 123456
    end,
    GetSpellInfo = function()
        return { name = "Test", iconID = 123456 }
    end,
    GetSpellName = function()
        return "Test"
    end,
}

C_Item = {
    GetItemIconByID = function()
        return 123456
    end,
}

local nameplate = CreateFrame("Frame", "HarnessNameplate1", UIParent)
nameplate.namePlateUnitToken = "nameplate1"
nameplate.UnitFrame = CreateFrame("Frame", "HarnessNameplate1UnitFrame", nameplate)

C_NamePlate = {
    GetNamePlates = function()
        return plateVisible and { nameplate } or {}
    end,
    GetNamePlateForUnit = function(unit)
        if plateVisible
            and (unit == "nameplate1" or unit == "arena1" or unit == "target" or unit == "focus") then
            return nameplate
        end
    end,
}

SlashCmdList = {}
LibStub = nil

--- Blizzard arena tray stub ------------------------------------------------

local arenaFrame = CreateFrame("Frame", "CompactArenaFrameMember1", UIParent)
local tray = CreateFrame("Frame", "HarnessSpellDiminishStatusTray", arenaFrame)
arenaFrame.SpellDiminishStatusTray = tray
tray.children = {}

local function CreateTrayItem()
    local item = CreateFrame("Frame", nil, tray)
    item:Hide()
    item.Icon = item:CreateTexture()
    item.Icon.texture = 123456
    item.Cooldown = CreateFrame("Cooldown", nil, item)
    item.Cooldown:Hide()
    item.ImmunityIndicator = CreateFrame("Frame", nil, item)
    item.ImmunityIndicator:Hide()
    return item
end

--- Addon load --------------------------------------------------------------

local ns = {}
loadAddonFile("Performance.lua", ns)
loadAddonFile("Adapters/Registry.lua", ns)
ns.NameplateAdapters:RegisterAdapter({
    id = "Harness",
    priority = 100,
    IsAvailable = function()
        return true
    end,
    GetTokenFromPlate = function(_, candidate)
        return candidate.namePlateUnitToken
    end,
    GetAnchorParent = function(_, candidate)
        return candidate.UnitFrame
    end,
})
loadAddonFile("ArenaNameplateHelper.lua", ns)
loadAddonFile("Shared.lua", ns)
loadAddonFile("Locales/enUS.lua", ns)

ArenaDRNameplatesDB = nil
loadAddonFile("Core.lua", ns)
loadAddonFile("TargetFocusDR.lua", ns)

local helper = ns.ArenaNameplateHelper

-- Core registers its own event frame; find it by the events it listens for.
local coreEventFrame
local targetFocusEventFrame
for _, frame in pairs(framesByName) do
    if frame.frameName and frame.frameName:find("EventFrame") and frame.frameName:find("Core") then
        coreEventFrame = frame
    end
    if frame.frameName
        and frame.frameName:find("EventFrame")
        and frame.frameName:find("TargetFocusDR") then
        targetFocusEventFrame = frame
    end
end

local function FireCoreEvent(event, ...)
    local handler = coreEventFrame and coreEventFrame:GetScript("OnEvent")
    if handler then
        handler(coreEventFrame, event, ...)
    end
    runTimers()
end

local function FireTargetFocusEvent(event, ...)
    local handler = targetFocusEventFrame and targetFocusEventFrame:GetScript("OnEvent")
    if handler then
        handler(targetFocusEventFrame, event, ...)
    end
    runTimers()
end

check(coreEventFrame ~= nil, "the core event frame is reachable for the harness")
check(targetFocusEventFrame ~= nil, "the Target/Focus event frame is reachable for the harness")

FireCoreEvent("ADDON_LOADED", "ArenaDRNameplates")
FireCoreEvent("PLAYER_LOGIN")
-- Writing the saved variables behind Shared.EnsureDB's back is exactly what the
-- options panel does, and it has to announce it the same way or the cached
-- normalization and the style snapshots keyed on its revision stay stale.
ArenaDRNameplatesDB.targetFocusDR.enabled = true
ns.Shared.InvalidateDB()
FireTargetFocusEvent("PLAYER_LOGIN")
helper:OnEvent("PLAYER_ENTERING_WORLD")
helper:OnEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
runTimers()
FireCoreEvent("PLAYER_ENTERING_WORLD")

--- Mirror inspection ------------------------------------------------------

local function GetMirrorSlot(slotIndex)
    for name, frame in pairs(framesByName) do
        if name:find("DRIcon_Live1_" .. slotIndex, 1, true) then
            return frame
        end
    end
end

local function GetFrameByNameFragment(fragment)
    for name, frame in pairs(framesByName) do
        if name:find(fragment, 1, true) then
            return frame
        end
    end
end

local function MirrorCooldown(slotIndex)
    local slot = GetMirrorSlot(slotIndex)
    return slot and slot.Cooldown
end

local function MirrorRemaining(slotIndex)
    local cooldown = MirrorCooldown(slotIndex)
    if not cooldown or not cooldown.start then
        return nil
    end
    return cooldown.start + cooldown.duration - now
end

local function GetTargetFocusSlot(kind, slotIndex)
    local expected = "ArenaDrNP_TargetFocusDR_" .. kind .. "Slot_" .. slotIndex
    return framesByName[expected]
end

local function GetTargetFocusBar(kind)
    local expected = "ArenaDrNP_TargetFocusDR_" .. kind .. "Bar_"
    for name, frame in pairs(framesByName) do
        if name:find(expected, 1, true) then
            return frame
        end
    end
end

local function GetBarLabel(bar)
    for _, region in ipairs({ bar:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            return region
        end
    end
end

local function TargetFocusRemaining(kind, slotIndex)
    local slot = GetTargetFocusSlot(kind, slotIndex)
    local cooldown = slot and slot.Cooldown
    if not cooldown or not cooldown.start then
        return nil
    end
    return cooldown.start + cooldown.duration - now
end

--- Target/Focus controls --------------------------------------------------

local targetBar = GetTargetFocusBar("target")
local focusBar = GetTargetFocusBar("focus")
check(targetBar ~= nil and focusBar ~= nil,
    "the Target and Focus bars are reachable for control tests")
check(ArenaDRNameplatesDB.targetFocusDR.locked == false,
    "the Target and Focus placement handles are unlocked by default")
check(targetBar.anchorRelativeFrame == TargetFrame
        and focusBar.anchorRelativeFrame == FocusFrame,
    "Target and Focus use their matching Unit Frames as default anchors")

local originalTargetSetScale = targetBar.SetScale
local originalFocusSetScale = focusBar.SetScale
local originalTargetSetSize = targetBar.SetSize
local originalFocusSetSize = focusBar.SetSize
local appliedTargetScale
local appliedFocusScale
local appliedTargetWidth
local appliedFocusWidth
targetBar.SetScale = function(_, scale)
    appliedTargetScale = scale
end
focusBar.SetScale = function(_, scale)
    appliedFocusScale = scale
end
targetBar.SetSize = function(_, width)
    appliedTargetWidth = width
end
focusBar.SetSize = function(_, width)
    appliedFocusWidth = width
end

ArenaDRNameplatesDB.targetFocusDR.size = 64
ArenaDRNameplatesDB.targetFocusDR.target.scale = 1.4
ArenaDRNameplatesDB.targetFocusDR.focus.scale = 0.8
ArenaDRNameplatesDB.targetFocusDR.locked = false
ns.Shared.InvalidateDB()
ns.TargetFocusDR.Refresh()
check(appliedTargetScale == 1 and appliedFocusScale == 1,
    "Target and Focus keep their positioned parent frames unscaled")
check(math.abs(appliedTargetWidth - 89.6) < 0.01
        and math.abs(appliedFocusWidth - 51.2) < 0.01,
    "Target and Focus apply scale through physical icon and layout sizes")
check(targetBar:IsShown() == true and focusBar:IsShown() == true,
    "unlocked Target and Focus bars remain visible as placement handles")
check(GetTargetFocusSlot("target", 1) == nil and GetTargetFocusSlot("focus", 1) == nil,
    "unlocking Target and Focus creates no preview icons")

local targetLabel = GetBarLabel(targetBar)
local focusLabel = GetBarLabel(focusBar)
check(targetLabel and targetLabel:GetText() == "Target" and targetLabel:IsShown() == true,
    "the Target placeholder has its visible label")
check(focusLabel and focusLabel:GetText() == "Focus" and focusLabel:IsShown() == true,
    "the Focus placeholder has its visible label")

ns.TargetFocusDR.StartPreview()
check(GetTargetFocusSlot("target", 1) and GetTargetFocusSlot("target", 1):IsShown() == true,
    "explicit Preview Mode shows Target sample icons")
check(GetTargetFocusSlot("focus", 1) and GetTargetFocusSlot("focus", 1):IsShown() == true,
    "explicit Preview Mode shows Focus sample icons")
ns.TargetFocusDR.StopPreview()
check(GetTargetFocusSlot("target", 1):IsShown() == false
        and GetTargetFocusSlot("focus", 1):IsShown() == false,
    "stopping Preview Mode restores unlocked placeholders without sample icons")

ArenaDRNameplatesDB.targetFocusDR.target.timers.override = true
ArenaDRNameplatesDB.targetFocusDR.target.timers.timerTextScale = 0.75
ArenaDRNameplatesDB.targetFocusDR.target.timers.timerTextColor = { 1, 0.2, 0.1 }
ArenaDRNameplatesDB.targetFocusDR.focus.timers.override = true
ArenaDRNameplatesDB.targetFocusDR.focus.timers.timerTextScale = 1.5
ArenaDRNameplatesDB.targetFocusDR.focus.timers.timerTextColor = { 0.1, 0.4, 1 }
ns.Shared.InvalidateDB()
ns.TargetFocusDR.StartPreview()

local targetTimerText = GetTargetFocusSlot("target", 1).Cooldown.Text
local focusTimerText = GetTargetFocusSlot("focus", 1).Cooldown.Text
check(targetTimerText.fontSize == 29 and focusTimerText.fontSize == 34,
    "Target and Focus countdown text sizes can be overridden independently")
check(targetTimerText.textColor[1] == 1
        and targetTimerText.textColor[2] == 0.2
        and focusTimerText.textColor[2] == 0.4
        and focusTimerText.textColor[3] == 1,
    "Target and Focus countdown text colors can be overridden independently")
ns.TargetFocusDR.StopPreview()

ArenaDRNameplatesDB.targetFocusDR.enabled = false
ArenaDRNameplatesDB.targetFocusDR.showTarget = false
ArenaDRNameplatesDB.targetFocusDR.showFocus = false
ArenaDRNameplatesDB.targetFocusDR.locked = true
arenaActive = false
ns.Shared.InvalidateDB()
ns.TargetFocusDR.StartPreview()
check(targetBar:IsShown() == false and focusBar:IsShown() == false,
    "Preview hides Target and Focus while their feature is disabled")
check(GetTargetFocusSlot("target", 1):IsShown() == false
        and GetTargetFocusSlot("focus", 1):IsShown() == false,
    "a disabled Target/Focus feature shows no sample icons")
ns.TargetFocusDR.StopPreview()

ArenaDRNameplatesDB.targetFocusDR.enabled = true
ArenaDRNameplatesDB.targetFocusDR.showTarget = true
ArenaDRNameplatesDB.targetFocusDR.showFocus = false
ArenaDRNameplatesDB.targetFocusDR.locked = false
ns.Shared.InvalidateDB()
ns.TargetFocusDR.StartPreview()
check(targetBar:IsShown() == true and focusBar:IsShown() == false,
    "Preview shows only the individually enabled Target bar")
check(GetTargetFocusSlot("target", 1):IsShown() == true
        and GetTargetFocusSlot("focus", 1):IsShown() == false,
    "Show Focus DR off hides the Focus sample icons and placement frame")
ns.TargetFocusDR.StopPreview()
check(targetBar:IsShown() == false and focusBar:IsShown() == false,
    "stopping the filtered preview hides every Target/Focus bar")
check(targetLabel:IsShown() == false and focusLabel:IsShown() == false,
    "stopping preview also hides the Target and Focus labels")

ArenaDRNameplatesDB.targetFocusDR.enabled = true
ArenaDRNameplatesDB.targetFocusDR.showTarget = true
ArenaDRNameplatesDB.targetFocusDR.showFocus = true
ArenaDRNameplatesDB.targetFocusDR.locked = false
arenaActive = true
ns.Shared.InvalidateDB()
ns.TargetFocusDR.Refresh()

local originalTargetSetPoint = targetBar.SetPoint
local targetSetPointCalls = 0
targetBar.SetPoint = function()
    targetSetPointCalls = targetSetPointCalls + 1
end
targetBar.GetCenter = function()
    return 610, 410
end
UIParent.GetCenter = function()
    return 500, 400
end
TargetFrame.GetCenter = function()
    return 500, 400
end

RunScript(targetBar, "OnDragStart")
local setPointCallsBeforeRefresh = targetSetPointCalls
ns.TargetFocusDR.Refresh()
check(targetBar.isDragging == true and targetSetPointCalls == setPointCallsBeforeRefresh,
    "refreshing the preview does not re-anchor the Target bar mid-drag")

RunScript(targetBar, "OnDragStop")
check(targetBar.isDragging == nil and targetSetPointCalls == setPointCallsBeforeRefresh + 1,
    "dropping the Target bar saves and reapplies its final anchor once")
check(ArenaDRNameplatesDB.targetFocusDR.target.offsetX == 110
        and ArenaDRNameplatesDB.targetFocusDR.target.offsetY == 10,
    "dropping the Target bar persists its new center offsets")

targetBar.SetPoint = originalTargetSetPoint
targetBar.SetScale = originalTargetSetScale
focusBar.SetScale = originalFocusSetScale
targetBar.SetSize = originalTargetSetSize
focusBar.SetSize = originalFocusSetSize
ArenaDRNameplatesDB.targetFocusDR.target.scale = 1.0
ArenaDRNameplatesDB.targetFocusDR.focus.scale = 1.0
ArenaDRNameplatesDB.targetFocusDR.size = 32
ArenaDRNameplatesDB.targetFocusDR.locked = true
ns.Shared.InvalidateDB()
ns.TargetFocusDR.Refresh()

--- Scale regression coverage ---------------------------------------------

ArenaDRNameplatesDB.scale = 2
ArenaDRNameplatesDB.scaleWithNameplate = true
ArenaDRNameplatesDB.trinket.enabled = true
ArenaDRNameplatesDB.trinket.size = 44
_G.ArenaDRNameplates_UpdateScale()
_G.ArenaDRNameplates_ToggleTestMode()
runTimers()

local testTray = GetFrameByNameFragment("ArenaDrNP_Core_TestTray_")
local testTrinket = GetFrameByNameFragment("ArenaDrNP_Core_TrinketIcon_Test")
local testIcon = testTray and testTray.previewIcons and testTray.previewIcons[1]
check(testTray and testTray.scale == 1 and testIcon and testIcon.width == 52,
    "the nameplate preview keeps its positioned tray unscaled and resizes icons physically")
check(testTrinket and testTrinket.scale == 1
        and testTrinket.width == 44 and testTrinket.height == 44,
    "the trinket size changes its physical dimensions without scaling its anchor")

local originalNameplateEffectiveScale = nameplate.UnitFrame.GetEffectiveScale
nameplate.UnitFrame.GetEffectiveScale = function()
    return 2
end
ArenaDRNameplatesDB.scaleWithNameplate = false
_G.ArenaDRNameplates_UpdateScale()
runTimers()
check(testIcon.width == 26 and testTray.scale == 1,
    "fixed-size nameplate icons compensate for parent scale without transforming the tray")

_G.ArenaDRNameplates_ToggleTestMode()
nameplate.UnitFrame.GetEffectiveScale = originalNameplateEffectiveScale
ArenaDRNameplatesDB.scale = 1
ArenaDRNameplatesDB.scaleWithNameplate = true
ArenaDRNameplatesDB.trinket.enabled = false
ArenaDRNameplatesDB.trinket.size = 22
_G.ArenaDRNameplates_UpdateScale()
runTimers()

--- Scenario 1: a crowd control lands, then breaks ------------------------

local item = CreateTrayItem()
FireCoreEvent("ARENA_OPPONENT_UPDATE", "arena1")
TickCooldowns()

check(GetMirrorSlot(1) ~= nil, "the mirror binds a slot to the new tray item")

-- Blizzard shows the icon and zeroes its swipe while the control runs.
item:Show()
item.Cooldown:SetCooldown(0, 0)
item.ImmunityIndicator:SetShown(false)
runTimers()

local slot = GetMirrorSlot(1)
check(slot:IsShown() == true, "the icon appears while the crowd control runs")
check(MirrorRemaining(1) == nil, "no countdown runs while the crowd control is active")

ArenaDRNameplatesDB.scale = 1.5
_G.ArenaDRNameplates_UpdateScale()
runTimers()
local liveContainer = ns.ArenaDRMirror:GetContainer(1)
check(liveContainer and liveContainer.scale == 1
        and slot.width == 39 and liveContainer.width == 39,
    "live nameplate DR scaling resizes the icon and layout without moving the anchor")
ArenaDRNameplatesDB.scale = 1
_G.ArenaDRNameplates_UpdateScale()
runTimers()

check(GetTargetFocusSlot("target", 1) and GetTargetFocusSlot("target", 1):IsShown() == true,
    "the Target bar mirrors the active arena DR icon")
check(GetTargetFocusSlot("focus", 1) and GetTargetFocusSlot("focus", 1):IsShown() == true,
    "the Focus bar mirrors the active arena DR icon")
check(TargetFocusRemaining("target", 1) == nil,
    "the Target bar does not count down while crowd control is active")

-- The control breaks four seconds later and the reset window starts.
advance(4)
TickCooldowns()
item.Cooldown:SetCooldown(now, 20)
runTimers()

check(MirrorRemaining(1) ~= nil, "the countdown starts when the crowd control breaks")
check(math.abs((MirrorRemaining(1) or 0) - 20) < 0.2,
    "the countdown mirrors the source reset window")
check(TargetFocusRemaining("target", 1)
        and math.abs(TargetFocusRemaining("target", 1) - 20) < 0.2,
    "the Target bar mirrors the source reset countdown")
check(TargetFocusRemaining("focus", 1)
        and math.abs(TargetFocusRemaining("focus", 1) - 20) < 0.2,
    "the Focus bar mirrors the source reset countdown")

-- Immunity turning on mid window must not restart the countdown.
advance(5)
TickCooldowns()
item.ImmunityIndicator:SetShown(true)
runTimers()
check(math.abs((MirrorRemaining(1) or 0) - 15) < 0.3,
    "an immunity change leaves the running countdown alone")
check(GetTargetFocusSlot("target", 1).isImmune == true,
    "the Target bar mirrors Blizzard's immune state")

-- The window ends: Blizzard hides its item, and the mirror follows.
advance(15.5)
TickCooldowns()
runTimers()
check(MirrorRemaining(1) == nil, "the countdown clears when the window ends")
check(slot:IsShown() == false, "the icon leaves the nameplate when the window ends")
check(GetTargetFocusSlot("target", 1):IsShown() == false,
    "the Target bar clears the icon when the reset window ends")
check(GetTargetFocusSlot("focus", 1):IsShown() == false,
    "the Focus bar clears the icon when the reset window ends")

-- Target/Focus remains usable while the opponent's nameplate is temporarily
-- absent; the arena unit comparison is the protected-identity-safe fallback.
plateVisible = false
helper:OnEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
runTimers()
FireCoreEvent("ARENA_OPPONENT_UPDATE", "arena1")
item:Show()
item.Cooldown:SetCooldown(0, 0)
runTimers()
check(GetTargetFocusSlot("target", 1):IsShown() == true,
    "the Target bar survives a temporarily missing nameplate")
check(GetTargetFocusSlot("focus", 1):IsShown() == true,
    "the Focus bar survives a temporarily missing nameplate")
item:Hide()
plateVisible = true
helper:OnEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
runTimers()
FireCoreEvent("ARENA_OPPONENT_UPDATE", "arena1")

--- Scenario 2: Blizzard's tray stops reporting the end -------------------
-- Another addon reparents the arena frames into a hidden frame, so the source
-- cooldown never reaches its own expiry and the item is never hidden.

item:Show()
item.Cooldown:SetCooldown(0, 0)
runTimers()
check(GetMirrorSlot(1):IsShown() == true, "a second crowd control shows the icon again")
check(MirrorRemaining(1) == nil, "the second crowd control shows no countdown yet")

advance(3)
item.Cooldown:SetCooldown(now, 20)
runTimers()
check(MirrorRemaining(1) ~= nil, "the second reset window starts counting")

-- Freeze the source: no OnCooldownDone, no Hide, exactly what a hidden arena
-- frame produces.
item.Cooldown.SetCooldown = function() end
item.Cooldown.Clear = function() end
advance(21)
runTimers()

check(MirrorRemaining(1) == nil, "the mirror expires its own window without the source")
check(GetMirrorSlot(1):IsShown() == false,
    "a finished window never leaves a timerless icon on the nameplate")

--- Scenario 3: a tray item bound while its window already runs -----------

local lateItem = CreateTrayItem()
lateItem:Show()
lateItem.Cooldown:SetCooldown(now - 6, 20)
FireCoreEvent("ARENA_COOLDOWNS_UPDATE")
runTimers()

local lateRemaining = MirrorRemaining(2)
check(lateRemaining ~= nil, "a late bound item adopts the running reset window")
check(lateRemaining and math.abs(lateRemaining - 14) < 0.3,
    "the adopted countdown keeps the source's remaining time")
check(GetMirrorSlot(2):IsShown() == true, "the late bound icon is visible")

--- Scenario 4: a tray icon created mid combat, with secret values ---------
-- No arena event follows, so only the runtime tick can notice the new child.

combatSecrets = true

local combatItem = CreateTrayItem()
combatItem:Show()
combatItem.Cooldown:SetCooldown(0, 0)
advance(1)
TickCooldowns()

check(GetMirrorSlot(3) ~= nil, "the runtime tick picks up a tray icon created mid combat")
check(GetMirrorSlot(3) and GetMirrorSlot(3):IsShown() == true,
    "the icon created mid combat reaches the nameplate")
check(MirrorRemaining(3) == nil,
    "no countdown runs during the crowd control while values are secret")

combatItem.Cooldown:SetCooldown(now, 20)
runTimers()
local secretRemaining = MirrorRemaining(3)
check(secretRemaining ~= nil, "a secret reset window still starts the countdown")
check(secretRemaining and secretRemaining > 19 and secretRemaining < 21,
    "the secret window falls back to the public reset duration")

-- A second crowd control lands on top of the running window: Blizzard zeroes the
-- swipe again, and the countdown has to stop until this control breaks too.
advance(3)
combatItem.Cooldown:SetCooldown(0, 0)
runTimers()
check(MirrorRemaining(3) == nil,
    "a crowd control landing mid combat stops the countdown instead of restarting it")
check(GetMirrorSlot(3) and GetMirrorSlot(3):IsShown() == true,
    "the icon stays on the nameplate while that crowd control runs")

advance(4)
combatItem.Cooldown:SetCooldown(now, 20)
runTimers()
check(MirrorRemaining(3) ~= nil, "the countdown resumes when the second control breaks")

--- Scenario 5: adopting a running window whose times are secret -----------

local secretLateItem = CreateTrayItem()
secretLateItem:Show()
secretLateItem.Cooldown:SetCooldown(now - 5, 20)
FireCoreEvent("ARENA_COOLDOWNS_UPDATE")
runTimers()

check(MirrorRemaining(4) ~= nil,
    "a late bound item with secret times still adopts a running window")
check(GetMirrorSlot(4) and GetMirrorSlot(4):IsShown() == true,
    "the adopted icon with secret times is visible")

-- Repeated resyncs must not restart that adopted window.
local adoptedRemaining = MirrorRemaining(4)
advance(2)
FireCoreEvent("ARENA_COOLDOWNS_UPDATE")
runTimers()
check(MirrorRemaining(4) and math.abs(MirrorRemaining(4) - (adoptedRemaining - 2)) < 0.3,
    "a resync leaves an adopted countdown running instead of restarting it")

-- And once the window is over the icon still leaves the nameplate, even though
-- the source never reported the end.
secretLateItem.Cooldown.SetCooldown = function() end
advance(20)
runTimers()
check(GetMirrorSlot(4) and GetMirrorSlot(4):IsShown() == false,
    "an adopted window that finishes hides its icon")

io.write(failures == 0 and "\nAll DR mirror checks passed.\n"
    or ("\n" .. failures .. " DR mirror check(s) failed.\n"))
os.exit(failures == 0 and 0 or 1)
