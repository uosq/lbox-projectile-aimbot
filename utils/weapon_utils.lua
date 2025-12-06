local wep_utils = {}

local old_weapon, lastFire, nextAttack = nil, 0, 0

local function GetLastFireTime(weapon)
    return weapon:GetPropFloat("LocalActiveTFWeaponData", "m_flLastFireTime")
end

local function GetNextPrimaryAttack(weapon)
    return weapon:GetPropFloat("LocalActiveWeaponData", "m_flNextPrimaryAttack")
end

--- https://www.unknowncheats.me/forum/team-fortress-2-a/273821-canshoot-function.html
function wep_utils.CanShoot()
    local player = entities:GetLocalPlayer()
    if not player then
        return false
    end

    local weapon = player:GetPropEntity("m_hActiveWeapon")
    if not weapon or not weapon:IsValid() then
        return false
    end

    if weapon:GetPropInt("LocalWeaponData", "m_iClip1") == 0 then
        return false
    end

    local lastfiretime = GetLastFireTime(weapon)
    if lastFire ~= lastfiretime or weapon ~= old_weapon then
        lastFire = lastfiretime
        nextAttack = GetNextPrimaryAttack(weapon)
    end

    old_weapon = weapon
    return nextAttack < globals.CurTime()
end

return wep_utils
