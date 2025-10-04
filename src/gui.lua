local gui = {}

local ui = require("src.ui")
local settings = require("src.settings")

---@param version string
function gui.init(version)
    local menu = ui.New({ title = string.format("NAVET'S PROJECTILE AIMBOT (v%s)", tostring(version)) })
    menu.y = 50
    menu.x = 50
    -- Create tabs
    local aim_tab = menu:CreateTab("aimbot")
    local visuals_tab = menu:CreateTab("visuals")
    local misc_tab = menu:CreateTab("misc")
    local conds_tab = menu:CreateTab("conditions")
    local colors_tab = menu:CreateTab("colors")
    local thick_tab = menu:CreateTab("thickness")
    local target_weights = menu:CreateTab("target weights")

    local component_width = 260
    local component_height = 25

    -- AIMBOT TAB
    -- Left column toggles
    menu:CreateToggle(aim_tab, component_width, component_height, "enabled", settings.enabled, function(checked)
        settings.enabled = checked
    end)

    menu:CreateToggle(aim_tab, component_width, component_height, "autoshoot", settings.autoshoot, function(checked)
        settings.autoshoot = checked
    end)

    menu:CreateToggle(visuals_tab, component_width, component_height, "draw projectile path", settings.draw_proj_path,
        function(checked)
            settings.draw_proj_path = checked
        end)

    menu:CreateToggle(visuals_tab, component_width, component_height, "draw player path", settings.draw_player_path,
        function(checked)
            settings.draw_player_path = checked
        end)

    menu:CreateToggle(visuals_tab, component_width, component_height, "draw bounding box", settings.draw_bounding_box,
        function(checked)
            settings.draw_bounding_box = checked
        end)

    menu:CreateToggle(visuals_tab, component_width, component_height, "draw only", settings.draw_only, function(checked)
        settings.draw_only = checked
    end)

    menu:CreateToggle(visuals_tab, component_width, component_height, "draw multpoint target",
        settings.draw_multipoint_target, function(checked)
            settings.draw_multipoint_target = checked
        end)

    --[[menu:CreateToggle(aim_tab, component_width, component_height, "cancel shot", settings.cancel_shot, function(checked)
		settings.cancel_shot = checked
	end)]]

    menu:CreateToggle(visuals_tab, component_width, component_height, "draw filled bounding box", settings.draw_quads,
        function(checked)
            settings.draw_quads = checked
        end)

    -- Right column toggles
    menu:CreateToggle(aim_tab, component_width, component_height, "allow aim at teammates",
        settings.allow_aim_at_teammates, function(checked)
            settings.allow_aim_at_teammates = checked
        end)

    menu:CreateToggle(aim_tab, component_width, component_height, "silent+", settings.psilent, function(checked)
        settings.psilent = checked
    end)

    menu:CreateToggle(aim_tab, component_width, component_height, "ping compensation", settings.ping_compensation,
        function(checked)
            settings.ping_compensation = checked
        end)

    -- Entity toggles
    for name, enabled in pairs(settings.ents) do
        menu:CreateToggle(aim_tab, component_width, component_height, name, enabled, function(checked)
            settings.ents[name] = checked
        end)
    end

    menu:CreateToggle(aim_tab, component_width, component_height, "wait for charge (laggy)", settings.wait_for_charge,
        function(checked)
            settings.wait_for_charge = checked
        end)

    menu:CreateToggle(aim_tab, component_width, component_height, "show angles", settings.show_angles, function(checked)
        settings.show_angles = checked
    end)

    -- MISC TAB
    menu:CreateSlider(misc_tab, component_width, component_height, "max sim time", 0.5, 10, settings.max_sim_time,
        function(value)
            settings.max_sim_time = value
        end)

    menu:CreateSlider(misc_tab, component_width, component_height, "max distance", 0, 4096, settings.max_distance,
        function(value)
            settings.max_distance = value
        end)

    menu:CreateSlider(misc_tab, component_width, component_height, "min priority", 0, 10, settings.min_priority,
        function(value)
            settings.min_priority = math.floor(value)
        end)

    menu:CreateSlider(misc_tab, component_width, component_height, "draw time", 0, 10, settings.draw_time,
        function(value)
            settings.draw_time = value
        end)

    menu:CreateSlider(misc_tab, component_width, component_height, "max charge (%)", 0, 100, settings.max_percent,
        function(value)
            settings.max_percent = value
        end)

    menu:CreateSlider(misc_tab, component_width, component_height, "close distance (%)", 0, 100, settings.close_distance,
        function(value)
            settings.close_distance = value
        end)

    menu:CreateSlider(misc_tab, component_width, component_height, "max targets", 1, 3, settings.max_targets,
        function(value)
            settings.max_targets = value // 1
        end)

    -- CONDITIONS TAB
    for name, enabled in pairs(settings.ignore_conds) do
        menu:CreateToggle(conds_tab, component_width, component_height, string.format("ignore %s", name), enabled,
            function(checked)
                settings.ignore_conds[name] = checked
            end)
    end

    -- COLORS TAB
    for name, visual in pairs(settings.colors) do
        local label = string.gsub(name, "_", " ")
        menu:CreateHueSlider(colors_tab, component_width, component_height, label, visual, function(value)
            settings.colors[name] = math.floor(value)
        end)
    end

    -- THICKNESS TAB
    for name, visual in pairs(settings.thickness) do
        local label = string.gsub(name, "_", " ")
        menu:CreateSlider(thick_tab, component_width, component_height, label, 0.1, 5, visual, function(value)
            settings.thickness[name] = math.floor(value)
        end)
    end

    menu:CreateLabel(target_weights, component_width, component_height, "Bigger = more priority")

    -- TARGET MODE
    for name, mode in pairs(settings.weights) do
        local label = string.gsub(name, "_", " ")
        menu:CreateAccurateSlider(target_weights, component_width, component_height, label, 0, 5.0, mode, function(value)
            settings.weights[name] = value
        end)
    end

    menu:CreateToggle(target_weights, component_width, component_height, "draw scores", settings.draw_scores,
        function(checked)
            settings.draw_scores = checked
        end)

    menu:CreateAccurateSlider(target_weights, component_width, component_height, "minimum score", 0, 10,
        settings.min_score, function(value)
            settings.min_score = value
        end)

    menu:CreateToggle(target_weights, component_width, component_height, "inside fov only", settings.onfov_only,
        function(checked)
            settings.onfov_only = checked
        end)

    menu:CreateSlider(target_weights, component_width, component_height, "fov", 0, 180, settings.fov, function(value)
        settings.fov = value
    end)

    menu:CreateToggle(target_weights, component_width, component_height, "smart mode", settings.smart_targeting,
        function(checked)
            settings.smart_targeting = checked
        end)

    callbacks.Register("Draw", function(...)
        menu:Draw()
    end)
    printc(150, 255, 150, 255, "[PROJ AIMBOT] Menu loaded")
end

function gui.unload()
    ui.Unload()
end

return gui
