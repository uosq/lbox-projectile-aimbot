local multipoint = {}

--- relative to Maxs().z
local z_offsets = { 0.5, 0.7, 0.9, 0.4, 0.2 }

--- inverse of z_offsets
local huntsman_z_offsets = { 0.9, 0.7, 0.5, 0.4, 0.2 }

local splash_offsets = { 0.2, 0.4, 0.5, 0.7, 0.9 }

---@param vHeadPos Vector3
---@param pTarget Entity
---@param vecPredictedPos Vector3
---@param pWeapon Entity
---@param weaponInfo WeaponInfo
---@param drop number
---@return boolean, Vector3?  -- visible, final predicted hit position (or nil)
function multipoint.Run(pTarget, pWeapon, weaponInfo, vHeadPos, vecPredictedPos, drop)
    local proj_type = pWeapon:GetWeaponProjectileType()
    local bExplosive = weaponInfo.m_flDamageRadius > 0 and
        proj_type == E_ProjectileType.TF_PROJECTILE_ROCKET or
        proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB or
        proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_REMOTE or
        proj_type == E_ProjectileType.TF_PROJECTILE_STICKY_BALL or
        proj_type == E_ProjectileType.TF_PROJECTILE_CANNONBALL or
        proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_PRACTICE

    local bSplashWeapon = proj_type == E_ProjectileType.TF_PROJECTILE_ROCKET
        or proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_REMOTE
        or proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_PRACTICE
        or proj_type == E_ProjectileType.TF_PROJECTILE_CANNONBALL
        or proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB
        or proj_type == E_ProjectileType.TF_PROJECTILE_STICKY_BALL
        or proj_type == E_ProjectileType.TF_PROJECTILE_FLAME_ROCKET

    local bHuntsman = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW
    local chosen_offsets = bHuntsman and huntsman_z_offsets or (bSplashWeapon or bExplosive) and splash_offsets or z_offsets

    local trace = nil
    local maxsZ = pTarget:GetMaxs().z

    for i = 1, #chosen_offsets do
        local offset = chosen_offsets[i]
        local baseZ = (maxsZ * offset)

        local zOffset = baseZ + drop
        local origin = vecPredictedPos + Vector3(0,0, zOffset)

        trace = engine.TraceHull(vHeadPos, origin, weaponInfo.m_vecMins, weaponInfo.m_vecMaxs, weaponInfo.m_iTraceMask,
            function(ent, contentsMask)
                return false
            end)

        if trace and trace.fraction == 1 then
            -- build a new Vector3 for the visible hit point
            local finalPos = Vector3(vecPredictedPos:Unpack())
            finalPos.z = origin.z
            return true, finalPos
        end
    end

    -- nothing visible among multipoints
    return false, nil
end

return multipoint
