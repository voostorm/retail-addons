local addon = CreateFrame("Frame")
local nameplateAuraMirrorHookInstalled = false

-- Normal CVars: exact values to enforce.
local CVARS = {
    nameplateShowEnemies = "1",
    WorldTextScale_v2 = "1.5",
}

-- Bitfield settings: only these individual checkboxes are forced on.
-- Other checkboxes in the same setting are left untouched.
local BITFIELDS = {
    nameplateEnemyNpcAuraDisplay = {
        Enum.NamePlateEnemyNpcAuraDisplay.CrowdControl, -- Shared CC
    },
    nameplateEnemyPlayerAuraDisplay = {
        Enum.NamePlateEnemyPlayerAuraDisplay.LossOfControl, -- Big Debuff
    },
}

local function ApplyCVar(cvar, desiredValue)
    local currentValue = C_CVar.GetCVar(cvar)
    if currentValue ~= desiredValue then
        C_CVar.SetCVar(cvar, desiredValue)
    end
end

local function ApplyBitfield(cvar, bitfieldFlag)
    if not GetCVarBitfield(cvar, bitfieldFlag) then
        SetCVarBitfield(cvar, bitfieldFlag, true)
    end
end

local function ApplyAll()
    for cvar, desiredValue in pairs(CVARS) do
        ApplyCVar(cvar, desiredValue)
    end

    for cvar, bitfieldFlags in pairs(BITFIELDS) do
        for _, bitfieldFlag in ipairs(bitfieldFlags) do
            ApplyBitfield(cvar, bitfieldFlag)
        end
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

    for cvar in pairs(BITFIELDS) do
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
        for _, bitfieldFlag in ipairs(BITFIELDS[cvar]) do
            ApplyBitfield(cvar, bitfieldFlag)
        end
    end
end

local function InstallEnemyPlayerSharedCCHook()
    if nameplateAuraMirrorHookInstalled then
        return true
    end

    if not NamePlateAurasMixin or not NamePlateAurasMixin.UpdateEnemyPlayerAuraFrames then
        return false
    end

    -- Blizzard's Enemy Player "Big Debuff" option normally shows the single
    -- LossOfControlFrame and explicitly hides CrowdControlListFrame.
    --
    -- Mirror Enemy NPC "Shared CC" behavior instead: when Big Debuff is
    -- enabled, show Blizzard's existing CrowdControlListFrame on enemy
    -- player nameplates and hide the LossOfControlFrame.
    hooksecurefunc(NamePlateAurasMixin, "UpdateEnemyPlayerAuraFrames", function(self)
        local bigDebuffEnabled = GetCVarBitfield(
            "nameplateEnemyPlayerAuraDisplay",
            Enum.NamePlateEnemyPlayerAuraDisplay.LossOfControl
        )

        self.CrowdControlListFrame:SetShown(bigDebuffEnabled)
        self.LossOfControlFrame:SetShown(false)
    end)

    nameplateAuraMirrorHookInstalled = true
    return true
end

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("CVAR_UPDATE")

addon:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "Blizzard_NamePlates" then
            InstallEnemyPlayerSharedCCHook()
        end

    elseif event == "PLAYER_LOGIN" then
        -- Blizzard_NamePlates may already be loaded before CVarEnabler.
        InstallEnemyPlayerSharedCCHook()
        -- Preserve the old Hide UI Errors addon behavior.
        if UIErrorsFrame then
            UIErrorsFrame:Hide()
        end

        -- Mark Blizzard's "click a quest to focus it" super-track tutorial as seen
        -- so the help tip does not appear again.
        SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_HOW_TO_SUPERTRACK, true)

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
