---@class Multipoint
---@field private pLocal Entity
---@field private pTarget Entity
---@field private bIsHuntsman boolean
---@field private vecAimDir Vector3
---@field private vecPredictedPos Vector3
---@field private players table<integer, Entity>
---@field private bAimTeamMate boolean
---@field private vecHeadPos Vector3
---@field private weapon_info WeaponInfo
---@field private math_utils MathLib
---@field private iMaxDistance integer
local multipoint = {}

local offset_multipliers = {
	normal = {
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
}

---@return Vector3?
function multipoint:GetBestHitPoint()
	local points = {}
	local origin = self.pTarget:GetAbsOrigin()
	local maxs = self.pTarget:GetMaxs()

	local multipliers = self.bIsHuntsman and offset_multipliers.huntsman or offset_multipliers.normal

	for _, mult in ipairs(multipliers) do
		local offset = Vector3(maxs.x * mult[1], maxs.y * mult[2], maxs.z * mult[3])
		table.insert(points, origin + offset)
	end

	local vecMins, vecMaxs = -self.weapon_info.vecCollisionMax, self.weapon_info.vecCollisionMax
	local bestPoint = nil
	local bestFraction = 0

	local function shouldHit(ent)
		if ent:GetIndex() == client.GetLocalPlayerIndex() then
			return false
		end

		if ent:GetIndex() == self.pTarget:GetIndex() then
			return false
		end

		if ent:IsPlayer() == false then
			return true
		end

		return true
	end

	for _, mult in ipairs(multipliers) do
		local forward = self.math_utils.NormalizeVector(self.vecAimDir)
		local right = self.math_utils.NormalizeVector(forward:Cross(Vector3(0, 0, 1)))
		local up = self.math_utils.NormalizeVector(right:Cross(forward))

		local test_pos = self.vecPredictedPos
			+ right * (maxs.x * mult[1])
			+ forward * (maxs.y * mult[2])
			+ up * (maxs.z * mult[3])
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
	players,
	bAimTeamMate,
	vecHeadPos,
	vecPredictedPos,
	weapon_info,
	math_utils,
	iMaxDistance
)
	self.pLocal = pLocal
	self.pTarget = pTarget
	self.bIsHuntsman = bIsHuntsman
	self.vecAimDir = vecAimDir
	self.players = players
	self.bAimTeamMate = bAimTeamMate
	self.vecHeadPos = vecHeadPos
	self.weapon_info = weapon_info
	self.math_utils = math_utils
	self.iMaxDistance = iMaxDistance
	self.vecPredictedPos = vecPredictedPos
end

return multipoint
