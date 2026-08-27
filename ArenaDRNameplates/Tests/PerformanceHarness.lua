-- Run from the addon root with: lua Tests/PerformanceHarness.lua

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

local function makeFrame(fields)
    local frame = fields or {}
    frame.GetObjectType = frame.GetObjectType or function()
        return "Frame"
    end
    return frame
end

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

local secretValuePredicate
function issecretvalue(value)
    return secretValuePredicate and secretValuePredicate(value) == true or false
end

-- Performance: deterministic timing, counters, status, and automatic report.
do
    local now = 0
    local completionSnapshot
    local scheduledTimer

    function debugprofilestop()
        return now
    end

    C_Timer = {
        NewTimer = function(delay, callback)
            scheduledTimer = {
                delay = delay,
                callback = callback,
                Cancel = function(self)
                    self.cancelled = true
                end,
            }
            return scheduledTimer
        end,
    }

    local ns = {}
    loadAddonFile("Performance.lua", ns)
    local performance = ns.Performance
    local started, duration = performance:Start(60, function(snapshot)
        completionSnapshot = snapshot
    end)
    check(started == true and duration == 60, "performance capture starts for 60 seconds")
    check(scheduledTimer and scheduledTimer.delay == 60, "performance capture schedules automatic completion")

    now = 10
    local measurement = performance:Begin()
    now = 13.5
    performance:Finish("mapping.validate", measurement)
    performance:Count("runtime.coalesced", 2)
    now = 25000
    local restarted, remaining = performance:Start(60)
    check(restarted == false and math.floor(remaining + 0.5) == 35,
        "a running performance capture reports remaining time without restarting")

    now = 60000
    scheduledTimer.callback()
    local metric = completionSnapshot
        and completionSnapshot.metrics
        and completionSnapshot.metrics["mapping.validate"]
    check(metric and metric.calls == 1 and metric.total == 3.5 and metric.maximum == 3.5,
        "performance capture aggregates calls, total, and maximum")
    check(completionSnapshot
        and completionSnapshot.counters
        and completionSnapshot.counters["runtime.coalesced"] == 2,
        "performance capture aggregates counters")
    check(performance:IsActive() == false, "performance capture stops automatically")

    debugprofilestop = nil
end

-- Registry: cached availability, weak plate selection, and capability lists.
do
    local ns = {}
    loadAddonFile("Adapters/Registry.lua", ns)
    local registry = ns.NameplateAdapters
    local availabilityCalls = 0
    local plate = makeFrame({ namePlateUnitToken = "nameplate1" })

    registry:RegisterAdapter({
        id = "Plater",
        priority = 100,
        IsAvailable = function()
            availabilityCalls = availabilityCalls + 1
            return true
        end,
        GetTokenFromPlate = function(_, candidate)
            return candidate.namePlateUnitToken
        end,
        GetAnchorParent = function(_, candidate)
            return candidate
        end,
    })

    registry:InvalidateAvailabilityCache()
    availabilityCalls = 0
    local allTokensResolved = true
    for _ = 1, 100 do
        local token = registry:ResolveTokenForPlate(plate)
        allTokensResolved = allTokensResolved and token == "nameplate1"
    end
    check(allTokensResolved, "registry resolves 100 cached nameplate tokens")
    check(availabilityCalls == 1, "100 resolutions compute adapter availability once")

    for _, id in ipairs({ "ThreatPlates", "Platynator", "ElvUI", "EllesmereUI", "Blizzard" }) do
        registry:RegisterAdapter({
            id = id,
            priority = 1,
            IsAvailable = function()
                return true
            end,
        })
    end

    local layoutCalls = 0
    local castbar = makeFrame()
    registry:RegisterAdapter({
        id = "BetterBlizzPlates",
        priority = 10,
        IsAvailable = function()
            return true
        end,
        GetLayoutAnchor = function()
            layoutCalls = layoutCalls + 1
            return castbar
        end,
    })

    local resolved = registry:ResolveLayoutAnchor(plate, {})
    check(resolved == castbar, "layout anchor resolves through BetterBlizzPlates")
    check(#registry.layoutAdapters == 1 and registry.layoutAdapters[1].id == "BetterBlizzPlates",
        "only BetterBlizzPlates is present in the layout-capability list")
    check(layoutCalls == 1, "GetLayoutAnchor consults BetterBlizzPlates once")
end

-- Helper: no out-of-arena timers and one cancelable retry chain in arena.
do
    local arenaActive = false
    local plateVisible = false
    local identityProtected = false
    local timers = {}
    local nameplateScans = 0

    local function pendingTimerCount()
        local count = 0
        for _, timer in ipairs(timers) do
            if not timer.cancelled and not timer.fired then
                count = count + 1
            end
        end
        return count
    end

    local function runNextTimer()
        for _, timer in ipairs(timers) do
            if not timer.cancelled and not timer.fired then
                timer.fired = true
                timer.callback()
                return true
            end
        end
        return false
    end

    C_Timer = {
        NewTimer = function(delay, callback)
            local timer = { delay = delay, callback = callback }
            function timer:Cancel()
                self.cancelled = true
            end
            timers[#timers + 1] = timer
            return timer
        end,
    }

    local helperFrame
    function CreateFrame()
        local frame = { events = {} }
        function frame:RegisterEvent(event)
            self.events[event] = true
        end
        function frame:UnregisterEvent(event)
            self.events[event] = nil
        end
        function frame:SetScript(_, callback)
            self.eventCallback = callback
        end
        helperFrame = frame
        return frame
    end

    function IsActiveBattlefieldArena()
        return arenaActive
    end
    function IsInInstance()
        return arenaActive, arenaActive and "arena" or "none"
    end

    local identities = {
        arena1 = "enemy-1",
        nameplate1 = "enemy-1",
        player = "player-1",
    }
    function UnitExists(unit)
        if unit == "arena1" then
            return arenaActive
        end
        if unit == "nameplate1" then
            return arenaActive and plateVisible
        end
        return unit == "player"
    end
    function UnitGUID(unit)
        if identityProtected and identities[unit] then
            return "secret-guid"
        end
        return identities[unit]
    end
    function UnitName(unit)
        if identityProtected and identities[unit] then
            return "secret-name"
        end
        return identities[unit] and unit or nil
    end
    function UnitClass(unit)
        if identities[unit] then
            if identityProtected then
                return "Secret Class", "SECRET_CLASS"
            end
            return "Rogue", "ROGUE"
        end
    end
    function UnitIsUnit(unitA, unitB)
        if identityProtected then
            return { secret = true }
        end
        return identities[unitA] ~= nil and identities[unitA] == identities[unitB]
    end
    function UnitIsProbablyUnit(unitA, unitB)
        return identities[unitA] ~= nil and identities[unitA] == identities[unitB]
    end
    function UnitCanAttack(_, unit)
        return unit == "nameplate1"
    end
    function UnitIsEnemy(_, unit)
        return unit == "nameplate1"
    end
    function UnitIsPlayer(unit)
        return unit == "nameplate1"
    end
    function UnitTokenFromGUID(guid)
        if plateVisible and guid == "enemy-1" then
            return "nameplate1"
        end
    end

    local anchor = makeFrame()
    local plate = makeFrame({ namePlateUnitToken = "nameplate1", UnitFrame = anchor })
    C_NamePlate = {
        GetNamePlates = function()
            nameplateScans = nameplateScans + 1
            return plateVisible and { plate } or {}
        end,
        GetNamePlateForUnit = function(unit)
            if plateVisible and (unit == "nameplate1" or (unit == "arena1" and not identityProtected)) then
                return plate
            end
        end,
    }

    local ns = {}
    loadAddonFile("Adapters/Registry.lua", ns)
    ns.NameplateAdapters:RegisterAdapter({
        id = "Harness",
        priority = 100,
        GetTokenFromPlate = function(_, candidate)
            return candidate.namePlateUnitToken
        end,
        GetAnchorParent = function(_, candidate)
            return candidate.UnitFrame
        end,
    })
    loadAddonFile("ArenaNameplateHelper.lua", ns)
    local helper = ns.ArenaNameplateHelper

    for index = 1, 20 do
        helper:OnEvent("NAME_PLATE_UNIT_ADDED", "nameplate" .. index)
    end
    check(pendingTimerCount() == 0, "20 nameplates added outside arena create zero timers")
    check(helperFrame.events.NAME_PLATE_UNIT_ADDED == nil,
        "frequent nameplate events remain unregistered outside arena")

    arenaActive = true
    helper:UpdateArenaActivity()
    local neverExceededOneRetry = true
    for _ = 1, 12 do
        helper:OnEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
        neverExceededOneRetry = neverExceededOneRetry and pendingTimerCount() <= 1
    end
    check(neverExceededOneRetry, "simultaneous arena events keep at most one retry pending")
    check(pendingTimerCount() == 1, "an incomplete mapping has exactly one retry pending")

    plateVisible = true
    check(runNextTimer(), "the pending retry can be executed")
    check(pendingTimerCount() == 0, "a complete mapping stops the retry chain immediately")
    local changed, complete = helper:RefreshMappings()
    check(changed == false and complete == true, "RefreshMappings returns stable changed/complete states")

    local scansBeforeValidation = nameplateScans
    local allValid = true
    for _ = 1, 100 do
        allValid = allValid and helper:ValidateMappings()
    end
    check(allValid, "100 stable mapping validations remain complete")
    check(nameplateScans == scansBeforeValidation,
        "100 stable mapping validations perform zero nameplate scans")

    identityProtected = true
    secretValuePredicate = function(value)
        return value == "secret-guid"
            or value == "secret-name"
            or value == "Secret Class"
            or value == "SECRET_CLASS"
            or (type(value) == "table" and value.secret == true)
    end
    helper:ClearMappings()
    local protectedChanged, protectedComplete = helper:RefreshMappings()
    check(protectedChanged == true and protectedComplete == true
        and helper:GetArenaToken(1) == "nameplate1",
        "combat-safe comparison maps opponents when arena identity values are secret")
    check(helper:GetAnchorParentByArenaID(1) == anchor,
        "mapped nameplate token resolves an anchor when direct arena lookup is unavailable")
    check(helper:ValidateMappings(),
        "combat-safe comparison validates a mapping when identity values are secret")
    identityProtected = false
    secretValuePredicate = nil
    check(helper:ValidateMappings(), "public identity validation resumes after arena restrictions end")

    helper:OnEvent("PLAYER_TARGET_CHANGED")
    helper:OnEvent("PLAYER_FOCUS_CHANGED")
    helper:OnEvent("UPDATE_MOUSEOVER_UNIT")
    check(pendingTimerCount() == 0,
        "stable target, focus, and mouseover events schedule no mapping work")

    for _ = 1, 20 do
        helper:OnEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    end
    check(pendingTimerCount() == 1,
        "20 stable nameplate additions coalesce into one validation")
    local scansBeforeAddedValidation = nameplateScans
    check(runNextTimer(), "the coalesced stable nameplate validation can run")
    check(nameplateScans == scansBeforeAddedValidation,
        "a stable nameplate addition validates without a full nameplate scan")

    local mappingNotifications = 0
    local callbackOwner = {}
    helper:RegisterCallback(callbackOwner, function()
        mappingNotifications = mappingNotifications + 1
    end)
    local scansBeforeTokenChurn = nameplateScans
    helper:OnEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    helper:OnEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    check(pendingTimerCount() == 1,
        "same-frame removal and addition share one remapping timer")
    check(runNextTimer(), "the coalesced remapping timer can run")
    check(nameplateScans == scansBeforeTokenChurn + 1,
        "same-frame removal and addition perform one full nameplate scan")
    check(mappingNotifications == 0,
        "same-frame token churn publishes no transient empty mapping")
    helper:UnregisterCallback(callbackOwner)

    arenaActive = false
    helper:UpdateArenaActivity()
    check(pendingTimerCount() == 0, "leaving arena cancels all Helper timers")
    check(helperFrame.events.NAME_PLATE_UNIT_ADDED == nil,
        "leaving arena unregisters frequent nameplate events")
end

-- Helper structural invariants for the lightweight validation path.
do
    local file = assert(io.open("ArenaNameplateHelper.lua", "rb"))
    local source = file:read("*a")
    file:close()
    source = source:gsub("\r\n", "\n")

    local validationBlock = source:match(
        "function Helper:ValidateMappings%(%).-\nend\n\nfunction Helper:GetPlateFrameByToken"
    ) or ""
    check(validationBlock ~= "", "the lightweight mapping validation function is present")
    check(not validationBlock:find("GetNamePlates", 1, true),
        "lightweight mapping validation never scans visible nameplates")
    check(source:find("if hasUnresolvedArena then", 1, true) ~= nil,
        "target, focus, and mouseover fallbacks only run for unresolved opponents")
    check(source:find('unitsShareIdentity("arena" .. arenaID, token)', 1, true) ~= nil,
        "cached mappings are identity-checked before reuse")
    check(source:find("refreshNeedsFullScan", 1, true) ~= nil,
        "mapping refresh requests can upgrade one coalesced validation to a full scan")
end

-- Core structural invariants that protect the mocked runtime counters above.
do
    local file = assert(io.open("Core.lua", "rb"))
    local source = file:read("*a")
    file:close()
    source = source:gsub("\r\n", "\n")

    local tickerCount = 0
    source:gsub("C_Timer%.NewTicker%(1,", function()
        tickerCount = tickerCount + 1
    end)
    check(not source:find("NewTicker%(0%.20"), "the permanent 5 Hz ticker is absent")
    check(tickerCount == 2, "Core defines only the 1-second arena and preview tickers")
    check(source:find("pendingLiveLayouts%[arenaID%]"), "live layout callbacks are coalesced per opponent")
    check(source:find("slot%.ArenaDRNameplatesStyleRevision ~= styleRevision"),
        "unchanged passes skip font, color, and border style application")
    check(source:find("slot.ArenaDRNameplatesLiveSourceReady == true", 1, true) ~= nil,
        "stable DR sources use the source-ready fast path")
    check(source:find("frame.sourceReady == true", 1, true) ~= nil,
        "stable trinket sources use the source-ready fast path")
    check(source:find("runtimeRefreshState.pending", 1, true) ~= nil,
        "runtime refresh requests share one coalesced timer")
    check(not source:find("secret and nil or"), "secret textures and atlases are never stored by a pseudo-ternary")
    check(source:find("local LIVE_DR_RESET_DURATION = Shared.DR_RESET_DURATION", 1, true) ~= nil,
        "DR mirrors take the reset window from the shared constant")

    local sharedFile = assert(io.open("Shared.lua", "rb"))
    local sharedSource = sharedFile:read("*a")
    sharedFile:close()
    check(sharedSource:find("Shared.DR_RESET_DURATION = 20", 1, true) ~= nil,
        "Midnight Season 2 keeps the 20-second reset window")
    check(source:find(
        "local LIVE_DR_TIMER_DURATION = LIVE_DR_RESET_DURATION + 0.1",
        1,
        true
    ) ~= nil, "the local DR fallback retains its source-expiry safety margin")
    check(not source:find("LIVE_DR_IMMUNITY_DURATION", 1, true),
        "immune and reduced DR states share the same reset window")
    check(not source:find("LiveSeverity", 1, true),
        "obsolete DR severity timing state is absent")

    local immunityBlock = source:match("local function SetLiveSlotImmunity.-\nend\n\nlocal function GetLiveAnchorParent") or ""
    check(not immunityBlock:find("LayoutLiveContainer"), "immunity changes do not trigger layout")
    check(immunityBlock:find("not IsSecretValue%(cachedIsImmune%)"),
        "public immunity values are never compared with a secret cached boolean")

    local reconcileBlock = source:match("local function AnchorLiveTray.-\nend\n\nlocal function RestoreAllLiveTrays") or ""
    local layoutCalls = 0
    reconcileBlock:gsub("LayoutLiveContainer%(arenaID%)", function()
        layoutCalls = layoutCalls + 1
    end)
    check(layoutCalls == 1, "each tray reconciliation contains at most one synchronous layout")

    local recoveryBlock = source:match("UpdateRecoveryTicker = function%(%).-\nend\n\nlocal function RegisterHelperCallback") or ""
    check(recoveryBlock:find("ValidateMappings", 1, true) ~= nil,
        "the 1-second recovery ticker uses lightweight mapping validation")
    check(recoveryBlock:find("recoveryTickCount >= 5", 1, true) ~= nil,
        "the recovery ticker forces a full watchdog pass every five seconds")
    check(recoveryBlock:find("RefreshLiveRuntimeLight", 1, true) ~= nil,
        "stable recovery ticks use the lightweight runtime path")

    local lightRuntimeBlock = source:match("RefreshLiveRuntimeLight = function%(%).-\nend\n\nRefreshLiveRuntime = function") or ""
    check(not lightRuntimeBlock:find("ResolveLiveArenaParents", 1, true),
        "the lightweight runtime never resolves nameplates again")
    check(not lightRuntimeBlock:find("GetLiveSourceChildren", 1, true),
        "the lightweight runtime never scans source children")
    check(lightRuntimeBlock:find("GetArenaToken", 1, true) ~= nil,
        "the lightweight runtime only requires parents for populated arena slots")

    local previewTickerBlock = source:match("local function StartPreviewTicker%(%).-\nend\n\nlocal function StartTestMode") or ""
    check(previewTickerBlock:find("UpdatePreviewCooldowns", 1, true) ~= nil,
        "the preview ticker only updates cached cooldown cycles")
    check(not previewTickerBlock:find("RefreshTestTrays", 1, true)
        and not previewTickerBlock:find("RefreshTestTrinket", 1, true),
        "the preview ticker performs no nameplate or layout reconciliation")
end

-- The profiler is loaded before every measured runtime module and all locales expose its messages.
do
    local toc = assert(io.open("ArenaDRNameplates.toc", "rb")):read("*a")
    local performanceIndex = toc:find("Performance.lua", 1, true)
    local helperIndex = toc:find("ArenaNameplateHelper.lua", 1, true)
    check(performanceIndex and helperIndex and performanceIndex < helperIndex,
        "Performance.lua loads before ArenaNameplateHelper.lua")

    for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "ruRU", "ptBR", "koKR", "zhCN", "zhTW" }) do
        local file = assert(io.open("Locales/" .. locale .. ".lua", "rb"))
        local source = file:read("*a")
        file:close()
        check(source:find("L.MSG_PERF_REPORT_HEADER", 1, true) ~= nil,
            locale .. " defines the performance report messages")
    end
end

if failures > 0 then
    error(string.format("performance harness failed: %d assertion(s)", failures), 0)
end

io.write("All performance harness checks passed.\n")
