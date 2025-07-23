---@diagnostic disable: duplicate-doc-field, missing-fields
local sim = {}

---@class KalmanFilter
---@field state Vector3 -- current velocity estimate
---@field acceleration Vector3 -- current acceleration estimate
---@field P_velocity number -- velocity estimation error covariance
---@field P_acceleration number -- acceleration estimation error covariance
---@field P_cross number -- cross-covariance between velocity and acceleration
---@field Q_velocity number -- process noise for velocity
---@field Q_acceleration number -- process noise for acceleration
---@field R number -- measurement noise
---@field last_time number -- last update time
local KalmanFilter = {}
KalmanFilter.__index = KalmanFilter

function KalmanFilter:new()
	return setmetatable({
		state = Vector3(0, 0, 0),
		acceleration = Vector3(0, 0, 0),
		P_velocity = 1000.0, -- high initial uncertainty
		P_acceleration = 100.0,
		P_cross = 0.0,
		Q_velocity = 25.0, -- velocity process noise
		Q_acceleration = 50.0, -- acceleration process noise
		R = 100.0, -- measurement noise (depends on tick rate/lag)
		last_time = 0,
	}, self)
end

---@class Sample
---@field pos Vector3
---@field time number

---@type Sample[]
local position_samples = {}

---@type table<number, KalmanFilter>
local kalman_filters = {}

local DoTraceHull = engine.TraceHull
local Vector3 = Vector3

---@param measured_velocity Vector3
---@param current_time number
---@param is_grounded boolean
function KalmanFilter:update(measured_velocity, current_time, is_grounded)
	local dt = current_time - self.last_time
	if dt <= 0 then
		return
	end

	-- Adjust noise based on player state
	local Q_vel = is_grounded and self.Q_velocity * 0.5 or self.Q_velocity
	local Q_acc = is_grounded and self.Q_acceleration * 0.3 or self.Q_acceleration
	local R = is_grounded and self.R * 0.7 or self.R * 1.5 -- more noise when airborne

	-- now we cook the prediction
	-- velocity = velocity + acceleration * dt
	local predicted_velocity = self.state + self.acceleration * dt

	-- update covariance matrix for prediction
	local dt2 = dt * dt

	-- Predicted covariances
	local P_vel_pred = self.P_velocity + 2 * self.P_cross * dt + self.P_acceleration * dt2 + Q_vel * dt2
	local P_acc_pred = self.P_acceleration + Q_acc * dt
	local P_cross_pred = self.P_cross + self.P_acceleration * dt

	-- update step (for each direction axis separately for better numerical stability)
	for axis = 1, 3 do
		local measured = axis == 1 and measured_velocity.x or axis == 2 and measured_velocity.y or measured_velocity.z
		local predicted = axis == 1 and predicted_velocity.x
			or axis == 2 and predicted_velocity.y
			or predicted_velocity.z
		local current_acc = axis == 1 and self.acceleration.x
			or axis == 2 and self.acceleration.y
			or self.acceleration.z

		-- innovation (measurement residual)
		local innovation = measured - predicted

		-- innovation covariance
		local S = P_vel_pred + R

		-- Kalman gains
		local K_velocity = P_vel_pred / S
		local K_acceleration = P_cross_pred / S

		-- update state estimates
		local new_vel = predicted + K_velocity * innovation
		local new_acc = current_acc + K_acceleration * innovation

		if axis == 1 then
			predicted_velocity.x = new_vel
			self.acceleration.x = new_acc
		elseif axis == 2 then
			predicted_velocity.y = new_vel
			self.acceleration.y = new_acc
		else
			predicted_velocity.z = new_vel
			self.acceleration.z = new_acc
		end
	end

	-- update covariances
	local K_vel_avg = P_vel_pred / (P_vel_pred + R) -- approximate average gain
	local K_acc_avg = P_cross_pred / (P_vel_pred + R)

	self.P_velocity = (1 - K_vel_avg) * P_vel_pred
	self.P_acceleration = P_acc_pred - K_acc_avg * P_cross_pred
	self.P_cross = (1 - K_vel_avg) * P_cross_pred

	-- constrain covariances to prevent numerical issues
	self.P_velocity = math.max(1.0, math.min(self.P_velocity, 10000.0))
	self.P_acceleration = math.max(0.1, math.min(self.P_acceleration, 1000.0)) --- im not sure how fast can the players go so im giving it a generous amount ig
	self.P_cross = math.max(-100.0, math.min(self.P_cross, 100.0))

	self.state = predicted_velocity
	self.last_time = current_time
end

---@param dt number time step for prediction
---@return Vector3 predicted_velocity
---@return Vector3 predicted_acceleration
---@return number confidence (0-1, higher is more confident)
function KalmanFilter:predict(dt)
	local predicted_velocity = self.state + self.acceleration * dt
	local predicted_acceleration = self.acceleration -- assume constant acceleration?

	-- calculate confidence based on covariance
	local total_uncertainty = self.P_velocity + self.P_acceleration * dt * dt
	local confidence = math.max(0, math.min(1, 1 - (total_uncertainty / 1000)))

	return predicted_velocity, predicted_acceleration, confidence
end

---@return number current uncertainty in velocity estimation
function KalmanFilter:getUncertainty()
	return math.sqrt(self.P_velocity)
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

	local trace = DoTraceHull(trace_start, trace_end, Vector3(0, 0, 0), Vector3(0, 0, 0), MASK_SHOT_HULL, shouldHit)

	if trace and trace.fraction < 1 then
		-- check if it's a walkable surface
		local surface_normal = trace.plane
		local ground_angle = math.deg(math.acos(surface_normal:Dot(Vector3(0, 0, 1))))

		if ground_angle <= 45 then
			-- check if we can actually step on this surface
			local hit_point = trace_start + (trace_end - trace_start) * trace.fraction
			local step_test_start = hit_point + Vector3(0, 0, step_height)
			local step_test_end = position

			local step_trace = DoTraceHull(step_test_start, step_test_end, mins, maxs, MASK_SHOT_HULL, shouldHit)

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

---@param pEntity Entity
local function AddPositionSample(pEntity)
	local index = pEntity:GetIndex()

	if not position_samples[index] then
		position_samples[index] = {}
		kalman_filters[index] = KalmanFilter:new()
	end

	local current_time = globals.CurTime()
	local current_pos = pEntity:GetAbsOrigin()
	local is_grounded = IsPlayerOnGround(pEntity)

	local sample = { pos = current_pos, time = current_time }
	local samples = position_samples[index]
	samples[#samples + 1] = sample

	-- get raw velocity from position samples
	local raw_velocity = Vector3(0, 0, 0)
	if #samples >= 2 then
		local prev = samples[#samples - 1]
		local dt = current_time - prev.time
		if dt > 0 then
			raw_velocity = (current_pos - prev.pos) / dt
		end
	end

	-- update Kalman filter with raw velocity
	kalman_filters[index]:update(raw_velocity, current_time, is_grounded)

	-- trim old samples
	local MAX_SAMPLES = 8 -- less needed with brcause of the Kalman filtering
	if #samples > MAX_SAMPLES then
		for i = 1, #samples - MAX_SAMPLES do
			table.remove(samples, 1)
		end
	end
end

---@param pEntity Entity
---@return Vector3
local function GetSmoothedVelocity(pEntity)
	local filter = kalman_filters[pEntity:GetIndex()]
	if not filter then
		return pEntity:EstimateAbsVelocity()
	end

	local predicted_vel, _, _ = filter:predict(0) -- current estimate
	return predicted_vel
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
	local base_alpha = grounded and 1 or 0.2
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

	local function shouldHitEntity(ent)
		if ent:GetIndex() == client.GetLocalPlayerIndex() then
			return false
		end
		return ent:GetTeamNumber() ~= pTarget:GetTeamNumber()
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

		local trace = DoTraceHull(last_pos, next_pos, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

		if trace.fraction < 1.0 then
			if smoothed_velocity.z >= -50 then
				local step_up = last_pos + Vector3(0, 0, stepSize)
				local step_up_trace = DoTraceHull(last_pos, step_up, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

				if step_up_trace.fraction >= 1.0 then
					local step_forward = step_up + move_delta
					local step_forward_trace =
						DoTraceHull(step_up, step_forward, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

					if step_forward_trace.fraction > 0 then
						local step_down_start = step_forward_trace.endpos
						local step_down_end = step_down_start + Vector3(0, 0, -stepSize)
						local step_down_trace =
							DoTraceHull(step_down_start, step_down_end, mins, maxs, MASK_PLAYERSOLID, shouldHitEntity)

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
			last_pos = next_pos
			positions[#positions + 1] = last_pos
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
