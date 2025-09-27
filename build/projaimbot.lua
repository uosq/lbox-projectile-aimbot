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
	Update: v9
	Source: https://github.com/uosq/lbox-projectile-aimbot
	
	This project would take way longer to start making
	if it weren't for them:
	Terminator - https://github.com/titaniummachine1
	GoodEvening - https://github.com/GoodEveningFellOff
--]]

---@diagnostic disable: cast-local-type

printc(186, 97, 255, 255, "The projectile aimbot is loading...")

local version = "10"

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
	draw_quads = true,
	show_angles = true,

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
		quads = 193,
	},

	thickness = {
		bounding_box = 1,
		player_path = 1,
		projectile_path = 1,
		multipoint_target = 1,
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

---@type Vector3?
local vAngles = nil

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
---@field m_iIndex integer

---@type table<integer, ENTRY>
local entitylist = {}

local rgbaData = string.char(255, 255, 255, 255)
local texture = draw.CreateTextureRGBA(rgbaData, 1, 1) --- 1x1 white pixel

---@param pos Vector3
---@param mins Vector3
---@param maxs Vector3
---@return Vector3[]
local function GetBoxVertices(pos, mins, maxs)
    local worldMins = pos + mins
    local worldMaxs = pos + maxs

    return {
        Vector3(worldMins.x, worldMins.y, worldMins.z), -- 1 bottom-back-left
        Vector3(worldMins.x, worldMaxs.y, worldMins.z), -- 2 bottom-front-left
        Vector3(worldMaxs.x, worldMaxs.y, worldMins.z), -- 3 bottom-front-right
        Vector3(worldMaxs.x, worldMins.y, worldMins.z), -- 4 bottom-back-right
        Vector3(worldMins.x, worldMins.y, worldMaxs.z), -- 5 top-back-left
        Vector3(worldMins.x, worldMaxs.y, worldMaxs.z), -- 6 top-front-left
        Vector3(worldMaxs.x, worldMaxs.y, worldMaxs.z), -- 7 top-front-right
        Vector3(worldMaxs.x, worldMins.y, worldMaxs.z), -- 8 top-back-right
    }
end

-- build a {x,y,u,v} vertex from a screen point {x,y}
local function XYUV(p, u, v)
    return { p[1], p[2], u, v }
end

-- draw a quad as two triangles in both windings (double sided)
local function DrawQuadFaceDoubleSided(tex, a, b, c, d)
    if not (a and b and c and d) then return end

    -- front (a,b,c) + (a,c,d)
    local f1 = { XYUV(a, 0, 0), XYUV(b, 1, 0), XYUV(c, 1, 1) }
    local f2 = { XYUV(a, 0, 0), XYUV(c, 1, 1), XYUV(d, 0, 1) }
    draw.TexturedPolygon(tex, f1, true)
    draw.TexturedPolygon(tex, f2, true)

    -- back (reverse winding): (a,c,b) + (a,d,c)
    local b1 = { XYUV(a, 0, 0), XYUV(c, 1, 1), XYUV(b, 1, 0) }
    local b2 = { XYUV(a, 0, 0), XYUV(d, 0, 1), XYUV(c, 1, 1) }
    draw.TexturedPolygon(tex, b1, true)
    draw.TexturedPolygon(tex, b2, true)
end

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
	if settings.show_angles then vAngles = uCmd.viewangles end
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
			entitylist[#entitylist+1] = {
				m_iIndex = building:GetIndex(),
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
				m_nCond = 0,
				m_nCondEx = 0,
				m_nCondEx2 = 0,
				m_nCondEx3 = 0,
				m_nCondEx4 = 0,
				m_nConditionBits = 0,
				priority = 0,
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
			entitylist[#entitylist+1] = {
				m_iIndex = player:GetIndex(),
				m_vecPos = player:GetPropVector("localdata", "m_vecOrigin") or player:GetAbsOrigin(),
				m_vecVelocity = player:EstimateAbsVelocity() or Vector3(),
				m_flFriction = player:GetPropFloat("m_flFriction") or 1.0,
				m_flAngularVelocity = player_sim.GetSmoothedAngularVelocity(player),
				m_flGravityStep = sv_gravity or 800.0,
				m_flMaxspeed = player:GetPropFloat("m_flMaxspeed") or 450,
				m_iTeam = enemy_team,
				m_flStepSize = player:GetPropFloat("m_flStepSize") or 18,
				m_vecMins = player:GetMins(),
				m_vecMaxs = player:GetMaxs(),

				m_nCond = player:GetPropInt("m_Shared", "m_nPlayerCond") or 0,
				m_nCondEx = player:GetPropInt("m_Shared", "m_nPlayerCondEx") or 0,
				m_nCondEx2 = player:GetPropInt("m_Shared", "m_nPlayerCondEx2") or 0,
				m_nCondEx3 = player:GetPropInt("m_Shared", "m_nPlayerCondEx3") or 0,
				m_nCondEx4 = player:GetPropInt("m_Shared", "m_nPlayerCondEx4") or 0,
				m_nConditionBits = player:GetPropInt("m_Shared", "m_ConditionList", "_condition_bits") or 0,
				priority = playerlist.GetPriority(player),
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
	vAngles = nil

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

	local pTarget, _, index = target_selector.Run(pLocal, vHeadPos, math_utils, entitylist, settings, bAimAtTeamMates)
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
	local pInfo = entitylist[index]
	if not pInfo then
		return
	end

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

local function DrawPlayerHitbox(playerPos, mins, maxs)
    local worldMins = playerPos + mins
    local worldMaxs = playerPos + maxs

    -- 8 corners of the AABB
    local v3 = {
        Vector3(worldMins.x, worldMins.y, worldMins.z), -- 1: bottom-back-left
        Vector3(worldMins.x, worldMaxs.y, worldMins.z), -- 2: bottom-front-left
        Vector3(worldMaxs.x, worldMaxs.y, worldMins.z), -- 3: bottom-front-right
        Vector3(worldMaxs.x, worldMins.y, worldMins.z), -- 4: bottom-back-right
        Vector3(worldMins.x, worldMins.y, worldMaxs.z), -- 5: top-back-left
        Vector3(worldMins.x, worldMaxs.y, worldMaxs.z), -- 6: top-front-left
        Vector3(worldMaxs.x, worldMaxs.y, worldMaxs.z), -- 7: top-front-right
        Vector3(worldMaxs.x, worldMins.y, worldMaxs.z), -- 8: top-back-right
    }

    -- Project 3D to 2D screen
    local v2 = {}
    for i = 1, 8 do
        v2[i] = client.WorldToScreen(v3[i])
    end

    -- If any corner is off-screen, skip
    for i = 1, 8 do
        if not v2[i] then return end
    end

    local edges = {
        {1,2},{2,3},{3,4},{4,1}, -- bottom
        {5,6},{6,7},{7,8},{8,5}, -- top
        {1,5},{2,6},{3,7},{4,8}, -- verticals
    }

	local thickness = settings.thickness.bounding_box

    for _, e in ipairs(edges) do
        local a, b = v2[e[1]], v2[e[2]]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local len = math.sqrt(dx*dx + dy*dy)
        if len > 0 then
            dx, dy = dx / len, dy / len
            local px, py = -dy * thickness, dx * thickness
            local verts = {
                {a[1] + px, a[2] + py, 0, 0},
                {a[1] - px, a[2] - py, 0, 1},
                {b[1] - px, b[2] - py, 1, 1},
                {b[1] + px, b[2] + py, 1, 0},
            }
            draw.TexturedPolygon(texture, verts, false)
        end
    end
end

local function DrawLine(p1, p2, thickness)
    local dx, dy = p2[1] - p1[1], p2[2] - p1[2]
    local len = math.sqrt(dx*dx + dy*dy)
    if len <= 0 then return end

    dx, dy = dx / len, dy / len
    local px, py = -dy * thickness, dx * thickness

    local verts = {
        {p1[1] + px, p1[2] + py, 0, 0},
        {p1[1] - px, p1[2] - py, 0, 1},
        {p2[1] - px, p2[2] - py, 1, 1},
        {p2[1] + px, p2[2] + py, 1, 0},
    }

    draw.TexturedPolygon(texture, verts, false)
end

local function DrawPlayerPath()
    if not paths.player_path or #paths.player_path < 2 then return end

    local last = client.WorldToScreen(paths.player_path[1])
    if not last then return end

    for i = 2, #paths.player_path do
        local current = client.WorldToScreen(paths.player_path[i])
        if current and last then
            DrawLine(last, current, settings.thickness.player_path)
        end
        last = current
    end
end

local function DrawMultipointTarget()
    if not multipoint_target_pos then return end
    local pos = client.WorldToScreen(multipoint_target_pos)
    if not pos then return end

    local s = settings.thickness.multipoint_target
    local verts = {
        {pos[1] - s, pos[2] - s, 0, 0},
        {pos[1] + s, pos[2] - s, 1, 0},
        {pos[1] + s, pos[2] + s, 1, 1},
        {pos[1] - s, pos[2] + s, 0, 1},
    }

    draw.TexturedPolygon(texture, verts, false)
end

local function DrawProjPath()
    if not paths.proj_path or #paths.proj_path < 2 then return end

    local last = client.WorldToScreen(paths.proj_path[1].pos)
    if not last then return end

    for i = 2, #paths.proj_path do
        local current = client.WorldToScreen(paths.proj_path[i].pos)
        if current and last then
            DrawLine(last, current, settings.thickness.projectile_path)
        end
        last = current
    end
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

	if settings.draw_quads then
		local pos = paths.player_path[#paths.player_path]
		local v3 = GetBoxVertices(pos, target_min_hull, target_max_hull)

        -- project to screen
        local v2 = {}
        for i, v in ipairs(v3) do
            v2[i] = client.WorldToScreen(v) -- {x,y} or nil if behind camera
        end

		if settings.colors.quads >= 360 then
			draw.Color(255, 255, 255, 25)
		else
			local r, g, b = HSVToRGB(settings.colors.quads, 0.5, 1)
			draw.Color((r*255)//1, (g*255)//1, (b*255)//1, 25)
		end

        -- faces: bottom, top, front, back, left, right
        DrawQuadFaceDoubleSided(texture, v2[1], v2[2], v2[3], v2[4]) -- bottom
        DrawQuadFaceDoubleSided(texture, v2[5], v2[6], v2[7], v2[8]) -- top
        DrawQuadFaceDoubleSided(texture, v2[2], v2[3], v2[7], v2[6]) -- front
        DrawQuadFaceDoubleSided(texture, v2[1], v2[4], v2[8], v2[5]) -- back
        DrawQuadFaceDoubleSided(texture, v2[1], v2[2], v2[6], v2[5]) -- left
        DrawQuadFaceDoubleSided(texture, v2[4], v2[3], v2[7], v2[8]) -- right
	end
end

local function FrameStage(stage)
	if stage == E_ClientFrameStage.FRAME_NET_UPDATE_END then
		local plocal = entities.GetLocalPlayer()
		if not plocal then return end

		player_sim.RunBackground(plocal, entitylist)
	elseif stage == E_ClientFrameStage.FRAME_RENDER_START and vAngles then
		local plocal = entities.GetLocalPlayer()
		if not plocal or not plocal:GetPropBool("m_nForceTauntCam") then return end
		plocal:SetVAngles(vAngles)
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

	draw.DeleteTexture(texture)
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

end)
__bundle_register("src.target_selector", function(require, _LOADED, __bundle_register, __bundle_modules)
--[[
    Target selection module
]]

local mod = {}

--- relative to Maxs().z
local z_offsets = {0.2, 0.4, 0.5, 0.7, 0.9}

---@param entityData table
---@param settings table
local function ShouldSkipPlayer(entityData, settings)
    local cond = entityData.m_nCond
    local condEx = entityData.m_nCondEx
    local condEx2 = entityData.m_nCondEx2
    local condition_bits = entityData.m_nConditionBits

    -- cloak/disguise/taunt/bonk
    if settings.ignore_conds.cloaked    and ((cond & E_TFCOND.TFCond_Cloaked)    ~= 0 or (condition_bits & (1<<cond)) ~= 0) then return true end
    if settings.ignore_conds.disguised  and ((cond & E_TFCOND.TFCond_Disguised)  ~= 0 or (condition_bits & (1<<cond)) ~= 0) then return true end
    if settings.ignore_conds.taunting   and ((cond & E_TFCOND.TFCond_Taunting)   ~= 0 or (condition_bits & (1<<cond)) ~= 0) then return true end
    if settings.ignore_conds.bonked     and ((cond & E_TFCOND.TFCond_Bonked)     ~= 0 or (condition_bits & (1<<cond)) ~= 0) then return true end

    -- uber / crit
    if settings.ignore_conds.ubercharged  and ((cond & E_TFCOND.TFCond_Ubercharged)  ~= 0 or condition_bits & (1<<cond) ~= 0) then return true end
    if settings.ignore_conds.kritzkrieged and ((cond & E_TFCOND.TFCond_Kritzkrieged) ~= 0 or condition_bits & (1<<cond) ~= 0) then return true end

    -- debuffs
    if settings.ignore_conds.jarated and ((cond & E_TFCOND.TFCond_Jarated) ~= 0 or condition_bits & (1<<cond) ~= 0) then return true end
    if settings.ignore_conds.milked  and ((cond & E_TFCOND.TFCond_Milked)  ~= 0 or condition_bits & (1<<cond) ~= 0) then return true end

    -- misc
    if settings.ignore_conds.ghost and (condEx2 & (1 << (E_TFCOND.TFCond_HalloweenGhostMode - 64))) ~= 0 then return true end

    -- friends / priority
    if entityData.priority < 0 and not settings.ignore_conds.friends then
        return true
    end
    if settings.min_priority > entityData.priority then
        return true
    end

    local VACCINATOR_MASK =
      E_TFCOND.TFCond_UberBulletResist
    | E_TFCOND.TFCond_UberBlastResist
    | E_TFCOND.TFCond_UberFireResist
    | E_TFCOND.TFCond_SmallBulletResist
    | E_TFCOND.TFCond_SmallBlastResist
    | E_TFCOND.TFCond_SmallFireResist

    -- vaccinator resistances (single mask)
    if settings.ignore_conds.vaccinator and (condEx & (1 << (VACCINATOR_MASK - 32))) ~= 0 then
        return true
    end

    return false
end

---@param pLocal Entity
---@param vHeadPos Vector3
---@param math_utils MathLib
---@param entitylist table<integer, ENTRY>
---@param settings table
---@param bAimAtTeamMates boolean
---@return Entity?, number?, integer?
function mod.Run(pLocal, vHeadPos, math_utils, entitylist, settings, bAimAtTeamMates)
    local bestFov = settings.fov
    local selected_entity = nil
    local nOffset = nil
    local trace
    local index = nil

    local close_distance = (settings.close_distance * 0.01) * settings.max_distance

    for _, entityInfo in ipairs (entitylist) do
        if not ShouldSkipPlayer(entityInfo, settings) then
            local vDistance = (vHeadPos - entityInfo.m_vecPos):Length()
            if vDistance <= settings.max_distance then
                for i = 1, #z_offsets do
                    local offset = z_offsets[i]
                    local zOffset = (entityInfo.m_vecMaxs.z * offset)
                    local origin = entityInfo.m_vecPos
                    origin.z = origin.z + zOffset

                    if (vHeadPos - origin):Length() <= close_distance then
                        local angle = math_utils.PositionAngles(vHeadPos, origin)
                        local fov = math_utils.AngleFov(angle, engine.GetViewAngles())
                        if fov <= bestFov then
                            bestFov = fov
                            selected_entity = entityInfo.m_iIndex
                            nOffset = zOffset
                        end
                    else
                        trace = engine.TraceLine(vHeadPos, origin, MASK_SHOT_HULL, function (ent, contentsMask)
                            return false
                        end)

                        if trace and trace.fraction >= 1 then
                            local angle = math_utils.PositionAngles(vHeadPos, origin)
                            local fov = math_utils.AngleFov(angle, engine.GetViewAngles())
                            if fov <= bestFov then
                                bestFov = fov
                                selected_entity = entityInfo.m_iIndex
                                index = entityInfo.m_iIndex
                                nOffset = zOffset
                            end
                        end
                    end
                end
            end
        end
    end

    if selected_entity == nil then
        return nil, nil
    end

    return entities.GetByIndex(selected_entity), nOffset, index
end

return mod
end)
__bundle_register("src.multipoint", function(require, _LOADED, __bundle_register, __bundle_modules)
local multipoint = {}

--- relative to Maxs().z
local z_offsets = {0.5, 0.7, 0.9, 0.4, 0.2}

--- inverse of z_offsets
local huntsman_z_offsets = {0.9, 0.7, 0.5, 0.4, 0.2}

local splash_offsets = {0.2, 0.4, 0.5, 0.7, 0.9}

---@param vHeadPos Vector3
---@param pTarget Entity
---@param vecPredictedPos Vector3
---@param pWeapon Entity
---@param weaponInfo WeaponInfo
function multipoint.Run(pTarget, pWeapon, weaponInfo, vHeadPos, vecPredictedPos)
	local proj_type = pWeapon:GetWeaponProjectileType()
	local bExplosive = weaponInfo.m_flDamageRadius > 0 and
		proj_type == E_ProjectileType.TF_PROJECTILE_ROCKET or
		proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB or
		proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_REMOTE or
		proj_type == E_ProjectileType.TF_PROJECTILE_STICKY_BALL or
		proj_type == E_ProjectileType.TF_PROJECTILE_CANNONBALL or
		proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_PRACTICE

	local bSplashWeapon = proj_type == E_ProjectileType.TF_PROJECTILE_ROCKET
		or proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_REMOTE
		or proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB_PRACTICE
		or proj_type == E_ProjectileType.TF_PROJECTILE_CANNONBALL
		or proj_type == E_ProjectileType.TF_PROJECTILE_PIPEBOMB
		or proj_type == E_ProjectileType.TF_PROJECTILE_STICKY_BALL
		or proj_type == E_ProjectileType.TF_PROJECTILE_FLAME_ROCKET

	local bHuntsman = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW
	local chosen_offsets = bHuntsman and huntsman_z_offsets or (bSplashWeapon or bExplosive) and splash_offsets or z_offsets

    local trace

    for i = 1, #z_offsets do
        local offset = chosen_offsets[i]
        local zOffset = (pTarget:GetMaxs().z * offset)
        local origin = vecPredictedPos + Vector3(0, 0, zOffset)

        trace = engine.TraceHull(vHeadPos, origin, weaponInfo.m_vecMins, weaponInfo.m_vecMaxs, weaponInfo.m_iTraceMask, function (ent, contentsMask)
            return false
        end)

    	if trace and trace.fraction >= 1 then
			vecPredictedPos.z = origin.z
			return
    	end
    end
end

return multipoint
end)
__bundle_register("src.gui", function(require, _LOADED, __bundle_register, __bundle_modules)
local gui = {}

local ui = require("src.ui")

---@param settings table
---@param version string
function gui.init(settings, version)
	local menu = ui.New({title=string.format("NAVET'S PROJECTILE AIMBOT (v%s)", tostring(version))})
	menu.y = 50
	menu.x = 50
	-- Create tabs
	local aim_tab = menu:CreateTab("aimbot")
	local misc_tab = menu:CreateTab("misc")
	local conds_tab = menu:CreateTab("conditions")
	local colors_tab = menu:CreateTab("colors")
	local thick_tab = menu:CreateTab("thickness")

	local component_width = 260
	local component_height = 25

	-- AIMBOT TAB
	-- Left column toggles
	menu:CreateToggle(aim_tab, component_width, component_height, "enabled", settings.enabled, function(checked)
		settings.enabled = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "autoshoot", settings.autoshoot, function(checked)
		settings.autoshoot = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "draw projectile path", settings.draw_proj_path, function(checked)
		settings.draw_proj_path = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "draw player path", settings.draw_player_path, function(checked)
		settings.draw_player_path = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "draw bounding box", settings.draw_bounding_box, function(checked)
		settings.draw_bounding_box = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "draw only", settings.draw_only, function(checked)
		settings.draw_only = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "draw multpoint target", settings.draw_multipoint_target, function(checked)
		settings.draw_multipoint_target = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "cancel shot", settings.cancel_shot, function(checked)
		settings.cancel_shot = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "draw filled bounding box", settings.draw_quads, function(checked)
		settings.draw_quads = checked
	end)

	-- Right column toggles
	menu:CreateToggle(aim_tab, component_width, component_height, "allow aim at teammates", settings.allow_aim_at_teammates, function(checked)
		settings.allow_aim_at_teammates = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "silent+", settings.psilent, function(checked)
		settings.psilent = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "ping compensation", settings.ping_compensation, function(checked)
		settings.ping_compensation = checked
	end)

	-- Entity toggles
	for name, enabled in pairs(settings.ents) do
		menu:CreateToggle(aim_tab, component_width, component_height, name, enabled, function(checked)
			settings.ents[name] = checked
		end)
	end

	menu:CreateToggle(aim_tab, component_width, component_height, "wait for charge (laggy)", settings.wait_for_charge, function(checked)
		settings.wait_for_charge = checked
	end)

	menu:CreateToggle(aim_tab, component_width, component_height, "show angles", settings.show_angles, function(checked)
		settings.show_angles = checked
	end)

	-- MISC TAB
	menu:CreateSlider(misc_tab, component_width, 20, "max sim time", 0.5, 10, settings.max_sim_time, function(value)
		settings.max_sim_time = value
	end)

	menu:CreateSlider(misc_tab, component_width, 20, "max distance", 0, 4096, settings.max_distance, function(value)
		settings.max_distance = value
	end)

	menu:CreateSlider(misc_tab, component_width, 20, "fov", 0, 180, settings.fov, function(value)
		settings.fov = value
	end)

	menu:CreateSlider(misc_tab, component_width, 20, "min priority", 0, 10, settings.min_priority, function(value)
		settings.min_priority = math.floor(value)
	end)

	menu:CreateSlider(misc_tab, component_width, 20, "draw time", 0, 10, settings.draw_time, function(value)
		settings.draw_time = value
	end)

	menu:CreateSlider(misc_tab, component_width, 20, "max charge (%)", 0, 100, settings.max_percent, function(value)
		settings.max_percent = value
	end)

	menu:CreateSlider(misc_tab, component_width, 20, "close distance (%)", 0, 100, settings.close_distance, function(value)
		settings.close_distance = value
	end)

	-- CONDITIONS TAB
	for name, enabled in pairs(settings.ignore_conds) do
		menu:CreateToggle(conds_tab, component_width, component_height, string.format("ignore %s", name), enabled, function(checked)
			settings.ignore_conds[name] = checked
		end)
	end

	-- COLORS TAB
	for name, visual in pairs(settings.colors) do
		local label = string.gsub(name, "_", " ")
		menu:CreateHueSlider(colors_tab, component_width, component_height, label, visual, function(value)
			settings.colors[name] = math.floor(value)
		end)
	end

	-- THICKNESS TAB
	for name, visual in pairs(settings.thickness) do
		local label = string.gsub(name, "_", " ")
		menu:CreateSlider(thick_tab, component_width, component_height, label, 0.1, 5, visual, function(value)
			settings.thickness[name] = math.floor(value)
		end)
	end

	callbacks.Register("Draw", function (...)
		menu:Draw()
	end)
	printc(150, 255, 150, 255, "[PROJ AIMBOT] Menu loaded")
end

function gui.unload()
	ui.Unload()
end

return gui
end)
__bundle_register("src.ui", function(require, _LOADED, __bundle_register, __bundle_modules)
---@class Context
---@field mouseX integer
---@field mouseY integer
---@field mouseDown boolean
---@field mouseReleased boolean
---@field mousePressed boolean
---@field tick integer
---@field lastPressedTick integer
---@field windowX integer
---@field windowY integer

local theme = {
    bg_light = {45, 45, 45},
    bg = {35, 35, 35},
    bg_dark = {30, 30, 30},
    primary = {143, 188, 187},
    success = {69, 255, 166},
    fail = {255, 69, 69},
}

local thickness = 1 --- outline thickness
local header_size = 25 --- title height
local tab_section_width = 100

local max_objects_per_column = 9
local column_spacing = 10
local row_spacing = 5
local element_margin = 5

---@class GuiWindow
local window = {
    dragging = false,
    mx = 0, my = 0,
    x = 0,
    y = 0,
    w = 0,
    h = 0,
    title = "",
    tabs = {},
    current_tab = 1,
}

local lastPressedTick = 0
local font = draw.CreateFont("TF2 BUILD", 12, 400, FONTFLAG_ANTIALIAS | FONTFLAG_CUSTOM)
local white_texture = draw.CreateTextureRGBA(string.rep(string.char(255, 255, 255, 255), 4), 2, 2)

---@param texture TextureID
---@param centerX integer
---@param centerY integer
---@param radius integer
---@param segments integer
local function DrawFilledCircle(texture, centerX, centerY, radius, segments)
    local vertices = {}

    for i = 0, segments do
        local angle = (i / segments) * math.pi * 2
        local x = centerX + math.cos(angle) * radius
        local y = centerY + math.sin(angle) * radius
        vertices[i + 1] = {x, y, 0, 0}
    end

    draw.TexturedPolygon(texture, vertices, false)
end

local function draw_tab_button(parent, x, y, width, height, label, i)
    local mousePos = input.GetMousePos()
    local mx, my = mousePos[1], mousePos[2]
    local mouseInside = mx >= x and mx <= x + width
        and my >= y and my <= y + height

    --draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
    --draw.FilledRect(x - thickness, y - thickness, x + width + thickness, y + height + thickness)

    if (mouseInside and input.IsButtonDown(E_ButtonCode.MOUSE_LEFT)) then
        draw.Color(theme.bg_light[1], theme.bg_light[2], theme.bg_light[3], 255)
    elseif (mouseInside) then
        draw.Color(theme.bg[1], theme.bg[2], theme.bg[3], 255)
    else
        draw.Color(theme.bg_dark[1], theme.bg_dark[2], theme.bg_dark[3], 255)
    end
    draw.FilledRect(x, y, x + width, y + height)

    if (parent.current_tab == i) then
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.FilledRect(x + 2, y + 2, x + 4, y + height - 2)
    end

    local tw, th = draw.GetTextSize(label)
    local tx, ty
    tx = (x + (width*0.5) - (tw*0.5))//1
    ty = (y + (height*0.5) - (th*0.5))//1

    draw.Color(242, 242, 242, 255)
    draw.Text(tx, ty, label)

    local pressed, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_FIRST)

    if (mouseInside and pressed and tick > lastPressedTick) then
        parent.current_tab = i
    end
end

local function hsv_to_rgb(h, s, v)
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)

    i = i % 6

    if i == 0 then
        r, g, b = v, t, p
    elseif i == 1 then
        r, g, b = q, v, p
    elseif i == 2 then
        r, g, b = p, v, t
    elseif i == 3 then
        r, g, b = p, q, v
    elseif i == 4 then
        r, g, b = t, p, v
    elseif i == 5 then
        r, g, b = v, p, q
    end

    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

function window.Draw(self)
    if (not gui.IsMenuOpen()) then
        return
    end

    local x, y = self.x, self.y
    local tab = self.tabs[self.current_tab]
    local w = (tab and tab.w or 200)
    local h = (tab and tab.h or 200)
    local title = self.title

    local mousePressed, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
    local mousePos = input.GetMousePos()

    local dx, dy = mousePos[1] - self.mx, mousePos[2] - self.my
    if (self.dragging) then
        self.x = self.x + dx
        self.y = self.y + dy
    end

    draw.SetFont(font)

    local numTabs = #self.tabs
    local extra_width = (numTabs > 1) and tab_section_width or 0

    local total_w = w + extra_width

    -- draw window outline & background
    draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
    draw.OutlinedRect(x - thickness, y - thickness, x + total_w + thickness, y + h + thickness)

    draw.Color(theme.bg_dark[1], theme.bg_dark[2], theme.bg_dark[3], 255)
    draw.FilledRect(x, y, x + total_w, y + h)

    -- draw tabs if needed
    if (numTabs > 1) then
        draw.Color(theme.bg_light[1], theme.bg_light[2], theme.bg_light[3], 255)
        draw.FilledRect(x, y, x + tab_section_width, y + h)

        local btnx, btny = x, y
        for i, t in ipairs(self.tabs) do
            draw_tab_button(self, btnx, btny, tab_section_width, 25, t.name, i)
            btny = btny + 25
        end
    end

    -- header
    if (title and #title > 0) then
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.FilledRect(x - thickness, y - header_size, x + total_w + thickness, y - thickness)

        local tw, th = draw.GetTextSize(title)
        local tx = (x - thickness + total_w * 0.5 - tw * 0.5)//1
        local ty = (y - thickness - header_size*0.5 - th*0.5)//1

        draw.Color(242, 242, 242, 255)
        draw.Text(tx, ty, title)

        -- dragging check
        if (mousePos[1] >= x and mousePos[1] <= x + total_w) and (mousePos[2] >= y - header_size and mousePos[2] <= y) then
            local state, thistick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
            if (state and thistick > lastPressedTick) then
                self.dragging = true
            end
        end

        if (input.IsButtonReleased(E_ButtonCode.MOUSE_LEFT) and self.dragging) then
            self.dragging = false
        end
    end

    -- adjust context X for drawing objs
    local content_x = x + extra_width

    local context = {
        mouseX = mousePos[1], mouseY = mousePos[2],
        mouseDown = input.IsButtonDown(E_ButtonCode.MOUSE_LEFT),
        mouseReleased = input.IsButtonReleased(E_ButtonCode.MOUSE_LEFT),
        mousePressed = mousePressed,
        tick = tick,
        lastPressedTick = lastPressedTick,
        windowX = content_x,
        windowY = y,
    }

    if (tab) then
        for i = #tab.objs, 1, -1 do
            local obj = tab.objs[i]
            if obj then
                obj:Draw(context)
            end
        end
    end

    lastPressedTick = tick
    self.mx, self.my = mousePos[1], mousePos[2]
end

function window:SetCurrentTab(tab_index)
    if (tab_index > #self.tabs or tab_index < 0) then
        error(string.format("Invalid tab index! Received %s", tab_index))
        return false
    end

    self.current_tab = tab_index
    return true
end

function window:CreateTab(tab_name)
    if (#self.tabs == 1 and self.tabs[1].name == "") then
        --- replace the default tab
        --- just in case we have more than 1 tabs
        self.tabs[1].name = tab_name
        return 1
    else
        self.tabs[#self.tabs + 1] = {
            name = tab_name,
            objs = {}
        }
        return #self.tabs
    end
end

--- recalculates positions of all objs in all tabs
--- and adjusts window size to fit contents
function window:RecalculateLayout(tab_index)
    if not tab_index or not self.tabs[tab_index] then return end
    local tab = self.tabs[tab_index]

    local col, row = 0, 0
    local col_widths, col_heights = {}, {}
    local current_col_width = 0

    --- calculate positions and track column dimensions
    for i, obj in ipairs(tab.objs) do
        --- track the maximum width in current column
        if obj.w > current_col_width then
            current_col_width = obj.w
        end

        -- calculate x position using previously completed column widths
        local x_offset = element_margin
        for j = 1, col do
            x_offset = x_offset + (col_widths[j] or 0) + column_spacing
        end
        obj.x = x_offset

        --- calc y position
        obj.y = element_margin + row * (obj.h + row_spacing)

        row = row + 1
        if row >= max_objects_per_column then
            col_widths[col + 1] = current_col_width
            col_heights[col + 1] = row * (obj.h + row_spacing)

            --- move to next column
            row = 0
            col = col + 1
            current_col_width = 0
        end
    end

    --- handle the last column if it has elements
    if row > 0 and #tab.objs > 0 then
        col_widths[col + 1] = current_col_width
        col_heights[col + 1] = row * (tab.objs[#tab.objs].h + row_spacing)
    end

    --- get total tab width
    local tab_w = element_margin * 2  --- left and right margins
    for i, w in ipairs(col_widths) do
        tab_w = tab_w + w
        if i < #col_widths then
            tab_w = tab_w + column_spacing
        end
    end

    --- calculate total tab height (maximum of all column heights)
    local tab_h = 0
    for _, h in ipairs(col_heights) do
        if h > tab_h then tab_h = h end
    end
    tab_h = tab_h + element_margin * 2

    --- save tab size
    tab.w = tab_w
    tab.h = tab_h
end

function window:InsertElement(object, tab_index)
    tab_index = tab_index or self.current_tab or 1
    if (tab_index > #self.tabs or tab_index < 0) then
        error(string.format("Invalid tab index! Received %s", tab_index))
        return false
    end

    local tab = self.tabs[tab_index]
    tab.objs[#tab.objs + 1] = object
    self:RecalculateLayout(tab_index)
    return true
end

---@param func fun(checked: boolean)?
function window:CreateToggle(tab_index, width, height, label, checked, func)
    local btn = {
        x = 0, y = 0,
        w = width, h = height,
        label = label, func = func,
        checked = checked,
    }

    ---@param context Context
    function btn:Draw(context)
        local bx, by, bw, bh
        bx = self.x + context.windowX
        by = self.y + context.windowY
        bw = self.w
        bh = self.h

        local mx, my = context.mouseX, context.mouseY
        local mouseInside = mx >= bx and mx <= bx + bw
            and my >= by and my <= by + bh

        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.OutlinedRect(bx - thickness, by - thickness, bx + bw + thickness, by + bh + thickness)

        if (mouseInside and context.mouseDown) then
            draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        elseif (mouseInside) then
            draw.Color(theme.bg_light[1], theme.bg_light[2], theme.bg_light[3], 255)
        else
            draw.Color(theme.bg[1], theme.bg[2], theme.bg[3], 255)
        end
        draw.FilledRect(bx, by, bx + bw, by + bh)

        local tw, th = draw.GetTextSize(self.label)
        local tx, ty
        tx = bx + 2
        ty = (by + bh*0.5 - th*0.5)//1

        draw.Color(242, 242, 242, 255)
        draw.Text(tx, ty, label)

        local circle_x = bx + bw - 10
        local circle_y = (by + bh*0.5)//1
        local radius = 8

        if (btn.checked) then
            draw.Color(theme.success[1], theme.success[2], theme.success[3], 255)
        else
            draw.Color(theme.fail[1], theme.fail[2], theme.fail[3], 255)
        end

        DrawFilledCircle(white_texture, circle_x, circle_y, radius, 4)

        if (mouseInside and context.mousePressed and context.tick > context.lastPressedTick) then
            btn.checked = not btn.checked

            if (func) then
                func(btn.checked)
            end
        end
    end

    self:InsertElement(btn, tab_index or self.current_tab)
    return btn
end

---@param func fun(value: number)?
function window:CreateSlider(tab_index, width, height, label, min, max, currentvalue, func)
    local slider = {
        x = 0, y = 0,
        w = width, h = height,
        label = label, func = func,
        min = min, max = max,
        value = currentvalue
    }

    ---@param context Context
    function slider:Draw(context)
        local bx, by, bw, bh
        bx = self.x + context.windowX
        by = self.y + context.windowY
        bw = self.w
        bh = self.h

        local mx, my = context.mouseX, context.mouseY
        local mouseInside = mx >= bx and mx <= bx + bw
            and my >= by and my <= by + bh

        --- draw outline
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.OutlinedRect(bx - thickness, by - thickness, bx + bw + thickness, by + bh + thickness)

        --- draw background based on mouse state
        if (mouseInside and context.mouseDown) then
            draw.Color(theme.bg_light[1], theme.bg_light[2], theme.bg_light[3], 255)
        elseif (mouseInside) then
            draw.Color(theme.bg[1], theme.bg[2], theme.bg[3], 255)
        else
            draw.Color(theme.bg_dark[1], theme.bg_dark[2], theme.bg_dark[3], 255)
        end
        draw.FilledRect(bx, by, bx + bw, by + bh)

        -- calculate percentage for the slider fill
        local percent = (self.value - self.min) / (self.max - self.min)
        percent = math.max(0, math.min(1, percent)) --- clamp it ;)

        --- draw slider fill
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.FilledRect(bx, by, (bx + (bw * percent))//1, by + bh)

        --- draw label text
        local tw, th = draw.GetTextSize(self.label)
        local tx, ty
        tx = bx + 2
        ty = (by + bh * 0.5 - th * 0.5)//1
        draw.Color(242, 242, 242, 255)
        draw.TextShadow(tx + 2, ty, self.label)

        tw = draw.GetTextSize(string.format("%.0f", self.value))
        tx = bx + bw - tw - 2
        draw.TextShadow(tx, ty, string.format("%.0f", self.value))

        --- handle mouse interaction
        if (mouseInside and context.mousePressed and context.tick > context.lastPressedTick) then
            self.isDragging = true
        end

        --- continue dragging even if mouse is outside the slider
        if (self.isDragging and context.mouseDown) then
            --- update slider value based on mouse position
            local mousePercent = (mx - bx) / bw
            mousePercent = math.max(0, math.min(1, mousePercent))
            self.value = self.min + (self.max - self.min) * mousePercent

            if (self.func) then
                self.func(self.value)
            end
        elseif (not context.mouseDown) then
            --- stop dragging when mouse is released
            self.isDragging = false
        end
    end

    self:InsertElement(slider, tab_index or self.current_tab)
    return slider
end

---@param func fun(value: number)?
function window:CreateHueSlider(tab_index, width, height, label, currentvalue, func)
    local slider = {
        x = 0, y = 0,
        w = width, h = height,
        label = label, func = func,
        min = 0, max = 360,
        value = currentvalue
    }

    ---@param context Context
    function slider:Draw(context)
        local bx, by, bw, bh
        bx = self.x + context.windowX
        by = self.y + context.windowY
        bw = self.w
        bh = self.h

        local mx, my = context.mouseX, context.mouseY
        local mouseInside = mx >= bx and mx <= bx + bw
            and my >= by and my <= by + bh

        --- draw outline
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.OutlinedRect(bx - thickness, by - thickness, bx + bw + thickness, by + bh + thickness)

        --- draw background
        draw.Color(theme.bg_dark[1], theme.bg_dark[2], theme.bg_dark[3], 255)
        draw.FilledRect(bx, by, bx + bw, by + bh)

        -- calculate percentage for the slider indicator
        local percent = (self.value - self.min) / (self.max - self.min)
        percent = math.max(0, math.min(1, percent))

        --- draw slider indicator line
        local indicator_x = (bx + (bw * percent))//1
        if (self.value == 360) then
            draw.Color(255, 255, 255, 255)
        else
            local r, g, b = hsv_to_rgb(self.value/360, 1.0, 1.0)
            draw.Color(r, g, b, 255)
        end
        draw.FilledRect(bx, (by + bh*0.6)//1, indicator_x, by + bh)

        --- draw label text with shadow for better visibility
        local tw, th = draw.GetTextSize(self.label)
        local tx, ty
        tx = bx + 2
        ty = by + 2

        -- Draw main text
        draw.Color(242, 242, 242, 255)
        draw.TextShadow(tx, ty, self.label)

        --- handle mouse interaction
        if (mouseInside and context.mousePressed and context.tick > context.lastPressedTick) then
            self.isDragging = true
        end

        --- continue dragging even if mouse is outside the slider
        if (self.isDragging and context.mouseDown) then
            --- update slider value based on mouse position
            local mousePercent = (mx - bx) / bw
            mousePercent = math.max(0, math.min(1, mousePercent))
            self.value = self.min + (self.max - self.min) * mousePercent

            if (self.func) then
                self.func(self.value)
            end
        elseif (not context.mouseDown) then
            --- stop dragging when mouse is released
            self.isDragging = false
        end
    end

    self:InsertElement(slider, tab_index or self.current_tab)
    return slider
end

---@return GuiWindow
function window.New(tbl)
    local newWindow = tbl or {}
    setmetatable(newWindow, {__index = window})
    newWindow.tabs[1] = {name="", objs={}}
    return newWindow
end

function window.Unload()
    draw.DeleteTexture(white_texture)
end

return window
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
		m_bHasGravity = tbl.bGravity == nil and true or tbl.bGravity,

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
				MASK_SHOT_HULL
			) -- MASK_SHOT_HULL

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

		HasGravity = (not tbl.HasGravity) and function(self, ...)
			return self.m_bHasGravity
		end or tbl.HasGravity,
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
	bGravity = false,

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
	bGravity = false,
})

AppendItemDefinitions(
	3,
	730 -- The Beggar's Bazooka
)
aProjectileInfo[3] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	flDamageRadius = 116.8,
	bGravity = false,
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
	bGravity = false,
})

AppendItemDefinitions(
	6,
	414 -- The Liberty Launcher
)
aProjectileInfo[6] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	vecVelocity = Vector3(1550, 0, 0),
	bGravity = false,
})

AppendItemDefinitions(
	7,
	513 -- The Original
)
aProjectileInfo[7] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
	bGravity = false,
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
	bGravity = false,

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
	bGravity = false,

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
	flGravity = 1,
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
	flDrag = 0.5,
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

		local resultTrace = TRACE_HULL(vecLocalView, vecFirePos, -Vector3(8, 8, 8), Vector3(8, 8, 8), MASK_SHOT_HULL) -- MASK_SOLID_BRUSHONLY

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
	bGravity = false,
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
	bGravity = false,
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
	bGravity = false,
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
	iTraceMask = MASK_SHOT_HULL, -- MASK_SHOT_HULL
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

--- source: https://developer.mozilla.org/en-US/docs/Games/Techniques/3D_collision_detection
---@param currentPos Vector3
---@param vecTargetPredictedPos Vector3
---@param weaponInfo WeaponInfo
---@param vecTargetMaxs Vector3
---@param vecTargetMins Vector3
local function IsIntersectingBB(currentPos, vecTargetPredictedPos, weaponInfo, vecTargetMaxs, vecTargetMins)
    local vecProjMins = weaponInfo.m_vecMins + currentPos
    local vecProjMaxs = weaponInfo.m_vecMaxs + currentPos

    local targetMins = vecTargetMins + vecTargetPredictedPos
    local targetMaxs = vecTargetMaxs + vecTargetPredictedPos

    -- check overlap on X, Y, and Z
    if vecProjMaxs.x < targetMins.x or vecProjMins.x > targetMaxs.x then return false end
    if vecProjMaxs.y < targetMins.y or vecProjMins.y > targetMaxs.y then return false end
    if vecProjMaxs.z < targetMins.z or vecProjMins.z > targetMaxs.z then return false end

    return true -- all axis overlap
end

---@param pTarget Entity The target
---@param pLocal Entity The localplayer
---@param pWeapon Entity The localplayer's weapon
---@param shootPos Vector3
---@param vecForward Vector3 The target direction the projectile should aim for
---@param nTime number Number of seconds we want to simulate
---@param weapon_info WeaponInfo
---@param charge_time number The charge time (0.0 to 1.0 for bows, 0.0 to 4.0 for stickies)
---@param vecPredictedPos Vector3
---@return ProjSimRet, boolean
function sim.Run(pTarget, pLocal, pWeapon, shootPos, vecForward, vecPredictedPos, nTime, weapon_info, charge_time)
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
	local targetmins, targetmaxs = pTarget:GetMaxs(), pTarget:GetMins()

	-- Decide trace mode: use line trace only for rocket-type projectiles
	local proj_type = pWeapon:GetWeaponProjectileType() or 0
	local use_line_trace = (
		proj_type == E_ProjectileType.TF_PROJECTILE_ROCKET or
		proj_type == E_ProjectileType.TF_PROJECTILE_FLAME_ROCKET or
		proj_type == E_ProjectileType.TF_PROJECTILE_SENTRY_ROCKET
	)
	local trace_mask = weapon_info.m_iTraceMask or MASK_SHOT_HULL
	local filter = function(ent)
		if ent:GetTeamNumber() ~= pLocal:GetTeamNumber() then
			return false
		end

		if ent:GetIndex() == pLocal:GetIndex() then
			return false
		end

		return true
	end

	-- Get the velocity vector from weapon info (includes upward velocity)
	local velocity_vector = weapon_info:GetVelocity(charge_time)
	local forward_speed = velocity_vector.x
	local upward_speed = velocity_vector.z or 0

	-- Calculate the final velocity vector with proper upward component
	local velocity = (vecForward * forward_speed) + (Vector3(0, 0, 1) * upward_speed)

	local has_gravity = weapon_info:HasGravity()
	if has_gravity then
		env:SetGravity(Vector3(0, 0, -800))
	else
		env:SetGravity(Vector3(0, 0, 0))
	end

	projectile:SetPosition(shootPos, vecForward, true)
	projectile:SetVelocity(velocity, weapon_info:GetAngularVelocity(charge_time))

	local tickInterval = globals.TickInterval()
	local positions = {}
	local hittarget = false

	while env:GetSimulationTime() < nTime do
		local currentPos = projectile:GetPosition()

		-- Perform a single collision trace per tick using the pre-decided mode
		local trace
		if use_line_trace then
			trace = engine.TraceLine(shootPos, currentPos, trace_mask, filter)
		else
			trace = engine.TraceHull(shootPos, currentPos, mins, maxs, trace_mask, filter)
		end

		if trace and trace.fraction >= 1 then
			local record = {
				pos = currentPos,
				time_secs = env:GetSimulationTime(),
			}

			positions[#positions + 1] = record
			shootPos = currentPos

			if IsIntersectingBB(currentPos, vecPredictedPos, weapon_info, targetmins, targetmaxs) then
				hittarget = true
				break
			end
		else
			break
		end

		env:Simulate(tickInterval)
	end

	env:ResetSimulationClock()
	projectile:Sleep()
	return positions, hittarget
end

return sim

end)
__bundle_register("src.simulation.player", function(require, _LOADED, __bundle_register, __bundle_modules)
---@diagnostic disable: duplicate-doc-field, missing-fields

local sim                   = {}

local MASK_SHOT_HULL        = MASK_SHOT_HULL
local MASK_PLAYERSOLID      = MASK_PLAYERSOLID
local DoTraceHull           = engine.TraceHull
local TraceLine             = engine.TraceLine
local Vector3               = Vector3
local math_deg              = math.deg
local math_rad              = math.rad
local math_atan             = math.atan
local math_cos              = math.cos
local math_sin              = math.sin
local math_abs              = math.abs
local math_acos             = math.acos
local math_min              = math.min
local math_max              = math.max
local math_floor            = math.floor
local math_pi               = math.pi

-- constants
local MIN_SPEED             = 25 -- HU/s
local MAX_ANGULAR_VEL       = 360 -- deg/s
local WALKABLE_ANGLE        = 45 -- degrees
local MIN_VELOCITY_Z        = 0.1
local AIR_ACCELERATE        = 10.0 -- Default air acceleration value
local GROUND_ACCELERATE     = 10.0 -- Default ground acceleration value
local SURFACE_FRICTION      = 1.0 -- Default surface friction

local MAX_CLIP_PLANES       = 5
local DIST_EPSILON          = 0.03125 -- Small epsilon for step calculations

local MAX_SAMPLES           = 16 -- tuned window size
local SMOOTH_ALPHA_G        = 0.392 -- tuned ground α
local SMOOTH_ALPHA_A        = 0.127 -- tuned air α

local COORD_FRACTIONAL_BITS = 5
local COORD_DENOMINATOR     = (1 << (COORD_FRACTIONAL_BITS))
local COORD_RESOLUTION      = (1.0 / (COORD_DENOMINATOR))

local impact_planes         = {}
local MAX_IMPACT_PLANES     = 5

---@class Sample
---@field pos Vector3
---@field time number

---@type table<number, Sample[]>
local position_samples      = {}

local zero_vector           = Vector3(0, 0, 0)
local up_vector             = Vector3(0, 0, 1)
local down_vector           = Vector3()

---this "zero-GC" shit is killing me

local RuneTypes_t           = {
	RUNE_NONE = -1,
	RUNE_STRENGTH = 0,
	RUNE_HASTE = 1,
	RUNE_REGEN = 2,
	RUNE_RESIST = 3,
	RUNE_VAMPIRE = 4,
	RUNE_REFLECT = 5,
	RUNE_PRECISION = 6,
	RUNE_AGILITY = 7,
	RUNE_KNOCKOUT = 8,
	RUNE_KING = 9,
	RUNE_PLAGUE = 10,
	RUNE_SUPERNOVA = 11,
	RUNE_TYPES_MAX = 12,
};

local function GetEntityOrigin(pEntity)
	return pEntity:GetPropVector("tflocaldata", "m_vecOrigin") or pEntity:GetAbsOrigin()
end

---@param vec Vector3
local function NormalizeVector(vec)
	local len = vec:Length()
	return len == 0 and vec or vec / len
end

---@param pTarget Entity
---@return number
local function GetAirSpeedCap(pTarget)
	local m_hGrapplingHookTarget = pTarget:GetPropEntity("m_hGrapplingHookTarget")
	if m_hGrapplingHookTarget then
		if pTarget:GetCarryingRuneType() == RuneTypes_t.RUNE_AGILITY then
			local m_iClass = pTarget:GetPropInt("m_iClass")
			if m_iClass == E_Character.TF2_Soldier or E_Character.TF2_Heavy then
				return 850
			else
				return 950
			end
		end

		local _, tf_grapplinghook_move_speed = client.GetConVar("tf_grapplinghook_move_speed")
		return tf_grapplinghook_move_speed
	elseif pTarget:InCond(E_TFCOND.TFCond_Charging) then
		local _, tf_max_charge_speed = client.GetConVar("tf_max_charge_speed")
		return tf_max_charge_speed
	else
		--- BaseClass::GetAirSpeedCap() returns 30
		local flCap = 30.0

		if pTarget:InCond(E_TFCOND.TFCond_ParachuteDeployed) then
			local _, tf_parachute_aircontrol = client.GetConVar("tf_parachute_aircontrol")
			flCap = flCap * tf_parachute_aircontrol
		end

		if pTarget:InCond(E_TFCOND.TFCond_HalloweenKart) then
			if pTarget:InCond(E_TFCOND.TFCond_HalloweenKartDash) then
				local _, tf_halloween_kart_dash_speed = client.GetConVar("tf_halloween_kart_dash_speed")
				return tf_halloween_kart_dash_speed
			end
			local _, tf_hallowen_kart_aircontrol = client.GetConVar("tf_hallowen_kart_aircontrol")
			flCap = flCap * tf_hallowen_kart_aircontrol
		end

		local flIncreasedAirControl = pTarget:AttributeHookFloat("mod_air_control")
		return flCap * flIncreasedAirControl
	end
end

---@param velocity Vector3
---@param normal Vector3
---@param overbounce number
local function ClipVelocity(velocity, normal, overbounce)
	local backoff = velocity:Dot(normal)

	if backoff < 0 then
		backoff = backoff * overbounce
	else
		backoff = backoff / overbounce
	end

	velocity.x = velocity.x - normal.x * backoff
	velocity.y = velocity.y - normal.y * backoff
	velocity.z = velocity.z - normal.z * backoff
end

local function AccelerateInPlace(velocity, wishdir, wishspeed, accel, dt, surf)
	--local currentspeed = v:Dot(wishdir)
	local currentspeed = velocity:Length()
	local addspeed     = wishspeed - currentspeed
	if addspeed <= 0 then return end

	local accelspeed = accel * dt * wishspeed * surf
	if accelspeed > addspeed then accelspeed = addspeed end

	velocity.x = velocity.x + accelspeed * wishdir.x
	velocity.y = velocity.y + accelspeed * wishdir.y
	velocity.z = velocity.z + accelspeed * wishdir.z
end

---@param v Vector3
---@param wishdir Vector3
---@param wishspeed number
---@param accel number
---@param dt number
---@param surf number
---@param pTarget Entity
local function AirAccelerateInPlace(v, wishdir, wishspeed, accel, dt, surf, pTarget)
	if wishspeed > GetAirSpeedCap(pTarget) then wishspeed = GetAirSpeedCap(pTarget) end

	--local currentspeed = v:Dot(wishdir)
	local currentspeed = v:Length()
	local addspeed     = wishspeed - currentspeed
	if addspeed <= 0 then return end

	local accelspeed = accel * wishspeed * dt * surf
	if accelspeed > addspeed then accelspeed = addspeed end

	v.x = v.x + accelspeed * wishdir.x
	v.y = v.y + accelspeed * wishdir.y
	v.z = v.z + accelspeed * wishdir.z
end

---@param vec Vector3
local function NormalizeVectorNoAllocate(vec)
	local length = vec:Length()
	if length == 0 then
		return
	end

	vec.x = vec.x / length
	vec.y = vec.y / length
	vec.z = vec.z / length
end

---@param velocity Vector3
---@param original_velocity Vector3
---@return Vector3, boolean
local function RedirectGroundVelocity(velocity, original_velocity)
	if #impact_planes >= MAX_IMPACT_PLANES then
		return Vector3(0, 0, 0), false
	end

	local redirected = Vector3(velocity.x, velocity.y, velocity.z)

	for i = 1, #impact_planes do
		local normal = impact_planes[i]
		if normal.z < 0 then
			normal = NormalizeVector(Vector3(normal.x, normal.y, 0))
		end

		ClipVelocity(redirected, normal, 1.0)

		-- Check if redirected velocity is valid against all planes
		local valid = true
		for j = 1, #impact_planes do
			if j ~= i and redirected:Dot(impact_planes[j]) < 0 then
				valid = false
				break
			end
		end

		if valid then
			return redirected, redirected:Dot(original_velocity) > 0
		end
	end

	-- If we reach here, velocity is invalid — maybe crease movement
	if #impact_planes == 2 then
		local crease = impact_planes[1]:Cross(impact_planes[2])
		NormalizeVectorNoAllocate(crease)
		local scalar = crease:Dot(velocity)
		return crease * scalar, scalar > 0
	end

	return Vector3(0, 0, 0), false
end

---@param velocity Vector3
---@param surface_friction number
---@return Vector3
local function RedirectAirVelocity(velocity, surface_friction)
	if #impact_planes >= MAX_IMPACT_PLANES then
		return Vector3(0, 0, 0)
	end

	local redirected = Vector3(velocity.x, velocity.y, velocity.z)

	for _, normal in ipairs(impact_planes) do
		if normal.z < 0 then
			normal = NormalizeVector(Vector3(normal.x, normal.y, 0))
		end

		local overbounce = (normal.z > 0.7) and 1.0 or (1.0 + (1.0 - surface_friction))
		ClipVelocity(redirected, normal, overbounce)
	end

	return redirected
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

	local trace = DoTraceHull(bbox_bottom, trace_end, zero_vector, zero_vector, MASK_PLAYERSOLID, shouldHit)

	if trace and trace.fraction < 1 then
		-- Check walkability
		local ground_angle = math_deg(math_acos(trace.plane:Dot(up_vector)))

		if ground_angle <= WALKABLE_ANGLE then
			-- Verify we can fit above the surface
			local hit_point = bbox_bottom + (trace_end - bbox_bottom) * trace.fraction
			local step_test_start = hit_point + Vector3(0, 0, step_height)
			local step_trace = DoTraceHull(step_test_start, position, mins, maxs, MASK_PLAYERSOLID, shouldHit)

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
	return IsOnGround(origin, mins, maxs, pEntity, pEntity:GetPropFloat("m_flStepSize") or 18)
end

---@param pEntity Entity
local function AddPositionSample(pEntity)
	local index = pEntity:GetIndex()

	if not position_samples[index] then
		position_samples[index] = {}
	end

	local current_time = globals.CurTime()
	local current_pos = GetEntityOrigin(pEntity)

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

---@param pLocal Entity
---@param entitylist table<integer, ENTRY>
function sim.RunBackground(pLocal, entitylist)
	local enemy_team = pLocal:GetTeamNumber() == 2 and 3 or 2

	for i, playerInfo in pairs(entitylist) do
		local player = entities.GetByIndex(i)
		if player and playerInfo.m_iTeam == enemy_team and player:IsAlive() and not player:IsDormant() then
			AddPositionSample(player)
		end
	end
end

---@param origin Vector3
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
	local primal_velocity = Vector3(velocity.x, velocity.y, velocity.z)
	local original_velocity = Vector3(velocity.x, velocity.y, velocity.z)
	local time_left = frametime
	local allFraction = 0
	local current_origin = Vector3(origin.x, origin.y, origin.z)

	impact_planes = {}

	for bumpcount = 0, numbumps - 1 do
		if velocity:Length() == 0.0 then
			break
		end

		local end_pos = current_origin + velocity * time_left
		local trace = DoTraceHull(current_origin, end_pos, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)
		allFraction = allFraction + trace.fraction

		if trace.allsolid then
			return current_origin, Vector3(0, 0, 0), 4
		end

		if trace.fraction > 0 then
			if numbumps > 0 and trace.fraction == 1 then
				local stuck_trace = DoTraceHull(trace.endpos, trace.endpos, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)
				if stuck_trace.startsolid or stuck_trace.fraction ~= 1.0 then
					return current_origin, Vector3(0, 0, 0), 4
				end
			end

			current_origin = trace.endpos
			original_velocity = Vector3(velocity.x, velocity.y, velocity.z)
			numplanes = 0
		end

		if trace.fraction == 1 then
			break
		end

		if trace.plane.z > 0.7 then
			blocked = blocked | 1
		end
		if trace.plane.z == 0 then
			blocked = blocked | 2
		end

		time_left = time_left - time_left * trace.fraction

		if numplanes >= MAX_CLIP_PLANES then
			return current_origin, Vector3(0, 0, 0), blocked
		end

		local normal = Vector3(trace.plane.x, trace.plane.y, trace.plane.z)
		numplanes = numplanes + 1
		impact_planes[#impact_planes + 1] = normal

		if numplanes == 1 and trace.plane.z <= 0.7 then
			local bounce_factor = 1.0 + (1.0 - surface_friction) * 0.5
			ClipVelocity(original_velocity, impact_planes[1], bounce_factor)
			velocity = Vector3(original_velocity.x, original_velocity.y, original_velocity.z)
		else
			local i = 0
			while i < numplanes do
				ClipVelocity(velocity, impact_planes[i + 1], 1.0)

				local j = 0
				while j < numplanes do
					if j ~= i and velocity:Dot(impact_planes[j + 1]) < 0 then
						break
					end
					j = j + 1
				end

				if j == numplanes then
					break
				end
				i = i + 1
			end

			if i == numplanes then
				-- velocity OK
			else
				if numplanes ~= 2 then
					return current_origin, Vector3(0, 0, 0), blocked
				end

				local dir = NormalizeVector(impact_planes[1]:Cross(impact_planes[2]))
				local d = dir:Dot(velocity)
				velocity = dir * d
			end

			local d = velocity:Dot(primal_velocity)
			if d <= 0 then
				return current_origin, Vector3(0, 0, 0), blocked
			end
		end
	end

	local is_grounded = IsOnGround(current_origin, mins, maxs, pTarget, pTarget:GetPropFloat("m_flStepSize") or 18)
	if is_grounded then
		local redirected, success = RedirectGroundVelocity(velocity, primal_velocity)
		if success then
			velocity = redirected
		end
	else
		velocity = RedirectAirVelocity(velocity, surface_friction)
	end

	if allFraction == 0 then
		velocity = Vector3(0, 0, 0)
	end

	return current_origin, velocity, blocked
end

---@param vecPos Vector3
---@param mins Vector3
---@param maxs Vector3
---@param step_size number
---@param shouldHitEntity function
local function StayOnGround(vecPos, mins, maxs, step_size, shouldHitEntity)
	local up_start = Vector3(vecPos.x, vecPos.y, vecPos.z + 2)
	local down_end = Vector3(vecPos.x, vecPos.y, vecPos.z - step_size)
	local trace = DoTraceHull(
		up_start,
		down_end,
		mins,
		maxs,
		MASK_PLAYERSOLID,
		shouldHitEntity
	)

	local normal = math_acos(math.rad(trace.plane:Dot(up_vector)))

	if trace
		and trace.fraction > 0.0 --- he must go somewhere
		and trace.fraction < 1.0 --- hit something
		and not trace.startsolid --- cant be embedded in a solid
		and normal >= 0.7  --- cant hit on a steep slope that we cant stand on anyway
	then
		local z_delta = math_abs(vecPos.z - trace.endpos.z)
		if z_delta > 0.5 * COORD_RESOLUTION then
			vecPos.x = trace.endpos.x
			vecPos.y = trace.endpos.y
			vecPos.z = trace.endpos.z
		end
	end
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
	--[[local down_dist_sq = (vec_down_pos.x - vec_pos.x) * (vec_down_pos.x - vec_pos.x)
		+ (vec_down_pos.y - vec_pos.y) * (vec_down_pos.y - vec_pos.y)
	local up_dist_sq = (vec_up_pos.x - vec_pos.x) * (vec_up_pos.x - vec_pos.x)
		+ (vec_up_pos.y - vec_pos.y) * (vec_up_pos.y - vec_pos.y)]]

	--- i never understand why they square shit when we can just use it as normal
	local down_dist = (vec_down_pos.x - vec_pos.x) + (vec_down_pos.y - vec_pos.y)
	local up_dist = (vec_up_pos.x - vec_pos.x) + (vec_up_pos.y - vec_pos.y)

	local final_origin, final_velocity, final_blocked

	if down_dist > up_dist then
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

---@param velocity Vector3
---@param pTarget Entity
local function ApplyFriction(velocity, pTarget, is_on_ground)
	-- Skip if water jump time is active (not implemented, so skip check)
	local speed = velocity:Length()
	if speed < 0.1 then
		return
	end

	local drop = 0

	if is_on_ground then
		local _, sv_friction = client.GetConVar("sv_friction")
		local surfaceFriction = pTarget:GetPropFloat("m_flFriction") or SURFACE_FRICTION
		local friction = sv_friction * surfaceFriction

		local _, sv_stopspeed = client.GetConVar("sv_stopspeed")
		local control = (speed < sv_stopspeed) and sv_stopspeed or speed

		drop = drop + control * friction * globals.TickInterval()
	end

	local newspeed = speed - drop
	if newspeed < 0 then
		newspeed = 0
	end

	if newspeed ~= speed and speed > 0 then
		local scale = newspeed / speed
		velocity.x = velocity.x * scale
		velocity.y = velocity.y * scale
		velocity.z = velocity.z * scale
	end
end

---@param pInfo ENTRY
---@param pTarget Entity
---@param initial_pos Vector3
---@param time number
---@return Vector3[]
function sim.Run(pInfo, pTarget, initial_pos, time)
	local last_pos = initial_pos
	local tick_interval = globals.TickInterval()
	local local_player_index = client.GetLocalPlayerIndex()

	local surface_friction = pInfo.m_flFriction or 1.0
	local angular_velocity = pInfo.m_flAngularVelocity * tick_interval
	local maxspeed = pInfo.m_flMaxspeed or 450
	local step_size = pInfo.m_flStepSize or 18
	local mins = pInfo.m_vecMins
	local maxs = pInfo.m_vecMaxs
	local gravity_step = pInfo.m_flGravityStep * tick_interval

	local velocity = pInfo.m_vecVelocity

	local positions = {}

	down_vector.z = -step_size

	-- pre calculate rotation values if angular velocity exists
	local cos_yaw, sin_yaw
	if angular_velocity ~= 0 then
		local yaw = math_rad(angular_velocity)
		cos_yaw, sin_yaw = math_cos(yaw), math_sin(yaw)
	end

	local function shouldHitEntity(ent)
		local ent_index = ent:GetIndex()
		return ent_index ~= local_player_index and ent:GetTeamNumber() ~= pInfo.m_iTeam
	end

	local was_onground = false

	for i = 1, time do
		if angular_velocity ~= 0 then
			local vx, vy = velocity.x, velocity.y
			velocity.x = vx * cos_yaw - vy * sin_yaw
			velocity.y = vx * sin_yaw + vy * cos_yaw
		end

		local next_pos = last_pos + velocity * tick_interval
		local ground_trace = TraceLine(next_pos, next_pos + down_vector, MASK_PLAYERSOLID, shouldHitEntity)
		local is_on_ground = ground_trace and ground_trace.fraction < 1.0 and velocity.z <= MIN_VELOCITY_Z

		--- wtf is this?
		local horizontal_vel = velocity
		local horizontal_speed = horizontal_vel:Length2D()

		ApplyFriction(velocity, pTarget, is_on_ground)

		if horizontal_speed > 0.1 then
			local inv_len = 1.0 / horizontal_speed
			local wishdir = horizontal_vel * inv_len
			wishdir.z = 0
			local wishspeed = math_min(horizontal_speed, maxspeed)

			if is_on_ground then
				-- apply ground acceleration
				AccelerateInPlace(velocity, wishdir, wishspeed, GROUND_ACCELERATE, tick_interval, surface_friction)
			else
				-- apply air acceleration when not on ground and falling
				if velocity.z < 0 then
					AirAccelerateInPlace(velocity, wishdir, wishspeed, AIR_ACCELERATE, tick_interval, surface_friction, pTarget)
				end
			end
		end

		if is_on_ground then
			local vel_length = velocity:Length()
			if vel_length > maxspeed then
				local scale = maxspeed / vel_length
				velocity.x = velocity.x * scale
				velocity.y = velocity.y * scale
				velocity.z = velocity.z * scale
			end
		end

		local new_pos, new_velocity = StepMove(
			last_pos,
			velocity,
			tick_interval,
			mins,
			maxs,
			shouldHitEntity,
			pTarget,
			surface_friction,
			step_size
		)

		-- try to keep player on ground after move
		--[[if settings.sim.stay_on_ground then
			StayOnGround(new_pos, mins, maxs, step_size, shouldHitEntity)
		end]]

		last_pos = new_pos
		velocity = new_velocity
		positions[#positions + 1] = last_pos

		-- ---  F. gravity
		was_onground = is_on_ground

		if not was_onground then
			velocity.z = velocity.z - gravity_step
		elseif velocity.z < 0 then
			velocity.z = 0
		end
	end

	return positions
end

sim.GetSmoothedAngularVelocity = GetSmoothedAngularVelocity
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
		if boneMatrix ~= nil then
			local bonePos = Vector3(boneMatrix[1][4], boneMatrix[2][4], boneMatrix[3][4])
			bones[i] = bonePos
		end
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

local M_RADPI = 180 / math.pi --- rad to deg

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

	local fov = M_RADPI * math.acos(vDst:Dot(vSrc) / vDst:LengthSqr())
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
---@return EulerAngles?, number? -- Euler angles (pitch, yaw, 0)
function Math.SolveBallisticArc(p0, p1, speed, gravity)
	local diff = p1 - p0
	local dx = diff:Length2D()
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
	local yaw = (math.atan(diff.y, diff.x)) * M_RADPI

	-- Convert pitch from angle
	local pitch = -angle * M_RADPI -- negative because upward is negative pitch in most engines

	--- seconds
	local time = dx / (math.cos(pitch) * speed)

	return EulerAngles(pitch, yaw, 0), time
end

-- Returns both low and high arc EulerAngles when gravity > 0
---@param p0 Vector3
---@param p1 Vector3
---@param speed number
---@param gravity number
---@return EulerAngles|nil lowArc, EulerAngles|nil highArc
function Math.SolveBallisticArcBoth(p0, p1, speed, gravity)
	local diff = p1 - p0
	local dx = math.sqrt(diff.x * diff.x + diff.y * diff.y)
	if dx == 0 then
		return nil, nil
	end

	local dy = diff.z
	local g = gravity
	local speed2 = speed * speed

	local root = speed2 * speed2 - g * (g * dx * dx + 2 * dy * speed2)
	if root < 0 then
		return nil, nil
	end

	local sqrt_root = math.sqrt(root)
	local theta_low = math.atan((speed2 - sqrt_root) / (g * dx))
	local theta_high = math.atan((speed2 + sqrt_root) / (g * dx))

	local yaw = math.atan(diff.y, diff.x) * M_RADPI

	local pitch_low = -theta_low * M_RADPI
	local pitch_high = -theta_high * M_RADPI

	local low = EulerAngles(pitch_low, yaw, 0)
	local high = EulerAngles(pitch_high, yaw, 0)
	return low, high
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
	local pitch = math.asin(-direction.z) * M_RADPI
	local yaw = math.atan(direction.y, direction.x) * M_RADPI
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
	if lastFire ~= lastfiretime or weapon ~= old_weapon then
		lastFire = lastfiretime
		nextAttack = GetNextPrimaryAttack(weapon)
	end

	old_weapon = weapon
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