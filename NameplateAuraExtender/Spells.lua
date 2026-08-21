local addonName, ns = ...

-- Add any harmful aura spell ID here to show it on enemy-player nameplates.
-- The addon shows these regardless of which player applied them.
--
-- Format:
--     [123456] = true, -- Spell Name
--
-- Starter set: common player-applied movement snares.
ns.TRACKED_SPELLS = {
    [116] = true,       -- Frostbolt
    [1715] = true,      -- Hamstring
    [3409] = true,      -- Crippling Poison
    [3600] = true,      -- Earthbind
    [5116] = true,      -- Concussive Shot
    [12323] = true,     -- Piercing Howl
    [15407] = true,     -- Mind Flay
    [31589] = true,     -- Slow
    [45524] = true,     -- Chains of Ice
    [58180] = true,     -- Infected Wounds
    [61391] = true,     -- Typhoon
    [116095] = true,    -- Disable
    [127797] = true,    -- Ursol's Vortex
    [135299] = true,    -- Tar Trap
    [157981] = true,    -- Blast Wave
    [183218] = true,    -- Hand of Hindrance
    [195645] = true,    -- Wing Clip
    [196840] = true,    -- Frost Shock
    [204843] = true,    -- Sigil of Chains
    [205021] = true,    -- Ray of Frost
}
