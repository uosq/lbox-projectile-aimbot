--[[
    This is a port of the GetProjectileInformation function
    from GoodEvening's Visualize Arc Trajectories

    His Github: https://github.com/GoodEveningFellOff
    Source: https://github.com/GoodEveningFellOff/Lmaobox-Scripts/blob/main/Visualize%20Arc%20Trajectories/dev.lua
--]]

local TRACE_HULL = engine.TraceHull
local CLAMP = function(a, b, c)
    return (a < b) and b or (a > c) and c or a
end
local VEC_ROT = function(a, b)
    return (b:Forward() * a.x) + (b:Right() * a.y) + (b:Up() * a.z)
end

local aProjectileInfo = {}
local aItemDefinitions = {}

local PROJECTILE_TYPE_BASIC = 0
local PROJECTILE_TYPE_PSEUDO = 1
local PROJECTILE_TYPE_SIMUL = 2

local COLLISION_NORMAL = 0
local COLLISION_HEAL_TEAMMATES = 1
local COLLISION_HEAL_BUILDINGS = 2
local COLLISION_HEAL_HURT = 3
local COLLISION_NONE = 4

local function AppendItemDefinitions(iType, ...)
    for _, i in pairs({ ... }) do
        aItemDefinitions[i] = iType
    end
end

---@return WeaponInfo
function GetProjectileInformation(itemDefinitionIndex)
    return aProjectileInfo[aItemDefinitions[itemDefinitionIndex or 0]]
end

---@return WeaponInfo?
local function DefineProjectileDefinition(tbl)
    return {
        m_iType = PROJECTILE_TYPE_BASIC,
        m_vecOffset = tbl.vecOffset or Vector3(0, 0, 0),
        m_vecAbsoluteOffset = tbl.vecAbsoluteOffset or Vector3(0, 0, 0),
        m_vecAngleOffset = tbl.vecAngleOffset or Vector3(0, 0, 0),
        m_vecVelocity = tbl.vecVelocity or Vector3(0, 0, 0),
        m_vecAngularVelocity = tbl.vecAngularVelocity or Vector3(0, 0, 0),
        m_vecMins = tbl.vecMins or (not tbl.vecMaxs) and Vector3(0, 0, 0) or -tbl.vecMaxs,
        m_vecMaxs = tbl.vecMaxs or (not tbl.vecMins) and Vector3(0, 0, 0) or -tbl.vecMins,
        m_flGravity = tbl.flGravity or 0.001,
        m_flDrag = tbl.flDrag or 0,
        m_flElasticity = tbl.flElasticity or 0,
        m_iAlignDistance = tbl.iAlignDistance or 0,
        m_iTraceMask = tbl.iTraceMask or 33570827, -- MASK_SOLID
        m_iCollisionType = tbl.iCollisionType or COLLISION_NORMAL,
        m_flCollideWithTeammatesDelay = tbl.flCollideWithTeammatesDelay or 0.25,
        m_flLifetime = tbl.flLifetime or 99999,
        m_flDamageRadius = tbl.flDamageRadius or 0,
        m_bStopOnHittingEnemy = tbl.bStopOnHittingEnemy ~= false,
        m_bCharges = tbl.bCharges or false,
        m_sModelName = tbl.sModelName or "",
        m_bHasGravity = tbl.bGravity == nil and true or tbl.bGravity,

        GetOffset = not tbl.GetOffset
            and function(self, bDucking, bIsFlipped)
                return bIsFlipped and Vector3(self.m_vecOffset.x, -self.m_vecOffset.y, self.m_vecOffset.z)
                    or self.m_vecOffset
            end
            or tbl.GetOffset, -- self, bDucking, bIsFlipped

        GetAngleOffset = (not tbl.GetAngleOffset) and function(self, flChargeBeginTime)
            return self.m_vecAngleOffset
        end or tbl.GetAngleOffset, -- self, flChargeBeginTime

        GetFirePosition = tbl.GetFirePosition or function(self, pLocalPlayer, vecLocalView, vecViewAngles, bIsFlipped)
            local resultTrace = TRACE_HULL(
                vecLocalView,
                vecLocalView
                + VEC_ROT(
                    self:GetOffset((pLocalPlayer:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0, bIsFlipped),
                    vecViewAngles
                ),
                -Vector3(8, 8, 8),
                Vector3(8, 8, 8),
                MASK_SHOT_HULL
            ) -- MASK_SHOT_HULL

            return (not resultTrace.startsolid) and resultTrace.endpos or nil
        end,

        GetVelocity = (not tbl.GetVelocity) and function(self, ...)
            return self.m_vecVelocity
        end or tbl.GetVelocity, -- self, flChargeBeginTime

        GetAngularVelocity = (not tbl.GetAngularVelocity) and function(self, ...)
            return self.m_vecAngularVelocity
        end or tbl.GetAngularVelocity, -- self, flChargeBeginTime

        GetGravity = (not tbl.GetGravity) and function(self, ...)
            return self.m_flGravity
        end or tbl.GetGravity, -- self, flChargeBeginTime

        GetLifetime = (not tbl.GetLifetime) and function(self, ...)
            return self.m_flLifetime
        end or tbl.GetLifetime, -- self, flChargeBeginTime

        HasGravity = (not tbl.HasGravity) and function(self, ...)
            return self.m_bHasGravity
        end or tbl.HasGravity,
    }
end

local function DefineBasicProjectileDefinition(tbl)
    local stReturned = DefineProjectileDefinition(tbl)
    stReturned.m_iType = PROJECTILE_TYPE_BASIC

    return stReturned
end

local function DefinePseudoProjectileDefinition(tbl)
    local stReturned = DefineProjectileDefinition(tbl)
    stReturned.m_iType = PROJECTILE_TYPE_PSEUDO

    return stReturned
end

local function DefineSimulProjectileDefinition(tbl)
    local stReturned = DefineProjectileDefinition(tbl)
    stReturned.m_iType = PROJECTILE_TYPE_SIMUL

    return stReturned
end

local function DefineDerivedProjectileDefinition(def, tbl)
    local stReturned = {}
    for k, v in pairs(def) do
        stReturned[k] = v
    end
    for k, v in pairs(tbl) do
        stReturned[((type(v) ~= "function") and "m_" or "") .. k] = v
    end

    if not tbl.GetOffset and tbl.vecOffset then
        stReturned.GetOffset = function(self, bDucking, bIsFlipped)
            return bIsFlipped and Vector3(self.m_vecOffset.x, -self.m_vecOffset.y, self.m_vecOffset.z)
                or self.m_vecOffset
        end
    end

    if not tbl.GetAngleOffset and tbl.vecAngleOffset then
        stReturned.GetAngleOffset = function(self, flChargeBeginTime)
            return self.m_vecAngleOffset
        end
    end

    if not tbl.GetVelocity and tbl.vecVelocity then
        stReturned.GetVelocity = function(self, ...)
            return self.m_vecVelocity
        end
    end

    if not tbl.GetAngularVelocity and tbl.vecAngularVelocity then
        stReturned.GetAngularVelocity = function(self, ...)
            return self.m_vecAngularVelocity
        end
    end

    if not tbl.GetGravity and tbl.flGravity then
        stReturned.GetGravity = function(self, ...)
            return self.m_flGravity
        end
    end

    if not tbl.GetLifetime and tbl.flLifetime then
        stReturned.GetLifetime = function(self, ...)
            return self.m_flLifetime
        end
    end

    return stReturned
end

AppendItemDefinitions(
    1,
    18,    -- Rocket Launcher
    205,   -- Rocket Launcher (Renamed/Strange)
    228,   -- The Black Box
    658,   -- Festive Rocket Launcher
    800,   -- Silver Botkiller Rocket Launcher Mk.I
    809,   -- Gold Botkiller Rocket Launcher Mk.I
    889,   -- Rust Botkiller Rocket Launcher Mk.I
    898,   -- Blood Botkiller Rocket Launcher Mk.I
    907,   -- Carbonado Botkiller Rocket Launcher Mk.I
    916,   -- Diamond Botkiller Rocket Launcher Mk.I
    965,   -- Silver Botkiller Rocket Launcher Mk.II
    974,   -- Gold Botkiller Rocket Launcher Mk.II
    1085,  -- Festive Black Box
    15006, -- Woodland Warrior
    15014, -- Sand Cannon
    15028, -- American Pastoral
    15043, -- Smalltown Bringdown
    15052, -- Shell Shocker
    15057, -- Aqua Marine
    15081, -- Autumn
    15104, -- Blue Mew
    15105, -- Brain Candy
    15129, -- Coffin Nail
    15130, -- High Roller's
    15150  -- Warhawk
)
aProjectileInfo[1] = DefineBasicProjectileDefinition({
    vecVelocity = Vector3(1100, 0, 0),
    vecMaxs = Vector3(0, 0, 0),
    iAlignDistance = 2000,
    flDamageRadius = 146,
    bGravity = false,

    GetOffset = function(self, bDucking, bIsFlipped)
        return Vector3(23.5, 12 * (bIsFlipped and -1 or 1), bDucking and 8 or -3)
    end,
})

AppendItemDefinitions(
    2,
    237 -- Rocket Jumper
)
aProjectileInfo[2] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
    iCollisionType = COLLISION_NONE,
    bGravity = false,
})

AppendItemDefinitions(
    3,
    730 -- The Beggar's Bazooka
)
aProjectileInfo[3] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
    flDamageRadius = 116.8,
    bGravity = false,
})

AppendItemDefinitions(
    4,
    1104 -- The Air Strike
)
aProjectileInfo[4] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
    flDamageRadius = 131.4,
})

AppendItemDefinitions(
    5,
    127 -- The Direct Hit
)
aProjectileInfo[5] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
    vecVelocity = Vector3(2000, 0, 0),
    flDamageRadius = 44,
    bGravity = false,
})

AppendItemDefinitions(
    6,
    414 -- The Liberty Launcher
)
aProjectileInfo[6] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
    vecVelocity = Vector3(1550, 0, 0),
    bGravity = false,
})

AppendItemDefinitions(
    7,
    513 -- The Original
)
aProjectileInfo[7] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
    bGravity = false,
    GetOffset = function(self, bDucking)
        return Vector3(23.5, 0, bDucking and 8 or -3)
    end,
})

-- https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/tf/tf_weapon_dragons_fury.cpp
AppendItemDefinitions(
    8,
    1178 -- Dragon's Fury
)
aProjectileInfo[8] = DefineBasicProjectileDefinition({
    vecVelocity = Vector3(600, 0, 0),
    vecMaxs = Vector3(1, 1, 1),
    bGravity = false,

    GetOffset = function(self, bDucking, bIsFlipped)
        return Vector3(3, 7, -9)
    end,
})

AppendItemDefinitions(
    9,
    442 -- The Righteous Bison
)
aProjectileInfo[9] = DefineBasicProjectileDefinition({
    vecVelocity = Vector3(1200, 0, 0),
    vecMaxs = Vector3(1, 1, 1),
    iAlignDistance = 2000,
    bGravity = false,

    GetOffset = function(self, bDucking, bIsFlipped)
        return Vector3(23.5, -8 * (bIsFlipped and -1 or 1), bDucking and 8 or -3)
    end,
})

AppendItemDefinitions(
    10,
    20,    -- Stickybomb Launcher
    207,   -- Stickybomb Launcher (Renamed/Strange)
    661,   -- Festive Stickybomb Launcher
    797,   -- Silver Botkiller Stickybomb Launcher Mk.I
    806,   -- Gold Botkiller Stickybomb Launcher Mk.I
    886,   -- Rust Botkiller Stickybomb Launcher Mk.I
    895,   -- Blood Botkiller Stickybomb Launcher Mk.I
    904,   -- Carbonado Botkiller Stickybomb Launcher Mk.I
    913,   -- Diamond Botkiller Stickybomb Launcher Mk.I
    962,   -- Silver Botkiller Stickybomb Launcher Mk.II
    971,   -- Gold Botkiller Stickybomb Launcher Mk.II
    15009, -- Sudden Flurry
    15012, -- Carpet Bomber
    15024, -- Blasted Bombardier
    15038, -- Rooftop Wrangler
    15045, -- Liquid Asset
    15048, -- Pink Elephant
    15082, -- Autumn
    15083, -- Pumpkin Patch
    15084, -- Macabre Web
    15113, -- Sweet Dreams
    15137, -- Coffin Nail
    15138, -- Dressed to Kill
    15155  -- Blitzkrieg
)
aProjectileInfo[10] = DefineSimulProjectileDefinition({
    vecOffset = Vector3(16, 8, -6),
    vecAngularVelocity = Vector3(600, 0, 0),
    vecMaxs = Vector3(3.5, 3.5, 3.5),
    bCharges = true,
    flDamageRadius = 150,
    sModelName = "models/weapons/w_models/w_stickybomb.mdl",
    flGravity = 0.25,

    GetVelocity = function(self, flChargeBeginTime)
        return Vector3(900 + CLAMP(flChargeBeginTime / 4, 0, 1) * 1500, 0, 200)
    end,
})

AppendItemDefinitions(
    11,
    1150 -- The Quickiebomb Launcher
)
aProjectileInfo[11] = DefineDerivedProjectileDefinition(aProjectileInfo[10], {
    sModelName = "models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl",
    flGravity = 0.25,
    GetVelocity = function(self, flChargeBeginTime)
        return Vector3(900 + CLAMP(flChargeBeginTime / 1.2, 0, 1) * 1500, 0, 200)
    end,
})

AppendItemDefinitions(
    12,
    130 -- The Scottish Resistance
)
aProjectileInfo[12] = DefineDerivedProjectileDefinition(aProjectileInfo[10], {
    sModelName = "models/weapons/w_models/w_stickybomb_d.mdl",
    flGravity = 0.25,
})

AppendItemDefinitions(
    13,
    265 -- Sticky Jumper
)
aProjectileInfo[13] = DefineDerivedProjectileDefinition(aProjectileInfo[12], {
    iCollisionType = COLLISION_NONE,
    flGravity = 0.25,
})

AppendItemDefinitions(
    14,
    19,    -- Grenade Launcher
    206,   -- Grenade Launcher (Renamed/Strange)
    1007,  -- Festive Grenade Launcher
    15077, -- Autumn
    15079, -- Macabre Web
    15091, -- Rainbow
    15092, -- Sweet Dreams
    15116, -- Coffin Nail
    15117, -- Top Shelf
    15142, -- Warhawk
    15158  -- Butcher Bird
)
aProjectileInfo[14] = DefineSimulProjectileDefinition({
    vecOffset = Vector3(16, 8, -6),
    vecVelocity = Vector3(1200, 0, 200),
    vecAngularVelocity = Vector3(600, 0, 0),
    flGravity = 0.25,
    vecMaxs = Vector3(2, 2, 2),
    flElasticity = 0.45,
    flLifetime = 2.175,
    flDamageRadius = 146,
    sModelName = "models/weapons/w_models/w_grenade_grenadelauncher.mdl",
})

AppendItemDefinitions(
    15,
    1151 -- The Iron Bomber
)
aProjectileInfo[15] = DefineDerivedProjectileDefinition(aProjectileInfo[14], {
    flElasticity = 0.09,
    flLifetime = 1.6,
    flDamageRadius = 124,
})

AppendItemDefinitions(
    16,
    308 -- The Loch-n-Load
)
aProjectileInfo[16] = DefineDerivedProjectileDefinition(aProjectileInfo[14], {
    iType = PROJECTILE_TYPE_PSEUDO,
    vecVelocity = Vector3(1500, 0, 200),
    flDrag = 0.225,
    flGravity = 1,
    flLifetime = 2.3,
    flDamageRadius = 0,
})

AppendItemDefinitions(
    17,
    996 -- The Loose Cannon
)
aProjectileInfo[17] = DefineDerivedProjectileDefinition(aProjectileInfo[14], {
    vecVelocity = Vector3(1440, 0, 200),
    vecMaxs = Vector3(6, 6, 6),
    bStopOnHittingEnemy = false,
    bCharges = true,
    sModelName = "models/weapons/w_models/w_cannonball.mdl",

    GetLifetime = function(self, flChargeBeginTime)
        return 1 * flChargeBeginTime
    end,
})

AppendItemDefinitions(
    18,
    56,   -- The Huntsman
    1005, -- Festive Huntsman
    1092  -- The Fortified Compound
)
aProjectileInfo[18] = DefinePseudoProjectileDefinition({
    vecOffset = Vector3(23.5, -8, -3),
    vecMaxs = Vector3(0, 0, 0),
    iAlignDistance = 2000,
    bCharges = true,

    GetVelocity = function(self, flChargeBeginTime)
        return Vector3(1800 + CLAMP(flChargeBeginTime, 0, 1) * 800, 0, 0)
    end,

    GetGravity = function(self, flChargeBeginTime)
        return 0.5 - CLAMP(flChargeBeginTime, 0, 1) * 0.4
    end,
})

AppendItemDefinitions(
    19,
    39,  -- The Flare Gun
    351, -- The Detonator
    595, -- The Manmelter
    1081 -- Festive Flare Gun
)
aProjectileInfo[19] = DefinePseudoProjectileDefinition({
    vecVelocity = Vector3(2000, 0, 0),
    vecMaxs = Vector3(0, 0, 0),
    flGravity = 0.3,
    flDrag = 0.5,
    iAlignDistance = 2000,
    flCollideWithTeammatesDelay = 0.25,

    GetOffset = function(self, bDucking, bIsFlipped)
        return Vector3(23.5, 12 * (bIsFlipped and -1 or 1), bDucking and 8 or -3)
    end,
})

AppendItemDefinitions(
    20,
    740 -- The Scorch Shot
)
aProjectileInfo[20] = DefineDerivedProjectileDefinition(aProjectileInfo[19], {
    flDamageRadius = 110,
})

AppendItemDefinitions(
    21,
    305, -- Crusader's Crossbow
    1079 -- Festive Crusader's Crossbow
)
aProjectileInfo[21] = DefinePseudoProjectileDefinition({
    vecOffset = Vector3(23.5, -8, -3),
    vecVelocity = Vector3(2400, 0, 0),
    vecMaxs = Vector3(3, 3, 3),
    flGravity = 0.2,
    iAlignDistance = 2000,
    iCollisionType = COLLISION_HEAL_TEAMMATES,
})

AppendItemDefinitions(
    22,
    997 -- The Rescue Ranger
)
aProjectileInfo[22] = DefineDerivedProjectileDefinition(aProjectileInfo[21], {
    vecMaxs = Vector3(1, 1, 1),
    iCollisionType = COLLISION_HEAL_BUILDINGS,
})

AppendItemDefinitions(
    23,
    17,  -- Syringe Gun
    36,  -- The Blutsauger
    204, -- Syringe Gun (Renamed/Strange)
    412  -- The Overdose
)
aProjectileInfo[23] = DefinePseudoProjectileDefinition({
    vecOffset = Vector3(16, 6, -8),
    vecVelocity = Vector3(1000, 0, 0),
    vecMaxs = Vector3(1, 1, 1),
    flGravity = 0.3,
    flCollideWithTeammatesDelay = 0,
})

AppendItemDefinitions(
    24,
    58,   -- Jarate
    222,  -- Mad Milk
    1083, -- Festive Jarate
    1105, -- The Self-Aware Beauty Mark
    1121  -- Mutated Milk
)
aProjectileInfo[24] = DefinePseudoProjectileDefinition({
    vecOffset = Vector3(16, 8, -6),
    vecVelocity = Vector3(1000, 0, 200),
    vecMaxs = Vector3(8, 8, 8),
    flGravity = 1.125,
    flDamageRadius = 200,
})

AppendItemDefinitions(
    25,
    812, -- The Flying Guillotine
    833  -- The Flying Guillotine (Genuine)
)
aProjectileInfo[25] = DefinePseudoProjectileDefinition({
    vecOffset = Vector3(23.5, 8, -3),
    vecVelocity = Vector3(3000, 0, 300),
    vecMaxs = Vector3(2, 2, 2),
    flGravity = 2.25,
    flDrag = 1.3,
})

AppendItemDefinitions(
    26,
    44 -- The Sandman
)
aProjectileInfo[26] = DefineSimulProjectileDefinition({
    vecVelocity = Vector3(2985.1118164063, 0, 298.51116943359),
    vecAngularVelocity = Vector3(0, 50, 0),
    vecMaxs = Vector3(4.25, 4.25, 4.25),
    flElasticity = 0.45,
    sModelName = "models/weapons/w_models/w_baseball.mdl",

    GetFirePosition = function(self, pLocalPlayer, vecLocalView, vecViewAngles, bIsFlipped)
        --https://github.com/ValveSoftware/source-sdk-2013/blob/0565403b153dfcde602f6f58d8f4d13483696a13/src/game/shared/tf/tf_weapon_bat.cpp#L232
        local vecFirePos = pLocalPlayer:GetAbsOrigin()
            + ((Vector3(0, 0, 50) + (vecViewAngles:Forward() * 32)) * pLocalPlayer:GetPropFloat("m_flModelScale"))

        local resultTrace = TRACE_HULL(vecLocalView, vecFirePos, -Vector3(8, 8, 8), Vector3(8, 8, 8), MASK_SHOT_HULL) -- MASK_SOLID_BRUSHONLY

        return (resultTrace.fraction == 1) and resultTrace.endpos or nil
    end,
})

AppendItemDefinitions(
    27,
    648 -- The Wrap Assassin
)
aProjectileInfo[27] = DefineDerivedProjectileDefinition(aProjectileInfo[26], {
    vecMins = Vector3(-2.990180015564, -2.5989532470703, -2.483987569809),
    vecMaxs = Vector3(2.6593606472015, 2.5989530086517, 2.4839873313904),
    flElasticity = 0,
    flDamageRadius = 50,
    sModelName = "models/weapons/c_models/c_xms_festive_ornament.mdl",
})

AppendItemDefinitions(
    28,
    441 -- The Cow Mangler 5000
)
aProjectileInfo[28] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
    bGravity = false,
    GetOffset = function(self, bDucking, bIsFlipped)
        return Vector3(23.5, 8 * (bIsFlipped and 1 or -1), bDucking and 8 or -3)
    end,
})

--https://github.com/ValveSoftware/source-sdk-2013/blob/0565403b153dfcde602f6f58d8f4d13483696a13/src/game/shared/tf/tf_weapon_raygun.cpp#L249
AppendItemDefinitions(
    29,
    588 -- The Pomson 6000
)
aProjectileInfo[29] = DefineDerivedProjectileDefinition(aProjectileInfo[9], {
    vecAbsoluteOffset = Vector3(0, 0, -13),
    flCollideWithTeammatesDelay = 0,
    bGravity = false,
})

AppendItemDefinitions(
    30,
    1180 -- Gas Passer
)
aProjectileInfo[30] = DefinePseudoProjectileDefinition({
    vecOffset = Vector3(16, 8, -6),
    vecVelocity = Vector3(2000, 0, 200),
    vecMaxs = Vector3(8, 8, 8),
    flGravity = 1,
    flDrag = 1.32,
    flDamageRadius = 200,
})

AppendItemDefinitions(
    31,
    528 -- The Short Circuit
)
aProjectileInfo[31] = DefineBasicProjectileDefinition({
    vecOffset = Vector3(40, 15, -10),
    vecVelocity = Vector3(700, 0, 0),
    vecMaxs = Vector3(1, 1, 1),
    flCollideWithTeammatesDelay = 99999,
    flLifetime = 1.25,
    bGravity = false,
})

AppendItemDefinitions(
    32,
    42,   -- Sandvich
    159,  -- The Dalokohs Bar
    311,  -- The Buffalo Steak Sandvich
    433,  -- Fishcake
    863,  -- Robo-Sandvich
    1002, -- Festive Sandvich
    1190  -- Second Banana
)
aProjectileInfo[32] = DefinePseudoProjectileDefinition({
    vecOffset = Vector3(0, 0, -8),
    vecAngleOffset = Vector3(-10, 0, 0),
    vecVelocity = Vector3(500, 0, 0),
    vecMaxs = Vector3(17, 17, 10),
    flGravity = 1.02,
    iTraceMask = MASK_SHOT_HULL, -- MASK_SHOT_HULL
    iCollisionType = COLLISION_HEAL_HURT,
})

return GetProjectileInformation
