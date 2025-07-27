--- i dont have enough motivation or time to continue this

---@diagnostic disable: cast-local-type

--- just so i dont have any confusion
---@class FakeUserCmd: UserCmd

---@class MoveData
---@field uCmd FakeUserCmd?
---@field m_hEntity Entity?
---@field m_flMaxspeed number?
---@field flConstraintSpeedFactor number?

---@class Movement
---@field m_MoveData table<integer, MoveData>
---@field current_MoveData MoveData?
local movement = {
	m_MoveData = {},
	current_MoveData = nil,
}

function movement:ComputeConstraintSpeedFactor() end

function movement:DecayPunchAngle()
	local player = self.current_MoveData.m_hEntity
	if not player then
		return
	end

	local m_vecPunchAngle = player:GetPropVector("m_Local", "m_vecPunchAngle")
	local m_vecPunchAngleVel = player:GetPropVector("m_Local", "m_vecPunchAngleVel")

	if (m_vecPunchAngle:LengthSqr() > 0.001) or (m_vecPunchAngleVel:LengthSqr() > 0.001) then
		--m_vecPunchAngle
	end
end

function movement:CheckParameters()
	local player = self.current_MoveData.m_hEntity
	if not player then
		return
	end

	local usercmd = self.CopyUserCmd(self.current_MoveData.uCmd)
	local mv = self.current_MoveData
	if not mv then
		return
	end

	local movetype = player:GetMoveType()

	if
		movetype ~= E_MoveType.MOVETYPE_ISOMETRIC
		and movetype ~= E_MoveType.MOVETYPE_NOCLIP
		and movetype ~= E_MoveType.MOVETYPE_OBSERVER
	then
		local spd
		local maxspeed

		spd = usercmd.forwardmove ^ 2 + usercmd.sidemove ^ 2 + usercmd.upmove ^ 2
		maxspeed = player:GetPropFloat("m_flMaxspeed")

		if maxspeed ~= 0.0 then
			mv.m_flMaxspeed = math.max(maxspeed, mv.m_flMaxspeed or 0)
		end

		local flSpeedFactor = 1.0
		local flConstraintSpeedFactor = mv.flConstraintSpeedFactor
		if self:ComputeConstraintSpeedFactor() < flSpeedFactor then
			flSpeedFactor = flConstraintSpeedFactor
		end

		mv.m_flMaxspeed = mv.m_flMaxspeed * flSpeedFactor

		if spd ~= 0.0 and spd > mv.m_flMaxspeed ^ 2 then
			local ratio = mv.m_flMaxspeed / math.sqrt(spd)
			mv.uCmd.forwardmove = mv.uCmd.forwardmove * ratio
			mv.uCmd.sidemove = mv.uCmd.sidemove * ratio
			mv.uCmd.upmove = mv.uCmd.upmove * ratio
		end

		local flags = player:GetPropInt("m_fFlags")
		if (flags & FL_FROZEN) ~= 0 or (flags & FL_ONTRAIN) or not player:IsAlive() then
			mv.uCmd.forwardmove = 0
			mv.uCmd.sidemove = 0
			mv.uCmd.upmove = 0
		end

		--self:DecayPunchAngle() fucking useless for us
	end
end

---@param uCmd UserCmd
---@return FakeUserCmd
function movement.CopyUserCmd(uCmd)
	local temp = {}

	temp.forwardmove = uCmd.forwardmove
	temp.tick_count = uCmd.tick_count
	temp.buttons = uCmd.buttons
	temp.command_number = uCmd.command_number
	temp.hasbeenpredicted = uCmd.hasbeenpredicted
	temp.impulse = uCmd.impulse
	temp.mousedx = uCmd.mousedx
	temp.mousedy = uCmd.mousedy
	temp.random_seed = uCmd.random_seed
	temp.sendpacket = uCmd.sendpacket
	temp.sidemove = uCmd.sidemove
	temp.upmove = uCmd.upmove
	temp.viewangles = uCmd.viewangles
	temp.weaponselect = uCmd.weaponselect
	temp.weaponsubtype = uCmd.weaponsubtype

	return temp
end

function movement:PlayerMove()
	self:CheckParameters()
end

---@param pEntity Entity
---@param MoveData MoveData
---@param uCmd UserCmd
function movement:ProcessMovement(pEntity, MoveData, uCmd)
	if not self.m_MoveData[pEntity:GetIndex()] then
		self.m_MoveData[pEntity:GetIndex()] = {}
		self.m_MoveData[pEntity:GetIndex()][#self.m_MoveData[pEntity:GetIndex()] + 1] = MoveData
	end

	self.current_MoveData = self.m_MoveData[pEntity:GetIndex()][#self.m_MoveData[pEntity:GetIndex()]]
	self.m_hEntity = pEntity
	self.uCmd = self.CopyUserCmd(uCmd)

	self:PlayerMove()
end

return movement
