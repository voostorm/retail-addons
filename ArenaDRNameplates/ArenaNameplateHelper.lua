-- ArenaNameplateHelper.lua
-- Retail Midnight friendly
-- Goal:
--   arena1/arena2/arena3 -> nameplate token -> nameplate frame / anchor parent

local _, ns = ...
ns = ns or {}

local Helper = CreateFrame("Frame", "ArenaDrNP_NameplateHelper")
ns.ArenaNameplateHelper = Helper
local Performance = ns.Performance

Helper.arenaToToken = {}
Helper.tokenToArena = {}
Helper.callbacks = {}

local arenaEventsActive = false
local refreshTimer
local burstTimer
local burstRetryIndex = 0
local refreshNeedsFullScan = false
local mappingComplete = false
local mappingDirty = true
local burstRefreshDelays = { 0.05, 0.12, 0.25, 0.50, 0.90, 1.50 }
local REFERENCE_UNITS = { "target", "focus", "mouseover" }
local ACTIVE_EVENTS = {
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED",
    "FORBIDDEN_NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "FORBIDDEN_NAME_PLATE_UNIT_REMOVED",
}

local scratchArenaGUIDByID = {}
local scratchArenaNameByID = {}
local scratchArenaClassByID = {}
local scratchArenaExistsByID = {}
local scratchEnemyTokenSet = {}
local scratchEnemyTokens = {}
local scratchClassByToken = {}
local scratchNewArenaToToken = {}
local scratchNewTokenToArena = {}
local scratchArenaIDsByName = {}
local scratchTokensByName = {}
local scratchArenaIDsByClass = {}
local scratchTokensByClass = {}
local scratchUnresolvedArenaIDs = {}
local scratchUnresolvedTokens = {}
local scratchArrayPool = {}

local function RecycleScratchMap(map)
    for key, values in pairs(map) do
        wipe(values)
        scratchArrayPool[#scratchArrayPool + 1] = values
        map[key] = nil
    end
end

local function AcquireScratchArray()
    local values = table.remove(scratchArrayPool)
    return values or {}
end

local function isSecretValue(value)
    if type(issecretvalue) ~= "function" then
        return false
    end

    local ok, result = pcall(issecretvalue, value)
    return ok and result == true
end

local function safeCall(func, ...)
    if type(func) ~= "function" then
        return nil, nil, nil, nil
    end

    local ok, a, b, c, d = pcall(func, ...)
    if not ok then
        return nil, nil, nil, nil
    end

    return a, b, c, d
end

local function asPublicString(value)
    if type(value) ~= "string" or isSecretValue(value) then
        return nil
    end
    return value
end

local function asPublicNumber(value)
    if type(value) ~= "number" or isSecretValue(value) then
        return nil
    end
    return value
end

local function asPublicBoolean(value)
    if type(value) ~= "boolean" or isSecretValue(value) then
        return nil
    end
    return value
end

local function safePublicString(func, ...)
    return asPublicString(safeCall(func, ...))
end

local function safePublicNumber(func, ...)
    return asPublicNumber(safeCall(func, ...))
end

local function safePublicBoolean(func, ...)
    return asPublicBoolean(safeCall(func, ...))
end

local function safeUnitExists(unit)
    return safePublicBoolean(UnitExists, unit) == true
end

local function safeUnitsMatch(unitA, unitB)
    if type(UnitIsProbablyUnit) == "function" then
        local probableMatch = safePublicBoolean(UnitIsProbablyUnit, unitA, unitB)
        if probableMatch ~= nil then
            return probableMatch
        end
    end

    return safePublicBoolean(UnitIsUnit, unitA, unitB) == true
end

local function safeUnitCanAttack(unitA, unitB)
    return safePublicBoolean(UnitCanAttack, unitA, unitB)
end

local function safeUnitIsEnemy(unitA, unitB)
    return safePublicBoolean(UnitIsEnemy, unitA, unitB)
end

local function safeUnitIsPlayer(unit)
    return safePublicBoolean(UnitIsPlayer, unit)
end

local function safeUnitName(unit)
    local name = safePublicString(UnitName, unit)
    if name and name ~= "" then
        return name
    end
    return nil
end

local function safeUnitGUID(unit)
    local guid = asPublicString(safeCall(UnitGUID, unit))
    if guid and guid ~= "" then
        return guid
    end
    return nil
end

local function safeUnitClassToken(unit)
    local _, classToken = safeCall(UnitClass, unit)
    classToken = asPublicString(classToken)
    if classToken and classToken ~= "" then
        return classToken
    end
    return nil
end

local FRIENDLY_REFERENCE_UNITS = {
    "player",
    "party1",
    "party2",
    "party3",
    "party4",
}

local isNameplateToken

local function isKnownFriendlyToken(token)
    token = isNameplateToken(token)
    if not token then
        return false
    end

    for _, unit in ipairs(FRIENDLY_REFERENCE_UNITS) do
        if safeUnitsMatch(token, unit) then
            return true
        end
    end

    return false
end

local function isEnemyPlayerToken(token)
    token = isNameplateToken(token)
    if not token or not safeUnitExists(token) then
        return false
    end

    if safeUnitIsPlayer(token) == false then
        return false
    end

    if isKnownFriendlyToken(token) then
        return false
    end

    local canAttack = safeUnitCanAttack("player", token)
    local isEnemy = safeUnitIsEnemy("player", token)

    if canAttack == true or isEnemy == true then
        return true
    end

    if canAttack == false or isEnemy == false then
        return false
    end

    return safeUnitClassToken(token) ~= nil
end

local function isAttackableNameplateToken(token)
    token = isNameplateToken(token)
    if not token or not safeUnitExists(token) then
        return false
    end

    if isKnownFriendlyToken(token) then
        return false
    end

    local canAttack = safeUnitCanAttack("player", token)
    local isEnemy = safeUnitIsEnemy("player", token)
    return canAttack == true or isEnemy == true
end

local function unitsShareIdentity(unitA, unitB)
    unitA = asPublicString(unitA)
    unitB = asPublicString(unitB)
    if not unitA or not unitB then
        return false
    end

    if not safeUnitExists(unitA) or not safeUnitExists(unitB) then
        return false
    end

    if safeUnitsMatch(unitA, unitB) then
        return true
    end

    local guidA = safeUnitGUID(unitA)
    local guidB = safeUnitGUID(unitB)
    return guidA and guidB and guidA == guidB
end

local function isInArenaInstance()
    if C_PvP and type(C_PvP.IsMatchConsideredArena) == "function" then
        local consideredArena = safePublicBoolean(C_PvP.IsMatchConsideredArena)
        if consideredArena == true then
            local matchActive = safePublicBoolean(C_PvP.IsMatchActive)
            local matchComplete = safePublicBoolean(C_PvP.IsMatchComplete)
            if matchActive == true or matchComplete == true then
                return true
            end
        end
    end

    local arenaActive = safePublicBoolean(IsActiveBattlefieldArena)
    if arenaActive == true then
        return true
    end

    local _, instanceType = safeCall(IsInInstance)
    instanceType = asPublicString(instanceType)
    return instanceType == "arena"
end

isNameplateToken = function(token)
    token = asPublicString(token)
    if not token then
        return nil
    end

    if token:match("^nameplate%d+$") then
        return token
    end

    return nil
end

local function getNameplateAdapters()
    return ns and ns.NameplateAdapters
end

local function getNameplateTokenFromUnitFrame(frame)
    if type(frame) ~= "table" then
        return nil
    end

    return isNameplateToken(frame.unit)
        or isNameplateToken(frame.displayedUnit)
end

local function getNameplateTokenFromPlate(plate)
    if type(plate) ~= "table" then
        return nil
    end

    local adapters = getNameplateAdapters()
    if adapters and type(adapters.ResolveTokenForPlate) == "function" then
        local resolvedToken, _, adapter = safeCall(adapters.ResolveTokenForPlate, adapters, plate)
        local token = isNameplateToken(resolvedToken)
        if token then
            return token, adapter
        end
    end

    if isNameplateToken(plate.namePlateUnitToken) then
        return isNameplateToken(plate.namePlateUnitToken)
    end

    if type(plate.UnitFrame) == "table" then
        local token = getNameplateTokenFromUnitFrame(plate.UnitFrame)
        if token then
            return token
        end
    end

    if type(plate.unitFrame) == "table" then
        local token = isNameplateToken(plate.unitFrame.namePlateUnitToken)
            or getNameplateTokenFromUnitFrame(plate.unitFrame)
        if token then
            return token
        end
    end

    return nil
end

local function getVisiblePlates()
    local plates = C_NamePlate.GetNamePlates()
    if type(plates) ~= "table" then
        return nil
    end
    return plates
end

local function getDefaultAnchorParentFromPlate(plate)
    if type(plate) ~= "table" then
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

local function getValidatedTokenForUnitFromPlate(unit, plate)
    unit = asPublicString(unit)
    if not unit or type(plate) ~= "table" then
        return nil
    end

    local token = getNameplateTokenFromPlate(plate)
    if not token then
        return nil
    end

    if isNameplateToken(unit) then
        if token == unit then
            return token
        end
        return nil
    end

    -- C_NamePlate.GetNamePlateForUnit is the authoritative bridge from an
    -- arena unit to its visible plate. Arena identity values such as GUID,
    -- class, name, and UnitIsUnit can all be secret in Midnight combat, so
    -- requiring those values here prevents every live arena mapping.
    if unit:match("^arena[1-3]$") and isEnemyPlayerToken(token) then
        return token
    end

    if unitsShareIdentity(unit, token) then
        return token
    end

    return nil
end

local function tryMap(newArenaToToken, newTokenToArena, arenaID, token)
    arenaID = asPublicNumber(arenaID)
    token = isNameplateToken(token)

    if not arenaID or not token then
        return false
    end

    if not isEnemyPlayerToken(token) then
        return false
    end

    if arenaID < 1 or arenaID > 3 then
        return false
    end

    local oldToken = newArenaToToken[arenaID]
    if oldToken and oldToken ~= token then
        newTokenToArena[oldToken] = nil
    end

    local oldArenaID = newTokenToArena[token]
    if oldArenaID and oldArenaID ~= arenaID then
        newArenaToToken[oldArenaID] = nil
    end

    newArenaToToken[arenaID] = token
    newTokenToArena[token] = arenaID
    return true
end

local function mappingsDiffer(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then
            return true
        end
    end
    for k, v in pairs(b) do
        if a[k] ~= v then
            return true
        end
    end
    return false
end

function Helper:ClearMappings()
    wipe(self.arenaToToken)
    wipe(self.tokenToArena)
    mappingComplete = false
end

local getArenaUnit

function Helper:GetArenaToken(arenaID)
    return self.arenaToToken[arenaID]
end

function Helper:GetArenaIDFromToken(token)
    token = isNameplateToken(token)
    if not token then
        return nil
    end
    return self.tokenToArena[token]
end

-- Resolves a stable unit such as target or focus back to its Blizzard arena
-- opponent index without depending on protected identity values. The visible
-- nameplate bridge is preferred; UnitIsProbablyUnit is the combat-safe fallback
-- when the opponent has no plate (for example during vanish).
function Helper:GetArenaIDForUnit(unit)
    unit = asPublicString(unit)
    if not unit or not safeUnitExists(unit) then
        return nil
    end

    local plate = safeCall(C_NamePlate.GetNamePlateForUnit, unit)
    local token = getNameplateTokenFromPlate(plate)
    local mappedArenaID = token and self:GetArenaIDFromToken(token)
    if mappedArenaID then
        return mappedArenaID
    end

    for arenaID = 1, 3 do
        local arenaUnit = getArenaUnit(arenaID)
        if arenaUnit and safeUnitExists(arenaUnit) and safeUnitsMatch(unit, arenaUnit) then
            return arenaID
        end
    end

    local guid = safeUnitGUID(unit)
    if guid then
        for arenaID = 1, 3 do
            if guid == safeUnitGUID(getArenaUnit(arenaID)) then
                return arenaID
            end
        end
    end

    return nil
end

function Helper:IsMappingComplete()
    return mappingComplete and not mappingDirty
end

getArenaUnit = function(arenaID)
    arenaID = asPublicNumber(arenaID)
    if not arenaID or arenaID < 1 or arenaID > 3 then
        return nil
    end

    return "arena" .. arenaID
end

function Helper:ValidateMappings()
    local metricStartedAt = Performance and Performance.active and Performance:Begin()
    if not arenaEventsActive or not isInArenaInstance() then
        mappingComplete = false
        mappingDirty = false
        if metricStartedAt then Performance:Finish("mapping.validate", metricStartedAt) end
        return false
    end

    local expectedArenaCount = 0
    local mappedCount = 0
    local valid = true

    for arenaID = 1, 3 do
        local arenaUnit = "arena" .. arenaID
        local arenaExists = safeUnitExists(arenaUnit)
        local token = self.arenaToToken[arenaID]

        if arenaExists then
            expectedArenaCount = expectedArenaCount + 1
            if not token
                or self.tokenToArena[token] ~= arenaID
                or not safeUnitExists(token) then
                valid = false
            else
                local directPlate = safeCall(C_NamePlate.GetNamePlateForUnit, arenaUnit)
                local directToken = getValidatedTokenForUnitFromPlate(arenaUnit, directPlate)
                if directToken == token or safeUnitsMatch(arenaUnit, token) then
                    mappedCount = mappedCount + 1
                else
                    local arenaGUID = safeUnitGUID(arenaUnit)
                    local tokenGUID = safeUnitGUID(token)
                    if arenaGUID and tokenGUID and arenaGUID == tokenGUID then
                        mappedCount = mappedCount + 1
                    else
                        valid = false
                    end
                end
            end
        elseif token then
            valid = false
        end
    end

    if valid then
        for token, arenaID in pairs(self.tokenToArena) do
            if self.arenaToToken[arenaID] ~= token then
                valid = false
                break
            end
        end
    end

    mappingComplete = valid
        and expectedArenaCount > 0
        and mappedCount >= expectedArenaCount
    mappingDirty = not mappingComplete
    if metricStartedAt then Performance:Finish("mapping.validate", metricStartedAt) end
    return mappingComplete
end

function Helper:GetPlateFrameByToken(token)
    return self:GetPlateFrameByUnit(token)
end

function Helper:GetPlateFrameByUnit(unit)
    unit = asPublicString(unit)
    if not unit then
        return nil
    end

    local directPlate = safeCall(C_NamePlate.GetNamePlateForUnit, unit)
    if type(directPlate) == "table" then
        if unit:match("^arena%d+$") or isNameplateToken(unit) then
            if getValidatedTokenForUnitFromPlate(unit, directPlate) then
                return directPlate
            end
        else
            return directPlate
        end
    end

    local token = isNameplateToken(unit)
    if not token then
        return nil
    end

    local plates = getVisiblePlates()
    if not plates then
        return nil
    end

    for _, plate in ipairs(plates) do
        if getNameplateTokenFromPlate(plate) == token then
            return plate
        end
    end

    return nil
end

function Helper:GetPlateFrameByArenaID(arenaID)
    local arenaUnit = getArenaUnit(arenaID)
    if arenaUnit and safeUnitExists(arenaUnit) then
        local directPlate = self:GetPlateFrameByUnit(arenaUnit)
        if directPlate then
            return directPlate
        end
    end

    local token = self:GetArenaToken(arenaID)
    if not token then
        return nil
    end
    return self:GetPlateFrameByToken(token)
end

function Helper:GetAnchorParentByArenaID(arenaID)
    local arenaUnit = getArenaUnit(arenaID)
    if arenaUnit and safeUnitExists(arenaUnit) then
        local directParent = self:GetAnchorParentByUnit(arenaUnit)
        if directParent then
            return directParent
        end
    end

    local token = self:GetArenaToken(arenaID)
    if not token then
        return nil
    end

    return self:GetAnchorParentByUnit(token)
end

function Helper:GetAnchorParentByUnit(unit)
    local plate = self:GetPlateFrameByUnit(unit)
    if type(plate) ~= "table" then
        return nil
    end

    local token = isNameplateToken(unit)
    local resolvedToken, adapter = getNameplateTokenFromPlate(plate)
    token = token or resolvedToken
    local adapters = getNameplateAdapters()
    if adapters and type(adapters.ResolveAnchorParent) == "function" then
        local resolvedParent = safeCall(adapters.ResolveAnchorParent, adapters, plate, token, adapter)
        if type(resolvedParent) == "table" then
            return resolvedParent
        end
    end

    return getDefaultAnchorParentFromPlate(plate)
end

function Helper:GetVisibleEnemyNameplates()
    local results = {}
    local plates = getVisiblePlates()
    if not plates then
        return results
    end

    local seenTokens = {}
    local adapters = getNameplateAdapters()
    for _, plate in ipairs(plates) do
        local token, adapter = getNameplateTokenFromPlate(plate)
        if token and not seenTokens[token] and isAttackableNameplateToken(token) then
            local parent
            if adapters and type(adapters.ResolveAnchorParent) == "function" then
                parent = safeCall(adapters.ResolveAnchorParent, adapters, plate, token, adapter)
            end
            if type(parent) ~= "table" then
                parent = getDefaultAnchorParentFromPlate(plate)
            end

            if type(parent) == "table" then
                seenTokens[token] = true
                table.insert(results, {
                    token = token,
                    guid = safeUnitGUID(token),
                    name = safeUnitName(token),
                    plate = plate,
                    parent = parent,
                })
            end
        end
    end

    return results
end

function Helper:RegisterCallback(owner, func)
    if not owner or type(func) ~= "function" then
        return
    end
    self.callbacks[owner] = func
end

function Helper:UnregisterCallback(owner)
    self.callbacks[owner] = nil
end

function Helper:NotifyUpdated()
    for owner, func in pairs(self.callbacks) do
        local ok = pcall(func, owner, self)
        if not ok then
            -- ignore callback errors
        end
    end
end

function Helper:RefreshMappings()
    local metricStartedAt = Performance and Performance.active and Performance:Begin()
    if not isInArenaInstance() then
        local changed = next(self.arenaToToken) ~= nil
        if next(self.arenaToToken) ~= nil then
            self:ClearMappings()
            self:NotifyUpdated()
        end
        mappingComplete = false
        mappingDirty = false
        if metricStartedAt then Performance:Finish("mapping.full", metricStartedAt) end
        return changed, false
    end

    local plates = getVisiblePlates()
    if not plates then
        mappingComplete = false
        mappingDirty = true
        if metricStartedAt then Performance:Finish("mapping.full", metricStartedAt) end
        return false, false
    end

    wipe(scratchArenaGUIDByID)
    wipe(scratchArenaNameByID)
    wipe(scratchArenaClassByID)
    wipe(scratchArenaExistsByID)
    wipe(scratchEnemyTokenSet)
    wipe(scratchEnemyTokens)
    wipe(scratchClassByToken)
    wipe(scratchNewArenaToToken)
    wipe(scratchNewTokenToArena)
    RecycleScratchMap(scratchArenaIDsByName)
    RecycleScratchMap(scratchTokensByName)
    RecycleScratchMap(scratchArenaIDsByClass)
    RecycleScratchMap(scratchTokensByClass)
    wipe(scratchUnresolvedArenaIDs)
    wipe(scratchUnresolvedTokens)

    local arenaGUIDByID = scratchArenaGUIDByID
    local arenaNameByID = scratchArenaNameByID
    local arenaClassByID = scratchArenaClassByID
    local arenaExistsByID = scratchArenaExistsByID
    local expectedArenaCount = 0

    for arenaID = 1, 3 do
        local arenaUnit = "arena" .. arenaID
        if safeUnitExists(arenaUnit) then
            arenaExistsByID[arenaID] = true
            expectedArenaCount = expectedArenaCount + 1
            arenaGUIDByID[arenaID] = safeUnitGUID(arenaUnit)
            arenaNameByID[arenaID] = safeUnitName(arenaUnit)
            arenaClassByID[arenaID] = safeUnitClassToken(arenaUnit)
        end
    end

    local enemyTokenSet = scratchEnemyTokenSet
    local enemyTokens = scratchEnemyTokens
    local classByToken = scratchClassByToken

    for _, plate in ipairs(plates) do
        local token = getNameplateTokenFromPlate(plate)
        if token and isEnemyPlayerToken(token) then
            local classToken = safeUnitClassToken(token)
            enemyTokenSet[token] = true
            if classToken then
                classByToken[token] = classToken
            end
            table.insert(enemyTokens, token)
        end
    end

    local newArenaToToken = scratchNewArenaToToken
    local newTokenToArena = scratchNewTokenToArena

    -- Keep still valid cached mappings
    for arenaID, token in pairs(self.arenaToToken) do
        if arenaExistsByID[arenaID]
            and enemyTokenSet[token]
            and unitsShareIdentity("arena" .. arenaID, token) then
            newArenaToToken[arenaID] = token
            newTokenToArena[token] = arenaID
        end
    end

    -- Prefer the arena unit directly so the mapping survives token churn
    -- from temporary effects like vanish or feign death.
    for arenaID = 1, 3 do
        if not newArenaToToken[arenaID] then
            local arenaUnit = getArenaUnit(arenaID)
            if arenaUnit and safeUnitExists(arenaUnit) then
                local directPlate = self:GetPlateFrameByUnit(arenaUnit)
                local directToken = getValidatedTokenForUnitFromPlate(arenaUnit, directPlate)
                if directToken and enemyTokenSet[directToken] then
                    tryMap(newArenaToToken, newTokenToArena, arenaID, directToken)
                end
            end
        end
    end

    -- Midnight can protect UnitIsUnit, GUID, class, and name during arena
    -- combat. UnitIsProbablyUnit is Blizzard's public comparison fallback;
    -- compare the remaining visible enemy tokens before consulting identity
    -- values that may be secret.
    for arenaID = 1, 3 do
        if arenaExistsByID[arenaID] and not newArenaToToken[arenaID] then
            local arenaUnit = getArenaUnit(arenaID)
            for _, token in ipairs(enemyTokens) do
                if not newTokenToArena[token] and unitsShareIdentity(arenaUnit, token) then
                    tryMap(newArenaToToken, newTokenToArena, arenaID, token)
                    break
                end
            end
        end
    end

    -- Fast path fallback: GUID -> nameplate token
    for arenaID = 1, 3 do
        if not newArenaToToken[arenaID] then
            local guid = arenaGUIDByID[arenaID]
            if guid then
                local tokenFromGUID = isNameplateToken(asPublicString(safeCall(UnitTokenFromGUID, guid)))
                if tokenFromGUID and enemyTokenSet[tokenFromGUID] then
                    tryMap(newArenaToToken, newTokenToArena, arenaID, tokenFromGUID)
                end
            end
        end
    end

    local hasUnresolvedArena = false
    for arenaID = 1, 3 do
        if arenaExistsByID[arenaID] and not newArenaToToken[arenaID] then
            hasUnresolvedArena = true
            break
        end
    end

    -- Fallback: target / focus / mouseover bridge
    if hasUnresolvedArena then
        for _, refUnit in ipairs(REFERENCE_UNITS) do
            if safeUnitExists(refUnit) then
                local matchedToken = nil

                for _, token in ipairs(enemyTokens) do
                    if not newTokenToArena[token] and safeUnitsMatch(token, refUnit) then
                        matchedToken = token
                        break
                    end
                end

                if matchedToken then
                    for arenaID = 1, 3 do
                        local arenaUnit = "arena" .. arenaID
                        if arenaExistsByID[arenaID]
                            and not newArenaToToken[arenaID]
                            and safeUnitsMatch(refUnit, arenaUnit) then
                            tryMap(newArenaToToken, newTokenToArena, arenaID, matchedToken)
                            break
                        end
                    end
                end
            end
        end
    end

    -- Fallback: unique name
    local unresolvedArenaIDsByName = scratchArenaIDsByName
    local unresolvedTokensByName = scratchTokensByName

    for arenaID = 1, 3 do
        if not newArenaToToken[arenaID] then
            local name = arenaNameByID[arenaID]
            if name then
                unresolvedArenaIDsByName[name] = unresolvedArenaIDsByName[name] or AcquireScratchArray()
                table.insert(unresolvedArenaIDsByName[name], arenaID)
            end
        end
    end

    for _, token in ipairs(enemyTokens) do
        if not newTokenToArena[token] then
            local name = safeUnitName(token)
            if name then
                unresolvedTokensByName[name] = unresolvedTokensByName[name] or AcquireScratchArray()
                table.insert(unresolvedTokensByName[name], token)
            end
        end
    end

    for name, arenaIDs in pairs(unresolvedArenaIDsByName) do
        local tokens = unresolvedTokensByName[name]
        if type(arenaIDs) == "table" and #arenaIDs == 1 and type(tokens) == "table" and #tokens == 1 then
            tryMap(newArenaToToken, newTokenToArena, arenaIDs[1], tokens[1])
        end
    end

    -- Fallback: unique class
    local unresolvedArenaIDsByClass = scratchArenaIDsByClass
    local unresolvedTokensByClass = scratchTokensByClass

    for arenaID = 1, 3 do
        if not newArenaToToken[arenaID] then
            local classToken = arenaClassByID[arenaID]
            if classToken then
                unresolvedArenaIDsByClass[classToken] = unresolvedArenaIDsByClass[classToken] or AcquireScratchArray()
                table.insert(unresolvedArenaIDsByClass[classToken], arenaID)
            end
        end
    end

    for _, token in ipairs(enemyTokens) do
        if not newTokenToArena[token] then
            local classToken = classByToken[token] or safeUnitClassToken(token)
            if classToken then
                unresolvedTokensByClass[classToken] = unresolvedTokensByClass[classToken] or AcquireScratchArray()
                table.insert(unresolvedTokensByClass[classToken], token)
            end
        end
    end

    for classToken, arenaIDs in pairs(unresolvedArenaIDsByClass) do
        local tokens = unresolvedTokensByClass[classToken]
        if type(arenaIDs) == "table" and #arenaIDs == 1 and type(tokens) == "table" and #tokens == 1 then
            tryMap(newArenaToToken, newTokenToArena, arenaIDs[1], tokens[1])
        end
    end

    -- Last fallback: if only one arena slot and one token remain
    local unresolvedArenaIDs = scratchUnresolvedArenaIDs
    local unresolvedTokens = scratchUnresolvedTokens

    for arenaID = 1, 3 do
        if arenaClassByID[arenaID] and not newArenaToToken[arenaID] then
            table.insert(unresolvedArenaIDs, arenaID)
        end
    end

    for _, token in ipairs(enemyTokens) do
        if not newTokenToArena[token] then
            table.insert(unresolvedTokens, token)
        end
    end

    if #unresolvedArenaIDs == 1 and #unresolvedTokens == 1 then
        tryMap(newArenaToToken, newTokenToArena, unresolvedArenaIDs[1], unresolvedTokens[1])
    end

    local changed = mappingsDiffer(self.arenaToToken, newArenaToToken)
    if changed then
        wipe(self.arenaToToken)
        wipe(self.tokenToArena)

        for arenaID, token in pairs(newArenaToToken) do
            self.arenaToToken[arenaID] = token
        end
        for token, arenaID in pairs(newTokenToArena) do
            self.tokenToArena[token] = arenaID
        end

        self:NotifyUpdated()
    end

    local mappedCount = 0
    for _ in pairs(newArenaToToken) do
        mappedCount = mappedCount + 1
    end

    local complete = expectedArenaCount > 0 and mappedCount >= expectedArenaCount
    mappingComplete = complete
    mappingDirty = not complete
    if metricStartedAt then Performance:Finish("mapping.full", metricStartedAt) end
    return changed, complete
end

local function CancelTimer(timer)
    if timer and type(timer.Cancel) == "function" then
        timer:Cancel()
    end
end

local function CancelPendingRefreshes()
    CancelTimer(refreshTimer)
    CancelTimer(burstTimer)
    refreshTimer = nil
    burstTimer = nil
    burstRetryIndex = 0
    refreshNeedsFullScan = false
end

local function ScheduleNextBurstRetry()
    if not arenaEventsActive then
        return
    end

    local targetDelay = burstRefreshDelays[burstRetryIndex]
    if not targetDelay then
        return
    end

    local previousDelay = burstRefreshDelays[burstRetryIndex - 1] or 0
    burstRetryIndex = burstRetryIndex + 1
    if Performance and Performance.active then Performance:Count("mapping.burstRetries") end
    burstTimer = C_Timer.NewTimer(math.max(targetDelay - previousDelay, 0), function()
        burstTimer = nil
        local _, complete = Helper:RefreshMappings()
        if not complete then
            ScheduleNextBurstRetry()
        else
            burstRetryIndex = 0
        end
    end)
end

function Helper:SetArenaActive(active)
    active = active == true
    if arenaEventsActive == active then
        return
    end

    arenaEventsActive = active
    if active then
        mappingComplete = false
        mappingDirty = true
    end
    for _, event in ipairs(ACTIVE_EVENTS) do
        if active then
            self:RegisterEvent(event)
        else
            self:UnregisterEvent(event)
        end
    end

    if not active then
        CancelPendingRefreshes()
        if next(self.arenaToToken) ~= nil then
            self:ClearMappings()
            self:NotifyUpdated()
        end
        mappingComplete = false
        mappingDirty = false
    end
end

function Helper:UpdateArenaActivity()
    self:SetArenaActive(isInArenaInstance())
    return arenaEventsActive
end

function Helper:IsArenaActive()
    return arenaEventsActive
end

local function RunFullRefreshWithRetries()
    burstRetryIndex = 1
    local _, complete = Helper:RefreshMappings()
    if not complete then
        ScheduleNextBurstRetry()
    else
        burstRetryIndex = 0
    end
end

local function QueueDeferredRefresh(fullScan)
    if not arenaEventsActive then
        return
    end

    if burstTimer then
        if Performance and Performance.active then Performance:Count("mapping.coalesced") end
        return
    end

    if fullScan then
        mappingComplete = false
        mappingDirty = true
        refreshNeedsFullScan = true
    end

    if refreshTimer then
        if Performance and Performance.active then Performance:Count("mapping.coalesced") end
        return
    end

    refreshTimer = C_Timer.NewTimer(0, function()
        refreshTimer = nil
        local needsFullScan = refreshNeedsFullScan or mappingDirty
        refreshNeedsFullScan = false

        if needsFullScan then
            RunFullRefreshWithRetries()
            return
        end

        if not Helper:ValidateMappings() then
            RunFullRefreshWithRetries()
        end
    end)
end

function Helper:QueueRefresh()
    QueueDeferredRefresh(false)
end

function Helper:QueueBurstRefresh()
    if not arenaEventsActive and not self:UpdateArenaActivity() then
        return
    end

    QueueDeferredRefresh(true)
end

function Helper:OnEvent(event, unitToken)
    if event == "PLAYER_LEAVING_WORLD" then
        self:SetArenaActive(false)
        return
    end

    if event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "PVP_MATCH_STATE_CHANGED"
        or event == "ARENA_OPPONENT_UPDATE"
        or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        if self:UpdateArenaActivity() then
            self:QueueBurstRefresh()
        end
        return
    end

    if not arenaEventsActive then
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" or event == "FORBIDDEN_NAME_PLATE_UNIT_REMOVED" then
        unitToken = isNameplateToken(unitToken)
        if unitToken then
            local arenaID = self.tokenToArena[unitToken]
            if arenaID then
                mappingComplete = false
                mappingDirty = true
                self:QueueBurstRefresh()
            end
        end
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED"
        or event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then
        if self:IsMappingComplete() then
            self:QueueRefresh()
        else
            self:QueueBurstRefresh()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if not self:IsMappingComplete() then
            self:QueueBurstRefresh()
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_FOCUS_CHANGED"
        or event == "UPDATE_MOUSEOVER_UNIT" then
        if not self:IsMappingComplete() then
            self:QueueRefresh()
        end
        return
    end
end

Helper:SetScript("OnEvent", function(self, event, ...)
    self:OnEvent(event, ...)
end)

Helper:RegisterEvent("PLAYER_ENTERING_WORLD")
Helper:RegisterEvent("PLAYER_LEAVING_WORLD")
Helper:RegisterEvent("ZONE_CHANGED_NEW_AREA")
Helper:RegisterEvent("ARENA_OPPONENT_UPDATE")
Helper:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
Helper:RegisterEvent("PVP_MATCH_STATE_CHANGED")
