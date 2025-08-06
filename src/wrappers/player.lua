---@class Player
---@field private m_hEntity Entity?
local player = {}

function player.New(entity)
    local plr = setmetatable({}, {__index = player})
    plr.m_hEntity = entity
    return plr
end

---@return Entity?
function player:GetHandle()
    return self.m_hEntity
end

---@return integer
function player:GetIndex()
    return self.m_hEntity:GetIndex()
end

---@return Vector3
function player:GetAbsOrigin()
    return self.m_hEntity:GetAbsOrigin()
end

---@return Vector3
function player:GetNetworkOrigin()
    return self.m_hEntity:GetPropVector("tfnonlocaldata", "m_vecOrigin")
end

return player