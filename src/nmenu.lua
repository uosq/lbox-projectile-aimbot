---@diagnostic disable: duplicate-set-field, undefined-field, redefined-local, cast-local-type

---@module "meta"

-- =============================================================================
-- CONSTANTS AND CONFIGURATION
-- =============================================================================

local OUTLINE_THICKNESS = 1
local TAB_BUTTON_WIDTH = 120
local TAB_BUTTON_HEIGHT = 25
local TAB_BUTTON_MARGIN = 2
local HEADER_SIZE = 25
local COMPONENT_TYPES = {
	BUTTON = 1,
	CHECKBOX = 2,
	SLIDER = 3,
	DROPDOWN = 4,
	LISTBOX = 5,
}

-- =============================================================================
-- MODULE STATE
-- =============================================================================

local draw_id = tostring(os.clock())
local font = draw.CreateFont("TF2 BUILD", 12, 1000)
local checkfont = draw.CreateFont("TF2 BUILD", 10, 1000)
local last_keypress_tick = 0

local deferred_dropdowns = {}

---@type table<integer, WINDOW>
local windows = {}

---@type WINDOW?
local current_window_context = nil

---@type BUTTON|CHECKBOX|SLIDER|DROPDOWN|LISTBOX
local current_component = nil

---@type SLIDER?
local dragging_slider = nil

---@type WINDOW?
local dragging_window = nil
local oldmx, oldmy = 0, 0
local dx, dy = 0, 0

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

local function clamp(value, min_val, max_val)
	return math.max(min_val, math.min(max_val, value))
end

local function is_mouse_inside(x1, y1, x2, y2)
	local mouse = input.GetMousePos()
	local mx, my = table.unpack(mouse)
	return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

local function get_current_window_tab()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return nil
	end

	-- If no tabs exist, return 0 (will be handled by make_new_component)
	if #window.tabs == 0 then
		return 0
	end

	return #window.tabs
end

local function get_content_area_offset()
	local window = current_window_context
	if not window or #window.tabs <= 1 then
		return 0
	end
	return TAB_BUTTON_WIDTH + TAB_BUTTON_MARGIN
end

local function get_new_component_index()
	local window = current_window_context
	assert(window, "Window context is nil!")

	-- If no tabs exist, create a default one
	if #window.tabs == 0 then
		table.insert(window.tabs, {
			name = "",
			components = {},
		})
	end

	return #window.tabs[#window.tabs].components + 1
end

local function make_new_component(component)
	local window = current_window_context
	if not window then
		return nil
	end

	-- If no tabs exist, create a default one
	if #window.tabs == 0 then
		table.insert(window.tabs, {
			name = "",
			components = {},
		})
	end

	local current_tab = get_current_window_tab()
	local index = get_new_component_index()

	window.tabs[current_tab].components[index] = component
	return window.tabs[current_tab].components[index]
end

-- =============================================================================
-- INPUT HANDLING
-- =============================================================================

local function handle_tab_button_click(window, tab_index)
	local tab_x = window.x
	local tab_y = window.y + (tab_index - 1) * (TAB_BUTTON_HEIGHT + TAB_BUTTON_MARGIN)
	local tab_x2 = tab_x + TAB_BUTTON_WIDTH
	local tab_y2 = tab_y + TAB_BUTTON_HEIGHT

	if is_mouse_inside(tab_x, tab_y, tab_x2, tab_y2) then
		local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
		if state and tick > last_keypress_tick then
			-- Set active tab for THIS specific window (my stupid brain is stupid)
			window.active_tab_index = tab_index
			last_keypress_tick = tick
		end
		return true
	end
	return false
end

local function handle_mouse_click()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
	local content_offset = get_content_area_offset()

	local x1 = component.x + window.x + content_offset
	local y1 = component.y + window.y
	local x2 = component.x + component.width + window.x + content_offset
	local y2 = component.y + component.height + window.y

	if component.type == COMPONENT_TYPES.DROPDOWN then
		if is_mouse_inside(x1, y1, x2, y2) and state and tick > last_keypress_tick then
			component.expanded = not component.expanded
			last_keypress_tick = tick
			return
		end

		if component.expanded then
			table.insert(deferred_dropdowns, {
				component = component,
				window = window,
			})
		end
	elseif component.type == COMPONENT_TYPES.LISTBOX then
		local item_height = 20
		local content_offset = get_content_area_offset()
		local listbox_x = window.x + component.x + content_offset
		local listbox_y = window.y + component.y

		for i, item in ipairs(component.items) do
			local iy = listbox_y + (i - 1) * item_height
			if iy + item_height > listbox_y + component.height then
				break
			end
			if
				is_mouse_inside(listbox_x, iy, listbox_x + component.width, iy + item_height)
				and state
				and tick > last_keypress_tick
			then
				component.selected_index = i
				if component.func then
					component.func(i, item)
				end
				last_keypress_tick = tick
				break
			end
		end
	else
		if is_mouse_inside(x1, y1, x2, y2) then
			if component.func and state and tick > last_keypress_tick then
				---@diagnostic disable-next-line: missing-parameter
				component.func()
				last_keypress_tick = tick
			end

			if input.IsButtonDown(E_ButtonCode.MOUSE_LEFT) then
				draw.Color(76, 86, 106, 255)
			end
		end
	end
end

local function handle_mouse_hover()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local content_offset = get_content_area_offset()
	local x1 = component.x + window.x - OUTLINE_THICKNESS + content_offset
	local y1 = component.y + window.y - OUTLINE_THICKNESS
	local x2 = component.x + window.x + component.width + OUTLINE_THICKNESS + content_offset
	local y2 = component.y + window.y + component.height + OUTLINE_THICKNESS

	if is_mouse_inside(x1, y1, x2, y2) then
		draw.Color(67, 76, 94, 255)
	end
end

local function handle_slider_drag()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local content_offset = get_content_area_offset()

	local slider_x = component.x + window.x + content_offset
	local slider_y = component.y + window.y
	local slider_w = component.width
	local slider_h = component.height

	-- Check if mouse is over the slider area
	if is_mouse_inside(slider_x, slider_y, slider_x + slider_w, slider_y + slider_h) then
		-- Start dragging if mouse is pressed and no other slider is being dragged
		if input.IsButtonDown(E_ButtonCode.MOUSE_LEFT) and dragging_slider == nil then
			dragging_slider = component
		end
	end

	-- Handle dragging
	if dragging_slider == component and input.IsButtonDown(E_ButtonCode.MOUSE_LEFT) then
		local mouse = input.GetMousePos()
		local mx = mouse[1]

		-- Calculate new value based on mouse position
		local relative_x = mx - slider_x
		local progress = clamp(relative_x / slider_w, 0, 1)

		-- Update slider value
		component.value = component.min + progress * (component.max - component.min)

		-- Call callback if exists
		if component.func then
			---@diagnostic disable-next-line: missing-parameter
			component.func(component.value)
		end
	end

	-- Stop dragging when mouse is released
	if dragging_slider == component and not input.IsButtonDown(E_ButtonCode.MOUSE_LEFT) then
		dragging_slider = nil
	end
end

local function handle_window_drag()
	local window = current_window_context
	assert(window, "Window context is nil! WTF")

	if input.IsButtonReleased(E_ButtonCode.MOUSE_LEFT) and dragging_window == window then
		dragging_window = nil
	end

	local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)

	if
		not dragging_slider
		and state
		and tick > last_keypress_tick
		and is_mouse_inside(window.x, window.y - HEADER_SIZE, window.x + window.width, window.y)
	then
		last_keypress_tick = tick
		dragging_window = window
	end

	if dragging_window == window then
		window.x = window.x + dx
		window.y = window.y + dy
	end
end

-- =============================================================================
-- COMPONENT RENDERING
-- =============================================================================

local function draw_button()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local content_offset = get_content_area_offset()

	-- Draw outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(
		component.x + window.x - OUTLINE_THICKNESS + content_offset,
		component.y + window.y - OUTLINE_THICKNESS,
		component.x + component.width + window.x + OUTLINE_THICKNESS + content_offset,
		component.y + component.height + window.y + OUTLINE_THICKNESS
	)

	-- Default background color
	draw.Color(59, 66, 82, 255)

	handle_mouse_hover()
	handle_mouse_click()

	-- Draw button background
	draw.FilledRect(
		component.x + window.x + content_offset,
		component.y + window.y,
		component.x + component.width + window.x + content_offset,
		component.y + component.height + window.y
	)

	-- Draw button text
	if component.label and component.label ~= "" then
		draw.SetFont(component.font or font)
		local tw, th = draw.GetTextSize(component.label)

		draw.Color(236, 239, 244, 255)
		draw.Text(
			window.x + component.x + (component.width // 2) - (tw // 2) + content_offset,
			window.y + component.y + (component.height // 2) - (th // 2),
			component.label
		)
	end
end

local function draw_checkbox()
	local window = current_window_context
	assert(window, "Window context is nil!")

	local component = current_component
	local content_offset = get_content_area_offset()
	local check_char = "x"

	draw.SetFont(checkfont)
	local tw, th = draw.GetTextSize(check_char)

	-- Draw outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(
		window.x + component.x - OUTLINE_THICKNESS + content_offset,
		window.y + component.y - OUTLINE_THICKNESS,
		window.x + component.x + component.width + OUTLINE_THICKNESS + content_offset,
		window.y + component.y + component.height + OUTLINE_THICKNESS
	)

	draw.Color(67, 76, 94, 255)

	handle_mouse_hover()
	handle_mouse_click()

	-- Draw checkbox background
	draw.FilledRect(
		window.x + component.x + content_offset,
		window.y + component.y,
		window.x + component.x + component.width + content_offset,
		window.y + component.y + component.height
	)

	-- Draw checkbox and label
	local box_width = component.width // 10
	local box_height = component.height // 2
	local box_x = window.x + component.x + 4 + content_offset
	local box_y = window.y + component.y + (component.height // 2) - (box_height // 2)

	-- Checkbox outline
	draw.Color(236, 239, 244, 255)
	draw.FilledRect(box_x - 1, box_y - 1, box_x + box_width + 1, box_y + box_height + 1)

	-- Checkbox background
	draw.Color(163, 190, 140, 255)
	draw.FilledRect(box_x, box_y, box_x + box_width, box_y + box_height)

	-- Draw check mark if enabled
	if component.enabled then
		draw.SetFont(checkfont)
		draw.Color(0, 0, 0, 255)
		draw.Text(box_x + (box_width // 2) - (tw // 2), box_y + (box_height // 2) - (th // 2), check_char)
	end

	-- Draw label text
	draw.SetFont(window.font or font)
	local _, label_height = draw.GetTextSize(component.label)
	draw.Color(236, 239, 244, 255)
	draw.Text(box_x + box_width + 3, box_y + (box_height // 2) - (label_height // 2), component.label)
end

local function draw_tab_buttons(window)
	if #window.tabs <= 1 then
		return
	end

	for i, tab in ipairs(window.tabs) do
		local tab_x = window.x
		local tab_y = window.y + (i - 1) * (TAB_BUTTON_HEIGHT + TAB_BUTTON_MARGIN)
		-- Use window-specific active tab index (or 1 if it's a single tab window (no tabs basically))
		local is_active = (i == (window.active_tab_index or 1))
		local is_hovered = handle_tab_button_click(window, i)

		-- Draw tab button outline
		draw.Color(143, 188, 187, 255)
		draw.FilledRect(
			tab_x - OUTLINE_THICKNESS,
			tab_y - OUTLINE_THICKNESS,
			tab_x + TAB_BUTTON_WIDTH + OUTLINE_THICKNESS,
			tab_y + TAB_BUTTON_HEIGHT + OUTLINE_THICKNESS
		)

		-- Draw tab button background
		if is_active then
			draw.Color(76, 86, 106, 255) -- Active tab color
		elseif is_hovered then
			draw.Color(67, 76, 94, 255) -- Hovered tab color
		else
			draw.Color(59, 66, 82, 255) -- Normal tab color
		end

		draw.FilledRect(tab_x, tab_y, tab_x + TAB_BUTTON_WIDTH, tab_y + TAB_BUTTON_HEIGHT)

		-- Draw tab button text
		if tab.name and tab.name ~= "" then
			draw.SetFont(font)
			local tw, th = draw.GetTextSize(tab.name)
			draw.Color(236, 239, 244, 255)
			draw.Text(
				tab_x + (TAB_BUTTON_WIDTH // 2) - (tw // 2),
				tab_y + (TAB_BUTTON_HEIGHT // 2) - (th // 2),
				tab.name
			)
		end
	end
end

local function draw_slider()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return
	end

	local component = current_component
	local content_offset = get_content_area_offset()

	local slider_x = component.x + window.x + content_offset
	local slider_y = component.y + window.y
	local slider_w = component.width
	local slider_h = component.height

	-- Handle slider interaction
	handle_slider_drag()

	-- Calculate dimensions
	local knob_width = 10
	local track_height = 4
	local track_y = slider_y + (slider_h // 2) - (track_height // 2)

	-- Calculate knob position based on value
	local progress = (component.value - component.min) / (component.max - component.min)
	local knob_x = (slider_x + (progress * (slider_w - knob_width))) // 1

	-- Draw track background
	draw.Color(67, 76, 94, 255)
	draw.FilledRect(slider_x, track_y, slider_x + slider_w, track_y + track_height)

	-- Draw track fill (progress)
	draw.Color(129, 161, 193, 255)
	draw.FilledRect(slider_x, track_y, knob_x + (knob_width / 2), track_y + track_height)

	-- Draw knob outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(knob_x - 1, slider_y - 1, knob_x + knob_width + 1, slider_y + slider_h + 1)

	-- Draw knob
	if dragging_slider == component then
		draw.Color(76, 86, 106, 255) -- Dragging color
	elseif is_mouse_inside(knob_x, slider_y, knob_x + knob_width, slider_y + slider_h) then
		draw.Color(67, 76, 94, 255) -- Hover color
	else
		draw.Color(59, 66, 82, 255) -- Normal color
	end

	draw.FilledRect(knob_x, slider_y, knob_x + knob_width, slider_y + slider_h)

	-- Draw label if exists
	if component.label and component.label ~= "" then
		draw.SetFont(component.font or font)
		local tw, th = draw.GetTextSize(component.label)

		draw.Color(236, 239, 244, 255)
		draw.Text(slider_x, slider_y - th - 2, component.label)
	end

	-- Draw value text
	local value_text = string.format("%.1f", component.value)
	draw.SetFont(component.font or font)
	local value_tw, value_th = draw.GetTextSize(value_text)

	draw.Color(236, 239, 244, 255)
	draw.Text(slider_x + slider_w - value_tw, slider_y - value_th - 2, value_text)
end

local function draw_dropdown()
	local window = current_window_context
	assert(window, "Window context is nil!")

	local component = current_component
	local content_offset = get_content_area_offset()
	local x = window.x + component.x + content_offset
	local y = window.y + component.y

	draw.SetFont(component.font or font)
	local label_w, label_h = draw.GetTextSize(component.label)

	--- Uma puta gambiarra
	--- Mas to com preguiça de pensar em um jeito bom de fazer isso

	local height_offset = 0
	if component.label and component.label ~= "" then
		height_offset = label_h + 5
	end

	-- Draw main dropdown box outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(
		x - OUTLINE_THICKNESS,
		y - OUTLINE_THICKNESS - height_offset,
		x + component.width + OUTLINE_THICKNESS,
		y + component.height + OUTLINE_THICKNESS
	)

	--- Draw dropdown label
	draw.Color(236, 239, 244, 255)
	draw.Text(x + (component.width // 2) - (label_w // 2), y - (height_offset // 2) - (label_h // 2), component.label)

	-- Draw main dropdown box background
	draw.Color(59, 66, 82, 255)
	draw.FilledRect(x, y, x + component.width, y + component.height)

	-- Handle mouse clicks
	handle_mouse_click()

	-- Draw selected item text
	local selected = component.items[component.selected_index] or ""
	draw.SetFont(component.font or font)
	draw.Color(236, 239, 244, 255)
	local _, text_h = draw.GetTextSize(selected)
	draw.Text(x + 4, y + (component.height // 2) - (text_h // 2), selected)

	-- Draw dropdown arrow indicator
	draw.Color(236, 239, 244, 255)
	local arrow = component.expanded and "^" or "v" --- I wish i could use other characters, but i dont think TF2 BUILD supports emojis
	local arrow_w, arrow_h = draw.GetTextSize(arrow)
	draw.Text(x + component.width - arrow_w - 4, y + (component.height // 2) - (arrow_h // 2), arrow)

	-- Draw dropdown items if expanded
	if component.expanded then
		for i, item in ipairs(component.items) do
			local iy = y + component.height + (i - 1) * component.height

			-- Check if mouse is hovering over this item
			local is_hovered = is_mouse_inside(x, iy, x + component.width, iy + component.height)

			-- Draw item outline
			draw.Color(143, 188, 187, 255)
			draw.FilledRect(
				x - OUTLINE_THICKNESS,
				iy - OUTLINE_THICKNESS,
				x + component.width + OUTLINE_THICKNESS,
				iy + component.height + OUTLINE_THICKNESS
			)

			-- Draw item background
			if is_hovered then
				draw.Color(76, 86, 106, 255) -- Hover color
			else
				draw.Color(67, 76, 94, 255) -- Normal dropdown item color
			end
			draw.FilledRect(x, iy, x + component.width, iy + component.height)

			-- Draw item text
			draw.Color(236, 239, 244, 255)
			draw.Text(x + 4, iy + (component.height // 2) - (text_h // 2), item)

			local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
			if is_hovered and state and tick > last_keypress_tick then
				component.selected_index = i
				component.expanded = false
				if component.func then
					component.func(i, item)
				end
				last_keypress_tick = tick
				break
			end
		end
	end
end

local function draw_listbox()
	local window = current_window_context
	assert(window, "Window context is nil!")

	local component = current_component
	local content_offset = get_content_area_offset()
	local x = window.x + component.x + content_offset
	local y = window.y + component.y
	local item_height = 20
	local state, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)

	draw.Color(46, 52, 64, 255)
	draw.FilledRect(x, y, x + component.width, y + (item_height * #component.items))

	for i, item in ipairs(component.items) do
		local iy = y + (i - 1) * item_height
		if iy + item_height > y + component.height then
			break
		end

		local is_hovered = is_mouse_inside(x, iy, x + component.width, iy + item_height)
		local is_selected = (i == component.selected_index)

		if is_hovered then
			draw.Color(67, 76, 94, 255)
		elseif is_selected then
			draw.Color(76, 86, 106, 255)
		else
			draw.Color(59, 66, 82, 255)
		end

		if is_hovered and state and tick > last_keypress_tick then
			last_keypress_tick = tick
			component.selected_index = i
		end

		draw.FilledRect(x, iy, x + component.width, iy + item_height)
		draw.SetFont(component.font)
		draw.Color(236, 239, 244, 255)
		draw.Text(x + 4, iy + 2, item)
	end

	draw.Color(143, 188, 187, 255)
	draw.OutlinedRect(x, y, x + component.width, y + (item_height * #component.items))
end

local function draw_window()
	local window = current_window_context
	if not window then
		error("The window context is nil!")
		return
	end

	handle_window_drag()

	local content_offset = get_content_area_offset()

	-- Draw window outline
	draw.Color(143, 188, 187, 255)
	draw.FilledRect(
		window.x - OUTLINE_THICKNESS,
		window.y - OUTLINE_THICKNESS - ((window.header and window.header ~= "") and HEADER_SIZE or 0),
		window.x + window.width + OUTLINE_THICKNESS,
		window.y + window.height + OUTLINE_THICKNESS
	)

	if window.header and window.header ~= "" then
		draw.SetFont(font)
		draw.Color(0, 0, 0, 255)

		local text_width, text_height = draw.GetTextSize(window.header)
		draw.Text(
			window.x + (window.width // 2) - (text_width // 2),
			window.y - (HEADER_SIZE // 2) - (text_height // 2),
			window.header
		)
	end

	-- Draw window background
	draw.Color(46, 52, 64, 255)
	draw.FilledRect(window.x, window.y, window.x + window.width, window.y + window.height)

	-- Draw tab buttons if multiple tabs exist
	draw_tab_buttons(window)

	-- Draw content area background (if tabs exist)
	if #window.tabs > 1 then
		draw.Color(41, 46, 57, 255)
		draw.FilledRect(window.x + content_offset, window.y, window.x + window.width, window.y + window.height)
	end

	-- Draw components from active tab (use window-specific active tab)
	local active_tab_index = window.active_tab_index or 1
	-- Reset active tab if it's out of bounds for this window
	if active_tab_index > #window.tabs then
		active_tab_index = 1
		window.active_tab_index = 1
	end

	local current_tab = window.tabs[active_tab_index] or window.tabs[1]
	if current_tab then
		for _, component in pairs(current_tab.components) do
			current_component = component

			if component.type == COMPONENT_TYPES.BUTTON then
				draw_button()
			elseif component.type == COMPONENT_TYPES.CHECKBOX then
				draw_checkbox()
			elseif component.type == COMPONENT_TYPES.SLIDER then
				draw_slider()
			elseif component.type == COMPONENT_TYPES.DROPDOWN then
				draw_dropdown()
			elseif component.type == COMPONENT_TYPES.LISTBOX then
				draw_listbox()
			else
				-- Fallback to button rendering for unknown types
				draw_button()
			end
		end
	end

	for _, dd in ipairs(deferred_dropdowns) do
		local component = dd.component
		local window = dd.window
		local content_offset = get_content_area_offset()
		local x = window.x + component.x + content_offset
		local y = window.y + component.y
		local _, text_h = draw.GetTextSize(component.label or "")

		for i, item in ipairs(component.items) do
			local iy = y + component.height + (i - 1) * component.height
			local is_hovered = is_mouse_inside(x, iy, x + component.width, iy + component.height)

			draw.Color(143, 188, 187, 255)
			draw.FilledRect(
				x - OUTLINE_THICKNESS,
				iy - OUTLINE_THICKNESS,
				x + component.width + OUTLINE_THICKNESS,
				iy + component.height + OUTLINE_THICKNESS
			)

			if is_hovered then
				draw.Color(76, 86, 106, 255)
			else
				draw.Color(67, 76, 94, 255)
			end
			draw.FilledRect(x, iy, x + component.width, iy + component.height)

			draw.Color(236, 239, 244, 255)
			draw.Text(x + 4, iy + (component.height // 2) - (text_h // 2), item)
		end
	end
end

local function draw_all_windows()
	if not gui.IsMenuOpen() then
		return
	end

	local mouse = input.GetMousePos()
	local mx, my = table.unpack(mouse)
	dx, dy = mx - oldmx, my - oldmy

	for _, window in ipairs(windows) do
		current_window_context = window
		draw_window()
	end

	oldmx, oldmy = mx, my
	deferred_dropdowns = {}
end

-- =============================================================================
-- COMPONENT FACTORY FUNCTIONS
-- =============================================================================

local function create_button_component()
	---@type BUTTON
	local button = {
		type = COMPONENT_TYPES.BUTTON,
		font = font,
		height = 0,
		width = 0,
		label = "",
		x = 0,
		y = 0,
	}
	return button
end

local function create_checkbox_component()
	---@type CHECKBOX
	local checkbox = {
		x = 0,
		y = 0,
		width = 0,
		height = 0,
		label = "",
		enabled = false,
		type = COMPONENT_TYPES.CHECKBOX,
		func = nil, -- Will be set after creation
	}

	-- Set the toggle function
	checkbox.func = function()
		checkbox.enabled = not checkbox.enabled
	end

	return checkbox
end

local function create_slider_component()
	---@type SLIDER
	local slider = {
		type = COMPONENT_TYPES.SLIDER,
		font = font,
		height = 20,
		width = 150,
		label = "",
		x = 0,
		y = 0,
		min = 0,
		max = 100,
		value = 50,
		func = nil, -- Callback function called when value changes
	}
	return slider
end

local function create_dropdown_component()
	---@type DROPDOWN
	local dropdown = {
		type = COMPONENT_TYPES.DROPDOWN,
		font = font,
		label = "",
		x = 0,
		y = 0,
		width = 150,
		height = 20,
		items = {}, -- List of strings
		selected_index = 1,
		expanded = false,
		func = nil,
	}
	return dropdown
end

local function create_listbox_component()
	---@type LISTBOX
	local listbox = {
		type = COMPONENT_TYPES.LISTBOX,
		font = font,
		label = "",
		x = 0,
		y = 0,
		width = 150,
		height = 100,
		items = {},
		selected_index = 1,
		func = nil,
	}
	return listbox
end

-- =============================================================================
-- COMPONENT SIZE CALCULATION
-- =============================================================================

local function calculate_component_sizes()
	for _, window in ipairs(windows) do
		for _, tab in ipairs(window.tabs) do
			for _, component in ipairs(tab.components) do
				if component.width == 0 and component.height == 0 then
					if component.label and component.label ~= "" then
						draw.SetFont(window.font or font)
						local tw, th = draw.GetTextSize(component.label)
						component.width = tw + 20
						component.height = th + 5
					else
						component.width = 100
						component.height = 20
					end
				end
			end
		end
	end
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

---@class MENU
local menu = {}

---@return WINDOW
function menu:make_window()
	---@type WINDOW
	local window = {
		x = 0,
		y = 0,
		width = 0,
		height = 0,
		tabs = {},
		active_tab_index = 1, -- Each window now has its own active tab index
	}

	table.insert(windows, window)
	current_window_context = windows[#windows]
	return windows[#windows]
end

---@param name string?
---@return integer? Returns the tab index relative to the current window context
function menu:make_tab(name)
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return nil
	end

	local new_tab = {
		name = name or "",
		components = {},
	}

	table.insert(window.tabs, new_tab)
	return #window.tabs
end

---@return BUTTON?
function menu:make_button()
	local window = current_window_context
	if not window then
		error("The window context is nil!")
		return nil
	end

	local button = create_button_component()
	return make_new_component(button)
end

---@return CHECKBOX?
function menu:make_checkbox()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return nil
	end

	local checkbox = create_checkbox_component()
	return make_new_component(checkbox)
end

---@return SLIDER?
function menu:make_slider()
	local window = current_window_context
	if not window then
		error("Current window context is nil!")
		return nil
	end

	local slider = create_slider_component()
	return make_new_component(slider)
end

---@return DROPDOWN?
function menu:make_dropdown()
	if not current_window_context then
		return nil
	end
	local dropdown = create_dropdown_component()
	return make_new_component(dropdown)
end

---@return LISTBOX?
function menu:make_listbox()
	if not current_window_context then
		return nil
	end
	local listbox = create_listbox_component()
	return make_new_component(listbox)
end

function menu:register()
	calculate_component_sizes() --- if we have any component with 0 width & height so they dont waste pc resources drawing nothing
	callbacks.Register("Draw", draw_id, draw_all_windows)
end

function menu.unload()
	menu = nil
	font = nil
	package.loaded["nmenu"] = nil
	input.SetMouseInputEnabled(false)
	callbacks.Unregister("Draw", draw_id)
end

return menu
