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
local MAX_ANGULAR_VEL = 540 -- deg/s
local WALKABLE_ANGLE = 45   -- degrees
local MIN_VELOCITY_Z = 0.1
local AIR_SPEED_CAP = 30.0
local AIR_ACCELERATE = 10.0    -- Default air acceleration value
local GROUND_ACCELERATE = 10.0 -- Default ground acceleration value
local SURFACE_FRICTION = 1.0   -- Default surface friction

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

-- Reusable temp vectors for zero-GC operations
local tmp1, tmp2, tmp3 = Vector3(), Vector3(), Vector3()
local tmp4 = Vector3() -- for wishdir (GC‑free)

---@param vec Vector3
local function NormalizeVector(vec)
	local len = vec:Length()
	return len == 0 and vec or vec / len --branchless
end

-- Helper functions for vector operations (no metatable modifications)
---@param vec Vector3
---@param other Vector3
---@param s number
local function AddMul(vec, other, s)
	vec.x = vec.x + other.x * s
	vec.y = vec.y + other.y * s
	vec.z = vec.z + other.z * s
	return vec
end

---@param vec Vector3
---@param other Vector3
local function Set(vec, other)
	vec.x = other.x
	vec.y = other.y
	vec.z = other.z
	return vec
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
local function AccelerateInPlace(v, wishdir, wishspeed, accel, dt, surf)
	local currentspeed = v:Dot(wishdir)
	local addspeed     = wishspeed - currentspeed
	if addspeed <= 0 then return end

	local accelspeed = accel * dt * wishspeed * surf
	if accelspeed > addspeed then accelspeed = addspeed end

	v.x = v.x + accelspeed * wishdir.x
	v.y = v.y + accelspeed * wishdir.y
	v.z = v.z + accelspeed * wishdir.z
end

local function AirAccelerateInPlace(v, wishdir, wishspeed, accel, dt, surf)
	if wishspeed > AIR_SPEED_CAP then wishspeed = AIR_SPEED_CAP end

	local currentspeed = v:Dot(wishdir)
	local addspeed     = wishspeed - currentspeed
	if addspeed <= 0 then return end

	local accelspeed = accel * wishspeed * dt * surf
	if accelspeed > addspeed then accelspeed = addspeed end

	v.x = v.x + accelspeed * wishdir.x
	v.y = v.y + accelspeed * wishdir.y
	v.z = v.z + accelspeed * wishdir.z
end
-- ===========================================================

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

	local positions = { initial_pos }

	local mins, maxs = pTarget:GetMins(), pTarget:GetMaxs()
	local down_vector = tmp1
	down_vector.x, down_vector.y, down_vector.z = 0, 0, -stepSize -- re-use tmp1

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

	-- ********* MAIN TICK LOOP *********
	for i = 1, time do
		-- ---  A. rotate velocity (no allocs)
		if angular_velocity ~= 0 then
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

		if horizontal_speed > 0.1 then
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
