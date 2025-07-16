--- Not used (yet)

local sim = {}

local env = physics.CreateEnvironment()

env:SetAirDensity(2.0)
env:SetGravity(Vector3(0, 0, -800))
env:SetSimulationTimestep(globals.TickInterval())

local MASK_SHOT_HULL = MASK_SHOT_HULL

local PROJECTILE_MODELS = {
	[E_WeaponBaseID.TF_WEAPON_ROCKETLAUNCHER] = [[models/weapons/w_models/w_rocket.mdl]],
	[E_WeaponBaseID.TF_WEAPON_GRENADELAUNCHER] = [[models/weapons/w_models/w_grenade_grenadelauncher.mdl]],
	[E_WeaponBaseID.TF_WEAPON_STICKBOMB] = [[models/weapons/w_models/w_stickybomb.mdl]],
}

-- projectile info by definition index
local PROJ_INFO_DEF = {
	[414] = { 1540, 0 }, -- Liberty Launcher
	[308] = { 1513.3, 0.4 }, -- Loch n' Load
	[595] = { 3000, 0.2 }, -- Manmelter
}

-- projectile info by weapon ID
local PROJ_INFO_ID = {
	[E_WeaponBaseID.TF_WEAPON_ROCKETLAUNCHER] = { 1100, 0 },
	[E_WeaponBaseID.TF_WEAPON_DIRECTHIT] = { 1980, 0 },
	[E_WeaponBaseID.TF_WEAPON_GRENADELAUNCHER] = { 1216.6, 0.5 },
	[E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER] = { 1100, 0 },
	[E_WeaponBaseID.TF_WEAPON_SYRINGEGUN_MEDIC] = { 1000, 0.2 },
	[E_WeaponBaseID.TF_WEAPON_FLAMETHROWER] = { 1000, 0.2, 0.33 },
	[E_WeaponBaseID.TF_WEAPON_FLAREGUN] = { 2000, 0.3 },
	[E_WeaponBaseID.TF_WEAPON_CLEAVER] = { 3000, 0.2 },
	[E_WeaponBaseID.TF_WEAPON_CROSSBOW] = { 2400, 0.2 },
	[E_WeaponBaseID.TF_WEAPON_SHOTGUN_BUILDING_RESCUE] = { 2400, 0.2 },
	[E_WeaponBaseID.TF_WEAPON_CANNON] = { 1453.9, 0.4 },
	[E_WeaponBaseID.TF_WEAPON_RAYGUN] = { 1100, 0 },
}

-- Default projectile info
local DEFAULT_PROJ_INFO = { 1100, 0.2 }

-- Cache parsed models to avoid repeated parsing
local modelCache = {}

---@param pWeapon Entity
local function GetProjectileModel(pWeapon)
	local weaponID = pWeapon:GetWeaponID()
	return PROJECTILE_MODELS[weaponID] or PROJECTILE_MODELS[E_WeaponBaseID.TF_WEAPON_ROCKETLAUNCHER]
end

-- Optimized remap function with early returns
local function RemapValClamped(val, A, B, C, D)
	if A == B then
		return val >= B and D or C
	end

	-- Early clamp check
	if val <= A then
		return C
	end
	if val >= B then
		return D
	end

	local cVal = (val - A) / (B - A)
	return C + (D - C) * cVal
end

local function GetProjectileInfo(weapon)
	local id = weapon:GetWeaponID()
	local defIndex = weapon:GetPropInt("m_iItemDefinitionIndex")

	-- Handle special cases first (most performance critical)
	if id == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW then
		local charge = globals.CurTime() - weapon:GetChargeBeginTime()
		return {
			RemapValClamped(charge, 0.0, 1.0, 1800, 2600),
			RemapValClamped(charge, 0.0, 1.0, 0.5, 0.1),
		}
	elseif id == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER then
		local charge = globals.CurTime() - weapon:GetChargeBeginTime()
		return {
			RemapValClamped(charge, 0.0, 4.0, 900, 2400),
			RemapValClamped(charge, 0.0, 4.0, 0.5, 0.0),
		}
	end

	-- Check cached tables
	return PROJ_INFO_DEF[defIndex] or PROJ_INFO_ID[id] or DEFAULT_PROJ_INFO
end

local function CreateProjectile(pWeapon)
	local projModel = GetProjectileModel(pWeapon)

	if not modelCache[projModel] then
		local solid, collisionModel = physics.ParseModelByName(projModel)
		modelCache[projModel] = {
			solid = solid,
			collisionModel = collisionModel,
			surfaceProp = solid:GetSurfacePropName(),
			objectParams = solid:GetObjectParameters(),
		}
	end

	local cached = modelCache[projModel]
	local projectile = env:CreatePolyObject(cached.collisionModel, cached.surfaceProp, cached.objectParams)
	projectile:Wake()
	return projectile
end

---@param pLocal Entity The localplayer
---@param pWeapon Entity The localplayer's weapon
---@param shootPos Vector3
---@param vecForward Vector3 The target direction the projectile should aim for
---@param nTime number Number of seconds we want to simulate
---@return {pos: Vector3, time_secs: number, target_index?: integer, error?: number}[]
function sim.Run(pLocal, pWeapon, shootPos, vecForward, nTime)
	local positions = {}

	local projectile = CreateProjectile(pWeapon)
	local projinfo = GetProjectileInfo(pWeapon)

	local mins, maxs = projinfo.maxs or Vector3(), projinfo.mins or Vector3()

	local speed = projinfo[1]
	local velocity = vecForward * speed

	local gravity = client.GetConVar("sv_gravity") * projinfo[2]
	env:SetGravity(Vector3(0, 0, -gravity))
	projectile:SetPosition(shootPos, vecForward, true)
	projectile:SetVelocity(velocity, Vector3())

	local tickInterval = globals.TickInterval()
	local running = true

	while running and env:GetSimulationTime() < nTime do
		env:Simulate(tickInterval)

		local currentPos = projectile:GetPosition()

		local trace = engine.TraceHull(shootPos, currentPos, mins, maxs, MASK_SHOT_HULL, function(ent)
			return ent:GetIndex() ~= pLocal:GetIndex()
		end)

		if trace and trace.fraction >= 1 then
			local record = {
				pos = currentPos,
				time_secs = env:GetSimulationTime(),
			}

			table.insert(positions, record)
			shootPos = currentPos
		else
			break
		end
	end

	env:DestroyObject(projectile)
	env:ResetSimulationClock()

	return positions
end

return sim
