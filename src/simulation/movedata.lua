---@class CMoveData
---@field m_bFirstRunOfFunctions boolean
---@field m_bGameCodeMovedPlayer boolean
---@field m_nPlayerHandle Entity?
---@field m_nImpulseCommand number
---@field m_vecViewAngles EulerAngles
---@field m_vecAbsViewAngles EulerAngles
---@field m_nButtons number
---@field m_nOldButtons number
---@field m_flForwardMove number
---@field m_flOldForwardMove number
---@field m_flSideMove number
---@field m_flUpMove number
---@field m_flMaxSpeed number
---@field m_flClientMaxSpeed number
---@field m_vecVelocity Vector3
---@field m_vecAngles EulerAngles
---@field m_vecOldAngles EulerAngles
---@field m_outStepHeight number
---@field m_outWishVel Vector3
---@field m_outJumpVel Vector3
---@field m_vecConstraintCenter Vector3
---@field m_flConstraintRadius number
---@field m_flConstraintWidth number
---@field m_flConstraintSpeedFactor number
---@field m_vecAbsOrigin Vector3
local movedata = {
    m_bFirstRunOfFunctions = false,
    m_bGameCodeMovedPlayer = false,
    m_nPlayerHandle = nil,
    m_nImpulseCommand = 0, --- is the impulse command the one like "impulse 101" to restore health & ammo?
    m_vecViewAngles = EulerAngles(),	-- view angles (local space)
    m_vecAbsViewAngles = EulerAngles(),	-- view angles (world space)
    m_nButtons = 0,
    m_nOldButtons = 0,
    m_flForwardMove = 0,
    m_flOldForwardMove = 0,
    m_flSideMove = 0,
    m_flUpMove = 0,
    m_flMaxSpeed = 0,
    m_flClientMaxSpeed = 0,
	m_vecVelocity = Vector3(),
	m_vecAngles = EulerAngles(),
	m_vecOldAngles = EulerAngles(),

    -- Output only
	m_outStepHeight = 0, --- how much you climbed this move
	m_outWishVel = Vector3(), --- This is where you tried 
	m_outJumpVel = Vector3(), --- This is your jump velocity

    -- Movement constraints	(radius 0 means no constraint)
	m_vecConstraintCenter = Vector3(),
	m_flConstraintRadius = 0,
	m_flConstraintWidth = 0,
	m_flConstraintSpeedFactor = 0,
	m_vecAbsOrigin = Vector3(),
}

---@return CMoveData
function movedata.new(data)
    local obj = setmetatable(data or {}, {__index = movedata})
    return obj
end

return movedata