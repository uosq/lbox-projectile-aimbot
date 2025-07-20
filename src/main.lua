---@diagnostic disable: cast-local-type

--[[
	NAVET'S PROEJECTILE AIMBOT
	made by navet
	Update: v4
]]

local version = "4"

local settings = {
	max_sim_time = 2.0,
	draw_proj_path = true,
	draw_player_path = true,
	draw_bounding_box = true,
	draw_only = false,
}

local wep_utils = require("src.utils.weapon_utils")
local math_utils = require("src.utils.math")

local player_sim = require("src.simulation.player")
local proj_sim = require("src.simulation.proj")

local prediction = require("src.prediction")
local multipoint = require("src.multipoint")

local displayed_time = 0.0
local BEGGARS_BAZOOKA_INDEX = 730
local max_distance = 2048

local paths = {
	proj_path = {},
	player_path = {},
}

local original_gui_value = gui.GetValue("projectile aimbot")

local function CanRun(pLocal, pWeapon, bIsBeggar, bIgnoreKey)
	if pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_BULLET then
		return false
	end

	if not wep_utils.CanShoot() and not bIsBeggar then
		return false
	end

	if pWeapon:IsMeleeWeapon() then
		return false
	end

	if bIgnoreKey == false and input.IsButtonDown(gui.GetValue("aim key")) == false then
		return false
	end

	if pLocal:InCond(E_TFCOND.TFCond_Taunting) then
		return false
	end

	if pLocal:InCond(E_TFCOND.TFCond_HalloweenKart) then
		return false
	end

	if (engine.IsChatOpen() or engine.Con_IsVisible() or engine.IsGameUIVisible()) == true then
		return false
	end

	return true
end

---@param players table<integer, Entity>
---@param pLocal Entity
---@param shootpos Vector3
---@param bAimTeamMate boolean -- Only aim at teammates if true, otherwise only aim at enemies
---@return PlayerInfo
local function GetClosestPlayerToFov(pLocal, shootpos, players, bAimTeamMate)
	local best_target = {
		angle = nil,
		fov = gui.GetValue("aim fov"),
		index = nil,
		pos = nil,
	}

	local localTeam = pLocal:GetTeamNumber()
	local localPos = pLocal:GetAbsOrigin()
	local viewAngles = engine.GetViewAngles()

	for _, player in pairs(players) do
		if player:IsDormant() or not player:IsAlive() or player:GetIndex() == pLocal:GetIndex() then
			goto continue
		end

		-- distance check
		local playerPos = player:GetAbsOrigin()
		local distSq = (playerPos - localPos):Length()
		if distSq > max_distance then
			goto continue
		end

		-- team check
		local isTeammate = player:GetTeamNumber() == localTeam
		if bAimTeamMate ~= isTeammate then
			goto continue
		end

		-- player conds
		local cond = player:GetPropInt("m_nPlayerCond")
		if (cond & TFCond_Cloaked) ~= 0 and gui.GetValue("ignore cloaked") == 1 then
			goto continue
		end

		if (cond & (TFCond_Disguised | TFCond_Ubercharged | TFCond_Taunting | TFCond_Bonked)) ~= 0 then
			if (cond & TFCond_Disguised) ~= 0 and gui.GetValue("ignore disguised") == 1 then
				goto continue
			end
			if (cond & TFCond_Taunting) ~= 0 and gui.GetValue("ignore taunting") == 1 then
				goto continue
			end
			if (cond & TFCond_Bonked) ~= 0 and gui.GetValue("ignore bonked") == 1 then
				goto continue
			end
			if (cond & TFCond_Ubercharged) ~= 0 then
				goto continue
			end
		end

		-- fov check
		local angleToPlayer = math_utils.PositionAngles(shootpos, playerPos)
		local fov = math_utils.AngleFov(viewAngles, angleToPlayer)
		if fov and fov < best_target.fov then
			best_target.angle = angleToPlayer
			best_target.fov = fov
			best_target.index = player:GetIndex()
			best_target.pos = playerPos
		end

		::continue::
	end

	return best_target
end

---@param pWeapon Entity
local function IsSplashDamageWeapon(pWeapon)
	local projtype = pWeapon:GetWeaponProjectileType()
	local result = projtype == E_ProjectileType.TF_PROJECTILE_ROCKET
		or projtype == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_REMOTE
		or projtype == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_PRACTICE
		or projtype == E_ProjectileType.TF_PROJECTILE_CANNONBALL
	return result
end

local function ProcessPrediction(pLocal, pWeapon, bAimTeamMate, netchannel, bDrawOnly, players)
	if
		not CanRun(pLocal, pWeapon, pWeapon:GetPropInt("m_iItemDefinitionIndex") == BEGGARS_BAZOOKA_INDEX, bDrawOnly)
	then
		return nil
	end

	local iCase, iDefinitionIndex = wep_utils.GetWeaponDefinition(pWeapon)
	if not iCase then
		return nil
	end

	if gui.GetValue("projectile aimbot") ~= "none" then
		gui.SetValue("projectile aimbot", "none")
	end

	local iWeaponID = pWeapon:GetWeaponID()
	bAimTeamMate = (iWeaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX) or (iWeaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW)

	local vecHeadPos = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
	local best_target = GetClosestPlayerToFov(pLocal, vecHeadPos, players, bAimTeamMate)

	if not best_target.index then
		return nil
	end

	local pTarget = entities.GetByIndex(best_target.index)
	if not pTarget then
		return nil
	end

	local bDucking = (pLocal:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0
	local weapon_info = wep_utils.GetWeaponInfo(pWeapon, bDucking, iCase, iDefinitionIndex, iWeaponID)
	local nLatency = netchannel:GetLatency(E_Flows.FLOW_OUTGOING) + netchannel:GetLatency(E_Flows.FLOW_INCOMING)

	prediction:Set(
		pLocal,
		pWeapon,
		pTarget,
		weapon_info,
		proj_sim,
		player_sim,
		math_utils,
		multipoint,
		vecHeadPos,
		nLatency,
		settings.max_sim_time
	)

	return prediction:Run()
end

local function CreateMove_DrawOnly()
	local netchannel = clientstate.GetNetChannel()
	if not netchannel then
		return
	end

	local pLocal = entities.GetLocalPlayer()
	if pLocal == nil then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if pWeapon == nil then
		return
	end

	local players = entities.FindByClass("CTFPlayer")
	player_sim.RunBackground(players)

	if not CanRun(pLocal, pWeapon, true, true) then
		return
	end

	local iCase, iDefinitionIndex = wep_utils.GetWeaponDefinition(pWeapon)
	if not iCase or not iDefinitionIndex then
		return
	end

	if gui.GetValue("projectile aimbot") ~= "none" then
		gui.SetValue("projectile aimbot", "none")
	end

	local iWeaponID = pWeapon:GetWeaponID()
	local bAimTeamMate = false

	if iWeaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX then
		bAimTeamMate = true
	elseif iWeaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW then
		bAimTeamMate = true
	end

	local offset = (pLocal:GetPropVector("localdata", "m_vecViewOffset[0]"))
	local vecHeadPos = pLocal:GetAbsOrigin() + offset

	local best_target = GetClosestPlayerToFov(pLocal, vecHeadPos, players, bAimTeamMate)
	if not best_target.index then
		return
	end

	local pTarget = entities.GetByIndex(best_target.index)
	if not pTarget then
		return
	end

	local pred_result = ProcessPrediction(pLocal, pWeapon, bAimTeamMate, netchannel, settings.draw_only, players)
	if not pred_result then
		return
	end

	displayed_time = globals.CurTime() + 1
	paths.player_path = pred_result.vecPlayerPath
	paths.proj_path = pred_result.vecProjPath
end

---@param uCmd UserCmd
local function CreateMove(uCmd)
	if settings.draw_only then
		CreateMove_DrawOnly()
		return
	end

	local netchannel = clientstate.GetNetChannel()
	if not netchannel then
		return
	end

	local pLocal = entities.GetLocalPlayer()
	if pLocal == nil then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if pWeapon == nil then
		return
	end

	local players = entities.FindByClass("CTFPlayer")
	player_sim.RunBackground(players)

	local bIsBeggar = pWeapon:GetPropInt("m_iItemDefinitionIndex") == BEGGARS_BAZOOKA_INDEX
	if not CanRun(pLocal, pWeapon, bIsBeggar, false) then
		return
	end

	local iCase, iDefinitionIndex = wep_utils.GetWeaponDefinition(pWeapon)
	if not iCase or not iDefinitionIndex then
		return
	end

	if gui.GetValue("projectile aimbot") ~= "none" then
		gui.SetValue("projectile aimbot", "none")
	end

	local iWeaponID = pWeapon:GetWeaponID()
	local bAimTeamMate = false
	local bIsSandvich = false

	if iWeaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX then
		bAimTeamMate = true
		bIsSandvich = true
	elseif iWeaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW then
		bAimTeamMate = true
	end

	local offset = (pLocal:GetPropVector("localdata", "m_vecViewOffset[0]"))
	local vecHeadPos = pLocal:GetAbsOrigin() + offset

	local best_target = GetClosestPlayerToFov(pLocal, vecHeadPos, players, bAimTeamMate)
	if not best_target.index then
		return
	end

	local pTarget = entities.GetByIndex(best_target.index)
	if not pTarget then
		return
	end

	local pred_result = ProcessPrediction(pLocal, pWeapon, bAimTeamMate, netchannel, settings.draw_only, players)
	if not pred_result then
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

	local bIsSplash = IsSplashDamageWeapon(pWeapon)

	local bDucking = (pLocal:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0
	local weapon_info = wep_utils.GetWeaponInfo(pWeapon, bDucking, iCase, iDefinitionIndex, iWeaponID)
	local bIsHuntsman = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW

	multipoint:Set(
		pLocal,
		pTarget,
		bIsHuntsman,
		pred_result.vecAimDir,
		players,
		bAimTeamMate,
		vecHeadPos,
		pred_result.vecPos,
		weapon_info,
		math_utils,
		max_distance,
		bIsSplash
	)

	local best_pos = multipoint:GetBestHitPoint()
	if not best_pos then
		return
	end

	local vecMins, vecMaxs = -weapon_info.vecCollisionMax, weapon_info.vecCollisionMax
	local trace = engine.TraceHull(vecHeadPos, best_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)

	if trace and trace.fraction < 1 then
		return
	end

	local angle = math_utils.PositionAngles(vecHeadPos, best_pos)

	local bAttack = false

	local bIsStickybombLauncher = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER

	if bIsBeggar then
		local clip = pWeapon:GetPropInt("LocalWeaponData", "m_iClip1")

		if clip < 1 and pTarget then
			-- keep holding IN_ATTACK while charging
			uCmd.buttons = uCmd.buttons | IN_ATTACK
		else
			-- release to fire
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK
			uCmd:SetViewAngles(angle:Unpack())
			uCmd:SetSendPacket(false)

			bAttack = true
		end
	elseif bIsHuntsman then
		if angle and pred_result.nChargeTime > 0.1 then -- smol charge required, just in case yk
			if gui.GetValue("auto shoot") == 1 and wep_utils.CanShoot() then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end

			-- release to shoot
			if (uCmd.buttons & IN_ATTACK) ~= 0 then
				uCmd.buttons = uCmd.buttons & ~IN_ATTACK
				uCmd:SetViewAngles(angle:Unpack())
				uCmd:SetSendPacket(false)

				bAttack = true
			end
		else
			-- keep charging
			if gui.GetValue("auto shoot") == 1 then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end
		end
	elseif bIsStickybombLauncher then
		if gui.GetValue("auto shoot") == 1 and wep_utils.CanShoot() then
			uCmd.buttons = uCmd.buttons | IN_ATTACK
		end

		-- release to fire
		if pred_result.nChargeTime > 0.1 then
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK
			uCmd:SetViewAngles(angle:Unpack())
			uCmd:SetSendPacket(false)

			bAttack = true
		end
	else
		--- epic sandvich aimbot
		--- (isso é uma gambiarra do caraio)
		if bIsSandvich then
			uCmd.buttons = uCmd.buttons | IN_ATTACK2
			uCmd:SetViewAngles(angle:Unpack())

			bAttack = true
		else
			if wep_utils.CanShoot() then
				if gui.GetValue("auto shoot") == 1 then
					uCmd.buttons = uCmd.buttons | IN_ATTACK
				end

				if (uCmd.buttons & IN_ATTACK) ~= 0 then
					uCmd:SetViewAngles(angle:Unpack())
					uCmd:SetSendPacket(false)

					bAttack = true
				end
			end
		end
	end

	if bAttack == true then
		displayed_time = globals.CurTime() + 1
		paths.player_path = pred_result.vecPlayerPath
		paths.proj_path = pred_result.vecProjPath
	end
end

--- Terminator (titaniummachine1) made this
---@param playerPos Vector3
---@param mins Vector3
---@param maxs Vector3
local function DrawPlayerHitbox(playerPos, mins, maxs)
	-- Calculate world space bounds
	local worldMins = playerPos + mins
	local worldMaxs = playerPos + maxs

	-- Calculate vertices of the AABB
	local vertices = {
		Vector3(worldMins.x, worldMins.y, worldMins.z), -- Bottom-back-left
		Vector3(worldMins.x, worldMaxs.y, worldMins.z), -- Bottom-front-left
		Vector3(worldMaxs.x, worldMaxs.y, worldMins.z), -- Bottom-front-right
		Vector3(worldMaxs.x, worldMins.y, worldMins.z), -- Bottom-back-right
		Vector3(worldMins.x, worldMins.y, worldMaxs.z), -- Top-back-left
		Vector3(worldMins.x, worldMaxs.y, worldMaxs.z), -- Top-front-left
		Vector3(worldMaxs.x, worldMaxs.y, worldMaxs.z), -- Top-front-right
		Vector3(worldMaxs.x, worldMins.y, worldMaxs.z), -- Top-back-right
	}

	-- Convert 3D coordinates to 2D screen coordinates
	for i, vertex in ipairs(vertices) do
		vertices[i] = client.WorldToScreen(vertex)
	end

	-- Draw lines between vertices to visualize the box
	if
		vertices[1]
		and vertices[2]
		and vertices[3]
		and vertices[4]
		and vertices[5]
		and vertices[6]
		and vertices[7]
		and vertices[8]
	then
		-- Draw front face
		draw.Line(vertices[1][1], vertices[1][2], vertices[2][1], vertices[2][2])
		draw.Line(vertices[2][1], vertices[2][2], vertices[3][1], vertices[3][2])
		draw.Line(vertices[3][1], vertices[3][2], vertices[4][1], vertices[4][2])
		draw.Line(vertices[4][1], vertices[4][2], vertices[1][1], vertices[1][2])

		-- Draw back face
		draw.Line(vertices[5][1], vertices[5][2], vertices[6][1], vertices[6][2])
		draw.Line(vertices[6][1], vertices[6][2], vertices[7][1], vertices[7][2])
		draw.Line(vertices[7][1], vertices[7][2], vertices[8][1], vertices[8][2])
		draw.Line(vertices[8][1], vertices[8][2], vertices[5][1], vertices[5][2])

		-- Draw connecting lines
		draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2])
		draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2])
		draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2])
		draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2])
	end
end

local function DrawPlayerPath()
	local lastpos = nil
	local lastpos_screen = nil

	for i, pos in pairs(paths.player_path) do
		if lastpos then
			local current = client.WorldToScreen(pos)
			if current and lastpos_screen then
				draw.Line(lastpos_screen[1], lastpos_screen[2], current[1], current[2])
			end
		end

		lastpos = pos
		lastpos_screen = client.WorldToScreen(lastpos)
	end
end

local function DrawProjPath()
	local lastpos = nil
	local lastpos_screen = nil

	for _, pos in pairs(paths.proj_path) do
		if lastpos then
			local current = client.WorldToScreen(pos.pos)
			if current and lastpos_screen then
				draw.Line(lastpos_screen[1], lastpos_screen[2], current[1], current[2])
			end
		end

		lastpos = pos.pos
		lastpos_screen = client.WorldToScreen(lastpos)
	end
end

local function Draw()
	if clientstate:GetNetChannel() == nil then
		return
	end

	if displayed_time < globals.CurTime() then
		paths.player_path = {}
		paths.proj_path = {}
		return
	end

	if settings.draw_player_path and paths.player_path then
		draw.Color(136, 192, 208, 255)
		DrawPlayerPath()

		if settings.draw_bounding_box then
			local pos = paths.player_path[#paths.player_path]
			DrawPlayerHitbox(pos, Vector3(-24.0, -24.0, 0.0), Vector3(24.0, 24.0, 82.0))
		end
	end

	if settings.draw_proj_path and paths.proj_path then
		draw.Color(235, 203, 139, 255)
		DrawProjPath()
	end
end

local function Unload()
	callbacks.Unregister("CreateMove", "ProjAimbot CreateMove")
	callbacks.Unregister("Draw", "ProjAimbot Draw")
	gui.SetValue("projectile aimbot", original_gui_value)
	paths = nil
	wep_utils = nil
	math_utils = nil
	player_sim = nil
	proj_sim = nil
	prediction = nil
	multipoint = nil
end

callbacks.Register("CreateMove", "ProjAimbot CreateMove", CreateMove)
callbacks.Register("Draw", "ProjAimbot Draw", Draw)
callbacks.Register("Unload", Unload)

printc(252, 186, 3, 255, string.format("Navet's Projectile Aimbot (v%s) loaded", version))
printc(166, 237, 255, 255, "Lmaobox's projectile aimbot will be turned off while this script is running")
