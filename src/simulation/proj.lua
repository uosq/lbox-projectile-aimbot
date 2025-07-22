--- Not used (yet)

local sim = {}

local env = physics.CreateEnvironment()

env:SetAirDensity(2.0)
env:SetGravity(Vector3(0, 0, -800))
env:SetSimulationTimestep(globals.TickInterval())

local MASK_SHOT_HULL = MASK_SHOT_HULL

---@type table<integer, PhysicsObject>
local projectiles = {}

--[[for i, model in pairs(PROJECTILE_MODELS) do
	local solid, collisionModel = physics.ParseModelByName(model)
	local surfaceProp = solid:GetSurfacePropName()
	local objectParams = solid:GetObjectParameters()
	local projectile = env:CreatePolyObject(collisionModel, surfaceProp, objectParams)
	projectiles[i] = projectile
end]]

local function CreateProjectile(model, i)
	local solid, collisionModel = physics.ParseModelByName(model)
	local surfaceProp = solid:GetSurfacePropName()
	local objectParams = solid:GetObjectParameters()
	local projectile = env:CreatePolyObject(collisionModel, surfaceProp, objectParams)
	projectiles[i] = projectile
	return projectile
end

CreateProjectile("models/weapons/w_models/w_rocket.mdl", -1)

---@param pLocal Entity The localplayer
---@param pWeapon Entity The localplayer's weapon
---@param shootPos Vector3
---@param vecForward Vector3 The target direction the projectile should aim for
---@param nTime number Number of seconds we want to simulate
---@param weapon_info WeaponInfo
---@return ProjSimRet
function sim.Run(pLocal, pWeapon, shootPos, vecForward, nTime, weapon_info)
	local positions = {}

	local projectile = projectiles[pWeapon:GetPropInt("m_iItemDefinitionIndex")]
	if not projectile then
		if weapon_info.m_sModelName and weapon_info.m_sModelName ~= "" then
			projectile = CreateProjectile(weapon_info.m_sModelName, pWeapon:GetPropInt("m_iItemDefinitionIndex"))
		else
			projectile = projectiles[-1]
		end
	end

	projectile:Wake()

	local mins, maxs = weapon_info.m_vecMins, weapon_info.m_vecMaxs
	local speed, gravity

	speed = weapon_info:GetVelocity(pWeapon:GetChargeBeginTime() or 0):Length()
	gravity = 800 * weapon_info:GetGravity(pWeapon:GetChargeBeginTime() or 0)

	local velocity = vecForward * speed

	env:SetGravity(Vector3(0, 0, -gravity))
	projectile:SetPosition(shootPos, vecForward, true)
	projectile:SetVelocity(velocity, weapon_info.m_vecAngularVelocity)

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
