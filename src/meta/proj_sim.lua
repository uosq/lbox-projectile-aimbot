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
function sim.Run(pTarget, pLocal, pWeapon, shootPos, vecForward, vecPredictedPos, nTime, weapon_info, charge_time) end

return sim
