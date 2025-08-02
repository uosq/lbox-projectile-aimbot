---@meta

---@class ProjectileSimulation
local sim = {}

---@class ProjSimPoint
---@field pos Vector3
---@field time_secs number

---@alias ProjSimRet ProjSimPoint[]

---@param pWeapon Entity
---@return string
function sim.GetProjectileModel(pWeapon) end

---@param val number
---@param A number
---@param B number
---@param C number
---@param D number
---@return number
function sim.RemapValClamped(val, A, B, C, D) end

---@param weapon Entity
---@return number[] | { [1]: number, [2]: number }
function sim.GetProjectileInfo(weapon) end

---@param pWeapon Entity
---@return PhysicsObject
function sim.CreateProjectile(pWeapon) end

---@param pLocal Entity
---@param pWeapon Entity
---@param shootPos Vector3
---@param vecForward Vector3
---@param nTime number
---@param weapon_info WeaponInfo
---@param charge_time number The charge time (0.0 to 1.0 for bows, 0.0 to 4.0 for stickies)
---@return ProjSimRet, boolean
function sim.Run(pLocal, pWeapon, shootPos, vecForward, nTime, weapon_info, charge_time) end

return sim
