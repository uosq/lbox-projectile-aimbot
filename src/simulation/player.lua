---@diagnostic disable: duplicate-doc-field, missing-fields

local sim = {}

local MASK_PLAYERSOLID = MASK_PLAYERSOLID
local DoTraceHull = engine.TraceHull
local Vector3 = Vector3
local math_deg = math.deg
local math_rad = math.rad
local math_atan = math.atan
local math_cos = math.cos
local math_sin = math.sin
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_pi = math.pi

local MIN_SPEED = 25
local MAX_ANGULAR_VEL = 360
local AIR_ACCELERATE = 10.0
local GROUND_ACCELERATE = 10.0
local SURFACE_FRICTION = 1.0
local MAX_CLIP_PLANES = 5
local DIST_EPSILON = 0.03125
local MAX_SAMPLES = 64
local IMPACT_NORMAL_FLOOR = 0.7

local temp_vec1 = Vector3()
local temp_vec2 = Vector3()
local temp_vec3 = Vector3()

local clip_planes = {}
for i = 1, MAX_CLIP_PLANES do
	clip_planes[i] = Vector3()
end

local position_samples = {}

local RuneTypes_t = {
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
}

local function GetEntityOrigin(pEntity)
	return pEntity:GetPropVector("tflocaldata", "m_vecOrigin") or pEntity:GetAbsOrigin()
end

---@param pTarget Entity
---@return number
local function GetAirSpeedCap(pTarget)
	local m_hGrapplingHookTarget = pTarget:GetPropEntity("m_hGrapplingHookTarget")
	if m_hGrapplingHookTarget then
		if pTarget:GetCarryingRuneType() == RuneTypes_t.RUNE_AGILITY then
			local m_iClass = pTarget:GetPropInt("m_iClass")
			return (m_iClass == E_Character.TF2_Soldier or E_Character.TF2_Heavy) and 850 or 950
		end
		local _, tf_grapplinghook_move_speed = client.GetConVar("tf_grapplinghook_move_speed")
		return tf_grapplinghook_move_speed
	elseif pTarget:InCond(E_TFCOND.TFCond_Charging) then
		local _, tf_max_charge_speed = client.GetConVar("tf_max_charge_speed")
		return tf_max_charge_speed
	else
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
		return flCap * pTarget:AttributeHookFloat("mod_air_control")
	end
end

-- Inline ClipVelocity to avoid function call overhead
local function ClipVelocity(velocity, normal, overbounce)
	local backoff = velocity.x * normal.x + velocity.y * normal.y + velocity.z * normal.z
	backoff = (backoff < 0) and (backoff * overbounce) or (backoff / overbounce)
	velocity.x = velocity.x - normal.x * backoff
	velocity.y = velocity.y - normal.y * backoff
	velocity.z = velocity.z - normal.z * backoff
end

local function AccelerateInPlace(velocity, wishdir, wishspeed, accel, dt, surf)
	local currentspeed = velocity:Length()
	local addspeed = wishspeed - currentspeed
	if addspeed <= 0 then
		return
	end

	local accelspeed = math_min(accel * dt * wishspeed * surf, addspeed)
	velocity.x = velocity.x + accelspeed * wishdir.x
	velocity.y = velocity.y + accelspeed * wishdir.y
	velocity.z = velocity.z + accelspeed * wishdir.z
end

local function AirAccelerateInPlace(v, wishdir, wishspeed, accel, dt, surf, pTarget)
	wishspeed = math_min(wishspeed, GetAirSpeedCap(pTarget))
	local currentspeed = v:Length()
	local addspeed = wishspeed - currentspeed
	if addspeed <= 0 then
		return
	end

	local accelspeed = math_min(accel * wishspeed * dt * surf, addspeed)
	v.x = v.x + accelspeed * wishdir.x
	v.y = v.y + accelspeed * wishdir.y
	v.z = v.z + accelspeed * wishdir.z
end

---@param pEntity Entity
local function AddPositionSample(pEntity)
	local index = pEntity:GetIndex()
	if not position_samples[index] then
		position_samples[index] = {}
	end

	local samples = position_samples[index]
	local sample = { pos = GetEntityOrigin(pEntity), time = globals.CurTime() }
	samples[#samples + 1] = sample

	if #samples > MAX_SAMPLES then
		table.remove(samples, 1)
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

	for i = 1, #samples - 2 do
		local s1, s2, s3 = samples[i], samples[i + 1], samples[i + 2]
		local dt1, dt2 = s2.time - s1.time, s3.time - s2.time

		if dt1 > 0 and dt2 > 0 then
			local vel1 = (s2.pos - s1.pos) / dt1
			local vel2 = (s3.pos - s2.pos) / dt2

			if vel1:Length() >= MIN_SPEED and vel2:Length() >= MIN_SPEED then
				local yaw1 = math_atan(vel1.y, vel1.x)
				local yaw2 = math_atan(vel2.y, vel2.x)
				local diff = math_deg((yaw2 - yaw1 + math_pi) % two_pi - math_pi)
				local angular_velocity = diff / ((dt1 + dt2) * 0.5)

				if math_abs(angular_velocity) < MAX_ANGULAR_VEL then
					ang_vels[#ang_vels + 1] = angular_velocity
				end
			end
		end
	end

	if #ang_vels == 0 then
		return 0
	end

	if #ang_vels >= 3 then
		table.sort(ang_vels)
		return ang_vels[math_floor(#ang_vels * 0.5) + 1]
	end

	local smoothed = ang_vels[1]
	for i = 2, #ang_vels do
		smoothed = smoothed * 0.7 + ang_vels[i] * 0.3
	end
	return smoothed
end

function sim.RunBackground(entitylist)
	for _, player in pairs(entitylist) do
		AddPositionSample(player)
	end
end

local function TryPlayerMove(origin, velocity, frametime, mins, maxs, shouldHitEntity, surface_friction)
	local time_left = frametime
	local numplanes = 0

	for bumpcount = 0, 3 do
		if velocity:LengthSqr() < 0.0001 then
			break
		end

		temp_vec1.x = origin.x + velocity.x * time_left
		temp_vec1.y = origin.y + velocity.y * time_left
		temp_vec1.z = origin.z + velocity.z * time_left

		local trace = DoTraceHull(origin, temp_vec1, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

		if trace.allsolid then
			velocity.x, velocity.y, velocity.z = 0, 0, 0
			return
		end

		if trace.fraction > 0 then
			origin.x, origin.y, origin.z = trace.endpos.x, trace.endpos.y, trace.endpos.z
		end

		if trace.fraction >= 0.99 then
			break
		end

		time_left = time_left * (1 - trace.fraction)

		if numplanes >= MAX_CLIP_PLANES then
			velocity.x, velocity.y, velocity.z = 0, 0, 0
			return
		end

		-- Store plane normal
		local plane = clip_planes[numplanes + 1]
		plane.x, plane.y, plane.z = trace.plane.x, trace.plane.y, trace.plane.z
		numplanes = numplanes + 1

		-- Just clip against the new plane
		local overbounce = (trace.plane.z > 0.7) and 1.0 or (1.0 + (1.0 - surface_friction) * 0.5)
		ClipVelocity(velocity, plane, overbounce)

		-- Check velocity against all planes
		local valid = true
		for i = 1, numplanes do
			local dot = velocity.x * clip_planes[i].x + velocity.y * clip_planes[i].y + velocity.z * clip_planes[i].z
			if dot < 0 then
				valid = false
				break
			end
		end

		if not valid and numplanes >= 2 then
			temp_vec2.x = clip_planes[1].y * clip_planes[2].z - clip_planes[1].z * clip_planes[2].y
			temp_vec2.y = clip_planes[1].z * clip_planes[2].x - clip_planes[1].x * clip_planes[2].z
			temp_vec2.z = clip_planes[1].x * clip_planes[2].y - clip_planes[1].y * clip_planes[2].x

			local len = temp_vec2:LengthSqr()
			if len > 0.001 then
				temp_vec2.x, temp_vec2.y, temp_vec2.z = temp_vec2.x / len, temp_vec2.y / len, temp_vec2.z / len
				local scalar = velocity.x * temp_vec2.x + velocity.y * temp_vec2.y + velocity.z * temp_vec2.z
				velocity.x, velocity.y, velocity.z = temp_vec2.x * scalar, temp_vec2.y * scalar, temp_vec2.z * scalar
			else
				velocity.x, velocity.y, velocity.z = 0, 0, 0
			end
		end
	end
end

local function StepMove(
	origin,
	velocity,
	frametime,
	mins,
	maxs,
	shouldHitEntity,
	surface_friction,
	step_size,
	is_on_ground
)
	local orig_x, orig_y, orig_z = origin.x, origin.y, origin.z
	local orig_vx, orig_vy, orig_vz = velocity.x, velocity.y, velocity.z

	-- Try regular move first
	TryPlayerMove(origin, velocity, frametime, mins, maxs, shouldHitEntity, surface_friction)

	local down_dist = (origin.x - orig_x) + (origin.y - orig_y)

	if not is_on_ground or down_dist > 5.0 or (orig_vx * orig_vx + orig_vy * orig_vy) < 1.0 then
		return
	end

	local down_x, down_y, down_z = origin.x, origin.y, origin.z
	local down_vx, down_vy, down_vz = velocity.x, velocity.y, velocity.z

	-- reset and try step up
	origin.x, origin.y, origin.z = orig_x, orig_y, orig_z
	velocity.x, velocity.y, velocity.z = orig_vx, orig_vy, orig_vz

	-- step up
	temp_vec1.x, temp_vec1.y, temp_vec1.z = origin.x, origin.y, origin.z + step_size + DIST_EPSILON
	local up_trace = DoTraceHull(origin, temp_vec1, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

	if not up_trace.startsolid and not up_trace.allsolid then
		origin.x, origin.y, origin.z = up_trace.endpos.x, up_trace.endpos.y, up_trace.endpos.z
	end

	-- move forward
	local up_orig_x, up_orig_y = origin.x, origin.y
	TryPlayerMove(origin, velocity, frametime, mins, maxs, shouldHitEntity, surface_friction)

	local up_dist = (origin.x - up_orig_x) + (origin.y - up_orig_y)

	-- if stepping up didn't help, revert to original result
	if up_dist <= down_dist then
		origin.x, origin.y, origin.z = down_x, down_y, down_z
		velocity.x, velocity.y, velocity.z = down_vx, down_vy, down_vz
		return
	end

	-- step down to ground
	temp_vec1.x, temp_vec1.y = origin.x, origin.y
	temp_vec1.z = origin.z - step_size - DIST_EPSILON
	local down_trace = DoTraceHull(origin, temp_vec1, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

	if down_trace.plane.z >= 0.7 and not down_trace.startsolid and not down_trace.allsolid then
		origin.x, origin.y, origin.z = down_trace.endpos.x, down_trace.endpos.y, down_trace.endpos.z
	end
end

local function ApplyFriction(velocity, pTarget, is_on_ground)
	local speed = velocity:Length()
	if speed < 0.1 then
		return
	end

	if is_on_ground then
		local _, sv_friction = client.GetConVar("sv_friction")
		local surfaceFriction = pTarget:GetPropFloat("m_flFriction") or SURFACE_FRICTION
		local _, sv_stopspeed = client.GetConVar("sv_stopspeed")

		local control = (speed < sv_stopspeed) and sv_stopspeed or speed
		local drop = control * sv_friction * surfaceFriction * globals.TickInterval()
		local newspeed = math_max(0, speed - drop)

		if newspeed ~= speed and speed > 0 then
			local scale = newspeed / speed
			velocity.x = velocity.x * scale
			velocity.y = velocity.y * scale
			velocity.z = velocity.z * scale
		end
	end
end

local function CategorizePosition(pos, vel, mins, maxs, shouldHitEntity)
	temp_vec1.x, temp_vec1.y, temp_vec1.z = pos.x, pos.y, pos.z
	temp_vec2.x, temp_vec2.y = pos.x, pos.y
	temp_vec2.z = pos.z - 66

	local is_on_ground = false
	local ground_normal = nil
	local surface_friction = 1.0

	-- check velocity in z - if shooting up fast, not on ground
	if vel.z <= 180.0 then
		local trace = DoTraceHull(temp_vec1, temp_vec2, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

		-- check if we hit a walkable surface
		-- ground must have normal.z >= 0.7
		if trace.fraction < 0.06 and (trace.plane.z >= IMPACT_NORMAL_FLOOR) then
			is_on_ground = true
			ground_normal = Vector3(trace.plane.x, trace.plane.y, trace.plane.z)

			-- snap to ground if not in water and trace succeeded
			if not trace.startsolid and not trace.allsolid then
				-- move player down that small amount to stay on ground
				pos.x = temp_vec1.x + trace.fraction * (temp_vec2.x - temp_vec1.x)
				pos.y = temp_vec1.y + trace.fraction * (temp_vec2.y - temp_vec1.y)
				pos.z = temp_vec1.z + trace.fraction * (temp_vec2.z - temp_vec1.z)
			end
		end
	end

	return is_on_ground, ground_normal, surface_friction
end

---@param pInfo EntityInfo
---@param pTarget Entity
---@param initial_pos Vector3
---@param time number
---@return Vector3[]
function sim.Run(pInfo, pTarget, initial_pos, time)
	local tick_interval = globals.TickInterval()
	local local_player_index = client.GetLocalPlayerIndex()

	local surface_friction = pInfo.friction or 1.0
	local angular_velocity = pInfo.angvelocity * tick_interval
	local maxspeed = pInfo.maxspeed or 450
	local step_size = pInfo.stepsize or 18
	local mins = pInfo.mins
	local maxs = pInfo.maxs
	local _, sv_gravity = client.GetConVar("sv_gravity")
	local gravity_step = sv_gravity * tick_interval

	local pos = Vector3(initial_pos.x, initial_pos.y, initial_pos.z)
	local vel = Vector3(pInfo.velocity.x, pInfo.velocity.y, pInfo.velocity.z)

	local positions = {}

	local cos_yaw, sin_yaw
	if angular_velocity ~= 0 then
		local yaw = math_rad(angular_velocity)
		cos_yaw, sin_yaw = math_cos(yaw), math_sin(yaw)
	end

	local function shouldHitEntity(ent)
		local idx = ent:GetIndex()
		return idx ~= local_player_index and ent:GetTeamNumber() ~= pInfo.team
	end

	temp_vec3.x, temp_vec3.y, temp_vec3.z = 0, 0, -step_size

	for i = 1, time do
		local is_on_ground = CategorizePosition(pos, vel, mins, maxs, shouldHitEntity)

		-- Friction
		-- i wanted to use this, but my implementation does not like acceleration
		--ApplyFriction(vel, pTarget, is_on_ground)

		-- Apply rotation
		if angular_velocity ~= 0 then
			local vx, vy = vel.x, vel.y
			vel.x = vx * cos_yaw - vy * sin_yaw
			vel.y = vx * sin_yaw + vy * cos_yaw
		end

		temp_vec1.x, temp_vec1.y = pos.x + vel.x * tick_interval, pos.y + vel.y * tick_interval
		temp_vec1.z = pos.z + vel.z * tick_interval
		temp_vec2.x, temp_vec2.y, temp_vec2.z = temp_vec1.x, temp_vec1.y, temp_vec1.z - step_size

		if not is_on_ground then
			vel.z = vel.z - (gravity_step * 0.5)
		end

		-- Acceleration
		local horizontal_speed = vel:Length2DSqr()
		if horizontal_speed > 0.0001 then
			local inv_len = 1.0 / horizontal_speed
			-- This is the direction they're currently moving
			local wish_x = vel.x * inv_len
			local wish_y = vel.y * inv_len

			-- Apply angular rotation to predict their turning
			if angular_velocity ~= 0 then
				local vx, vy = wish_x, wish_y
				wish_x = vx * cos_yaw - vy * sin_yaw
				wish_y = vx * sin_yaw + vy * cos_yaw
			end

			temp_vec1.x, temp_vec1.y, temp_vec1.z = wish_x, wish_y, 0
			local wishspeed = math_min(horizontal_speed, maxspeed)

			if is_on_ground then
				AccelerateInPlace(vel, temp_vec1, wishspeed, GROUND_ACCELERATE, tick_interval, surface_friction)
			else
				AirAccelerateInPlace(
					vel,
					temp_vec1,
					wishspeed,
					AIR_ACCELERATE,
					tick_interval,
					surface_friction,
					pTarget
				)
			end

			vel.x = math_max(-3500, math_min(3500, vel.x)) -- clamp to reasonable bounds
			vel.y = math_max(-3500, math_min(3500, vel.y)) -- clamp to reasonable bounds
			vel.z = math_max(-3500, math_min(3500, vel.z)) -- clamp to reasonable bounds
		end

		-- Speed cap on ground
		if is_on_ground then
			local vel_length = vel:Length()
			if vel_length > maxspeed then
				local scale = maxspeed / vel_length
				vel.x, vel.y = vel.x * scale, vel.y * scale
			end
		end

		-- Move
		StepMove(pos, vel, tick_interval, mins, maxs, shouldHitEntity, surface_friction, step_size, is_on_ground)

		-- Gravity
		if not is_on_ground then
			vel.z = vel.z - gravity_step * 0.5
		elseif vel.z < 0 then
			vel.z = 0
		end

		positions[#positions + 1] = Vector3(pos.x, pos.y, pos.z)
	end

	return positions
end

sim.GetSmoothedAngularVelocity = GetSmoothedAngularVelocity
return sim
