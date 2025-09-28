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
	max_targets = 2,
	draw_scores = true,

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

	weights = {
		health_weight     = 1.0, -- prefer lower player health
		distance_weight   = 1.1, -- prefer closer players
		fov_weight        = 2,
		visibility_weight = 1.2,
		speed_weight      = 0.6,   -- prefer slower targets
		medic_priority    = 1.5,   -- bonus if Medic
		sniper_priority   = 1.0,   -- bonus if Sniper
		uber_penalty      = -2.0,  -- skip/penalize Ubercharged targets
	},

	min_score = 2,
	onfov_only = true,
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

---@type Entity?, Entity?, WeaponInfo?
local plocal, weapon, weaponInfo = nil, nil, nil

---@class EntityInfo
---@field index integer
---@field health integer
---@field maxs Vector3
---@field mins Vector3
---@field velocity Vector3
---@field maxspeed number
---@field angvelocity number
---@field stepsize number
---@field origin Vector3
---@field fov number?
---@field name string
---@field dist number
---@field friction number
---@field team number
---@field sim_path Vector3[]?
---@field finalPos Vector3?
---@field score number
---@field isUbered boolean
---@field class integer
---@field maxhealth integer

---@type table<integer, EntityInfo>
local _entitylist = {}

local rgbaData = string.char(255, 255, 255, 255)
local texture = draw.CreateTextureRGBA(rgbaData, 1, 1) --- 1x1 white pixel

local paths = {
	proj = {},
	player = {},
}

local displayed_time = 0.0
local target_min_hull, target_max_hull = nil, nil
local vAngles = nil

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

local function ProcessClass(className, includeTeam)
	if plocal == nil then
		return
	end

	local list = entities.FindByClass(className)

	for _, entity in pairs (list) do
		if entity:IsDormant() or (entity:IsPlayer() and not entity:IsAlive() or entity:GetHealth() <= 0) then
			goto continue
		end

		if not includeTeam and entity:GetTeamNumber() == plocal:GetTeamNumber() then
			goto continue
		end

		_entitylist[#_entitylist+1] = {
			index = entity:GetIndex(),
			health = entity:GetHealth(),
			maxs = entity:GetMaxs(),
			mins = entity:GetMins(),
			velocity = entity:EstimateAbsVelocity() or Vector3(),
			maxspeed = entity:GetPropFloat("m_flMaxspeed") or 0,
			angvelocity = player_sim.GetSmoothedAngularVelocity(entity) or 0,
			stepsize = entity:GetPropFloat("m_flStepSize") or 18,
			origin = entity:GetAbsOrigin(),
			name = entity:GetName() or "unnamed",
			fov = math.huge,
			dist = math.huge,
			friction = entity:GetPropFloat("localdata", "m_flFriction") or 1.0,
			team = entity:GetTeamNumber(),
			score = 0,
			class = entity:GetPropInt("m_iClass") or nil,
			isUbered = entity:InCond(E_TFCOND.TFCond_Ubercharged),
			maxhealth = entity:GetMaxBuffedHealth()
		}

	    ::continue::
	end
end

---@param data EntityInfo
local function CalculateScore(data, eyePos, viewAngles)
    local score = 0
    local w = settings.weights

    -- Distance (closer = higher score)
    if w.distance_weight > 0 then
        local dist_score = 1 - math.min(data.dist / settings.max_distance, 1)
        score = score + dist_score * w.distance_weight
    end

    -- Health (lower health = higher score)
    if w.health_weight > 0 then
        local health_score = 1 - math.min(data.health / data.maxhealth, 1)
        score = score + health_score * w.health_weight
    end

	--- No need for this as we already reduce
	--- the entitylist with lowest fovs
    if w.fov_weight > 0 then
        local angle = math_utils.PositionAngles(eyePos, data.finalPos or data.origin)
        if angle then
            local fov = math_utils.AngleFov(viewAngles, angle)
            local fov_score = 1 - math.min(fov / settings.fov, 1)
            score = score + fov_score * w.fov_weight
        end
    end

    -- Visibility (if visible = full weight)
    if w.visibility_weight > 0 then
        score = score + w.visibility_weight
    end

    -- Speed (slower = easier to hit)
    if w.speed_weight and w.speed_weight ~= 0 then
        local speed = data.velocity:Length()
        local speed_score = 1 - math.min(speed / data.maxspeed, 1) -- normalize
        score = score + speed_score * w.speed_weight
    end

    -- Class priority
    if data.class and data.class == E_Character.TF2_Medic then
        score = score + w.medic_priority
    elseif data.class and data.class == E_Character.TF2_Sniper then
        score = score + w.sniper_priority
    end

    -- Uber penalty (skip ubercharged targets)
    if data.isUbered and w.uber_penalty then
        score = score + w.uber_penalty
    end

    return score
end

--- Returns a sorted table (:))
local function GetTargets(includeTeam)
    if plocal == nil or weapon == nil or weaponInfo == nil then
        return nil
    end

    -- clear old list
    for i = 1, #_entitylist do
        _entitylist[i] = nil
    end

    -- collect entities
    ProcessClass("CTFPlayer", includeTeam)
    ProcessClass("CObjetSentrygun", includeTeam)
    ProcessClass("CObjectDispenser", includeTeam)
    ProcessClass("CObjectTeleporter", includeTeam)

    local lpPos = plocal:GetAbsOrigin()
    local eyePos = lpPos + plocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    local viewAngles = engine.GetViewAngles()
    local projectileSpeed = weaponInfo:GetVelocity(0):Length2D()

    local candidates = {}

    --- basic filtering
    for _, data in ipairs(_entitylist) do
        local ent = entities.GetByIndex(data.index)
        if not ent then goto continue end

        local dist = (data.origin - lpPos):Length()
        if dist > settings.max_distance then goto continue end
        data.dist = dist

		if settings.onfov_only then
			local angle = math_utils.PositionAngles(eyePos, data.origin)
			if angle then
				local fov = math_utils.AngleFov(viewAngles, angle)
				if fov > settings.fov then goto continue end
			end
		end

        candidates[#candidates+1] = data

        ::continue::
    end

    local det_mult = weapon:AttributeHookFloat("sticky_arm_time") or 1.0
    local detonate_time = (settings.sim.use_detonate_time and weapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER) and 0.7 * det_mult or 0
    local choked_time = clientstate:GetChokedCommands()

    local final_targets = {}

    -- Simulation and multipoint
    for _, data in ipairs(candidates) do
        local ent = entities.GetByIndex(data.index)
        if not ent then goto continue end

        local travel_time_est = data.dist / projectileSpeed
        local total_time = travel_time_est + detonate_time
        local finalPos = Vector3(data.origin:Unpack())

        -- simulate player path if moving
        if data.velocity:Length() > 0 then
			data.origin.z = data.origin.z + 5 --- smol offset to fix a issue
            local time_ticks = math.ceil((total_time * 66.67) + 0.5) + choked_time + 1
            data.sim_path = player_sim.Run(data, ent, data.origin, time_ticks)
            if data.sim_path and #data.sim_path > 0 then
                finalPos = data.sim_path[#data.sim_path]
                travel_time_est = (finalPos - eyePos):Length() / projectileSpeed
                total_time = travel_time_est + detonate_time
            end
        else
            data.sim_path = {data.origin}
        end

        if total_time > settings.max_sim_time then goto continue end

        local visible, mpFinalPos = multipoint.Run(ent, weapon, weaponInfo, eyePos, finalPos)
        if not visible then goto continue end
        if mpFinalPos then finalPos = mpFinalPos end

        data.dist = (finalPos - lpPos):Length()
        data.finalPos = finalPos

        -- Assign weighted score
        data.score = CalculateScore(data, eyePos, viewAngles)

		if data.score < (settings.weights.min_score or 0) then
    		goto continue
		end

        final_targets[#final_targets+1] = data

        ::continue::
    end

    -- Sort by weighted score (highest first)
    table.sort(final_targets, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)

    -- Limit number of targets
    local max_targets = settings.max_targets or 2
    if #final_targets > max_targets then
        for i = max_targets + 1, #final_targets do
            final_targets[i] = nil
        end
    end

    _entitylist = final_targets
    return _entitylist
end

---@param cmd UserCmd
local function CreateMove(cmd)
	if clientstate.GetNetChannel() == nil then
		return
	end

	vAngles = nil

	if settings.enabled == false then
		return
	end

	if plocal == nil or weapon == nil or weaponInfo == nil then
		return
	end

	if (engine.IsChatOpen() or engine.Con_IsVisible() or engine.IsGameUIVisible()) == true then
		return
	end

	if not wep_utils.CanShoot() then
		return
	end

	if gui.GetValue("aim key") ~= 0 and input.IsButtonDown(gui.GetValue("aim key")) == false then
		return
	end

	if plocal:InCond(E_TFCOND.TFCond_Taunting) then
		return
	end

	if plocal:InCond(E_TFCOND.TFCond_HalloweenKart) then
		return
	end

	if weaponInfo.m_bCharges then
		local begintime = weapon:GetChargeBeginTime()
		local maxtime = weapon:GetChargeMaxTime()
		local percentage = (globals.CurTime() - begintime)/maxtime

		if percentage > maxtime then
			percentage = 0.0
		end

		if percentage < 0.1 then
			cmd.buttons = cmd.buttons | IN_ATTACK
			return
		end
	end

	---@type table<integer, EntityInfo>?
	local targets = GetTargets()
	if targets == nil then
		return
	end

	---@type EulerAngles?
	local angle = nil

	local charge = weaponInfo.m_bCharges and weapon:GetChargeBeginTime() or globals.CurTime()
    local eyePos = plocal:GetAbsOrigin() + plocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    local projectileSpeed = weaponInfo:GetVelocity(charge):Length2D()
    local gravity = client.GetConVar("sv_gravity") * weaponInfo:GetGravity(charge) * 0.5

	for _, target in ipairs(targets) do
		local finalPos = target.finalPos or target.origin

		-- calculate ballistic angle
		angle = math_utils.SolveBallisticArc(eyePos, finalPos, projectileSpeed, gravity)
		if angle then
			if weaponInfo.m_bCharges == false then
				cmd.buttons = cmd.buttons | IN_ATTACK
			end

			if settings.psilent then
				cmd.sendpacket = false
			end

			cmd.viewangles = Vector3(angle:Unpack())
			paths.player = target.sim_path
			displayed_time = globals.CurTime() + settings.draw_time
			target_min_hull, target_max_hull = target.mins, target.maxs
			vAngles = angle
			return
		end
	end
end

local function FrameStage(stage)
	if stage == E_ClientFrameStage.FRAME_NET_UPDATE_END then
		plocal = entities.GetLocalPlayer()
		if plocal == nil then
			weapon = nil
			weaponInfo = nil
			return
		end

		weapon = plocal:GetPropEntity("m_hActiveWeapon")
		weaponInfo = GetProjectileInformation(weapon:GetPropInt("m_iItemDefinitionIndex"))

		player_sim.RunBackground(entities.FindByClass("CTFPlayer"))
	elseif stage == E_ClientFrameStage.FRAME_RENDER_START and vAngles and settings.show_angles then
		if plocal == nil then return end
		if plocal:GetPropBool("m_nForceTauntCam") == false then return end
		plocal:SetVAngles(Vector3(vAngles:Unpack()))
	end
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
    if not paths.player or #paths.player < 2 then return end

    local last = client.WorldToScreen(paths.player[1])
    if not last then return end

    for i = 2, #paths.player do
        local current = client.WorldToScreen(paths.player[i])
        if current and last then
            DrawLine(last, current, settings.thickness.player_path)
        end
        last = current
    end
end

local function DrawProjPath()
    if not paths.proj or #paths.proj < 2 then return end

    local last = client.WorldToScreen(paths.proj[1].pos)
    if not last then return end

    for i = 2, #paths.proj do
        local current = client.WorldToScreen(paths.proj[i].pos)
        if current and last then
            DrawLine(last, current, settings.thickness.projectile_path)
        end
        last = current
    end
end

local font = draw.CreateFont("Arial", 12, 400)

local function Draw()
	if not settings.enabled then
		return
	end

	if displayed_time < globals.CurTime() then
		paths.player = {}
		paths.proj = {}
		return
	end

	if not paths or not paths.player or not paths.proj then
		return
	end

	if settings.draw_player_path and paths.player and #paths.player > 0 then
		if settings.colors.player_path >= 360 then
			draw.Color(255, 255, 255, 255)
		else
			local r, g, b = HSVToRGB(settings.colors.player_path, 0.5, 1)
			draw.Color((r*255)//1, (g*255)//1, (b*255)//1, 255)
		end
		DrawPlayerPath()
	end

	if settings.draw_bounding_box then
		local pos = paths.player[#paths.player]
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

	if settings.draw_proj_path and paths.proj and #paths.proj > 0 then
		if settings.colors.projectile_path >= 360 then
			draw.Color(255, 255, 255, 255)
		else
			local r, g, b = HSVToRGB(settings.colors.projectile_path, 0.5, 1)
			draw.Color((r*255)//1, (g*255)//1, (b*255)//1, 255)
		end
		DrawProjPath()
	end

	if settings.draw_quads then
		if target_max_hull == nil or target_min_hull == nil then
			return
		end

		local pos = paths.player[#paths.player]
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

	if settings.draw_scores then
		draw.Color(255, 255, 255, 255)
		draw.SetFont(font)
		for _, data in ipairs(_entitylist) do
			if data.score then
				local screen = client.WorldToScreen(data.origin)
				if screen then
					local text = tostring(data.score)
					local tw, th = draw.GetTextSize(text)
					draw.Text(screen[1] - (tw//2), screen[2] - (th//2), text)
				end
			end
		end
	end
end

local function Unload()
	menu.unload()
	draw.DeleteTexture(texture)
end

callbacks.Register("Draw", Draw)
callbacks.Register("CreateMove", CreateMove)
callbacks.Register("FrameStageNotify", FrameStage)
callbacks.Register("Unload", Unload)