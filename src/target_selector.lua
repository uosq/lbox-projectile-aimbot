--[[
    Target selection module
]]

local mod = {}

--- relative to Maxs().z
local z_offsets = {0.2, 0.4, 0.5, 0.7, 0.9}

---@param pLocal Entity
local function GetEnemyTeam(pLocal)
    return pLocal:GetTeamNumber() == 2 and 3 or 2
end

---@param pPlayer Entity
---@param settings table
local function ShouldSkipPlayer(pPlayer, settings)
    if pPlayer:IsPlayer() then
        if not pPlayer:IsAlive() then
            return true
        end
    else
        if pPlayer:GetHealth() == 0 then
            return true
        end
    end

    if pPlayer:IsDormant() then
        return true
    end

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

---@param pLocal Entity
---@param vHeadPos Vector3
---@param math_utils MathLib
---@param entitylist table<integer, Entity>
---@param settings table
---@param bAimAtTeamMates boolean
---@return Entity?, number?
function mod.Run(pLocal, vHeadPos, math_utils, entitylist, settings, bAimAtTeamMates)
    local bestFov = settings.fov
    local selected_entity = nil
    local nOffset = nil
    local trace

    local ignore_team = bAimAtTeamMates and GetEnemyTeam(pLocal) or pLocal:GetTeamNumber()
    local ignore_index = pLocal:GetIndex()
    local close_distance = (settings.close_distance / 100) * settings.max_distance

    for _, entity in pairs (entitylist) do
        if not entity:IsDormant() and entity:GetIndex() ~= ignore_index and entity:GetTeamNumber() ~= ignore_team and not ShouldSkipPlayer(entity, settings) then
            local vDistance = (vHeadPos - entity:GetAbsOrigin()):Length()
            if vDistance <= settings.max_distance then
                for i = 1, #z_offsets do
                    local offset = z_offsets[i]
                    local zOffset = (entity:GetMaxs().z * offset)
                    local origin = entity:GetAbsOrigin()
                    origin.z = origin.z + zOffset

                    if (vHeadPos - origin):Length() <= close_distance then
                        local angle = math_utils.PositionAngles(vHeadPos, origin)
                        local fov = math_utils.AngleFov(angle, engine.GetViewAngles())
                        if fov <= bestFov then
                            bestFov = fov
                            selected_entity = entity
                            nOffset = zOffset
                        end
                    else
                        trace = engine.TraceLine(vHeadPos, origin, MASK_SHOT_HULL, function (ent, contentsMask)
                            return false
                        end)

                        if trace and trace.fraction >= 1 then
                            local angle = math_utils.PositionAngles(vHeadPos, origin)
                            local fov = math_utils.AngleFov(angle, engine.GetViewAngles())
                            if fov <= bestFov then
                                bestFov = fov
                                selected_entity = entity
                                nOffset = zOffset
                            end
                        end
                    end
                end
            end
        end
    end

    return selected_entity, nOffset
end

return mod