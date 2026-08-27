-- Drives the personal DR tracker against a stubbed Loss of Control list.
-- Run from the addon root with: lua Tests/SelfDRHarness.lua
--
-- The tracker shows an icon without a countdown while a crowd control runs and
-- only starts the reset window once it ends, so the checks below follow that
-- transition through the events and through the fallback poll.

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

function issecretvalue()
    return false
end

--- Clock and timers --------------------------------------------------------

local now = 500
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
}

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

local function activeTickerCount()
    local count = 0
    for _, timer in ipairs(timers) do
        if timer.interval and not timer.cancelled then
            count = count + 1
        end
    end
    return count
end

--- Widgets -----------------------------------------------------------------

local Frame = {}
Frame.__index = Frame

function Frame:SetScript(script, handler)
    self.scriptHandlers = self.scriptHandlers or {}
    self.scriptHandlers[script] = handler
end

function Frame:HookScript(script, handler)
    self.hookedScripts = self.hookedScripts or {}
    self.hookedScripts[script] = self.hookedScripts[script] or {}
    table.insert(self.hookedScripts[script], handler)
end

function Frame:GetScript(script)
    return self.scriptHandlers and self.scriptHandlers[script]
end

function Frame:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end

function Frame:RegisterUnitEvent(event)
    self:RegisterEvent(event)
end

function Frame:UnregisterEvent(event)
    if self.events then
        self.events[event] = nil
    end
end

function Frame:Show()
    self.shown = true
end

function Frame:Hide()
    self.shown = false
end

function Frame:SetShown(shown)
    self.shown = shown and true or false
end

function Frame:IsShown()
    return self.shown == true
end

function Frame:GetObjectType()
    return self.objectType or "Frame"
end

function Frame:GetParent()
    return self.parent
end

function Frame:CreateTexture()
    local texture = setmetatable({ objectType = "Texture", parent = self }, Frame)
    self.regions = self.regions or {}
    table.insert(self.regions, texture)
    return texture
end

function Frame:CreateFontString()
    local fontString = setmetatable({ objectType = "FontString", parent = self, text = "" }, Frame)
    self.regions = self.regions or {}
    table.insert(self.regions, fontString)
    return fontString
end

function Frame:GetRegions()
    return table.unpack(self.regions or {})
end

function Frame:GetChildren()
    return table.unpack(self.children or {})
end

function Frame:SetScale(scale)
    self.scale = scale
end

function Frame:SetSize(width, height)
    self.width = width
    self.height = height
end

function Frame:SetPoint(point, relativeFrame, relativePoint, offsetX, offsetY)
    self.anchorPoint = point
    self.anchorRelativeFrame = relativeFrame
    self.anchorRelativePoint = relativePoint
    self.anchorOffsetX = offsetX
    self.anchorOffsetY = offsetY
end

function Frame:SetText(text)
    self.text = text
end

local NOOP_METHODS = {
    "SetSize", "SetWidth", "SetHeight", "SetPoint", "SetAllPoints", "ClearAllPoints",
    "SetFrameStrata", "SetFrameLevel", "EnableMouse", "SetAlpha", "SetScale",
    "SetIgnoreParentAlpha", "SetTexture", "SetAtlas", "SetTexCoord", "SetColorTexture",
    "SetVertexColor", "SetDrawLayer", "SetTextColor", "SetText", "SetFont",
    "SetJustifyH", "SetJustifyV", "SetShadowOffset", "SetShadowColor", "SetReverse",
    "SetDrawSwipe", "SetSwipeColor", "SetDrawEdge", "SetDrawBling",
    "SetHideCountdownNumbers", "SetCountdownMillisecondsThreshold", "SetMovable",
    "SetClampedToScreen", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
    "SetUserPlaced", "SetToplevel", "SetClipsChildren", "SetPropagateMouseClicks",
    "SetPropagateMouseMotion", "SetMouseClickEnabled", "SetMouseMotionEnabled",
    "SetAlphaFromBoolean", "Raise", "SetParent",
}

for _, name in ipairs(NOOP_METHODS) do
    if not Frame[name] then
        Frame[name] = function() end
    end
end

function Frame:GetWidth()
    return 32
end

function Frame:GetHeight()
    return 32
end

function Frame:GetEffectiveScale()
    return 1
end

function Frame:GetCenter()
    return self.centerX or 500, self.centerY or 400
end

function Frame:GetFrameLevel()
    return 1
end

function Frame:GetText()
    return self.text
end

local Cooldown = setmetatable({}, { __index = Frame })
Cooldown.__index = Cooldown

function Cooldown:SetCooldown(start, duration)
    if not start or not duration or duration <= 0 then
        self.start = nil
        self.duration = nil
        return
    end
    self.start = start
    self.duration = duration
end

function Cooldown:Clear()
    self.start = nil
    self.duration = nil
end

function Cooldown:GetCooldownTimes()
    if not self.start then
        return 0, 0
    end
    return self.start * 1000, self.duration * 1000
end

function Cooldown:GetCountdownFontString()
    return nil
end

function CreateFrame(frameType, name, parent)
    local metatable = frameType == "Cooldown" and Cooldown or Frame
    local frame = setmetatable({
        frameType = frameType,
        frameName = name,
        parent = parent,
        shown = true,
        children = {},
        regions = {},
    }, metatable)
    if name then
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
PlayerFrame = CreateFrame("Frame", "PlayerFrame", UIParent)
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a }
end

--- Game API ----------------------------------------------------------------

function IsInInstance()
    return true, "arena"
end

function IsActiveBattlefieldArena()
    return true
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

C_CVar = {
    GetCVarBool = GetCVarBool,
    GetCVar = function() return "1" end,
    GetCVarDefault = function() return "1" end,
    SetCVar = function() end,
}

C_PvP = {
    IsMatchConsideredArena = function() return true end,
    IsMatchActive = function() return true end,
    IsMatchComplete = function() return false end,
}

-- The stubbed Loss of Control list. readFails simulates a protected read, which
-- must never be taken for a crowd control that ended.
local locEntries = {}
local readFails = false

C_LossOfControl = {
    GetActiveLossOfControlDataCountByUnit = function(unit)
        return unit == "player" and #locEntries or 0
    end,
    GetActiveLossOfControlDataCount = function()
        return #locEntries
    end,
    GetActiveLossOfControlDataByUnit = function(_, index)
        if readFails then
            error("protected")
        end
        return locEntries[index]
    end,
}

local function ApplyStun(auraInstanceID)
    locEntries = {
        {
            lockType = "STUN_MECHANIC",
            spellID = 408,
            startTime = now,
            duration = 4,
            auraInstanceID = auraInstanceID,
        },
    }
end

local function ClearLossOfControl()
    locEntries = {}
end

--- Addon load --------------------------------------------------------------

local ns = {}
loadAddonFile("Shared.lua", ns)
loadAddonFile("Locales/enUS.lua", ns)

ArenaDRNameplatesDB = nil
local db = ns.Shared.EnsureDB()

loadAddonFile("SelfDR.lua", ns)
local SelfDR = ns.SelfDR

SelfDR.StartPreview()
local disabledPreviewContainer
for name, frame in pairs(_G) do
    if type(name) == "string"
        and name:find("ArenaDrNP_SelfDR_Container_", 1, true) == 1 then
        disabledPreviewContainer = frame
        break
    end
end
check(disabledPreviewContainer == nil,
    "Preview creates no My DRs placement frame while the feature is disabled")
SelfDR.StopPreview()

db.selfDR.enabled = true
db.selfDR.showInArena = true
ns.Shared.InvalidateDB()
SelfDR.RefreshAll()
runTimers()

local selfDRContainer
for name, frame in pairs(_G) do
    if type(name) == "string"
        and name:find("ArenaDrNP_SelfDR_Container_", 1, true) == 1 then
        selfDRContainer = frame
        break
    end
end
check(selfDRContainer ~= nil, "the personal DR container is reachable for UI checks")
check(db.selfDR.locked == false,
    "the personal DR placement handle is unlocked by default")
check(db.selfDR.relativeFrame == "PlayerFrame"
        and selfDRContainer.anchorRelativeFrame == PlayerFrame,
    "the personal DR tray is anchored to PlayerFrame by default")
db.selfDR.size = 64
ns.Shared.InvalidateDB()
SelfDR.Refresh()

local selfDRLabel
for _, region in ipairs({ selfDRContainer:GetRegions() }) do
    if region:GetObjectType() == "FontString" then
        selfDRLabel = region
        break
    end
end

check(selfDRContainer:IsShown() == true,
    "the unlocked personal DR tray remains visible as a placement handle")
check(selfDRContainer.scale == 1,
    "the personal DR tray keeps its positioned parent frame unscaled")
check(selfDRContainer.width == 64 and selfDRContainer.height == 64,
    "the personal DR tray applies its size directly to the placeholder layout")
check(selfDRLabel and selfDRLabel:GetText() == "My DRs" and selfDRLabel:IsShown() == true,
    "the personal DR placeholder has its visible My DRs label")

db.selfDR.locked = true
db.selfDR.size = 32
ns.Shared.InvalidateDB()
SelfDR.Refresh()

local function StunState()
    return SelfDR.GetCategoryState("stun")
end

local function StunRemaining()
    local state = StunState()
    if not state or not state.expiresAt then
        return nil
    end
    return state.expiresAt - now
end

local function GetSelfDRIcon(category)
    local expected = "ArenaDrNP_SelfDR_Icon_" .. category
    for name, frame in pairs(_G) do
        if type(name) == "string" and name:find(expected, 1, true) == 1 then
            return frame
        end
    end
end

--- A stun lands: the icon tracks it without a countdown -------------------

ApplyStun(11)
SelfDR.RefreshAll()
runTimers()

check(StunState() and StunState().isActive == true, "the tracker follows an active stun")
check(StunState().stage == 1, "the first stun records the half stage")
check(StunRemaining() == nil, "no reset window runs while the stun is active")
check(activeTickerCount() >= 1, "an active crowd control arms the fallback poll")

db.selfDR.size = 64
ns.Shared.InvalidateDB()
SelfDR.Refresh()
local stunIcon = GetSelfDRIcon("stun")
check(selfDRContainer.scale == 1 and stunIcon and stunIcon.scale ~= 2,
    "resizing an active My DRs tray never scales its positioned parent or icon frame")
check(stunIcon and stunIcon.width == 64 and stunIcon.height == 64,
    "My DRs resizes active icons physically")
check(selfDRContainer.width == 64 and selfDRContainer.height == 64,
    "My DRs resizes its active one-icon layout without moving the anchor")
db.selfDR.size = 32
ns.Shared.InvalidateDB()
SelfDR.Refresh()

--- The stun ends with no aura event to announce it ------------------------
-- This is the case that used to leave the icon on screen with no countdown for
-- the rest of the match.

advance(4)
ClearLossOfControl()
advance(0.2)

check(StunRemaining() ~= nil, "the reset window starts from the poll alone")
check(StunRemaining() and math.abs(StunRemaining() - 20) < 0.4,
    "the reset window runs for the full 20 seconds")
check(StunState().isActive == false, "the tracker sees the stun as over")
check(activeTickerCount() == 0, "the poll stops once no crowd control is active")

--- A protected read must not start a window -------------------------------

ApplyStun(12)
SelfDR.RefreshAll()
runTimers()
check(StunState().isActive == true, "a second stun is tracked")
check(StunState().stage == 2, "a stun inside the window reaches the immune stage")

local windowBeforeFailure = StunState().expiresAt
readFails = true
advance(0.5)
check(StunState().isActive == true, "a failed Loss of Control read leaves the stun active")
check(StunState().expiresAt == windowBeforeFailure,
    "a failed read never starts the reset window early")

readFails = false
ClearLossOfControl()
advance(0.2)
check(StunRemaining() ~= nil, "the window starts once the reads recover and the stun ends")

--- The window expiring clears the state ----------------------------------

advance(21)
local expiredState = StunState()
check(expiredState.expiresAt == nil or expiredState.expiresAt <= now,
    "the reset window is no longer pending after it elapses")

--- Position migration ----------------------------------------------------

ArenaDRNameplatesDB = {
    selfDR = {
        locked = true,
        point = "CENTER",
        relativePoint = "CENTER",
        offsetX = 0,
        offsetY = -180,
    },
    targetFocusDR = {
        locked = true,
        target = {
            point = "CENTER",
            relativePoint = "CENTER",
            offsetX = 0,
            offsetY = -115,
        },
        focus = {
            point = "CENTER",
            relativePoint = "CENTER",
            offsetX = 0,
            offsetY = -65,
        },
    },
}
ns.Shared.InvalidateDB()
local migratedDB = ns.Shared.EnsureDB()
check(migratedDB.selfDR.locked == false
        and migratedDB.selfDR.relativeFrame == "PlayerFrame",
    "the legacy default My DRs position migrates to an unlocked PlayerFrame anchor")
check(migratedDB.targetFocusDR.locked == false
        and migratedDB.targetFocusDR.target.relativeFrame == "TargetFrame"
        and migratedDB.targetFocusDR.focus.relativeFrame == "FocusFrame",
    "the legacy default Target and Focus positions migrate to unlocked Unit Frame anchors")

ArenaDRNameplatesDB = {
    selfDR = {
        point = "CENTER",
        relativePoint = "CENTER",
        offsetX = 125,
        offsetY = -90,
    },
}
ns.Shared.InvalidateDB()
local customPositionDB = ns.Shared.EnsureDB()
check(customPositionDB.selfDR.relativeFrame == "UIParent"
        and customPositionDB.selfDR.offsetX == 125
        and customPositionDB.selfDR.offsetY == -90,
    "a legacy custom My DRs position remains relative to UIParent")

io.write(failures == 0 and "\nAll personal DR checks passed.\n"
    or ("\n" .. failures .. " personal DR check(s) failed.\n"))
os.exit(failures == 0 and 0 or 1)
