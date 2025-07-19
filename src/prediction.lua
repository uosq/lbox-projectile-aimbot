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
---@field private __index table
local pred = {}
pred.__index = pred

function pred:Set(pLocal, pWeapon, pTarget, weapon_info, proj_sim, player_sim, math_utils, vecShootPos, nLatency)
	self.pLocal = pLocal
	self.pWeapon = pWeapon
	self.weapon_info = weapon_info
	self.proj_sim = proj_sim
	self.player_sim = player_sim
	self.vecShootPos = vecShootPos
	self.pTarget = pTarget
	self.iMaxDistance = 2048
	self.nMaxTime = 1.0
	self.nLatency = nLatency
	self.math_utils = math_utils
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
	local predicted_target_pos = vecTargetOrigin

	local aim_dir = nil
	if self.weapon_info.flGravity > 0 then
		local gravity = self.weapon_info.flGravity
		aim_dir = self.math_utils.SolveBallisticArc(self.vecShootPos, predicted_target_pos, iprojectile_speed, gravity)
	else
		aim_dir = self.math_utils.NormalizeVector(predicted_target_pos - self.vecShootPos)
	end

	if not aim_dir then
		return nil
	end

	local projectile_path = self.proj_sim.Run(self.pLocal, self.pWeapon, self.vecShootPos, aim_dir, self.nMaxTime)
	local TOLERANCE = 5.0 --- in HUs

	local total_time = 0.0
	local travel_time = nil
	if projectile_path and #projectile_path > 0 then
		for i, step in ipairs(projectile_path) do
			if (step.pos - predicted_target_pos):Length() < TOLERANCE then
				travel_time = step.time_secs
				break
			end
		end

		-- Fallback: last time
		if not travel_time then
			travel_time = projectile_path[#projectile_path].time_secs
		end
	else
		return nil
	end

	total_time = travel_time + self.nLatency

	if total_time > self.nMaxTime then
		return nil
	end

	local flstepSize = self.pLocal:GetPropFloat("localdata", "m_flStepSize") or 18
	local player_positions = nil

	player_positions = self.player_sim.Run(flstepSize, self.pTarget, total_time)

	if player_positions and #player_positions > 0 then
		return {
			vecPos = player_positions[#player_positions],
			nTime = total_time,
			nChargeTime = charge_time,
			vecAimDir = aim_dir,
			vecPlayerPath = player_positions,
			vecProjPath = projectile_path,
		}
	end

	return nil
end

return pred
