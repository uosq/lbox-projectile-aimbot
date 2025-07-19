---@meta

---@class PlayerInfo
---@field angle EulerAngles? The angle from positions
---@field fov number? The fov from the crosshair
---@field index integer? The player's index
---@field pos Vector3? The player's origin

---@class WeaponInfo
---@field vecOffset Vector3
---@field flForwardVelocity number
---@field flUpwardVelocity number
---@field vecCollisionMax Vector3
---@field flGravity number
---@field flDrag number

---@class PredictionResult
---@field vecPos Vector3
---@field nTime number
---@field nChargeTime number
---@field vecAimDir Vector3
---@field vecProjPath ProjSimPoint[]
---@field vecPlayerPath Vector3[]
