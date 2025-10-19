local version = "10"

local settings = require("src.settings")
assert(settings, "[PROJ AIMBOT] Settings module failed to load!")

local wep_utils = require("src.utils.weapon_utils")
assert(wep_utils, "[PROJ AIMBOT] Weapon utils module failed to load!")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Weapon utils loaded")

local math_utils = require("src.utils.math")
assert(math_utils, "[PROJ AIMBOT] Math utils module failed to load!")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Math utils loaded")

local ent_utils = require("src.utils.entity")
assert(ent_utils, "[PROJ AIMBOT] Entity utils module failed to load!")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Entity utils loaded")

local player_sim = require("src.simulation.player")
assert(player_sim, "[PROJ AIMBOT] Player prediction module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Player prediction module loaded")

---@type ProjectileSimulation
local proj_sim = require("src.simulation.proj")
assert(proj_sim, "[PROJ AIMBOT] Projectile prediction module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Projectile prediction module loaded")

local GetProjectileInformation = require("src.projectile_info")
assert(GetProjectileInformation, "[PROJ AIMBOT] GetProjectileInformation module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] GetProjectileInformation module loaded")

local Visuals = require("src.visuals")
assert(Visuals, "[PROJ AIMBOT] Visuals module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Visuals module loaded")

local multipoint = require("src.multipoint")
assert(multipoint, "[PROJ AIMBOT] Multipoint module failed to load")
printc(150, 255, 150, 255, "[PROJ AIMBOT] Multipoint module loaded")

local visuals = Visuals.new()

local menu = require("src.gui")
menu.init(version)

---@type Entity?, Entity?, WeaponInfo?
local plocal, weapon, weaponInfo = nil, nil, nil

local vAngles = nil

---@param outputList table<integer, EntityInfo>
local function ProcessClass(className, includeTeam, outputList)
    if plocal == nil then
        return
    end

    local list = entities.FindByClass(className)

    for _, entity in pairs(list) do
        if entity:IsDormant() or (entity:IsPlayer() and not entity:IsAlive() or entity:GetHealth() <= 0) then
            goto continue
        end

        if not includeTeam and entity:GetTeamNumber() == plocal:GetTeamNumber() then
            goto continue
        end

        outputList[#outputList + 1] = {
            index = entity:GetIndex(),
            health = entity:GetHealth(),
            maxs = entity:GetMaxs(),
            mins = entity:GetMins(),
            velocity = entity:EstimateAbsVelocity() or Vector3(),
            maxspeed = entity:GetPropFloat("m_flMaxspeed") or 0,
            angvelocity = player_sim.GetSmoothedAngularVelocity(entity) or 0,
            stepsize = entity:GetPropFloat("m_flStepSize") or 18,
            origin = entity:GetAbsOrigin(),
            name = entity:GetName() or "unnamed",
            fov = math.huge,
            dist = math.huge,
            friction = entity:GetPropFloat("localdata", "m_flFriction") or 1.0,
            team = entity:GetTeamNumber(),
            score = 0,
            class = entity:GetPropInt("m_iClass") or nil,
            isUbered = entity:InCond(E_TFCOND.TFCond_Ubercharged),
            maxhealth = entity:GetMaxBuffedHealth(),
            timesecs = math.huge,
        }

        ::continue::
    end
end

---@param data EntityInfo
---@return number
local function CalculateScore(data, eyePos, viewAngles, includeTeam)
    if plocal == nil then
        return 0
    end

    local score = 0
    local w = settings.weights

    --- distance (closer = higher score)
    if w.distance_weight > 0 then
        local dist_score = 1 - math.min(data.dist / settings.max_distance, 1)
        score = score + dist_score * w.distance_weight
    end

    --- health (lower health = higher score)
    if w.health_weight > 0 then
        local health_score = 1 - math.min(data.health / data.maxhealth, 1)
        score = score + health_score * w.health_weight
    end

    --- lower fov = better
    if w.fov_weight > 0 and settings.onfov_only == false then
        local angle = math_utils.PositionAngles(eyePos, data.finalPos or data.origin)
        if angle then
            local fov = math_utils.AngleFov(viewAngles, angle)
            local fov_score = 1 - math.min(fov / settings.fov, 1)
            score = score + fov_score * w.fov_weight
        end
    end

    --- visibility (if visible = full weight)
    if w.visibility_weight > 0 then
        score = score + w.visibility_weight
    end

    --- speed (slower = easier to hit)
    if w.speed_weight and w.speed_weight > 0 then
        local speed = data.velocity:Length()
        local speed_score = 1 - math.min(speed / data.maxspeed, 1) -- normalize
        score = score + speed_score * w.speed_weight
    end

    --- class priority
    if data.class and data.class == E_Character.TF2_Medic then
        score = score + w.medic_priority
    elseif data.class and data.class == E_Character.TF2_Sniper then
        score = score + w.sniper_priority
    end

    --- uber penalty (skip ubercharged targets)
    if data.isUbered and w.uber_penalty then
        score = score + w.uber_penalty
    end

    --- favor a lot our team
    if includeTeam and data.team == plocal:GetTeamNumber() then
        score = score + settings.weights.teammate_weight
    end

    return score
end

--- Returns a sorted table (:))
---@return table<integer, EntityInfo>?
local function GetTargetsSmart(includeTeam)
    if plocal == nil or weapon == nil or weaponInfo == nil then
        return nil
    end

    local startList = {}

    -- collect entities
    if settings.ents["aim players"] then
        ProcessClass("CTFPlayer", includeTeam, startList)
    end

    if settings.ents["aim sentries"] then
        ProcessClass("CObjectSentrygun", includeTeam, startList)
    end

    if settings.ents["aim dispensers"] then
        ProcessClass("CObjectDispenser", includeTeam, startList)
    end

    if settings.ents["aim teleporters"] then
        ProcessClass("CObjectTeleporter", includeTeam, startList)
    end

    --- make a early return here
    --- if there are no valid entities
    --- then dont even bother
    if #startList == 0 then
        return startList
    end

    local lpPos = plocal:GetAbsOrigin()
    local eyePos = lpPos + plocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    local viewAngles = engine.GetViewAngles()
    local projectileSpeed = weaponInfo:GetVelocity(0):Length2D()

    local candidates = {}

    --- basic filtering
    for _, data in ipairs(startList) do
        local ent = entities.GetByIndex(data.index)
        if not ent then goto continue end

        local dist = (data.origin - lpPos):Length()
        if dist > settings.max_distance then goto continue end
        data.dist = dist

        if settings.onfov_only then
            local angle = math_utils.PositionAngles(eyePos, data.origin)
            if angle then
                local fov = math_utils.AngleFov(viewAngles, angle)
                if fov > settings.fov then goto continue end
            end
        end

        candidates[#candidates + 1] = data

        ::continue::
    end

    --- another early return
    --- dont bother if we have no candidates
    if #candidates == 0 then
        return candidates
    end

    local det_mult = weapon:AttributeHookFloat("sticky_arm_time") or 1.0
    local detonate_time = (settings.sim.use_detonate_time and weapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER) and
        0.7 * det_mult or 0
    local choked_time = clientstate:GetChokedCommands()

    local final_targets = {}

    for _, data in ipairs(candidates) do
        local ent = entities.GetByIndex(data.index)
        if not ent then goto continue end

        local travel_time_est = data.dist / projectileSpeed
        local total_time = travel_time_est + detonate_time
        local finalPos = Vector3(data.origin:Unpack())

        -- simulate player path if moving
        if data.velocity:Length() > 0 then
            data.origin.z = data.origin.z + 1 --- smol offset to fix a issue
            local time_ticks = math.ceil((total_time * 66.67) + 0.5) + choked_time + 1
            data.sim_path = player_sim.Run(data, ent, data.origin, time_ticks)
            if data.sim_path and #data.sim_path > 0 then
                finalPos = data.sim_path[#data.sim_path]
                travel_time_est = (finalPos - eyePos):Length() / projectileSpeed
                total_time = travel_time_est + detonate_time
            end
        else
            data.sim_path = { data.origin }
        end

        if total_time > settings.max_sim_time then goto continue end

        local visible, mpFinalPos = multipoint.Run(ent, weapon, weaponInfo, eyePos, finalPos)
        if not visible then goto continue end
        if mpFinalPos then finalPos = mpFinalPos end

        data.dist = (finalPos - lpPos):Length()
        data.finalPos = finalPos

        data.score = CalculateScore(data, eyePos, viewAngles, includeTeam)
        data.timesecs = total_time

        if data.score < (settings.min_score or 0) then
            goto continue
        end

        final_targets[#final_targets + 1] = data

        ::continue::
    end

    if #final_targets == 0 then
        return final_targets
    end

    -- sort by weighted score (highest first)
    table.sort(final_targets, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)

    -- limit number of targets
    local max_targets = settings.max_targets or 2
    if #final_targets > max_targets then
        for i = max_targets + 1, #final_targets do
            final_targets[i] = nil
        end
    end

    return final_targets
end

--- Normal closest to crosshair mode
--- with no weights or anything like that
---@return table<integer, EntityInfo>
local function GetTargetsNormal(includeTeam)
    if plocal == nil or weapon == nil or weaponInfo == nil then
        return {}
    end

    ---@type table<integer, EntityInfo>
    local startList = {}

    -- collect entities
    if settings.ents["aim players"] then
        ProcessClass("CTFPlayer", includeTeam, startList)
    end
    if settings.ents["aim sentries"] then
        ProcessClass("CObjectSentrygun", includeTeam, startList)
    end
    if settings.ents["aim dispensers"] then
        ProcessClass("CObjectDispenser", includeTeam, startList)
    end
    if settings.ents["aim teleporters"] then
        ProcessClass("CObjectTeleporter", includeTeam, startList)
    end

    if #startList == 0 then
        return {}
    end

    local lpPos = plocal:GetAbsOrigin()
    local eyePos = lpPos + plocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    local viewAngles = engine.GetViewAngles()
    local projectileSpeed = weaponInfo:GetVelocity(0):Length2D()

    local det_mult = weapon:AttributeHookFloat("sticky_arm_time") or 1.0
    local detonate_time = (settings.sim.use_detonate_time and weapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_PIPEBOMBLAUNCHER) and
        0.7 * det_mult or 0
    local choked_time = clientstate:GetChokedCommands()

    local candidates = {}

    for _, data in ipairs(startList) do
        local dist = (data.origin - lpPos):Length()
        if dist > settings.max_distance then
            goto continue
        end

        local angle = math_utils.PositionAngles(eyePos, data.origin)
        if angle then
            local fov = math_utils.AngleFov(viewAngles, angle)
            if fov > settings.fov then
                goto continue
            end

            data.fov = fov
            data.dist = dist
            data.finalPos = data.origin

            local ent = entities.GetByIndex(data.index)
            if ent then
                local travel_time_est = dist / projectileSpeed
                local total_time = travel_time_est + detonate_time
                local finalPos = Vector3(data.origin:Unpack())

                if data.velocity:Length() > 0 then
                    data.origin.z = data.origin.z + 1
                    local time_ticks = math.ceil((total_time * 66.67) + 0.5) + choked_time + 1
                    data.sim_path = player_sim.Run(data, ent, data.origin, time_ticks)
                    if data.sim_path and #data.sim_path > 0 then
                        finalPos = data.sim_path[#data.sim_path]
                        travel_time_est = (finalPos - eyePos):Length() / projectileSpeed
                        total_time = travel_time_est + detonate_time
                    end
                else
                    data.sim_path = { data.origin }
                end

                if total_time > settings.max_sim_time then
                    goto continue
                end

                -- multipoint
                local visible, mpFinalPos = multipoint.Run(ent, weapon, weaponInfo, eyePos, finalPos)
                if not visible then
                    goto continue
                end
                if mpFinalPos then
                    finalPos = mpFinalPos
                end

                data.dist = (finalPos - lpPos):Length()
                data.finalPos = finalPos
                data.score = 1.0 -- dummy, since sorting is by fov
            end

            candidates[#candidates + 1] = data
        end
        ::continue::
    end

    if #candidates == 0 then
        return {}
    end

    table.sort(candidates, function(a, b)
        return (a.fov or math.huge) < (b.fov or math.huge)
    end)

    local max_targets = settings.max_targets or 2
    if #candidates > max_targets then
        for i = max_targets + 1, #candidates do
            candidates[i] = nil
        end
    end

    return candidates
end

---@param cmd UserCmd
local function GetWeaponElapsedCharge(cmd)
    if weapon == nil or weaponInfo == nil then
        return 0.0
    end

    if weaponInfo.m_bCharges == false then
        return 0.0
    end

    local begintime = weapon:GetChargeBeginTime()
    local maxtime   = weapon:GetChargeMaxTime()
    local elapsed   = globals.CurTime() - begintime

    if elapsed > maxtime and (cmd.buttons & IN_ATTACK) == 0 then
        return 0.0
    end

    if weapon:GetPropInt("m_iItemDefinitionIndex") == 996 then
        elapsed = math.max(0, 1 - elapsed)
    end

    return elapsed
end

---@param cmd UserCmd
local function CreateMove(cmd)
    if clientstate.GetNetChannel() == nil then
        return
    end

    vAngles = nil

    if settings.enabled == false then
        return
    end

    if plocal == nil or weapon == nil or weaponInfo == nil then
        return
    end

    if (engine.IsChatOpen() or engine.Con_IsVisible() or engine.IsGameUIVisible()) == true then
        return
    end

    local isBeggarsBazooka = weapon:GetPropInt("m_iItemDefinitionIndex") == 730

    if not isBeggarsBazooka and not wep_utils.CanShoot() then
        return
    end

    if gui.GetValue("aim key") ~= 0 and input.IsButtonDown(gui.GetValue("aim key")) == false then
        return
    end

    if plocal:InCond(E_TFCOND.TFCond_Taunting) then
        return
    end

    if plocal:InCond(E_TFCOND.TFCond_HalloweenKart) then
        return
    end

    local weaponID = weapon:GetWeaponID()

    local includeTeam = weaponID == E_WeaponBaseID.TF_WEAPON_CROSSBOW
        or weaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX

    ---@type table<integer, EntityInfo>?
    local targets = settings.smart_targeting and GetTargetsSmart(includeTeam) or GetTargetsNormal(includeTeam)
    if targets == nil or #targets == 0 then
        return
    end

    ---@type EulerAngles?
    local angle = nil

    local weaponNoPSilent = weaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX
        or weaponID == E_WeaponBaseID.TF_WEAPON_FLAME_BALL
        or weaponID == E_WeaponBaseID.TF_WEAPON_BAT_WOOD
        or weaponID == E_WeaponBaseID.TF_WEAPON_JAR_MILK
        or weaponID == E_WeaponBaseID.TF_WEAPON_JAR
        or weaponID == E_WeaponBaseID.TF_WEAPON_BAT_GIFTWRAP

    local in_attack2 = weaponID == E_WeaponBaseID.TF_WEAPON_LUNCHBOX
        or weaponID == E_WeaponBaseID.TF_WEAPON_BAT_WOOD
        or weaponID == E_WeaponBaseID.TF_WEAPON_KNIFE
        or weaponID == E_WeaponBaseID.TF_WEAPON_BAT_GIFTWRAP

    local charge = weaponInfo.m_bCharges and weapon:GetChargeBeginTime() or globals.CurTime()
    local eyePos = plocal:GetAbsOrigin() + plocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    local projectileSpeed = weaponInfo:GetVelocity(charge):Length2D()
    local gravity = client.GetConVar("sv_gravity") * weaponInfo:GetGravity(charge) * 0.5

    local isRocketLauncher = isBeggarsBazooka or weaponID == E_WeaponBaseID.TF_WEAPON_ROCKETLAUNCHER

    visuals:set_eye_position(eyePos)

    local elapsedCharge = GetWeaponElapsedCharge(cmd)
    local ammo = weapon:GetPropInt("m_iClip1")
    for _, target in ipairs(targets) do
        local finalPos = target.finalPos or target.origin

        if settings.draw_only == false then
            angle = math_utils.SolveBallisticArc(eyePos, finalPos, projectileSpeed, gravity)
            if angle then
                if settings.autoshoot then
                    if weaponInfo.m_bCharges then
                        if elapsedCharge < 0.01 then
                            -- just started charging
                            cmd.buttons = cmd.buttons | IN_ATTACK
                            return
                        end

                        cmd.buttons = cmd.buttons & ~IN_ATTACK
                    else
                        if in_attack2 then
                            cmd.buttons = cmd.buttons | IN_ATTACK2
                        else
                            if isBeggarsBazooka then
                                --- gotta check CanShoot() as we skip it
                                --- because it returns false with 0 ammo
                                if ammo == 0 and wep_utils.CanShoot() == false then
                                    cmd.buttons = cmd.buttons | IN_ATTACK
                                    return
                                end
                            else
                                cmd.buttons = cmd.buttons | IN_ATTACK
                            end
                        end
                    end
                end

                if settings.psilent and weaponNoPSilent == false then
                    cmd.sendpacket = false
                end

                cmd.viewangles = Vector3(angle:Unpack())
                vAngles = angle
            end
        end

        if target then
            local ent = entities.GetByIndex(target.index)
            local proj_path = nil
            if ent and angle and settings.draw_proj_path then
                local weaponFirePos = weaponInfo:GetFirePosition(plocal, eyePos, angle, weapon:IsViewModelFlipped())
                if isRocketLauncher then
                  proj_path = {{pos = weaponFirePos}, {pos = target.sim_path[#target.sim_path]}}
                else
                  proj_path = proj_sim.Run(ent, plocal, weapon, weaponFirePos, angle:Forward(),
                      target.sim_path[#target.sim_path], target.timesecs, weaponInfo, charge)
                end
            end

            visuals:update_paths(target.sim_path, proj_path)
            visuals:set_target_hull(target.mins, target.maxs)
            visuals:set_displayed_time(globals.CurTime() + settings.draw_time)
            return
        end
    end
end

local function FrameStage(stage)
    if stage == E_ClientFrameStage.FRAME_NET_UPDATE_END then
        plocal = entities.GetLocalPlayer()
        if plocal == nil then
            weapon = nil
            weaponInfo = nil
            return
        end

        weapon = plocal:GetPropEntity("m_hActiveWeapon")
        weaponInfo = GetProjectileInformation(weapon:GetPropInt("m_iItemDefinitionIndex"))

        player_sim.RunBackground(entities.FindByClass("CTFPlayer"))
    elseif stage == E_ClientFrameStage.FRAME_RENDER_START and vAngles and settings.show_angles then
        if plocal == nil then return end
        if plocal:GetPropBool("m_nForceTauntCam") == false then return end
        plocal:SetVAngles(Vector3(vAngles:Unpack()))
    end
end

local function Draw()
    if not settings.enabled then
        return
    end

    if clientstate.GetNetChannel() == nil then
        return
    end

    visuals:draw()
end

local function Unload()
    menu.unload()
    visuals:destroy()
end

callbacks.Register("Draw", Draw)
callbacks.Register("CreateMove", CreateMove)
callbacks.Register("FrameStageNotify", FrameStage)
callbacks.Register("Unload", Unload)
