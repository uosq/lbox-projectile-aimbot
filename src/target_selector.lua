--[[
    Target selection module
]]

local mod = {}

--- relative to Maxs().z
local z_offsets = { 0.2, 0.4, 0.5, 0.7, 0.9 }

---@param entityData table
---@param settings table
local function ShouldSkipPlayer(entityData, settings)
	local cond = entityData.m_nCond
	local condEx = entityData.m_nCondEx
	local condEx2 = entityData.m_nCondEx2
	local condition_bits = entityData.m_nConditionBits

	-- cloak/disguise/taunt/bonk
	if
		settings.ignore_conds.cloaked
		and ((cond & E_TFCOND.TFCond_Cloaked) ~= 0 or (condition_bits & (1 << cond)) ~= 0)
	then
		return true
	end
	if
		settings.ignore_conds.disguised
		and ((cond & E_TFCOND.TFCond_Disguised) ~= 0 or (condition_bits & (1 << cond)) ~= 0)
	then
		return true
	end
	if
		settings.ignore_conds.taunting
		and ((cond & E_TFCOND.TFCond_Taunting) ~= 0 or (condition_bits & (1 << cond)) ~= 0)
	then
		return true
	end
	if
		settings.ignore_conds.bonked and ((cond & E_TFCOND.TFCond_Bonked) ~= 0 or (condition_bits & (1 << cond)) ~= 0)
	then
		return true
	end

	-- uber / crit
	if
		settings.ignore_conds.ubercharged
		and ((cond & E_TFCOND.TFCond_Ubercharged) ~= 0 or condition_bits & (1 << cond) ~= 0)
	then
		return true
	end
	if
		settings.ignore_conds.kritzkrieged
		and ((cond & E_TFCOND.TFCond_Kritzkrieged) ~= 0 or condition_bits & (1 << cond) ~= 0)
	then
		return true
	end

	-- debuffs
	if
		settings.ignore_conds.jarated and ((cond & E_TFCOND.TFCond_Jarated) ~= 0 or condition_bits & (1 << cond) ~= 0)
	then
		return true
	end
	if settings.ignore_conds.milked and ((cond & E_TFCOND.TFCond_Milked) ~= 0 or condition_bits & (1 << cond) ~= 0) then
		return true
	end

	-- misc
	if settings.ignore_conds.ghost and (condEx2 & (1 << (E_TFCOND.TFCond_HalloweenGhostMode - 64))) ~= 0 then
		return true
	end

	-- friends / priority
	if entityData.priority < 0 and not settings.ignore_conds.friends then
		return true
	end
	if settings.min_priority > entityData.priority then
		return true
	end

	local VACCINATOR_MASK = E_TFCOND.TFCond_UberBulletResist
		| E_TFCOND.TFCond_UberBlastResist
		| E_TFCOND.TFCond_UberFireResist
		| E_TFCOND.TFCond_SmallBulletResist
		| E_TFCOND.TFCond_SmallBlastResist
		| E_TFCOND.TFCond_SmallFireResist

	-- vaccinator resistances (single mask)
	if settings.ignore_conds.vaccinator and (condEx & (1 << (VACCINATOR_MASK - 32))) ~= 0 then
		return true
	end

	return false
end

---@param pLocal Entity
---@param vHeadPos Vector3
---@param math_utils MathLib
---@param entitylist table<integer, ENTRY>
---@param settings table
---@param bAimAtTeamMates boolean
---@return Entity?, number?, integer?
function mod.Run(pLocal, vHeadPos, math_utils, entitylist, settings, bAimAtTeamMates)
	local bestFov = settings.fov
	local selected_entity = nil
	local nOffset = nil
	local trace
	local selected_index = nil

	local close_distance = (settings.close_distance * 0.01) * settings.max_distance

	for idx, entityInfo in ipairs(entitylist) do
		if not ShouldSkipPlayer(entityInfo, settings) then
			local vDistance = (vHeadPos - entityInfo.m_vecPos):Length()
			if vDistance <= settings.max_distance then
				for i = 1, #z_offsets do
					local offset = z_offsets[i]
					local zOffset = entityInfo.m_vecMaxs.z * offset
					local pos = entityInfo.m_vecPos
					local origin = Vector3(pos.x, pos.y, pos.z + zOffset)

					if (vHeadPos - origin):Length() <= close_distance then
						local angle = math_utils.PositionAngles(vHeadPos, origin)
						local fov = math_utils.AngleFov(angle, engine.GetViewAngles())
						if fov <= bestFov then
							bestFov = fov
							selected_entity = entityInfo.m_iIndex
							nOffset = zOffset
							selected_index = idx
						end
					else
						trace = engine.TraceLine(
							vHeadPos,
							origin,
							MASK_SHOT_HULL,
							function(ent, contentsMask) --ignore entities
								return false
							end
						)

						if trace and trace.fraction == 1 then
							local angle = math_utils.PositionAngles(vHeadPos, origin)
							local fov = math_utils.AngleFov(angle, engine.GetViewAngles())
							if fov <= bestFov then
								bestFov = fov
								selected_entity = entityInfo.m_iIndex
								nOffset = zOffset
								selected_index = idx
							end
						end
					end
				end
			end
		end
	end

	if selected_entity == nil then
		return nil, nil
	end

	return entities.GetByIndex(selected_entity), nOffset, selected_index
end

return mod
