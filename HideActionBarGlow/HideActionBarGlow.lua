local addon = CreateFrame("Frame")
local hooked = false

local function HideExistingAlerts()
    local manager = ActionButtonSpellAlertManager
    if not manager or not manager.HideAlert or not manager.activeAlerts then
        return
    end

    -- Copy the buttons first because HideAlert removes entries from activeAlerts.
    local buttons = {}
    for button in pairs(manager.activeAlerts) do
        buttons[#buttons + 1] = button
    end

    for _, button in ipairs(buttons) do
        manager:HideAlert(button)
    end
end

local function InstallHook()
    if hooked then
        return true
    end

    local manager = ActionButtonSpellAlertManager
    if not manager or not manager.ShowAlert or not manager.HideAlert then
        return false
    end

    -- Blizzard calls ShowAlert whenever a spell activation/proc glow should
    -- appear. Hide it immediately after Blizzard's call completes.
    hooksecurefunc(manager, "ShowAlert", function(self, actionButton)
        self:HideAlert(actionButton)
    end)

    hooked = true
    HideExistingAlerts()
    return true
end

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")

addon:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "PLAYER_LOGIN"
        or (event == "ADDON_LOADED" and loadedAddon == "Blizzard_ActionBar") then

        if InstallHook() then
            self:UnregisterEvent("ADDON_LOADED")
            self:UnregisterEvent("PLAYER_LOGIN")
        end
    end
end)
