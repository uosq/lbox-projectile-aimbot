local gui = {}

local menu = require("src.nmenu")
local font = draw.CreateFont("TF2 BUILD", 16, 500)

---@param settings table
---@param version string
function gui.init(settings, version)
	local window = menu:make_window()
	window.width = 400
	window.height = 330

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

	local sim_time_slider = menu:make_slider()
	assert(sim_time_slider, "sim time slider is nil somehow!")

	sim_time_slider.font = font
	sim_time_slider.height = 20
	sim_time_slider.label = "max sim time"
	sim_time_slider.max = 10
	sim_time_slider.min = 0.5
	sim_time_slider.value = settings.max_sim_time
	sim_time_slider.width = component_width
	sim_time_slider.x = 10
	sim_time_slider.y = 80

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
	max_distance_slider.width = component_width
	max_distance_slider.x = 10
	max_distance_slider.y = 125

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
	fov_slider.width = component_width
	fov_slider.x = 10
	fov_slider.y = 170

	fov_slider.func = function()
		settings.fov = fov_slider.value
	end

	local draw_proj_path_btn = menu:make_checkbox()
	draw_proj_path_btn.height = 20
	draw_proj_path_btn.width = component_width
	draw_proj_path_btn.label = "draw projectile path"
	draw_proj_path_btn.enabled = settings.draw_proj_path
	draw_proj_path_btn.x = 10
	draw_proj_path_btn.y = 200

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
	draw_player_path_btn.y = 225

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
	draw_bounding_btn.y = 250

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
	draw_only_btn.y = 275

	draw_only_btn.func = function()
		settings.draw_only = not settings.draw_only
		draw_only_btn.enabled = settings.draw_only
	end

	local silent_btn = menu:make_checkbox()
	silent_btn.height = 20
	silent_btn.width = component_width
	silent_btn.label = "silent"
	silent_btn.enabled = settings.silent
	silent_btn.x = 10
	silent_btn.y = 300

	silent_btn.func = function()
		settings.silent = not settings.silent
		silent_btn.enabled = settings.silent
	end

	local psilent_btn = menu:make_checkbox()
	psilent_btn.height = 20
	psilent_btn.width = component_width
	psilent_btn.label = "silent+"
	psilent_btn.enabled = settings.psilent
	psilent_btn.x = 10
	psilent_btn.y = 325

	psilent_btn.func = function()
		settings.psilent = not settings.psilent
		psilent_btn.enabled = settings.psilent
	end

	menu:make_tab("conditions")

	do
		local i = 0
		local starty = 10
		local gap = 5

		--- im too lazy to make them one by one
		--- i just didnt do the same with the other ones because i want them ordered
		for name, enabled in pairs(settings.conds) do
			local btn = menu:make_checkbox()
			assert(btn, string.format("Button %s is nil!", name))

			btn.enabled = enabled
			btn.width = component_width
			btn.height = 20
			btn.x = 10
			btn.y = (btn.height * i) + starty + (gap * i)
			btn.label = string.format("ignore %s", name)

			btn.func = function()
				settings.conds[name] = not settings.conds[name]
				btn.enabled = settings.conds[name]
			end

			i = i + 1
		end
	end

	local soon_btn = menu:make_button()
	assert(soon_btn, "soon button is nil! wtf")

	local half_content_offset = 61

	soon_btn.width = 100
	soon_btn.height = 20
	soon_btn.label = "more soon?"
	soon_btn.x = (window.width // 2) - (soon_btn.width // 2) - half_content_offset
	soon_btn.y = 200

	menu:register()
end

function gui.unload()
	menu.unload()
end

return gui
