-- Constants
local FL_DUCKING = 1

---@class Multipoint
---@field m_pLocal Entity?
---@field m_pTarget Entity?
---@field m_pWeapon Entity?
---@field m_bIsHuntsman boolean
---@field m_bIsExplosive boolean
---@field m_vecPredictedPos Vector3
---@field m_bAimTeamMate boolean
---@field m_vecHeadPos Vector3
---@field m_weaponInfo WeaponInfo?
---@field m_mathUtils MathLib
---@field m_iMaxDistance integer
---@field m_bSplashWeapon boolean
local multipoint = {
	m_pLocal = nil,
	m_pWeapon = nil,
	m_pTarget = nil,
	m_bIsHuntsman = false,
	m_bAimTeamMate = false,
	m_vecHeadPos = Vector3(),
	m_vecShootPos = Vector3(),
	m_weaponInfo = nil,
	m_mathUtils = {},
	m_iMaxDistance = 0,
	m_vecPredictedPos = Vector3(),
	m_bIsExplosive = false,
	m_entUtils = {},
	m_settings = {},
	m_bSplashWeapon = false,
}

---@return Vector3?
function multipoint:GetBestHitPoint()
	if self.m_weaponInfo == nil then
		return self.m_vecPredictedPos
	end

	local maxs = self.m_pTarget:GetMaxs()
	local mins = self.m_pTarget:GetMins()

	local target_height = maxs.z - mins.z
	local target_width = maxs.x - mins.x
	local target_depth = maxs.y - mins.y

	local vecMins, vecMaxs = self.m_weaponInfo.m_vecMins, self.m_weaponInfo.m_vecMaxs

	local function shouldHit(ent)
		if not ent then
			return false
		end

		if ent:GetIndex() == self.m_pLocal:GetIndex() then
			return false
		end

		-- For rockets, we want to hit enemies (different team)
		-- For healing weapons, we want to hit teammates (same team)
		if self.m_bAimTeamMate then
			return ent:GetTeamNumber() == self.m_pTarget:GetTeamNumber()
		else
			return ent:GetTeamNumber() ~= self.m_pTarget:GetTeamNumber()
		end
	end

	-- Check if we can shoot from our position to the target point using the same logic as main code
	local function canShootToPoint(target_pos)
		if not target_pos then
			return false
		end

		-- Use the same logic as main code: calculate aim direction first, then check if we can hit
		local viewpos = self.m_pLocal:GetAbsOrigin() + self.m_pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")

		-- Calculate aim direction from viewpos to target
		local aim_dir = self.m_mathUtils.NormalizeVector(target_pos - viewpos)
		if not aim_dir then
			return false
		end

		-- Get weapon offset and calculate weapon fire position using the same logic as main code
		local muzzle_offset = self.m_weaponInfo:GetOffset(
			(self.m_pLocal:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0,
			self.m_pWeapon:IsViewModelFlipped()
		)
		local vecWeaponFirePos = viewpos
			+ self.m_mathUtils.RotateOffsetAlongDirection(muzzle_offset, aim_dir)
			+ self.m_weaponInfo.m_vecAbsoluteOffset

		-- Use TraceLine when projectile has zero collision hull (e.g., rockets), else TraceHull
		local trace_mask = self.m_weaponInfo.m_iTraceMask or MASK_SHOT_HULL
		-- Use line trace only for rocket-type projectiles
		local proj_type = self.m_pWeapon:GetWeaponProjectileType() or 0
		local use_line_trace = (
			proj_type == E_ProjectileType.TF_PROJECTILE_ROCKET or
			proj_type == E_ProjectileType.TF_PROJECTILE_FLAME_ROCKET or
			proj_type == E_ProjectileType.TF_PROJECTILE_SENTRY_ROCKET
		)
		local trace
		if use_line_trace then
			trace = engine.TraceLine(vecWeaponFirePos, target_pos, trace_mask, shouldHit)
		else
			trace = engine.TraceHull(vecWeaponFirePos, target_pos, vecMins, vecMaxs, trace_mask, shouldHit)
		end
		return trace and trace.fraction >= 1
	end

	local head_pos = self.m_entUtils.GetBones and self.m_entUtils.GetBones(self.m_pTarget)[1] or nil
	local center_pos = self.m_vecPredictedPos + Vector3(0, 0, target_height / 2)
	local feet_pos = self.m_vecPredictedPos + Vector3(0, 0, 5)

	-- For rockets and pipes, prioritize feet positions
	local fallback_points = {}

	-- For explosive weapons (rockets/pipes), prioritize feet and ground-level positions
	fallback_points = {
		-- Bottom corners (feet/ground level, highest priority for explosive)
		{ pos = Vector3(-target_width / 2, -target_depth / 2, 0),                 name = "bottom_corner_1" },
		{ pos = Vector3(target_width / 2, -target_depth / 2, 0),                  name = "bottom_corner_2" },
		{ pos = Vector3(-target_width / 2, target_depth / 2, 0),                  name = "bottom_corner_3" },
		{ pos = Vector3(target_width / 2, target_depth / 2, 0),                   name = "bottom_corner_4" },

		-- Bottom mid-points (legs level, high priority for explosive)
		{ pos = Vector3(0, -target_depth / 2, 0),                                 name = "bottom_front" },
		{ pos = Vector3(0, target_depth / 2, 0),                                  name = "bottom_back" },
		{ pos = Vector3(-target_width / 2, 0, 0),                                 name = "bottom_left" },
		{ pos = Vector3(target_width / 2, 0, 0),                                  name = "bottom_right" },

		-- Mid-height corners (body level, medium priority)
		{ pos = Vector3(-target_width / 2, -target_depth / 2, target_height / 2), name = "mid_corner_1" },
		{ pos = Vector3(target_width / 2, -target_depth / 2, target_height / 2),  name = "mid_corner_2" },
		{ pos = Vector3(-target_width / 2, target_depth / 2, target_height / 2),  name = "mid_corner_3" },
		{ pos = Vector3(target_width / 2, target_depth / 2, target_height / 2),   name = "mid_corner_4" },

		-- Mid-points on edges (body level)
		{ pos = Vector3(0, -target_depth / 2, target_height / 2),                 name = "mid_front" },
		{ pos = Vector3(0, target_depth / 2, target_height / 2),                  name = "mid_back" },
		{ pos = Vector3(-target_width / 2, 0, target_height / 2),                 name = "mid_left" },
		{ pos = Vector3(target_width / 2, 0, target_height / 2),                  name = "mid_right" },

		-- Top corners (head level, lowest priority for explosive)
		{ pos = Vector3(-target_width / 2, -target_depth / 2, target_height),     name = "top_corner_1" },
		{ pos = Vector3(target_width / 2, -target_depth / 2, target_height),      name = "top_corner_2" },
		{ pos = Vector3(-target_width / 2, target_depth / 2, target_height),      name = "top_corner_3" },
		{ pos = Vector3(target_width / 2, target_depth / 2, target_height),       name = "top_corner_4" },

		-- Top mid-points (head level, lowest priority for explosive)
		{ pos = Vector3(0, -target_depth / 2, target_height),                     name = "top_front" },
		{ pos = Vector3(0, target_depth / 2, target_height),                      name = "top_back" },
		{ pos = Vector3(-target_width / 2, 0, target_height),                     name = "top_left" },
		{ pos = Vector3(target_width / 2, 0, target_height),                      name = "top_right" },
	}

	-- Set primary point based on weapon type:
	-- - Bow/Huntsman: prefer head
	-- - Explosives (rocket/pipe of any form): aim feet (splash optimization)
	-- - Default: center of AABB
	local primary_pos
	if self.m_bIsHuntsman then
		if self.m_settings.hitparts.head and head_pos then
			primary_pos = head_pos
		else
			primary_pos = center_pos
		end
	elseif self.m_bSplashWeapon then
		-- Explosives: always prefer feet
		primary_pos = feet_pos
	else
		primary_pos = center_pos
	end

	-- First try to hit the primary point.
	if primary_pos and canShootToPoint(primary_pos) then
		return primary_pos
	end

	-- If primary point wasn't center, try center.
	if primary_pos ~= center_pos and canShootToPoint(center_pos) then
		return center_pos
	end

	-- Iterate through fallback points (multipoint) and return first achievable one.
	for _, point in ipairs(fallback_points) do
		local test_pos = self.m_vecPredictedPos + point.pos
		if canShootToPoint(test_pos) then
			return test_pos
		end
	end

	-- Ultimate fallback: return center.
	return center_pos
end

return multipoint
