---@meta

--- version 0.1
--- any component with width == 0 & height == 0 gets a width and height assigned at menu:register

---@class TAB_COMPONENTS

---@class TAB
---@field name string|''
---@field components table<integer, BUTTON|CHECKBOX|SLIDER|DROPDOWN|LISTBOX>}
---@field draw_func fun(window: WINDOW, current_tab: TAB, content_offset: integer|0)?

---@class WINDOW
---@field public x integer The 'X' coordinate of the window (default: 0)
---@field public y integer The 'Y' coordinate of the window (default: 0)
---@field public width integer The 'width' of the window (default: 0)
---@field public height integer The 'height' of the window (default: 0)
---@field public tabs table<integer, TAB> The tabs of the window (default: { [1]: {} })
---@field public font Font? The font to be used (default: "TF2 BUILD")
---@field public header string? The window's title bar text
---@field public active_tab_index integer The active tab index (default: 1) | Doesn't need to be changed, NMENU handles it for you

---@class BUTTON
---@field public label string|'' The button's text
---@field public width integer The 'width' size of the button (default: text width + 20 or 100)
---@field public height integer The 'height' size of the button (default: text height + 5 or 20)
---@field public x integer The 'X' coordinate of the button (default: 0)
---@field public y integer The 'Y' coordinate of the button (default: 0)
---@field public func function? The callback of the button when clicked

---@class CHECKBOX
---@field public x integer The 'X' coordinate of the window (default: 0)
---@field public y integer The 'Y' coordinate of the window (default: 0)
---@field public width integer The 'width' of the window (default: 100)
---@field public height integer The 'height' of the window (default: 20)
---@field public label string|'' The text in the checkbox (default: '')
---@field public enabled boolean The 'checked' state of the checkbox (default: false)
---@field public func function? The callback triggered when toggled

---@class SLIDER
---@field public font Font?
---@field public height integer
---@field public width integer
---@field public label string
---@field public x integer
---@field public y integer
---@field public min number
---@field public max number
---@field public value number
---@field public func function?

---@class DROPDOWN
---@field public font Font? The font used for the dropdown
---@field public label string|'' The label text (optional)
---@field public x integer The 'X' coordinate (default: 0)
---@field public y integer The 'Y' coordinate (default: 0)
---@field public width integer The 'width' of the dropdown (default: 150)
---@field public height integer The 'height' of the dropdown (default: 20)
---@field public items string[] The list of selectable items
---@field public selected_index integer The currently selected item's index (default: 1)
---@field public expanded boolean Whether the dropdown is currently expanded (default: false)
---@field public func fun(index: integer, value: string)? Called when a new item is selected

---@class LISTBOX
---@field public font Font? The font used for the listbox
---@field public label string|'' Optional label
---@field public x integer The 'X' coordinate (default: 0)
---@field public y integer The 'Y' coordinate (default: 0)
---@field public width integer The 'width' of the listbox (default: 150)
---@field public height integer The 'height' of the listbox (default: 100)
---@field public items string[] The list of selectable items
---@field public selected_index integer The index of the currently selected item (default: 1)
---@field public func fun(index: integer, value: string)? Called when an item is selected

---@class MENU
local menu = {}

--- Registers the callback necessary to make the menu draw
function menu:register() end

--- This sets the current context to be the window created
---@return WINDOW
function menu:make_window() end

---@return integer? Returns the tab index relative to the current window context
---@param name string
function menu:make_tab(name) end

---@return BUTTON?
function menu:make_button() end

---@return CHECKBOX?
function menu:make_checkbox() end

---@return SLIDER?
function menu:make_slider() end

---@return DROPDOWN?
function menu:make_dropdown() end

---@return LISTBOX?
function menu:make_listbox() end

--- Unload function, you should register this as a callback
function menu.unload() end

---@param tab_index integer
---@param draw_func fun(window: WINDOW, current_tab: TAB, content_offset: integer|0)?
function menu:set_tab_draw_function(tab_index, draw_func) end

return menu
