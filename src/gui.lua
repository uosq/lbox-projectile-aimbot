local gui = {}

local menu = require("src.dependencies.nmenu")

local font = draw.CreateFont("TF2 BUILD", 16, 500)

---@param settings table
---@param version string
function gui.init(settings, version)
	local window = menu:make_window()
	window.width = 670
	window.height = 225

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
		btn_starty = y +  45
		return y
	end

	do
		local w, h = draw.GetScreenSize()
		window.x = (w // 2) - (window.width // 2)
		window.y = (h // 2) - (window.height // 2)
	end

	window.font = font
	window.header = string.format("navet's projectile aimbot (v%s)", version)

	menu:make_tab("aimbot")

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
	draw_only_btn.enabled = settings.draw_only
	draw_only_btn.x = 10
	draw_only_btn.y = get_btn_y()

	draw_only_btn.func = function()
		settings.draw_only = not settings.draw_only
		draw_only_btn.enabled = settings.draw_only
	end

	local psilent_btn = menu:make_checkbox()
	psilent_btn.height = component_height
	psilent_btn.width = component_width
	psilent_btn.label = "silent+"
	psilent_btn.enabled = settings.psilent
	psilent_btn.x = 10
	psilent_btn.y = get_btn_y()

	psilent_btn.func = function()
		settings.psilent = not settings.psilent
		psilent_btn.enabled = settings.psilent
	end

	--- right side

	btn_starty = 10

	local multipoint_btn = menu:make_checkbox()
	multipoint_btn.height = component_height
	multipoint_btn.width = component_width
	multipoint_btn.label = "multipoint"
	multipoint_btn.enabled = settings.multipointing
	multipoint_btn.x = component_width + 20
	multipoint_btn.y = get_btn_y()

	multipoint_btn.func = function()
		settings.multipointing = not settings.multipointing
		multipoint_btn.enabled = settings.multipointing
	end

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
	---

	menu:make_tab("misc")

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

	menu:make_tab("conditions")

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

	--local hitpoints_tab = menu:make_tab("hitpoints")
	menu:make_tab("hitpoints")

	column = 1
	left_column_count = 0
	right_column_count = 0

	for name, enabled in pairs(settings.hitparts) do
		local btn = menu:make_checkbox()
		assert(btn, string.format("Button %s is nil!", name))

		btn.enabled = enabled
		btn.width = component_width
		btn.height = component_height

		local label = string.gsub(name, "_", " ")

		btn.label = string.format("%s", label)

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
			settings.hitparts[name] = not settings.hitparts[name]
			btn.enabled = settings.hitparts[name]
		end
	end

	--- happy now lsp?
	--[[if hitpoints_tab then
		menu:set_tab_draw_function(hitpoints_tab, function(current_window, current_tab, content_offset)
			local head_width = 20
			local centerx = (content_offset // 2) + current_window.x + (current_window.width // 2) - (head_width // 2)
			local y = window.y + (window.height // 2) - 50

			draw.Color(150, 255, 150, 255)
			draw.OutlinedCircle(centerx, y, head_width, 32)

			--- torso
			draw.Color(150, 255, 150, 255)
			draw.Line(centerx, y + head_width, centerx, y + 100)

			--- left leg
			draw.Color(150, 255, 150, 255)
			draw.Line(centerx, y + 100, centerx - 20, y + 150)

			--- right leg
			draw.Color(150, 255, 150, 255)
			draw.Line(centerx, y + 100, centerx + 20, y + 150)

			--- left arm
			draw.Color(255, 100, 100, 255)
			draw.Line(centerx, y + head_width, centerx - 55, y + 70)

			--- right arm
			draw.Line(centerx, y + head_width, centerx + 55, y + 70)
		end)
	end]]

	menu:register()
	printc(150, 255, 150, 255, "[PROJ AIMBOT] Menu loaded")
end

function gui.unload()
	menu.unload()
end

return gui
