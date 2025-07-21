---@param player_sim table
---@param CanRun function
---@param wep_utils table
---@param ProcessPrediction function
---@param paths table
---@return number?
local function CreateMove(player_sim, CanRun, wep_utils, ProcessPrediction, paths)
	local netchannel = clientstate.GetNetChannel()
	if not netchannel then
		return
	end

	local pLocal = entities.GetLocalPlayer()
	if pLocal == nil then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if pWeapon == nil then
		return
	end

	local players = entities.FindByClass("CTFPlayer")
	player_sim.RunBackground(players)

	if not CanRun(pLocal, pWeapon, true, true) then
		return
	end

	local iCase, iDefinitionIndex = wep_utils.GetWeaponDefinition(pWeapon)
	if not iCase or not iDefinitionIndex then
		return
	end

	local iWeaponID = pWeapon:GetWeaponID()
	local bAimAtTeamMates = false

	if (iWeaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX) or (iWeaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW) then
		bAimAtTeamMates = true
	end

	local pred_result, _ = ProcessPrediction(
		pLocal,
		pWeapon,
		pTarget,
		vecHeadPos,
		iMaxDistance,
		math_utils,
		weaponInfo,
		multipoint,
		nLatency,
		nMaxTime,
		player_sim
	)
	if not pred_result then
		return
	end

	paths.player_path = pred_result.vecPlayerPath
	paths.proj_path = pred_result.vecProjPath
	return globals.CurTime() + 1
end

return CreateMove
