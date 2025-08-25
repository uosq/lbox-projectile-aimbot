--[[
	NAVET'S PROEJECTILE AIMBOT
	made by navet
	Update: v9
	Source: https://github.com/uosq/lbox-projectile-aimbot
	
	This project would take way longer to start making
	if it weren't for them:
	Terminator - https://github.com/titaniummachine1
	GoodEvening - https://github.com/GoodEveningFellOff
--]]

---@diagnostic disable: cast-local-type

printc(186, 97, 255, 255, "The projectile aimbot is loading...")

local version = "9"

local settings = {
	enabled = true,
	autoshoot = true,
	fov = gui.GetValue("aim fov"),
	max_sim_time = 2.0,
	draw_time = 1.0,
	draw_proj_path = true,
	draw_player_path = true,
	draw_bounding_box = true,
	draw_only = false,
	draw_multipoint_target = false,
	max_distance = 1024,
	allow_aim_at_teammates = true,
	ping_compensation = true,
	min_priority = 0,
	explosive = true,
	close_distance = 10, --- %

	sim = {
		use_detonate_time = true,
		can_rotate = true,
		stay_on_ground = false,
	},

	max_percent = 90,
	wait_for_charge = false,
	cancel_shot = false,

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

	colors = {
		bounding_box = 193, --{136, 192, 208, 255},
		player_path = 193, --{136, 192, 208, 255},
		projectile_path = 40, --{235, 203, 139, 255}
		multipoint_target = 20,
		target_glow = 360,
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

---@type ProjectileSimulation
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

local target_selector = require("src.target_selector")
assert(target_selector, "[PROJ AIMBOT] Target selector module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Target selector module loaded")

local draw                             = draw
local entities                         = entities
local engine                           = engine
local E_TFCOND                         = E_TFCOND

local displayed_time                   = 0.0
local BEGGARS_BAZOOKA_INDEX            = 730
local LOOSE_CANNON_INDEX               = 996

--local PLAYER_MIN_HULL, PLAYER_MAX_HULL = Vector3(-24.0, -24.0, 0.0), Vector3(24.0, 24.0, 82.0)
local target_min_hull, target_max_hull = Vector3(), Vector3()

local paths                            = {
	proj_path = {},
	player_path = {},
}

local multipoint_target_pos            = nil

local original_gui_value               = gui.GetValue("projectile aimbot")

---@type Entity?
local pSelectedTarget = nil

---@class ENTRY
---@field m_vecPos Vector3
---@field m_vecVelocity Vector3
---@field m_flFriction number
---@field m_flAngularVelocity number
---@field m_flGravityStep number
---@field m_flMaxspeed number
---@field m_iTeam integer
---@field m_flStepSize number
---@field m_vecMins Vector3
---@field m_vecMaxs Vector3

---@type table<integer, ENTRY>
local entitylist = {}

---@param pWeapon Entity
local function GetCharge(pWeapon)
	local charge_time = 0.0

	if not pWeapon then
		return charge_time
	end

	if pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW then
		-- check if bow is currently being charged
		local charge_begin_time = pWeapon:GetChargeBeginTime()

		-- if charge_begin_time is 0, the bow isn't charging
		if charge_begin_time and charge_begin_time > 0 then
			charge_time = globals.CurTime() - charge_begin_time
			-- clamp charge time between 0 and 1 second (full charge)
			charge_time = math.max(0, math.min(charge_time, 1.0))
		else
			-- bow is not charging, use minimum speed
			charge_time = 0.0
		end
	elseif pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER then
		local charge_begin_time = pWeapon:GetChargeBeginTime()

		if charge_begin_time and charge_begin_time > 0 then
			charge_time = (globals.CurTime() - charge_begin_time) / pWeapon:GetChargeMaxTime()
			if charge_time > 1.0 then
				charge_time = 0.0
			end
		end
	elseif pWeapon:GetPropInt("m_iItemDefinitionIndex") == LOOSE_CANNON_INDEX then -- The Loose Cannon
		local charge_begin_time = pWeapon:GetChargeBeginTime()

		if charge_begin_time and charge_begin_time > 0 then
			charge_time = globals.CurTime() - charge_begin_time
			-- Loose Cannon has a maximum charge time of 1 second
			charge_time = math.max(0, math.min(charge_time, 1.0))
		end
	end

	return charge_time
end

---@param pLocal Entity
---@param pWeapon Entity
---@param uCmd UserCmd
local function CancelShot(pLocal, pWeapon, uCmd)
	local current_slot = pWeapon:GetLoadoutSlot()
	local next_slot = current_slot + 1
	if next_slot > E_LoadoutSlot.LOADOUT_POSITION_MELEE then
		next_slot = E_LoadoutSlot.LOADOUT_POSITION_PRIMARY
	end
	local pSlotWeapon = pLocal:GetEntityForLoadoutSlot(next_slot)
	if pSlotWeapon then
		uCmd.weaponselect = pSlotWeapon:GetIndex()
	end
end

local function GetEntityOrigin(pTarget)
	return pTarget:GetPropVector("tflocaldata", "m_vecOrigin") or pTarget:GetAbsOrigin()
end

---@param pLocal Entity
---@param pWeapon Entity
---@param pTarget Entity
---@param vHeadPos Vector3
---@param weaponInfo WeaponInfo
---@param time_ticks integer
---@param charge number
---@param uCmd UserCmd
---@param orig_buttons integer
---@param orig_viewangle Vector3
local function ShootProjectile(pInfo, pLocal, pWeapon, pTarget, vHeadPos, weaponInfo, time_ticks, charge, uCmd, orig_buttons, orig_viewangle)
	local player_path, gravity

	gravity = client.GetConVar("sv_gravity") * 0.5

	local function ResetUserCmd()
		if weaponInfo.m_bCharges and charge > 0 and settings.cancel_shot then
			CancelShot(pLocal, pWeapon, uCmd)
		end

		uCmd.viewangles = orig_viewangle
		uCmd.buttons = orig_buttons
		uCmd.sendpacket = true
	end

	local vecTargetOrigin = GetEntityOrigin(pTarget)
	player_path = player_sim.Run(pInfo, pTarget, vecTargetOrigin + Vector3(0, 0, 1), time_ticks)

	local vPredictedPos = Vector3(player_path[#player_path]:Unpack()) --- copy predicted path
	multipoint.Run(pTarget, pWeapon, weaponInfo, vHeadPos, vPredictedPos)

	local angle = math_utils.SolveBallisticArc(vHeadPos, vPredictedPos, weaponInfo:GetVelocity(charge):Length2D(), weaponInfo:GetGravity(charge)*gravity)
	if angle == nil then
		return ResetUserCmd()
	end

	local vWeaponFirePos = weaponInfo:GetFirePosition(pLocal, vHeadPos, angle, pWeapon:IsViewModelFlipped())
	if vWeaponFirePos == nil then
		return ResetUserCmd()
	end

	local function shouldHit(ent)
		if not ent then -- world / sky / nil
			return true -- trace should go on
		end
		if ent == pLocal or ent == pTarget then
			return false -- pretend they don't exist
		end
		return ent:GetTeamNumber() ~= pTarget:GetTeamNumber()
	end

	local trace = engine.TraceHull(vWeaponFirePos, vPredictedPos, weaponInfo.m_vecMins, weaponInfo.m_vecMaxs, weaponInfo.m_iTraceMask or MASK_SHOT_HULL, shouldHit)
	if (not trace or trace.fraction < 0.9) then
		return ResetUserCmd()
	end

	local proj_path = proj_sim.Run(pTarget, pLocal, pWeapon, vWeaponFirePos, angle:Forward(), player_path[#player_path], time_ticks, weaponInfo, charge)

	multipoint_target_pos = vPredictedPos
	uCmd.viewangles = Vector3(angle:Unpack())
	displayed_time = globals.CurTime() + settings.draw_time
	paths.player_path = player_path
	paths.proj_path = proj_path
end

---@param uCmd UserCmd
---@param pWeapon Entity
---@param pTarget Entity
---@param pLocal Entity
---@param weaponInfo WeaponInfo
---@param vHeadPos Vector3
local function HandleWeaponFiring(uCmd, pLocal, pWeapon, pTarget, charge, weaponInfo, time_ticks, vHeadPos, pInfo)
	local orig_buttons = uCmd:GetButtons()
	local orig_viewangle = Vector3(uCmd:GetViewAngles())

	if weaponInfo.m_bCharges then
		if settings.autoshoot and wep_utils.CanShoot() then
			uCmd.buttons = uCmd.buttons | IN_ATTACK
		end

		--- if its 100%, then we have a very high chance that it didnt find any angle to shoot
		if settings.cancel_shot and charge > (settings.max_percent / 100) or charge >= 1 then
			CancelShot(pLocal, pWeapon, uCmd)
		end

		if charge > 0 and wep_utils.CanShoot() then
			if settings.psilent then
				uCmd.sendpacket = false
			end

			uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
			ShootProjectile(pInfo, pLocal, pWeapon, pTarget, vHeadPos, weaponInfo, time_ticks, charge, uCmd, orig_buttons, orig_viewangle)
		end
	elseif pWeapon:GetPropInt("m_iItemDefinitionIndex") == BEGGARS_BAZOOKA_INDEX then
		local clip = pWeapon:GetPropInt("LocalWeaponData", "m_iClip1")
		if clip < 1 then
			uCmd.buttons = uCmd.buttons | IN_ATTACK -- hold to charge
		else
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
			if settings.psilent then
				uCmd.sendpacket = false
			end
			ShootProjectile(pInfo, pLocal, pWeapon, pTarget, vHeadPos, weaponInfo, time_ticks, charge, uCmd, orig_buttons, orig_viewangle)
		end
	elseif pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_LUNCHBOX then
		uCmd.buttons = uCmd.buttons | IN_ATTACK2
		ShootProjectile(pInfo, pLocal, pWeapon, pTarget, vHeadPos, weaponInfo, time_ticks, charge, uCmd, orig_buttons, orig_viewangle)
	elseif pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_BAT_WOOD then
		uCmd.buttons = uCmd.buttons | IN_ATTACK2
		ShootProjectile(pInfo, pLocal, pWeapon, pTarget, vHeadPos, weaponInfo, time_ticks, charge, uCmd, orig_buttons, orig_viewangle)
	elseif pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_FLAME_BALL then
		uCmd.buttons = uCmd.buttons | IN_ATTACK
		ShootProjectile(pInfo, pLocal, pWeapon, pTarget, vHeadPos, weaponInfo, time_ticks, charge, uCmd, orig_buttons, orig_viewangle)
	else
		if wep_utils.CanShoot() then
			if settings.autoshoot and (uCmd.buttons & IN_ATTACK) == 0 then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end

			if (uCmd.buttons & IN_ATTACK) ~= 0 then
				if settings.psilent then
					uCmd.sendpacket = false
				end

				ShootProjectile(pInfo, pLocal, pWeapon, pTarget, vHeadPos, weaponInfo, time_ticks, charge, uCmd, orig_buttons, orig_viewangle)
			end
		end
	end
end

---@param classTable table<integer, Entity>
local function ProcessBuilding(classTable, enemy_team)
	for _, building in pairs(classTable) do
		if building:GetTeamNumber() == enemy_team and building:GetHealth() > 0 and not building:IsDormant() then
			entitylist[building:GetIndex()] = {
				m_vecPos = building:GetPropVector("m_vecOrigin") or building:GetAbsOrigin(),
				m_vecVelocity = Vector3(),
				m_flFriction = 0,
				m_flAngularVelocity = 0,
				m_flGravityStep = 0,
				m_flMaxspeed = 0,
				m_iTeam = enemy_team,
				m_flStepSize = 0,
				m_vecMins = building:GetMins(),
				m_vecMaxs = building:GetMaxs(),
			}
		end
	end
end

---@param pLocal Entity
---@param players table<integer, Entity>
---@param sentries table<integer, Entity>
---@param dispensers table<integer, Entity>
---@param teleporters table<integer, Entity>
local function UpdateEntityList(pLocal, players, sentries, dispensers, teleporters, weaponInfo, vHeadPos, charge)
	local enemy_team = pLocal:GetTeamNumber() == 2 and 3 or 2

	entitylist = {}
	local _, sv_gravity = client.GetConVar("sv_gravity")

	for _, player in pairs(players) do
		if player:GetTeamNumber() == enemy_team and player:IsAlive() and not player:IsDormant() then
			entitylist[player:GetIndex()] = {
				m_vecPos =  player:GetPropVector("localdata", "m_vecOrigin") or player:GetAbsOrigin(),
				m_vecVelocity = player:EstimateAbsVelocity(),
				m_flFriction = player:GetPropFloat("m_flFriction"),
				m_flAngularVelocity = player_sim.GetSmoothedAngularVelocity(player),
				m_flGravityStep = sv_gravity,
				m_flMaxspeed = player:GetPropFloat("m_flMaxspeed"),
				m_iTeam = enemy_team,
				m_flStepSize = player:GetPropFloat("m_flStepSize"),
				m_vecMins = player:GetMins(),
				m_vecMaxs = player:GetMaxs(),
			}
		end
	end

	ProcessBuilding(sentries, enemy_team)
	ProcessBuilding(dispensers, enemy_team)
	ProcessBuilding(teleporters, enemy_team)
end

---@param uCmd UserCmd
local function CreateMove(uCmd)
	pSelectedTarget = nil

	if (settings.enabled == false) then
		return
	end

	if (engine.IsChatOpen() or engine.Con_IsVisible() or engine.IsGameUIVisible()) == true then
		return
	end

	if gui.GetValue("aim key") ~= 0 and input.IsButtonDown(gui.GetValue("aim key")) == false then
		return
	end

	local pLocal = entities.GetLocalPlayer()
	if pLocal == nil then
		return
	end

	if pLocal:InCond(E_TFCOND.TFCond_Taunting) then
		return
	end

	if pLocal:InCond(E_TFCOND.TFCond_HalloweenKart) then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if pWeapon == nil then
		return
	end

	local item_def_index = pWeapon:GetPropInt("m_iItemDefinitionIndex")
	local weaponInfo = GetProjectileInformation(item_def_index)
	if weaponInfo == nil then
		return
	end

	local vHeadPos = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
	local players = entities.FindByClass("CTFPlayer")
	local sentries = entities.FindByClass("CObjectSentrygun")
	local dispensers = entities.FindByClass("CObjectDispenser")
	local teleporters = entities.FindByClass("CObjectTeleporter")
	local charge_time = GetCharge(pWeapon)

	UpdateEntityList(pLocal, players, sentries, dispensers, teleporters, weaponInfo, vHeadPos, charge_time)

	local iWeaponID = pWeapon:GetWeaponID()
	local bAimAtTeamMates = false

	if iWeaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX then
		bAimAtTeamMates = true
	elseif iWeaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW then
		bAimAtTeamMates = true
	end

	bAimAtTeamMates = settings.allow_aim_at_teammates and bAimAtTeamMates or false

	local pTarget = target_selector.Run(pLocal, vHeadPos, math_utils, entitylist, settings, bAimAtTeamMates)
	pSelectedTarget = pTarget
	if pTarget == nil then
		return
	end

	local vecTargetOrigin = GetEntityOrigin(pTarget) + Vector3(0, 0, 10)
	target_max_hull = pTarget:GetMaxs()
	target_min_hull = pTarget:GetMins()

	local velocity_vector = weaponInfo:GetVelocity(charge_time)
	local forward_speed = velocity_vector:Length2D()

	local det_mult = pWeapon:AttributeHookFloat("sticky_arm_time")
	local detonate_time = (settings.use_detonate_time and pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER) and 0.7 * det_mult or 0
	local travel_time_est = (vecTargetOrigin - vHeadPos):Length() / forward_speed
	local total_time = travel_time_est + detonate_time

	if total_time > settings.max_sim_time then
		return
	end

	local choked_time = clientstate:GetChokedCommands()
	local time_ticks = (((total_time * 66.67) + 0.5) // 1) + choked_time + 1 --- one extra tick because our current createmove is 1 tick behind
	local pInfo = entitylist[pTarget:GetIndex()]

	if settings.draw_only then
		local player_path = player_sim.Run(pInfo, pTarget, vecTargetOrigin, detonate_time)
		local vecPredictedPos = player_path[#player_path]
		local gravity = client.GetConVar("sv_gravity") * 0.5 * weaponInfo:GetGravity(charge_time)
		local angle_low, angle_high = math_utils.SolveBallisticArcBoth(vHeadPos, vecPredictedPos, forward_speed, gravity)
		if not angle_low or not angle_high then
			return
		end

		local vecWeaponFirePos = weaponInfo:GetFirePosition(pLocal, vHeadPos, angle_low, pWeapon:IsViewModelFlipped())
		paths.player_path = player_path
		paths.proj_path = proj_sim.Run(pTarget, pLocal, pWeapon, vecWeaponFirePos, angle_low:Forward(), player_path[#player_path], total_time, weaponInfo, charge_time)
		displayed_time = globals.CurTime() + settings.draw_time
		return
	end

	HandleWeaponFiring(uCmd, pLocal, pWeapon, pTarget, charge_time, weaponInfo, time_ticks, vHeadPos, pInfo)
end

--- source: https://gist.github.com/GigsD4X/8513963
local function HSVToRGB( hue, saturation, value )
	-- Returns the RGB equivalent of the given HSV-defined color
	-- (adapted from some code found around the web)

	-- If it's achromatic, just return the value
	if saturation == 0 then
		return value, value, value;
	end;

	-- Get the hue sector
	local hue_sector = math.floor( hue / 60 );
	local hue_sector_offset = ( hue / 60 ) - hue_sector;

	local p = value * ( 1 - saturation );
	local q = value * ( 1 - saturation * hue_sector_offset );
	local t = value * ( 1 - saturation * ( 1 - hue_sector_offset ) );

	if hue_sector == 0 then
		return value, t, p;
	elseif hue_sector == 1 then
		return q, value, p;
	elseif hue_sector == 2 then
		return p, value, t;
	elseif hue_sector == 3 then
		return p, q, value;
	elseif hue_sector == 4 then
		return t, p, value;
	elseif hue_sector == 5 then
		return value, p, q;
	end;
end;

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

local function DrawMultipointTarget()
	if not multipoint_target_pos then
		return
	end

	local screen_pos = client.WorldToScreen(multipoint_target_pos)
	if not screen_pos then
		return
	end

	-- Draw a small square at the multipoint target position
	local square_size = 4

	-- Draw filled square
	draw.FilledRect(screen_pos[1] - square_size, screen_pos[2] - square_size,
	screen_pos[1] + square_size, screen_pos[2] + square_size)
end

local function Draw()
	if not settings.enabled then
		return
	end

	if displayed_time < globals.CurTime() then
		paths.player_path = {}
		paths.proj_path = {}
		multipoint_target_pos = nil
		return
	end

	if settings.draw_player_path and paths.player_path and #paths.player_path > 0 then
		--draw.Color(136, 192, 208, 255)
		if settings.colors.player_path >= 360 then
			draw.Color(255, 255, 255, 255)
		else
			local r, g, b = HSVToRGB(settings.colors.player_path, 0.5, 1)
			draw.Color((r*255)//1, (g*255)//1, (b*255)//1, 255)
		end
		DrawPlayerPath()
	end

	if settings.draw_bounding_box then
		local pos = paths.player_path[#paths.player_path]
		if pos then
			if settings.colors.bounding_box >= 360 then
			draw.Color(255, 255, 255, 255)
			else
				local r, g, b = HSVToRGB(settings.colors.bounding_box, 0.5, 1)
				draw.Color((r*255)//1, (g*255)//1, (b*255)//1, 255)
			end
			DrawPlayerHitbox(pos, target_min_hull, target_max_hull)
		end
	end

	if settings.draw_proj_path and paths.proj_path and #paths.proj_path > 0 then
		if settings.colors.projectile_path >= 360 then
			draw.Color(255, 255, 255, 255)
		else
			local r, g, b = HSVToRGB(settings.colors.projectile_path, 0.5, 1)
			draw.Color((r*255)//1, (g*255)//1, (b*255)//1, 255)
		end
		DrawProjPath()
	end

	-- Draw multipoint target indicator
	if settings.draw_multipoint_target then
		if settings.colors.multipoint_target >= 360 then
			draw.Color(255, 255, 255, 255)
		else
			local r, g, b = HSVToRGB(settings.colors.multipoint_target, 0.5, 1)
			draw.Color((r*255)//1, (g*255)//1, (b*255)//1, 255)
		end
		DrawMultipointTarget()
	end
end

local function FrameStage(stage)
	if stage == E_ClientFrameStage.FRAME_NET_UPDATE_END then
		local plocal = entities.GetLocalPlayer()
		if not plocal then return end

		local pweapon = plocal:GetPropEntity("m_hActiveWeapon")
		if not pweapon then return end

		player_sim.RunBackground(plocal, entitylist)
	end
end

---@param dme DrawModelContext
local function DrawModel(dme)
	if not pSelectedTarget then
		return
	end

	local ent = dme:GetEntity()
	if ent and ent:GetIndex() == pSelectedTarget:GetIndex() and dme:IsDrawingGlow() then
		local r, g, b = HSVToRGB(settings.colors.target_glow, 0.5, 1)
		if settings.colors.target_glow < 360 then
			dme:SetColorModulation(r, g, b)
		else
			dme:SetColorModulation(1, 1, 1)
		end
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
callbacks.Register("DrawModel", "ProjAimbot DrawModel", DrawModel)

printc(252, 186, 3, 255, string.format("Navet's Projectile Aimbot (v%s) loaded", version))
printc(166, 237, 255, 255, "Lmaobox's projectile aimbot will be turned off while this script is running")

if gui.GetValue("projectile aimbot") ~= "none" then
	gui.SetValue("projectile aimbot", "none")
end
