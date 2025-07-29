--- Not used (yet)

local sim = {}

local env = physics.CreateEnvironment()

env:SetAirDensity(2.0)
env:SetGravity(Vector3(0, 0, -800))
env:SetSimulationTimestep(globals.TickInterval())

local MASK_SHOT_HULL = MASK_SHOT_HULL

---@type table<integer, PhysicsObject>
local projectiles = {}

local function CreateProjectile(model, i)
	local solid, collisionModel = physics.ParseModelByName(model)
	if not solid or not collisionModel then
		printc(255, 100, 100, 255, string.format("[PROJ AIMBOT] Failed to parse model: %s", model))
		return nil
	end

	local surfaceProp = solid:GetSurfacePropName()
	local objectParams = solid:GetObjectParameters()
	if not surfaceProp or not objectParams then
		printc(255, 100, 100, 255, "[PROJ AIMBOT] Invalid surface properties or parameters")
		return nil
	end

	local projectile = env:CreatePolyObject(collisionModel, surfaceProp, objectParams)
	if not projectile then
		printc(255, 100, 100, 255, "[PROJ AIMBOT] Failed to create poly object")
		return nil
	end

	projectiles[i] = projectile

	printc(150, 255, 150, 255, string.format("[PROJ AIMBOT] Projectile with model %s created", model))
	return projectile
end

---@param pWeapon Entity
---@param weaponInfo WeaponInfo
local function GetChargeTime(pWeapon, weaponInfo)
	local charge_time = 0.0

	if pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW then
		-- check if bow is currently being charged
		local charge_begin_time = pWeapon:GetChargeBeginTime()

		-- if charge_begin_time is 0, the bow isn't charging
		if charge_begin_time > 0 then
			charge_time = globals.CurTime() - charge_begin_time
			-- clamp charge time between 0 and 1 second (full charge)
			charge_time = math.max(0, math.min(charge_time, 1.0))
		else
			-- bow is not charging, use minimum speed
			charge_time = 0.0
		end
	elseif pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER then
		local charge_begin_time = pWeapon:GetChargeBeginTime()

		if charge_begin_time > 0 then
			charge_time = globals.CurTime() - charge_begin_time
			if charge_time > 4.0 then
				charge_time = 0.0
			end
		end
	end

	return charge_time
end

---@param pLocal Entity The localplayer
---@param pWeapon Entity The localplayer's weapon
---@param shootPos Vector3
---@param vecForward Vector3 The target direction the projectile should aim for
---@param nTime number Number of seconds we want to simulate
---@param weapon_info WeaponInfo
---@return ProjSimRet, boolean
function sim.Run(pLocal, pWeapon, shootPos, vecForward, nTime, weapon_info)
	local projectile = projectiles[pWeapon:GetPropInt("m_iItemDefinitionIndex")]
	if not projectile then
		if weapon_info.m_sModelName and weapon_info.m_sModelName ~= "" then
			---@diagnostic disable-next-line: cast-local-type
			projectile = CreateProjectile(weapon_info.m_sModelName, pWeapon:GetPropInt("m_iItemDefinitionIndex"))
		else
			if not projectiles[-1] then
				CreateProjectile("models/weapons/w_models/w_rocket.mdl", -1)
			end
			projectile = projectiles[-1]
		end
	end

	if not projectile then
		printc(255, 0, 0, 255, "[PROJ AIMBOT] Failed to acquire projectile instance!")
		return {}, false
	end

	projectile:Wake()

	local mins, maxs = weapon_info.m_vecMins, weapon_info.m_vecMaxs

	local charge = GetChargeTime(pWeapon, weapon_info)

	-- Get the velocity vector from weapon info (includes upward velocity)
	local velocity_vector = weapon_info:GetVelocity(charge)
	local forward_speed = velocity_vector.x
	local upward_speed = velocity_vector.z or 0

	-- Calculate the final velocity vector with proper upward component
	local velocity = (vecForward * forward_speed) + (Vector3(0, 0, 1) * upward_speed)

	-- Get gravity and apply it to the physics environment
	local has_gravity = pWeapon:GetWeaponProjectileType() ~= E_ProjectileType.TF_PROJECTILE_ROCKET
	if has_gravity then
		env:SetGravity(Vector3(0, 0, -800))
	else
		env:SetGravity(Vector3(0, 0, 0))
	end

	projectile:SetPosition(shootPos, vecForward, true)
	projectile:SetVelocity(velocity, weapon_info:GetAngularVelocity(charge))

	local tickInterval = globals.TickInterval()
	local running = true
	local positions = {}
	local full_sim = true

	while running and env:GetSimulationTime() < nTime do
		env:Simulate(tickInterval)

		local currentPos = projectile:GetPosition()

		local trace = engine.TraceHull(shootPos, currentPos, mins, maxs, MASK_SHOT_HULL, function(ent)
			if ent:GetTeamNumber() ~= pLocal:GetTeamNumber() then
				return false
			end

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
			full_sim = false
			break
		end
	end

	env:ResetSimulationClock()
	projectile:Sleep()
	return positions, full_sim
end

return sim
