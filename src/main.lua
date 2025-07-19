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

---@param pWeapon Entity
local function iGetSplashRadius(pWeapon)
	if pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_REMOTE then
		return 146
	elseif pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_ROCKET then
		if pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_DIRECTHIT then
			return 50.7
		end
		return 169
	end

	return nil
end

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
