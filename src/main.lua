--- this is a fuckin lie
printc(100, 255, 100, 255, "Navet's Projectile Aimbot loaded")
printc(100, 100, 255, 255, "(almost) Every setting is configured by using the Lmaobox menu")
printc(255, 100, 100, 255, "This build does NOT compensate for high ping")

local wep_utils = require("src.utils.weapon_utils")
local math_utils = require("src.utils.math")

local playerSim = require("src.simulation.player")
local projSim = require("src.simulation.proj")

local displayed_projectile_path = {}
local displayed_path = {}
local displayed_time = 0

local iMaxDistance = 2048

---@param players table<integer, Entity>
---@param pLocal Entity
---@param shootpos Vector3
---@return PlayerInfo
local function GetClosestPlayerToFov(pLocal, shootpos, players)
	local info = {
		angle = nil,
		fov = gui.GetValue("aim fov"),
		index = nil,
		pos = nil,
	}

	for _, player in pairs(players) do
		if not player:IsDormant() and player:IsAlive() and player:GetTeamNumber() ~= pLocal:GetTeamNumber() then
			if player:InCond(E_TFCOND.TFCond_Cloaked) == true and gui.GetValue("ignore cloaked") == 1 then
				goto skip
			end

			if player:InCond(E_TFCOND.TFCond_Disguised) == true and gui.GetValue("ignore disguised") == 1 then
				goto skip
			end

			if player:InCond(E_TFCOND.TFCond_Ubercharged) == true then
				goto skip
			end

			if player:InCond(E_TFCOND.TFCond_Taunting) == true and gui.GetValue("ignore taunting") == 1 then
				goto skip
			end

			if player:InCond(E_TFCOND.TFCond_Bonked) == true and gui.GetValue("ignore bonked") == 1 then
				goto skip
			end

			if (player:GetAbsOrigin() - pLocal:GetAbsOrigin()):Length() < iMaxDistance then
				local origin = player:GetAbsOrigin()
				local angle, fov
				angle = math_utils.PositionAngles(shootpos, origin)
				fov = math_utils.AngleFov(engine.GetViewAngles(), angle)

				if fov and fov < info.fov then
					info.angle = angle
					info.fov = fov
					info.index = player:GetIndex()
					info.pos = player:GetAbsOrigin()
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
local function GetPredictedPosition(pLocal, pWeapon, pTarget, vecShootPos, weapon_info)
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
	total_time = travel_time + charge_time

	player_positions = playerSim.Run(flstepSize, pTarget, total_time)

	if player_positions and #player_positions > 0 then
		predicted_target_pos = player_positions[#player_positions]
		return predicted_target_pos, total_time, charge_time, player_positions
	end

	return nil, nil, nil, nil
end

---@param uCmd UserCmd
local function CreateMove(uCmd)
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

	if gui.GetValue("projectile aimbot") ~= "none" then
		return
	end

	local bIsFlippedViewModel = pWeapon:IsViewModelFlipped()
	local bDucking = (pLocal:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0
	local iWeaponID = pWeapon:GetWeaponID()
	local weapon_info = wep_utils.GetWeaponInfo(pWeapon, bDucking, iCase, iDefinitionIndex, iWeaponID)

	--- gotta fix those offsets
	--local vecShootPos = wep_utils.GetShootPos(pLocal, weapon_info, bIsFlippedViewModel)

	local vecShootPos = pLocal:GetAbsOrigin()
		+ (pLocal:GetPropVector("localdata", "m_vecViewOffset[0]") * (bIsFlippedViewModel and -1 or 1))

	local target_info = GetClosestPlayerToFov(pLocal, vecShootPos, players)
	if not target_info or target_info.index == nil then
		return
	end

	local pTarget = entities.GetByIndex(target_info.index)
	if not pTarget then
		return
	end

	local predicted_pos, total_time, charge, player_predicted_path =
		GetPredictedPosition(pLocal, pWeapon, pTarget, vecShootPos, weapon_info)

	if predicted_pos == nil or total_time == nil or charge == nil or player_predicted_path == nil then
		return
	end

	local angle = nil
	local projectile_path

	if weapon_info.flGravity > 0 then
		local gravity = weapon_info.flGravity * globals.TickInterval()
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

	local trace = engine.TraceLine(vecShootPos, predicted_pos, MASK_PLAYERSOLID, function(ent, contentsMask)
		return false
	end)

	if trace and trace.fraction < 1 then
		return
	end

	if wep_utils.CanShoot() and (gui.GetValue("auto shoot") or (uCmd.buttons & IN_ATTACK) ~= 0) then
		uCmd:SetViewAngles(angle:Unpack())
		uCmd.buttons = uCmd.buttons | IN_ATTACK

		if charge and charge > 0 then
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK
		end

		uCmd:SetSendPacket(false)

		displayed_path = player_predicted_path
		displayed_projectile_path = projectile_path
		displayed_time = globals.CurTime() + 1
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

	draw.Color(255, 255, 255, 255)

	if displayed_path and #displayed_path >= 2 then
		local max_positions = #displayed_path
		local last_pos = nil

		for i, pos in pairs(displayed_path) do
			if last_pos then
				local screen_current = client.WorldToScreen(pos)
				local screen_last = client.WorldToScreen(last_pos)

				if screen_current and screen_last then
					draw.Color(255, 255, 255, 200)
					draw.Line(screen_last[1], screen_last[2], screen_current[1], screen_current[2])

					--- last position
					if i == max_positions then
						local w, h = 10, 10
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
					-- sick ass fade
					local alpha = math.max(25, 255 - (i * 5))
					draw.Color(255, 255, 255, alpha)
					draw.Line(screen_last[1], screen_last[2], screen_current[1], screen_current[2])
				end
			end
			last_pos = path.pos
		end
	end
end

callbacks.Register("CreateMove", CreateMove)
callbacks.Register("Draw", Draw)
