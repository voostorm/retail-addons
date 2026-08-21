local addon = CreateFrame("Frame")

-- Normal CVars: exact values to enforce.
local CVARS = {
    nameplateShowEnemies = "1",
    WorldTextScale_v2 = "1.5",
}

-- Bitfield CVars: each listed index must remain enabled.
-- Enemy NPC Buffs/Debuffs:
--   1 = Mob Buffs
--   2 = Personal Debuffs
--   3 = Shared CC
-- Enemy Player Buffs/Debuffs:
--   1 = Enemy Buffs
--   2 = Personal Debuffs
--   3 = Big Debuff / Loss of Control
local BITFIELD_CVARS = {
    nameplateEnemyNpcAuraDisplay = { 1, 2, 3 },
    nameplateEnemyPlayerAuraDisplay = { 1, 2, 3 },
}

local function ApplyCVar(cvar, desiredValue)
    local currentValue = C_CVar.GetCVar(cvar)
    if currentValue ~= desiredValue then
        C_CVar.SetCVar(cvar, desiredValue)
    end
end

local function ApplyBitfieldCVar(cvar, enabledIndices)
    for _, index in ipairs(enabledIndices) do
        if not C_CVar.GetCVarBitfield(cvar, index) then
            C_CVar.SetCVarBitfield(cvar, index, true)
        end
    end
end

local function ApplyAll()
    for cvar, desiredValue in pairs(CVARS) do
        ApplyCVar(cvar, desiredValue)
    end

    for cvar, enabledIndices in pairs(BITFIELD_CVARS) do
        ApplyBitfieldCVar(cvar, enabledIndices)
    end
end

local function FindManagedCVar(changedCVar)
    if not changedCVar then
        return nil, nil
    end

    local changedLower = string.lower(changedCVar)

    for cvar in pairs(CVARS) do
        if string.lower(cvar) == changedLower then
            return "normal", cvar
        end
    end

    for cvar in pairs(BITFIELD_CVARS) do
        if string.lower(cvar) == changedLower then
            return "bitfield", cvar
        end
    end

    return nil, nil
end

local function ReapplyManagedCVar(kind, cvar)
    if kind == "normal" then
        ApplyCVar(cvar, CVARS[cvar])
    elseif kind == "bitfield" then
        ApplyBitfieldCVar(cvar, BITFIELD_CVARS[cvar])
    end
end

addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("CVAR_UPDATE")

addon:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Preserve the old Hide UI Errors addon behavior.
        if UIErrorsFrame then
            UIErrorsFrame:Hide()
        end

        ApplyAll()

        -- Some Blizzard settings are initialized after PLAYER_LOGIN.
        C_Timer.After(1, ApplyAll)

    elseif event == "PLAYER_ENTERING_WORLD" then
        ApplyAll()

    elseif event == "CVAR_UPDATE" then
        local changedCVar = ...
        local kind, managedCVar = FindManagedCVar(changedCVar)

        if managedCVar then
            -- Let Blizzard's current CVar write finish, then enforce ours.
            C_Timer.After(0, function()
                ReapplyManagedCVar(kind, managedCVar)
            end)
        end
    end
end)
