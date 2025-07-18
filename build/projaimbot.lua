-- Bundled by luabundle {"version":"1.7.0"}
local __bundle_require, __bundle_loaded, __bundle_register, __bundle_modules = (function(superRequire)
	local loadingPlaceholder = {[{}] = true}

	local register
	local modules = {}

	local require
	local loaded = {}

	register = function(name, body)
		if not modules[name] then
			modules[name] = body
		end
	end

	require = function(name)
		local loadedModule = loaded[name]

		if loadedModule then
			if loadedModule == loadingPlaceholder then
				return nil
			end
		else
			if not modules[name] then
				if not superRequire then
					local identifier = type(name) == 'string' and '\"' .. name .. '\"' or tostring(name)
					error('Tried to require ' .. identifier .. ', but no such module has been registered')
				else
					return superRequire(name)
				end
			end

			loaded[name] = loadingPlaceholder
			loadedModule = modules[name](require, loaded, register, modules)
			loaded[name] = loadedModule
		end

		return loadedModule
	end

	return require, loaded, register, modules
end)(require)
__bundle_register("__root", function(require, _LOADED, __bundle_register, __bundle_modules)
--- this is a fuckin lie
printc(100, 255, 100, 255, "Navet's Projectile Aimbot loaded")
printc(100, 100, 255, 255, "(almost) Every setting is configured by using the Lmaobox menu")

local wep_utils = require("src.utils.weapon_utils")
local math_utils = require("src.utils.math")
local ent_utils = require("src.utils.entity")

local playerSim = require("src.simulation.player")
local projSim = require("src.simulation.proj")

local displayed_projectile_path = {}
local displayed_path = {}
--local displayed_splash_pos = nil
local displayed_time = 0

local iMaxDistance = 2048

local MAX_SIM_TIME = 2.0 --- 2.0 * 67 = 134 ticks
local BEGGARS_BAZOOKA_INDEX = 730

local original_gui_value = gui.GetValue("projectile aimbot")

local OFFSET_MULTIPLIERS = {
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

--[[
---@type Vector3[]
local splashDirections = {}

local stepTheta = 15 --- yaw
local stepPhi = 15 --- pitch

for phi = 0 + stepPhi, 180 - stepPhi, stepPhi do
	local radPhi = math.rad(phi)
	for theta = 0, 360 - stepTheta, stepTheta do
		local radTheta = math.rad(theta)

		local x = math.sin(radPhi) * math.cos(radTheta)
		local y = math.sin(radPhi) * math.sin(radTheta)
		local z = math.cos(radPhi)

		splashDirections[#splashDirections + 1] = Vector3(x, y, z)
	end
end]]

---@param players table<integer, Entity>
---@param pLocal Entity
---@param shootpos Vector3
---@param bAimTeamMate boolean -- Only aim at teammates if true, otherwise only aim at enemies
---@return PlayerInfo
local function GetClosestPlayerToFov(pLocal, shootpos, players, bAimTeamMate)
	local info = {
		angle = nil,
		fov = gui.GetValue("aim fov"),
		index = nil,
		pos = nil,
	}

	local localTeam = pLocal:GetTeamNumber()

	for _, player in pairs(players) do
		if not player:IsDormant() and player:IsAlive() and player:GetIndex() ~= pLocal:GetIndex() then
			local isTeammate = player:GetTeamNumber() == localTeam
			if bAimTeamMate ~= isTeammate then
				goto skip
			end

			if player:InCond(E_TFCOND.TFCond_Cloaked) and gui.GetValue("ignore cloaked") == 1 then
				goto skip
			end

			if player:InCond(E_TFCOND.TFCond_Disguised) and gui.GetValue("ignore disguised") == 1 then
				goto skip
			end

			if player:InCond(E_TFCOND.TFCond_Ubercharged) then
				goto skip
			end

			if player:InCond(E_TFCOND.TFCond_Taunting) and gui.GetValue("ignore taunting") == 1 then
				goto skip
			end

			if player:InCond(E_TFCOND.TFCond_Bonked) and gui.GetValue("ignore bonked") == 1 then
				goto skip
			end

			if (player:GetAbsOrigin() - pLocal:GetAbsOrigin()):Length() < iMaxDistance then
				local origin = player:GetAbsOrigin()
				local angle = math_utils.PositionAngles(shootpos, origin)
				local fov = math_utils.AngleFov(engine.GetViewAngles(), angle)

				if fov and fov < info.fov then
					info.angle = angle
					info.fov = fov
					info.index = player:GetIndex()
					info.pos = origin
				end
			end

			::skip::
		end
	end

	return info
end

local function DirectionToAngles(direction)
	local pitch = math.asin(-direction.z) * (180 / math.pi)
	local yaw = math.atan(direction.y, direction.x) * (180 / math.pi)
	return Vector3(pitch, yaw, 0)
end

--[[-@param pWeapon Entity
local function iGetSplashRadius(pWeapon)
	if pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_REMOTE then
		return 146
	elseif pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_ROCKET then
		return 130
	end

	return nil
end]]

--[[---@param pLocal Entity
---@param pWeapon Entity
---@param vecPredictedPos Vector3
---@param weapon_info WeaponInfo
---@param vecShootPos Vector3
---@return Vector3?
local function vecFindVisibleSplashPos(pLocal, pWeapon, vecPredictedPos, weapon_info, vecShootPos)
	local iSplashRadius = iGetSplashRadius(pWeapon)
	if not iSplashRadius then
		return nil
	end

	local vecMins = -weapon_info.vecCollisionMax
	local vecMaxs = weapon_info.vecCollisionMax

	local bestPos, bestDist = nil, iSplashRadius

	local function shouldHit(ent)
		if ent:GetIndex() == pLocal:GetIndex() then
			return false
		end
		return ent:IsPlayer() == false
	end

	for _, dir in ipairs(splashDirections) do
		local splashPos = vecPredictedPos + dir * (iSplashRadius * 0.9)

		-- check if we can shoot the splash position
		local shootTrace = engine.TraceHull(vecShootPos, splashPos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
		if shootTrace and shootTrace.fraction == 1 then
			local distanceToTarget = (splashPos - vecPredictedPos):Length()
			if distanceToTarget <= iSplashRadius then
				local splashTrace = engine.TraceLine(splashPos, vecPredictedPos, MASK_SHOT_HULL, shouldHit)
				if splashTrace and splashTrace.fraction >= 1 then
					if distanceToTarget < bestDist then
						bestPos = splashPos
						bestDist = distanceToTarget
					end
				end
			end
		end
	end

	return bestPos
end]]

---Returns predicted target pos, total time, charge time
---@param pLocal Entity
---@param pWeapon Entity
---@param pTarget Entity
---@param vecShootPos Vector3
---@param weapon_info any
---@param latency number
local function GetPredictedPosition(pLocal, pWeapon, pTarget, vecShootPos, weapon_info, latency)
	local vecTargetOrigin = pTarget:GetAbsOrigin()
	local dist = (vecShootPos - vecTargetOrigin):Length()

	if dist > iMaxDistance then
		return nil, nil, nil, nil
	end

	local charge_time = 0.0
	if pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW then
		charge_time = globals.CurTime() - pWeapon:GetChargeBeginTime()
		charge_time = (charge_time > 1.0) and 0 or charge_time
	elseif pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER then
		charge_time = globals.CurTime() - pWeapon:GetChargeBeginTime()
		charge_time = (charge_time > 4.0) and 0 or charge_time
	end

	local iprojectile_speed = weapon_info.flForwardVelocity
	local flstepSize = pLocal:GetPropFloat("localdata", "m_flStepSize") or 18
	local predicted_target_pos = vecTargetOrigin
	local total_time = 0.0
	local player_positions = nil

	-- Solve for the ballistic direction first
	local aim_dir = nil
	if weapon_info.flGravity > 0 then
		local gravity = weapon_info.flGravity
		aim_dir = math_utils.SolveBallisticArc(vecShootPos, predicted_target_pos, iprojectile_speed, gravity)
	else
		aim_dir = math_utils.NormalizeVector(predicted_target_pos - vecShootPos)
	end

	if not aim_dir then
		return nil, nil, nil, nil
	end

	local projectile_path = projSim.Run(pLocal, pWeapon, vecShootPos, aim_dir, MAX_SIM_TIME)
	local TOLERANCE = 5.0 --- in HUs

	-- find time where projectile hits or reaches closest to predicted_target_pos
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
		return nil, nil, nil, nil
	end

	total_time = travel_time + latency

	if total_time > MAX_SIM_TIME then
		return nil, nil, nil, nil
	end

	player_positions = playerSim.Run(flstepSize, pTarget, total_time)

	if player_positions and #player_positions > 0 then
		predicted_target_pos = player_positions[#player_positions]
		return predicted_target_pos, total_time, charge_time, player_positions
	end

	return nil, nil, nil, nil
end

---I wanted to use ent_utils.GetBones but this way i dont need to loop some bones
---@return Vector3[]
local function GetMultipointOffsets(pTarget, bIsHuntsman)
	local points = {}
	local origin = pTarget:GetAbsOrigin()
	local maxs = pTarget:GetMaxs()

	local multipliers = bIsHuntsman and OFFSET_MULTIPLIERS.huntsman or OFFSET_MULTIPLIERS.normal

	for _, mult in ipairs(multipliers) do
		local offset = Vector3(maxs.x * mult[1], maxs.y * mult[2], maxs.z * mult[3])
		table.insert(points, origin + offset)
	end

	return points
end

---@param uCmd UserCmd
local function CreateMove(uCmd)
	local netchan = clientstate:GetNetChannel()
	if not netchan then
		return
	end

	local pLocal = entities.GetLocalPlayer()
	if not pLocal or pLocal:IsAlive() == false then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if not pWeapon then
		return
	end

	if pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_BULLET then
		return
	end

	if pWeapon:IsMeleeWeapon() then
		return
	end

	local players = entities.FindByClass("CTFPlayer")

	playerSim.RunBackground(players)

	if input.IsButtonDown(gui.GetValue("aim key")) == false then
		return
	end

	if pLocal:InCond(E_TFCOND.TFCond_Taunting) then
		return
	end

	if pLocal:InCond(E_TFCOND.TFCond_HalloweenKart) then
		return
	end

	if engine.IsChatOpen() == true or engine.Con_IsVisible() or engine.IsGameUIVisible() then
		return
	end

	if gui.GetValue("projectile aimbot") ~= "none" then
		gui.SetValue("projectile aimbot", "none")
	end

	local iCase, iDefinitionIndex = wep_utils.GetWeaponDefinition(pWeapon)
	if not iCase or not iDefinitionIndex then
		return
	end

	local bIsFlippedViewModel = pWeapon:IsViewModelFlipped()
	local bDucking = (pLocal:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0
	local iWeaponID = pWeapon:GetWeaponID()
	local weapon_info = wep_utils.GetWeaponInfo(pWeapon, bDucking, iCase, iDefinitionIndex, iWeaponID)
	local bAimTeamMate = false
	local bIsSandvich = false

	if iWeaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX then
		bAimTeamMate = true
		bIsSandvich = true
	elseif iWeaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW then
		bAimTeamMate = true
	end

	--- gotta fix those offsets ( i never fixed them)
	--local vecShootPos = wep_utils.GetShootPos(pLocal, weapon_info, bIsFlippedViewModel, engine.GetViewAngles())

	local vecHeadPos = pLocal:GetAbsOrigin()
		+ (pLocal:GetPropVector("localdata", "m_vecViewOffset[0]") * (bIsFlippedViewModel and -1 or 1))

	local target_info = GetClosestPlayerToFov(pLocal, vecHeadPos, players, bAimTeamMate)
	if not target_info or target_info.index == nil then
		return
	end

	local pTarget = entities.GetByIndex(target_info.index)
	if not pTarget then
		return
	end

	local latency = netchan:GetLatency(E_Flows.FLOW_OUTGOING) + netchan:GetLatency(E_Flows.FLOW_INCOMING)

	local predicted_pos, total_time, charge, player_predicted_path =
		GetPredictedPosition(pLocal, pWeapon, pTarget, vecHeadPos, weapon_info, latency)

	if predicted_pos == nil or total_time == nil or charge == nil or player_predicted_path == nil then
		return
	end

	local function shouldHit(ent)
		if ent:GetIndex() == pLocal:GetIndex() then
			return false
		end

		if ent:GetIndex() == pTarget:GetIndex() then
			return false
		end

		if ent:IsPlayer() == false then
			return true
		end

		return true
	end

	local vecMins, vecMaxs = -weapon_info.vecCollisionMax, weapon_info.vecCollisionMax
	local multipoints = GetMultipointOffsets(pTarget, pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW)
	local bestPoint = nil
	local bestFraction = 0

	for _, point in ipairs(multipoints) do
		local test_pos = predicted_pos + (point - pTarget:GetAbsOrigin())
		local trace = engine.TraceHull(vecHeadPos, test_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
		if trace and trace.fraction > bestFraction then
			bestPoint = test_pos
			bestFraction = trace.fraction
			if bestFraction >= 0.95 then
				break
			end
		end
	end

	if bestPoint then
		predicted_pos = bestPoint
	end

	local trace = engine.TraceHull(vecHeadPos, predicted_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)

	if trace and trace.fraction < 1 then
		local bones = ent_utils.GetBones(pTarget)
		local preferred_bones = {}

		if pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_ARROW then
			preferred_bones = { 1, 4, 3 } -- head, body, chest
		else
			preferred_bones = { 4, 3, 1 } -- body, chest, head
		end

		local found_bone = false
		local best_pos = nil
		local best_trace_fraction = 0

		for _, boneIndex in ipairs(preferred_bones) do
			local bone = bones[boneIndex]
			if bone then
				local test_pos = bone
				local test_trace = engine.TraceHull(vecHeadPos, test_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)

				if test_trace and test_trace.fraction > best_trace_fraction then
					best_pos = test_pos
					best_trace_fraction = test_trace.fraction

					if test_trace.fraction >= 0.95 then -- almost clear shot
						found_bone = true
						break
					end
				end
			end
		end

		if best_pos and best_trace_fraction > 0.7 then -- at least 70% clear (good enough :)
			predicted_pos = best_pos
			found_bone = true
		end

		if not found_bone then
			--[[local bestSplashPos = vecFindVisibleSplashPos(pLocal, pWeapon, predicted_pos, weapon_info, vecShootPos)
			if bestSplashPos then
				local visTrace =
					engine.TraceHull(vecShootPos, bestSplashPos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
				if visTrace and visTrace.fraction >= 0.95 then
					predicted_pos = bestSplashPos
					displayed_splash_pos = bestSplashPos
				else
					return -- no clear shot available :(
				end
			else
				return -- no clear shot available :(
			end]]
			return
		end
	end

	local angle = nil
	local projectile_path

	if weapon_info.flGravity > 0 then
		local gravity = weapon_info.flGravity
		local aim_dir = math_utils.SolveBallisticArc(vecHeadPos, predicted_pos, weapon_info.flForwardVelocity, gravity)

		if aim_dir then
			-- convert direction to angles
			angle = DirectionToAngles(aim_dir)
			projectile_path =
				projSim.Run(pLocal, pWeapon, vecHeadPos, EulerAngles(angle:Unpack()):Forward(), total_time)
		end
	else
		angle = math_utils.PositionAngles(vecHeadPos, predicted_pos)
		projectile_path = projSim.Run(pLocal, pWeapon, vecHeadPos, angle:Forward(), total_time)
	end

	if angle == nil then
		return
	end

	local isBeggar = iDefinitionIndex == BEGGARS_BAZOOKA_INDEX
	local isCompoundBow = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW
	local isStickyLauncher = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER

	if isBeggar then
		local clip = pWeapon:GetPropInt("LocalWeaponData", "m_iClip1")

		if clip < 1 and pTarget then
			-- keep holding IN_ATTACK while charging
			uCmd.buttons = uCmd.buttons | IN_ATTACK
		else
			-- release to fire
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK
			uCmd:SetViewAngles(angle:Unpack())
			uCmd:SetSendPacket(false)

			displayed_path = player_predicted_path
			displayed_projectile_path = projectile_path
			displayed_time = globals.CurTime() + 1
		end
	elseif isCompoundBow then
		if angle and charge > 0.1 then -- smol charge required, just in case yk
			if gui.GetValue("auto shoot") == 1 and wep_utils.CanShoot() then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end

			-- release to shoot
			if (uCmd.buttons & IN_ATTACK) ~= 0 then
				uCmd.buttons = uCmd.buttons & ~IN_ATTACK
				uCmd:SetViewAngles(angle:Unpack())
				uCmd:SetSendPacket(false)

				displayed_path = player_predicted_path
				displayed_projectile_path = projectile_path
				displayed_time = globals.CurTime() + 1
			end
		else
			-- keep charging
			if gui.GetValue("auto shoot") == 1 and wep_utils.CanShoot() then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end
		end
	elseif isStickyLauncher then
		if gui.GetValue("auto shoot") == 1 and wep_utils.CanShoot() then
			uCmd.buttons = uCmd.buttons | IN_ATTACK
		end

		-- release to fire
		if charge > 0.1 then
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK
			uCmd:SetViewAngles(angle:Unpack())
			uCmd:SetSendPacket(false)

			displayed_path = player_predicted_path
			displayed_projectile_path = projectile_path
			displayed_time = globals.CurTime() + 1
		end
	else
		--- epic sandvich aimbot
		--- (isso é uma gambiarra do caraio)
		if bIsSandvich then
			uCmd.buttons = uCmd.buttons | IN_ATTACK2
			uCmd:SetViewAngles(angle:Unpack())

			displayed_path = player_predicted_path
			displayed_projectile_path = projectile_path
			displayed_time = globals.CurTime() + 1
		else
			if wep_utils.CanShoot() then
				if gui.GetValue("auto shoot") == 1 then
					uCmd.buttons = uCmd.buttons | IN_ATTACK
				end

				if (uCmd.buttons & IN_ATTACK) ~= 0 then
					uCmd:SetViewAngles(angle:Unpack())
					uCmd:SetSendPacket(false)
					displayed_path = player_predicted_path
					displayed_projectile_path = projectile_path
					displayed_time = globals.CurTime() + 1
				end
			end
		end
	end
end

local function Draw()
	local pLocal = entities.GetLocalPlayer()
	if not pLocal then
		return
	end

	if (globals.CurTime() - displayed_time) > 0 then
		displayed_path = {}
		displayed_projectile_path = {}
		--displayed_splash_pos = nil
	end

	if pLocal:IsAlive() == false then
		return
	end

	if engine.IsTakingScreenshot() and gui.GetValue("clean screenshots") == 1 then
		return
	end

	draw.Color(255, 255, 255, 255)

	if displayed_path and #displayed_path >= 2 then
		local max_positions = #displayed_path
		local last_pos = nil

		for i, pos in pairs(displayed_path) do
			if last_pos then
				local screen_current = client.WorldToScreen(pos)
				local screen_last = client.WorldToScreen(last_pos)

				if screen_current and screen_last then
					draw.Color(255, 255, 255, 100)
					draw.Line(screen_last[1], screen_last[2], screen_current[1], screen_current[2])

					--- last position
					if i == max_positions then
						local w, h = 5, 5
						draw.FilledRect(
							screen_current[1] - w,
							screen_current[2] - h,
							screen_current[1] + w,
							screen_current[2] + h
						)
					end
				end
			end
			last_pos = pos
		end
	end

	if displayed_projectile_path then
		local last_pos = nil
		for i, path in pairs(displayed_projectile_path) do
			if last_pos then
				local screen_current = client.WorldToScreen(path.pos)
				local screen_last = client.WorldToScreen(last_pos)

				if screen_current and screen_last then
					-- sick ass fade (no more :( )
					draw.Color(255, 255, 255, 100)
					draw.Line(screen_last[1], screen_last[2], screen_current[1], screen_current[2])
				end
			end
			last_pos = path.pos
		end
	end

	--[[if displayed_splash_pos then
		draw.Color(255, 150, 150, 150)
		local pos = client.WorldToScreen(displayed_splash_pos)
		if pos then
			draw.FilledRect(pos[1] - 5, pos[2] - 5, pos[1] + 5, pos[2] + 5)
		end
	end]]
end

local function Unload()
	gui.SetValue("projectile aimbot", original_gui_value)
end

callbacks.Register("CreateMove", CreateMove)
callbacks.Register("Draw", Draw)
callbacks.Register("Unload", Unload)

end)
__bundle_register("src.simulation.proj", function(require, _LOADED, __bundle_register, __bundle_modules)
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

end)
__bundle_register("src.simulation.player", function(require, _LOADED, __bundle_register, __bundle_modules)
---@diagnostic disable: duplicate-doc-field, missing-fields
local sim = {}

---@type Vector3
local position_samples = {}

---@type Vector3
local velocity_samples = {}

---@type Vector3
local acceleration_samples = {}

local MAX_ALLOWED_SPEED = 2000 -- HU/sec
local MAX_ALLOWED_ACCELERATION = 5000 -- HU/sec²
local SAMPLE_COUNT = 16

---@class Sample
---@field pos Vector3
---@field time number

---@param pEntity Entity
local function AddPositionSample(pEntity)
	local index = pEntity:GetIndex()

	if not position_samples[index] then
		---@type Sample[]
		position_samples[index] = {}
		---@type Vector3[]
		velocity_samples[index] = {}
		---@type Vector3[]
		acceleration_samples[index] = {}
	end

	local current_time = globals.CurTime()
	local current_pos = pEntity:GetAbsOrigin()

	local sample = { pos = current_pos, time = current_time }
	local samples = position_samples[index]
	samples[#samples + 1] = sample

	-- calculate velocity from last sample
	if #samples >= 2 then
		local prev = samples[#samples - 1]
		local dt = current_time - prev.time
		if dt > 0 then
			local vel = (current_pos - prev.pos) / dt

			-- reject outlier velocities
			if vel:Length() <= MAX_ALLOWED_SPEED then
				velocity_samples[index][#velocity_samples[index] + 1] = vel

				-- calculate acceleration from velocity samples
				local vel_samples = velocity_samples[index]
				if #vel_samples >= 2 then
					local prev_vel = vel_samples[#vel_samples - 1]
					local accel = (vel - prev_vel) / dt

					-- reject outlier accelerations
					if accel:Length() <= MAX_ALLOWED_ACCELERATION then
						acceleration_samples[index][#acceleration_samples[index] + 1] = accel
					end
				end
			end
		end
	end

	-- trim samples
	if #samples > SAMPLE_COUNT then
		for i = 1, #samples - SAMPLE_COUNT do
			table.remove(samples, 1)
		end
	end

	if #velocity_samples[index] > SAMPLE_COUNT - 1 then
		for i = 1, #velocity_samples[index] - (SAMPLE_COUNT - 1) do
			table.remove(velocity_samples[index], 1)
		end
	end

	if #acceleration_samples[index] > SAMPLE_COUNT - 2 then
		for i = 1, #acceleration_samples[index] - (SAMPLE_COUNT - 2) do
			table.remove(acceleration_samples[index], 1)
		end
	end
end

---@param position Vector3
---@param mins Vector3
---@param maxs Vector3
---@param pTarget Entity
---@param step_height number
---@return boolean
local function IsOnGround(position, mins, maxs, pTarget, step_height)
	local function shouldHit(ent)
		return ent:GetIndex() ~= pTarget:GetIndex()
	end

	-- first, trace down from the bottom of the bounding box
	local bbox_bottom = position + Vector3(0, 0, mins.z)
	local trace_start = bbox_bottom
	local trace_end = bbox_bottom + Vector3(0, 0, -step_height)

	local trace =
		engine.TraceHull(trace_start, trace_end, Vector3(0, 0, 0), Vector3(0, 0, 0), MASK_SHOT_HULL, shouldHit)

	if trace and trace.fraction < 1 then
		-- check if it's a walkable surface
		local surface_normal = trace.plane
		local ground_angle = math.deg(math.acos(surface_normal:Dot(Vector3(0, 0, 1))))

		if ground_angle <= 45 then
			-- check if we can actually step on this surface
			local hit_point = trace_start + (trace_end - trace_start) * trace.fraction
			local step_test_start = hit_point + Vector3(0, 0, step_height)
			local step_test_end = position

			local step_trace = engine.TraceHull(step_test_start, step_test_end, mins, maxs, MASK_SHOT_HULL, shouldHit)

			-- ff we can fit in the space above the ground, we're grounded
			if not step_trace or step_trace.fraction >= 1 then
				return true
			end
		end
	end

	return false
end

---@param pEntity Entity
---@return boolean
local function IsPlayerOnGround(pEntity)
	local mins, maxs = pEntity:GetMins(), pEntity:GetMaxs()
	local origin = pEntity:GetAbsOrigin()
	local grounded = IsOnGround(origin, mins, maxs, pEntity, pEntity:GetPropFloat("m_flStepSize"))
	return grounded == true
end

--- exponential smoothing for velocity
---@param pEntity Entity
---@return Vector3
local function GetSmoothedVelocity(pEntity)
	local samples = velocity_samples[pEntity:GetIndex()]
	if not samples or #samples == 0 then
		return pEntity:EstimateAbsVelocity()
	end

	local grounded = IsPlayerOnGround(pEntity)
	local alpha = grounded and 0.3 or 0.2 -- grounded = smoother, airborne = more responsive

	local smoothed = samples[1]
	for i = 2, #samples do
		smoothed = (samples[i] * alpha) + (smoothed * (1 - alpha))
	end

	return smoothed
end

--- exponential smoothing for acceleration
---@param pEntity Entity
---@return Vector3
local function GetSmoothedAcceleration(pEntity)
	local samples = acceleration_samples[pEntity:GetIndex()]
	if not samples or #samples == 0 then
		return Vector3(0, 0, 0)
	end

	local grounded = IsPlayerOnGround(pEntity)
	local alpha = grounded and 0.4 or 0.3

	local smoothed = samples[1]
	for i = 2, #samples do
		smoothed = (samples[i] * alpha) + (smoothed * (1 - alpha))
	end

	-- apply deadzone to filter out noise
	local ACCEL_DEADZONE = 50.0 -- HU/sec²
	if smoothed:Length() < ACCEL_DEADZONE then
		smoothed = Vector3(0, 0, 0)
	end

	return smoothed
end

---@param pEntity Entity
---@return number
local function GetSmoothedAngularVelocity(pEntity)
	local samples = position_samples[pEntity:GetIndex()]
	if not samples or #samples < 4 then -- need more samples for better smoothing
		return 0
	end

	local function GetYaw(vec)
		return (vec.x == 0 and vec.y == 0) and 0 or math.deg(math.atan(vec.y, vec.x))
	end

	-- first pass: calculate raw angular velocities with movement threshold
	local ang_vels = {}
	local MIN_MOVEMENT = 1 -- ignore tiny movements that are likely noise

	for i = 1, #samples - 2 do
		local d1 = samples[i + 1].pos - samples[i].pos
		local d2 = samples[i + 2].pos - samples[i + 1].pos

		-- skip if movement is too small (likely noise)
		if d1:Length() < MIN_MOVEMENT or d2:Length() < MIN_MOVEMENT then
			goto continue
		end

		local yaw1 = GetYaw(d1)
		local yaw2 = GetYaw(d2)
		local diff = (yaw2 - yaw1 + 180) % 360 - 180

		-- filter out extreme jumps (likely noise)
		if math.abs(diff) < 120 then -- ignore impossible turns
			ang_vels[#ang_vels + 1] = diff
		end

		::continue::
	end

	if #ang_vels == 0 then
		return 0
	end

	-- second pass: apply median filter to remove outliers
	if #ang_vels >= 3 then
		local filtered_vels = {}
		for i = 1, #ang_vels do
			if i == 1 or i == #ang_vels then
				-- keep edge values
				filtered_vels[i] = ang_vels[i]
			else
				-- use median of 3 consecutive values
				local window = { ang_vels[i - 1], ang_vels[i], ang_vels[i + 1] }
				table.sort(window)
				filtered_vels[i] = window[2] -- median
			end
		end
		ang_vels = filtered_vels
	end

	-- third pass: exponential smoothing with adaptive alpha
	local grounded = IsPlayerOnGround(pEntity)
	local base_alpha = grounded and 0.4 or 0.2

	local smoothed = ang_vels[1]
	for i = 2, #ang_vels do
		-- adaptive alpha based on change magnitude
		local change = math.abs(ang_vels[i] - smoothed)
		local alpha = base_alpha * math.min(1, change / 45) -- reduce smoothing for large changes
		alpha = math.max(0.1, alpha) -- minimum smoothing

		smoothed = (ang_vels[i] * alpha) + (smoothed * (1 - alpha))
	end

	-- apply deadzone for very small movements
	local DEADZONE = 4.0
	if math.abs(smoothed) < DEADZONE then
		smoothed = 0
	end

	-- clamp to reasonable range
	local MAX_ANG_VEL = 45
	return math.max(-MAX_ANG_VEL, math.min(smoothed, MAX_ANG_VEL))
end

local function GetEnemyTeam()
	local pLocal = entities.GetLocalPlayer()
	if not pLocal then
		return
	end

	return pLocal:GetTeamNumber() == 2 and 3 or 2
end

function sim.RunBackground(players)
	local enemy_team = GetEnemyTeam()

	for _, player in pairs(players) do
		--- no need to predict our own team
		if player:GetTeamNumber() == enemy_team and player:IsAlive() == true and player:IsDormant() == false then
			AddPositionSample(player)
		end
	end
end

local function NormalizeVector(vec)
	local len = vec:Length()
	if len == 0 then
		return Vector3()
	end
	return vec / len
end

---@param stepSize number
---@param pTarget Entity The target
---@param time number The time in seconds we want to predict
function sim.Run(stepSize, pTarget, time)
	local smoothed_velocity = GetSmoothedVelocity(pTarget)
	local smoothed_acceleration = GetSmoothedAcceleration(pTarget)
	local angular_velocity = GetSmoothedAngularVelocity(pTarget)
	local last_pos = pTarget:GetAbsOrigin()

	local tick_interval = globals.TickInterval()
	local gravity = client.GetConVar("sv_gravity")
	local gravity_step = gravity * tick_interval
	local down_vector = Vector3(0, 0, -stepSize)

	local positions = {}
	local mins, maxs = pTarget:GetMins(), pTarget:GetMaxs()

	local function shouldHitEntity(ent, contentsMask)
		return ent:GetIndex() ~= pTarget:GetIndex()
	end

	local maxTicks = (time * 67) // 1
	local was_onground = false

	for i = 1, maxTicks do
		-- apply angular velocity to both velocity and acceleration
		local yaw = math.rad(angular_velocity)
		local cos_yaw, sin_yaw = math.cos(yaw), math.sin(yaw)

		-- rotate velocity
		local vx, vy = smoothed_velocity.x, smoothed_velocity.y
		smoothed_velocity.x = vx * cos_yaw - vy * sin_yaw
		smoothed_velocity.y = vx * sin_yaw + vy * cos_yaw

		-- rotate acceleration
		local ax, ay = smoothed_acceleration.x, smoothed_acceleration.y
		smoothed_acceleration.x = ax * cos_yaw - ay * sin_yaw
		smoothed_acceleration.y = ax * sin_yaw + ay * cos_yaw

		-- apply acceleration to velocity
		smoothed_velocity = smoothed_velocity + smoothed_acceleration * tick_interval

		smoothed_acceleration = smoothed_acceleration * (pTarget:GetPropFloat("m_flFriction") or 1.0)

		-- clamp velocity to target's max speed
		local target_max_speed = pTarget:GetPropFloat("m_flMaxspeed") or 450
		local vel_length = smoothed_velocity:Length()
		if vel_length > target_max_speed then
			smoothed_velocity = smoothed_velocity * (target_max_speed / vel_length)

			-- also reduce acceleration when at max speed to prevent unrealistic buildup
			local vel_direction = NormalizeVector(smoothed_velocity)
			local accel_in_vel_direction = smoothed_acceleration:Dot(vel_direction)
			if accel_in_vel_direction > 0 then
				-- remove acceleration component that would increase speed further
				smoothed_acceleration = smoothed_acceleration - vel_direction * accel_in_vel_direction
			end
		end

		local move_delta = smoothed_velocity * tick_interval
		local next_pos = last_pos + move_delta

		local trace = engine.TraceHull(last_pos, next_pos, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

		if trace.fraction < 1.0 then
			if smoothed_velocity.z >= -50 then
				local step_up = last_pos + Vector3(0, 0, stepSize)
				local step_up_trace = engine.TraceHull(last_pos, step_up, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

				if step_up_trace.fraction >= 1.0 then
					local step_forward = step_up + move_delta
					local step_forward_trace =
						engine.TraceHull(step_up, step_forward, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

					if step_forward_trace.fraction > 0 then
						local step_down_start = step_forward_trace.endpos
						local step_down_end = step_down_start + Vector3(0, 0, -stepSize)
						local step_down_trace = engine.TraceHull(
							step_down_start,
							step_down_end,
							mins,
							maxs,
							MASK_PLAYERSOLID,
							shouldHitEntity
						)

						if step_down_trace.fraction < 1.0 then
							-- check if the surface is walkable
							local surface_normal = step_down_trace.plane
							local ground_angle = math.deg(math.acos(surface_normal:Dot(Vector3(0, 0, 1))))
							local actual_step_height = step_down_start.z - step_down_trace.endpos.z

							if ground_angle <= 45 and actual_step_height <= stepSize and actual_step_height > 0.1 then
								next_pos = step_down_trace.endpos
								last_pos = next_pos
								positions[#positions + 1] = last_pos
								goto continue
							end
						end
					end
				end
			end

			-- do slide, we failed to do a step up
			next_pos = trace.endpos
			local normal = trace.plane
			local dot = smoothed_velocity:Dot(normal)
			smoothed_velocity = smoothed_velocity - normal * dot

			-- also adjust acceleration when hitting walls
			local accel_dot = smoothed_acceleration:Dot(normal)
			if accel_dot < 0 then -- only adjust if accelerating into the wall
				smoothed_acceleration = smoothed_acceleration - normal * accel_dot
			end
		else
			last_pos = next_pos
			positions[#positions + 1] = last_pos
		end

		if smoothed_velocity.z <= 0.1 then
			local ground_trace = engine.TraceLine(next_pos, next_pos + down_vector, MASK_PLAYERSOLID, shouldHitEntity)
			was_onground = ground_trace and ground_trace.fraction < 1.0
		else
			was_onground = false
		end

		if not was_onground then
			smoothed_velocity.z = smoothed_velocity.z - gravity_step
		elseif smoothed_velocity.z < 0 then
			smoothed_velocity.z = 0
		end

		::continue::
	end

	return positions
end

return sim

end)
__bundle_register("src.utils.entity", function(require, _LOADED, __bundle_register, __bundle_modules)
local ent_utils = {}

---@param plocal Entity
function ent_utils.GetShootPosition(plocal)
	return plocal:GetAbsOrigin() + plocal:GetPropVector("localdata", "m_vecViewOffset[0]")
end

---@param entity Entity
---@return table<integer, Vector3>
function ent_utils.GetBones(entity)
	local model = entity:GetModel()
	local studioHdr = models.GetStudioModel(model)

	local myHitBoxSet = entity:GetPropInt("m_nHitboxSet")
	local hitboxSet = studioHdr:GetHitboxSet(myHitBoxSet)
	local hitboxes = hitboxSet:GetHitboxes()

	--boneMatrices is an array of 3x4 float matrices
	local boneMatrices = entity:SetupBones()

    local bones = {}

	for i = 1, #hitboxes do
		local hitbox = hitboxes[i]
		local bone = hitbox:GetBone()

		local boneMatrix = boneMatrices[bone]

		if boneMatrix == nil then
			goto continue
		end

		local bonePos = Vector3(boneMatrix[1][4], boneMatrix[2][4], boneMatrix[3][4])

        bones[i] = bonePos
		::continue::
	end

    return bones
end

---@param player Entity
---@param shootpos Vector3
---@param viewangle EulerAngles
---@param PREFERRED_BONES table
function ent_utils.FindVisibleBodyPart(player, shootpos, utils, viewangle, PREFERRED_BONES)
	local bones = ent_utils.GetBones(player)
	local info = {}
	info.fov = math.huge
	info.angle = nil
	info.index = nil
	info.pos = nil

	for _, preferred_bone in ipairs(PREFERRED_BONES) do
		local bonePos = bones[preferred_bone]
		local trace = engine.TraceLine(shootpos, bonePos, MASK_SHOT_HULL)

		if trace and trace.fraction >= 0.6 then
			local angle = utils.PositionAngles(shootpos, bonePos)
			local fov = utils.AngleFov(angle, viewangle)

			if fov < info.fov then
				info.fov, info.angle, info.index = fov, angle, player:GetIndex()
				info.pos = bonePos
				break --- found a suitable bone, no need to check the other ones
			end
		end
	end

	return info
end

return ent_utils

end)
__bundle_register("src.utils.math", function(require, _LOADED, __bundle_register, __bundle_modules)
local Math = {}

--- Pasted from Lnx00's LnxLib
local function isNaN(x)
	return x ~= x
end

local M_RADPI = 180 / math.pi

-- Calculates the angle between two vectors
---@param source Vector3
---@param dest Vector3
---@return EulerAngles angles
function Math.PositionAngles(source, dest)
	local delta = source - dest

	local pitch = math.atan(delta.z / delta:Length2D()) * M_RADPI
	local yaw = math.atan(delta.y / delta.x) * M_RADPI

	if delta.x >= 0 then
		yaw = yaw + 180
	end

	if isNaN(pitch) then
		pitch = 0
	end
	if isNaN(yaw) then
		yaw = 0
	end

	return EulerAngles(pitch, yaw, 0)
end

-- Calculates the FOV between two angles
---@param vFrom EulerAngles
---@param vTo EulerAngles
---@return number fov
function Math.AngleFov(vFrom, vTo)
	local vSrc = vFrom:Forward()
	local vDst = vTo:Forward()

	local fov = math.deg(math.acos(vDst:Dot(vSrc) / vDst:LengthSqr()))
	if isNaN(fov) then
		fov = 0
	end

	return fov
end

local function NormalizeVector(vec)
	return vec / vec:Length()
end

function Math.SolveBallisticArc(p0, p1, speed, gravity)
	local diff = p1 - p0
	local dx = math.sqrt(diff.x ^ 2 + diff.y ^ 2)
	local dy = diff.z

	local speed2 = speed * speed
	local g = gravity
	local root = speed2 * speed2 - g * (g * dx * dx + 2 * dy * speed2)

	if root < 0 then
		return nil
	end -- no solution

	local sqrt_root = math.sqrt(root)
	local angle = math.atan((speed2 - sqrt_root) / (g * dx)) -- low arc

	local dir_xy = NormalizeVector(Vector3(diff.x, diff.y, 0))
	local aim = Vector3(dir_xy.x * math.cos(angle), dir_xy.y * math.cos(angle), math.sin(angle))

	return NormalizeVector(aim)
end

---@param shootPos Vector3
---@param targetPos Vector3
---@param speed number
---@return number
function Math.EstimateTravelTime(shootPos, targetPos, speed)
	local distance = (targetPos - shootPos):Length()
	return distance / speed
end

---@param val number
---@param min number
---@param max number
function Math.clamp(val, min, max)
	return math.max(min, math.min(val, max))
end

function Math.GetBallisticFlightTime(p0, p1, speed, gravity)
	local diff = p1 - p0
	local dx = math.sqrt(diff.x ^ 2 + diff.y ^ 2)
	local dy = diff.z
	local speed2 = speed * speed
	local g = gravity

	local discriminant = speed2 * speed2 - g * (g * dx * dx + 2 * dy * speed2)
	if discriminant < 0 then
		return nil
	end

	local sqrt_discriminant = math.sqrt(discriminant)
	local angle = math.atan((speed2 - sqrt_discriminant) / (g * dx))

	-- Flight time calculation
	local vz = speed * math.sin(angle)
	local flight_time = (vz + math.sqrt(vz * vz + 2 * g * dy)) / g

	return flight_time
end

Math.NormalizeVector = NormalizeVector
return Math

end)
__bundle_register("src.utils.weapon_utils", function(require, _LOADED, __bundle_register, __bundle_modules)
local wep_utils = {}

---@type table<integer, integer>
local ItemDefinitions = {}

local old_weapon, lastFire, nextAttack

local function GetLastFireTime(weapon)
	return weapon:GetPropFloat("LocalActiveTFWeaponData", "m_flLastFireTime")
end

local function GetNextPrimaryAttack(weapon)
	return weapon:GetPropFloat("LocalActiveWeaponData", "m_flNextPrimaryAttack")
end

--- https://www.unknowncheats.me/forum/team-fortress-2-a/273821-canshoot-function.html
function wep_utils.CanShoot()
	local player = entities:GetLocalPlayer()
	if not player then
		return false
	end

	local weapon = player:GetPropEntity("m_hActiveWeapon")
	if not weapon or not weapon:IsValid() then
		return false
	end
	if weapon:GetPropInt("LocalWeaponData", "m_iClip1") == 0 then
		return false
	end

	local lastfiretime = GetLastFireTime(weapon)
	if lastFire ~= lastfiretime or weapon ~= old_weapon then
		lastFire = lastfiretime
		nextAttack = GetNextPrimaryAttack(weapon)
	end
	old_weapon = weapon
	--[[if math.floor(weapon:GetWeaponData().timeFireDelay * 10) / 10 <= 0.1 then
		return true
	end]]
	return nextAttack <= globals.CurTime()
end

do
	local defs = {
		[222] = 11,
		[812] = 12,
		[833] = 12,
		[1121] = 11,
		[18] = -1,
		[205] = -1,
		[127] = -1,
		[228] = -1,
		[237] = -1,
		[414] = -1,
		[441] = -1,
		[513] = -1,
		[658] = -1,
		[730] = -1,
		[800] = -1,
		[809] = -1,
		[889] = -1,
		[898] = -1,
		[907] = -1,
		[916] = -1,
		[965] = -1,
		[974] = -1,
		[1085] = -1,
		[1104] = -1,
		[15006] = -1,
		[15014] = -1,
		[15028] = -1,
		[15043] = -1,
		[15052] = -1,
		[15057] = -1,
		[15081] = -1,
		[15104] = -1,
		[15105] = -1,
		[15129] = -1,
		[15130] = -1,
		[15150] = -1,
		[442] = -1,
		[1178] = -1,
		[39] = 8,
		[351] = 8,
		[595] = 8,
		[740] = 8,
		[1180] = 0,
		[19] = 5,
		[206] = 5,
		[308] = 5,
		[996] = 6,
		[1007] = 5,
		[1151] = 4,
		[15077] = 5,
		[15079] = 5,
		[15091] = 5,
		[15092] = 5,
		[15116] = 5,
		[15117] = 5,
		[15142] = 5,
		[15158] = 5,
		[20] = 1,
		[207] = 1,
		[130] = 3,
		[265] = 3,
		[661] = 1,
		[797] = 1,
		[806] = 1,
		[886] = 1,
		[895] = 1,
		[904] = 1,
		[913] = 1,
		[962] = 1,
		[971] = 1,
		[1150] = 2,
		[15009] = 1,
		[15012] = 1,
		[15024] = 1,
		[15038] = 1,
		[15045] = 1,
		[15048] = 1,
		[15082] = 1,
		[15083] = 1,
		[15084] = 1,
		[15113] = 1,
		[15137] = 1,
		[15138] = 1,
		[15155] = 1,
		[588] = -1,
		[997] = 9,
		[17] = 10,
		[204] = 10,
		[36] = 10,
		[305] = 9,
		[412] = 10,
		[1079] = 9,
		[56] = 7,
		[1005] = 7,
		[1092] = 7,
		[58] = 11,
		[1083] = 11,
		[1105] = 11,
		[42] = 13,
	}
	local maxIndex = 0
	for k, _ in pairs(defs) do
		if k > maxIndex then
			maxIndex = k
		end
	end
	for i = 1, maxIndex do
		ItemDefinitions[i] = defs[i] or false
	end
end

---@param val number
---@param min number
---@param max number
local function clamp(val, min, max)
	return math.max(min, math.min(val, max))
end

function wep_utils.GetWeaponDefinition(pWeapon)
	local definition_index = pWeapon:GetPropInt("m_iItemDefinitionIndex")
	return ItemDefinitions[definition_index], definition_index
end

-- Returns (offset, forward velocity, upward velocity, collision hull, gravity, drag)
function wep_utils.GetProjectileInformation(pWeapon, bDucking, iCase, iDefIndex, iWepID)
	local chargeTime = pWeapon:GetPropFloat("m_flChargeBeginTime") or 0
	if chargeTime ~= 0 then
		chargeTime = globals.CurTime() - chargeTime
	end

	-- Predefined offsets and collision sizes:
	local offsets = {
		Vector3(16, 8, -6), -- Index 1: Sticky Bomb, Iron Bomber, etc.
		Vector3(23.5, -8, -3), -- Index 2: Huntsman, Crossbow, etc.
		Vector3(23.5, 12, -3), -- Index 3: Flare Gun, Guillotine, etc.
		Vector3(16, 6, -8), -- Index 4: Syringe Gun, etc.
	}
	local collisionMaxs = {
		Vector3(0, 0, 0), -- For projectiles that use TRACE_LINE (e.g. rockets)
		Vector3(1, 1, 1),
		Vector3(2, 2, 2),
		Vector3(3, 3, 3),
	}

	if iCase == -1 then
		-- Rocket Launcher types: force a zero collision hull so that TRACE_LINE is used.
		local vOffset = Vector3(23.5, -8, bDucking and 8 or -3)
		local vCollisionMax = collisionMaxs[1] -- Zero hitbox
		local fForwardVelocity = 1200
		if iWepID == 22 or iWepID == 65 then
			vOffset.y = (iDefIndex == 513) and 0 or 12
			fForwardVelocity = (iWepID == 65) and 2000 or ((iDefIndex == 414) and 1550 or 1100)
		elseif iWepID == 109 then
			vOffset.y, vOffset.z = 6, -3
		else
			fForwardVelocity = 1200
		end
		return vOffset, fForwardVelocity, 0, vCollisionMax, 0, nil
	elseif iCase == 1 then
		return offsets[1], 900 + clamp(chargeTime / 4, 0, 1) * 1500, 200, collisionMaxs[3], 0, nil
	elseif iCase == 2 then
		return offsets[1], 900 + clamp(chargeTime / 1.2, 0, 1) * 1500, 200, collisionMaxs[3], 0, nil
	elseif iCase == 3 then
		return offsets[1], 900 + clamp(chargeTime / 4, 0, 1) * 1500, 200, collisionMaxs[3], 0, nil
	elseif iCase == 4 then
		return offsets[1], 1200, 200, collisionMaxs[4], 400, 0.45
	elseif iCase == 5 then
		local vel = (iDefIndex == 308) and 1500 or 1200
		local drag = (iDefIndex == 308) and 0.225 or 0.45
		return offsets[1], vel, 200, collisionMaxs[4], 400, drag
	elseif iCase == 6 then
		return offsets[1], 1440, 200, collisionMaxs[3], 560, 0.5
	elseif iCase == 7 then
		return offsets[2],
			1800 + clamp(chargeTime, 0, 1) * 800,
			0,
			collisionMaxs[2],
			200 - clamp(chargeTime, 0, 1) * 160,
			nil
	elseif iCase == 8 then
		-- Flare Gun: Use a small nonzero collision hull and a higher drag value to make drag noticeable.
		return Vector3(23.5, 12, bDucking and 8 or -3), 2000, 0, Vector3(0.1, 0.1, 0.1), 120, 0.5
	elseif iCase == 9 then
		local idx = (iDefIndex == 997) and 2 or 4
		return offsets[2], 2400, 0, collisionMaxs[idx], 80, nil
	elseif iCase == 10 then
		return offsets[4], 1000, 0, collisionMaxs[2], 120, nil
	elseif iCase == 11 then
		return Vector3(23.5, 8, -3), 1000, 200, collisionMaxs[4], 450, nil
	elseif iCase == 12 then
		return Vector3(23.5, 8, -3), 3000, 300, collisionMaxs[3], 900, 1.3
	elseif iCase == 13 then
		return Vector3(), 350, 0, collisionMaxs[4], 0.25, 0.1
	end
end

---@return WeaponInfo
function wep_utils.GetWeaponInfo(pWeapon, bDucking, iCase, iDefIndex, iWepID)
	local vOffset, fForwardVelocity, fUpwardVelocity, vCollisionMax, fGravity, fDrag =
		wep_utils.GetProjectileInformation(pWeapon, bDucking, iCase, iDefIndex, iWepID)

	return {
		vecOffset = vOffset,
		flForwardVelocity = fForwardVelocity,
		flUpwardVelocity = fUpwardVelocity,
		vecCollisionMax = vCollisionMax,
		flGravity = fGravity,
		flDrag = fDrag,
	}
end

---@param pLocal Entity
---@param weapon_info WeaponInfo
---@param bIsFlippedViewModel boolean
---@param eAngle EulerAngles
---@return Vector3, Vector3 The normal shoot position
function wep_utils.GetShootPos(pLocal, weapon_info, bIsFlippedViewModel, eAngle)
	-- i stole this from terminator
	local vStartPosition = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
	local vOffset = (eAngle:Forward() * weapon_info.vecOffset.x)
		+ (eAngle:Right() * (weapon_info.vecOffset.y * (bIsFlippedViewModel and -1 or 1)))
		+ (eAngle:Up() * weapon_info.vecOffset.z)

	return vStartPosition + vOffset, vOffset
end

return wep_utils

end)
return __bundle_require("__root")