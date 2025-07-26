--[[
	NAVET'S PROEJECTILE AIMBOT
	made by navet
	Update: v6
	Source: https://github.com/uosq/lbox-projectile-aimbot
	
	This project would take way longer to start making
	if it weren't for them:
	Terminator - https://github.com/titaniummachine1
	GoodEvening - https://github.com/GoodEveningFellOff
--]]

---@diagnostic disable: cast-local-type

if engine.GetServerIP() == "" then
	printc(255, 0, 0, 255, "Gotta load the script in a match!")
	return
end

printc(186, 97, 255, 255, "The projectile aimbot is loading...")

local version = "6"

local settings = {
	enabled = true,
	autoshoot = true,
	fov = 30.0,
	max_sim_time = 2.0,
	draw_proj_path = true,
	draw_player_path = true,
	draw_bounding_box = true,
	draw_only = false,
	max_distance = 2048,
	multipointing = true,
	allow_aim_at_teammates = true,
	ping_compensation = true,
	min_priority = 0,
	splash = true,

	hitparts = {
		head = true,
		left_arm = true,
		right_arm = true,
		left_shoulder = true,
		right_shoulder = true,
		legs = true,
	},

	ents = {
		["aim players"] = true,
		["aim sentries"] = true,
		["aim dispensers"] = true,
		["aim teleporters"] = true,
	},

	psilent = true,

	ignore_conds = {
		cloaked = true,
		disguised = false,
		ubercharged = true,
		bonked = true,
		taunting = true,
		friends = true,
		bumper_karts = false,
		kritzkrieged = false,
		jarated = false,
		milked = false,
		vaccinator = false,
		ghost = true,
	},
}

local wep_utils = require("src.utils.weapon_utils")
assert(wep_utils, "[PROJ AIMBOT] Weapon utils module failed to load!")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Weapon utils loaded")

local math_utils = require("src.utils.math")
assert(math_utils, "[PROJ AIMBOT] Math utils module failed to load!")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Math utils loaded")

local ent_utils = require("src.utils.entity")
assert(ent_utils, "[PROJ AIMBOT] Entity utils module failed to load!")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Entity utils loaded")

local player_sim = require("src.simulation.player")
assert(player_sim, "[PROJ AIMBOT] Player prediction module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Player prediction module loaded")

local proj_sim = require("src.simulation.proj")
assert(proj_sim, "[PROJ AIMBOT] Projectile prediction module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Projectile prediction module loaded")

local prediction = require("src.prediction")
assert(prediction, "[PROJ AIMBOT] Prediction module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Mrediction module loaded")

local GetProjectileInformation = require("src.projectile_info")
assert(GetProjectileInformation, "[PROJ AIMBOT] GetProjectileInformation module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] GetProjectileInformation module loaded")

local menu = require("src.gui")
menu.init(settings, version)

local draw = draw
local entities = entities
local engine = engine
local E_TFCOND = E_TFCOND

local displayed_time = 0.0
local BEGGARS_BAZOOKA_INDEX = 730

--local PLAYER_MIN_HULL, PLAYER_MAX_HULL = Vector3(-24.0, -24.0, 0.0), Vector3(24.0, 24.0, 82.0)
local target_min_hull, target_max_hull = Vector3(), Vector3()

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

local function ShouldSkipPlayer(pPlayer)
	if pPlayer:InCond(E_TFCOND.TFCond_Cloaked) and settings.ignore_conds.cloaked then
		return true
	end

	if pPlayer:InCond(E_TFCOND.TFCond_Disguised) and settings.ignore_conds.disguised then
		return true
	end

	if pPlayer:InCond(E_TFCOND.TFCond_Taunting) and settings.ignore_conds.taunting then
		return true
	end

	if pPlayer:InCond(E_TFCOND.TFCond_Bonked) and settings.ignore_conds.bonked then
		return true
	end

	if pPlayer:InCond(E_TFCOND.TFCond_Ubercharged) and settings.ignore_conds.ubercharged then
		return true
	end

	if pPlayer:InCond(E_TFCOND.TFCond_Kritzkrieged) and settings.ignore_conds.kritzkrieged then
		return true
	end

	if pPlayer:InCond(E_TFCOND.TFCond_Jarated) and settings.ignore_conds.jarated then
		return true
	end

	if pPlayer:InCond(E_TFCOND.TFCond_Milked) and settings.ignore_conds.milked then
		return true
	end

	if pPlayer:InCond(E_TFCOND.TFCond_HalloweenGhostMode) and settings.ignore_conds.ghost then
		return true
	end

	if playerlist.GetPriority(pPlayer) < 0 and not settings.ignore_conds.friends then
		return true
	end

	if settings.min_priority > playerlist.GetPriority(pPlayer) then
		return true
	end

	if settings.ignore_conds.vaccinator then
		local resist_table = {
			TFCond_UberBulletResist = 58,
			TFCond_UberBlastResist = 59,
			TFCond_UberFireResist = 60,
			TFCond_SmallBulletResist = 61,
			TFCond_SmallBlastResist = 62,
			TFCond_SmallFireResist = 63,
		}

		for _, resist in pairs(resist_table) do
			if pPlayer:InCond(resist) then
				return true
			end
		end
	end

	return false
end

---@param players table<integer, Entity>
---@param pLocal Entity
---@param shootpos Vector3
---@param bAimTeamMate boolean -- Only aim at teammates if true, otherwise only aim at enemies
---@return PlayerInfo
local function GetClosestEntityToFov(pLocal, shootpos, players, bAimTeamMate)
	local best_target = {
		angle = nil,
		fov = settings.fov,
		index = nil,
		pos = nil,
	}

	local localTeam = pLocal:GetTeamNumber()
	local localPos = pLocal:GetAbsOrigin()
	local viewAngles = engine.GetViewAngles()

	local function loop_entity_class(class_table)
		for _, ent in pairs(class_table) do
			if ent:GetTeamNumber() == pLocal:GetTeamNumber() and not bAimTeamMate then
				goto continue
			end

			local origin = ent:GetAbsOrigin()
			local dist = (origin - localPos):Length2D()
			if dist > settings.max_distance then
				goto continue
			end

			local angleToEntity = math_utils.PositionAngles(shootpos, origin)
			local fov = math_utils.AngleFov(viewAngles, angleToEntity)
			if fov and fov < best_target.fov then
				best_target.angle = angleToEntity
				best_target.fov = fov
				best_target.index = ent:GetIndex()
				best_target.pos = origin

				target_max_hull = ent:GetMaxs()
				target_min_hull = ent:GetMins()
			end

			::continue::
		end
	end

	if settings.ents["aim teleporters"] then
		local teles = entities.FindByClass("CObjectTeleporter")
		loop_entity_class(teles)
	end

	if settings.ents["aim dispensers"] then
		loop_entity_class(entities.FindByClass("CObjectDispenser"))
	end

	if settings.ents["aim sentries"] then
		loop_entity_class(entities.FindByClass("CObjectSentrygun"))
	end

	if settings.ents["aim players"] then
		for _, player in pairs(players) do
			if player:IsDormant() or not player:IsAlive() or player:GetIndex() == pLocal:GetIndex() then
				goto continue
			end

			-- distance check
			local playerPos = player:GetAbsOrigin()
			local dist = (playerPos - localPos):Length()
			if dist > settings.max_distance then
				goto continue
			end

			if playerlist.GetPriority(player) < 0 and settings.ignore_conds.friends then
				goto continue
			end

			-- team check
			local isTeammate = player:GetTeamNumber() == localTeam
			if bAimTeamMate ~= isTeammate then
				goto continue
			end

			-- player conds
			if ShouldSkipPlayer(player) then
				goto continue
			end

			-- fov check
			local angleToPlayer = math_utils.PositionAngles(shootpos, playerPos)
			local fov = math_utils.AngleFov(viewAngles, angleToPlayer)
			if fov and fov < best_target.fov then
				best_target.angle = angleToPlayer
				best_target.fov = fov
				best_target.index = player:GetIndex()
				best_target.pos = playerPos

				target_max_hull = player:GetMaxs()
				target_min_hull = player:GetMins()
			end

			::continue::
		end
	end

	return best_target
end

---@param pLocal Entity
---@param pWeapon Entity
---@param bAimTeamMate boolean
---@param vecHeadPos Vector3
---@param netchannel NetChannel
---@param bDrawOnly boolean
---@param players table<integer, Entity>
---@param bIsHuntsman boolean
---@param weaponInfo WeaponInfo
---@return PredictionResult?, Entity?
local function ProcessPrediction(
	pLocal,
	pWeapon,
	vecHeadPos,
	bAimTeamMate,
	netchannel,
	bDrawOnly,
	players,
	bIsHuntsman,
	weaponInfo
)
	if
		not CanRun(pLocal, pWeapon, pWeapon:GetPropInt("m_iItemDefinitionIndex") == BEGGARS_BAZOOKA_INDEX, bDrawOnly)
	then
		return nil
	end

	if gui.GetValue("projectile aimbot") ~= "none" then
		gui.SetValue("projectile aimbot", "none")
	end

	local best_target = GetClosestEntityToFov(pLocal, vecHeadPos, players, bAimTeamMate)

	if not best_target.index then
		return nil
	end

	local pTarget = entities.GetByIndex(best_target.index)
	if not pTarget then
		return nil
	end

	-- weaponInfo is now passed as parameter, no need to recalculate
	local nlatency = settings.ping_compensation and 0
		or netchannel:GetLatency(E_Flows.FLOW_OUTGOING) + netchannel:GetLatency(E_Flows.FLOW_INCOMING)

	prediction:Set(
		pLocal,
		pWeapon,
		pTarget,
		weaponInfo,
		proj_sim,
		player_sim,
		math_utils,
		vecHeadPos,
		nlatency,
		settings,
		bIsHuntsman,
		bAimTeamMate,
		ent_utils
	)

	return prediction:Run(), pTarget
end

---@param uCmd UserCmd
local function CreateMove_Draw(uCmd)
	if not settings.enabled then
		return
	end

	local netChannel = clientstate.GetNetChannel()
	if not netChannel then
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

	if gui.GetValue("projectile aimbot") ~= "none" then
		gui.SetValue("projectile aimbot", "none")
	end

	local iWeaponID = pWeapon:GetWeaponID()
	local bAimAtTeamMates = false

	if iWeaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX then
		bAimAtTeamMates = true
	elseif iWeaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW then
		bAimAtTeamMates = true
	end

	bAimAtTeamMates = settings.allow_aim_at_teammates and bAimAtTeamMates or false

	local weaponInfo = GetProjectileInformation(pWeapon:GetPropInt("m_iItemDefinitionIndex"))
	local vecHeadPos = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")

	local vecWeaponFirePos = weaponInfo:GetFirePosition(
		pLocal,
		pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]"),
		engine.GetViewAngles(),
		pWeapon:IsViewModelFlipped()
	) + weaponInfo.m_vecAbsoluteOffset

	local bIsHuntsman = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW

	local pred_result, pTarget = ProcessPrediction(
		pLocal,
		pWeapon,
		vecHeadPos,
		bAimAtTeamMates,
		netChannel,
		settings.draw_only,
		players,
		bIsHuntsman,
		weaponInfo
	)

	if not pred_result or not pTarget then
		return
	end

	local function shouldHit(ent)
		if ent:GetIndex() == pLocal:GetIndex() then
			return false
		end
		return ent:GetTeamNumber() ~= pTarget:GetTeamNumber()
	end

	local vec_bestPos = pred_result.vecPos

	-- Use the muzzle position for the trace check instead of the head position
	local vecMins, vecMaxs = weaponInfo.m_vecMins, weaponInfo.m_vecMaxs
	local trace = engine.TraceHull(vecWeaponFirePos, vec_bestPos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)

	if trace and trace.fraction < 1 then
		return
	end

	displayed_time = globals.CurTime() + 1
	paths.player_path = pred_result.vecPlayerPath
	paths.proj_path =
		proj_sim.Run(pLocal, pWeapon, vecWeaponFirePos, pred_result.vecAimDir, pred_result.nTime, weaponInfo)
end

---@param uCmd UserCmd
local function CreateMove(uCmd)
	if not settings.enabled then
		return
	end

	if settings.draw_only then
		CreateMove_Draw(uCmd)
		return
	end

	local netChannel = clientstate.GetNetChannel()
	if not netChannel then
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

	if gui.GetValue("projectile aimbot") ~= "none" then
		gui.SetValue("projectile aimbot", "none")
	end

	local iWeaponID = pWeapon:GetWeaponID()
	local bAimAtTeamMates = false
	local bIsSandvich = false

	if iWeaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX then
		bAimAtTeamMates = true
		bIsSandvich = true
	elseif iWeaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW then
		bAimAtTeamMates = true
	end

	bAimAtTeamMates = settings.allow_aim_at_teammates and bAimAtTeamMates or false

	local weaponInfo = GetProjectileInformation(pWeapon:GetPropInt("m_iItemDefinitionIndex"))
	local vecHeadPos = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")

	local vecWeaponFirePos = weaponInfo:GetFirePosition(
		pLocal,
		pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]"),
		engine.GetViewAngles(),
		pWeapon:IsViewModelFlipped()
	) + weaponInfo.m_vecAbsoluteOffset

	local bIsHuntsman = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW

	local pred_result, pTarget = ProcessPrediction(
		pLocal,
		pWeapon,
		vecHeadPos,
		bAimAtTeamMates,
		netChannel,
		settings.draw_only,
		players,
		bIsHuntsman,
		weaponInfo
	)

	if not pred_result or not pTarget then
		return
	end

	local function shouldHit(ent)
		if ent:GetIndex() == pLocal:GetIndex() then
			return false
		end
		return ent:GetTeamNumber() ~= pTarget:GetTeamNumber()
	end

	local vec_bestPos = pred_result.vecPos

	-- Use the muzzle position for the trace check instead of the head position
	local vecMins, vecMaxs = weaponInfo.m_vecMins, weaponInfo.m_vecMaxs
	local trace = engine.TraceHull(vecWeaponFirePos, vec_bestPos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)

	if trace and trace.fraction < 1 then
		return
	end

	local angle = math_utils.DirectionToAngles(pred_result.vecAimDir)
	local bAttack = false
	local bIsStickybombLauncher = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER

	local function FireWeapon(isSandvich)
		uCmd:SetViewAngles(angle:Unpack())
		if not isSandvich and settings.psilent then
			uCmd:SetSendPacket(false)
		end

		return true
	end

	if bIsBeggar then
		local clip = pWeapon:GetPropInt("LocalWeaponData", "m_iClip1")
		if clip < 1 then
			uCmd.buttons = uCmd.buttons | IN_ATTACK -- hold to charge
		else
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
			bAttack = FireWeapon(false)
		end
	elseif bIsHuntsman then
		if pred_result.nChargeTime > 0.0 then
			if settings.autoshoot and wep_utils.CanShoot() then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end

			if (uCmd.buttons & IN_ATTACK) ~= 0 then
				uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
				bAttack = FireWeapon(false)
			end
		else
			if settings.autoshoot then
				uCmd.buttons = uCmd.buttons | IN_ATTACK -- hold to charge
			end
		end
	elseif bIsStickybombLauncher then
		if settings.autoshoot and wep_utils.CanShoot() then
			uCmd.buttons = uCmd.buttons | IN_ATTACK
		end

		if pred_result.nChargeTime > 0.0 then
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
			bAttack = FireWeapon(false)
		end
	elseif bIsSandvich then
		uCmd.buttons = uCmd.buttons | IN_ATTACK2
		bAttack = FireWeapon(true) -- special case for sandvich
	else -- generic weapons
		if wep_utils.CanShoot() then
			if settings.autoshoot then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end

			if (uCmd.buttons & IN_ATTACK) ~= 0 then
				bAttack = FireWeapon(false)
			end
		end
	end

	if bAttack == true then
		displayed_time = globals.CurTime() + 1
		paths.player_path = pred_result.vecPlayerPath
		paths.proj_path =
			proj_sim.Run(pLocal, pWeapon, vecWeaponFirePos, pred_result.vecAimDir, pred_result.nTime, weaponInfo)
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
	if displayed_time < globals.CurTime() then
		paths.player_path = {}
		paths.proj_path = {}
	end

	if not settings.enabled then
		return
	end

	if settings.draw_player_path and paths.player_path and #paths.player_path > 0 then
		draw.Color(136, 192, 208, 255)
		DrawPlayerPath()
	end

	if settings.draw_bounding_box then
		local pos = paths.player_path[#paths.player_path]
		if pos then
			DrawPlayerHitbox(pos, target_min_hull, target_max_hull)
		end
	end

	if settings.draw_proj_path and paths.proj_path and #paths.proj_path > 0 then
		draw.Color(235, 203, 139, 255)
		DrawProjPath()
	end
end

local function Unload()
	callbacks.Unregister("CreateMove", "ProjAimbot CreateMove")
	callbacks.Unregister("Draw", "ProjAimbot Draw")
	menu.unload()

	paths = nil
	wep_utils = nil
	math_utils = nil
	player_sim = nil
	proj_sim = nil
	prediction = nil

	gui.SetValue("projectile aimbot", original_gui_value)
end

callbacks.Register("CreateMove", "ProjAimbot CreateMove", CreateMove)
callbacks.Register("Draw", "ProjAimbot Draw", Draw)
callbacks.Register("Unload", Unload)

printc(252, 186, 3, 255, string.format("Navet's Projectile Aimbot (v%s) loaded", version))
printc(166, 237, 255, 255, "Lmaobox's projectile aimbot will be turned off while this script is running")

if gui.GetValue("projectile aimbot") ~= "none" then
	gui.SetValue("projectile aimbot", "none")
end
