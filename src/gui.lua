local gui = {}

local menu = require("src.dependencies.nmenu")

local font = draw.CreateFont("TF2 BUILD", 16, 500)

---@param settings table
---@param version string
function gui.init(settings, version)
	local window = menu:make_window()
	window.width = 670
	window.height = 315

	local btn_starty = 10
	local component_width = 260
	local component_height = 25
	local gap = 5

	local function increase_y()
		btn_starty = btn_starty + component_height + gap
	end

	local function get_btn_y()
		local y = btn_starty
		increase_y()
		return y
	end

	local function get_slider_y()
		local y = btn_starty
		btn_starty = y + 45
		return y
	end

	do
		local w, h = draw.GetScreenSize()
		window.x = (w // 2) - (window.width // 2)
		window.y = (h // 2) - (window.height // 2)
	end

	window.font = font
	window.header = string.format("navet's projectile aimbot (v%s)", version)

	local aim_tab = menu:make_tab("aimbot")
	assert(aim_tab, "[PROJ AIMBOT] aimbot tab is nil! WTF")

	menu:set_tab_draw_function(aim_tab, function (current_window, current_tab, content_offset)
		window.height = 285
	end)

	local enabled_btn = menu:make_checkbox()
	enabled_btn.height = component_height
	enabled_btn.width = component_width
	enabled_btn.label = "enabled"
	enabled_btn.enabled = settings.enabled
	enabled_btn.x = 10
	enabled_btn.y = get_btn_y()

	enabled_btn.func = function()
		settings.enabled = not settings.enabled
		enabled_btn.enabled = settings.enabled
	end

	local autoshoot_btn = menu:make_checkbox()
	autoshoot_btn.height = component_height
	autoshoot_btn.width = component_width
	autoshoot_btn.label = "autoshoot"
	autoshoot_btn.enabled = settings.autoshoot
	autoshoot_btn.x = 10
	autoshoot_btn.y = get_btn_y()

	autoshoot_btn.func = function()
		settings.autoshoot = not settings.autoshoot
		autoshoot_btn.enabled = settings.autoshoot
	end

	local draw_proj_path_btn = menu:make_checkbox()
	draw_proj_path_btn.height = component_height
	draw_proj_path_btn.width = component_width
	draw_proj_path_btn.label = "draw projectile path"
	draw_proj_path_btn.enabled = settings.draw_proj_path
	draw_proj_path_btn.x = 10
	draw_proj_path_btn.y = get_btn_y()

	draw_proj_path_btn.func = function()
		settings.draw_proj_path = not settings.draw_proj_path
		draw_proj_path_btn.enabled = settings.draw_proj_path
	end

	local draw_player_path_btn = menu:make_checkbox()
	draw_player_path_btn.height = component_height
	draw_player_path_btn.width = component_width
	draw_player_path_btn.label = "draw player path"
	draw_player_path_btn.enabled = settings.draw_player_path
	draw_player_path_btn.x = 10
	draw_player_path_btn.y = get_btn_y()

	draw_player_path_btn.func = function()
		settings.draw_player_path = not settings.draw_player_path
		draw_player_path_btn.enabled = settings.draw_player_path
	end

	local draw_bounding_btn = menu:make_checkbox()
	draw_bounding_btn.height = component_height
	draw_bounding_btn.width = component_width
	draw_bounding_btn.label = "draw bounding box"
	draw_bounding_btn.enabled = settings.draw_bounding_box
	draw_bounding_btn.x = 10
	draw_bounding_btn.y = get_btn_y()

	draw_bounding_btn.func = function()
		settings.draw_bounding_box = not settings.draw_bounding_box
		draw_bounding_btn.enabled = settings.draw_bounding_box
	end

	local draw_only_btn = menu:make_checkbox()
	draw_only_btn.height = component_height
	draw_only_btn.width = component_width
	draw_only_btn.label = "draw only"
	draw_only_btn.enabled = settings.draw_multipoint_target
	draw_only_btn.x = 10
	draw_only_btn.y = get_btn_y()

	draw_only_btn.func = function()
		settings.draw_only = not settings.draw_only
		draw_only_btn.enabled = settings.draw_only
	end

	local draw_multipoint_target_btn = menu:make_checkbox()
	draw_multipoint_target_btn.height = component_height
	draw_multipoint_target_btn.width = component_width
	draw_multipoint_target_btn.label = "draw multpoint target"
	draw_multipoint_target_btn.enabled = settings.draw_only
	draw_multipoint_target_btn.x = 10
	draw_multipoint_target_btn.y = get_btn_y()

	draw_multipoint_target_btn.func = function()
		settings.draw_multipoint_target = not settings.draw_multipoint_target
		draw_multipoint_target_btn.enabled = settings.draw_multipoint_target
	end

	local cancel_shot_btn = menu:make_checkbox()
	cancel_shot_btn.height = component_height
	cancel_shot_btn.width = component_width
	cancel_shot_btn.label = "cancel shot"
	cancel_shot_btn.enabled = settings.cancel_shot
	cancel_shot_btn.x = 10
	cancel_shot_btn.y = get_btn_y()

	cancel_shot_btn.func = function()
		settings.cancel_shot = not settings.cancel_shot
		cancel_shot_btn.enabled = settings.cancel_shot
	end

	local draw_quads_btn = menu:make_checkbox()
	draw_quads_btn.height = component_height
	draw_quads_btn.width = component_width
	draw_quads_btn.label = "draw quads"
	draw_quads_btn.enabled = settings.draw_quads
	draw_quads_btn.x = 10
	draw_quads_btn.y = get_btn_y()

	draw_quads_btn.func = function()
		settings.draw_quads = not settings.draw_quads
		draw_quads_btn.enabled = settings.draw_quads
	end

	--- right side

	btn_starty = 10

	local allow_aim_at_teammates_btn = menu:make_checkbox()
	allow_aim_at_teammates_btn.height = component_height
	allow_aim_at_teammates_btn.width = component_width
	allow_aim_at_teammates_btn.label = "allow aim at teammates"
	allow_aim_at_teammates_btn.enabled = settings.allow_aim_at_teammates
	allow_aim_at_teammates_btn.x = component_width + 20
	allow_aim_at_teammates_btn.y = get_btn_y()

	allow_aim_at_teammates_btn.func = function()
		settings.allow_aim_at_teammates = not settings.allow_aim_at_teammates
		allow_aim_at_teammates_btn.enabled = settings.allow_aim_at_teammates
	end

	local psilent_btn = menu:make_checkbox()
	psilent_btn.height = component_height
	psilent_btn.width = component_width
	psilent_btn.label = "silent+"
	psilent_btn.enabled = settings.psilent
	psilent_btn.x = component_width + 20
	psilent_btn.y = get_btn_y()

	psilent_btn.func = function()
		settings.psilent = not settings.psilent
		psilent_btn.enabled = settings.psilent
	end

	local lag_comp_btn = menu:make_checkbox()
	lag_comp_btn.height = component_height
	lag_comp_btn.width = component_width
	lag_comp_btn.label = "ping compensation"
	lag_comp_btn.enabled = settings.ping_compensation
	lag_comp_btn.x = component_width + 20
	lag_comp_btn.y = get_btn_y()

	lag_comp_btn.func = function()
		settings.ping_compensation = not settings.ping_compensation
		lag_comp_btn.enabled = settings.ping_compensation
	end

	for name, enabled in pairs(settings.ents) do
		local btn = menu:make_checkbox()
		assert(btn, string.format("Button %s is nil!", name))

		btn.enabled = enabled
		btn.width = component_width
		btn.height = component_height
		btn.x = component_width + 20
		btn.y = get_btn_y()
		btn.label = name

		btn.func = function()
			settings.ents[name] = not settings.ents[name]
			btn.enabled = settings.ents[name]
		end
	end

	local wait_charge_btn = menu:make_checkbox()
	wait_charge_btn.height = component_height
	wait_charge_btn.width = component_width
	wait_charge_btn.label = "wait for charge (laggy)"
	wait_charge_btn.enabled = settings.wait_for_charge
	wait_charge_btn.x = component_width + 20
	wait_charge_btn.y = get_btn_y()

	wait_charge_btn.func = function()
		settings.wait_for_charge = not settings.wait_for_charge
		wait_charge_btn.enabled = settings.wait_for_charge
	end

	local show_angles_btn = menu:make_checkbox()
	show_angles_btn.height = component_height
	show_angles_btn.width = component_width
	show_angles_btn.label = "show angles"
	show_angles_btn.enabled = settings.show_angles
	show_angles_btn.x = component_width + 20
	show_angles_btn.y = get_btn_y()

	show_angles_btn.func = function()
		settings.show_angles = not settings.show_angles
		show_angles_btn.enabled = settings.show_angles
	end

	---

	local misc_tab = menu:make_tab("misc")
	assert(misc_tab, "[PROJ AIMBOT] aimbot tab is nil! WTF")

	menu:set_tab_draw_function(misc_tab, function (current_window, current_tab, content_offset)
		window.height = 315
	end)

	btn_starty = 25

	local sim_time_slider = menu:make_slider()
	assert(sim_time_slider, "sim time slider is nil somehow!")

	sim_time_slider.font = font
	sim_time_slider.height = 20
	sim_time_slider.label = "max sim time"
	sim_time_slider.max = 10
	sim_time_slider.min = 0.5
	sim_time_slider.value = settings.max_sim_time
	sim_time_slider.width = component_width * 2
	sim_time_slider.x = 10
	sim_time_slider.y = get_slider_y()

	sim_time_slider.func = function()
		settings.max_sim_time = sim_time_slider.value
	end

	local max_distance_slider = menu:make_slider()
	assert(max_distance_slider, "max distance slider is nil somehow!")

	max_distance_slider.font = font
	max_distance_slider.height = 20
	max_distance_slider.label = "max distance"
	max_distance_slider.max = 4096
	max_distance_slider.min = 0
	max_distance_slider.value = settings.max_distance
	max_distance_slider.width = component_width * 2
	max_distance_slider.x = 10
	max_distance_slider.y = get_slider_y()

	max_distance_slider.func = function()
		settings.max_distance = max_distance_slider.value
	end

	local fov_slider = menu:make_slider()
	assert(fov_slider, "fov slider is nil somehow!")

	fov_slider.font = font
	fov_slider.height = 20
	fov_slider.label = "fov"
	fov_slider.max = 180
	fov_slider.min = 0
	fov_slider.value = settings.fov
	fov_slider.width = component_width * 2
	fov_slider.x = 10
	fov_slider.y = get_slider_y()

	fov_slider.func = function()
		settings.fov = fov_slider.value
	end

	local priotity_slider = menu:make_slider()
	assert(priotity_slider, "priotty slider is nil somehow!")

	priotity_slider.font = font
	priotity_slider.height = 20
	priotity_slider.label = "min priority"
	priotity_slider.max = 10
	priotity_slider.min = 0
	priotity_slider.value = settings.min_priority
	priotity_slider.width = component_width * 2
	priotity_slider.x = 10
	priotity_slider.y = get_slider_y()

	priotity_slider.func = function()
		settings.min_priority = priotity_slider.value // 1
	end

	local time_slider = menu:make_slider()
	assert(time_slider, "time slider is nil somehow!")

	time_slider.font = font
	time_slider.height = 20
	time_slider.label = "draw time"
	time_slider.max = 10
	time_slider.min = 0
	time_slider.value = settings.draw_time
	time_slider.width = component_width * 2
	time_slider.x = 10
	time_slider.y = get_slider_y()

	time_slider.func = function()
		settings.draw_time = time_slider.value
	end

	local percent_slider = menu:make_slider()
	assert(percent_slider, "max percentage slider is nil somehow!")

	percent_slider.font = font
	percent_slider.height = 20
	percent_slider.label = "max charge (%)"
	percent_slider.max = 100
	percent_slider.min = 0
	percent_slider.value = settings.max_percent
	percent_slider.width = component_width * 2
	percent_slider.x = 10
	percent_slider.y = get_slider_y()

	percent_slider.func = function()
		settings.max_percent = percent_slider.value
	end

	local close_dst_slider = menu:make_slider()
	assert(close_dst_slider, "close distance slider is nil somehow!")

	close_dst_slider.font = font
	close_dst_slider.height = 20
	close_dst_slider.label = "close distance (%)"
	close_dst_slider.max = 100
	close_dst_slider.min = 0
	close_dst_slider.value = settings.close_distance
	close_dst_slider.width = component_width * 2
	close_dst_slider.x = 10
	close_dst_slider.y = get_slider_y()

	close_dst_slider.func = function()
		settings.close_distance = close_dst_slider.value
	end

	local conds_tab = menu:make_tab("conditions")
	assert(conds_tab, "[PROJ AIMBOT] aimbot tab is nil! WTF")

	menu:set_tab_draw_function(conds_tab, function (current_window, current_tab, content_offset)
		window.height = 195
	end)

	btn_starty = 10

	local column = 1
	local left_column_count = 0
	local right_column_count = 0

	for name, enabled in pairs(settings.ignore_conds) do
		local btn = menu:make_checkbox()
		assert(btn, string.format("Button %s is nil!", name))

		btn.enabled = enabled
		btn.width = component_width
		btn.height = component_height
		btn.label = string.format("ignore %s", name)

		-- alternate between left and right columns
		if column == 1 then
			btn.x = 10
			btn.y = 10 + (left_column_count * (component_height + gap))
			left_column_count = left_column_count + 1
			column = 2
		else
			btn.x = component_width + 20
			btn.y = 10 + (right_column_count * (component_height + gap))
			right_column_count = right_column_count + 1
			column = 1
		end

		btn.func = function()
			settings.ignore_conds[name] = not settings.ignore_conds[name]
			btn.enabled = settings.ignore_conds[name]
		end
	end

	---

	local colors_tab = menu:make_tab("colors")
	assert(colors_tab, "colors tab is nil!")

	menu:set_tab_draw_function(colors_tab, function (current_window, current_tab, content_offset)
		window.height = 280
	end)

	btn_starty = 25

	for name, visual in pairs (settings.colors) do
		local slider = menu:make_colored_slider()
		assert(slider, string.format("Slider %s is nil!", name))

		slider.width = component_width * 2
		slider.height = component_height
		slider.x = 10
		slider.y = get_slider_y()
		slider.max = 360
		slider.min = 0
		slider.value = visual
		slider.label = string.gsub(name, "_", " ")
		slider.func = function()
			settings.colors[name] = slider.value//1
		end
	end

	--[[local sim_tab = menu:make_tab("simulation")
	assert(sim_tab, "[PROJ AIMBOT] simulation tab is nil! wtf")

	menu:set_tab_draw_function(sim_tab, function (current_window, current_tab, content_offset)
		window.height = 135
	end)

	btn_starty = 10

	column = 1
	left_column_count = 0
	right_column_count = 0

	for name, enabled in pairs(settings.sim) do
		local btn = menu:make_checkbox()
		assert(btn, string.format("Button %s is nil!", name))

		btn.enabled = enabled
		btn.width = component_width
		btn.height = component_height
		btn.label = string.gsub(name, "_", " ")

		-- alternate between left and right columns
		if column == 1 then
			btn.x = 10
			btn.y = 10 + (left_column_count * (component_height + gap))
			left_column_count = left_column_count + 1
			column = 2
		else
			btn.x = component_width + 20
			btn.y = 10 + (right_column_count * (component_height + gap))
			right_column_count = right_column_count + 1
			column = 1
		end

		btn.func = function()
			settings.sim[name] = not settings.sim[name]
			btn.enabled = settings.sim[name]
		end
	end]]

	local thick = menu:make_tab("thickness")
	assert(thick, "Thick is not valid!")
	menu:set_tab_draw_function(thick, function (current_window, current_tab, content_offset)
		window.height = 195
	end)

	btn_starty = 25

	for name, visual in pairs (settings.thickness) do
		local slider = menu:make_slider()
		assert(slider, string.format("Slider %s is nil!", name))

		slider.width = component_width * 2
		slider.height = component_height
		slider.x = 10
		slider.y = get_slider_y()
		slider.max = 5
		slider.min = 0.1
		slider.value = visual
		slider.label = string.gsub(name, "_", " ")
		slider.func = function()
			settings.thickness[name] = slider.value//1
		end
	end

	menu:register()
	printc(150, 255, 150, 255, "[PROJ AIMBOT] Menu loaded")
end

function gui.unload()
	menu.unload()
end

return gui
