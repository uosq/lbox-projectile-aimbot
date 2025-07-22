---@meta

---@class WeaponInfo
---@field m_iType integer
---@field m_vecOffset Vector3
---@field m_vecAbsoluteOffset Vector3
---@field m_vecAngleOffset Vector3
---@field m_vecVelocity Vector3
---@field m_vecAngularVelocity Vector3
---@field m_vecMins Vector3
---@field m_vecMaxs Vector3
---@field m_flGravity number
---@field m_flDrag number
---@field m_flElasticity number
---@field m_iAlignDistance integer
---@field m_iTraceMask integer
---@field m_iCollisionType integer
---@field m_flCollideWithTeammatesDelay number
---@field m_flLifetime number
---@field m_flDamageRadius number
---@field m_bStopOnHittingEnemy boolean
---@field m_bCharges boolean
---@field m_sModelName string
local WeaponInfo = {}

---@param bDucking boolean
---@param bIsFlipped boolean
---@return Vector3
function WeaponInfo:GetOffset(bDucking, bIsFlipped) end

---@param flChargeBeginTime number
---@return Vector3
function WeaponInfo:GetAngleOffset(flChargeBeginTime) end

---@param pLocalPlayer Entity
---@param vecLocalView Vector3
---@param vecViewAngles Vector3
---@param bIsFlipped boolean
---@return Vector3
function WeaponInfo:GetFirePosition(pLocalPlayer, vecLocalView, vecViewAngles, bIsFlipped) end

---@param flChargeBeginTime number
---@return Vector3
function WeaponInfo:GetVelocity(flChargeBeginTime) end

---@param flChargeBeginTime number
---@return Vector3
function WeaponInfo:GetAngularVelocity(flChargeBeginTime) end

---@param flChargeBeginTime number
---@return number
function WeaponInfo:GetGravity(flChargeBeginTime) end

---@param flChargeBeginTime number
---@return number
function WeaponInfo:GetLifetime(flChargeBeginTime) end
