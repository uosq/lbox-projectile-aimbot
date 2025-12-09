local multipoint = require "multipoint"
--- made by navet

local MAX_DISTANCE = 3000
local MIN_ACCURACY = 2
local MAX_ACCURACY = 12
local MIN_CONFIDENCE = 40 --- 40%

--local SimulatePlayer = require("playersim")
local GetProjectileInfo = require("projectile_info")
local SimulatePlayer = require("playersim")
local SimulateProj = require("projectilesim")

local utils = {}
utils.math = require("utils.math")
utils.weapon = require("utils.weapon_utils")

---@class State
---@field target Entity?
---@field angle EulerAngles?
---@field path Vector3[]?
---@field storedpath {path: Vector3[]?, projpath: Vector3[]?, projtimetable: number[]?, timetable: number[]?}
---@field charge number
---@field charges boolean
---@field silent boolean
---@field secondaryfire boolean
----@field accuracy number?
local state = {
	target = nil,
	angle = nil,
	path = nil,
	storedpath = {path = nil, projpath = nil, projtimetable = nil, timetable = nil},
	charge = 0,
	charges = false,
	silent = true,
	secondaryfire = false
}

local noSilentTbl = {
	[E_WeaponBaseID.TF_WEAPON_CLEAVER] = true,
	[E_WeaponBaseID.TF_WEAPON_BAT_WOOD] = true,
	[E_WeaponBaseID.TF_WEAPON_BAT_GIFTWRAP] = true,
	[E_WeaponBaseID.TF_WEAPON_LUNCHBOX] = true,
	[E_WeaponBaseID.TF_WEAPON_JAR] = true,
	[E_WeaponBaseID.TF_WEAPON_JAR_MILK] = true,
	[E_WeaponBaseID.TF_WEAPON_JAR_GAS] = true,
	[E_WeaponBaseID.TF_WEAPON_FLAME_BALL] = true,
}

local doSecondaryFiretbl = {
	[E_WeaponBaseID.TF_WEAPON_BAT_GIFTWRAP] = true,
	[E_WeaponBaseID.TF_WEAPON_LUNCHBOX] = true,
	[E_WeaponBaseID.TF_WEAPON_BAT_WOOD] = true,
}

---@param localPos Vector3
---@param className string
---@param enemyTeam integer
---@param outTable table
local function ProcessClass(localPos, className, enemyTeam, outTable)
	local isPlayer = false

	for _, entity in pairs (entities.FindByClass(className)) do
		isPlayer = entity:IsPlayer()
		if (isPlayer == true and entity:IsAlive()
		or (isPlayer == false and entity:GetHealth() > 0))
		and not entity:IsDormant()
		and entity:GetTeamNumber() == enemyTeam
		and not entity:InCond(E_TFCOND.TFCond_Cloaked)
		and (localPos - entity:GetAbsOrigin()):Length() <= MAX_DISTANCE then
			--print(string.format("Is alive: %s, Health: %d", entity:IsAlive(), entity:GetHealth()))
			outTable[#outTable+1] = entity
		end
	end
end

---@param tbl Vector3[]
local function DrawPath(tbl)
	if #tbl >= 2 then
		local prev = client.WorldToScreen(tbl[1])
		if prev then
			draw.Color(255, 255, 255, 255)
			for i = 2, #tbl do
				local curr = client.WorldToScreen(tbl[i])
				if curr and prev then
					draw.Line(prev[1], prev[2], curr[1], curr[2])
					prev = curr
				else
					break
				end
			end
		end
	end
end

local function CleanTimeTable(pathtbl, timetbl)
	if not pathtbl or not timetbl or #pathtbl ~= #timetbl or #pathtbl < 2 then
		return nil, nil
	end

	local curtime = globals.CurTime()
	local newpath = {}
	local newtime = {}

	for i = 1, #timetbl do
		if timetbl[i] >= curtime then
			newpath[#newpath+1] = pathtbl[i]
			newtime[#newtime+1] = timetbl[i]
		end
	end

	-- Return nil if we filtered everything out
	if #newpath == 0 then
		return nil, nil
	end

	return newpath, newtime
end

---@param entity Entity The target entity
---@param projpath Vector3[]? The predicted projectile path
---@param hit boolean? Whether projectile simulation hit the target
---@param distance number Distance to target
---@param speed number Projectile speed
---@param gravity number Gravity modifier
---@param time number Prediction time
---@return number score Hitchance score from 0-100%
local function CalculateHitchance(entity, projpath, hit, distance, speed, gravity, time)
    local score = 100.0

    local maxDistance = MAX_DISTANCE
    local distanceFactor = math.min(distance / maxDistance, 1.0)
    score = score - (distanceFactor * 40)

    --- prediction time penalty (longer predictions = less accurate)
    if time > 2.0 then
        score = score - ((time - 2.0) * 15)
    elseif time > 1.0 then
        score = score - ((time - 1.0) * 10)
    end

    --- projectile simulation penalties
    if projpath then
        --- if hit something, penalize the shit out of it
        if not hit then
            score = score - 40
        end

        --- penalty for very long projectile paths (more chance for error)
        if #projpath > 50 then
            score = score - 10
        elseif #projpath > 100 then
            score = score - 20
        end
    else
        --- i dont remember if i ever return nil for projpath
		--- but fuck it we ball
        score = score - 100
    end

    --- gravity penalty (high arc = less accurate (kill me))
    if gravity > 0 then
		--- using 400 or 800 gravity is such a pain
		--- i dont remember anymore why i chose 400 here
		--- but its working fine as far as i know
		--- unless im using 800 graviy
		--- then this is probably giving a shit ton of score
		--- but im so confused and sleep deprived that i dont care
        local gravityFactor = math.min(gravity/400, 1.0)
        score = score - (gravityFactor * 15)
    end

    --- targed speed penalty
	--- more speed = less confiident we are
    local velocity = entity:EstimateAbsVelocity() or Vector3()
    if velocity then
        local speed2d = velocity:Length2D()
        if speed2d > 300 then
            score = score - 15
        elseif speed2d > 200 then
            score = score - 10
        elseif speed2d > 100 then
            score = score - 5
        end
    end

    --- target class bonus/penalty
    if entity:IsPlayer() then
        local class = entity:GetPropInt("m_iClass")
        --- scouts are harder to hit
        if class == E_Character.TF2_Scout then -- Scout
            score = score - 10
        end

        --- classes easier to hit
        if class == E_Character.TF2_Heavy or class == E_Character.TF2_Sniper then -- Heavy or Sniper
            score = score + 5
        end

        --- penalize air targets
		--- i wrote this shit at 3 am, wtf is this?
        if entity:InCond(E_TFCOND.TFCond_BlastJumping) then
            score = score - 15
        end
    else
        --- buildings dont have feet (at least the ones i know)
        score = score + 15
    end

    --- projectile speed penalty (slow projectiles are harder to hit)
    if speed < 1000 then
        score = score - 10
    elseif speed < 1500 then
        score = score - 5
    end

    --- clamp this
    return math.max(0, math.min(100, score))
end

--- vector.Normalize doesn't work
--- so we do it ourselves
--- Normalizes In Place and returns length
---@param vec Vector3
local function Normalize(vec)
	local len = vec:Length()
	if (len < 0.0001) then
		return 0
	end

	vec.x = vec.x / len
	vec.y = vec.y / len
	vec.z = vec.z / len

	return len
end

local font = draw.CreateFont("Arial", 36, 1000)

local function OnDraw()
	--- Reset our state table
	state.angle = nil
	state.path = nil
	state.target = nil
	state.charge = 0
	state.charges = false

	if gui.IsMenuOpen() and not engine.IsTakingScreenshot() then
		draw.SetFont(font)
		draw.Color(255, 150, 150, 255)
		local text = "Navet's Proj Aimbot Loaded"
		local w, h = draw.GetScreenSize()
		local tw, th = draw.GetTextSize(text)
		draw.TextShadow((w*0.5 - tw*0.5)//1, (h*0.1)//1, text)
		tw = draw.GetTextSize(text)
		text = "Go to AIMBOT tab to configure it"
		draw.TextShadow((w*0.5 - tw*0.5)//1, (h*0.15)//1, text)
	end

	local netchannel = clientstate.GetNetChannel()

	if netchannel == nil then
		return
	end

	if clientstate.GetClientSignonState() <= E_SignonState.SIGNONSTATE_SPAWN then
		return
	end

	if state.storedpath.path and state.storedpath.timetable then
		local cleanedpath, cleanedtime = CleanTimeTable(state.storedpath.path, state.storedpath.timetable)
		state.storedpath.path = cleanedpath
		state.storedpath.timetable = cleanedtime
	end

	if state.storedpath.projpath and state.storedpath.projtimetable then
		local cleanedprojpath, cleanedprojtime = CleanTimeTable(state.storedpath.projpath, state.storedpath.projtimetable)
		state.storedpath.projpath = cleanedprojpath
		state.storedpath.projtimetable = cleanedprojtime
	end

	--- TODO: Use a polygon instead!
	local storedpath = state.storedpath.path
	if storedpath then
		DrawPath(storedpath)
	end

	local storedprojpath = state.storedpath.projpath
	if storedprojpath then
		DrawPath(storedprojpath)
	end

	if input.IsButtonDown(gui.GetValue("aim key")) == false then
		return
	end

	if utils.weapon.CanShoot() == false then
		return
	end

	local plocal = entities.GetLocalPlayer()
	if plocal == nil then
		return
	end

	local weapon = plocal:GetPropEntity("m_hActiveWeapon")
	if weapon == nil then
		return
	end

	local info = GetProjectileInfo(weapon:GetPropInt("m_iItemDefinitionIndex"))
	if info == nil then
		return
	end

	local enemyTeam = plocal:GetTeamNumber() == 2 and 3 or 2
	local localPos = plocal:GetAbsOrigin()

	---@type Entity[]
	local entitylist = {}
	ProcessClass(localPos, "CTFPlayer", enemyTeam, entitylist)

	if gui.GetValue("aim sentry") == 1 then
		ProcessClass(localPos, "CObjectSentrygun", enemyTeam, entitylist)
	end

	if gui.GetValue("aim other buildings") then
		ProcessClass(localPos, "CObjectDispenser", enemyTeam, entitylist)
		ProcessClass(localPos, "CObjectTeleporter", enemyTeam, entitylist)
	end

	if #entitylist == 0 then
		return
	end

	local eyePos = localPos + plocal:GetPropVector("localdata", "m_vecViewOffset[0]")
	local viewangle = engine.GetViewAngles()

	local charge = info.m_bCharges and weapon:GetCurrentCharge() or 0.0
	local speed = info:GetVelocity(charge):Length2D()
	local _, sv_gravity = client.GetConVar("sv_gravity")
	local gravity = sv_gravity * 0.5 * info:GetGravity(charge)
	local weaponID = weapon:GetWeaponID()

	local sortedEntities = {}
	local RAD2DEG = 180/math.pi
	for _, entity in ipairs(entitylist) do
		local entityCenter = entity:GetAbsOrigin() + (entity:GetMins() + entity:GetMaxs()) * 0.5
		local dirToEntity = (entityCenter - eyePos)
		Normalize(dirToEntity)
		local forward = viewangle:Forward()
		local angle = math.acos(forward:Dot(dirToEntity)) * RAD2DEG --- i love dot products

		if angle <= gui.GetValue("aim fov") then
			table.insert(sortedEntities, {
				entity = entity,
				fov = angle
			})
		end
	end

	--- sort by fov (lowest to highest)
	table.sort(sortedEntities, function(a, b)
		return a.fov < b.fov
	end)

	if #sortedEntities == 0 then
		return
	end

	for _, entData in ipairs(sortedEntities) do
		local entity = entData.entity
		local distance = (localPos - entity:GetAbsOrigin() + (entity:GetMins() + entity:GetMaxs()) * 0.5):Length()
		local time = (distance/speed) + netchannel:GetLatency(E_Flows.FLOW_INCOMING)
		local lazyness = MIN_ACCURACY + (MAX_ACCURACY - MIN_ACCURACY) * (math.min(distance/MAX_DISTANCE, 1.0)^1.5)

		local path, lastPos, timetable = SimulatePlayer(entity, time, lazyness)
		local drop = gravity * time * time

		--lastPos.z = lastPos.z + drop this works really well for demo, fuck

		local _, multipointPos = multipoint.Run(entity, weapon, info, eyePos, lastPos, drop)
		if multipointPos then
			lastPos = multipointPos
		end

		local angle = utils.math.SolveBallisticArc(eyePos, lastPos, speed, gravity)
		if angle then
			--- check visibility
			local firePos = info:GetFirePosition(plocal, eyePos, angle, weapon:IsViewModelFlipped())
			local translatedAngle = utils.math.SolveBallisticArc(firePos, lastPos, speed, gravity)

			if translatedAngle then
				local projpath, hit, fullSim, projtimetable = SimulateProj(entity, lastPos, firePos, translatedAngle, info, plocal:GetTeamNumber(), time, charge)

				--if hit then
				if fullSim then
					local confidence = CalculateHitchance(entity, projpath, fullSim, distance, speed, gravity, time)
					if confidence >= MIN_CONFIDENCE then
						local secondaryFire = doSecondaryFiretbl[weaponID]
						local noSilent = noSilentTbl[weaponID]

						state.target = entity
						state.path = path
						state.angle = angle
						state.storedpath.path = path
						state.storedpath.projpath = projpath
						state.storedpath.timetable = timetable
						state.storedpath.projtimetable = projtimetable
						state.charge = charge
						state.charges = info.m_bCharges
						state.secondaryfire = secondaryFire
						state.silent = not noSilent
						state.confidence = confidence
						return
					end
				end
			end
		end
	end

	--- no valid target found :sob:
end

---@param cmd UserCmd
local function OnCreateMove(cmd)
	if utils.weapon.CanShoot() == false then
		return
	end

	if input.IsButtonDown(gui.GetValue("aim key")) == false then
		return
	end

	if not state.angle then
		return
	end

	if state.charge > 1.0 then
		state.charge = 0
	end

	if state.charges and state.charge < 0.1 then
		cmd.buttons = cmd.buttons | IN_ATTACK
		return
	end

	if state.charges then
		cmd.buttons = cmd.buttons & ~IN_ATTACK
	else
		if state.secondaryfire then
			cmd.buttons = cmd.buttons | IN_ATTACK2
		else
			cmd.buttons = cmd.buttons | IN_ATTACK
		end
	end

	if state.silent then
		cmd.sendpacket = false
	end

	cmd.viewangles = Vector3(state.angle:Unpack())
end

local function getKey()
	local value = gui.GetValue("aim key")
	local key = "error"
	for name, v in pairs(E_ButtonCode) do
		if v == value then
			key = name
		end
	end
	return key
end

printc(150, 255, 150, 255, "Proj Aimbot - Loaded successfully")
printc(
	255, 255, 0, 255,
	"There is no menu anymore. Use the AIMBOT tab in Lmaobox to configure",
	"FOV: " .. gui.GetValue("aim fov"),
	"Aim Key: " .. getKey()
)

callbacks.Register("Draw", OnDraw)
callbacks.Register("CreateMove", OnCreateMove)