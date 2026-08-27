local _, ns = ...
ns = ns or {}

local Registry = ns.NameplateAdapters
if not Registry then
    return
end

Registry:RegisterAdapter({
    id = "Blizzard",
    priority = 0,
    GetTokenFromPlate = function(_, plate)
        return Registry.GetDefaultTokenFromPlate(plate)
    end,
    MatchesPlate = function()
        return true
    end,
    GetAnchorParent = function(_, plate)
        return Registry.GetDefaultAnchorParent(plate)
    end,
})
