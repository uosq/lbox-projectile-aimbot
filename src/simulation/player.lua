---@diagnostic disable: duplicate-doc-field, missing-fields
local sim = {}

---@type Vector3
local position_samples = {}

---@type Vector3
local velocity_samples = {}

---@type Vector3
local acceleration_samples = {}

local MAX_ALLOWED_SPEED = 2000 -- HU/sec
local MAX_ALLOWED_ACCELERATION = 5000 -- HU/sec²
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
		---@type Vector3[]
		acceleration_samples[index] = {}
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

				-- calculate acceleration from velocity samples
				local vel_samples = velocity_samples[index]
				if #vel_samples >= 2 then
					local prev_vel = vel_samples[#vel_samples - 1]
					local accel = (vel - prev_vel) / dt

					-- reject outlier accelerations
					if accel:Length() <= MAX_ALLOWED_ACCELERATION then
						acceleration_samples[index][#acceleration_samples[index] + 1] = accel
					end
				end
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

	if #acceleration_samples[index] > SAMPLE_COUNT - 2 then
		for i = 1, #acceleration_samples[index] - (SAMPLE_COUNT - 2) do
			table.remove(acceleration_samples[index], 1)
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

--- exponential smoothing for acceleration
---@param pEntity Entity
---@return Vector3
local function GetSmoothedAcceleration(pEntity)
	local samples = acceleration_samples[pEntity:GetIndex()]
	if not samples or #samples == 0 then
		return Vector3(0, 0, 0)
	end

	local grounded = IsPlayerOnGround(pEntity)
	local alpha = grounded and 0.4 or 0.3

	local smoothed = samples[1]
	for i = 2, #samples do
		smoothed = (samples[i] * alpha) + (smoothed * (1 - alpha))
	end

	-- apply deadzone to filter out noise
	local ACCEL_DEADZONE = 50.0 -- HU/sec²
	if smoothed:Length() < ACCEL_DEADZONE then
		smoothed = Vector3(0, 0, 0)
	end

	return smoothed
end

---@param pEntity Entity
---@return number
local function GetSmoothedAngularVelocity(pEntity)
	local samples = position_samples[pEntity:GetIndex()]
	if not samples or #samples < 4 then -- need more samples for better smoothing
		return 0
	end

	local function GetYaw(vec)
		return (vec.x == 0 and vec.y == 0) and 0 or math.deg(math.atan(vec.y, vec.x))
	end

	-- first pass: calculate raw angular velocities with movement threshold
	local ang_vels = {}
	local MIN_MOVEMENT = 1 -- ignore tiny movements that are likely noise

	for i = 1, #samples - 2 do
		local d1 = samples[i + 1].pos - samples[i].pos
		local d2 = samples[i + 2].pos - samples[i + 1].pos

		-- skip if movement is too small (likely noise)
		if d1:Length() < MIN_MOVEMENT or d2:Length() < MIN_MOVEMENT then
			goto continue
		end

		local yaw1 = GetYaw(d1)
		local yaw2 = GetYaw(d2)
		local diff = (yaw2 - yaw1 + 180) % 360 - 180

		-- filter out extreme jumps (likely noise)
		if math.abs(diff) < 120 then -- ignore impossible turns
			ang_vels[#ang_vels + 1] = diff
		end

		::continue::
	end

	if #ang_vels == 0 then
		return 0
	end

	-- second pass: apply median filter to remove outliers
	if #ang_vels >= 3 then
		local filtered_vels = {}
		for i = 1, #ang_vels do
			if i == 1 or i == #ang_vels then
				-- keep edge values
				filtered_vels[i] = ang_vels[i]
			else
				-- use median of 3 consecutive values
				local window = { ang_vels[i - 1], ang_vels[i], ang_vels[i + 1] }
				table.sort(window)
				filtered_vels[i] = window[2] -- median
			end
		end
		ang_vels = filtered_vels
	end

	-- third pass: exponential smoothing with adaptive alpha
	local grounded = IsPlayerOnGround(pEntity)
	local base_alpha = grounded and 0.4 or 0.2

	local smoothed = ang_vels[1]
	for i = 2, #ang_vels do
		-- adaptive alpha based on change magnitude
		local change = math.abs(ang_vels[i] - smoothed)
		local alpha = base_alpha * math.min(1, change / 45) -- reduce smoothing for large changes
		alpha = math.max(0.1, alpha) -- minimum smoothing

		smoothed = (ang_vels[i] * alpha) + (smoothed * (1 - alpha))
	end

	-- apply deadzone for very small movements
	local DEADZONE = 4.0
	if math.abs(smoothed) < DEADZONE then
		smoothed = 0
	end

	-- clamp to reasonable range
	local MAX_ANG_VEL = 45
	return math.max(-MAX_ANG_VEL, math.min(smoothed, MAX_ANG_VEL))
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

local function NormalizeVector(vec)
	local len = vec:Length()
	if len == 0 then
		return Vector3()
	end
	return vec / len
end

---@param stepSize number
---@param pTarget Entity The target
---@param time number The time in seconds we want to predict
function sim.Run(stepSize, pTarget, time)
	local smoothed_velocity = GetSmoothedVelocity(pTarget)
	local smoothed_acceleration = GetSmoothedAcceleration(pTarget)
	local angular_velocity = GetSmoothedAngularVelocity(pTarget)
	local last_pos = pTarget:GetAbsOrigin()

	local tick_interval = globals.TickInterval()
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

		-- rotate acceleration
		local ax, ay = smoothed_acceleration.x, smoothed_acceleration.y
		smoothed_acceleration.x = ax * cos_yaw - ay * sin_yaw
		smoothed_acceleration.y = ax * sin_yaw + ay * cos_yaw

		-- apply acceleration to velocity
		smoothed_velocity = smoothed_velocity + smoothed_acceleration * tick_interval

		smoothed_acceleration = smoothed_acceleration * (pTarget:GetPropFloat("m_flFriction") or 1.0)

		-- clamp velocity to target's max speed
		local target_max_speed = pTarget:GetPropFloat("m_flMaxspeed") or 450
		local vel_length = smoothed_velocity:Length()
		if vel_length > target_max_speed then
			smoothed_velocity = smoothed_velocity * (target_max_speed / vel_length)

			-- also reduce acceleration when at max speed to prevent unrealistic buildup
			local vel_direction = NormalizeVector(smoothed_velocity)
			local accel_in_vel_direction = smoothed_acceleration:Dot(vel_direction)
			if accel_in_vel_direction > 0 then
				-- remove acceleration component that would increase speed further
				smoothed_acceleration = smoothed_acceleration - vel_direction * accel_in_vel_direction
			end
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

			-- also adjust acceleration when hitting walls
			local accel_dot = smoothed_acceleration:Dot(normal)
			if accel_dot < 0 then -- only adjust if accelerating into the wall
				smoothed_acceleration = smoothed_acceleration - normal * accel_dot
			end
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
