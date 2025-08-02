--[[
	NAVET'S PROEJECTILE AIMBOT
	made by navet
	Update: v8
	Source: https://github.com/uosq/lbox-projectile-aimbot
	
	This project would take way longer to start making
	if it weren't for them:
	Terminator - https://github.com/titaniummachine1
	GoodEvening - https://github.com/GoodEveningFellOff
--]]

---@diagnostic disable: cast-local-type

printc(186, 97, 255, 255, "The projectile aimbot is loading...")

local version = "8"

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
	max_distance = 1024,
	multipointing = true,
	allow_aim_at_teammates = true,
	ping_compensation = true,
	min_priority = 0,
	splash = true,
	aim_circle = true,

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

local multipoint_target_pos = nil

local original_gui_value = gui.GetValue("projectile aimbot")

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
---@return PlayerInfo?
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

	if best_target.index == nil then
		return nil
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
---@param pWeapon Entity
---@param pLocal Entity
---@param angle EulerAngles
---@param player_path table<integer, Vector3>
---@param vecHeadPos Vector3
---@param total_time number
---@param weaponInfo WeaponInfo
---@param charge number
local function HandleWeaponFiring(uCmd, pLocal, pWeapon, angle, player_path, vecHeadPos, weaponInfo, total_time, charge)
	if pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW then
		if charge > 0 then
			if settings.autoshoot and wep_utils.CanShoot() then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end
			if (uCmd.buttons & IN_ATTACK) ~= 0 then
				uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
				if settings.psilent then
					uCmd.sendpacket = false
				end
				uCmd.viewangles = Vector3(angle:Unpack())
				displayed_time = globals.CurTime() + settings.draw_time
				paths.player_path = player_path
				paths.proj_path = proj_sim.Run(pLocal, pWeapon, vecHeadPos, angle:Forward(), total_time, weaponInfo)
			end
		else
			if settings.autoshoot and wep_utils.CanShoot() then
				uCmd.buttons = uCmd.buttons | IN_ATTACK -- hold to charge
			end
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
			uCmd.viewangles = Vector3(angle:Unpack())
			displayed_time = globals.CurTime() + settings.draw_time
			paths.player_path = player_path
			paths.proj_path = proj_sim.Run(pLocal, pWeapon, vecHeadPos, angle:Forward(), total_time, weaponInfo)
		end
	elseif pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER then
		if settings.autoshoot and wep_utils.CanShoot() then
			uCmd.buttons = uCmd.buttons | IN_ATTACK
		end

		if charge > 0 then
			uCmd.buttons = uCmd.buttons & ~IN_ATTACK -- release to fire
			if settings.psilent then
				uCmd.sendpacket = false
			end
			uCmd.viewangles = Vector3(angle:Unpack())
			displayed_time = globals.CurTime() + settings.draw_time
			paths.player_path = player_path
			paths.proj_path = proj_sim.Run(pLocal, pWeapon, vecHeadPos, angle:Forward(), total_time, weaponInfo)
		end
	elseif pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_LUNCHBOX then
		uCmd.buttons = uCmd.buttons | IN_ATTACK2
		uCmd.viewangles = Vector3(angle:Unpack())
		displayed_time = globals.CurTime() + settings.draw_time
		paths.player_path = player_path
		paths.proj_path = proj_sim.Run(pLocal, pWeapon, vecHeadPos, angle:Forward(), total_time, weaponInfo)
	elseif pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_BAT_WOOD then
		uCmd.buttons = uCmd.buttons | IN_ATTACK2
		uCmd.viewangles = Vector3(angle:Unpack())
		displayed_time = globals.CurTime() + settings.draw_time
		paths.player_path = player_path
		paths.proj_path = proj_sim.Run(pLocal, pWeapon, vecHeadPos, angle:Forward(), total_time, weaponInfo)
	else
		if wep_utils.CanShoot() then
			if settings.autoshoot and (uCmd.buttons & IN_ATTACK) == 0 then
				uCmd.buttons = uCmd.buttons | IN_ATTACK
			end

			if (uCmd.buttons & IN_ATTACK) ~= 0 then
				if settings.psilent then
					uCmd.sendpacket = false
				end
				uCmd.viewangles = Vector3(angle:Unpack())
				displayed_time = globals.CurTime() + settings.draw_time
				paths.player_path = player_path
				paths.proj_path = proj_sim.Run(pLocal, pWeapon, vecHeadPos, angle:Forward(), total_time, weaponInfo)
			end
		end
	end
end

---@param uCmd UserCmd
local function CreateMove(uCmd)
	multipoint_target_pos = nil

	if settings.enabled == false then
		return
	end

	if (engine.IsChatOpen() or engine.Con_IsVisible() or engine.IsGameUIVisible()) == true then
		return false
	end

	if input.IsButtonDown(gui.GetValue("aim key")) == false then
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

	if pWeapon:IsMeleeWeapon() and pWeapon:GetWeaponID() ~= E_WeaponBaseID.TF_WEAPON_BAT_WOOD then
		return false
	end

	local iWeaponID = pWeapon:GetWeaponID()
	local bAimAtTeamMates = false

	if iWeaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX then
		bAimAtTeamMates = true
	elseif iWeaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW then
		bAimAtTeamMates = true
	end

	bAimAtTeamMates = settings.allow_aim_at_teammates and bAimAtTeamMates or false

	local players = entities.FindByClass("CTFPlayer")
	local vecHeadPos = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
	local pTargetInfo = GetClosestEntityToFov(pLocal, vecHeadPos, players, bAimAtTeamMates)
	if pTargetInfo == nil then
		return
	end

	local pTarget = entities.GetByIndex(pTargetInfo.index)
	if pTarget == nil then
		return
	end

	local weaponInfo = GetProjectileInformation(pWeapon:GetPropInt("m_iItemDefinitionIndex"))
	if weaponInfo == nil then
		return
	end

	local vecTargetOrigin = pTarget:GetAbsOrigin()
	local charge_time = GetCharge(pWeapon)

	local velocity_vector = weaponInfo:GetVelocity(charge_time) -- use real charge
	local forward_speed = math.sqrt(velocity_vector.x ^ 2 + velocity_vector.y ^ 2)

	local det_mult = pWeapon:AttributeHookFloat("sticky_arm_time")
	local detonate_time = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER and 0.7 * det_mult or 0
	local travel_time_est = (vecTargetOrigin - vecHeadPos):Length() / forward_speed
	local total_time = travel_time_est + detonate_time

	if total_time > settings.max_sim_time then
		return
	end

	local choked_time = clientstate:GetChokedCommands()
	local time_ticks = (((total_time * 66.67) + 0.5) // 1) + choked_time

	local player_path = player_sim.Run(pTarget, vecTargetOrigin, time_ticks)
	if player_path == nil then
		return
	end

	if settings.draw_only then
		local vecPredictedPos = player_path[#player_path]
		local gravity = client.GetConVar("sv_gravity") * 0.5 * weaponInfo:GetGravity(charge_time)
		local angle = math_utils.SolveBallisticArc(vecHeadPos, vecPredictedPos, forward_speed, gravity)
		if angle == nil then
			return
		end

		local vecWeaponFirePos = weaponInfo:GetFirePosition(pLocal, vecHeadPos, angle, pWeapon:IsViewModelFlipped())
		paths.player_path = player_path
		paths.proj_path = proj_sim.Run(pLocal, pWeapon, vecWeaponFirePos, angle:Forward(), total_time, weaponInfo)
		displayed_time = globals.CurTime() + settings.draw_time
		return
	end

	-- Make traces ignore *us* and also the target's **current** position,
	-- because we're aiming at where he *will* be, not where he is now.
	local function shouldHit(ent)
		if not ent then -- world / sky / nil
			return true -- trace should go on
		end
		if ent == pLocal or ent == pTarget then
			return false -- pretend they don't exist
		end
		return ent:GetTeamNumber() ~= pTarget:GetTeamNumber()
	end

	local vecPredictedPos = player_path[#player_path]
	local vecMins, vecMaxs = weaponInfo.m_vecMins, weaponInfo.m_vecMaxs
	local trace = engine.TraceHull(vecHeadPos, vecPredictedPos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
	local is_visible = trace and (trace.fraction >= 0.9 or trace.entity == pTarget)

	local bIsHuntsman = pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW

	if settings.multipointing then
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
			vecPredictedPos,
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

		vecPredictedPos = best_multipoint
		multipoint_target_pos = best_multipoint
	end

	-- Two-pass aiming system for precise targeting
	local function TryAimAtPoint(target_pos)
		-- First pass: Aim at the target point
		local gravity = client.GetConVar("sv_gravity") * 0.5 * weaponInfo:GetGravity(charge_time)
		local first_angle = math_utils.SolveBallisticArc(vecHeadPos, target_pos, forward_speed, gravity)
		if not first_angle then
			return nil, nil
		end

		-- Get our weapon fire position for this angle
		local first_fire_pos = weaponInfo:GetFirePosition(pLocal, vecHeadPos, first_angle, pWeapon:IsViewModelFlipped())

		-- Check if we can hit the target from our fire position
		local first_trace = engine.TraceHull(first_fire_pos, target_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
		if not first_trace or (first_trace.fraction < 0.9 and first_trace.entity ~= pTarget) then
			return nil, nil
		end

		-- Second pass: Make target "aim back" at our fire position
		-- Calculate direction from target to our fire position
		local target_to_fire_dir = math_utils.NormalizeVector(first_fire_pos - target_pos)

		-- Get the target's "shoot position" (where they would shoot from if aiming at our fire pos)
		local target_shoot_pos = target_pos + target_to_fire_dir * 50 -- Approximate weapon offset

		-- Now solve aiming at the target's shoot position
		local final_angle = math_utils.SolveBallisticArc(vecHeadPos, target_shoot_pos, forward_speed, gravity)
		if not final_angle then
			return nil, nil
		end

		-- Get our final fire position
		local final_fire_pos = weaponInfo:GetFirePosition(pLocal, vecHeadPos, final_angle, pWeapon:IsViewModelFlipped())

		-- Final trace check
		local final_trace = engine.TraceHull(final_fire_pos, target_shoot_pos, vecMins, vecMaxs, MASK_SHOT_HULL,
			shouldHit)
		if not final_trace or (final_trace.fraction < 0.9 and final_trace.entity ~= pTarget) then
			return nil, nil
		end

		return final_angle, final_fire_pos
	end

	-- Try aiming at the predicted position
	local final_angle, final_fire_pos = TryAimAtPoint(vecPredictedPos)

	-- If multipoint is enabled and first attempt failed, try multipoint positions
	if not final_angle and settings.multipointing then
		-- Get all available multipoint positions
		local multipoint_positions = {}

		-- Add primary positions based on weapon type
		if bIsHuntsman and settings.hitparts.head then
			local head_pos = vecPredictedPos + Vector3(0, 0, 82)
			table.insert(multipoint_positions, head_pos)
		end

		if bSplashWeapon and settings.hitparts.feet and pTarget:IsOnGround() then
			local feet_pos = vecPredictedPos + Vector3(0, 0, 10)
			table.insert(multipoint_positions, feet_pos)
		end

		-- Add center position
		table.insert(multipoint_positions, vecPredictedPos)

		-- Add fallback multipoint positions
		local fallback_points = {
			{ pos = Vector3(0, 0, 41) }, -- Center height
			{ pos = Vector3(0, 0, 20) }, -- Lower center
			{ pos = Vector3(0, 0, 60) }, -- Upper center
		}

		for _, point in ipairs(fallback_points) do
			local test_pos = vecPredictedPos + point.pos
			table.insert(multipoint_positions, test_pos)
		end

		-- Try each position until one works
		for _, pos in ipairs(multipoint_positions) do
			final_angle, final_fire_pos = TryAimAtPoint(pos)
			if final_angle then
				multipoint_target_pos = pos
				break
			end
		end
	end

	if not final_angle then
		return
	end

	HandleWeaponFiring(uCmd, pLocal, pWeapon, final_angle, player_path, final_fire_pos, weaponInfo, total_time,
		charge_time)
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

local function DrawMultipointTarget()
	if not multipoint_target_pos then
		return
	end

	local screen_pos = client.WorldToScreen(multipoint_target_pos)
	if not screen_pos then
		return
	end

	-- Draw a small square at the multipoint target position
	local square_size = 8
	local half_size = square_size / 2

	-- Draw filled square
	draw.Color(255, 0, 0, 200) -- Red with alpha
	draw.FilledRect(screen_pos[1] - half_size, screen_pos[2] - half_size,
		screen_pos[1] + half_size, screen_pos[2] + half_size)

	-- Draw outline
	draw.Color(255, 255, 255, 255) -- White outline
	draw.OutlinedRect(screen_pos[1] - half_size, screen_pos[2] - half_size,
		screen_pos[1] + half_size, screen_pos[2] + half_size)
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
		draw.Color(136, 192, 208, 255)
		DrawPlayerPath()
	end

	if settings.draw_bounding_box then
		local pos = paths.player_path[#paths.player_path]
		if pos then
			draw.Color(136, 192, 208, 255)
			DrawPlayerHitbox(pos, target_min_hull, target_max_hull)
		end
	end

	if settings.draw_proj_path and paths.proj_path and #paths.proj_path > 0 then
		draw.Color(235, 203, 139, 255)
		DrawProjPath()
	end

	-- Draw multipoint target indicator
	DrawMultipointTarget()
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
