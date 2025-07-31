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
--[[
	NAVET'S PROEJECTILE AIMBOT
	made by navet
	Update: v7-experimental
	Source: https://github.com/uosq/lbox-projectile-aimbot
	
	This project would take way longer to start making
	if it weren't for them:
	Terminator - https://github.com/titaniummachine1
	GoodEvening - https://github.com/GoodEveningFellOff
--]]

---@diagnostic disable: cast-local-type

--[[if engine.GetServerIP() == "" then
	printc(255, 0, 0, 255, "Gotta load the script in a match!")
	return
end]]

printc(186, 97, 255, 255, "The projectile aimbot is loading...")

local version = "7"

local settings = {
	enabled = true,
	autoshoot = true,
	fov = gui.GetValue("aim fov"),
	max_sim_time = 2.0,
	draw_proj_path = true,
	draw_player_path = true,
	draw_bounding_box = true,
	draw_only = false,
	max_distance = 2048,
	multipointing = false,
	allow_aim_at_teammates = true,
	ping_compensation = true,
	min_priority = 0,
	splash = true,

	hitparts = {
		head = true,
		feet = true, -- Used for bows (fallback) and explosives (primary if on ground)
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

	psilent = false,

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

local GetProjectileInformation = require("src.projectile_info")
assert(GetProjectileInformation, "[PROJ AIMBOT] GetProjectileInformation module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] GetProjectileInformation module loaded")

local menu = require("src.gui")
menu.init(settings, version)

local multipoint = require("src.multipoint")
assert(multipoint, "[PROJ AIMBOT] Multipoint module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Multipoint module loaded")

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
--local original_auto_reload = tostring(client.GetConVar("cl_autoreload"))

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

	---@type Entity?
	local bestEntity = nil

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
				bestEntity = ent
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
				bestEntity = player
			end

			::continue::
		end
	end

	if bestEntity then
		target_max_hull = bestEntity:GetMaxs()
		target_min_hull = bestEntity:GetMins()
		best_target.index = bestEntity:GetIndex()
		best_target.pos = bestEntity:GetAbsOrigin()
	end

	return best_target
end

---@param pWeapon Entity
local function GetCharge(pWeapon)
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

---@param uCmd UserCmd
local function CreateMove(uCmd)
	if not settings.enabled then
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

	local bIsBeggar = pWeapon:GetPropInt("m_iItemDefinitionIndex") == BEGGARS_BAZOOKA_INDEX
	if not CanRun(pLocal, pWeapon, bIsBeggar, false) then
		return
	end

	if gui.GetValue("projectile aimbot") ~= "none" then
		gui.SetValue("projectile aimbot", "none")
	end

	--- fuck you psilent
	--[[if tostring(client.GetConVar("cl_autoreload")) == "1" then
		client.SetConVar("cl_autoreload", "0")
	end]]

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

	local players = entities.FindByClass("CTFPlayer")

	local best_target = GetClosestEntityToFov(pLocal, vecHeadPos, players, bAimAtTeamMates)
	if not best_target.index then
		return nil
	end

	local pTarget = entities.GetByIndex(best_target.index)
	if not pTarget then
		return nil
	end

	local nlatency = settings.ping_compensation and 0
		or netchannel:GetLatency(E_Flows.FLOW_OUTGOING) + netchannel:GetLatency(E_Flows.FLOW_INCOMING)
	local flStepSize = pTarget:GetPropFloat("m_flStepSize")

	local vecTargetOrigin = pTarget:GetAbsOrigin()

	local vecWeaponFirePos =
		weaponInfo:GetFirePosition(pLocal, vecHeadPos, engine.GetViewAngles(), pWeapon:IsViewModelFlipped())

	local dist = (vecHeadPos - vecTargetOrigin):Length()
	if dist > settings.max_distance then
		return nil
	end

	local velocity_vector = weaponInfo:GetVelocity(0)
	local forward_speed = math.sqrt(velocity_vector.x ^ 2 + velocity_vector.y ^ 2)

	local detonate_time = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER and 0.7 or 0
	local travel_time_est = (vecTargetOrigin - vecHeadPos):Length() / forward_speed
	local choked_time = (clientstate:GetChokedCommands() / 66) * 1000
	local total_time = travel_time_est + nlatency + detonate_time + choked_time

	if total_time > settings.max_sim_time or total_time > weaponInfo.m_flLifetime then
		return nil
	end

	local time_ticks = (((total_time * 66.67) + 0.5) // 1)

	local player_positions = player_sim.Run(flStepSize, pTarget, vecTargetOrigin, time_ticks)
	if not player_positions then
		return nil
	end

	local predicted_target_pos = player_positions[#player_positions] or vecTargetOrigin

	local function shouldHit(ent)
		if ent:GetIndex() == pLocal:GetIndex() then
			return false
		end

		return ent:GetTeamNumber() ~= pTarget:GetTeamNumber()
	end

	local vecMins, vecMaxs = weaponInfo.m_vecMins, weaponInfo.m_vecMaxs
	local trace = engine.TraceHull(vecWeaponFirePos, predicted_target_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
	local is_visible = trace and trace.fraction >= 0.9

	local bIsHuntsman = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW

	if (not is_visible or bIsHuntsman) and settings.multipointing then
		local bSplashWeapon = pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_ROCKET
			or pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_REMOTE
			or pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_PRACTICE
			or pWeapon:GetWeaponProjectileType() == E_ProjectileType.TF_PROJECTILE_CANNONBALL

		multipoint:Set(
			pLocal,
			pWeapon,
			pTarget,
			bIsHuntsman,
			bAimAtTeamMates,
			vecHeadPos,
			predicted_target_pos,
			weaponInfo,
			math_utils,
			settings.max_distance,
			bSplashWeapon,
			ent_utils,
			settings
		)

		local best_multipoint = multipoint:GetBestHitPoint()
		if not best_multipoint then
			return
		end

		predicted_target_pos = best_multipoint
	end

	-- Recheck trace for final prediction
	trace = engine.TraceHull(vecWeaponFirePos, predicted_target_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
	if not trace or trace.fraction < 0.9 then
		return
	end

	local charge_time = GetCharge(pWeapon)
	local gravity = client.GetConVar("sv_gravity") * weaponInfo:GetGravity(charge_time)
	local angle = math_utils.SolveBallisticArc(vecHeadPos, predicted_target_pos, forward_speed, gravity)
	if not angle then
		return
	end

	local bAttack = false
	local bIsStickybombLauncher = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER

	if bIsBeggar then
		local clip = pWeapon:GetPropInt("LocalWeaponData", "m_iClip1")
		if clip < 1 then
			uCmd.buttons = uCmd.buttons | IN_ATTACK -- hold to charge
		else
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
			bAttack = true
		end
	elseif bIsHuntsman then
		if charge_time > 0.0 then
			if settings.autoshoot and wep_utils.CanShoot() then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end

			if (uCmd.buttons & IN_ATTACK) ~= 0 then
				uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
				bAttack = true
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

		if charge_time > 0.0 then
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
			bAttack = true
		end
	elseif bIsSandvich then
		uCmd.buttons = uCmd.buttons | IN_ATTACK2
		bAttack = true -- special case for sandvich
	else -- generic weapons
		if wep_utils.CanShoot() then
			if settings.autoshoot then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end

			if (uCmd.buttons & IN_ATTACK) ~= 0 then
				bAttack = true
			end
		end
	end

	if bAttack == true then
		local can_psilent = not bIsSandvich and settings.psilent

		if can_psilent then
			uCmd:SetSendPacket(false)
		end

		uCmd:SetViewAngles(angle:Unpack())
		displayed_time = globals.CurTime() + 1
		paths.player_path = player_positions
		paths.proj_path = proj_sim.Run(pLocal, pWeapon, vecWeaponFirePos, angle:Forward(), total_time, weaponInfo)
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
	if not settings.enabled then
		return
	end

	if displayed_time < globals.CurTime() then
		paths.player_path = {}
		paths.proj_path = {}
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

local function FrameStage(stage)
	if stage == E_ClientFrameStage.FRAME_NET_UPDATE_END then
		local players = entities.FindByClass("CTFPlayer")
		player_sim.RunBackground(players)
	end
end

local function Unload()
	callbacks.Unregister("CreateMove", "ProjAimbot CreateMove")
	callbacks.Unregister("Draw", "ProjAimbot Draw")
	callbacks.Unregister("FrameStageNotify", "ProjAimbot FrameStage")
	menu.unload()

	paths = nil
	wep_utils = nil
	math_utils = nil
	player_sim = nil
	proj_sim = nil

	gui.SetValue("projectile aimbot", original_gui_value)
	--client.SetConVar("cl_autoreload", original_auto_reload)
end

callbacks.Register("CreateMove", "ProjAimbot CreateMove", CreateMove)
callbacks.Register("Draw", "ProjAimbot Draw", Draw)
callbacks.Register("Unload", Unload)
callbacks.Register("FrameStageNotify", "ProjAimbot FrameStage", FrameStage)

printc(252, 186, 3, 255, string.format("Navet's Projectile Aimbot (v%s) loaded", version))
printc(166, 237, 255, 255, "Lmaobox's projectile aimbot will be turned off while this script is running")

if gui.GetValue("projectile aimbot") ~= "none" then
	gui.SetValue("projectile aimbot", "none")
end

end)
__bundle_register("src.multipoint", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Constants
local FL_DUCKING = 1

---@class Multipoint
---@field private pLocal Entity
---@field private pTarget Entity
---@field private pWeapon Entity
---@field private bIsHuntsman boolean
---@field private bIsSplash boolean
---@field private vecAimDir Vector3
---@field private vecPredictedPos Vector3
---@field private bAimTeamMate boolean
---@field private vecHeadPos Vector3
---@field private weapon_info WeaponInfo
---@field private math_utils MathLib
---@field private iMaxDistance integer
local multipoint = {}

local offset_multipliers = {
	splash = {
		{ "legs", { { 0, 0, 0 }, { 0, 0, 0.2 } } },
		{ "chest", { { 0, 0, 0.5 } } },
		{ "right_shoulder", { { 0.6, 0, 0.5 } } },
		{ "left_shoulder", { { -0.6, 0, 0.5 } } },
		{ "head", { { 0, 0, 0.9 } } },
	},
	huntsman = {
		{ "chest", { { 0, 0, 0.5 } } },
		{ "right_shoulder", { { 0.6, 0, 0.5 } } },
		{ "left_shoulder", { { -0.6, 0, 0.5 } } },
		{ "legs", { { 0, 0, 0.2 } } },
	},
	normal = {
		{ "chest", { { 0, 0, 0.5 } } },
		{ "right_shoulder", { { 0.6, 0, 0.5 } } },
		{ "left_shoulder", { { -0.6, 0, 0.5 } } },
		{ "head", { { 0, 0, 0.9 } } },
		{ "legs", { { 0, 0, 0.2 } } },
	},
}

-- Robust normalization function that handles edge cases
local function SafeNormalize(vec)
	if not vec then
		return nil
	end

	local length = vec:Length()
	if length < 0.001 then
		return nil -- Vector is too small to normalize
	end

	-- Try the built-in Normalize method first
	local normalized = vec:Normalize()
	if normalized then
		return normalized
	end

	-- Fallback: manual normalization
	local inv_length = 1.0 / length
	return Vector3(vec.x * inv_length, vec.y * inv_length, vec.z * inv_length)
end

---@return Vector3?
function multipoint:GetBestHitPoint()
	local maxs = self.pTarget:GetMaxs()
	local mins = self.pTarget:GetMins()

	local target_height = maxs.z - mins.z
	local target_width = maxs.x - mins.x
	local target_depth = maxs.y - mins.y

	local is_on_ground = (self.pTarget:GetPropInt("m_fFlags") & FL_ONGROUND) ~= 0
	local vecMins, vecMaxs = self.weapon_info.m_vecMins, self.weapon_info.m_vecMaxs

	local function shouldHit(ent)
		if not ent then
			return false
		end

		if ent:GetIndex() == self.pLocal:GetIndex() then
			return false
		end

		-- For rockets, we want to hit enemies (different team)
		-- For healing weapons, we want to hit teammates (same team)
		if self.bAimTeamMate then
			return ent:GetTeamNumber() == self.pTarget:GetTeamNumber()
		else
			return ent:GetTeamNumber() ~= self.pTarget:GetTeamNumber()
		end
	end

	-- Check if we can shoot from our position to the target point using the same logic as main code
	local function canShootToPoint(target_pos)
		if not target_pos then
			return false
		end

		-- Use the same logic as main code: calculate aim direction first, then check if we can hit
		local viewpos = self.pLocal:GetAbsOrigin() + self.pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")

		-- Calculate aim direction from viewpos to target
		local aim_dir = self.math_utils.NormalizeVector(target_pos - viewpos)
		if not aim_dir then
			return false
		end

		-- Get weapon offset and calculate weapon fire position using the same logic as main code
		local muzzle_offset = self.weapon_info:GetOffset(
			(self.pLocal:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0,
			self.pWeapon:IsViewModelFlipped()
		)
		local vecWeaponFirePos = viewpos
			+ self.math_utils.RotateOffsetAlongDirection(muzzle_offset, aim_dir)
			+ self.weapon_info.m_vecAbsoluteOffset

		-- Check if we can hit using TraceHull (same as main code)
		local trace = engine.TraceHull(vecWeaponFirePos, target_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
		return trace and trace.fraction >= 1
	end

	local head_pos = self.ent_utils.GetBones and self.ent_utils.GetBones(self.pTarget)[1] or nil
	local center_pos = self.vecPredictedPos + Vector3(0, 0, target_height / 2)
	local feet_pos = self.vecPredictedPos

	local fallback_points = {
		-- Bottom corners (feet/ground level, prioritized if feet are enabled)
		{ pos = Vector3(-target_width / 2, -target_depth / 2, 0), name = "bottom_corner_1" },
		{ pos = Vector3(target_width / 2, -target_depth / 2, 0), name = "bottom_corner_2" },
		{ pos = Vector3(-target_width / 2, target_depth / 2, 0), name = "bottom_corner_3" },
		{ pos = Vector3(target_width / 2, target_depth / 2, 0), name = "bottom_corner_4" },

		-- Mid-height corners (body level)
		{ pos = Vector3(-target_width / 2, -target_depth / 2, target_height / 2), name = "mid_corner_1" },
		{ pos = Vector3(target_width / 2, -target_depth / 2, target_height / 2), name = "mid_corner_2" },
		{ pos = Vector3(-target_width / 2, target_depth / 2, target_height / 2), name = "mid_corner_3" },
		{ pos = Vector3(target_width / 2, target_depth / 2, target_height / 2), name = "mid_corner_4" },

		-- Mid-points on edges (body level)
		{ pos = Vector3(0, -target_depth / 2, target_height / 2), name = "mid_front" },
		{ pos = Vector3(0, target_depth / 2, target_height / 2), name = "mid_back" },
		{ pos = Vector3(-target_width / 2, 0, target_height / 2), name = "mid_left" },
		{ pos = Vector3(target_width / 2, 0, target_height / 2), name = "mid_right" },

		-- Bottom mid-points (legs level)
		{ pos = Vector3(0, -target_depth / 2, 0), name = "bottom_front" },
		{ pos = Vector3(0, target_depth / 2, 0), name = "bottom_back" },
		{ pos = Vector3(-target_width / 2, 0, 0), name = "bottom_left" },
		{ pos = Vector3(target_width / 2, 0, 0), name = "bottom_right" },

		-- Top corners (head level)
		{ pos = Vector3(-target_width / 2, -target_depth / 2, target_height), name = "top_corner_1" },
		{ pos = Vector3(target_width / 2, -target_depth / 2, target_height), name = "top_corner_2" },
		{ pos = Vector3(-target_width / 2, target_depth / 2, target_height), name = "top_corner_3" },
		{ pos = Vector3(target_width / 2, target_depth / 2, target_height), name = "top_corner_4" },

		-- Top mid-points (head level)
		{ pos = Vector3(0, -target_depth / 2, target_height), name = "top_front" },
		{ pos = Vector3(0, target_depth / 2, target_height), name = "top_back" },
		{ pos = Vector3(-target_width / 2, 0, target_height), name = "top_left" },
		{ pos = Vector3(target_width / 2, 0, target_height), name = "top_right" },
	}

	-- 1. Bows/headshot weapons
	if self.bIsHuntsman then
		if self.settings.hitparts.head and head_pos and canShootToPoint(head_pos) then
			return head_pos
		end
		if canShootToPoint(center_pos) then
			return center_pos
		end
		if self.settings.hitparts.feet and is_on_ground and canShootToPoint(feet_pos) then
			return feet_pos
		end
		for _, point in ipairs(fallback_points) do
			local test_pos = self.vecPredictedPos + point.pos
			if canShootToPoint(test_pos) then
				return test_pos
			end
		end
		return nil
	end

	-- 2. Explosive projectiles: feet first if enabled and on ground
	if self.bIsSplash and self.settings.hitparts.feet and is_on_ground and canShootToPoint(feet_pos) then
		return feet_pos
	end
	-- Center next
	if canShootToPoint(center_pos) then
		return center_pos
	end

	-- Try fallback points
	for _, point in ipairs(fallback_points) do
		local test_pos = self.vecPredictedPos + point.pos

		if canShootToPoint(test_pos) then
			return test_pos
		end
	end

	-- Fallback: return center position if all else fails
	return center_pos
end

---@param pLocal Entity
---@param pWeapon Entity
---@param pTarget Entity
---@param bIsHuntsman boolean
---@param bAimTeamMate boolean
---@param vecHeadPos Vector3
---@param vecPredictedPos Vector3
---@param weapon_info WeaponInfo
---@param math_utils MathLib
---@param iMaxDistance integer
---@param bIsSplash boolean
---@param ent_utils table
---@param settings table
function multipoint:Set(
	pLocal,
	pWeapon,
	pTarget,
	bIsHuntsman,
	bAimTeamMate,
	vecHeadPos,
	vecPredictedPos,
	weapon_info,
	math_utils,
	iMaxDistance,
	bIsSplash,
	ent_utils,
	settings
)
	self.pLocal = pLocal
	self.pWeapon = pWeapon
	self.pTarget = pTarget
	self.bIsHuntsman = bIsHuntsman
	self.bAimTeamMate = bAimTeamMate
	self.vecHeadPos = vecHeadPos
	self.vecShootPos = vecHeadPos -- Use view position as base
	self.weapon_info = weapon_info
	self.math_utils = math_utils
	self.iMaxDistance = iMaxDistance
	self.vecPredictedPos = vecPredictedPos
	self.bIsSplash = bIsSplash
	self.ent_utils = ent_utils
	self.settings = settings
end

return multipoint

end)
__bundle_register("src.gui", function(require, _LOADED, __bundle_register, __bundle_modules)
local gui = {}

local menu = require("src.dependencies.nmenu")

local font = draw.CreateFont("TF2 BUILD", 16, 500)

---@param settings table
---@param version string
function gui.init(settings, version)
	local window = menu:make_window()
	window.width = 670
	window.height = 225

	local btn_starty = 10
	local component_width = 260
	local component_height = 25
	local gap = 5

	local function increase_y()
		btn_starty = btn_starty + component_height + gap
	end

	local function get_btn_y()
		local y = btn_starty
		increase_y()
		return y
	end

	do
		local w, h = draw.GetScreenSize()
		window.x = (w // 2) - (window.width // 2)
		window.y = (h // 2) - (window.height // 2)
	end

	window.font = font
	window.header = string.format("navet's projectile aimbot (v%s)", version)

	menu:make_tab("aimbot")

	local enabled_btn = menu:make_checkbox()
	enabled_btn.height = component_height
	enabled_btn.width = component_width
	enabled_btn.label = "enabled"
	enabled_btn.enabled = settings.enabled
	enabled_btn.x = 10
	enabled_btn.y = get_btn_y()

	enabled_btn.func = function()
		settings.enabled = not settings.enabled
		enabled_btn.enabled = settings.enabled
	end

	local autoshoot_btn = menu:make_checkbox()
	autoshoot_btn.height = component_height
	autoshoot_btn.width = component_width
	autoshoot_btn.label = "autoshoot"
	autoshoot_btn.enabled = settings.autoshoot
	autoshoot_btn.x = 10
	autoshoot_btn.y = get_btn_y()

	autoshoot_btn.func = function()
		settings.autoshoot = not settings.autoshoot
		autoshoot_btn.enabled = settings.autoshoot
	end

	local draw_proj_path_btn = menu:make_checkbox()
	draw_proj_path_btn.height = component_height
	draw_proj_path_btn.width = component_width
	draw_proj_path_btn.label = "draw projectile path"
	draw_proj_path_btn.enabled = settings.draw_proj_path
	draw_proj_path_btn.x = 10
	draw_proj_path_btn.y = get_btn_y()

	draw_proj_path_btn.func = function()
		settings.draw_proj_path = not settings.draw_proj_path
		draw_proj_path_btn.enabled = settings.draw_proj_path
	end

	local draw_player_path_btn = menu:make_checkbox()
	draw_player_path_btn.height = component_height
	draw_player_path_btn.width = component_width
	draw_player_path_btn.label = "draw player path"
	draw_player_path_btn.enabled = settings.draw_player_path
	draw_player_path_btn.x = 10
	draw_player_path_btn.y = get_btn_y()

	draw_player_path_btn.func = function()
		settings.draw_player_path = not settings.draw_player_path
		draw_player_path_btn.enabled = settings.draw_player_path
	end

	local draw_bounding_btn = menu:make_checkbox()
	draw_bounding_btn.height = component_height
	draw_bounding_btn.width = component_width
	draw_bounding_btn.label = "draw bounding box"
	draw_bounding_btn.enabled = settings.draw_bounding_box
	draw_bounding_btn.x = 10
	draw_bounding_btn.y = get_btn_y()

	draw_bounding_btn.func = function()
		settings.draw_bounding_box = not settings.draw_bounding_box
		draw_bounding_btn.enabled = settings.draw_bounding_box
	end

	local draw_only_btn = menu:make_checkbox()
	draw_only_btn.height = component_height
	draw_only_btn.width = component_width
	draw_only_btn.label = "draw only"
	draw_only_btn.enabled = settings.draw_only
	draw_only_btn.x = 10
	draw_only_btn.y = get_btn_y()

	draw_only_btn.func = function()
		settings.draw_only = not settings.draw_only
		draw_only_btn.enabled = settings.draw_only
	end

	local psilent_btn = menu:make_checkbox()
	psilent_btn.height = component_height
	psilent_btn.width = component_width
	psilent_btn.label = "silent+"
	psilent_btn.enabled = settings.psilent
	psilent_btn.x = 10
	psilent_btn.y = get_btn_y()

	psilent_btn.func = function()
		settings.psilent = not settings.psilent
		psilent_btn.enabled = settings.psilent
	end

	--- right side

	btn_starty = 10

	local multipoint_btn = menu:make_checkbox()
	multipoint_btn.height = component_height
	multipoint_btn.width = component_width
	multipoint_btn.label = "multipoint"
	multipoint_btn.enabled = settings.multipointing
	multipoint_btn.x = component_width + 20
	multipoint_btn.y = get_btn_y()

	multipoint_btn.func = function()
		settings.multipointing = not settings.multipointing
		multipoint_btn.enabled = settings.multipointing
	end

	local allow_aim_at_teammates_btn = menu:make_checkbox()
	allow_aim_at_teammates_btn.height = component_height
	allow_aim_at_teammates_btn.width = component_width
	allow_aim_at_teammates_btn.label = "allow aim at teammates"
	allow_aim_at_teammates_btn.enabled = settings.allow_aim_at_teammates
	allow_aim_at_teammates_btn.x = component_width + 20
	allow_aim_at_teammates_btn.y = get_btn_y()

	allow_aim_at_teammates_btn.func = function()
		settings.allow_aim_at_teammates = not settings.allow_aim_at_teammates
		allow_aim_at_teammates_btn.enabled = settings.allow_aim_at_teammates
	end

	local lag_comp_btn = menu:make_checkbox()
	lag_comp_btn.height = component_height
	lag_comp_btn.width = component_width
	lag_comp_btn.label = "ping compensation"
	lag_comp_btn.enabled = settings.ping_compensation
	lag_comp_btn.x = component_width + 20
	lag_comp_btn.y = get_btn_y()

	lag_comp_btn.func = function()
		settings.ping_compensation = not settings.ping_compensation
		lag_comp_btn.enabled = settings.ping_compensation
	end

	for name, enabled in pairs(settings.ents) do
		local btn = menu:make_checkbox()
		assert(btn, string.format("Button %s is nil!", name))

		btn.enabled = enabled
		btn.width = component_width
		btn.height = component_height
		btn.x = component_width + 20
		btn.y = get_btn_y()
		btn.label = name

		btn.func = function()
			settings.ents[name] = not settings.ents[name]
			btn.enabled = settings.ents[name]
		end
	end
	---

	menu:make_tab("misc")

	local sim_time_slider = menu:make_slider()
	assert(sim_time_slider, "sim time slider is nil somehow!")

	sim_time_slider.font = font
	sim_time_slider.height = 20
	sim_time_slider.label = "max sim time"
	sim_time_slider.max = 10
	sim_time_slider.min = 0.5
	sim_time_slider.value = settings.max_sim_time
	sim_time_slider.width = component_width * 2
	sim_time_slider.x = 10
	sim_time_slider.y = 25

	sim_time_slider.func = function()
		settings.max_sim_time = sim_time_slider.value
	end

	local max_distance_slider = menu:make_slider()
	assert(max_distance_slider, "max distance slider is nil somehow!")

	max_distance_slider.font = font
	max_distance_slider.height = 20
	max_distance_slider.label = "max distance"
	max_distance_slider.max = 4096
	max_distance_slider.min = 0
	max_distance_slider.value = settings.max_distance
	max_distance_slider.width = component_width * 2
	max_distance_slider.x = 10
	max_distance_slider.y = 70

	max_distance_slider.func = function()
		settings.max_distance = max_distance_slider.value
	end

	local fov_slider = menu:make_slider()
	assert(fov_slider, "fov slider is nil somehow!")

	fov_slider.font = font
	fov_slider.height = 20
	fov_slider.label = "fov"
	fov_slider.max = 180
	fov_slider.min = 0
	fov_slider.value = settings.fov
	fov_slider.width = component_width * 2
	fov_slider.x = 10
	fov_slider.y = 115

	fov_slider.func = function()
		settings.fov = fov_slider.value
	end

	local priotity_slider = menu:make_slider()
	assert(priotity_slider, "priotty slider is nil somehow!")

	priotity_slider.font = font
	priotity_slider.height = 20
	priotity_slider.label = "min priority"
	priotity_slider.max = 10
	priotity_slider.min = 0
	priotity_slider.value = 0
	priotity_slider.width = component_width * 2
	priotity_slider.x = 10
	priotity_slider.y = 160

	priotity_slider.func = function()
		settings.min_priority = priotity_slider.value // 1
	end

	menu:make_tab("conditions")

	btn_starty = 10

	local column = 1
	local left_column_count = 0
	local right_column_count = 0

	for name, enabled in pairs(settings.ignore_conds) do
		local btn = menu:make_checkbox()
		assert(btn, string.format("Button %s is nil!", name))

		btn.enabled = enabled
		btn.width = component_width
		btn.height = component_height
		btn.label = string.format("ignore %s", name)

		-- alternate between left and right columns
		if column == 1 then
			btn.x = 10
			btn.y = 10 + (left_column_count * (component_height + gap))
			left_column_count = left_column_count + 1
			column = 2
		else
			btn.x = component_width + 20
			btn.y = 10 + (right_column_count * (component_height + gap))
			right_column_count = right_column_count + 1
			column = 1
		end

		btn.func = function()
			settings.ignore_conds[name] = not settings.ignore_conds[name]
			btn.enabled = settings.ignore_conds[name]
		end
	end

	--local hitpoints_tab = menu:make_tab("hitpoints")
	menu:make_tab("hitpoints")

	column = 1
	left_column_count = 0
	right_column_count = 0

	for name, enabled in pairs(settings.hitparts) do
		local btn = menu:make_checkbox()
		assert(btn, string.format("Button %s is nil!", name))

		btn.enabled = enabled
		btn.width = component_width
		btn.height = component_height

		local label = string.gsub(name, "_", " ")

		btn.label = string.format("%s", label)

		-- alternate between left and right columns
		if column == 1 then
			btn.x = 10
			btn.y = 10 + (left_column_count * (component_height + gap))
			left_column_count = left_column_count + 1
			column = 2
		else
			btn.x = component_width + 20
			btn.y = 10 + (right_column_count * (component_height + gap))
			right_column_count = right_column_count + 1
			column = 1
		end

		btn.func = function()
			settings.hitparts[name] = not settings.hitparts[name]
			btn.enabled = settings.hitparts[name]
		end
	end

	--- happy now lsp?
	--[[if hitpoints_tab then
		menu:set_tab_draw_function(hitpoints_tab, function(current_window, current_tab, content_offset)
			local head_width = 20
			local centerx = (content_offset // 2) + current_window.x + (current_window.width // 2) - (head_width // 2)
			local y = window.y + (window.height // 2) - 50

			draw.Color(150, 255, 150, 255)
			draw.OutlinedCircle(centerx, y, head_width, 32)

			--- torso
			draw.Color(150, 255, 150, 255)
			draw.Line(centerx, y + head_width, centerx, y + 100)

			--- left leg
			draw.Color(150, 255, 150, 255)
			draw.Line(centerx, y + 100, centerx - 20, y + 150)

			--- right leg
			draw.Color(150, 255, 150, 255)
			draw.Line(centerx, y + 100, centerx + 20, y + 150)

			--- left arm
			draw.Color(255, 100, 100, 255)
			draw.Line(centerx, y + head_width, centerx - 55, y + 70)

			--- right arm
			draw.Line(centerx, y + head_width, centerx + 55, y + 70)
		end)
	end]]

	menu:register()
	printc(150, 255, 150, 255, "[PROJ AIMBOT] Menu loaded")
end

function gui.unload()
	menu.unload()
end

return gui

end)
__bundle_register("src.dependencies.nmenu", function(require, _LOADED, __bundle_register, __bundle_modules)
---@diagnostic disable: duplicate-set-field, undefined-field, redefined-local, cast-local-type

---@module "meta"

-- =============================================================================
-- CONSTANTS AND CONFIGURATION
-- =============================================================================

local OUTLINE_THICKNESS = 1
local TAB_BUTTON_WIDTH = 120
local TAB_BUTTON_HEIGHT = 25
local TAB_BUTTON_MARGIN = 2
local HEADER_SIZE = 25
local COMPONENT_TYPES = {
	BUTTON = 1,
	CHECKBOX = 2,
	SLIDER = 3,
	DROPDOWN = 4,
	LISTBOX = 5,
}

-- =============================================================================
-- MODULE STATE
-- =============================================================================

local draw_id = tostring(os.clock())
local font = draw.CreateFont("TF2 BUILD", 12, 1000)
local last_keypress_tick = 0

local deferred_dropdowns = {}

---@type table<integer, WINDOW>
local windows = {}

---@type WINDOW?
local current_window_context = nil

---@type BUTTON|CHECKBOX|SLIDER|DROPDOWN|LISTBOX
local current_component = nil

---@type SLIDER?
local dragging_slider = nil

---@type WINDOW?
local dragging_window = nil
local oldmx, oldmy = 0, 0
local dx, dy = 0, 0

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

local function clamp(value, min_val, max_val)
	return math.max(min_val, math.min(max_val, value))
end

local function is_mouse_inside(x1, y1, x2, y2)
	local mouse = input.GetMousePos()
	local mx, my = table.unpack(mouse)
	return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

local function get_current_window_tab()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return nil
	end

	-- If no tabs exist, return 0 (will be handled by make_new_component)
	if #window.tabs == 0 then
		return 0
	end

	return #window.tabs
end

local function get_content_area_offset()
	local window = current_window_context
	if not window or #window.tabs <= 1 then
		return 0
	end
	return TAB_BUTTON_WIDTH + (TAB_BUTTON_MARGIN * 2) -- add margin on both sides
end

local function get_new_component_index()
	local window = current_window_context
	assert(window, "Window context is nil!")

	-- If no tabs exist, create a default one
	if #window.tabs == 0 then
		table.insert(window.tabs, {
			name = "",
			components = {},
		})
	end

	return #window.tabs[#window.tabs].components + 1
end

local function make_new_component(component)
	local window = current_window_context
	if not window then
		return nil
	end

	-- If no tabs exist, create a default one
	if #window.tabs == 0 then
		table.insert(window.tabs, {
			name = "",
			components = {},
		})
	end

	local current_tab = get_current_window_tab()
	local index = get_new_component_index()

	window.tabs[current_tab].components[index] = component
	return window.tabs[current_tab].components[index]
end

-- =============================================================================
-- INPUT HANDLING
-- =============================================================================

local function handle_tab_button_click(window, tab_index)
	local tab_x = window.x + TAB_BUTTON_MARGIN -- Add margin to x position
	local tab_y = window.y + (tab_index - 1) * (TAB_BUTTON_HEIGHT + TAB_BUTTON_MARGIN)
	local tab_x2 = tab_x + TAB_BUTTON_WIDTH
	local tab_y2 = tab_y + TAB_BUTTON_HEIGHT

	if is_mouse_inside(tab_x, tab_y, tab_x2, tab_y2) then
		local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
		if state and tick > last_keypress_tick then
			-- Set active tab for THIS specific window (my stupid brain is stupid)
			window.active_tab_index = tab_index
			last_keypress_tick = tick
		end
		return true
	end
	return false
end

local function handle_mouse_click()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
	local content_offset = get_content_area_offset()

	local x1 = component.x + window.x + content_offset
	local y1 = component.y + window.y
	local x2 = component.x + component.width + window.x + content_offset
	local y2 = component.y + component.height + window.y

	if component.type == COMPONENT_TYPES.DROPDOWN then
		if is_mouse_inside(x1, y1, x2, y2) and state and tick > last_keypress_tick then
			component.expanded = not component.expanded
			last_keypress_tick = tick
			return
		end

		if component.expanded then
			table.insert(deferred_dropdowns, {
				component = component,
				window = window,
			})
		end
	elseif component.type == COMPONENT_TYPES.LISTBOX then
		local item_height = 20
		local content_offset = get_content_area_offset()
		local listbox_x = window.x + component.x + content_offset
		local listbox_y = window.y + component.y

		for i, item in ipairs(component.items) do
			local iy = listbox_y + (i - 1) * item_height
			if iy + item_height > listbox_y + component.height then
				break
			end
			if
				is_mouse_inside(listbox_x, iy, listbox_x + component.width, iy + item_height)
				and state
				and tick > last_keypress_tick
			then
				component.selected_index = i
				if component.func then
					component.func(i, item)
				end
				last_keypress_tick = tick
				break
			end
		end
	else
		if is_mouse_inside(x1, y1, x2, y2) then
			if component.func and state and tick > last_keypress_tick then
				---@diagnostic disable-next-line: missing-parameter
				component.func()
				last_keypress_tick = tick
			end

			if input.IsButtonDown(E_ButtonCode.MOUSE_LEFT) then
				draw.Color(76, 86, 106, 255)
			end
		end
	end
end

local function handle_mouse_hover()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local content_offset = get_content_area_offset()
	local x1 = component.x + window.x - OUTLINE_THICKNESS + content_offset
	local y1 = component.y + window.y - OUTLINE_THICKNESS
	local x2 = component.x + window.x + component.width + OUTLINE_THICKNESS + content_offset
	local y2 = component.y + window.y + component.height + OUTLINE_THICKNESS

	if is_mouse_inside(x1, y1, x2, y2) then
		draw.Color(67, 76, 94, 255)
	end
end

local function handle_slider_drag()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local content_offset = get_content_area_offset()

	local slider_x = component.x + window.x + content_offset
	local slider_y = component.y + window.y
	local slider_w = component.width
	local slider_h = component.height

	-- Check if mouse is over the slider area
	if is_mouse_inside(slider_x, slider_y, slider_x + slider_w, slider_y + slider_h) then
		-- Start dragging if mouse is pressed and no other slider is being dragged
		if input.IsButtonDown(E_ButtonCode.MOUSE_LEFT) and dragging_slider == nil then
			dragging_slider = component
		end
	end

	-- Handle dragging
	if dragging_slider == component and input.IsButtonDown(E_ButtonCode.MOUSE_LEFT) then
		local mouse = input.GetMousePos()
		local mx = mouse[1]

		-- Calculate new value based on mouse position
		local relative_x = mx - slider_x
		local progress = clamp(relative_x / slider_w, 0, 1)

		-- Update slider value
		component.value = component.min + progress * (component.max - component.min)

		-- Call callback if exists
		if component.func then
			---@diagnostic disable-next-line: missing-parameter
			component.func(component.value)
		end
	end

	-- Stop dragging when mouse is released
	if dragging_slider == component and not input.IsButtonDown(E_ButtonCode.MOUSE_LEFT) then
		dragging_slider = nil
	end
end

local function handle_window_drag()
	local window = current_window_context
	assert(window, "Window context is nil! WTF")

	if input.IsButtonReleased(E_ButtonCode.MOUSE_LEFT) and dragging_window == window then
		dragging_window = nil
	end

	local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)

	if
		not dragging_slider
		and state
		and tick > last_keypress_tick
		and is_mouse_inside(window.x, window.y - HEADER_SIZE, window.x + window.width, window.y)
	then
		last_keypress_tick = tick
		dragging_window = window
	end

	if dragging_window == window then
		window.x = window.x + dx
		window.y = window.y + dy
	end
end

-- =============================================================================
-- COMPONENT RENDERING
-- =============================================================================

local function draw_button()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local content_offset = get_content_area_offset()

	-- Draw outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(
		component.x + window.x - OUTLINE_THICKNESS + content_offset,
		component.y + window.y - OUTLINE_THICKNESS,
		component.x + component.width + window.x + OUTLINE_THICKNESS + content_offset,
		component.y + component.height + window.y + OUTLINE_THICKNESS
	)

	-- Default background color
	draw.Color(59, 66, 82, 255)

	handle_mouse_hover()
	handle_mouse_click()

	-- Draw button background
	draw.FilledRect(
		component.x + window.x + content_offset,
		component.y + window.y,
		component.x + component.width + window.x + content_offset,
		component.y + component.height + window.y
	)

	-- Draw button text
	if component.label and component.label ~= "" then
		draw.SetFont(component.font or font)
		local tw, th = draw.GetTextSize(component.label)

		draw.Color(236, 239, 244, 255)
		draw.Text(
			window.x + component.x + (component.width // 2) - (tw // 2) + content_offset,
			window.y + component.y + (component.height // 2) - (th // 2),
			component.label
		)
	end
end

local function draw_checkbox()
	local window = current_window_context
	assert(window, "Window context is nil!")

	local component = current_component
	local content_offset = get_content_area_offset()

	-- Draw outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(
		window.x + component.x - OUTLINE_THICKNESS + content_offset,
		window.y + component.y - OUTLINE_THICKNESS,
		window.x + component.x + component.width + OUTLINE_THICKNESS + content_offset,
		window.y + component.y + component.height + OUTLINE_THICKNESS
	)

	draw.Color(67, 76, 94, 255)

	handle_mouse_hover()
	handle_mouse_click()

	-- Draw checkbox background
	draw.FilledRect(
		window.x + component.x + content_offset,
		window.y + component.y,
		window.x + component.x + component.width + content_offset,
		window.y + component.y + component.height
	)

	-- Draw checkbox and label
	local box_width = component.width // 10
	local box_height = component.height // 2
	local box_x = window.x + component.x + 4 + content_offset
	local box_y = window.y + component.y + (component.height // 2) - (box_height // 2)

	-- Checkbox outline
	draw.Color(236, 239, 244, 255)
	draw.FilledRect(box_x - 1, box_y - 1, box_x + box_width + 1, box_y + box_height + 1)

	-- Checkbox background
	if component.enabled then
		draw.Color(163, 190, 140, 255)
	else
		draw.Color(191, 97, 106, 255)
	end
	draw.FilledRect(box_x, box_y, box_x + box_width, box_y + box_height)

	-- Draw label text
	draw.SetFont(window.font or font)
	local _, label_height = draw.GetTextSize(component.label)
	draw.Color(236, 239, 244, 255)
	draw.Text(box_x + box_width + 3, box_y + (box_height // 2) - (label_height // 2), component.label)
end

local function draw_tab_buttons(window)
	if #window.tabs <= 1 then
		return
	end

	for i, tab in ipairs(window.tabs) do
		local tab_x = window.x + TAB_BUTTON_MARGIN -- Add margin to x position
		local tab_y = window.y + (i - 1) * (TAB_BUTTON_HEIGHT + TAB_BUTTON_MARGIN)
		-- Use window-specific active tab index (or 1 if it's a single tab window (no tabs basically))
		local is_active = (i == (window.active_tab_index or 1))
		local is_hovered = handle_tab_button_click(window, i)

		-- Draw tab button outline
		--[[draw.Color(143, 188, 187, 255)
		draw.FilledRect(
			tab_x - OUTLINE_THICKNESS,
			tab_y - OUTLINE_THICKNESS,
			tab_x + TAB_BUTTON_WIDTH + OUTLINE_THICKNESS,
			tab_y + TAB_BUTTON_HEIGHT + OUTLINE_THICKNESS
		)]]

		-- Draw tab button background
		if is_active then
			draw.Color(76, 86, 106, 255) -- Active tab color
		elseif is_hovered then
			draw.Color(67, 76, 94, 255) -- Hovered tab color
		else
			draw.Color(59, 66, 82, 255) -- Normal tab color
		end

		draw.FilledRect(tab_x, tab_y, tab_x + TAB_BUTTON_WIDTH, tab_y + TAB_BUTTON_HEIGHT)

		-- Draw tab button text
		if tab.name and tab.name ~= "" then
			draw.SetFont(font)
			local tw, th = draw.GetTextSize(tab.name)
			draw.Color(236, 239, 244, 255)
			draw.Text(
				tab_x + (TAB_BUTTON_WIDTH // 2) - (tw // 2),
				tab_y + (TAB_BUTTON_HEIGHT // 2) - (th // 2),
				tab.name
			)
		end
	end
end

local function draw_slider()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local content_offset = get_content_area_offset()

	local slider_x = component.x + window.x + content_offset
	local slider_y = component.y + window.y
	local slider_w = component.width
	local slider_h = component.height

	-- Handle slider interaction
	handle_slider_drag()

	-- Calculate dimensions
	local knob_width = 10
	local track_height = 4
	local track_y = slider_y + (slider_h // 2) - (track_height // 2)

	-- Calculate knob position based on value
	local progress = (component.value - component.min) / (component.max - component.min)
	local knob_x = (slider_x + (progress * (slider_w - knob_width))) // 1

	-- Draw track background
	draw.Color(67, 76, 94, 255)
	draw.FilledRect(slider_x, track_y, slider_x + slider_w, track_y + track_height)

	-- Draw track fill (progress)
	draw.Color(129, 161, 193, 255)
	draw.FilledRect(slider_x, track_y, knob_x + (knob_width / 2), track_y + track_height)

	-- Draw knob outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(knob_x - 1, slider_y - 1, knob_x + knob_width + 1, slider_y + slider_h + 1)

	-- Draw knob
	if dragging_slider == component then
		draw.Color(76, 86, 106, 255) -- Dragging color
	elseif is_mouse_inside(knob_x, slider_y, knob_x + knob_width, slider_y + slider_h) then
		draw.Color(67, 76, 94, 255) -- Hover color
	else
		draw.Color(59, 66, 82, 255) -- Normal color
	end

	draw.FilledRect(knob_x, slider_y, knob_x + knob_width, slider_y + slider_h)

	-- Draw label if exists
	if component.label and component.label ~= "" then
		draw.SetFont(component.font or font)
		local tw, th = draw.GetTextSize(component.label)

		draw.Color(236, 239, 244, 255)
		draw.Text(slider_x, slider_y - th - 2, component.label)
	end

	-- Draw value text
	local value_text = string.format("%.1f", component.value)
	draw.SetFont(component.font or font)
	local value_tw, value_th = draw.GetTextSize(value_text)

	draw.Color(236, 239, 244, 255)
	draw.Text(slider_x + slider_w - value_tw, slider_y - value_th - 2, value_text)
end

local function draw_dropdown()
	local window = current_window_context
	assert(window, "Window context is nil!")

	local component = current_component
	local content_offset = get_content_area_offset()
	local x = window.x + component.x + content_offset
	local y = window.y + component.y

	draw.SetFont(component.font or font)
	local label_w, label_h = draw.GetTextSize(component.label)

	--- Uma puta gambiarra
	--- Mas to com preguiça de pensar em um jeito bom de fazer isso

	local height_offset = 0
	if component.label and component.label ~= "" then
		height_offset = label_h + 4
	end

	-- Draw main dropdown box outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(
		x - OUTLINE_THICKNESS,
		y - OUTLINE_THICKNESS - height_offset,
		x + component.width + OUTLINE_THICKNESS,
		y + component.height + OUTLINE_THICKNESS
	)

	--- Draw dropdown label
	draw.Color(236, 239, 244, 255)
	draw.Text(x + (component.width // 2) - (label_w // 2), y - (height_offset // 2) - (label_h // 2), component.label)

	-- Draw main dropdown box background
	draw.Color(59, 66, 82, 255)
	draw.FilledRect(x, y, x + component.width, y + component.height)

	-- Handle mouse clicks
	handle_mouse_click()

	-- Draw selected item text
	local selected = component.items[component.selected_index] or ""
	draw.SetFont(component.font or font)
	draw.Color(236, 239, 244, 255)
	local _, text_h = draw.GetTextSize(selected)
	draw.Text(x + 4, y + (component.height // 2) - (text_h // 2), selected)

	-- Draw dropdown arrow indicator
	draw.Color(236, 239, 244, 255)
	local arrow = component.expanded and "^" or "v" --- I wish i could use other characters, but i dont think TF2 BUILD supports emojis
	local arrow_w, arrow_h = draw.GetTextSize(arrow)
	draw.Text(x + component.width - arrow_w - 4, y + (component.height // 2) - (arrow_h // 2), arrow)

	-- Draw dropdown items if expanded
	if component.expanded then
		for i, item in ipairs(component.items) do
			local iy = y + component.height + (i - 1) * component.height

			-- Check if mouse is hovering over this item
			local is_hovered = is_mouse_inside(x, iy, x + component.width, iy + component.height)

			-- Draw item outline
			draw.Color(143, 188, 187, 255)
			draw.FilledRect(
				x - OUTLINE_THICKNESS,
				iy - OUTLINE_THICKNESS,
				x + component.width + OUTLINE_THICKNESS,
				iy + component.height + OUTLINE_THICKNESS
			)

			-- Draw item background
			if is_hovered then
				draw.Color(76, 86, 106, 255) -- Hover color
			else
				draw.Color(67, 76, 94, 255) -- Normal dropdown item color
			end
			draw.FilledRect(x, iy, x + component.width, iy + component.height)

			-- Draw item text
			draw.Color(236, 239, 244, 255)
			draw.Text(x + 4, iy + (component.height // 2) - (text_h // 2), item)

			local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
			if is_hovered and state and tick > last_keypress_tick then
				component.selected_index = i
				component.expanded = false
				if component.func then
					component.func(i, item)
				end
				last_keypress_tick = tick
				break
			end
		end
	end
end

local function draw_listbox()
	local window = current_window_context
	assert(window, "Window context is nil!")

	local component = current_component
	local content_offset = get_content_area_offset()
	local x = window.x + component.x + content_offset
	local y = window.y + component.y
	local item_height = 20
	local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)

	draw.Color(46, 52, 64, 255)
	draw.FilledRect(x, y, x + component.width, y + (item_height * #component.items))

	for i, item in ipairs(component.items) do
		local iy = y + (i - 1) * item_height
		if iy + item_height > y + component.height then
			break
		end

		local is_hovered = is_mouse_inside(x, iy, x + component.width, iy + item_height)
		local is_selected = (i == component.selected_index)

		if is_hovered then
			draw.Color(67, 76, 94, 255)
		elseif is_selected then
			draw.Color(76, 86, 106, 255)
		else
			draw.Color(59, 66, 82, 255)
		end

		if is_hovered and state and tick > last_keypress_tick then
			last_keypress_tick = tick
			component.selected_index = i
		end

		draw.FilledRect(x, iy, x + component.width, iy + item_height)
		draw.SetFont(component.font)
		draw.Color(236, 239, 244, 255)
		draw.Text(x + 4, iy + 2, item)
	end

	draw.Color(143, 188, 187, 255)
	draw.OutlinedRect(x, y, x + component.width, y + (item_height * #component.items))
end

local function draw_window()
	local window = current_window_context
	if not window then
		error("The window context is nil!")
		return
	end

	handle_window_drag()

	local content_offset = get_content_area_offset()

	-- Draw window outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(
		window.x - OUTLINE_THICKNESS,
		window.y - OUTLINE_THICKNESS - ((window.header and window.header ~= "") and HEADER_SIZE or 0),
		window.x + window.width + OUTLINE_THICKNESS,
		window.y + window.height + OUTLINE_THICKNESS
	)

	if window.header and window.header ~= "" then
		draw.SetFont(font)
		draw.Color(0, 0, 0, 255)

		local text_width, text_height = draw.GetTextSize(window.header)
		draw.Text(
			window.x + (window.width // 2) - (text_width // 2),
			window.y - (HEADER_SIZE // 2) - (text_height // 2),
			window.header
		)
	end

	-- Draw window background
	draw.Color(46, 52, 64, 255)
	draw.FilledRect(window.x, window.y, window.x + window.width, window.y + window.height)

	-- Draw tab buttons if multiple tabs exist
	draw_tab_buttons(window)

	-- Draw content area background (if tabs exist)
	if #window.tabs > 1 then
		draw.Color(41, 46, 57, 255)
		draw.FilledRect(window.x + content_offset, window.y, window.x + window.width, window.y + window.height)
	end

	-- Draw components from active tab (use window-specific active tab)
	local active_tab_index = window.active_tab_index or 1
	-- Reset active tab if it's out of bounds for this window
	if active_tab_index > #window.tabs then
		active_tab_index = 1
		window.active_tab_index = 1
	end

	local current_tab = window.tabs[active_tab_index] or window.tabs[1]
	if current_tab then
		for _, component in pairs(current_tab.components) do
			current_component = component

			if component.type == COMPONENT_TYPES.BUTTON then
				draw_button()
			elseif component.type == COMPONENT_TYPES.CHECKBOX then
				draw_checkbox()
			elseif component.type == COMPONENT_TYPES.SLIDER then
				draw_slider()
			elseif component.type == COMPONENT_TYPES.DROPDOWN then
				draw_dropdown()
			elseif component.type == COMPONENT_TYPES.LISTBOX then
				draw_listbox()
			else
				-- Fallback to button rendering for unknown types
				draw_button()
			end
		end
	end

	for _, dd in ipairs(deferred_dropdowns) do
		local component = dd.component
		local window = dd.window
		local content_offset = get_content_area_offset()
		local x = window.x + component.x + content_offset
		local y = window.y + component.y
		local _, text_h = draw.GetTextSize(component.label or "")

		for i, item in ipairs(component.items) do
			local iy = y + component.height + (i - 1) * component.height
			local is_hovered = is_mouse_inside(x, iy, x + component.width, iy + component.height)

			draw.Color(143, 188, 187, 255)
			draw.FilledRect(
				x - OUTLINE_THICKNESS,
				iy - OUTLINE_THICKNESS,
				x + component.width + OUTLINE_THICKNESS,
				iy + component.height + OUTLINE_THICKNESS
			)

			if is_hovered then
				draw.Color(76, 86, 106, 255)
			else
				draw.Color(67, 76, 94, 255)
			end
			draw.FilledRect(x, iy, x + component.width, iy + component.height)

			draw.Color(236, 239, 244, 255)
			draw.Text(x + 4, iy + (component.height // 2) - (text_h // 2), item)
		end
	end

	if current_tab.draw_func and type(current_tab.draw_func) == "function" then
		-- Pass useful context to the draw function
		current_tab.draw_func(window, current_tab, content_offset)
	end
end

local function draw_all_windows()
	if not gui.IsMenuOpen() then
		return
	end

	local mouse = input.GetMousePos()
	local mx, my = table.unpack(mouse)
	dx, dy = mx - oldmx, my - oldmy

	for _, window in ipairs(windows) do
		current_window_context = window
		draw_window()
	end

	oldmx, oldmy = mx, my
	deferred_dropdowns = {}
end

-- =============================================================================
-- COMPONENT FACTORY FUNCTIONS
-- =============================================================================

local function create_button_component()
	---@type BUTTON
	local button = {
		type = COMPONENT_TYPES.BUTTON,
		font = font,
		height = 0,
		width = 0,
		label = "",
		x = 0,
		y = 0,
	}
	return button
end

local function create_checkbox_component()
	---@type CHECKBOX
	local checkbox = {
		x = 0,
		y = 0,
		width = 0,
		height = 0,
		label = "",
		enabled = false,
		type = COMPONENT_TYPES.CHECKBOX,
		func = nil, -- Will be set after creation
	}

	-- Set the toggle function
	checkbox.func = function()
		checkbox.enabled = not checkbox.enabled
	end

	return checkbox
end

local function create_slider_component()
	---@type SLIDER
	local slider = {
		type = COMPONENT_TYPES.SLIDER,
		font = font,
		height = 20,
		width = 150,
		label = "",
		x = 0,
		y = 0,
		min = 0,
		max = 100,
		value = 50,
		func = nil, -- Callback function called when value changes
	}
	return slider
end

local function create_dropdown_component()
	---@type DROPDOWN
	local dropdown = {
		type = COMPONENT_TYPES.DROPDOWN,
		font = font,
		label = "",
		x = 0,
		y = 0,
		width = 150,
		height = 20,
		items = {}, -- List of strings
		selected_index = 1,
		expanded = false,
		func = nil,
	}
	return dropdown
end

local function create_listbox_component()
	---@type LISTBOX
	local listbox = {
		type = COMPONENT_TYPES.LISTBOX,
		font = font,
		label = "",
		x = 0,
		y = 0,
		width = 150,
		height = 100,
		items = {},
		selected_index = 1,
		func = nil,
	}
	return listbox
end

-- =============================================================================
-- COMPONENT SIZE CALCULATION
-- =============================================================================

local function calculate_component_sizes()
	for _, window in ipairs(windows) do
		for _, tab in ipairs(window.tabs) do
			for _, component in ipairs(tab.components) do
				if component.width == 0 and component.height == 0 then
					if component.label and component.label ~= "" then
						draw.SetFont(window.font or font)
						local tw, th = draw.GetTextSize(component.label)
						component.width = tw + 20
						component.height = th + 5
					else
						component.width = 100
						component.height = 20
					end
				end
			end
		end
	end
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

---@class MENU
local menu = {}

---@return WINDOW
function menu:make_window()
	---@type WINDOW
	local window = {
		x = 0,
		y = 0,
		width = 0,
		height = 0,
		tabs = {},
		active_tab_index = 1, -- Each window now has its own active tab index
	}

	table.insert(windows, window)
	current_window_context = windows[#windows]
	return windows[#windows]
end

---@param name string?
---@return integer? Returns the tab index relative to the current window context
function menu:make_tab(name)
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return nil
	end

	local new_tab = {
		name = name or "",
		components = {},
	}

	table.insert(window.tabs, new_tab)
	return #window.tabs
end

---@return BUTTON?
function menu:make_button()
	local window = current_window_context
	if not window then
		error("The window context is nil!")
		return nil
	end

	local button = create_button_component()
	return make_new_component(button)
end

---@return CHECKBOX?
function menu:make_checkbox()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return nil
	end

	local checkbox = create_checkbox_component()
	return make_new_component(checkbox)
end

---@return SLIDER?
function menu:make_slider()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return nil
	end

	local slider = create_slider_component()
	return make_new_component(slider)
end

---@return DROPDOWN?
function menu:make_dropdown()
	if not current_window_context then
		return nil
	end
	local dropdown = create_dropdown_component()
	return make_new_component(dropdown)
end

---@return LISTBOX?
function menu:make_listbox()
	if not current_window_context then
		return nil
	end
	local listbox = create_listbox_component()
	return make_new_component(listbox)
end

function menu:register()
	calculate_component_sizes() --- if we have any component with 0 width & height so they dont waste pc resources drawing nothing
	callbacks.Register("Draw", draw_id, draw_all_windows)
end

---@param tab_index integer
---@param draw_func function
function menu:set_tab_draw_function(tab_index, draw_func)
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	if tab_index > 0 and tab_index <= #window.tabs then
		window.tabs[tab_index].draw_func = draw_func
	else
		error("Invalid tab index: " .. tostring(tab_index))
	end
end

function menu.unload()
	menu = nil
	font = nil
	package.loaded["nmenu"] = nil
	input.SetMouseInputEnabled(false)
	callbacks.Unregister("Draw", draw_id)
end

return menu

end)
__bundle_register("src.projectile_info", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
    This is a port of the GetProjectileInformation function
    from GoodEvening's Visualize Arc Trajectories
    
    His Github: https://github.com/GoodEveningFellOff
    Source: https://github.com/GoodEveningFellOff/Lmaobox-Scripts/blob/main/Visualize%20Arc%20Trajectories/dev.lua
--]]

local TRACE_HULL = engine.TraceHull
local CLAMP = function(a, b, c)
	return (a < b) and b or (a > c) and c or a
end
local VEC_ROT = function(a, b)
	return (b:Forward() * a.x) + (b:Right() * a.y) + (b:Up() * a.z)
end

local aProjectileInfo = {}
local aItemDefinitions = {}

local PROJECTILE_TYPE_BASIC = 0
local PROJECTILE_TYPE_PSEUDO = 1
local PROJECTILE_TYPE_SIMUL = 2

local COLLISION_NORMAL = 0
local COLLISION_HEAL_TEAMMATES = 1
local COLLISION_HEAL_BUILDINGS = 2
local COLLISION_HEAL_HURT = 3
local COLLISION_NONE = 4

local function AppendItemDefinitions(iType, ...)
	for _, i in pairs({ ... }) do
		aItemDefinitions[i] = iType
	end
end

---@return WeaponInfo
function GetProjectileInformation(i)
	return aProjectileInfo[aItemDefinitions[i or 0]]
end

---@return WeaponInfo?
local function DefineProjectileDefinition(tbl)
	return {
		m_iType = PROJECTILE_TYPE_BASIC,
		m_vecOffset = tbl.vecOffset or Vector3(0, 0, 0),
		m_vecAbsoluteOffset = tbl.vecAbsoluteOffset or Vector3(0, 0, 0),
		m_vecAngleOffset = tbl.vecAngleOffset or Vector3(0, 0, 0),
		m_vecVelocity = tbl.vecVelocity or Vector3(0, 0, 0),
		m_vecAngularVelocity = tbl.vecAngularVelocity or Vector3(0, 0, 0),
		m_vecMins = tbl.vecMins or (not tbl.vecMaxs) and Vector3(0, 0, 0) or -tbl.vecMaxs,
		m_vecMaxs = tbl.vecMaxs or (not tbl.vecMins) and Vector3(0, 0, 0) or -tbl.vecMins,
		m_flGravity = tbl.flGravity or 0.001,
		m_flDrag = tbl.flDrag or 0,
		m_flElasticity = tbl.flElasticity or 0,
		m_iAlignDistance = tbl.iAlignDistance or 0,
		m_iTraceMask = tbl.iTraceMask or 33570827, -- MASK_SOLID
		m_iCollisionType = tbl.iCollisionType or COLLISION_NORMAL,
		m_flCollideWithTeammatesDelay = tbl.flCollideWithTeammatesDelay or 0.25,
		m_flLifetime = tbl.flLifetime or 99999,
		m_flDamageRadius = tbl.flDamageRadius or 0,
		m_bStopOnHittingEnemy = tbl.bStopOnHittingEnemy ~= false,
		m_bCharges = tbl.bCharges or false,
		m_sModelName = tbl.sModelName or "",

		GetOffset = not tbl.GetOffset
				and function(self, bDucking, bIsFlipped)
					return bIsFlipped and Vector3(self.m_vecOffset.x, -self.m_vecOffset.y, self.m_vecOffset.z)
						or self.m_vecOffset
				end
			or tbl.GetOffset, -- self, bDucking, bIsFlipped

		GetAngleOffset = (not tbl.GetAngleOffset) and function(self, flChargeBeginTime)
			return self.m_vecAngleOffset
		end or tbl.GetAngleOffset, -- self, flChargeBeginTime

		GetFirePosition = tbl.GetFirePosition or function(self, pLocalPlayer, vecLocalView, vecViewAngles, bIsFlipped)
			local resultTrace = TRACE_HULL(
				vecLocalView,
				vecLocalView
					+ VEC_ROT(
						self:GetOffset((pLocalPlayer:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0, bIsFlipped),
						vecViewAngles
					),
				-Vector3(8, 8, 8),
				Vector3(8, 8, 8),
				100679691
			) -- MASK_SOLID_BRUSHONLY

			return (not resultTrace.startsolid) and resultTrace.endpos or nil
		end,

		GetVelocity = (not tbl.GetVelocity) and function(self, ...)
			return self.m_vecVelocity
		end or tbl.GetVelocity, -- self, flChargeBeginTime

		GetAngularVelocity = (not tbl.GetAngularVelocity) and function(self, ...)
			return self.m_vecAngularVelocity
		end or tbl.GetAngularVelocity, -- self, flChargeBeginTime

		GetGravity = (not tbl.GetGravity) and function(self, ...)
			return self.m_flGravity
		end or tbl.GetGravity, -- self, flChargeBeginTime

		GetLifetime = (not tbl.GetLifetime) and function(self, ...)
			return self.m_flLifetime
		end or tbl.GetLifetime, -- self, flChargeBeginTime
	}
end

local function DefineBasicProjectileDefinition(tbl)
	local stReturned = DefineProjectileDefinition(tbl)
	stReturned.m_iType = PROJECTILE_TYPE_BASIC

	return stReturned
end

local function DefinePseudoProjectileDefinition(tbl)
	local stReturned = DefineProjectileDefinition(tbl)
	stReturned.m_iType = PROJECTILE_TYPE_PSEUDO

	return stReturned
end

local function DefineSimulProjectileDefinition(tbl)
	local stReturned = DefineProjectileDefinition(tbl)
	stReturned.m_iType = PROJECTILE_TYPE_SIMUL

	return stReturned
end

local function DefineDerivedProjectileDefinition(def, tbl)
	local stReturned = {}
	for k, v in pairs(def) do
		stReturned[k] = v
	end
	for k, v in pairs(tbl) do
		stReturned[((type(v) ~= "function") and "m_" or "") .. k] = v
	end

	if not tbl.GetOffset and tbl.vecOffset then
		stReturned.GetOffset = function(self, bDucking, bIsFlipped)
			return bIsFlipped and Vector3(self.m_vecOffset.x, -self.m_vecOffset.y, self.m_vecOffset.z)
				or self.m_vecOffset
		end
	end

	if not tbl.GetAngleOffset and tbl.vecAngleOffset then
		stReturned.GetAngleOffset = function(self, flChargeBeginTime)
			return self.m_vecAngleOffset
		end
	end

	if not tbl.GetVelocity and tbl.vecVelocity then
		stReturned.GetVelocity = function(self, ...)
			return self.m_vecVelocity
		end
	end

	if not tbl.GetAngularVelocity and tbl.vecAngularVelocity then
		stReturned.GetAngularVelocity = function(self, ...)
			return self.m_vecAngularVelocity
		end
	end

	if not tbl.GetGravity and tbl.flGravity then
		stReturned.GetGravity = function(self, ...)
			return self.m_flGravity
		end
	end

	if not tbl.GetLifetime and tbl.flLifetime then
		stReturned.GetLifetime = function(self, ...)
			return self.m_flLifetime
		end
	end

	return stReturned
end

AppendItemDefinitions(
	1,
	18, -- Rocket Launcher
	205, -- Rocket Launcher (Renamed/Strange)
	228, -- The Black Box
	658, -- Festive Rocket Launcher
	800, -- Silver Botkiller Rocket Launcher Mk.I
	809, -- Gold Botkiller Rocket Launcher Mk.I
	889, -- Rust Botkiller Rocket Launcher Mk.I
	898, -- Blood Botkiller Rocket Launcher Mk.I
	907, -- Carbonado Botkiller Rocket Launcher Mk.I
	916, -- Diamond Botkiller Rocket Launcher Mk.I
	965, -- Silver Botkiller Rocket Launcher Mk.II
	974, -- Gold Botkiller Rocket Launcher Mk.II
	1085, -- Festive Black Box
	15006, -- Woodland Warrior
	15014, -- Sand Cannon
	15028, -- American Pastoral
	15043, -- Smalltown Bringdown
	15052, -- Shell Shocker
	15057, -- Aqua Marine
	15081, -- Autumn
	15104, -- Blue Mew
	15105, -- Brain Candy
	15129, -- Coffin Nail
	15130, -- High Roller's
	15150 -- Warhawk
)
aProjectileInfo[1] = DefineBasicProjectileDefinition({
	vecVelocity = Vector3(1100, 0, 0),
	vecMaxs = Vector3(0, 0, 0),
	iAlignDistance = 2000,
	flDamageRadius = 146,

	GetOffset = function(self, bDucking, bIsFlipped)
		return Vector3(23.5, 12 * (bIsFlipped and -1 or 1), bDucking and 8 or -3)
	end,
})

AppendItemDefinitions(
	2,
	237 -- Rocket Jumper
)
aProjectileInfo[2] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	iCollisionType = COLLISION_NONE,
})

AppendItemDefinitions(
	3,
	730 -- The Beggar's Bazooka
)
aProjectileInfo[3] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	flDamageRadius = 116.8,
})

AppendItemDefinitions(
	4,
	1104 -- The Air Strike
)
aProjectileInfo[4] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	flDamageRadius = 131.4,
})

AppendItemDefinitions(
	5,
	127 -- The Direct Hit
)
aProjectileInfo[5] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	vecVelocity = Vector3(2000, 0, 0),
	flDamageRadius = 44,
})

AppendItemDefinitions(
	6,
	414 -- The Liberty Launcher
)
aProjectileInfo[6] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	vecVelocity = Vector3(1550, 0, 0),
})

AppendItemDefinitions(
	7,
	513 -- The Original
)
aProjectileInfo[7] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	GetOffset = function(self, bDucking)
		return Vector3(23.5, 0, bDucking and 8 or -3)
	end,
})

-- https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/tf/tf_weapon_dragons_fury.cpp
AppendItemDefinitions(
	8,
	1178 -- Dragon's Fury
)
aProjectileInfo[8] = DefineBasicProjectileDefinition({
	vecVelocity = Vector3(600, 0, 0),
	vecMaxs = Vector3(1, 1, 1),

	GetOffset = function(self, bDucking, bIsFlipped)
		return Vector3(3, 7, -9)
	end,
})

AppendItemDefinitions(
	9,
	442 -- The Righteous Bison
)
aProjectileInfo[9] = DefineBasicProjectileDefinition({
	vecVelocity = Vector3(1200, 0, 0),
	vecMaxs = Vector3(1, 1, 1),
	iAlignDistance = 2000,

	GetOffset = function(self, bDucking, bIsFlipped)
		return Vector3(23.5, -8 * (bIsFlipped and -1 or 1), bDucking and 8 or -3)
	end,
})

AppendItemDefinitions(
	10,
	20, -- Stickybomb Launcher
	207, -- Stickybomb Launcher (Renamed/Strange)
	661, -- Festive Stickybomb Launcher
	797, -- Silver Botkiller Stickybomb Launcher Mk.I
	806, -- Gold Botkiller Stickybomb Launcher Mk.I
	886, -- Rust Botkiller Stickybomb Launcher Mk.I
	895, -- Blood Botkiller Stickybomb Launcher Mk.I
	904, -- Carbonado Botkiller Stickybomb Launcher Mk.I
	913, -- Diamond Botkiller Stickybomb Launcher Mk.I
	962, -- Silver Botkiller Stickybomb Launcher Mk.II
	971, -- Gold Botkiller Stickybomb Launcher Mk.II
	15009, -- Sudden Flurry
	15012, -- Carpet Bomber
	15024, -- Blasted Bombardier
	15038, -- Rooftop Wrangler
	15045, -- Liquid Asset
	15048, -- Pink Elephant
	15082, -- Autumn
	15083, -- Pumpkin Patch
	15084, -- Macabre Web
	15113, -- Sweet Dreams
	15137, -- Coffin Nail
	15138, -- Dressed to Kill
	15155 -- Blitzkrieg
)
aProjectileInfo[10] = DefineSimulProjectileDefinition({
	vecOffset = Vector3(16, 8, -6),
	vecAngularVelocity = Vector3(600, 0, 0),
	vecMaxs = Vector3(3.5, 3.5, 3.5),
	bCharges = true,
	flDamageRadius = 150,
	sModelName = "models/weapons/w_models/w_stickybomb.mdl",
	flGravity = 0.25,

	GetVelocity = function(self, flChargeBeginTime)
		return Vector3(900 + CLAMP(flChargeBeginTime / 4, 0, 1) * 1500, 0, 200)
	end,
})

AppendItemDefinitions(
	11,
	1150 -- The Quickiebomb Launcher
)
aProjectileInfo[11] = DefineDerivedProjectileDefinition(aProjectileInfo[10], {
	sModelName = "models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl",
	flGravity = 0.25,
	GetVelocity = function(self, flChargeBeginTime)
		return Vector3(900 + CLAMP(flChargeBeginTime / 1.2, 0, 1) * 1500, 0, 200)
	end,
})

AppendItemDefinitions(
	12,
	130 -- The Scottish Resistance
)
aProjectileInfo[12] = DefineDerivedProjectileDefinition(aProjectileInfo[10], {
	sModelName = "models/weapons/w_models/w_stickybomb_d.mdl",
	flGravity = 0.25,
})

AppendItemDefinitions(
	13,
	265 -- Sticky Jumper
)
aProjectileInfo[13] = DefineDerivedProjectileDefinition(aProjectileInfo[12], {
	iCollisionType = COLLISION_NONE,
	flGravity = 0.25,
})

AppendItemDefinitions(
	14,
	19, -- Grenade Launcher
	206, -- Grenade Launcher (Renamed/Strange)
	1007, -- Festive Grenade Launcher
	15077, -- Autumn
	15079, -- Macabre Web
	15091, -- Rainbow
	15092, -- Sweet Dreams
	15116, -- Coffin Nail
	15117, -- Top Shelf
	15142, -- Warhawk
	15158 -- Butcher Bird
)
aProjectileInfo[14] = DefineSimulProjectileDefinition({
	vecOffset = Vector3(16, 8, -6),
	vecVelocity = Vector3(1200, 0, 200),
	vecAngularVelocity = Vector3(600, 0, 0),
	flGravity = 0.25,
	vecMaxs = Vector3(2, 2, 2),
	flElasticity = 0.45,
	flLifetime = 2.175,
	flDamageRadius = 146,
	sModelName = "models/weapons/w_models/w_grenade_grenadelauncher.mdl",
})

AppendItemDefinitions(
	15,
	1151 -- The Iron Bomber
)
aProjectileInfo[15] = DefineDerivedProjectileDefinition(aProjectileInfo[14], {
	flElasticity = 0.09,
	flLifetime = 1.6,
	flDamageRadius = 124,
})

AppendItemDefinitions(
	16,
	308 -- The Loch-n-Load
)
aProjectileInfo[16] = DefineDerivedProjectileDefinition(aProjectileInfo[14], {
	iType = PROJECTILE_TYPE_PSEUDO,
	vecVelocity = Vector3(1500, 0, 200),
	flDrag = 0.225,
	flLifetime = 2.3,
	flDamageRadius = 0,
})

AppendItemDefinitions(
	17,
	996 -- The Loose Cannon
)
aProjectileInfo[17] = DefineDerivedProjectileDefinition(aProjectileInfo[14], {
	vecVelocity = Vector3(1440, 0, 200),
	vecMaxs = Vector3(6, 6, 6),
	bStopOnHittingEnemy = false,
	bCharges = true,
	sModelName = "models/weapons/w_models/w_cannonball.mdl",

	GetLifetime = function(self, flChargeBeginTime)
		return 1 * flChargeBeginTime
	end,
})

AppendItemDefinitions(
	18,
	56, -- The Huntsman
	1005, -- Festive Huntsman
	1092 -- The Fortified Compound
)
aProjectileInfo[18] = DefinePseudoProjectileDefinition({
	vecOffset = Vector3(23.5, -8, -3),
	vecMaxs = Vector3(0, 0, 0),
	iAlignDistance = 2000,
	bCharges = true,

	GetVelocity = function(self, flChargeBeginTime)
		return Vector3(1800 + CLAMP(flChargeBeginTime, 0, 1) * 800, 0, 0)
	end,

	GetGravity = function(self, flChargeBeginTime)
		return 0.5 - CLAMP(flChargeBeginTime, 0, 1) * 0.4
	end,
})

AppendItemDefinitions(
	19,
	39, -- The Flare Gun
	351, -- The Detonator
	595, -- The Manmelter
	1081 -- Festive Flare Gun
)
aProjectileInfo[19] = DefinePseudoProjectileDefinition({
	vecVelocity = Vector3(2000, 0, 0),
	vecMaxs = Vector3(0, 0, 0),
	flGravity = 0.3,
	iAlignDistance = 2000,
	flCollideWithTeammatesDelay = 0.25,

	GetOffset = function(self, bDucking, bIsFlipped)
		return Vector3(23.5, 12 * (bIsFlipped and -1 or 1), bDucking and 8 or -3)
	end,
})

AppendItemDefinitions(
	20,
	740 -- The Scorch Shot
)
aProjectileInfo[20] = DefineDerivedProjectileDefinition(aProjectileInfo[19], {
	flDamageRadius = 110,
})

AppendItemDefinitions(
	21,
	305, -- Crusader's Crossbow
	1079 -- Festive Crusader's Crossbow
)
aProjectileInfo[21] = DefinePseudoProjectileDefinition({
	vecOffset = Vector3(23.5, -8, -3),
	vecVelocity = Vector3(2400, 0, 0),
	vecMaxs = Vector3(3, 3, 3),
	flGravity = 0.2,
	iAlignDistance = 2000,
	iCollisionType = COLLISION_HEAL_TEAMMATES,
})

AppendItemDefinitions(
	22,
	997 -- The Rescue Ranger
)
aProjectileInfo[22] = DefineDerivedProjectileDefinition(aProjectileInfo[21], {
	vecMaxs = Vector3(1, 1, 1),
	iCollisionType = COLLISION_HEAL_BUILDINGS,
})

AppendItemDefinitions(
	23,
	17, -- Syringe Gun
	36, -- The Blutsauger
	204, -- Syringe Gun (Renamed/Strange)
	412 -- The Overdose
)
aProjectileInfo[23] = DefinePseudoProjectileDefinition({
	vecOffset = Vector3(16, 6, -8),
	vecVelocity = Vector3(1000, 0, 0),
	vecMaxs = Vector3(1, 1, 1),
	flGravity = 0.3,
	flCollideWithTeammatesDelay = 0,
})

AppendItemDefinitions(
	24,
	58, -- Jarate
	222, -- Mad Milk
	1083, -- Festive Jarate
	1105, -- The Self-Aware Beauty Mark
	1121 -- Mutated Milk
)
aProjectileInfo[24] = DefinePseudoProjectileDefinition({
	vecOffset = Vector3(16, 8, -6),
	vecVelocity = Vector3(1000, 0, 200),
	vecMaxs = Vector3(8, 8, 8),
	flGravity = 1.125,
	flDamageRadius = 200,
})

AppendItemDefinitions(
	25,
	812, -- The Flying Guillotine
	833 -- The Flying Guillotine (Genuine)
)
aProjectileInfo[25] = DefinePseudoProjectileDefinition({
	vecOffset = Vector3(23.5, 8, -3),
	vecVelocity = Vector3(3000, 0, 300),
	vecMaxs = Vector3(2, 2, 2),
	flGravity = 2.25,
	flDrag = 1.3,
})

AppendItemDefinitions(
	26,
	44 -- The Sandman
)
aProjectileInfo[26] = DefineSimulProjectileDefinition({
	vecVelocity = Vector3(2985.1118164063, 0, 298.51116943359),
	vecAngularVelocity = Vector3(0, 50, 0),
	vecMaxs = Vector3(4.25, 4.25, 4.25),
	flElasticity = 0.45,
	sModelName = "models/weapons/w_models/w_baseball.mdl",

	GetFirePosition = function(self, pLocalPlayer, vecLocalView, vecViewAngles, bIsFlipped)
		--https://github.com/ValveSoftware/source-sdk-2013/blob/0565403b153dfcde602f6f58d8f4d13483696a13/src/game/shared/tf/tf_weapon_bat.cpp#L232
		local vecFirePos = pLocalPlayer:GetAbsOrigin()
			+ ((Vector3(0, 0, 50) + (vecViewAngles:Forward() * 32)) * pLocalPlayer:GetPropFloat("m_flModelScale"))

		local resultTrace = TRACE_HULL(vecLocalView, vecFirePos, -Vector3(8, 8, 8), Vector3(8, 8, 8), 100679691) -- MASK_SOLID_BRUSHONLY

		return (resultTrace.fraction == 1) and resultTrace.endpos or nil
	end,
})

AppendItemDefinitions(
	27,
	648 -- The Wrap Assassin
)
aProjectileInfo[27] = DefineDerivedProjectileDefinition(aProjectileInfo[26], {
	vecMins = Vector3(-2.990180015564, -2.5989532470703, -2.483987569809),
	vecMaxs = Vector3(2.6593606472015, 2.5989530086517, 2.4839873313904),
	flElasticity = 0,
	flDamageRadius = 50,
	sModelName = "models/weapons/c_models/c_xms_festive_ornament.mdl",
})

AppendItemDefinitions(
	28,
	441 -- The Cow Mangler 5000
)
aProjectileInfo[28] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	GetOffset = function(self, bDucking, bIsFlipped)
		return Vector3(23.5, 8 * (bIsFlipped and 1 or -1), bDucking and 8 or -3)
	end,
})

--https://github.com/ValveSoftware/source-sdk-2013/blob/0565403b153dfcde602f6f58d8f4d13483696a13/src/game/shared/tf/tf_weapon_raygun.cpp#L249
AppendItemDefinitions(
	29,
	588 -- The Pomson 6000
)
aProjectileInfo[29] = DefineDerivedProjectileDefinition(aProjectileInfo[9], {
	vecAbsoluteOffset = Vector3(0, 0, -13),
	flCollideWithTeammatesDelay = 0,
})

AppendItemDefinitions(
	30,
	1180 -- Gas Passer
)
aProjectileInfo[30] = DefinePseudoProjectileDefinition({
	vecOffset = Vector3(16, 8, -6),
	vecVelocity = Vector3(2000, 0, 200),
	vecMaxs = Vector3(8, 8, 8),
	flGravity = 1,
	flDrag = 1.32,
	flDamageRadius = 200,
})

AppendItemDefinitions(
	31,
	528 -- The Short Circuit
)
aProjectileInfo[31] = DefineBasicProjectileDefinition({
	vecOffset = Vector3(40, 15, -10),
	vecVelocity = Vector3(700, 0, 0),
	vecMaxs = Vector3(1, 1, 1),
	flCollideWithTeammatesDelay = 99999,
	flLifetime = 1.25,
})

AppendItemDefinitions(
	32,
	42, -- Sandvich
	159, -- The Dalokohs Bar
	311, -- The Buffalo Steak Sandvich
	433, -- Fishcake
	863, -- Robo-Sandvich
	1002, -- Festive Sandvich
	1190 -- Second Banana
)
aProjectileInfo[32] = DefinePseudoProjectileDefinition({
	vecOffset = Vector3(0, 0, -8),
	vecAngleOffset = Vector3(-10, 0, 0),
	vecVelocity = Vector3(500, 0, 0),
	vecMaxs = Vector3(17, 17, 10),
	flGravity = 1.02,
	iTraceMask = 33636363, -- MASK_PLAYERSOLID
	iCollisionType = COLLISION_HEAL_HURT,
})

return GetProjectileInformation

end)
__bundle_register("src.simulation.proj", function(require, _LOADED, __bundle_register, __bundle_modules)
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

end)
__bundle_register("src.simulation.player", function(require, _LOADED, __bundle_register, __bundle_modules)
---@diagnostic disable: duplicate-doc-field, missing-fields
local sim = {}

local MASK_SHOT_HULL = MASK_SHOT_HULL
local MASK_PLAYERSOLID = MASK_PLAYERSOLID
local DoTraceHull = engine.TraceHull
local TraceLine = engine.TraceLine
local Vector3 = Vector3
local math_deg = math.deg
local math_rad = math.rad
local math_atan = math.atan
local math_cos = math.cos
local math_sin = math.sin
local math_abs = math.abs
local math_acos = math.acos
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_pi = math.pi

-- constants
local MAX_SAMPLES = 8
local MIN_SPEED = 25 -- HU/s
local MAX_ANGULAR_VEL = 540 -- deg/s
local WALKABLE_ANGLE = 45 -- degrees
local MIN_VELOCITY_Z = 0.1
local AIR_SPEED_CAP = 30.0
local AIR_ACCELERATE = 10.0 -- Default air acceleration value
local GROUND_ACCELERATE = 10.0 -- Default ground acceleration value
local SURFACE_FRICTION = 1.0 -- Default surface friction

local MAX_CLIP_PLANES = 5
local DIST_EPSILON = 0.03125 -- Small epsilon for step calculations

local MAX_SAMPLES      = 8       -- tuned window size
local SMOOTH_ALPHA_G   = 0.392   -- tuned ground α
local SMOOTH_ALPHA_A   = 0.127   -- tuned air α

---@class Sample
---@field pos Vector3
---@field time number

---@type table<number, Sample[]>
local position_samples = {}

local zero_vector = Vector3(0, 0, 0)
local up_vector = Vector3(0, 0, 1)

---@param vec Vector3
local function NormalizeVector(vec)
	local len = vec:Length()
	if len == 0 then
		return Vector3()
	end

	return vec / len
end

---@param velocity Vector3
---@param normal Vector3
---@param overbounce number
---@return Vector3
local function ClipVelocity(velocity, normal, overbounce)
	local backoff = velocity:Dot(normal)

	if backoff < 0 then
		backoff = backoff * overbounce
	else
		backoff = backoff / overbounce
	end

	local change = normal * backoff
	return velocity - change
end

---@param velocity Vector3
---@param wishdir Vector3
---@param wishspeed number
---@param accel number
---@param frametime number
---@param surface_friction number
---@return Vector3
local function Accelerate(velocity, wishdir, wishspeed, accel, frametime, surface_friction)
	-- See if we are changing direction a bit
	local currentspeed = velocity:Dot(wishdir)

	-- Reduce wishspeed by the amount of veer.
	local addspeed = wishspeed - currentspeed

	-- If not going to add any speed, done.
	if addspeed <= 0 then
		return velocity
	end

	-- Determine amount of acceleration.
	local accelspeed = accel * frametime * wishspeed * surface_friction

	-- Cap at addspeed
	if accelspeed > addspeed then
		accelspeed = addspeed
	end

	-- Adjust velocity.
	local new_velocity = Vector3(
		velocity.x + accelspeed * wishdir.x,
		velocity.y + accelspeed * wishdir.y,
		velocity.z + accelspeed * wishdir.z
	)

	return new_velocity
end

---@param velocity Vector3
---@param wishdir Vector3
---@param wishspeed number
---@param accel number
---@param frametime number
---@param surface_friction number
---@return Vector3
local function AirAccelerate(velocity, wishdir, wishspeed, accel, frametime, surface_friction)
	local wishspd = wishspeed

	-- Cap speed
	if wishspd > AIR_SPEED_CAP then
		wishspd = AIR_SPEED_CAP
	end

	-- Determine veer amount
	local currentspeed = velocity:Dot(wishdir)

	-- See how much to add
	local addspeed = wishspd - currentspeed

	-- If not adding any, done.
	if addspeed <= 0 then
		return velocity
	end

	-- Determine acceleration speed after acceleration
	local accelspeed = accel * wishspeed * frametime * surface_friction

	-- Cap it
	if accelspeed > addspeed then
		accelspeed = addspeed
	end

	-- Adjust velocity
	local new_velocity = Vector3(
		velocity.x + accelspeed * wishdir.x,
		velocity.y + accelspeed * wishdir.y,
		velocity.z + accelspeed * wishdir.z
	)

	return new_velocity
end

---@param position Vector3
---@param mins Vector3
---@param maxs Vector3
---@param pTarget Entity
---@param step_height number
---@return boolean
local function IsOnGround(position, mins, maxs, pTarget, step_height)
	local target_index = pTarget:GetIndex()

	local function shouldHit(ent)
		return ent:GetIndex() ~= target_index
	end

	-- Trace down from bottom of bounding box
	local bbox_bottom = position + Vector3(0, 0, mins.z)
	local trace_end = bbox_bottom + Vector3(0, 0, -step_height)

	local trace = DoTraceHull(bbox_bottom, trace_end, zero_vector, zero_vector, MASK_SHOT_HULL, shouldHit)

	if trace and trace.fraction < 1 then
		-- Check walkability
		local ground_angle = math_deg(math_acos(trace.plane:Dot(up_vector)))

		if ground_angle <= WALKABLE_ANGLE then
			-- Verify we can fit above the surface
			local hit_point = bbox_bottom + (trace_end - bbox_bottom) * trace.fraction
			local step_test_start = hit_point + Vector3(0, 0, step_height)
			local step_trace = DoTraceHull(step_test_start, position, mins, maxs, MASK_SHOT_HULL, shouldHit)

			return not step_trace or step_trace.fraction >= 1
		end
	end

	return false
end

---@param pEntity Entity
---@return boolean
local function IsPlayerOnGround(pEntity)
	local mins, maxs = pEntity:GetMins(), pEntity:GetMaxs()
	local origin = pEntity:GetAbsOrigin()
	return IsOnGround(origin, mins, maxs, pEntity, pEntity:GetPropFloat("m_flStepSize"))
end

---@param pEntity Entity
local function AddPositionSample(pEntity)
	local index = pEntity:GetIndex()

	if not position_samples[index] then
		position_samples[index] = {}
	end

	local current_time = globals.CurTime()
	local current_pos = pEntity:GetAbsOrigin()

	local sample = { pos = current_pos, time = current_time }
	local samples = position_samples[index]
	samples[#samples + 1] = sample

	-- trim old samples
	if #samples > MAX_SAMPLES then
		for i = 1, #samples - MAX_SAMPLES do
			table.remove(samples, 1)
		end
	end
end

---@param pEntity Entity
---@return number
local function GetSmoothedAngularVelocity(pEntity)
	local samples = position_samples[pEntity:GetIndex()]
	if not samples or #samples < 3 then
		return 0
	end

	local ang_vels = {}
	local two_pi = 2 * math_pi

	-- calculate angular velocities from at least 3 samples
	for i = 1, #samples - 2 do
		local s1, s2, s3 = samples[i], samples[i + 1], samples[i + 2]
		local dt1, dt2 = s2.time - s1.time, s3.time - s2.time

		if dt1 > 0 and dt2 > 0 then
			-- Calculate velocities
			local vel1 = (s2.pos - s1.pos) / dt1
			local vel2 = (s3.pos - s2.pos) / dt2

			-- Skip low-speed samples
			if vel1:Length() >= MIN_SPEED and vel2:Length() >= MIN_SPEED then
				-- Calculate angular change
				local yaw1 = math_atan(vel1.y, vel1.x)
				local yaw2 = math_atan(vel2.y, vel2.x)
				local diff = math_deg((yaw2 - yaw1 + math_pi) % two_pi - math_pi)

				local angular_velocity = diff / ((dt1 + dt2) * 0.5)

				-- Filter extreme values
				if math_abs(angular_velocity) < MAX_ANGULAR_VEL then
					ang_vels[#ang_vels + 1] = angular_velocity
				end
			end
		end
	end

	if #ang_vels == 0 then
		return 0
	end

	-- Use median for outlier rejection
	if #ang_vels >= 3 then
		table.sort(ang_vels)
		local mid = math_floor(#ang_vels * 0.5) + 1
		return ang_vels[mid]
	end

	-- Simple exponential smoothing for few samples
	local grounded = IsPlayerOnGround(pEntity)
	local base_alpha = grounded and SMOOTH_ALPHA_G or SMOOTH_ALPHA_A
	local smoothed = ang_vels[1]

	for i = 2, #ang_vels do
		local alpha = math_max(0.05, math_min(base_alpha, 0.4))
		smoothed = smoothed * (1 - alpha) + ang_vels[i] * alpha
	end

	return smoothed
end

local function GetEnemyTeam()
	local pLocal = entities.GetLocalPlayer()
	if pLocal == nil then
		return 2
	end

	return pLocal:GetTeamNumber() == 2 and 3 or 2
end

function sim.RunBackground(players)
	local enemy_team = GetEnemyTeam()
	if not enemy_team then
		return
	end

	for _, player in pairs(players) do
		if player:GetTeamNumber() == enemy_team and player:IsAlive() and not player:IsDormant() then
			AddPositionSample(player)
		end
	end
end

---@param velocity Vector3
---@param frametime number
---@param mins Vector3
---@param maxs Vector3
---@param shouldHitEntity function
---@param pTarget Entity
---@param surface_friction number
---@return Vector3, Vector3, number
local function TryPlayerMove(origin, velocity, frametime, mins, maxs, shouldHitEntity, pTarget, surface_friction)
	local numbumps = 4
	local blocked = 0
	local numplanes = 0
	local planes = {}
	local primal_velocity = Vector3(velocity.x, velocity.y, velocity.z)
	local original_velocity = Vector3(velocity.x, velocity.y, velocity.z)
	local new_velocity = Vector3(0, 0, 0)
	local time_left = frametime
	local allFraction = 0
	local current_origin = Vector3(origin.x, origin.y, origin.z)

	for bumpcount = 0, numbumps - 1 do
		if velocity:Length() == 0.0 then
			break
		end

		-- Calculate end position
		local end_pos = current_origin + velocity * time_left

		-- Trace from current origin to end position
		local trace = DoTraceHull(current_origin, end_pos, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

		allFraction = allFraction + trace.fraction

		-- If we started in a solid object or were in solid space the whole way
		if trace.allsolid then
			velocity = zero_vector
			return current_origin, velocity, 4 -- blocked by floor and wall
		end

		-- If we moved some portion of the total distance
		if trace.fraction > 0 then
			if numbumps > 0 and trace.fraction == 1 then
				-- Check for precision issues - verify we won't get stuck at end position
				local stuck_trace =
					DoTraceHull(trace.endpos, trace.endpos, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)
				if stuck_trace.startsolid or stuck_trace.fraction ~= 1.0 then
					velocity = zero_vector
					break
				end
			end

			-- Actually covered some distance
			current_origin = trace.endpos
			original_velocity = Vector3(velocity.x, velocity.y, velocity.z)
			numplanes = 0
		end

		-- If we covered the entire distance, we are done
		if trace.fraction == 1 then
			break -- moved the entire distance
		end

		-- Determine what we hit
		if trace.plane.z > 0.7 then
			blocked = blocked | 1 -- floor
		end
		if trace.plane.z == 0 then
			blocked = blocked | 2 -- step/wall
		end

		-- Reduce time left by the fraction we moved
		time_left = time_left - time_left * trace.fraction

		-- Did we run out of planes to clip against?
		if numplanes >= MAX_CLIP_PLANES then
			velocity = zero_vector
			break
		end

		-- Set up clipping plane
		planes[numplanes + 1] = Vector3(trace.plane.x, trace.plane.y, trace.plane.z)
		numplanes = numplanes + 1

		-- Modify velocity so it parallels all of the clip planes
		-- Reflect player velocity for first impact plane only
		if numplanes == 1 and trace.plane.z <= 0.7 then
			-- Wall bounce - simple reflection with bounce factor
			local bounce_factor = 1.0 + (1.0 - surface_friction) * 0.5
			new_velocity = ClipVelocity(original_velocity, planes[1], bounce_factor)
			velocity = Vector3(new_velocity.x, new_velocity.y, new_velocity.z)
			original_velocity = Vector3(new_velocity.x, new_velocity.y, new_velocity.z)
		else
			-- Multi-plane clipping
			local i = 0
			while i < numplanes do
				velocity = ClipVelocity(original_velocity, planes[i + 1], 1.0)

				-- Check if this velocity works with all planes
				local j = 0
				while j < numplanes do
					if j ~= i then
						if velocity:Dot(planes[j + 1]) < 0 then
							break -- not ok
						end
					end
					j = j + 1
				end

				if j == numplanes then -- Didn't have to re-clip
					break
				end
				i = i + 1
			end

			-- Did we go all the way through plane set?
			if i == numplanes then
				-- Velocity is set in clipping call
			else
				-- Go along the crease (intersection of two planes)
				if numplanes ~= 2 then
					velocity = zero_vector
					break
				end

				-- Calculate cross product for crease direction
				local dir = planes[1]:Cross(planes[2])
				dir = NormalizeVector(dir)
				local d = dir:Dot(velocity)
				velocity = dir * d
			end

			-- If velocity is against the original velocity, stop to avoid oscillations
			local d = velocity:Dot(primal_velocity)
			if d <= 0 then
				velocity = zero_vector
				break
			end
		end
	end

	if allFraction == 0 then
		velocity = zero_vector
	end

	return current_origin, velocity, blocked
end

---@param origin Vector3
---@param velocity Vector3
---@param frametime number
---@param mins Vector3
---@param maxs Vector3
---@param shouldHitEntity function
---@param pTarget Entity
---@param surface_friction number
---@param step_size number
---@return Vector3, Vector3, number, number
local function StepMove(origin, velocity, frametime, mins, maxs, shouldHitEntity, pTarget, surface_friction, step_size)
	local vec_pos = Vector3(origin.x, origin.y, origin.z)
	local vec_vel = Vector3(velocity.x, velocity.y, velocity.z)
	local step_height = 0

	-- Try sliding forward both on ground and up step_size pixels
	-- Take the move that goes farthest

	-- Slide move down (regular movement)
	local down_origin, down_velocity, down_blocked =
		TryPlayerMove(vec_pos, vec_vel, frametime, mins, maxs, shouldHitEntity, pTarget, surface_friction)

	local vec_down_pos = Vector3(down_origin.x, down_origin.y, down_origin.z)
	local vec_down_vel = Vector3(down_velocity.x, down_velocity.y, down_velocity.z)

	-- Reset to original values for step-up attempt
	local current_origin = Vector3(vec_pos.x, vec_pos.y, vec_pos.z)
	local current_velocity = Vector3(vec_vel.x, vec_vel.y, vec_vel.z)

	-- Move up a stair height
	local step_up_end = Vector3(current_origin.x, current_origin.y, current_origin.z + step_size + DIST_EPSILON)

	-- Trace up to see if we can step up
	local up_trace = DoTraceHull(current_origin, step_up_end, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

	if not up_trace.startsolid and not up_trace.allsolid then
		current_origin = up_trace.endpos
	end

	-- Slide move up (after stepping up)
	local up_origin, up_velocity, up_blocked = TryPlayerMove(
		current_origin,
		current_velocity,
		frametime,
		mins,
		maxs,
		shouldHitEntity,
		pTarget,
		surface_friction
	)

	-- Move down a stair (attempt to land on ground after step)
	local step_down_end = Vector3(up_origin.x, up_origin.y, up_origin.z - step_size - DIST_EPSILON)
	local down_trace = DoTraceHull(up_origin, step_down_end, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

	-- If we are not on the ground anymore, use the original movement attempt
	if down_trace.plane.z < 0.7 then
		local step_dist = down_origin.z - vec_pos.z
		if step_dist > 0.0 then
			step_height = step_height + step_dist
		end
		return down_origin, down_velocity, down_blocked, step_height
	end

	-- If the trace ended up in empty space, copy the end over to the origin
	if not down_trace.startsolid and not down_trace.allsolid then
		up_origin = down_trace.endpos
	end

	local vec_up_pos = Vector3(up_origin.x, up_origin.y, up_origin.z)

	-- Decide which one went farther (compare horizontal distance)
	local down_dist_sq = (vec_down_pos.x - vec_pos.x) * (vec_down_pos.x - vec_pos.x)
		+ (vec_down_pos.y - vec_pos.y) * (vec_down_pos.y - vec_pos.y)
	local up_dist_sq = (vec_up_pos.x - vec_pos.x) * (vec_up_pos.x - vec_pos.x)
		+ (vec_up_pos.y - vec_pos.y) * (vec_up_pos.y - vec_pos.y)

	local final_origin, final_velocity, final_blocked

	if down_dist_sq > up_dist_sq then
		-- Down movement went farther
		final_origin = vec_down_pos
		final_velocity = vec_down_vel
		final_blocked = down_blocked
	else
		-- Up movement went farther, but copy z velocity from down movement
		final_origin = vec_up_pos
		final_velocity = Vector3(up_velocity.x, up_velocity.y, vec_down_vel.z)
		final_blocked = up_blocked
	end

	local step_dist = final_origin.z - vec_pos.z
	if step_dist > 0 then
		step_height = step_height + step_dist
	end

	return final_origin, final_velocity, final_blocked, step_height
end

---@param stepSize number
---@param pTarget Entity
---@param initial_pos Vector3
---@param time integer
---@return Vector3[]
function sim.Run(stepSize, pTarget, initial_pos, time)
	local smoothed_velocity = pTarget:EstimateAbsVelocity()
	local last_pos = initial_pos
	local tick_interval = globals.TickInterval()
	local angular_velocity = GetSmoothedAngularVelocity(pTarget) * tick_interval
	local gravity_step = client.GetConVar("sv_gravity") * tick_interval
	local target_max_speed = pTarget:GetPropFloat("m_flMaxspeed") or 450
	local local_player_index = client.GetLocalPlayerIndex()
	local target_team = pTarget:GetTeamNumber()
	local surface_friction = pTarget:GetPropFloat("m_flFriction") or SURFACE_FRICTION
	local step_size = pTarget:GetPropFloat("m_flStepSize") or 18.0

	local positions = {
		initial_pos,
	}

	local mins, maxs = pTarget:GetMins(), pTarget:GetMaxs()
	local down_vector = Vector3(0, 0, -stepSize)

	-- pre calculate rotation values if angular velocity exists
	local cos_yaw, sin_yaw
	if angular_velocity ~= 0 then
		local yaw = math_rad(angular_velocity)
		cos_yaw, sin_yaw = math_cos(yaw), math_sin(yaw)
	end

	local function shouldHitEntity(ent)
		local ent_index = ent:GetIndex()
		return ent_index ~= local_player_index and ent:GetTeamNumber() ~= target_team
	end

	local was_onground = false

	for i = 1, time do
		-- apply angular velocity rotation (if we have it)
		if angular_velocity ~= 0 then
			local vx, vy = smoothed_velocity.x, smoothed_velocity.y
			smoothed_velocity.x = vx * cos_yaw - vy * sin_yaw
			smoothed_velocity.y = vx * sin_yaw + vy * cos_yaw
		end

		-- ground check first to determine acceleration type
		local next_pos_check = last_pos + smoothed_velocity * tick_interval
		local ground_trace = TraceLine(next_pos_check, next_pos_check + down_vector, MASK_PLAYERSOLID, shouldHitEntity)
		local is_on_ground = ground_trace and ground_trace.fraction < 1.0 and smoothed_velocity.z <= MIN_VELOCITY_Z

		-- apply appropriate acceleration based on ground state
		local horizontal_vel = Vector3(smoothed_velocity.x, smoothed_velocity.y, 0)
		local horizontal_speed = horizontal_vel:Length()

		if horizontal_speed > 0.1 then
			local wishdir = horizontal_vel * (1.0 / horizontal_speed)
			local wishspeed = math_min(horizontal_speed, target_max_speed)

			if is_on_ground then
				-- apply ground acceleration
				smoothed_velocity = Accelerate(
					smoothed_velocity,
					wishdir,
					wishspeed,
					GROUND_ACCELERATE,
					tick_interval,
					surface_friction
				)
			else
				-- apply air acceleration when not on ground and falling
				if smoothed_velocity.z < 0 then
					smoothed_velocity = AirAccelerate(
						smoothed_velocity,
						wishdir,
						wishspeed,
						AIR_ACCELERATE,
						tick_interval,
						surface_friction
					)
				end
			end
		end

		-- Clamp velocity to max speed when on ground
		if is_on_ground then
			local vel_length = smoothed_velocity:Length()
			if vel_length > target_max_speed then
				smoothed_velocity = smoothed_velocity * (target_max_speed / vel_length)
			end
		end

		local new_pos, new_velocity = StepMove(
			last_pos,
			smoothed_velocity,
			tick_interval,
			mins,
			maxs,
			shouldHitEntity,
			pTarget,
			surface_friction,
			step_size
		)

		last_pos = new_pos
		smoothed_velocity = new_velocity
		positions[#positions + 1] = last_pos

		-- Update ground state and apply gravity
		was_onground = is_on_ground

		if not was_onground then
			smoothed_velocity.z = smoothed_velocity.z - gravity_step
		elseif smoothed_velocity.z < 0 then
			smoothed_velocity.z = 0
		end
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

---@param p0 Vector3 -- start position
---@param p1 Vector3 -- target position
---@param speed number -- projectile speed
---@param gravity number -- gravity constant
---@return EulerAngles|nil -- Euler angles (pitch, yaw, 0)
function Math.SolveBallisticArc(p0, p1, speed, gravity)
	local diff = p1 - p0
	local dx = math.sqrt(diff.x * diff.x + diff.y * diff.y)
	local dy = diff.z
	local speed2 = speed * speed
	local g = gravity

	local root = speed2 * speed2 - g * (g * dx * dx + 2 * dy * speed2)
	if root < 0 then
		return nil -- no solution
	end

	local sqrt_root = math.sqrt(root)
	local angle = math.atan((speed2 - sqrt_root) / (g * dx)) -- low arc

	-- Get horizontal direction (yaw)
	local yaw = math.atan(diff.y, diff.x)

	-- Convert pitch from angle
	local pitch = -angle -- negative because upward is negative pitch in most engines

	return EulerAngles(math.deg(pitch), math.deg(yaw), 0)
end

---@param shootPos Vector3
---@param targetPos Vector3
---@param speed number
---@return number
function Math.EstimateTravelTime(shootPos, targetPos, speed)
	local distance = (targetPos - shootPos):Length2D()
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

function Math.DirectionToAngles(direction)
	local pitch = math.asin(-direction.z) * (180 / math.pi)
	local yaw = math.atan(direction.y, direction.x) * (180 / math.pi)
	return Vector3(pitch, yaw, 0)
end

---@param offset Vector3
---@param direction Vector3
function Math.RotateOffsetAlongDirection(offset, direction)
	local forward = NormalizeVector(direction)
	local up = Vector3(0, 0, 1)
	local right = NormalizeVector(forward:Cross(up))
	up = NormalizeVector(right:Cross(forward))

	return forward * offset.x + right * offset.y + up * offset.z
end

Math.NormalizeVector = NormalizeVector
return Math

end)
__bundle_register("src.utils.weapon_utils", function(require, _LOADED, __bundle_register, __bundle_modules)
local wep_utils = {}

---@type table<integer, integer>
local ItemDefinitions = {}

local old_weapon, lastFire, nextAttack = nil, 0, 0

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

	if lastfiretime ~= lastFire or weapon:GetIndex() ~= old_weapon then
		lastFire = lastfiretime
		nextAttack = GetNextPrimaryAttack(weapon)
	end

	old_weapon = weapon:GetIndex()
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
---@param eAngle EulerAngles
---@return Vector3
function wep_utils.GetShootPos(pLocal, weapon_info, eAngle)
	-- i stole this from terminator
	local vStartPosition = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
	return weapon_info:GetFirePosition(pLocal, vStartPosition, eAngle, client.GetConVar("cl_flipviewmodels") == 1) --vStartPosition + vOffset, vOffset
end

return wep_utils

end)
return __bundle_require("__root")