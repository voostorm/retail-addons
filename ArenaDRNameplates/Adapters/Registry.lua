local _, ns = ...
ns = ns or {}

local Registry = {}
ns.NameplateAdapters = Registry

Registry.adapters = {}
Registry.adaptersByID = {}
Registry.layoutAdapters = {}
Registry.availabilityCache = {}
Registry.plateAdapterCache = setmetatable({}, { __mode = "k" })

local function isSecretValue(value)
    if type(issecretvalue) ~= "function" then
        return false
    end

    local ok, result = pcall(issecretvalue, value)
    return ok and result == true
end

local function asPublicString(value)
    if type(value) ~= "string" or isSecretValue(value) then
        return nil
    end
    return value
end

local function isNameplateToken(token)
    token = asPublicString(token)
    if not token then
        return nil
    end

    if token:match("^nameplate%d+$") then
        return token
    end

    return nil
end

local function isFrame(frame)
    return type(frame) == "table" and type(frame.GetObjectType) == "function"
end

local function safeCall(func, ...)
    if type(func) ~= "function" then
        return nil, nil, nil
    end

    local ok, a, b, c = pcall(func, ...)
    if not ok then
        return nil, nil, nil
    end

    return a, b, c
end

local function safeBooleanCall(func, defaultValue, ...)
    if type(func) ~= "function" then
        return defaultValue
    end

    local ok, result = pcall(func, ...)
    if not ok or isSecretValue(result) then
        return defaultValue
    end

    return result == true
end

local function isAdapterAvailable(adapter)
    if type(adapter) ~= "table" then
        return false
    end

    local cached = Registry.availabilityCache[adapter]
    if cached ~= nil then
        return cached
    end

    local available = type(adapter.IsAvailable) ~= "function"
        or safeBooleanCall(adapter.IsAvailable, false, adapter)
    Registry.availabilityCache[adapter] = available
    return available
end

local function getAdapterFromHint(hint)
    if type(hint) == "table" then
        return hint
    end
    if type(hint) == "string" then
        return Registry.adaptersByID[hint]
    end
    return nil
end

local function adapterMatchesPlate(adapter, plate, token)
    if not adapter or not isAdapterAvailable(adapter) then
        return false
    end

    return safeBooleanCall(adapter.MatchesPlate, true, adapter, plate, token)
end

local function getTokenFromUnitFrame(frame)
    if not isFrame(frame) then
        return nil
    end

    return isNameplateToken(frame.unit)
        or isNameplateToken(frame.displayedUnit)
end

local function getDefaultTokenFromPlate(plate)
    if not isFrame(plate) then
        return nil
    end

    if isNameplateToken(plate.namePlateUnitToken) then
        return isNameplateToken(plate.namePlateUnitToken)
    end

    if isFrame(plate.UnitFrame) then
        local token = getTokenFromUnitFrame(plate.UnitFrame)
        if token then
            return token
        end
    end

    if isFrame(plate.unitFrame) then
        local token = isNameplateToken(plate.unitFrame.namePlateUnitToken)
            or getTokenFromUnitFrame(plate.unitFrame)
        if token then
            return token
        end
    end

    return nil
end

local function getDefaultAnchorParent(plate)
    if not isFrame(plate) then
        return nil
    end

    local unitFrame = nil
    if isFrame(plate.UnitFrame) then
        unitFrame = plate.UnitFrame
    elseif isFrame(plate.unitFrame) then
        unitFrame = plate.unitFrame
    end

    if unitFrame then
        for _, key in ipairs({
            "HealthBarsContainer",
            "healthBarsContainer",
            "healthBar",
            "HealthBar",
        }) do
            if isFrame(unitFrame[key]) then
                return unitFrame[key]
            end
        end

        return unitFrame
    end

    return plate
end

function Registry:RegisterAdapter(adapter)
    if type(adapter) ~= "table" or type(adapter.id) ~= "string" or adapter.id == "" then
        return
    end

    adapter.priority = tonumber(adapter.priority) or 0
    table.insert(self.adapters, adapter)
    self.adaptersByID[adapter.id] = adapter
    if type(adapter.GetLayoutAnchor) == "function" then
        table.insert(self.layoutAdapters, adapter)
    end
    table.sort(self.adapters, function(a, b)
        if a.priority == b.priority then
            return a.id < b.id
        end
        return a.priority > b.priority
    end)
    table.sort(self.layoutAdapters, function(a, b)
        if a.priority == b.priority then
            return a.id < b.id
        end
        return a.priority > b.priority
    end)
    self:InvalidateAvailabilityCache()
end

function Registry:ResolveTokenForPlate(plate)
    local cachedAdapter = self.plateAdapterCache[plate]
    if cachedAdapter and isAdapterAvailable(cachedAdapter) then
        local token = isNameplateToken(safeCall(cachedAdapter.GetTokenFromPlate, cachedAdapter, plate))
        if token then
            return token, cachedAdapter.id, cachedAdapter
        end
        self.plateAdapterCache[plate] = nil
    end

    for _, adapter in ipairs(self.adapters) do
        if adapter ~= cachedAdapter and isAdapterAvailable(adapter) then
            local token = isNameplateToken(safeCall(adapter.GetTokenFromPlate, adapter, plate))
            if token then
                self.plateAdapterCache[plate] = adapter
                return token, adapter.id, adapter
            end
        end
    end

    return nil, nil
end

function Registry:ResolveAnchorParent(plate, token, adapterHint)
    token = isNameplateToken(token)
    local preferredAdapter = getAdapterFromHint(adapterHint) or self.plateAdapterCache[plate]

    if adapterMatchesPlate(preferredAdapter, plate, token) then
        local parent = safeCall(preferredAdapter.GetAnchorParent, preferredAdapter, plate, token)
        if isFrame(parent) then
            self.plateAdapterCache[plate] = preferredAdapter
            return parent, preferredAdapter.id, preferredAdapter
        end
    end

    for _, adapter in ipairs(self.adapters) do
        if adapter ~= preferredAdapter and adapterMatchesPlate(adapter, plate, token) then
            local parent = safeCall(adapter.GetAnchorParent, adapter, plate, token)
            if isFrame(parent) then
                self.plateAdapterCache[plate] = adapter
                return parent, adapter.id, adapter
            end
        end
    end

    return nil, nil
end

function Registry:ResolveLayoutAnchor(parent, context)
    if not isFrame(parent) or type(context) ~= "table" then
        return nil, nil
    end

    for _, adapter in ipairs(self.layoutAdapters) do
        if isAdapterAvailable(adapter) then
            local relativeFrame = safeCall(adapter.GetLayoutAnchor, adapter, parent, context)
            if isFrame(relativeFrame) then
                return relativeFrame, adapter.id
            end
        end
    end

    return nil, nil
end

function Registry:InvalidateAvailabilityCache()
    self.availabilityCache = {}
    self.plateAdapterCache = setmetatable({}, { __mode = "k" })
end

function Registry:RefreshAvailability()
    self:InvalidateAvailabilityCache()
    for _, adapter in ipairs(self.adapters) do
        isAdapterAvailable(adapter)
    end
end

function Registry:IsAddOnLoaded(...)
    if not C_AddOns or type(C_AddOns.IsAddOnLoaded) ~= "function" then
        return false
    end

    for index = 1, select("#", ...) do
        local addonName = select(index, ...)
        if type(addonName) == "string" and addonName ~= "" then
            if safeCall(C_AddOns.IsAddOnLoaded, addonName) == true then
                return true
            end
        end
    end

    return false
end

Registry.AsPublicString = asPublicString
Registry.IsNameplateToken = isNameplateToken
Registry.IsFrame = isFrame
Registry.SafeCall = safeCall
Registry.SafeBooleanCall = safeBooleanCall
Registry.GetDefaultTokenFromPlate = getDefaultTokenFromPlate
Registry.GetDefaultAnchorParent = getDefaultAnchorParent
