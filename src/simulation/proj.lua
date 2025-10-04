--- Not used (yet)

local sim = {}

local env = physics.CreateEnvironment()

env:SetAirDensity(2.0)
env:SetGravity(Vector3(0, 0, -800))
env:SetSimulationTimestep(globals.TickInterval())

local MASK_SHOT_HULL = MASK_SHOT_HULL

---@type table<integer, PhysicsObject>
local projectiles = {}

local function CreateProjectile(model, i)
    local solid, collisionModel = physics.ParseModelByName(model)
    if not solid or not collisionModel then
        printc(255, 100, 100, 255, string.format("[PROJ AIMBOT] Failed to parse model: %s", model))
        return nil
    end

    local surfaceProp = solid:GetSurfacePropName()
    local objectParams = solid:GetObjectParameters()
    if not surfaceProp or not objectParams then
        printc(255, 100, 100, 255, "[PROJ AIMBOT] Invalid surface properties or parameters")
        return nil
    end

    local projectile = env:CreatePolyObject(collisionModel, surfaceProp, objectParams)
    if not projectile then
        printc(255, 100, 100, 255, "[PROJ AIMBOT] Failed to create poly object")
        return nil
    end

    projectiles[i] = projectile

    printc(150, 255, 150, 255, string.format("[PROJ AIMBOT] Projectile with model %s created", model))
    return projectile
end

--- source: https://developer.mozilla.org/en-US/docs/Games/Techniques/3D_collision_detection
---@param currentPos Vector3
---@param vecTargetPredictedPos Vector3
---@param weaponInfo WeaponInfo
---@param vecTargetMaxs Vector3
---@param vecTargetMins Vector3
local function IsIntersectingBB(currentPos, vecTargetPredictedPos, weaponInfo, vecTargetMaxs, vecTargetMins)
    local vecProjMins = weaponInfo.m_vecMins + currentPos
    local vecProjMaxs = weaponInfo.m_vecMaxs + currentPos

    local targetMins = vecTargetMins + vecTargetPredictedPos
    local targetMaxs = vecTargetMaxs + vecTargetPredictedPos

    -- check overlap on X, Y, and Z
    if vecProjMaxs.x < targetMins.x or vecProjMins.x > targetMaxs.x then return false end
    if vecProjMaxs.y < targetMins.y or vecProjMins.y > targetMaxs.y then return false end
    if vecProjMaxs.z < targetMins.z or vecProjMins.z > targetMaxs.z then return false end

    return true -- all axis overlap
end

---@param pTarget Entity The target
---@param pLocal Entity The localplayer
---@param pWeapon Entity The localplayer's weapon
---@param shootPos Vector3
---@param vecForward Vector3 The target direction the projectile should aim for
---@param nTime number Number of seconds we want to simulate
---@param weapon_info WeaponInfo
---@param charge_time number The charge time (0.0 to 1.0 for bows, 0.0 to 4.0 for stickies)
---@param vecPredictedPos Vector3
---@return ProjSimRet, boolean
function sim.Run(pTarget, pLocal, pWeapon, shootPos, vecForward, vecPredictedPos, nTime, weapon_info, charge_time)
    local projectile = projectiles[pWeapon:GetPropInt("m_iItemDefinitionIndex")]
    if not projectile then
        if weapon_info.m_sModelName and weapon_info.m_sModelName ~= "" then
            ---@diagnostic disable-next-line: cast-local-type
            projectile = CreateProjectile(weapon_info.m_sModelName, pWeapon:GetPropInt("m_iItemDefinitionIndex"))
        else
            if not projectiles[-1] then
                CreateProjectile("models/weapons/w_models/w_rocket.mdl", -1)
            end
            projectile = projectiles[-1]
        end
    end

    if not projectile then
        printc(255, 0, 0, 255, "[PROJ AIMBOT] Failed to acquire projectile instance!")
        return {}, false
    end

    projectile:Wake()

    local mins, maxs = weapon_info.m_vecMins, weapon_info.m_vecMaxs
    local targetmins, targetmaxs = pTarget:GetMaxs(), pTarget:GetMins()

    -- Decide trace mode: use line trace only for rocket-type projectiles
    local proj_type = pWeapon:GetWeaponProjectileType() or 0
    local use_line_trace = (
        proj_type == E_ProjectileType.TF_PROJECTILE_ROCKET or
        proj_type == E_ProjectileType.TF_PROJECTILE_FLAME_ROCKET or
        proj_type == E_ProjectileType.TF_PROJECTILE_SENTRY_ROCKET
    )
    local trace_mask = weapon_info.m_iTraceMask or MASK_SHOT_HULL
    local filter = function(ent)
        if ent:GetTeamNumber() ~= pLocal:GetTeamNumber() then
            return false
        end

        if ent:GetIndex() == pLocal:GetIndex() then
            return false
        end

        return true
    end

    -- Get the velocity vector from weapon info (includes upward velocity)
    local velocity_vector = weapon_info:GetVelocity(charge_time)
    local forward_speed = velocity_vector.x
    local upward_speed = velocity_vector.z or 0

    -- Calculate the final velocity vector with proper upward component
    local velocity = (vecForward * forward_speed) + (Vector3(0, 0, 1) * upward_speed)

    local has_gravity = weapon_info:HasGravity()
    if has_gravity then
        env:SetGravity(Vector3(0, 0, -800))
    else
        env:SetGravity(Vector3(0, 0, 0))
    end

    projectile:SetPosition(shootPos, vecForward, true)
    projectile:SetVelocity(velocity, weapon_info:GetAngularVelocity(charge_time))

    local tickInterval = globals.TickInterval()
    local positions = {}
    local hittarget = false

    while env:GetSimulationTime() < nTime do
        local currentPos = projectile:GetPosition()

        -- Perform a single collision trace per tick using the pre-decided mode
        local trace
        if use_line_trace then
            trace = engine.TraceLine(shootPos, currentPos, trace_mask, filter)
        else
            trace = engine.TraceHull(shootPos, currentPos, mins, maxs, trace_mask, filter)
        end

        if trace and trace.fraction >= 1 then
            local record = {
                pos = currentPos,
                time_secs = env:GetSimulationTime(),
            }

            positions[#positions + 1] = record
            shootPos = currentPos

            if IsIntersectingBB(currentPos, vecPredictedPos, weapon_info, targetmins, targetmaxs) then
                hittarget = true
                break
            end
        else
            break
        end

        env:Simulate(tickInterval)
    end

    env:ResetSimulationClock()
    projectile:Sleep()
    return positions, hittarget
end

return sim
