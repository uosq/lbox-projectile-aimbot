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
    m_flMaxspeed = nil,
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

    point = Vector3()
    point.x = self.m_vecPos.x + (vPlayerMins.x + vPlayerMaxs.x) * 0.5;
    point.y = self.m_vecPos.y + (vPlayerMins.y + vPlayerMaxs.y) * 0.5;
    point.z = self.m_vecPos.z + vPlayerMins.z + 1

    iWaterLevel = EWaterLevel.WL_NotInWater;

    cont = engine.GetPointContents(point, 0);

    if (cont & MASK_WATER) ~= 0 then
        iWaterLevel = EWaterLevel.WL_Feet;

        point.z = self.m_vecPos.z + (vPlayerMins.z + vPlayerMaxs.z) * 0.5;
        cont = engine.GetPointContents(point, 1);

        if (cont & MASK_WATER) ~= 0 then
            iWaterLevel = EWaterLevel.WL_Waist;

            point.z = self.m_vecPos.z + GetViewOffset(self.m_hTarget).z;
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

    --[[ does nothing
    local flSpeed = self.m_vecVelocity:Length();
    if flSpeed == 0 then
        return;
    end

    flSpeed = math.sqrt(flSpeed);
    ]]

    --[[
        Skipping surface data and constraint
        Because we dont have a way to get the data :(
    ]]

    self:SpeedCrop();
end

--- wtf is this?
function GameMovement:TestPlayerPosition(pos)
    local trace;
    local vMins, vMaxs = self.m_hTarget:GetMins(), self.m_hTarget:GetMaxs();
    trace = engine.TraceHull(pos, pos, vMins, vMaxs, MASK_PLAYERSOLID, function(ent)
        if ent:IsPlayer() and ent:GetIndex() == self.m_hTarget:GetIndex() then
            return false;
        end

        return true;
    end);

    return trace.entity;
end

--- why is this so big?!!?!?!?
function GameMovement:CheckStuck()
    --[[local base;
    local offset;
    local test;]]
    local hitent;
    --[[local idx;
    local fTime;
    local trace;]]

    hitent = self:TestPlayerPosition(self.m_vecPos);
    if hitent == nil then
        return false;
    end

    --- there is a bunch of shit here
    --- but honestly idk wtf they are doing

    return true;
end

--- i simplified it a bit
--- as they are only clamping them
function GameMovement:CheckVelocity()
    local _, sv_maxvelocity = client.GetConVar("sv_maxvelocity");
    self.m_vecVelocity.x = clamp(self.m_vecVelocity.x, -sv_maxvelocity, sv_maxvelocity);
    self.m_vecVelocity.y = clamp(self.m_vecVelocity.y, -sv_maxvelocity, sv_maxvelocity);
    self.m_vecVelocity.z = clamp(self.m_vecVelocity.z, -sv_maxvelocity, sv_maxvelocity);
end

function GameMovement:StartGravity()
    --local ent_gravity = 1.0;
    local _, sv_gravity = client.GetConVar("sv_gravity");
    self.m_vecVelocity.z = self.m_vecVelocity.z - (sv_gravity * 0.5 * globals.TickInterval());
    self.m_vecVelocity.z = self.m_vecVelocity.z + self.m_vecVelocity.z * globals.TickInterval();
    self:CheckVelocity();
end

function GameMovement:Friction()
    -- skip if water jump time is active (not implemented, so skip check)

    local speed = self.m_vecVelocity:Length()
    if speed < 0.1 then
        return
    end

    local drop = 0

    local groundEntity = self.m_hTarget:GetPropEntity("movetype") ~= E_MoveType.MOVETYPE_NONE
        and self.m_hTarget:GetPropEntity("m_hGroundEntity")

    if groundEntity then
        local _, sv_friction = client.GetConVar("sv_friction")
        local surfaceFriction = self.m_hTarget:GetPropFloat("m_flFriction") or 1.0
        local friction = sv_friction * surfaceFriction

        local _, sv_stopspeed = client.GetConVar("sv_stopspeed")
        local control = (speed < sv_stopspeed) and sv_stopspeed or speed

        local frameTime = globals.FrameTime()
        drop = drop + control * friction * frameTime
    end

    local newspeed = speed - drop
    if newspeed < 0 then
        newspeed = 0
    end

    if newspeed ~= speed then
        local scale = newspeed / speed
        self.m_vecVelocity = self.m_vecVelocity * scale

        if self.m_outWishVel then
            self.m_outWishVel = self.m_outWishVel - ((1.0 - scale) * self.m_vecVelocity)
        end
    end
end

local function CheckGround(vPos, vMins, vMaxs, step_height)
    local trace;
    trace = engine.TraceHull(vPos, vPos - step_height, vMins, vMaxs, MASK_PLAYERSOLID, function (ent, contentsMask)
        if ent:IsPlayer() then
            return false;
        end

        return true;
    end)

    return trace and trace.fraction < 1;
end

function CalcWishVelocityAndPosition(vWishPos, vWishDir, flWishSpeed)
    
end

function GameMovement:WalkMove2()

end

function GameMovement:AirMove()
end

function GameMovement:FullWalkMove()
    if not self:CheckWater() then
        self:StartGravity();
    end

    if self.m_iWaterLevel >= EWaterLevel.WL_Waist then
        --- WaterMove();
    else
        local vMins, vMaxs;
        vMins = self.m_hTarget:GetMins();
        vMaxs = self.m_hTarget:GetMaxs();
        local bGround = CheckGround(self.m_vecPos, vMins, vMaxs, self.m_hTarget:GetPropFloat("m_flStepSize"))

        if bGround then
            self:Friction();
        end

        self:CheckVelocity();

        if bGround then
            self:WalkMove2();
        else
            self:AirMove();
        end
    end
end

function GameMovement:HandlePlayerMove()
    local moveType = self.m_hTarget:GetMoveType();

    --- very good ik
    if moveType == E_MoveType.MOVETYPE_NONE then
        return;
    elseif moveType == E_MoveType.MOVETYPE_WALK then
        self:FullWalkMove();
    end
end

return GameMovement
