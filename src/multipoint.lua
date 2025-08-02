-- Constants
local FL_DUCKING = 1

---@class Multipoint
---@field private pLocal Entity
---@field private pTarget Entity
---@field private pWeapon Entity
---@field private bIsHuntsman boolean
---@field private bIsSplash boolean
---@field private vecAimDir Vector3
---@field private vecPredictedPos Vector3
---@field private bAimTeamMate boolean
---@field private vecHeadPos Vector3
---@field private weapon_info WeaponInfo
---@field private math_utils MathLib
---@field private iMaxDistance integer
local multipoint = {}

---@return Vector3?
function multipoint:GetBestHitPoint()
	local maxs = self.pTarget:GetMaxs()
	local mins = self.pTarget:GetMins()

	local target_height = maxs.z - mins.z
	local target_width = maxs.x - mins.x
	local target_depth = maxs.y - mins.y

	local is_on_ground = (self.pTarget:GetPropInt("m_fFlags") & FL_ONGROUND) ~= 0
	local vecMins, vecMaxs = self.weapon_info.m_vecMins, self.weapon_info.m_vecMaxs

	local function shouldHit(ent)
		if not ent then
			return false
		end

		if ent:GetIndex() == self.pLocal:GetIndex() then
			return false
		end

		-- For rockets, we want to hit enemies (different team)
		-- For healing weapons, we want to hit teammates (same team)
		if self.bAimTeamMate then
			return ent:GetTeamNumber() == self.pTarget:GetTeamNumber()
		else
			return ent:GetTeamNumber() ~= self.pTarget:GetTeamNumber()
		end
	end

	-- Check if we can shoot from our position to the target point using the same logic as main code
	local function canShootToPoint(target_pos)
		if not target_pos then
			return false
		end

		-- Use the same logic as main code: calculate aim direction first, then check if we can hit
		local viewpos = self.pLocal:GetAbsOrigin() + self.pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")

		-- Calculate aim direction from viewpos to target
		local aim_dir = self.math_utils.NormalizeVector(target_pos - viewpos)
		if not aim_dir then
			return false
		end

		-- Get weapon offset and calculate weapon fire position using the same logic as main code
		local muzzle_offset = self.weapon_info:GetOffset(
			(self.pLocal:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0,
			self.pWeapon:IsViewModelFlipped()
		)
		local vecWeaponFirePos = viewpos
			+ self.math_utils.RotateOffsetAlongDirection(muzzle_offset, aim_dir)
			+ self.weapon_info.m_vecAbsoluteOffset

		-- Check if we can hit using TraceHull (same as main code)
		local trace = engine.TraceHull(vecWeaponFirePos, target_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
		return trace and trace.fraction >= 1
	end

	local head_pos = self.ent_utils.GetBones and self.ent_utils.GetBones(self.pTarget)[1] or nil
	local center_pos = self.vecPredictedPos + Vector3(0, 0, target_height / 2)
	local feet_pos = self.vecPredictedPos + Vector3(0, 0, 10)

	local fallback_points = {
		-- Bottom corners (feet/ground level, prioritized if feet are enabled)
		{ pos = Vector3(-target_width / 2, -target_depth / 2, 0),                 name = "bottom_corner_1" },
		{ pos = Vector3(target_width / 2, -target_depth / 2, 0),                  name = "bottom_corner_2" },
		{ pos = Vector3(-target_width / 2, target_depth / 2, 0),                  name = "bottom_corner_3" },
		{ pos = Vector3(target_width / 2, target_depth / 2, 0),                   name = "bottom_corner_4" },

		-- Mid-height corners (body level)
		{ pos = Vector3(-target_width / 2, -target_depth / 2, target_height / 2), name = "mid_corner_1" },
		{ pos = Vector3(target_width / 2, -target_depth / 2, target_height / 2),  name = "mid_corner_2" },
		{ pos = Vector3(-target_width / 2, target_depth / 2, target_height / 2),  name = "mid_corner_3" },
		{ pos = Vector3(target_width / 2, target_depth / 2, target_height / 2),   name = "mid_corner_4" },

		-- Mid-points on edges (body level)
		{ pos = Vector3(0, -target_depth / 2, target_height / 2),                 name = "mid_front" },
		{ pos = Vector3(0, target_depth / 2, target_height / 2),                  name = "mid_back" },
		{ pos = Vector3(-target_width / 2, 0, target_height / 2),                 name = "mid_left" },
		{ pos = Vector3(target_width / 2, 0, target_height / 2),                  name = "mid_right" },

		-- Bottom mid-points (legs level)
		{ pos = Vector3(0, -target_depth / 2, 0),                                 name = "bottom_front" },
		{ pos = Vector3(0, target_depth / 2, 0),                                  name = "bottom_back" },
		{ pos = Vector3(-target_width / 2, 0, 0),                                 name = "bottom_left" },
		{ pos = Vector3(target_width / 2, 0, 0),                                  name = "bottom_right" },

		-- Top corners (head level)
		{ pos = Vector3(-target_width / 2, -target_depth / 2, target_height),     name = "top_corner_1" },
		{ pos = Vector3(target_width / 2, -target_depth / 2, target_height),      name = "top_corner_2" },
		{ pos = Vector3(-target_width / 2, target_depth / 2, target_height),      name = "top_corner_3" },
		{ pos = Vector3(target_width / 2, target_depth / 2, target_height),       name = "top_corner_4" },

		-- Top mid-points (head level)
		{ pos = Vector3(0, -target_depth / 2, target_height),                     name = "top_front" },
		{ pos = Vector3(0, target_depth / 2, target_height),                      name = "top_back" },
		{ pos = Vector3(-target_width / 2, 0, target_height),                     name = "top_left" },
		{ pos = Vector3(target_width / 2, 0, target_height),                      name = "top_right" },
	}

	-- 1. Bows/headshot weapons
	if self.bIsHuntsman then
		if self.settings.hitparts.head and head_pos and canShootToPoint(head_pos) then
			return head_pos
		end
		if canShootToPoint(center_pos) then
			return center_pos
		end
		if self.settings.hitparts.feet and is_on_ground and canShootToPoint(feet_pos) then
			return feet_pos
		end
		for _, point in ipairs(fallback_points) do
			local test_pos = self.vecPredictedPos + point.pos
			if canShootToPoint(test_pos) then
				return test_pos
			end
		end
		return nil
	end

	-- 2. Explosive projectiles: feet first if enabled and on ground
	if self.bIsSplash and self.settings.hitparts.feet and is_on_ground and canShootToPoint(feet_pos) then
		return feet_pos
	end
	-- Center next
	if canShootToPoint(center_pos) then
		return center_pos
	end

	-- Try fallback points
	for _, point in ipairs(fallback_points) do
		local test_pos = self.vecPredictedPos + point.pos

		if canShootToPoint(test_pos) then
			return test_pos
		end
	end

	-- Fallback: return center position if all else fails
	return center_pos
end

---@param pLocal Entity
---@param pWeapon Entity
---@param pTarget Entity
---@param bIsHuntsman boolean
---@param bAimTeamMate boolean
---@param vecHeadPos Vector3
---@param vecPredictedPos Vector3
---@param weapon_info WeaponInfo
---@param math_utils MathLib
---@param iMaxDistance integer
---@param bIsSplash boolean
---@param ent_utils table
---@param settings table
function multipoint:Set(
	pLocal,
	pWeapon,
	pTarget,
	bIsHuntsman,
	bAimTeamMate,
	vecHeadPos,
	vecPredictedPos,
	weapon_info,
	math_utils,
	iMaxDistance,
	bIsSplash,
	ent_utils,
	settings
)
	self.pLocal = pLocal
	self.pWeapon = pWeapon
	self.pTarget = pTarget
	self.bIsHuntsman = bIsHuntsman
	self.bAimTeamMate = bAimTeamMate
	self.vecHeadPos = vecHeadPos
	self.vecShootPos = vecHeadPos -- Use view position as base
	self.weapon_info = weapon_info
	self.math_utils = math_utils
	self.iMaxDistance = iMaxDistance
	self.vecPredictedPos = vecPredictedPos
	self.bIsSplash = bIsSplash
	self.ent_utils = ent_utils
	self.settings = settings
end

return multipoint
