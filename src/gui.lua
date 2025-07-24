local gui = {}

local menu
do
	local content = http.Get("https://raw.githubusercontent.com/uosq/lbox-menu/refs/heads/main/src/nmenu.lua")
	if content then
		menu = load(content)()
		assert(menu, "Menu is nil!")
	end
end

local font = draw.CreateFont("TF2 BUILD", 16, 500)

---@param settings table
---@param version string
function gui.init(settings, version)
	local window = menu:make_window()
	window.width = 670
	window.height = 270

	local component_width = 260

	do
		local w, h = draw.GetScreenSize()
		window.x = (w // 2) - (window.width // 2)
		window.y = (h // 2) - (window.height // 2)
	end

	window.font = font
	window.header = string.format("navet's projectile aimbot (v%s)", version)

	menu:make_tab("aimbot")

	local enabled_btn = menu:make_checkbox()
	enabled_btn.height = 20
	enabled_btn.width = component_width
	enabled_btn.label = "enabled"
	enabled_btn.enabled = settings.enabled
	enabled_btn.x = 10
	enabled_btn.y = 10

	enabled_btn.func = function()
		settings.enabled = not settings.enabled
		enabled_btn.enabled = settings.enabled
	end

	local autoshoot_btn = menu:make_checkbox()
	autoshoot_btn.height = 20
	autoshoot_btn.width = component_width
	autoshoot_btn.label = "autoshoot"
	autoshoot_btn.enabled = settings.autoshoot
	autoshoot_btn.x = 10
	autoshoot_btn.y = 35

	autoshoot_btn.func = function()
		settings.autoshoot = not settings.autoshoot
		autoshoot_btn.enabled = settings.autoshoot
	end

	local draw_proj_path_btn = menu:make_checkbox()
	draw_proj_path_btn.height = 20
	draw_proj_path_btn.width = component_width
	draw_proj_path_btn.label = "draw projectile path"
	draw_proj_path_btn.enabled = settings.draw_proj_path
	draw_proj_path_btn.x = 10
	draw_proj_path_btn.y = 60

	draw_proj_path_btn.func = function()
		settings.draw_proj_path = not settings.draw_proj_path
		draw_proj_path_btn.enabled = settings.draw_proj_path
	end

	local draw_player_path_btn = menu:make_checkbox()
	draw_player_path_btn.height = 20
	draw_player_path_btn.width = component_width
	draw_player_path_btn.label = "draw player path"
	draw_player_path_btn.enabled = settings.draw_player_path
	draw_player_path_btn.x = 10
	draw_player_path_btn.y = 85

	draw_player_path_btn.func = function()
		settings.draw_player_path = not settings.draw_player_path
		draw_player_path_btn.enabled = settings.draw_player_path
	end

	local draw_bounding_btn = menu:make_checkbox()
	draw_bounding_btn.height = 20
	draw_bounding_btn.width = component_width
	draw_bounding_btn.label = "draw bounding box"
	draw_bounding_btn.enabled = settings.draw_bounding_box
	draw_bounding_btn.x = 10
	draw_bounding_btn.y = 110

	draw_bounding_btn.func = function()
		settings.draw_bounding_box = not settings.draw_bounding_box
		draw_bounding_btn.enabled = settings.draw_bounding_box
	end

	local draw_only_btn = menu:make_checkbox()
	draw_only_btn.height = 20
	draw_only_btn.width = component_width
	draw_only_btn.label = "draw only"
	draw_only_btn.enabled = settings.draw_only
	draw_only_btn.x = 10
	draw_only_btn.y = 135

	draw_only_btn.func = function()
		settings.draw_only = not settings.draw_only
		draw_only_btn.enabled = settings.draw_only
	end

	local method_selection = menu:make_dropdown()
	method_selection.font = font
	method_selection.height = 20
	method_selection.width = component_width
	method_selection.label = "aim method"
	method_selection.items = { "plain", "silent", "silent+" }
	method_selection.x = 10
	method_selection.y = 181
	method_selection.selected_index = 3

	method_selection.func = function(index, value)
		if value == "silent" then
			settings.psilent = false
			settings.silent = true
		elseif value == "silent+" then
			settings.psilent = true
			settings.silent = true
		elseif value == "plain" then
			settings.psilent = false
			settings.silent = false
		end
	end

	--- right side
	local multipoint_btn = menu:make_checkbox()
	multipoint_btn.height = 20
	multipoint_btn.width = component_width
	multipoint_btn.label = "multipoint"
	multipoint_btn.enabled = settings.multipointing
	multipoint_btn.x = component_width + 20
	multipoint_btn.y = 10

	multipoint_btn.func = function()
		settings.multipointing = not settings.multipointing
		multipoint_btn.enabled = settings.multipointing
	end

	local allow_aim_at_teammates_btn = menu:make_checkbox()
	allow_aim_at_teammates_btn.height = 20
	allow_aim_at_teammates_btn.width = component_width
	allow_aim_at_teammates_btn.label = "allow aim at teammates"
	allow_aim_at_teammates_btn.enabled = settings.allow_aim_at_teammates
	allow_aim_at_teammates_btn.x = component_width + 20
	allow_aim_at_teammates_btn.y = 35

	allow_aim_at_teammates_btn.func = function()
		settings.allow_aim_at_teammates = not settings.allow_aim_at_teammates
		allow_aim_at_teammates_btn.enabled = settings.allow_aim_at_teammates
	end

	local lag_comp_btn = menu:make_checkbox()
	lag_comp_btn.height = 20
	lag_comp_btn.width = component_width
	lag_comp_btn.label = "ping compensation"
	lag_comp_btn.enabled = settings.ping_compensation
	lag_comp_btn.x = component_width + 20
	lag_comp_btn.y = 60

	lag_comp_btn.func = function()
		settings.ping_compensation = not settings.ping_compensation
		lag_comp_btn.enabled = settings.ping_compensation
	end

	do
		local i = 0
		local starty = 85
		local gap = 5

		for name, enabled in pairs(settings.ents) do
			local btn = menu:make_checkbox()
			assert(btn, string.format("Button %s is nil!", name))

			btn.enabled = enabled
			btn.width = component_width
			btn.height = 20
			btn.x = component_width + 20
			btn.y = (btn.height * i) + starty + (gap * i)
			btn.label = name

			btn.func = function()
				settings.ents[name] = not settings.ents[name]
				btn.enabled = settings.ents[name]
			end

			i = i + 1
		end
	end
	---

	menu:make_tab("misc")

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
	sim_time_slider.y = 25

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
	max_distance_slider.y = 70

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
	fov_slider.y = 115

	fov_slider.func = function()
		settings.fov = fov_slider.value
	end

	menu:make_tab("conditions")

	do
		local i = 0
		local starty = 10
		local gap = 5

		--- im too lazy to make them one by one
		--- i just didnt do the same with the other ones because i want them ordered
		for name, enabled in pairs(settings.ignore_conds) do
			local btn = menu:make_checkbox()
			assert(btn, string.format("Button %s is nil!", name))

			btn.enabled = enabled
			btn.width = component_width
			btn.height = 20
			btn.x = i >= 10 and component_width + 20 or 10
			btn.y = (btn.height * (i >= 10 and i - 10 or i)) + starty + (gap * (i >= 10 and i - 10 or i))
			btn.label = string.format("ignore %s", name)

			btn.func = function()
				settings.ignore_conds[name] = not settings.ignore_conds[name]
				btn.enabled = settings.ignore_conds[name]
			end

			i = i + 1
		end
	end

	menu:register()
	printc(150, 255, 150, 255, "[PROJ AIMBOT] Menu loaded")
end

function gui.unload()
	menu.unload()
end

return gui
