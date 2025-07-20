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

end)
__bundle_register("src.multipoint", function(require, _LOADED, __bundle_register, __bundle_modules)
---@class Multipoint
---@field private pLocal Entity
---@field private pTarget Entity
---@field private bIsHuntsman boolean
---@field private bIsSplash boolean
---@field private vecAimDir Vector3
---@field private vecPredictedPos Vector3
---@field private players table<integer, Entity>
---@field private bAimTeamMate boolean
---@field private vecHeadPos Vector3
---@field private weapon_info WeaponInfo
---@field private math_utils MathLib
---@field private iMaxDistance integer
local multipoint = {}

local offset_multipliers = {
	splash = {
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
	normal = {
		{ 0, 0, 0.5 }, -- chest
		{ 0.6, 0, 0.5 }, -- right shoulder
		{ -0.6, 0, 0.5 }, -- left shoulder
		{ 0, 0, 0.9 }, -- near head
		{ 0, 0, 0.2 }, -- legs
	},
}

---@return Vector3?
function multipoint:GetBestHitPoint()
	local points = {}
	local origin = self.pTarget:GetAbsOrigin()
	local maxs = self.pTarget:GetMaxs()

	local multipliers = self.bIsHuntsman and offset_multipliers.huntsman
		or self.bIsSplash and offset_multipliers.splash
		or offset_multipliers.normal

	for _, mult in ipairs(multipliers) do
		local offset = Vector3(maxs.x * mult[1], maxs.y * mult[2], maxs.z * mult[3])
		table.insert(points, origin + offset)
	end

	local vecMins, vecMaxs = -self.weapon_info.vecCollisionMax, self.weapon_info.vecCollisionMax
	local bestPoint = nil
	local bestFraction = 0

	local function shouldHit(ent)
		if ent:GetIndex() == client.GetLocalPlayerIndex() then
			return false
		end

		if ent:GetIndex() == self.pTarget:GetIndex() then
			return false
		end

		if ent:IsPlayer() == false then
			return true
		end

		return true
	end

	for _, mult in ipairs(multipliers) do
		local forward = self.math_utils.NormalizeVector(self.vecAimDir)
		local right = self.math_utils.NormalizeVector(forward:Cross(Vector3(0, 0, 1)))
		local up = self.math_utils.NormalizeVector(right:Cross(forward))

		local test_pos = self.vecPredictedPos
			+ right * (maxs.x * mult[1])
			+ forward * (maxs.y * mult[2])
			+ up * (maxs.z * mult[3])
		local trace = engine.TraceHull(self.vecHeadPos, test_pos, vecMins, vecMaxs, MASK_SHOT_HULL, shouldHit)
		if trace and trace.fraction > bestFraction then
			bestPoint = test_pos
			bestFraction = trace.fraction
			if bestFraction >= 0.95 then
				break
			end
		end
	end

	return bestPoint
end

function multipoint:Set(
	pLocal,
	pTarget,
	bIsHuntsman,
	vecAimDir,
	players,
	bAimTeamMate,
	vecHeadPos,
	vecPredictedPos,
	weapon_info,
	math_utils,
	iMaxDistance,
	bIsSplash
)
	self.pLocal = pLocal
	self.pTarget = pTarget
	self.bIsHuntsman = bIsHuntsman
	self.vecAimDir = vecAimDir
	self.players = players
	self.bAimTeamMate = bAimTeamMate
	self.vecHeadPos = vecHeadPos
	self.weapon_info = weapon_info
	self.math_utils = math_utils
	self.iMaxDistance = iMaxDistance
	self.vecPredictedPos = vecPredictedPos
	self.bIsSplash = bIsSplash
end

return multipoint

end)
__bundle_register("src.prediction", function(require, _LOADED, __bundle_register, __bundle_modules)
---@class Prediction
---@field pLocal Entity
---@field pWeapon Entity
---@field pTarget Entity
---@field weapon_info WeaponInfo
---@field proj_sim ProjectileSimulation
---@field player_sim table
---@field vecShootPos Vector3
---@field iMaxDistance integer
---@field math_utils MathLib
---@field nMaxTime number
---@field nLatency number
---@field multipoint Multipoint
---@field private __index table
local pred = {}
pred.__index = pred

function pred:Set(
	pLocal,
	pWeapon,
	pTarget,
	weapon_info,
	proj_sim,
	player_sim,
	math_utils,
	multipoint,
	vecShootPos,
	nLatency,
	nMaxTime
)
	self.pLocal = pLocal
	self.pWeapon = pWeapon
	self.weapon_info = weapon_info
	self.proj_sim = proj_sim
	self.player_sim = player_sim
	self.vecShootPos = vecShootPos
	self.pTarget = pTarget
	self.iMaxDistance = 2048
	self.nMaxTime = nMaxTime
	self.multipoint = multipoint
	self.nLatency = nLatency
	self.math_utils = math_utils
end

function pred:GetChargeTimeAndSpeed()
	local charge_time = 0.0
	local projectile_speed = self.weapon_info.flForwardVelocity

	if self.pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_COMPOUND_BOW then
		-- check if bow is currently being charged
		local charge_begin_time = self.pWeapon:GetChargeBeginTime()

		-- if charge_begin_time is 0, the bow isn't charging
		if charge_begin_time > 0 then
			charge_time = globals.CurTime() - charge_begin_time
			-- clamp charge time between 0 and 1 second (full charge)
			charge_time = math.max(0, math.min(charge_time, 1.0))

			-- apply charge multiplier to projectile speed
			local charge_multiplier = 1.0 + (charge_time * 0.44) -- 44% speed increase at full charge
			projectile_speed = projectile_speed * charge_multiplier
		else
			-- bow is not charging, use minimum speed
			charge_time = 0.0
		end
	elseif self.pWeapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER then
		local charge_begin_time = self.pWeapon:GetChargeBeginTime()
		if charge_begin_time > 0 then
			charge_time = globals.CurTime() - charge_begin_time
			if charge_time > 4.0 then
				charge_time = 0.0
			end
		end
	end

	return charge_time, projectile_speed
end

---@return PredictionResult?
function pred:Run()
	if not self.pLocal or not self.pWeapon or not self.pTarget then
		return nil
	end

	local vecTargetOrigin = self.pTarget:GetAbsOrigin()
	local dist = (self.vecShootPos - vecTargetOrigin):Length()
	if dist > self.iMaxDistance then
		return nil
	end

	local charge_time, projectile_speed = self:GetChargeTimeAndSpeed()
	local gravity = self.weapon_info.flGravity

	local shoot_dir = self.math_utils.NormalizeVector(vecTargetOrigin - self.vecShootPos)
	local vecMuzzlePos = self.vecShootPos
		+ self.math_utils.RotateOffsetAlongDirection(self.weapon_info.vecOffset, shoot_dir)

	-- Estimate flight time to origin for sim
	local flat_aim_dir = (gravity > 0)
			and self.math_utils.SolveBallisticArc(vecMuzzlePos, vecTargetOrigin, projectile_speed, gravity)
		or shoot_dir
	if not flat_aim_dir then
		return nil
	end

	local travel_time_est = (vecTargetOrigin - vecMuzzlePos):Length() / projectile_speed
	local total_time = travel_time_est + self.nLatency
	if total_time > self.nMaxTime then
		return nil
	end

	local flstepSize = self.pLocal:GetPropFloat("localdata", "m_flStepSize") or 18
	local player_positions = self.player_sim.Run(flstepSize, self.pTarget, total_time)
	if not player_positions or #player_positions == 0 then
		return nil
	end

	local predicted_target_pos = player_positions[#player_positions]
	local aim_dir = (gravity > 0)
			and self.math_utils.SolveBallisticArc(vecMuzzlePos, predicted_target_pos, projectile_speed, gravity)
		or self.math_utils.NormalizeVector(predicted_target_pos - vecMuzzlePos)
	if not aim_dir then
		return nil
	end

	local projectile_path =
		self.proj_sim.Run(self.pLocal, self.pWeapon, vecMuzzlePos, aim_dir, self.nMaxTime, self.weapon_info)
	if not projectile_path or #projectile_path == 0 then
		return nil
	end

	return {
		vecPos = predicted_target_pos,
		nTime = total_time,
		nChargeTime = charge_time,
		vecAimDir = aim_dir,
		vecPlayerPath = player_positions,
		vecProjPath = projectile_path,
	}
end

return pred

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

-- Cache parsed models to avoid repeated parsing
local modelCache = {}

---@param pWeapon Entity
local function GetProjectileModel(pWeapon)
	local weaponID = pWeapon:GetWeaponID()
	return PROJECTILE_MODELS[weaponID] or PROJECTILE_MODELS[E_WeaponBaseID.TF_WEAPON_ROCKETLAUNCHER]
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
---@param weapon_info WeaponInfo
---@return ProjSimRet
function sim.Run(pLocal, pWeapon, shootPos, vecForward, nTime, weapon_info)
	local positions = {}

	local projectile = CreateProjectile(pWeapon)
	local mins, maxs = -weapon_info.vecCollisionMax, weapon_info.vecCollisionMax
	local speed = weapon_info.flForwardVelocity
	local velocity = vecForward * speed

	local gravity = weapon_info.flGravity
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

local MAX_ALLOWED_SPEED = 2000 -- HU/sec
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

---@param pEntity Entity
---@return number
local function GetSmoothedAngularVelocity(pEntity)
	local samples = position_samples[pEntity:GetIndex()]
	if not samples or #samples < 3 then
		return 0
	end

	local MIN_SPEED = 25 -- HU/s
	local ang_vels = {}

	for i = 1, #samples - 2 do
		local s1 = samples[i]
		local s2 = samples[i + 1]
		local s3 = samples[i + 2]

		local dt1 = s2.time - s1.time
		local dt2 = s3.time - s2.time
		if dt1 <= 0 or dt2 <= 0 then
			goto continue
		end

		-- calculate velocities between sample points
		local vel1 = (s2.pos - s1.pos) / dt1
		local vel2 = (s3.pos - s2.pos) / dt2

		-- skip if velocity is too low
		if vel1:Length() < MIN_SPEED or vel2:Length() < MIN_SPEED then
			goto continue
		end

		-- calculate yaw differences
		local yaw1 = math.atan(vel1.y, vel1.x)
		local yaw2 = math.atan(vel2.y, vel2.x)
		local diff = math.deg((yaw2 - yaw1 + math.pi) % (2 * math.pi) - math.pi)

		-- calculate time-weighted angular velocity (deg/s)
		local avg_time = (dt1 + dt2) / 2
		local angular_velocity = diff / avg_time

		-- filter impossible values (> 720 deg/s)
		if math.abs(angular_velocity) < 720 then
			ang_vels[#ang_vels + 1] = angular_velocity
		end

		::continue::
	end

	if #ang_vels == 0 then
		return 0
	end

	-- median filtering for outlier rejection
	if #ang_vels >= 3 then
		table.sort(ang_vels)
		local mid = math.floor(#ang_vels / 2) + 1
		ang_vels = { ang_vels[mid] }
	end

	-- exponential smoothing
	local grounded = IsPlayerOnGround(pEntity)
	local base_alpha = grounded and 0.4 or 0.2
	local smoothed = ang_vels[1]

	for i = 2, #ang_vels do
		local change = math.abs(ang_vels[i] - smoothed)
		local alpha = base_alpha * math.min(1, change / 180) -- adaptive scaling
		alpha = math.max(0.05, math.min(alpha, 0.4))
		smoothed = smoothed * (1 - alpha) + ang_vels[i] * alpha
	end

	return smoothed
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

---@param stepSize number
---@param pTarget Entity The target
---@param time number The time in seconds we want to predict
function sim.Run(stepSize, pTarget, time)
	local smoothed_velocity = GetSmoothedVelocity(pTarget)
	local last_pos = pTarget:GetAbsOrigin()
	local tick_interval = globals.TickInterval()
	local angular_velocity = GetSmoothedAngularVelocity(pTarget) * tick_interval
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

		-- clamp velocity to target's max speed
		local target_max_speed = pTarget:GetPropFloat("m_flMaxspeed") or 450
		local vel_length = smoothed_velocity:Length()
		if vel_length > target_max_speed then
			smoothed_velocity = smoothed_velocity * (target_max_speed / vel_length)
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