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
local MIN_SPEED = 25        -- HU/s
local MAX_ANGULAR_VEL = 360 -- deg/s
local WALKABLE_ANGLE = 45   -- degrees
local MIN_VELOCITY_Z = 0.1
local AIR_SPEED_CAP = 30.0
local AIR_ACCELERATE = 10.0    -- Default air acceleration value
local GROUND_ACCELERATE = 10.0 -- Default ground acceleration value
local SURFACE_FRICTION = 1.0   -- Default surface friction

local MAX_CLIP_PLANES = 5
local DIST_EPSILON = 0.03125 -- Small epsilon for step calculations

local MAX_SAMPLES      = 16       -- tuned window size
local SMOOTH_ALPHA_G   = 0.392   -- tuned ground α
local SMOOTH_ALPHA_A   = 0.127   -- tuned air α

local COORD_FRACTIONAL_BITS =	5
local COORD_DENOMINATOR =		(1<<(COORD_FRACTIONAL_BITS))
local COORD_RESOLUTION =		(1.0/(COORD_DENOMINATOR))

local impact_planes = {}
local MAX_IMPACT_PLANES = 5

---@class Sample
---@field pos Vector3
---@field time number

---@type table<number, Sample[]>
local position_samples = {}

local zero_vector = Vector3(0, 0, 0)
local up_vector = Vector3(0, 0, 1)

-- Reusable temp vectors for zero-GC operations
local tmp1, tmp2, tmp3 = Vector3(), Vector3(), Vector3()
local tmp4 = Vector3() -- for wishdir (GC‑free)

---@param vec Vector3
local function NormalizeVector(vec)
	local len = vec:Length()
	return len == 0 and vec or vec / len --branchless
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

	-- Use tmp1 for the change vector to avoid allocation
	tmp1.x = normal.x * backoff
	tmp1.y = normal.y * backoff
	tmp1.z = normal.z * backoff

	-- Return new vector with subtraction
	return Vector3(velocity.x - tmp1.x, velocity.y - tmp1.y, velocity.z - tmp1.z)
end

-- === GC‑FREE IN‑PLACE ACCELERATION =========================
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

local function AirAccelerateInPlace(v, wishdir, wishspeed, accel, dt, surf)
	if wishspeed > AIR_SPEED_CAP then wishspeed = AIR_SPEED_CAP end

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
-- ===========================================================

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

		redirected = ClipVelocity(redirected, normal, 1.0)

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
		crease:Normalize()
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
		redirected = ClipVelocity(redirected, normal, overbounce)
	end

	return redirected
end

---@param vecPredictedPos Vector3
---@param vecMins Vector3
---@param vecMaxs Vector3
local function InWater(vecPredictedPos, vecMins, vecMaxs)
    local pos = vecPredictedPos + (vecMins + vecMaxs) * 0.5
    local contents = engine.GetPointContents(pos)
    return (contents & MASK_WATER) ~= 0
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
	local planes = {}
	local primal_velocity = Vector3(velocity.x, velocity.y, velocity.z)
	local original_velocity = Vector3(velocity.x, velocity.y, velocity.z)
	local new_velocity = Vector3(0, 0, 0)
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
		planes[numplanes + 1] = normal
		numplanes = numplanes + 1
		impact_planes[#impact_planes + 1] = normal

		if numplanes == 1 and trace.plane.z <= 0.7 then
			local bounce_factor = 1.0 + (1.0 - surface_friction) * 0.5
			new_velocity = ClipVelocity(original_velocity, planes[1], bounce_factor)
			velocity = Vector3(new_velocity.x, new_velocity.y, new_velocity.z)
			original_velocity = Vector3(new_velocity.x, new_velocity.y, new_velocity.z)
		else
			local i = 0
			while i < numplanes do
				velocity = ClipVelocity(original_velocity, planes[i + 1], 1.0)

				local j = 0
				while j < numplanes do
					if j ~= i and velocity:Dot(planes[j + 1]) < 0 then
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

				local dir = NormalizeVector(planes[1]:Cross(planes[2]))
				local d = dir:Dot(velocity)
				velocity = dir * d
			end

			local d = velocity:Dot(primal_velocity)
			if d <= 0 then
				return current_origin, Vector3(0, 0, 0), blocked
			end
		end
	end

	-- Optional redirection here
	local is_grounded = IsOnGround(current_origin, mins, maxs, pTarget, pTarget:GetPropFloat("m_flStepSize"))
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
		and normal >= 0.7 --- cant hit on a steep slope that we cant stand on anyway
	then
		local z_delta = math_abs(vecPos.z - trace.endpos.z)
		if z_delta > 0.5 * COORD_RESOLUTION then
			vecPos.x = trace.endpos.x
			vecPos.y = trace.endpos.y
			vecPos.z = trace.endpos.z
		end
	end
end

---@param pos Vector3
---@param vel Vector3
---@param tick_interval number
---@param mins Vector3
---@param maxs Vector3
---@param friction number
---@param maxspeed number
---@param accel number
---@param step_size number
---@param shouldHitEntity function
---@param pTarget Entity
---@return Vector3, Vector3
local function WalkMove(pos, vel, tick_interval, mins, maxs, friction, maxspeed, accel, step_size, shouldHitEntity, pTarget)
	local trace_start = Vector3(pos.x, pos.y, pos.z)
	local trace_end = Vector3(pos.x, pos.y, pos.z - step_size - DIST_EPSILON)
	local trace = DoTraceHull(trace_start, trace_end, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

	local is_steep = trace.plane:Dot(up_vector) < math_cos(math_rad(WALKABLE_ANGLE))
	local is_grounded = trace.fraction < 1 and not trace.startsolid and not trace.allsolid

	local slope_normal = trace.plane
	local slope_downhill = Vector3()

	if is_grounded and is_steep then
		--- compute downhill direction from slope normal
		slope_downhill = slope_normal:Cross(up_vector):Cross(slope_normal)
		slope_downhill:Normalize()

		--- project velocity onto downhill vector
		local slide_speed = vel:Dot(slope_downhill)
		vel = slope_downhill * slide_speed
	else
		--- standard walk acceleration
		local wishvel = Vector3(vel.x, vel.y, 0)
		local wishspeed = wishvel:Length()
		if wishspeed > 0.1 then
			local wishdir = wishvel / wishspeed
			wishspeed = math_min(wishspeed, maxspeed)
			AccelerateInPlace(vel, wishdir, wishspeed, accel, tick_interval, friction)
		end
	end

	--- clamp to max speed
	local speed = vel:Length()
	if speed > maxspeed then
		local scale = maxspeed / speed
		vel.x = vel.x * scale
		vel.y = vel.y * scale
	end

	--- step movement
	local new_pos, new_vel = StepMove(
		pos, vel, tick_interval, mins, maxs,
		shouldHitEntity, pTarget, friction, step_size
	)

	return new_pos, new_vel
end

---@param pTarget Entity
---@param initial_pos Vector3
---@param time integer
---@param settings table
---@return Vector3[]
function sim.Run(settings, pTarget, initial_pos, time)
	local smoothed_velocity = pTarget:GetPropVector("m_vecVelocity[0]")
	local last_pos = initial_pos
	local tick_interval = globals.TickInterval()
	local angular_velocity = GetSmoothedAngularVelocity(pTarget) * tick_interval
	local gravity_step = client.GetConVar("sv_gravity") * tick_interval
	local target_max_speed = pTarget:GetPropFloat("m_flMaxspeed") or 450
	local local_player_index = client.GetLocalPlayerIndex()
	local target_team = pTarget:GetTeamNumber()
	local surface_friction = pTarget:GetPropFloat("m_flFriction") or SURFACE_FRICTION
	local step_size = pTarget:GetPropFloat("m_flStepSize") or 18.0

	local positions = {}

	local mins, maxs = pTarget:GetMins(), pTarget:GetMaxs()
	local down_vector = tmp1
	down_vector.x, down_vector.y, down_vector.z = 0, 0, -step_size -- re-use tmp1

	-- pre calculate rotation values if angular velocity exists
	local cos_yaw, sin_yaw
	if angular_velocity ~= 0 and settings.sim.rotation then
		local yaw = math_rad(angular_velocity)
		cos_yaw, sin_yaw = math_cos(yaw), math_sin(yaw)
	end

	local function shouldHitEntity(ent)
		local ent_index = ent:GetIndex()
		return ent_index ~= local_player_index and ent:GetTeamNumber() ~= target_team
	end

	local was_onground = false

	-- ********* MAIN TICK LOOP *********
	for i = 1, time do
		-- ---  A. rotate velocity (no allocs)
		if angular_velocity ~= 0 and settings.sim.rotation then
			local vx, vy = smoothed_velocity.x, smoothed_velocity.y
			smoothed_velocity.x = vx * cos_yaw - vy * sin_yaw
			smoothed_velocity.y = vx * sin_yaw + vy * cos_yaw
		end

		-- ---  B. ground check
		local next_pos = tmp2 -- reuse tmp2
		-- Set next_pos to last_pos and add velocity * tick_interval
		next_pos.x, next_pos.y, next_pos.z = last_pos.x, last_pos.y, last_pos.z
		next_pos.x = next_pos.x + smoothed_velocity.x * tick_interval
		next_pos.y = next_pos.y + smoothed_velocity.y * tick_interval
		next_pos.z = next_pos.z + smoothed_velocity.z * tick_interval

		-- Set tmp3 to next_pos + down_vector for ground trace
		tmp3.x, tmp3.y, tmp3.z = next_pos.x, next_pos.y, next_pos.z
		tmp3.x = tmp3.x + down_vector.x
		tmp3.y = tmp3.y + down_vector.y
		tmp3.z = tmp3.z + down_vector.z

		local ground_trace = TraceLine(next_pos, tmp3, MASK_PLAYERSOLID, shouldHitEntity)
		local is_on_ground = ground_trace and ground_trace.fraction < 1.0 and smoothed_velocity.z <= MIN_VELOCITY_Z

		-- ---  C. horizontal accel
		local horizontal_vel = tmp3 -- re-use tmp3
		horizontal_vel.x, horizontal_vel.y, horizontal_vel.z = smoothed_velocity.x, smoothed_velocity.y,
			smoothed_velocity.z
		horizontal_vel.z = 0
		local horizontal_speed = horizontal_vel:Length()

		if horizontal_speed > 0.1 and settings.sim.acceleration then
			local inv_len = 1.0 / horizontal_speed
			tmp4.x = horizontal_vel.x * inv_len
			tmp4.y = horizontal_vel.y * inv_len
			tmp4.z = 0
			local wishdir = tmp4 -- alias for clarity; no alloc
			local wishspeed = math_min(horizontal_speed, target_max_speed)

			if is_on_ground then
				-- apply ground acceleration
				AccelerateInPlace(smoothed_velocity, wishdir, wishspeed,
					GROUND_ACCELERATE, tick_interval, surface_friction)
			else
				-- apply air acceleration when not on ground and falling
				if smoothed_velocity.z < 0 then
					AirAccelerateInPlace(smoothed_velocity, wishdir, wishspeed,
						AIR_ACCELERATE, tick_interval, surface_friction)
				end
			end
		end

		-- ---  D. clamp ground speed (no alloc)
		if is_on_ground then
			local vel_length = smoothed_velocity:Length()
			if vel_length > target_max_speed then
				local scale = target_max_speed / vel_length
				smoothed_velocity.x = smoothed_velocity.x * scale
				smoothed_velocity.y = smoothed_velocity.y * scale
				smoothed_velocity.z = smoothed_velocity.z * scale
			end
		end

		-- ---  E. physics move (StepMove still allocates internally)
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

		-- try to keep player on ground after move
		if settings.sim.stay_on_ground then
			StayOnGround(new_pos, mins, maxs, step_size, shouldHitEntity)
		end

		last_pos = new_pos
		smoothed_velocity = new_velocity
		positions[#positions + 1] = last_pos

		-- ---  F. gravity
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
