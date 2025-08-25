local CMoveData = require("src.simulation.movedata")

local m_vecGroundNormal = nil
local m_vecOriginalVelocity = nil
local m_nLanding = nil

local MAX_IMPACT_PLANES = 5
local MOVEMENTSTACK_MAXSIZE = 9 --- 10 - 1 = 9, 9 elements as 0 is one as well

local SPEED_STOP_THRESHOLD = 1.0
local BUMP_MAX_COUNT = 8

---@enum MovementBlocked
local MovementBlocked = {
	MOVEMENT_BLOCKED_NONE  = 0x0,
	MOVEMENT_BLOCKED_WALL  = 0x1,
	MOVEMENT_BLOCKED_FLOOR = 0x2,
	MOVEMENT_BLOCKED_ALL   = 0x4
}

local SPEED_CROP_FRACTION_WALKING = 0.4
local SPEED_CROP_FRACTION_USING = 0.3
local SPEED_CROP_FRACTION_DUCKING = 0.3

---@class MovementStackData_t
---@field m_vecPosition Vector3?
---@field m_vecVelocity Vector3?
---@field m_vecImpactNormal Vector3?
local MovementStackData_t = {
    m_vecPosition = nil,
    m_vecVelocity = nil,
    m_vecImpactNormal = nil,
}

function MovementStackData_t.new()
    local data = setmetatable({}, {__index = MovementStackData_t})
    return data
end

local m_nMovementStackSize = 0

---@type MovementStackData_t[]
local m_aMovementStack = {}

local movement = {}

---@type CMoveData
local mv = nil -- = CMoveData.new()

---@type Entity
local player = nil

local function CheckStuck()
    if ((player:GetMoveType() == MOVETYPE_NOCLIP) or (player:GetMoveType() == MOVETYPE_NONE) or (player:GetMoveType() == MOVETYPE_ISOMETRIC)) then
        return false;
    end

    return false
end

local function SetupViewAngles()
    mv.m_vecViewAngles = player:GetAbsAngles()
end

local function HandleDuck()
    local buttonsChanged = mv.m_nOldButtons ~ mv.m_nButtons
    local buttonsPressed = buttonsChanged & mv.m_nButtons
    local buttonsReleased = buttonsChanged & mv.m_nOldButtons

    if (mv.m_nButtons & IN_DUCK) ~= 0 then
        mv.m_nOldButtons = mv.m_nOldButtons | IN_DUCK
    else
        mv.m_nOldButtons = mv.m_nOldButtons & ~IN_DUCK
    end

    if (not player:IsAlive() and player:GetPropInt("m_fFlags") & FL_DUCKING) then
        FinishUnDuck()
        return
    end

    if (mv.m_nButtons & IN_DUCK) ~= 0 or (player:GetPropBool("m_Local", "m_bDucking")) or (player:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0 then
        mv.m_flForwardMove = 0
        mv.m_flSideMove = 0
        mv.m_flUpMove = 0
    end
end

---@param pTarget Entity
function movement.Init(pTarget)
    player = pTarget
end

function movement.PrePlayerMove()
    if not player then
        return false
    end

    if (CheckStuck()) then
        return false
    end

    --- update movement timers
    --UpdateTimers()

    if player:IsAlive() then
        SetupViewAngles()
    end

    HandleDuck()

    HandleLadder()

    CategorizePosition()

    --- calculate the player's movement speed (has to happen after categorize position)
    SetupSpeed()

    return true
end

return movement