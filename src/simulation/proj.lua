--- Not used (yet)

local sim = {}

local env = physics.CreateEnvironment()

env:SetAirDensity(2.0)
env:SetGravity(Vector3(0, 0, -800))
env:SetSimulationTimestep(globals.TickInterval())

local MASK_SHOT_HULL = MASK_SHOT_HULL

---@type table<integer, PhysicsObject>
local projectiles = {}

local PROJECTILE_MODELS = {
	[E_WeaponBaseID.TF_WEAPON_ROCKETLAUNCHER] = [[models/weapons/w_models/w_rocket.mdl]],
	[E_WeaponBaseID.TF_WEAPON_GRENADELAUNCHER] = [[models/weapons/w_models/w_grenade_grenadelauncher.mdl]],
	[E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER] = [[models/weapons/w_models/w_stickybomb.mdl]],
	[E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW] = [[models/weapons/w_models/w_arrow.mdl]],
	[E_WeaponBaseID.TF_WEAPON_CANNON] = [[models/weapons/w_models/w_cannonball.mdl]],
	[E_WeaponBaseID.TF_WEAPON_FLAREGUN] = [[models/weapons/w_models/w_flaregun_shell.mdl]],
	[E_WeaponBaseID.TF_WEAPON_DRG_POMSON] = [[models/weapons/w_models/w_drg_ball.mdl]],
}

for i, model in pairs(PROJECTILE_MODELS) do
	local solid, collisionModel = physics.ParseModelByName(model)
	local surfaceProp = solid:GetSurfacePropName()
	local objectParams = solid:GetObjectParameters()
	local projectile = env:CreatePolyObject(collisionModel, surfaceProp, objectParams)
	projectiles[i] = projectile
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

	local projectile = projectiles[pWeapon:GetWeaponID()] or projectiles[E_WeaponBaseID.TF_WEAPON_ROCKETLAUNCHER]
	projectile:Wake()

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

			positions[#positions + 1] = record
			shootPos = currentPos
		else
			break
		end
	end

	env:ResetSimulationClock()
	projectile:Sleep()
	return positions
end

return sim
