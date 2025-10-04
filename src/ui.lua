---@class Context
---@field mouseX integer
---@field mouseY integer
---@field mouseDown boolean
---@field mouseReleased boolean
---@field mousePressed boolean
---@field tick integer
---@field lastPressedTick integer
---@field windowX integer
---@field windowY integer

local theme = {
    bg_light = { 45, 45, 45 },
    bg = { 35, 35, 35 },
    bg_dark = { 30, 30, 30 },
    primary = { 143, 188, 187 },
    success = { 69, 255, 166 },
    fail = { 255, 69, 69 },
}

local thickness = 1    --- outline thickness
local header_size = 25 --- title height
local tab_section_width = 100

local max_objects_per_column = 9
local column_spacing = 10
local row_spacing = 5
local element_margin = 5

---@class GuiWindow
local window = {
    dragging = false,
    mx = 0,
    my = 0,
    x = 0,
    y = 0,
    w = 0,
    h = 0,
    title = "",
    tabs = {},
    current_tab = 1,
}

local lastPressedTick = 0
local font = draw.CreateFont("TF2 BUILD", 12, 400, FONTFLAG_ANTIALIAS | FONTFLAG_CUSTOM)
local white_texture = draw.CreateTextureRGBA(string.rep(string.char(255, 255, 255, 255), 4), 2, 2)

---@param texture TextureID
---@param centerX integer
---@param centerY integer
---@param radius integer
---@param segments integer
local function DrawFilledCircle(texture, centerX, centerY, radius, segments)
    local vertices = {}

    for i = 0, segments do
        local angle = (i / segments) * math.pi * 2
        local x = centerX + math.cos(angle) * radius
        local y = centerY + math.sin(angle) * radius
        vertices[i + 1] = { x, y, 0, 0 }
    end

    draw.TexturedPolygon(texture, vertices, false)
end

local function draw_tab_button(parent, x, y, width, height, label, i)
    local mousePos = input.GetMousePos()
    local mx, my = mousePos[1], mousePos[2]
    local mouseInside = mx >= x and mx <= x + width
        and my >= y and my <= y + height

    --draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
    --draw.FilledRect(x - thickness, y - thickness, x + width + thickness, y + height + thickness)

    if (mouseInside and input.IsButtonDown(E_ButtonCode.MOUSE_LEFT)) then
        draw.Color(theme.bg_light[1], theme.bg_light[2], theme.bg_light[3], 255)
    elseif (mouseInside) then
        draw.Color(theme.bg[1], theme.bg[2], theme.bg[3], 255)
    else
        draw.Color(theme.bg_dark[1], theme.bg_dark[2], theme.bg_dark[3], 255)
    end
    draw.FilledRect(x, y, x + width, y + height)

    if (parent.current_tab == i) then
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.FilledRect(x + 2, y + 2, x + 4, y + height - 2)
    end

    local tw, th = draw.GetTextSize(label)
    local tx, ty
    tx = (x + (width * 0.5) - (tw * 0.5)) // 1
    ty = (y + (height * 0.5) - (th * 0.5)) // 1

    draw.Color(242, 242, 242, 255)
    draw.Text(tx, ty, label)

    local pressed, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_FIRST)

    if (mouseInside and pressed and tick > lastPressedTick) then
        parent.current_tab = i
    end
end

local function hsv_to_rgb(h, s, v)
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)

    i = i % 6

    if i == 0 then
        r, g, b = v, t, p
    elseif i == 1 then
        r, g, b = q, v, p
    elseif i == 2 then
        r, g, b = p, v, t
    elseif i == 3 then
        r, g, b = p, q, v
    elseif i == 4 then
        r, g, b = t, p, v
    elseif i == 5 then
        r, g, b = v, p, q
    end

    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

function window.Draw(self)
    if (not gui.IsMenuOpen()) then
        return
    end

    local x, y = self.x, self.y
    local tab = self.tabs[self.current_tab]
    local w = (tab and tab.w or 200)
    local h = (tab and tab.h or 200)
    local title = self.title

    local mousePressed, tick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
    local mousePos = input.GetMousePos()

    local dx, dy = mousePos[1] - self.mx, mousePos[2] - self.my
    if (self.dragging) then
        self.x = self.x + dx
        self.y = self.y + dy
    end

    draw.SetFont(font)

    local numTabs = #self.tabs
    local extra_width = (numTabs > 1) and tab_section_width or 0

    local total_w = w + extra_width

    -- draw window outline & background
    draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
    draw.OutlinedRect(x - thickness, y - thickness, x + total_w + thickness, y + h + thickness)

    draw.Color(theme.bg_dark[1], theme.bg_dark[2], theme.bg_dark[3], 255)
    draw.FilledRect(x, y, x + total_w, y + h)

    -- draw tabs if needed
    if (numTabs > 1) then
        draw.Color(theme.bg_light[1], theme.bg_light[2], theme.bg_light[3], 255)
        draw.FilledRect(x, y, x + tab_section_width, y + h)

        local btnx, btny = x, y
        for i, t in ipairs(self.tabs) do
            draw_tab_button(self, btnx, btny, tab_section_width, 25, t.name, i)
            btny = btny + 25
        end
    end

    -- header
    if (title and #title > 0) then
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.FilledRect(x - thickness, y - header_size, x + total_w + thickness, y - thickness)
        draw.Color(0, 0, 0, 255)
        draw.FilledRectFade(x - thickness, y - header_size, x + total_w + thickness, y - thickness, 200, 0, false)

        local tw, th = draw.GetTextSize(title)
        local tx = (x - thickness + total_w * 0.5 - tw * 0.5) // 1
        local ty = (y - thickness - header_size * 0.5 - th * 0.5) // 1

        draw.Color(242, 242, 242, 255)
        draw.Text(tx, ty, title)

        -- dragging check
        if (mousePos[1] >= x and mousePos[1] <= x + total_w) and (mousePos[2] >= y - header_size and mousePos[2] <= y) then
            local state, thistick = input.IsButtonPressed(E_ButtonCode.MOUSE_LEFT)
            if (state and thistick > lastPressedTick) then
                self.dragging = true
            end
        end

        if (input.IsButtonReleased(E_ButtonCode.MOUSE_LEFT) and self.dragging) then
            self.dragging = false
        end
    end

    -- adjust context X for drawing objs
    local content_x = x + extra_width

    local context = {
        mouseX = mousePos[1],
        mouseY = mousePos[2],
        mouseDown = input.IsButtonDown(E_ButtonCode.MOUSE_LEFT),
        mouseReleased = input.IsButtonReleased(E_ButtonCode.MOUSE_LEFT),
        mousePressed = mousePressed,
        tick = tick,
        lastPressedTick = lastPressedTick,
        windowX = content_x,
        windowY = y,
    }

    if (tab) then
        for i = #tab.objs, 1, -1 do
            local obj = tab.objs[i]
            if obj then
                obj:Draw(context)
            end
        end
    end

    lastPressedTick = tick
    self.mx, self.my = mousePos[1], mousePos[2]
end

function window:SetCurrentTab(tab_index)
    if (tab_index > #self.tabs or tab_index < 0) then
        error(string.format("Invalid tab index! Received %s", tab_index))
        return false
    end

    self.current_tab = tab_index
    return true
end

function window:CreateTab(tab_name)
    if (#self.tabs == 1 and self.tabs[1].name == "") then
        --- replace the default tab
        --- just in case we have more than 1 tabs
        self.tabs[1].name = tab_name
        return 1
    else
        self.tabs[#self.tabs + 1] = {
            name = tab_name,
            objs = {}
        }
        return #self.tabs
    end
end

--- recalculates positions of all objs in all tabs
--- and adjusts window size to fit contents
function window:RecalculateLayout(tab_index)
    if not tab_index or not self.tabs[tab_index] then return end
    local tab = self.tabs[tab_index]

    local col, row = 0, 0
    local col_widths, col_heights = {}, {}
    local current_col_width = 0

    --- calculate positions and track column dimensions
    for i, obj in ipairs(tab.objs) do
        --- track the maximum width in current column
        if obj.w > current_col_width then
            current_col_width = obj.w
        end

        -- calculate x position using previously completed column widths
        local x_offset = element_margin
        for j = 1, col do
            x_offset = x_offset + (col_widths[j] or 0) + column_spacing
        end
        obj.x = x_offset

        --- calc y position
        obj.y = element_margin + row * (obj.h + row_spacing)

        row = row + 1
        if row >= max_objects_per_column then
            col_widths[col + 1] = current_col_width
            col_heights[col + 1] = row * (obj.h + row_spacing)

            --- move to next column
            row = 0
            col = col + 1
            current_col_width = 0
        end
    end

    --- handle the last column if it has elements
    if row > 0 and #tab.objs > 0 then
        col_widths[col + 1] = current_col_width
        col_heights[col + 1] = row * (tab.objs[#tab.objs].h + row_spacing)
    end

    --- get total tab width
    local tab_w = element_margin * 2 --- left and right margins
    for i, w in ipairs(col_widths) do
        tab_w = tab_w + w
        if i < #col_widths then
            tab_w = tab_w + column_spacing
        end
    end

    --- calculate total tab height (maximum of all column heights)
    local tab_h = 0
    for _, h in ipairs(col_heights) do
        if h > tab_h then tab_h = h end
    end
    tab_h = tab_h + element_margin * 2

    --- save tab size
    tab.w = tab_w
    tab.h = tab_h
end

function window:InsertElement(object, tab_index)
    tab_index = tab_index or self.current_tab or 1
    if (tab_index > #self.tabs or tab_index < 0) then
        error(string.format("Invalid tab index! Received %s", tab_index))
        return false
    end

    local tab = self.tabs[tab_index]
    tab.objs[#tab.objs + 1] = object
    self:RecalculateLayout(tab_index)
    return true
end

---@param func fun(checked: boolean)?
function window:CreateToggle(tab_index, width, height, label, checked, func)
    local btn = {
        x = 0,
        y = 0,
        w = width,
        h = height,
        label = label,
        func = func,
        checked = checked,
    }

    ---@param context Context
    function btn:Draw(context)
        local bx, by, bw, bh
        bx = self.x + context.windowX
        by = self.y + context.windowY
        bw = self.w
        bh = self.h

        local mx, my = context.mouseX, context.mouseY
        local mouseInside = mx >= bx and mx <= bx + bw
            and my >= by and my <= by + bh

        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.OutlinedRect(bx - thickness, by - thickness, bx + bw + thickness, by + bh + thickness)

        if (mouseInside and context.mouseDown) then
            draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        elseif (mouseInside) then
            draw.Color(theme.bg_light[1], theme.bg_light[2], theme.bg_light[3], 255)
        else
            draw.Color(theme.bg[1], theme.bg[2], theme.bg[3], 255)
        end
        draw.FilledRect(bx, by, bx + bw, by + bh)

        local tw, th = draw.GetTextSize(self.label)
        local tx, ty
        tx = bx + 2
        ty = (by + bh * 0.5 - th * 0.5) // 1

        draw.Color(242, 242, 242, 255)
        draw.Text(tx, ty, label)

        local circle_x = bx + bw - 10
        local circle_y = (by + bh * 0.5) // 1
        local radius = 8

        if (btn.checked) then
            draw.Color(theme.success[1], theme.success[2], theme.success[3], 255)
        else
            draw.Color(theme.fail[1], theme.fail[2], theme.fail[3], 255)
        end

        DrawFilledCircle(white_texture, circle_x, circle_y, radius, 4)

        if (mouseInside and context.mousePressed and context.tick > context.lastPressedTick) then
            btn.checked = not btn.checked

            if (func) then
                func(btn.checked)
            end
        end
    end

    self:InsertElement(btn, tab_index or self.current_tab)
    return btn
end

---@param func fun(value: number)?
function window:CreateSlider(tab_index, width, height, label, min, max, currentvalue, func)
    local slider = {
        x = 0,
        y = 0,
        w = width,
        h = height,
        label = label,
        func = func,
        min = min,
        max = max,
        value = currentvalue
    }

    ---@param context Context
    function slider:Draw(context)
        local bx, by, bw, bh
        bx = self.x + context.windowX
        by = self.y + context.windowY
        bw = self.w
        bh = self.h

        local mx, my = context.mouseX, context.mouseY
        local mouseInside = mx >= bx and mx <= bx + bw
            and my >= by and my <= by + bh

        --- draw outline
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.OutlinedRect(bx - thickness, by - thickness, bx + bw + thickness, by + bh + thickness)

        --- draw background based on mouse state
        if (mouseInside and context.mouseDown) then
            draw.Color(theme.bg_light[1], theme.bg_light[2], theme.bg_light[3], 255)
        elseif (mouseInside) then
            draw.Color(theme.bg[1], theme.bg[2], theme.bg[3], 255)
        else
            draw.Color(theme.bg_dark[1], theme.bg_dark[2], theme.bg_dark[3], 255)
        end
        draw.FilledRect(bx, by, bx + bw, by + bh)

        -- calculate percentage for the slider fill
        local percent = (self.value - self.min) / (self.max - self.min)
        percent = math.max(0, math.min(1, percent)) --- clamp it ;)

        --- draw slider fill
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.FilledRect(bx, by, (bx + (bw * percent)) // 1, by + bh)

        --- draw label text
        local tw, th = draw.GetTextSize(self.label)
        local tx, ty
        tx = bx + 2
        ty = (by + bh * 0.5 - th * 0.5) // 1
        draw.Color(242, 242, 242, 255)
        draw.TextShadow(tx + 2, ty, self.label)

        tw = draw.GetTextSize(string.format("%.0f", self.value))
        tx = bx + bw - tw - 2
        draw.TextShadow(tx, ty, string.format("%.0f", self.value))

        --- handle mouse interaction
        if (mouseInside and context.mousePressed and context.tick > context.lastPressedTick) then
            self.isDragging = true
        end

        --- continue dragging even if mouse is outside the slider
        if (self.isDragging and context.mouseDown) then
            --- update slider value based on mouse position
            local mousePercent = (mx - bx) / bw
            mousePercent = math.max(0, math.min(1, mousePercent))
            self.value = self.min + (self.max - self.min) * mousePercent

            if (self.func) then
                self.func(self.value)
            end
        elseif (not context.mouseDown) then
            --- stop dragging when mouse is released
            self.isDragging = false
        end
    end

    self:InsertElement(slider, tab_index or self.current_tab)
    return slider
end

---@param func fun(value: number)?
function window:CreateHueSlider(tab_index, width, height, label, currentvalue, func)
    local slider = {
        x = 0,
        y = 0,
        w = width,
        h = height,
        label = label,
        func = func,
        min = 0,
        max = 360,
        value = currentvalue
    }

    ---@param context Context
    function slider:Draw(context)
        local bx, by, bw, bh
        bx = self.x + context.windowX
        by = self.y + context.windowY
        bw = self.w
        bh = self.h

        local mx, my = context.mouseX, context.mouseY
        local mouseInside = mx >= bx and mx <= bx + bw
            and my >= by and my <= by + bh

        --- draw outline
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.OutlinedRect(bx - thickness, by - thickness, bx + bw + thickness, by + bh + thickness)

        --- draw background
        draw.Color(theme.bg_dark[1], theme.bg_dark[2], theme.bg_dark[3], 255)
        draw.FilledRect(bx, by, bx + bw, by + bh)

        -- calculate percentage for the slider indicator
        local percent = (self.value - self.min) / (self.max - self.min)
        percent = math.max(0, math.min(1, percent))

        --- draw slider indicator line
        local indicator_x = (bx + (bw * percent)) // 1
        if (self.value == 360) then
            draw.Color(255, 255, 255, 255)
        else
            local r, g, b = hsv_to_rgb(self.value / 360, 1.0, 1.0)
            draw.Color(r, g, b, 255)
        end
        draw.FilledRect(bx, (by + bh * 0.6) // 1, indicator_x, by + bh)

        --- draw label text with shadow for better visibility
        local tw, th = draw.GetTextSize(self.label)
        local tx, ty
        tx = bx + 2
        ty = by + 2

        -- Draw main text
        draw.Color(242, 242, 242, 255)
        draw.TextShadow(tx, ty, self.label)

        --- handle mouse interaction
        if (mouseInside and context.mousePressed and context.tick > context.lastPressedTick) then
            self.isDragging = true
        end

        --- continue dragging even if mouse is outside the slider
        if (self.isDragging and context.mouseDown) then
            --- update slider value based on mouse position
            local mousePercent = (mx - bx) / bw
            mousePercent = math.max(0, math.min(1, mousePercent))
            self.value = self.min + (self.max - self.min) * mousePercent

            if (self.func) then
                self.func(self.value)
            end
        elseif (not context.mouseDown) then
            --- stop dragging when mouse is released
            self.isDragging = false
        end
    end

    self:InsertElement(slider, tab_index or self.current_tab)
    return slider
end

---@param func fun(value: number)?
function window:CreateAccurateSlider(tab_index, width, height, label, min, max, currentvalue, func)
    local slider = {
        x = 0,
        y = 0,
        w = width,
        h = height,
        label = label,
        func = func,
        min = min,
        max = max,
        value = currentvalue
    }

    ---@param context Context
    function slider:Draw(context)
        local bx, by, bw, bh
        bx = self.x + context.windowX
        by = self.y + context.windowY
        bw = self.w
        bh = self.h

        local mx, my = context.mouseX, context.mouseY
        local mouseInside = mx >= bx and mx <= bx + bw
            and my >= by and my <= by + bh

        --- draw outline
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.OutlinedRect(bx - thickness, by - thickness, bx + bw + thickness, by + bh + thickness)

        --- draw background based on mouse state
        if (mouseInside and context.mouseDown) then
            draw.Color(theme.bg_light[1], theme.bg_light[2], theme.bg_light[3], 255)
        elseif (mouseInside) then
            draw.Color(theme.bg[1], theme.bg[2], theme.bg[3], 255)
        else
            draw.Color(theme.bg_dark[1], theme.bg_dark[2], theme.bg_dark[3], 255)
        end
        draw.FilledRect(bx, by, bx + bw, by + bh)

        -- calculate percentage for the slider fill
        local percent = (self.value - self.min) / (self.max - self.min)
        percent = math.max(0, math.min(1, percent)) --- clamp it ;)

        --- draw slider fill
        draw.Color(theme.primary[1], theme.primary[2], theme.primary[3], 255)
        draw.FilledRect(bx, by, (bx + (bw * percent)) // 1, by + bh)

        --- draw label text
        local tw, th = draw.GetTextSize(self.label)
        local tx, ty
        tx = bx + 2
        ty = (by + bh * 0.5 - th * 0.5) // 1
        draw.Color(242, 242, 242, 255)
        draw.TextShadow(tx + 2, ty, self.label)

        tw = draw.GetTextSize(string.format("%f", self.value))
        tx = bx + bw - tw - 2
        draw.TextShadow(tx, ty, string.format("%f", self.value))

        --- handle mouse interaction
        if (mouseInside and context.mousePressed and context.tick > context.lastPressedTick) then
            self.isDragging = true
        end

        --- continue dragging even if mouse is outside the slider
        if (self.isDragging and context.mouseDown) then
            --- update slider value based on mouse position
            local mousePercent = (mx - bx) / bw
            mousePercent = math.max(0, math.min(1, mousePercent))
            self.value = self.min + (self.max - self.min) * mousePercent

            if (self.func) then
                self.func(self.value)
            end
        elseif (not context.mouseDown) then
            --- stop dragging when mouse is released
            self.isDragging = false
        end
    end

    self:InsertElement(slider, tab_index or self.current_tab)
    return slider
end

function window:CreateLabel(tab_index, width, height, text, func)
    local label = {
        x = 0,
        y = 0,
        w = width,
        h = height,
        text = text,
    }

    ---@param context Context
    function label:Draw(context)
        local x, y, tw, th

        tw, th = draw.GetTextSize(self.text)

        x = (context.windowX + self.x + (self.w * 0.5) - (tw * 0.5)) // 1
        y = (context.windowY + self.y + (self.h * 0.5) - (th * 0.5)) // 1
        draw.Color(255, 255, 255, 255)
        draw.TextShadow(x, y, tostring(text))
    end

    self:InsertElement(label, tab_index or self.current_tab)
    return label
end

---@return GuiWindow
function window.New(tbl)
    local newWindow = tbl or {}
    setmetatable(newWindow, { __index = window })
    newWindow.tabs[1] = { name = "", objs = {} }
    return newWindow
end

function window.Unload()
    draw.DeleteTexture(white_texture)
end

return window
