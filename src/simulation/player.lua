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
		local surfaceFriction = pTarget:GetPropFloat("m_flFriction") or 1.0
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

	local surface_friction = pInfo.m_flFriction
	local angular_velocity = pInfo.m_flAngularVelocity * tick_interval
	local maxspeed = pInfo.m_flMaxspeed
	local step_size = pInfo.m_flStepSize
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
