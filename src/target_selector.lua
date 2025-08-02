--[[
    Target Selector Module
    Handles all target selection logic with weighted scoring system
]]

local math_utils   = require("src.utils.math")

-- =============== Tunables ===============
local DAM_DEFAULT  = 50 -- default damage if you don't have per-weapon value here
local MAX_HP_CLAMP = 300

local FOV_K        = 6.0 -- higher => FOV weight dies faster with angle
local DIST_K_NEAR  = 4.0 -- rise sharpness from 0 -> plateau
local DIST_K_FAR   = 4.0 -- decay sharpness from plateau -> max
local HP_K_LOW     = 6.0 -- health < damage (how fast 1 -> 0.5)
local HP_K_HIGH    = 4.0 -- health > damage (how fast 0.5 -> 0)

-- Component importances (sum doesn't have to be 1, we gate by visibility anyway)
local W_FOV        = 0.45
local W_DIST       = 0.25
local W_HEALTH     = 0.30

-- =============== Helpers ===============
-- exp01_pos: map x in [0,1] -> [0,1] with exponential *rise* (0->0, 1->1)
local function exp01_pos(x, k)
    if k == 0 then return x end
    local denom = 1 - math.exp(-k)
    if denom == 0 then return x end
    return (1 - math.exp(-k * x)) / denom
end

-- exp01_neg: map x in [0,1] -> [1,0] with exponential *decay* (0->1, 1->0)
local function exp01_neg(x, k)
    if k == 0 then return 1 - x end
    local eK = math.exp(-k)
    local denom = 1 - eK
    if denom == 0 then return 1 - x end
    return (math.exp(-k * x) - eK) / denom
end

-- =============== Visibility ===============
-- 1 if visible, 0 if not (gate)
local function GetVisibilityWeight(pLocal, pTarget)
    if not pLocal or not pTarget then return 0 end
    local localViewPos  = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    local targetViewPos = pTarget:GetAbsOrigin() + pTarget:GetPropVector("localdata", "m_vecViewOffset[0]")
    local tr            = engine.TraceLine(localViewPos, targetViewPos, MASK_SHOT)
    -- be generous: either we hit the target, or almost no obstruction
    if tr and (tr.entity == pTarget or tr.fraction > 0.98) then
        return 1
    end
    return 0
end

-- =============== FOV ===============
-- 1 at fov=0 → exponentially to 0 at fov=maxFov
local function GetFovWeight(fov, maxFov, k)
    k = k or FOV_K
    maxFov = math.max(1e-6, maxFov or 180)
    fov = math.max(0, math.min(fov or 0, maxFov))
    local s = fov / maxFov
    return exp01_neg(s, k) -- 0->1, 1->0
end

-- =============== Distance ===============
-- Continuous:
--   d in [0, P]: 0 -> 0.5 (exp rise)
--   d in [P, M]: 0.5 -> 0   (half-exp decay)
local function GetDistanceWeight(distance, plateau, maxDist, kNear, kFar)
    plateau  = plateau or 200
    maxDist  = math.max(0, maxDist or 2000)
    kNear    = kNear or DIST_K_NEAR
    kFar     = kFar or DIST_K_FAR

    distance = math.max(0, math.min(distance or 0, maxDist))
    plateau  = math.min(plateau, maxDist)

    if distance <= plateau then
        local s = (plateau > 0) and (distance / plateau) or 1.0
        return 0.5 * exp01_pos(s, kNear) -- 0..0.5
    else
        local u = (maxDist > plateau) and ((distance - plateau) / (maxDist - plateau)) or 1.0
        return 0.5 * exp01_neg(u, kFar) -- 0.5..0
    end
end

-- =============== Health ===============
-- Below damage: 1 at 1 HP → down to 0.5 at damage (exp decay)
-- Above damage: 0.5 → 0 by MAX_HP_CLAMP (half-exp decay)
local function GetHealthWeight(health, damage)
    damage = math.max(1, damage or DAM_DEFAULT)
    local H = math.max(0, math.min(health or 0, MAX_HP_CLAMP))

    if H <= damage then
        local s = H / damage                             -- 0 -> 1 as HP approaches damage
        local part = exp01_neg(s, HP_K_LOW)              -- 1..0
        return 0.5 + 0.5 * part                          -- 1..0.5
    else
        local u = (H - damage) / (MAX_HP_CLAMP - damage) -- 0..1
        return 0.5 * exp01_neg(u, HP_K_HIGH)             -- 0.5..0
    end
end

-- =============== Target Selection ===============
local TargetSelector = {}

---@param pLocal Entity: Local player
---@param shootpos Vector3: Shooting position
---@param players table<integer, Entity>: List of players to check
---@param settings table: Settings table
---@param bAimTeamMate boolean: Whether to aim at teammates
---@return table? best_target: Best target info or nil if none found
function TargetSelector.GetBestTarget(pLocal, shootpos, players, settings, bAimTeamMate)
    local best_target = {
        angle = nil,
        fov = settings.fov,
        index = nil,
        pos = nil,
    }

    -- Precompute max values for early rejection
    local max_fov = settings.fov or 180
    local max_distance = settings.max_distance or 0
    local best_score = -math.huge

    local localTeam = pLocal:GetTeamNumber()
    local localPos = pLocal:GetAbsOrigin()
    local viewAngles = engine.GetViewAngles()

    ---@type Entity?
    local bestEntity = nil

    -- Helper function to process entities
    local function processEntity(ent)
        if ent:GetTeamNumber() == pLocal:GetTeamNumber() and not bAimTeamMate then
            return
        end

        local origin = ent:GetAbsOrigin()
        local diff = origin - localPos
        local dist = diff:Length()

        -- early skip: too far
        if dist > max_distance then
            return
        end

        local angleToEntity = math_utils.PositionAngles(shootpos, origin)
        if not angleToEntity then
            return
        end

        local fov = math_utils.AngleFov(viewAngles, angleToEntity)
        -- early skip: fov outside allowed range
        if not fov or fov > max_fov then
            return
        end

        -- Scoring: all factors 0-1, higher is better
        local fov_weight = GetFovWeight(fov, max_fov)                  -- [0,1], higher=better
        local dist_weight = GetDistanceWeight(dist, 200, max_distance) -- [0,1], higher=better
        local health_weight = 0                                        -- [0,1], higher=better
        local vis_weight = 1                                           -- [0,1], 1 if visible else 0

        -- Objects (sentry/disp/tele) don't need health; players do:
        if ent:IsPlayer() then
            local assumed_damage = 50 -- TODO: fetch real for current weapon if you want
            health_weight = GetHealthWeight(ent:GetHealth(), assumed_damage)
            vis_weight = GetVisibilityWeight(pLocal, ent)
        else
            vis_weight = GetVisibilityWeight(pLocal, ent)
        end

        -- linear mix, then visibility gate
        local score = (W_FOV * fov_weight) + (W_DIST * dist_weight) + (W_HEALTH * health_weight)
        score = score * vis_weight -- invisible => 0

        if score > best_score then
            best_score = score
            best_target.angle = angleToEntity
            best_target.fov = fov
            bestEntity = ent
        end
    end

    -- Process buildings
    if settings.ents["aim teleporters"] then
        local teles = entities.FindByClass("CObjectTeleporter")
        for _, ent in pairs(teles) do
            processEntity(ent)
        end
    end

    if settings.ents["aim dispensers"] then
        local dispensers = entities.FindByClass("CObjectDispenser")
        for _, ent in pairs(dispensers) do
            processEntity(ent)
        end
    end

    if settings.ents["aim sentries"] then
        local sentries = entities.FindByClass("CObjectSentrygun")
        for _, ent in pairs(sentries) do
            processEntity(ent)
        end
    end

    -- Process players
    if settings.ents["aim players"] then
        for _, player in pairs(players) do
            if player:IsDormant() or not player:IsAlive() or player:GetIndex() == pLocal:GetIndex() then
                goto continue
            end

            -- distance check
            local playerPos = player:GetAbsOrigin()
            local diff = playerPos - localPos
            local dist = diff:Length()
            if dist > max_distance then
                goto continue
            end

            if playerlist.GetPriority(player) < 0 and settings.ignore_conds.friends then
                goto continue
            end

            -- team check
            local isTeammate = player:GetTeamNumber() == localTeam
            if bAimTeamMate ~= isTeammate then
                goto continue
            end

            -- player conds
            if TargetSelector.ShouldSkipPlayer(player, settings) then
                goto continue
            end

            -- fov check
            local angleToPlayer = math_utils.PositionAngles(shootpos, playerPos)
            if not angleToPlayer then
                goto continue
            end
            local fov = math_utils.AngleFov(viewAngles, angleToPlayer)
            if not fov or fov > max_fov then
                goto continue
            end

            -- Scoring: all factors 0-1, higher is better
            local fov_weight = GetFovWeight(fov, max_fov)                  -- [0,1], higher=better
            local dist_weight = GetDistanceWeight(dist, 200, max_distance) -- [0,1], higher=better
            local health_weight = GetHealthWeight(player:GetHealth(), 50)  -- [0,1], higher=better (assume 50 damage)
            local vis_weight = GetVisibilityWeight(pLocal, player)         -- [0,1], 1 if visible else 0

            -- linear mix, then visibility gate
            local score = (W_FOV * fov_weight) + (W_DIST * dist_weight) + (W_HEALTH * health_weight)
            score = score * vis_weight -- invisible => 0

            if score > best_score then
                best_score = score
                best_target.angle = angleToPlayer
                best_target.fov = fov
                bestEntity = player
            end

            ::continue::
        end
    end

    if bestEntity then
        best_target.index = bestEntity:GetIndex()
        best_target.pos = bestEntity:GetAbsOrigin()
    end

    if best_target.index == nil then
        return nil
    end

    return best_target
end

---@param pPlayer Entity: Player to check
---@param settings table: Settings table
---@return boolean: True if player should be skipped
function TargetSelector.ShouldSkipPlayer(pPlayer, settings)
    if pPlayer:InCond(E_TFCOND.TFCond_Cloaked) and settings.ignore_conds.cloaked then
        return true
    end

    if pPlayer:InCond(E_TFCOND.TFCond_Disguised) and settings.ignore_conds.disguised then
        return true
    end

    if pPlayer:InCond(E_TFCOND.TFCond_Taunting) and settings.ignore_conds.taunting then
        return true
    end

    if pPlayer:InCond(E_TFCOND.TFCond_Bonked) and settings.ignore_conds.bonked then
        return true
    end

    if pPlayer:InCond(E_TFCOND.TFCond_Ubercharged) and settings.ignore_conds.ubercharged then
        return true
    end

    if pPlayer:InCond(E_TFCOND.TFCond_Kritzkrieged) and settings.ignore_conds.kritzkrieged then
        return true
    end

    if pPlayer:InCond(E_TFCOND.TFCond_Jarated) and settings.ignore_conds.jarated then
        return true
    end

    if pPlayer:InCond(E_TFCOND.TFCond_Milked) and settings.ignore_conds.milked then
        return true
    end

    if pPlayer:InCond(E_TFCOND.TFCond_HalloweenGhostMode) and settings.ignore_conds.ghost then
        return true
    end

    if playerlist.GetPriority(pPlayer) < 0 and not settings.ignore_conds.friends then
        return true
    end

    if settings.min_priority > playerlist.GetPriority(pPlayer) then
        return true
    end

    if settings.ignore_conds.vaccinator then
        local resist_table = {
            TFCond_UberBulletResist = 58,
            TFCond_UberBlastResist = 59,
            TFCond_UberFireResist = 60,
            TFCond_SmallBulletResist = 61,
            TFCond_SmallBlastResist = 62,
            TFCond_SmallFireResist = 63,
        }

        for _, resist in pairs(resist_table) do
            if pPlayer:InCond(resist) then
                return true
            end
        end
    end

    return false
end

return TargetSelector
