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
local displayed_time = 0

local iMaxDistance = 2048

local MAX_SIM_TIME = 2.0 --- 2.0 * 67 = 134 ticks
local BEGGARS_BAZOOKA_INDEX = 730

local original_gui_value = gui.GetValue("projectile aimbot")

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

	local travel_time = math.sqrt((vecShootPos - predicted_target_pos):LengthSqr()) / iprojectile_speed
	total_time = travel_time + charge_time + latency

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

---@param pWeapon Entity
---@param pTarget Entity
---@return Vector3
local function GetProjectileOffset(pTarget, pWeapon)
	if pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_ROCKET then
		return Vector3()
	elseif pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_ARROW then
		local bones = ent_utils.GetBones(pTarget)
		local head_pos = bones[1]
		local diff = head_pos - pTarget:GetAbsOrigin()
		return Vector3(0, 0, diff.z)
	elseif pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_PIPEBOMB then
		return Vector3(0, 0, 10)
	end

	return Vector3(0, 0, pTarget:GetMaxs().z / 2)
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

	local iCase, iDefinitionIndex = wep_utils.GetWeaponDefinition(pWeapon)
	if not iCase or not iDefinitionIndex then
		return
	end

	local players = entities.FindByClass("CTFPlayer")

	playerSim.RunBackground(players)

	if input.IsButtonDown(gui.GetValue("aim key")) == false then
		return
	end

	if engine.IsChatOpen() == true or engine.Con_IsVisible() or engine.IsGameUIVisible() then
		return
	end

	if gui.GetValue("projectile aimbot") ~= "none" then
		gui.SetValue("projectile aimbot", "none")
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
	end

	--- gotta fix those offsets
	local vecShootPos = wep_utils.GetShootPos(pLocal, weapon_info, bIsFlippedViewModel)

	--[[local vecShootPos = pLocal:GetAbsOrigin()
		+ (pLocal:GetPropVector("localdata", "m_vecViewOffset[0]") * (bIsFlippedViewModel and -1 or 1))]]

	local target_info = GetClosestPlayerToFov(pLocal, vecShootPos, players, bAimTeamMate)
	if not target_info or target_info.index == nil then
		return
	end

	local pTarget = entities.GetByIndex(target_info.index)
	if not pTarget then
		return
	end

	local latency = netchan:GetLatency(E_Flows.FLOW_OUTGOING) + netchan:GetLatency(E_Flows.FLOW_INCOMING)

	local predicted_pos, total_time, charge, player_predicted_path =
		GetPredictedPosition(pLocal, pWeapon, pTarget, vecShootPos, weapon_info, latency)

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

	predicted_pos = predicted_pos + GetProjectileOffset(pTarget, pWeapon)

	local trace = engine.TraceHull(
		vecShootPos,
		predicted_pos,
		-weapon_info.vecCollisionMax,
		weapon_info.vecCollisionMax,
		MASK_SHOT_HULL,
		shouldHit
	)

	if trace and trace.fraction < 1 then
		local newpos = predicted_pos + Vector3(0, 0, 10)

		trace = engine.TraceHull(
			vecShootPos,
			newpos,
			-weapon_info.vecCollisionMax,
			weapon_info.vecCollisionMax,
			MASK_SHOT_HULL,
			shouldHit
		)

		if trace and trace.fraction < 1 then
			return
		end

		predicted_pos = newpos
	end

	local angle = nil
	local projectile_path

	if weapon_info.flGravity > 0 then
		local gravity = weapon_info.flGravity -- * globals.TickInterval()
		local aim_dir = math_utils.SolveBallisticArc(vecShootPos, predicted_pos, weapon_info.flForwardVelocity, gravity)

		if aim_dir then
			projectile_path = projSim.Run(pLocal, pWeapon, vecShootPos, aim_dir, total_time)
			angle = DirectionToAngles(aim_dir)
		end
	else
		angle = math_utils.PositionAngles(vecShootPos, predicted_pos)
		projectile_path = projSim.Run(pLocal, pWeapon, vecShootPos, angle:Forward(), total_time)
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
	elseif isCompoundBow or isStickyLauncher then
		if gui.GetValue("auto shoot") == 1 then
			uCmd.buttons = uCmd.buttons | IN_ATTACK
		end

		-- release to fire
		if charge > 0.0 then
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK
			uCmd:SetViewAngles(angle:Unpack())
			uCmd:SetSendPacket(false)

			displayed_path = player_predicted_path
			displayed_projectile_path = projectile_path
			displayed_time = globals.CurTime() + 1
		end
	else
		--- epic sandvich aimbot
		if bIsSandvich then
			uCmd.buttons = uCmd.buttons | IN_ATTACK2
			uCmd:SetViewAngles(angle:Unpack())
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
					draw.Color(255, 255, 255, 150)
					draw.Line(screen_last[1], screen_last[2], screen_current[1], screen_current[2])
				end
			end
			last_pos = path.pos
		end
	end
end

local function Unload()
	gui.SetValue("projectile aimbot", original_gui_value)
end

callbacks.Register("CreateMove", CreateMove)
callbacks.Register("Draw", Draw)
callbacks.Register("Unload", Unload)
