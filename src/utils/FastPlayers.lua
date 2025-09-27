-- fastplayers.lua ─────────────────────────────────────────────────────────
-- Simple helpers for retrieving valid player entities each tick.

--[[ Module Declaration ]]
local FastPlayers = {}

--[[ Local Cache ]]
local cachedAllPlayers
local cachedLocal

--[[ Internal helpers ]]
local function isValidPlayer(player)
	if not player or not player:IsValid() then
		return false
	end

	if player:IsDormant() then
		return false
	end

	return player:IsAlive()
end

local function ResetCaches()
	cachedAllPlayers = nil
	cachedLocal = nil
end

local function buildPlayerCache()
	cachedAllPlayers = {}
	local players = entities.FindByClass("CTFPlayer") or {}

	for i = 1, #players do
		local player = players[i]
		if isValidPlayer(player) then
			cachedAllPlayers[#cachedAllPlayers + 1] = player
		end
	end
end

--[[ Public API ]]

--- Returns the local player entity if it is currently valid.
function FastPlayers.GetLocal()
	if cachedLocal ~= nil and isValidPlayer(cachedLocal) then
		return cachedLocal
	end

	local localPlayer = entities.GetLocalPlayer()
	if not isValidPlayer(localPlayer) then
		cachedLocal = nil
		return nil
	end

	cachedLocal = localPlayer
	return cachedLocal
end

--- Returns a cached list of valid player entities for the current tick.
---@param excludeLocal boolean? set true to skip the local player
function FastPlayers.GetAll(excludeLocal)
	if cachedAllPlayers == nil then
		buildPlayerCache()
	end

	if not excludeLocal then
		return cachedAllPlayers
	end

	local skip = FastPlayers.GetLocal()
	if skip == nil then
		return cachedAllPlayers
	end

	local filtered = {}
	for _, player in ipairs(cachedAllPlayers) do
		if player ~= skip then
			filtered[#filtered + 1] = player
		end
	end

	return filtered
end

--- Allows manual cache reset if needed by external modules.
function FastPlayers.Reset()
	ResetCaches()
end

callbacks.Unregister("CreateMove", "FastPlayers_ResetCaches")
callbacks.Unregister("FireGameEvent", "FastPlayers_PlayerEvents")

callbacks.Register("CreateMove", "FastPlayers_ResetCaches", ResetCaches)
callbacks.Register("FireGameEvent", "FastPlayers_PlayerEvents", function(event)
	local name = event:GetName()
	if
		name == "player_disconnect"
		or name == "player_connect"
		or name == "player_changeteam"
		or name == "player_changeclass"
		or name == "player_spawn"
		or name == "teamplay_round_start"
		or name == "game_newmap"
		or name == "localplayer_changeteam"
		or name == "localplayer_changeclass"
	then
		FastPlayers.Reset()
	end
end)

return FastPlayers
