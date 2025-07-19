---@class Prediction
---@field pLocal Entity
---@field pWeapon Entity
---@field pTarget Entity
---@field weapon_info WeaponInfo
---@field proj_sim ProjectileSimulation
---@field player_sim table
---@field vecShootPos Vector3
---@field iMaxDistance integer
---@field math_utils MathLib
---@field nMaxTime number
---@field nLatency number
---@field multipoint Multipoint
---@field private __index table
local pred = {}
pred.__index = pred

function pred:Set(
	pLocal,
	pWeapon,
	pTarget,
	weapon_info,
	proj_sim,
	player_sim,
	math_utils,
	multipoint,
	vecShootPos,
	nLatency
)
	self.pLocal = pLocal
	self.pWeapon = pWeapon
	self.weapon_info = weapon_info
	self.proj_sim = proj_sim
	self.player_sim = player_sim
	self.vecShootPos = vecShootPos
	self.pTarget = pTarget
	self.iMaxDistance = 2048
	self.nMaxTime = 5.0
	self.multipoint = multipoint
	self.nLatency = nLatency
	self.math_utils = math_utils
end

---@param offset Vector3
---@param direction Vector3
local function RotateOffsetAlongDirection(math_utils, offset, direction)
	local forward = math_utils.NormalizeVector(direction)
	local up = Vector3(0, 0, 1)
	local right = math_utils.NormalizeVector(forward:Cross(up))
	up = math_utils.NormalizeVector(right:Cross(forward))

	return forward * offset.x + right * offset.y + up * offset.z
end

---@return PredictionResult?
function pred:Run()
	local vecTargetOrigin = self.pTarget:GetAbsOrigin()
	local dist = (self.vecShootPos - vecTargetOrigin):Length()

	if dist > self.iMaxDistance then
		return nil
	end

	local charge_time = 0.0
	if self.pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW then
		charge_time = globals.CurTime() - self.pWeapon:GetChargeBeginTime()
		charge_time = (charge_time > 1.0) and 0 or charge_time
	elseif self.pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER then
		charge_time = globals.CurTime() - self.pWeapon:GetChargeBeginTime()
		charge_time = (charge_time > 4.0) and 0 or charge_time
	end

	local iprojectile_speed = self.weapon_info.flForwardVelocity
	local gravity = self.weapon_info.flGravity

	local preliminary_dir = self.math_utils.NormalizeVector(vecTargetOrigin - self.vecShootPos)
	local rotated_offset = RotateOffsetAlongDirection(self.math_utils, self.weapon_info.vecOffset, preliminary_dir)
	local vecMuzzlePos = self.vecShootPos + rotated_offset

	local initial_dir = nil
	if gravity > 0 then
		initial_dir = self.math_utils.SolveBallisticArc(vecMuzzlePos, vecTargetOrigin, iprojectile_speed, gravity)
	else
		initial_dir = self.math_utils.NormalizeVector(vecTargetOrigin - vecMuzzlePos)
	end

	if not initial_dir then
		return nil
	end

	local projectile_path = self.proj_sim.Run(self.pLocal, self.pWeapon, vecMuzzlePos, initial_dir, self.nMaxTime)

	if not projectile_path or #projectile_path == 0 then
		return nil
	end

	local travel_time = projectile_path[#projectile_path].time_secs
	local total_time = travel_time + self.nLatency

	if total_time > self.nMaxTime then
		return nil
	end

	local flstepSize = self.pLocal:GetPropFloat("localdata", "m_flStepSize") or 18
	local player_positions = self.player_sim.Run(flstepSize, self.pTarget, total_time)

	if not player_positions or #player_positions == 0 then
		return nil
	end

	-- final aim calculation towards predicted position
	local predicted_target_pos = player_positions[#player_positions]
	local aim_dir
	if gravity > 0 then
		aim_dir = self.math_utils.SolveBallisticArc(vecMuzzlePos, predicted_target_pos, iprojectile_speed, gravity)
	else
		aim_dir = self.math_utils.NormalizeVector(predicted_target_pos - vecMuzzlePos)
	end

	projectile_path = self.proj_sim.Run(self.pLocal, self.pWeapon, vecMuzzlePos, aim_dir, self.nMaxTime)

	if not projectile_path or #projectile_path == 0 then
		return nil
	end

	return {
		vecPos = predicted_target_pos,
		nTime = total_time,
		nChargeTime = charge_time,
		vecAimDir = aim_dir,
		vecPlayerPath = player_positions,
		vecProjPath = projectile_path,
	}
end

return pred
