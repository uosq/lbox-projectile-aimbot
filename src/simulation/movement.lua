---@class CGameMovement
---@field m_vecVelocity Vector3?
---@field m_vecPos Vector3?
---@field m_hTarget Entity?
---@field m_vecGroundNormal Vector3?
---@field m_iWaterLevel integer?
---@field m_flFallVelocity number?
---@field m_iSpeedCropped integer?
---@field m_flMaxspeed number?
local GameMovement = {
    m_vecVelocity = nil,
    m_vecPos = nil,
    m_hTarget = nil,
    m_vecGroundNormal = nil,
    m_iWaterLevel = nil,
    m_flFallVelocity = nil,
    m_iSpeedCropped = nil,
    m_flMaxspeed = nil
};

--- i think not even NASA uses a pi this big wtf
local M_PI = 3.14159265358979323846;

--- is this a angle?
local IMPACT_NORMAL_FLOOR = 0.7;
local IMPACT_NORMAL_WALL = 0.0;

local EMovement = {
	MOVEMENT_BLOCKED_NONE  = 0x0,
	MOVEMENT_BLOCKED_WALL  = 0x1,
	MOVEMENT_BLOCKED_FLOOR = 0x2,
	MOVEMENT_BLOCKED_ALL   = 0x4
};

local EWaterLevel = {
	WL_NotInWater = 0,
	WL_Feet = 1,
	WL_Waist = 2,
	WL_Eyes = 3
};

local ESpeedCrop = {
	SPEED_CROPPED_RESET = 0,
	SPEED_CROPPED_DUCK = 1,
	SPEED_CROPPED_WEAPON = 2,
};

local SPEED_CROP_FRACTION_DUCKING = 0.3;

local up_vec = Vector3(0, 0, 1);

---@param pEntity Entity
local function GetViewOffset(pEntity)
    return pEntity:GetPropVector("m_vecViewOffset[0]");
end

function GameMovement:CheckWater()
    local point;
    local cont;
    local iWaterLevel = 0;

    local vPlayerMins = self.m_hTarget:GetMins();
    local vPlayerMaxs = self.m_hTarget:GetMaxs();
    local vTargetOrigin = self.m_hTarget:GetAbsOrigin()

    point = Vector3()
    point.x = vTargetOrigin.x + (vPlayerMins.x + vPlayerMaxs.x) * 0.5;
    point.y = vTargetOrigin.y + (vPlayerMins.y + vPlayerMaxs.y) * 0.5;
    point.z = vTargetOrigin.z + vPlayerMins.z + 1

    iWaterLevel = EWaterLevel.WL_NotInWater;

    cont = engine.GetPointContents(point, 0);

    if (cont & MASK_WATER) ~= 0 then
        iWaterLevel = EWaterLevel.WL_Feet;

        point.z = vTargetOrigin.z + (vPlayerMins.z + vPlayerMaxs.z) * 0.5;
        cont = engine.GetPointContents(point, 1);

        if (cont & MASK_WATER) ~= 0 then
            iWaterLevel = EWaterLevel.WL_Waist;

            point.z = vTargetOrigin.z + GetViewOffset(self.m_hTarget).z;
            cont = engine.GetPointContents(point, 2);
            if (cont & MASK_WATER) ~= 0 then
                iWaterLevel = EWaterLevel.WL_Eyes;
            end
        end
    end

    self.m_iWaterLevel = iWaterLevel;
    return iWaterLevel > EWaterLevel.WL_Feet;
end

---@param ent Entity
---@param contents integer
---@return boolean
local function COLLISION_GROUP_PLAYER_MOVEMENT(ent, contents)
    if ent:IsPlayer() then
        return false
    end

    if ent:IsPlayer() then
        return false
    end

    return true
end

function GameMovement:TracePlayerBBox(vStart, vEnd, iMask)
    local vPlayerMins, vPlayerMaxs;
    vPlayerMins = self.m_hTarget:GetMins();
    vPlayerMaxs = self.m_hTarget:GetMaxs();

    return engine.TraceHull(vStart, vEnd, vPlayerMins, vPlayerMaxs, iMask, COLLISION_GROUP_PLAYER_MOVEMENT);
end

function GameMovement:CategorizePosition()
    self:CheckWater();

    local trace;
    local vTargetOrigin = self.m_vecPos;
    local vStart = vTargetOrigin;
    local vEnd = vTargetOrigin + Vector3(0, 0, -66);

    if self.m_vecVelocity.z <= 180.0 then
        trace = self:TracePlayerBBox(vStart, vEnd, MASK_PLAYERSOLID);
        local normal = trace.plane:Dot(up_vec);
        if normal >= IMPACT_NORMAL_FLOOR and trace.fraction < 0.06 then
            self.m_vecGroundNormal = trace.plane;
            if self.m_iWaterLevel < EWaterLevel.WL_Waist and not trace.startsolid and not trace.allsolid then
                self.m_vecPos = vStart + trace.fraction * (vEnd - vStart);
            end
        end
    end

    if not trace then
        self.m_flFallVelocity = -self.m_vecVelocity.z;
    end
end

---@param val number
---@param min number
---@param max number
local function clamp(val, min, max)
	return math.max(min, math.min(val, max))
end

function GameMovement:SpeedCrop()
    if (self.m_iSpeedCropped & ESpeedCrop.SPEED_CROPPED_DUCK) ~= 0 then
        return;
    end

    self.m_iSpeedCropped = self.m_iSpeedCropped | ESpeedCrop.SPEED_CROPPED_DUCK;

    if (self.m_hTarget:GetPropInt("m_fFlags") & IN_DUCK) ~= 0 then
        self.m_vecVelocity = self.m_vecVelocity * SPEED_CROP_FRACTION_DUCKING;
    end

    local flAngle = math.atan(self.m_vecVelocity:Right():Length(), self.m_vecVelocity:Length()) / M_PI;
    flAngle = 2.0 * (math.abs(flAngle) - 0.5);
    flAngle = clamp(flAngle, 0.0, 1.0);
    local _, sv_backspeed = client.GetConVar("sv_backspeed");
    local flFactor = 1.0 - math.abs(flAngle) * (1.0 - sv_backspeed);

    self.m_vecVelocity.x = self.m_vecVelocity.x * flFactor;
    self.m_vecVelocity.y = self.m_vecVelocity.y * flFactor;
end

function GameMovement:SetupSpeed()
    if self.m_hTarget:GetMoveType() == E_MoveType.MOVETYPE_ISOMETRIC
    or self.m_hTarget:GetMoveType() == E_MoveType.MOVETYPE_NOCLIP then
        return;
    end

    if (self.m_hTarget:GetPropInt("m_fFlags") & FL_FROZEN) ~= 0
    or (self.m_hTarget:GetPropInt("m_fFlags") & FL_ONTRAIN) ~= 0 then
        self.m_vecVelocity.x = 0;
        self.m_vecVelocity.y = 0;
        self.m_vecVelocity.z = 0;
        return;
    end

    local flSpeed = self.m_vecVelocity:Length();
    if flSpeed == 0 then
        return;
    end

    flSpeed = math.sqrt(flSpeed);

    local flSpeedFactor = 1.0;

    --[[
        Skipping surface data and constraint
        Because we dont have a way to get the data :(
    ]]

    self:SpeedCrop();
end

--- why is this so big?!!?!?!?
function GameMovement:CheckStuck()
    local base;
    local offset;
    local test;
    local hitent;
    local idx;
    local fTime;
    local trace;


end

return GameMovement
