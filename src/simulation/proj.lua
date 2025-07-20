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

-- Cache parsed models to avoid repeated parsing
local modelCache = {}

---@param pWeapon Entity
local function GetProjectileModel(pWeapon)
	local weaponID = pWeapon:GetWeaponID()
	return PROJECTILE_MODELS[weaponID] or PROJECTILE_MODELS[E_WeaponBaseID.TF_WEAPON_ROCKETLAUNCHER]
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
---@param weapon_info WeaponInfo
---@return ProjSimRet
function sim.Run(pLocal, pWeapon, shootPos, vecForward, nTime, weapon_info)
	local positions = {}

	local projectile = CreateProjectile(pWeapon)
	local mins, maxs = -weapon_info.vecCollisionMax, weapon_info.vecCollisionMax
	local speed = weapon_info.flForwardVelocity
	local velocity = vecForward * speed

	local gravity = weapon_info.flGravity
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
