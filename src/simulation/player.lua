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
local MAX_SAMPLES = 8
local MIN_SPEED = 25 -- HU/s
local MAX_ANGULAR_VEL = 540 -- deg/s
local WALKABLE_ANGLE = 45 -- degrees
local GRAVITY_Z_THRESHOLD = -50
local MIN_VELOCITY_Z = 0.1
local MIN_STEP_HEIGHT = 0.1
local AIR_SPEED_CAP = 30.0
local AIR_ACCELERATE = 10.0 -- Default air acceleration value
local GROUND_ACCELERATE = 10.0 -- Default ground acceleration value
local SURFACE_FRICTION = 1.0 -- Default surface friction

---@class Sample
---@field pos Vector3
---@field time number

---@type table<number, Sample[]>
local position_samples = {}

local zero_vector = Vector3(0, 0, 0)
local up_vector = Vector3(0, 0, 1)

---@param velocity Vector3
---@param wishdir Vector3
---@param wishspeed number
---@param accel number
---@param frametime number
---@param surface_friction number
---@return Vector3
local function Accelerate(velocity, wishdir, wishspeed, accel, frametime, surface_friction)
	-- See if we are changing direction a bit
	local currentspeed = velocity:Dot(wishdir)

	-- Reduce wishspeed by the amount of veer.
	local addspeed = wishspeed - currentspeed

	-- If not going to add any speed, done.
	if addspeed <= 0 then
		return velocity
	end

	-- Determine amount of acceleration.
	local accelspeed = accel * frametime * wishspeed * surface_friction

	-- Cap at addspeed
	if accelspeed > addspeed then
		accelspeed = addspeed
	end

	-- Adjust velocity.
	local new_velocity = Vector3(
		velocity.x + accelspeed * wishdir.x,
		velocity.y + accelspeed * wishdir.y,
		velocity.z + accelspeed * wishdir.z
	)

	return new_velocity
end

---@param velocity Vector3
---@param wishdir Vector3
---@param wishspeed number
---@param accel number
---@param frametime number
---@param surface_friction number
---@return Vector3
local function AirAccelerate(velocity, wishdir, wishspeed, accel, frametime, surface_friction)
	local wishspd = wishspeed

	-- Cap speed (equivalent to GetAirSpeedCap())
	if wishspd > AIR_SPEED_CAP then
		wishspd = AIR_SPEED_CAP
	end

	-- Determine veer amount
	local currentspeed = velocity:Dot(wishdir)

	-- See how much to add
	local addspeed = wishspd - currentspeed

	-- If not adding any, done.
	if addspeed <= 0 then
		return velocity
	end

	-- Determine acceleration speed after acceleration
	local accelspeed = accel * wishspeed * frametime * surface_friction

	-- Cap it
	if accelspeed > addspeed then
		accelspeed = addspeed
	end

	-- Adjust velocity
	local new_velocity = Vector3(
		velocity.x + accelspeed * wishdir.x,
		velocity.y + accelspeed * wishdir.y,
		velocity.z + accelspeed * wishdir.z
	)

	return new_velocity
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
	local base_alpha = grounded and 1 or 0.2
	local smoothed = ang_vels[1]

	for i = 2, #ang_vels do
		local alpha = math_max(0.05, math_min(base_alpha, 0.4))
		smoothed = smoothed * (1 - alpha) + ang_vels[i] * alpha
	end

	return smoothed
end

-- Cache enemy team lookup
local cached_enemy_team = nil
local last_team_check = 0

local function GetEnemyTeam()
	local current_time = globals.CurTime()
	if current_time - last_team_check > 1.0 then -- Cache for 1 second
		local pLocal = entities.GetLocalPlayer()
		if pLocal then
			cached_enemy_team = pLocal:GetTeamNumber() == 2 and 3 or 2
		end
		last_team_check = current_time
	end
	return cached_enemy_team
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

	local positions = {}
	local mins, maxs = pTarget:GetMins(), pTarget:GetMaxs()
	local down_vector = Vector3(0, 0, -stepSize)
	local step_up_vector = Vector3(0, 0, stepSize)

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

	for i = 1, time do
		-- apply angular velocity rotation (if we have it)
		if angular_velocity ~= 0 then
			local vx, vy = smoothed_velocity.x, smoothed_velocity.y
			smoothed_velocity.x = vx * cos_yaw - vy * sin_yaw
			smoothed_velocity.y = vx * sin_yaw + vy * cos_yaw
		end

		-- ground check first to determine acceleration type
		local next_pos_check = last_pos + smoothed_velocity * tick_interval
		local ground_trace = TraceLine(next_pos_check, next_pos_check + down_vector, MASK_PLAYERSOLID, shouldHitEntity)
		local is_on_ground = ground_trace and ground_trace.fraction < 1.0 and smoothed_velocity.z <= MIN_VELOCITY_Z

		-- apply appropriate acceleration based on ground state
		local horizontal_vel = Vector3(smoothed_velocity.x, smoothed_velocity.y, 0)
		local horizontal_speed = horizontal_vel:Length()

		if horizontal_speed > 0.1 then
			local wishdir = horizontal_vel * (1.0 / horizontal_speed)
			local wishspeed = math_min(horizontal_speed, target_max_speed)

			if is_on_ground then
				-- apply ground acceleration
				smoothed_velocity = Accelerate(
					smoothed_velocity,
					wishdir,
					wishspeed,
					GROUND_ACCELERATE,
					tick_interval,
					surface_friction
				)
			else
				-- apply air acceleration when not on ground and falling
				if smoothed_velocity.z < 0 then
					smoothed_velocity = AirAccelerate(
						smoothed_velocity,
						wishdir,
						wishspeed,
						AIR_ACCELERATE,
						tick_interval,
						surface_friction
					)
				end
			end
		end

		-- Clamp velocity to max speed when on ground
		if is_on_ground then
			local vel_length = smoothed_velocity:Length()
			if vel_length > target_max_speed then
				smoothed_velocity = smoothed_velocity * (target_max_speed / vel_length)
			end
		end

		local move_delta = smoothed_velocity * tick_interval
		local next_pos = last_pos + move_delta

		-- Movement collision check
		local trace = DoTraceHull(last_pos, next_pos, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

		if trace.fraction < 1.0 then
			-- Try step-up movement
			if smoothed_velocity.z >= GRAVITY_Z_THRESHOLD then
				local step_up = last_pos + step_up_vector
				local step_up_trace = DoTraceHull(last_pos, step_up, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

				if step_up_trace.fraction >= 1.0 then
					local step_forward = step_up + move_delta
					local step_forward_trace =
						DoTraceHull(step_up, step_forward, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

					if step_forward_trace.fraction > 0 then
						local step_down_start = step_forward_trace.endpos
						local step_down_end = step_down_start + down_vector
						local step_down_trace =
							DoTraceHull(step_down_start, step_down_end, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

						if step_down_trace.fraction < 1.0 then
							local ground_angle = math_deg(math_acos(step_down_trace.plane:Dot(up_vector)))
							local actual_step_height = step_down_start.z - step_down_trace.endpos.z

							if
								ground_angle <= WALKABLE_ANGLE
								and actual_step_height <= stepSize
								and actual_step_height > MIN_STEP_HEIGHT
							then
								next_pos = step_down_trace.endpos
								last_pos = next_pos
								positions[#positions + 1] = last_pos
								was_onground = true
								goto continue
							end
						end
					end
				end
			end

			-- Slide along surface
			next_pos = trace.endpos
			local dot = smoothed_velocity:Dot(trace.plane)
			smoothed_velocity = smoothed_velocity - trace.plane * dot
		end

		last_pos = next_pos
		positions[#positions + 1] = last_pos

		-- Update ground state and apply gravity
		was_onground = is_on_ground

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
