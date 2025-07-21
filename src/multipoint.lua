---@class Multipoint
---@field private pLocal Entity
---@field private pTarget Entity
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

local offset_multipliers = {
	splash = {
		{ 0, 0, 0.2 }, -- legs
		{ 0, 0, 0.5 }, -- chest
		{ 0.6, 0, 0.5 }, -- right shoulder
		{ -0.6, 0, 0.5 }, -- left shoulder
		{ 0, 0, 0.9 }, -- near head
	},
	huntsman = {
		{ 0, 0, 0.9 }, -- near head
		{ 0, 0, 0.5 }, -- chest
		{ 0.6, 0, 0.5 }, -- right shoulder
		{ -0.6, 0, 0.5 }, -- left shoulder
		{ 0, 0, 0.2 }, -- legs
	},
	normal = {
		{ 0, 0, 0.5 }, -- chest
		{ 0.6, 0, 0.5 }, -- right shoulder
		{ -0.6, 0, 0.5 }, -- left shoulder
		{ 0, 0, 0.9 }, -- near head
		{ 0, 0, 0.2 }, -- legs
	},
}

---@return Vector3?
function multipoint:GetBestHitPoint()
	local maxs = self.pTarget:GetMaxs()
	local origin = self.pTarget:GetAbsOrigin()

	local multipliers = self.bIsHuntsman and offset_multipliers.huntsman
		or self.bIsSplash and offset_multipliers.splash
		or offset_multipliers.normal

	local vecMins, vecMaxs = -self.weapon_info.vecCollisionMax, self.weapon_info.vecCollisionMax
	local bestPoint = nil
	local bestFraction = 0

	local function shouldHit(ent)
		if ent:GetIndex() == self.pLocal:GetIndex() then
			return false
		end
		return ent:GetTeamNumber() ~= self.pTarget:GetTeamNumber()
	end

	for _, mult in ipairs(multipliers) do
		local offset = Vector3(maxs.x * mult[1], maxs.y * mult[2], maxs.z * mult[3])
		local test_pos = self.vecPredictedPos + offset

		local trace = engine.TraceHull(self.vecHeadPos, test_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
		if trace and trace.fraction > bestFraction then
			bestPoint = test_pos
			bestFraction = trace.fraction
			if bestFraction >= 0.95 then
				break
			end
		end
	end

	return bestPoint
end

function multipoint:Set(
	pLocal,
	pTarget,
	bIsHuntsman,
	vecAimDir,
	bAimTeamMate,
	vecHeadPos,
	vecPredictedPos,
	weapon_info,
	math_utils,
	iMaxDistance,
	bIsSplash
)
	self.pLocal = pLocal
	self.pTarget = pTarget
	self.bIsHuntsman = bIsHuntsman
	self.vecAimDir = vecAimDir
	self.bAimTeamMate = bAimTeamMate
	self.vecHeadPos = vecHeadPos
	self.weapon_info = weapon_info
	self.math_utils = math_utils
	self.iMaxDistance = iMaxDistance
	self.vecPredictedPos = vecPredictedPos
	self.bIsSplash = bIsSplash
end

return multipoint
