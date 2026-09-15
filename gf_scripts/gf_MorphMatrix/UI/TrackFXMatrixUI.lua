-- @noindex

local source_path = debug.getinfo(1, "S").source:sub(2)
local module_root = source_path:match("^(.*[\\/])UI[\\/][^\\/]+$")
local default_preset_directory = module_root and module_root .. "User Presets\\" or ""

local TrackFXMatrixUI = {}
TrackFXMatrixUI.__index = TrackFXMatrixUI

local function sorted_parameter_indices(parameters)
    local indices = {}
    for parameter_index in pairs(parameters) do
        indices[#indices + 1] = parameter_index
    end
    table.sort(indices)
    return indices
end

local function descriptor_display_name(descriptor)
    if type(descriptor.instance_name) == "string" and descriptor.instance_name ~= "" then
        return descriptor.instance_name
    end
    if descriptor.plugin_identity and descriptor.plugin_identity.factory_name then
        return descriptor.plugin_identity.factory_name
    end
    return "Track FX"
end

local function format_descriptor(descriptor)
    local location
    if descriptor.track_number == -1 then
        location = "Master"
    elseif type(descriptor.track_number) == "number" then
        location = "Track " .. tostring(descriptor.track_number)
    end

    if type(descriptor.track_name) == "string" and descriptor.track_name ~= "" then
        location = location and location .. ": " .. descriptor.track_name or descriptor.track_name
    end

    local occurrence = type(descriptor.plugin_occurrence) == "number"
            and "  [" .. tostring(descriptor.plugin_occurrence) .. "]"
        or ""
    if location then
        return descriptor_display_name(descriptor) .. "  [" .. location .. "]" .. occurrence
    end
    return descriptor_display_name(descriptor) .. occurrence
end

local UI_STATE_SECTION = "gf_MorphMatrix_TrackFX_UI"
local CORNER_COLORS = {
    0xFF7655FF,
    0x53D8D7FF,
    0xB8E26DFF,
    0xF4C95DFF,
}

local COLORS = {
    background = 0x17191CFF,
    panel = 0x202328FF,
    panel_alt = 0x282C32FF,
    panel_highlight = 0x30363EFF,
    line = 0x454B54FF,
    grid = 0x58616AFF,
    text = 0xF5F1E8FF,
    muted = 0x9CA4ABFF,
    dim = 0x68717AFF,
    cursor = 0xFFF1D1FF,
    cursor_shadow = 0x0E1013FF,
    active = 0xFF7655FF,
    cool = 0x53D8D7FF,
    danger = 0xFF6B70FF,
    link = 0x66D487FF,
    unlink = 0xEA6B73FF,
    unlink_bright = 0xFF4F5EFF,
    unlocked = 0x53D8D7FF,
    locked = 0xF4C95DFF,
}

local TOP_BUTTON_WIDTH = 138
local TOP_BUTTON_HEIGHT = 30
local TOP_BUTTON_GAP = 10
local TOP_GRID_WIDTH = TOP_BUTTON_WIDTH * 3 + TOP_BUTTON_GAP * 2
local TOP_GRID_HEIGHT = TOP_BUTTON_HEIGHT * 2 + TOP_BUTTON_GAP
local TOP_GRID_WORKSPACE_GAP = 12
local MATRIX_GRID_STEPS = 15
local MATRIX_GLOW_RADIUS = 0.32
local MATRIX_GLOW_BRIGHTNESS = 2.0
local INACTIVE_CORNER_ICON_ALPHA = 165
local LABEL_BUTTON_FEEDBACK_DURATION = 0.3
local LINKED_BUTTON_OPACITY = 175

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function blend_colors(first, second, amount)
    amount = clamp(amount, 0, 1)
    local first_red = (first >> 24) & 0xFF
    local first_green = (first >> 16) & 0xFF
    local first_blue = (first >> 8) & 0xFF
    local second_red = (second >> 24) & 0xFF
    local second_green = (second >> 16) & 0xFF
    local second_blue = (second >> 8) & 0xFF
    local red = math.floor(first_red + (second_red - first_red) * amount + 0.5)
    local green = math.floor(first_green + (second_green - first_green) * amount + 0.5)
    local blue = math.floor(first_blue + (second_blue - first_blue) * amount + 0.5)
    return (red << 24) | (green << 16) | (blue << 8) | 0xFF
end

local function matrix_cursor_color(x, y)
    local top = blend_colors(CORNER_COLORS[1], CORNER_COLORS[2], x)
    local bottom = blend_colors(CORNER_COLORS[3], CORNER_COLORS[4], x)
    return blend_colors(top, bottom, y)
end

local function parameter_clamp_bounds(parameter)
    local minimum = type(parameter.clamp_min) == "number"
            and clamp(parameter.clamp_min, 0, 1)
        or 0
    local maximum = type(parameter.clamp_max) == "number"
            and clamp(parameter.clamp_max, 0, 1)
        or 1
    if minimum > maximum then
        return 0, 1
    end
    return minimum, maximum
end

local function color_with_alpha(color, alpha)
    return (color & 0xFFFFFF00) | math.floor(clamp(alpha, 0, 255))
end

local function color_luminance(color)
    local function linear_channel(channel)
        channel = channel / 255
        return channel <= 0.04045
                and channel / 12.92
            or ((channel + 0.055) / 1.055) ^ 2.4
    end

    local red = linear_channel((color >> 24) & 0xFF)
    local green = linear_channel((color >> 16) & 0xFF)
    local blue = linear_channel((color >> 8) & 0xFF)
    return red * 0.2126 + green * 0.7152 + blue * 0.0722
end

local function contrast_ratio(first, second)
    local first_luminance = color_luminance(first)
    local second_luminance = color_luminance(second)
    local brighter = math.max(first_luminance, second_luminance)
    local darker = math.min(first_luminance, second_luminance)
    return (brighter + 0.05) / (darker + 0.05)
end

local function composite_button_color(color, alpha)
    local opacity = clamp(alpha, 0, 255) / 255
    local background_red = (COLORS.background >> 24) & 0xFF
    local background_green = (COLORS.background >> 16) & 0xFF
    local background_blue = (COLORS.background >> 8) & 0xFF
    local red = (color >> 24) & 0xFF
    local green = (color >> 16) & 0xFF
    local blue = (color >> 8) & 0xFF
    red = math.floor(red * opacity + background_red * (1 - opacity) + 0.5)
    green = math.floor(green * opacity + background_green * (1 - opacity) + 0.5)
    blue = math.floor(blue * opacity + background_blue * (1 - opacity) + 0.5)
    return (red << 24) | (green << 16) | (blue << 8) | 0xFF
end

local function readable_button_foreground(accent, alpha, enabled)
    local surface = composite_button_color(accent or COLORS.muted, alpha)
    if not enabled and contrast_ratio(surface, COLORS.muted) >= 3 then
        return COLORS.muted
    end

    local dark_foreground = COLORS.background
    local light_foreground = COLORS.text
    return contrast_ratio(surface, dark_foreground) >= contrast_ratio(surface, light_foreground)
            and dark_foreground
        or light_foreground
end

local function count_parameters(parameters)
    local count = 0
    for _ in pairs(parameters or {}) do
        count = count + 1
    end
    return count
end

local function parameter_corner_is_saved(parameter, corner_id)
    return type(parameter.corner_saved) == "table"
        and parameter.corner_saved[corner_id] == true
end

local function corner_has_saved_mapping(snapshot, corner_id)
    for _, parameter in pairs(snapshot.parameters or {}) do
        if not parameter.bypassed and parameter_corner_is_saved(parameter, corner_id) then
            return true
        end
    end
    return false
end

local function get_ext_state(api, key)
    if type(api) ~= "table" or type(api.GetExtState) ~= "function" then
        return ""
    end
    return api.GetExtState(UI_STATE_SECTION, key) or ""
end

local function set_ext_state(api, key, value)
    if type(api) == "table" and type(api.SetExtState) == "function" then
        api.SetExtState(UI_STATE_SECTION, key, value, true)
    end
end

local function now(api)
    if type(api) == "table" and type(api.time_precise) == "function" then
        return api.time_precise()
    end
    return os.clock()
end

local function imgui_member(imgui, name)
    local ok, value = pcall(function()
        return imgui[name]
    end)
    if ok then
        return value
    end
    return nil
end

local function call_imgui(imgui, name, ...)
    local function_to_call = imgui_member(imgui, name)
    if type(function_to_call) ~= "function" then
        return nil
    end
    return function_to_call(...)
end

function TrackFXMatrixUI.new(imgui, controller, options)
    options = options or {}
    local reaper_api = options.reaper_api or reaper
    local drawer_preference = get_ext_state(reaper_api, "drawer")
    if drawer_preference ~= "open" and drawer_preference ~= "closed" then
        drawer_preference = nil
    end
    local instance = {
        imgui = imgui,
        controller = controller,
        command = options.command,
        reaper_api = reaper_api,
        preset_directory = options.preset_directory or default_preset_directory,
        save_preset_dialog = options.save_preset_dialog,
        load_preset_dialog = options.load_preset_dialog,
        context = nil,
        open = true,
        error_message = nil,
        pad_size = options.pad_size,
        default_width = options.default_width or 1100,
        default_height = options.default_height or 760,
        minimum_width = options.minimum_width or 760,
        minimum_height = options.minimum_height or 600,
        mappings_locked = get_ext_state(reaper_api, "mappings_locked") == "true",
        drawer_user_preference = drawer_preference,
        drawer_open = drawer_preference ~= "closed",
        drawer_initialized = false,
        drawer_auto_collapsed = false,
        drawer_was_open_before_auto = false,
        drawer_manual_override = false,
        drawer_target_open = false,
        last_mapping_count = 0,
        label_button_feedback_until = {},
        matrix_frame = options.matrix_frame or 48,
        minimum_matrix_side = options.minimum_matrix_side or 420,
        dpi_scale = 1,
        feedback_corner = nil,
        feedback_kind = nil,
        feedback_until = 0,
        unlink_feedback_until = 0,
        cursor_history = {},
        cursor_drag_active = false,
        row_edit_index = nil,
        row_edit_active = false,
        row_display_values = {},
        parameter_drag_index = nil,
        parameter_drag_mode = nil,
        learning_record_id = nil,
        last_learned_parameter_index = nil,
        stale_last_touched_parameter_index = nil,
    }
    return setmetatable(instance, TrackFXMatrixUI)
end

function TrackFXMatrixUI:set_context(context)
    self.context = context
    if self.bold_font or type(self.imgui.CreateFont) ~= "function" then
        return
    end
    local font_flags = imgui_member(self.imgui, "FontFlags_Bold") or 0
    local ok, font = pcall(self.imgui.CreateFont, "sans-serif", font_flags)
    if ok and font then
        self.bold_font = font
        if type(self.imgui.Attach) == "function" then
            pcall(self.imgui.Attach, context, font)
        end
    end
end

function TrackFXMatrixUI:_push_style()
    local imgui = self.imgui
    local ctx = self.context
    self.style_color_count = 0
    self.style_var_count = 0

    local function push_color(name, color)
        local color_id = imgui_member(imgui, name)
        if color_id ~= nil and type(imgui.PushStyleColor) == "function" then
            imgui.PushStyleColor(ctx, color_id, color)
            self.style_color_count = self.style_color_count + 1
        end
    end

    local function push_var(name, ...)
        local var_id = imgui_member(imgui, name)
        if var_id ~= nil and type(imgui.PushStyleVar) == "function" then
            imgui.PushStyleVar(ctx, var_id, ...)
            self.style_var_count = self.style_var_count + 1
        end
    end

    push_color("Col_WindowBg", COLORS.background)
    push_color("Col_ChildBg", COLORS.panel)
    push_color("Col_PopupBg", COLORS.panel_alt)
    push_color("Col_FrameBg", COLORS.panel_alt)
    push_color("Col_FrameBgHovered", COLORS.panel_highlight)
    push_color("Col_FrameBgActive", color_with_alpha(COLORS.active, 210))
    push_color("Col_Button", COLORS.panel_alt)
    push_color("Col_ButtonHovered", COLORS.panel_highlight)
    push_color("Col_ButtonActive", color_with_alpha(COLORS.active, 220))
    push_color("Col_Header", COLORS.panel_alt)
    push_color("Col_HeaderHovered", COLORS.panel_highlight)
    push_color("Col_HeaderActive", color_with_alpha(COLORS.active, 180))
    push_color("Col_Text", COLORS.text)
    push_color("Col_Border", COLORS.line)
    push_color("Col_Separator", COLORS.line)
    push_color("Col_MenuBarBg", COLORS.panel)
    push_var("StyleVar_WindowPadding", 18, 16)
    push_var("StyleVar_FramePadding", 9, 6)
    push_var("StyleVar_ItemSpacing", 10, 8)
    push_var("StyleVar_FrameRounding", 6)
    push_var("StyleVar_ChildRounding", 8)
    push_var("StyleVar_WindowRounding", 8)
end

function TrackFXMatrixUI:_pop_style()
    if self.style_var_count > 0 and type(self.imgui.PopStyleVar) == "function" then
        self.imgui.PopStyleVar(self.context, self.style_var_count)
    end
    if self.style_color_count > 0 and type(self.imgui.PopStyleColor) == "function" then
        self.imgui.PopStyleColor(self.context, self.style_color_count)
    end
    self.style_var_count = 0
    self.style_color_count = 0
end

function TrackFXMatrixUI:_set_next_window_size()
    local imgui = self.imgui
    local cond = imgui_member(imgui, "Cond_FirstUseEver")
    if type(imgui.SetNextWindowSize) == "function" then
        imgui.SetNextWindowSize(self.context, self.default_width, self.default_height, cond)
    end
    if type(imgui.SetNextWindowSizeConstraints) == "function" then
        -- A max of 0 with a nonzero min inverts the constraint (min > max) and can
        -- collapse the window below its minimum. Use FLT_MAX for "no upper limit",
        -- matching the ReaImGui demo idiom.
        local _, flt_max = call_imgui(imgui, "NumericLimits_Float")
        local no_limit = type(flt_max) == "number" and flt_max or 3.402823466e38
        imgui.SetNextWindowSizeConstraints(
            self.context,
            self.minimum_width,
            self.minimum_height,
            no_limit,
            no_limit
        )
    end
end

function TrackFXMatrixUI:_draw_list_call(draw_list, name, ...)
    local function_to_call = imgui_member(self.imgui, name)
    if draw_list and type(function_to_call) == "function" then
        return function_to_call(draw_list, ...)
    end
    return nil
end

function TrackFXMatrixUI:_draw_text(draw_list, x, y, color, text, bold, size)
    if bold
        and self.bold_font
        and type(imgui_member(self.imgui, "DrawList_AddTextEx")) == "function" then
        self.imgui.DrawList_AddTextEx(
            draw_list,
            self.bold_font,
            size or 22,
            x,
            y,
            color,
            text
        )
        return
    end
    self:_draw_list_call(draw_list, "DrawList_AddText", x, y, color, text)
end

function TrackFXMatrixUI:_draw_icon(draw_list, icon, x, y, size, color)
    local center_x = x + size / 2
    local center_y = y + size / 2
    local inset = math.max(4, size * 0.25)
    local draw_flags = imgui_member(self.imgui, "DrawFlags_None") or 0
    if icon == "save" then
        self:_draw_list_call(draw_list, "DrawList_AddRect", x + inset, y + inset, x + size - inset, y + size - inset, color, 3, draw_flags, 1.5)
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", x + size * 0.35, y + inset, x + size * 0.65, y + size * 0.42, color)
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + size * 0.32, y + size * 0.68, x + size * 0.68, y + size * 0.68, color, 1.5)
    elseif icon == "dice" then
        self:_draw_list_call(draw_list, "DrawList_AddRect", x + inset, y + inset, x + size - inset, y + size - inset, color, 3, draw_flags, 1.5)
        local dot = math.max(1.5, size * 0.07)
        self:_draw_list_call(draw_list, "DrawList_AddCircleFilled", x + size * 0.36, y + size * 0.36, dot, color)
        self:_draw_list_call(draw_list, "DrawList_AddCircleFilled", x + size * 0.64, y + size * 0.64, dot, color)
        self:_draw_list_call(draw_list, "DrawList_AddCircleFilled", x + size * 0.64, y + size * 0.36, dot, color)
        self:_draw_list_call(draw_list, "DrawList_AddCircleFilled", x + size * 0.36, y + size * 0.64, dot, color)
    elseif icon == "link" or icon == "unlink" then
        self:_draw_list_call(draw_list, "DrawList_AddRect", x + inset, y + size * 0.32, x + size * 0.62, y + size * 0.62, color, 3, draw_flags, 1.8)
        self:_draw_list_call(draw_list, "DrawList_AddRect", x + size * 0.38, y + size * 0.38, x + size - inset, y + size * 0.68, color, 3, draw_flags, 1.8)
        if icon == "unlink" then
            self:_draw_list_call(draw_list, "DrawList_AddLine", x + size * 0.26, y + size * 0.74, x + size * 0.74, y + size * 0.26, color, 2)
        end
    elseif icon == "lock" then
        self:_draw_list_call(draw_list, "DrawList_AddRect", x + inset, y + size * 0.42, x + size - inset, y + size - inset, color, 3, draw_flags, 1.8)
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + size * 0.34, y + size * 0.42, x + size * 0.34, y + size * 0.28, color, 1.8)
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + size * 0.34, y + size * 0.28, x + size * 0.66, y + size * 0.28, color, 1.8)
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + size * 0.66, y + size * 0.28, x + size * 0.66, y + size * 0.42, color, 1.8)
    elseif icon == "unlock" then
        self:_draw_list_call(draw_list, "DrawList_AddRect", x + inset, y + size * 0.42, x + size - inset, y + size - inset, color, 3, draw_flags, 1.8)
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + size * 0.38, y + size * 0.42, x + size * 0.38, y + size * 0.25, color, 1.8)
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + size * 0.38, y + size * 0.25, x + size * 0.68, y + size * 0.25, color, 1.8)
    elseif icon == "close" then
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + inset, y + inset, x + size - inset, y + size - inset, color, 2)
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + size - inset, y + inset, x + inset, y + size - inset, color, 2)
    elseif icon == "left" or icon == "right" then
        local direction = icon == "left" and -1 or 1
        self:_draw_list_call(draw_list, "DrawList_AddLine", center_x + direction * size * 0.18, y + size * 0.28, center_x - direction * size * 0.18, center_y, color, 2)
        self:_draw_list_call(draw_list, "DrawList_AddLine", center_x - direction * size * 0.18, center_y, center_x + direction * size * 0.18, y + size * 0.72, color, 2)
    elseif icon == "clear" then
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + size * 0.3, y + size * 0.32, x + size * 0.7, y + size * 0.72, color, 2)
        self:_draw_list_call(draw_list, "DrawList_AddLine", x + size * 0.7, y + size * 0.32, x + size * 0.3, y + size * 0.72, color, 2)
    elseif icon == "fader" then
        local rail_top = y + size * 0.18
        local rail_bottom = y + size * 0.82
        local rail_width = math.max(1.5, size * 0.07)
        local knob_width = size * 0.26
        local knob_height = size * 0.12
        local knob_positions = {0.34, 0.62, 0.46}
        for index = 1, 3 do
            local rail_x = x + size * (0.25 + (index - 1) * 0.25)
            self:_draw_list_call(draw_list, "DrawList_AddLine", rail_x, rail_top, rail_x, rail_bottom, color, rail_width)
            local knob_y = y + size * knob_positions[index]
            self:_draw_list_call(
                draw_list,
                "DrawList_AddRectFilled",
                rail_x - knob_width / 2,
                knob_y - knob_height / 2,
                rail_x + knob_width / 2,
                knob_y + knob_height / 2,
                color,
                2
            )
        end
    end
end

function TrackFXMatrixUI:icon_button(id, tooltip, icon, size, selected, enabled, accent, transparent, allow_right_click)
    local imgui = self.imgui
    local ctx = self.context
    local cursor_x, cursor_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
    local clicked = false
    local right_clicked = false
    local hovered = false
    local pressed = false
    local invisible_button = imgui_member(imgui, "InvisibleButton")
    if type(invisible_button) == "function" then
        invisible_button(ctx, "##" .. id, size, size)
        hovered = call_imgui(imgui, "IsItemHovered", ctx) == true
        clicked = call_imgui(imgui, "IsItemClicked", ctx) == true
        if allow_right_click and hovered then
            local right_button = imgui_member(imgui, "MouseButton_Right")
            right_button = type(right_button) == "number" and right_button or 1
            right_clicked = call_imgui(imgui, "IsItemClicked", ctx, right_button) == true
        end
        pressed = call_imgui(imgui, "IsItemActive", ctx) == true
    elseif type(imgui.Button) == "function" then
        clicked = imgui.Button(ctx, "...##" .. id, size, size) == true
        hovered = call_imgui(imgui, "IsItemHovered", ctx) == true
        if allow_right_click and hovered then
            local right_button = imgui_member(imgui, "MouseButton_Right")
            right_button = type(right_button) == "number" and right_button or 1
            right_clicked = call_imgui(imgui, "IsItemClicked", ctx, right_button) == true
        end
    end
    if enabled == false then
        clicked = false
        right_clicked = false
    elseif right_clicked then
        clicked = false
    end

    local draw_list = call_imgui(imgui, "GetWindowDrawList", ctx)
    if draw_list and cursor_x and cursor_y then
        local background = selected and color_with_alpha(COLORS.active, 230)
                or hovered and COLORS.panel_highlight
                or COLORS.panel_alt
        if not transparent then
            self:_draw_list_call(draw_list, "DrawList_AddRectFilled", cursor_x, cursor_y, cursor_x + size, cursor_y + size, background, 5)
        end
        local icon_color
        if selected then
            icon_color = COLORS.text
        elseif enabled == false then
            icon_color = COLORS.dim
        elseif clicked or pressed or right_clicked then
            icon_color = color_with_alpha(accent or COLORS.muted, 255)
        else
            icon_color = accent or COLORS.muted
        end
        self:_draw_icon(draw_list, icon, cursor_x, cursor_y, size, icon_color)
    end
    if hovered and type(imgui.SetTooltip) == "function" then
        imgui.SetTooltip(ctx, tooltip)
    end
    return clicked, pressed, right_clicked
end

function TrackFXMatrixUI:label_button(id, label, icon, width, height, accent, tooltip, enabled, opacity)
    local imgui = self.imgui
    local ctx = self.context
    enabled = enabled ~= false
    local cursor_x, cursor_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
    local clicked = false
    local hovered = false
    local pressed = false
    local invisible_button = imgui_member(imgui, "InvisibleButton")
    if type(invisible_button) == "function" then
        invisible_button(ctx, "##" .. id, width, height)
        clicked = call_imgui(imgui, "IsItemClicked", ctx) == true
        hovered = call_imgui(imgui, "IsItemHovered", ctx) == true
        pressed = call_imgui(imgui, "IsItemActive", ctx) == true
    elseif type(imgui.Button) == "function" then
        clicked = imgui.Button(ctx, label .. "##" .. id, width, height) == true
        hovered = clicked
        pressed = clicked
    end
    if not enabled then
        clicked = false
        pressed = false
    elseif clicked or pressed then
        self.label_button_feedback_until[id] = now(self.reaper_api)
            + LABEL_BUTTON_FEEDBACK_DURATION
    end

    local feedback_until = self.label_button_feedback_until[id]
    local feedback_active = type(feedback_until) == "number"
        and now(self.reaper_api) < feedback_until
    if not feedback_active then
        self.label_button_feedback_until[id] = nil
    end

    local draw_list = call_imgui(imgui, "GetWindowDrawList", ctx)
    if draw_list and cursor_x and cursor_y then
        local alpha = type(opacity) == "number"
                and clamp(opacity, 0, 255)
            or hovered and 235
            or 175
        local background = color_with_alpha(accent, alpha)
        local foreground = feedback_active
                and COLORS.text
            or readable_button_foreground(accent, alpha, enabled)
        self:_draw_list_call(
            draw_list,
            "DrawList_AddRectFilled",
            cursor_x,
            cursor_y,
            cursor_x + width,
            cursor_y + height,
            background,
            6
        )
        self:_draw_icon(draw_list, icon, cursor_x + 7, cursor_y + 4, height - 8, foreground)
        self:_draw_text(draw_list, cursor_x + height + 2, cursor_y + 6, foreground, label, false, 16)
    end
    if hovered and type(imgui.SetTooltip) == "function" then
        imgui.SetTooltip(ctx, tooltip)
    end
    return clicked
end

function TrackFXMatrixUI:_is_linked_to_focused_fx(active, focused)
    if not active then
        return false
    end
    if type(self.controller.is_active_fx_focused) == "function" then
        local ok, linked = pcall(
            self.controller.is_active_fx_focused,
            self.controller
        )
        return ok and linked == true
    end
    return focused ~= nil
        and active.descriptor ~= nil
        and active.descriptor == focused
end

function TrackFXMatrixUI:_set_mapping_lock(locked)
    self.mappings_locked = locked == true
    set_ext_state(self.reaper_api, "mappings_locked", self.mappings_locked and "true" or "false")
    self.learning_record_id = nil
    self.last_learned_parameter_index = nil
end

function TrackFXMatrixUI:_capture_last_touched_parameter()
    if type(self.controller.get_last_touched_parameter) ~= "function" then
        return nil
    end

    local ok, parameter_index = pcall(
        self.controller.get_last_touched_parameter,
        self.controller
    )
    return ok and parameter_index or nil
end

function TrackFXMatrixUI:_remember_stale_touch_after_unlink(parameter_index)
    self.stale_last_touched_parameter_index = parameter_index
    self.learning_record_id = nil
    self.last_learned_parameter_index = nil
end

function TrackFXMatrixUI:_set_drawer_open(open, manual)
    self.drawer_open = open == true
    if manual then
        self.drawer_user_preference = self.drawer_open and "open" or "closed"
        set_ext_state(self.reaper_api, "drawer", self.drawer_user_preference)
        self.drawer_auto_collapsed = false
        self.drawer_was_open_before_auto = false
        self.drawer_manual_override = self.drawer_open
    end
end

function TrackFXMatrixUI:_sync_drawer_state(mapping_count, available_width)
    if mapping_count <= 0 then
        self.drawer_target_open = false
        self.last_mapping_count = 0
        self.drawer_auto_collapsed = false
        self.drawer_was_open_before_auto = false
        self.drawer_manual_override = false
        return
    end

    local first_mapping = self.last_mapping_count == 0
    if first_mapping then
        self.drawer_open = self.drawer_user_preference ~= "closed"
    end
    self.last_mapping_count = mapping_count

    local drawer_width = clamp(available_width * 0.31, 300, 360)
    local threshold = self.minimum_matrix_side + drawer_width + 12
    local should_auto_collapse = self.drawer_open
        and not self.drawer_manual_override
        and type(available_width) == "number"
        and available_width < threshold
    if first_mapping and should_auto_collapse then
        self.drawer_manual_override = true
        should_auto_collapse = false
    end
    if should_auto_collapse and not self.drawer_auto_collapsed then
        self.drawer_auto_collapsed = true
        self.drawer_was_open_before_auto = self.drawer_open
    elseif not should_auto_collapse and self.drawer_auto_collapsed then
        self.drawer_auto_collapsed = false
        if self.drawer_was_open_before_auto then
            self.drawer_open = true
        end
        self.drawer_was_open_before_auto = false
    end

    self.drawer_target_open = self.drawer_open and not self.drawer_auto_collapsed
end

function TrackFXMatrixUI:_mark_feedback(corner_id, kind)
    self.feedback_corner = corner_id
    self.feedback_kind = kind
    self.feedback_until = now(self.reaper_api) + 0.45
end

function TrackFXMatrixUI:_remember_cursor(x, y)
    self.cursor_history[#self.cursor_history + 1] = {x = x, y = y}
    while #self.cursor_history > 8 do
        table.remove(self.cursor_history, 1)
    end
end

function TrackFXMatrixUI:_clear_cursor_trail()
    self.cursor_history = {}
end

function TrackFXMatrixUI:_move_cursor(x, y, feedback_corner)
    local moved, move_error = self.controller:move_cursor(x, y)
    if moved == false then
        self.error_message = move_error or "unable to apply cursor position"
        return false
    end
    if feedback_corner then
        self:_clear_cursor_trail()
        self:_mark_feedback(feedback_corner, "snap")
    else
        self:_remember_cursor(x, y)
    end
    return true
end

function TrackFXMatrixUI:invoke(label, operation)
    if not self.command then
        local result, error_message = operation()
        if result == false or result == nil then
            self.error_message = error_message or "command failed"
        elseif error_message and error_message ~= "" then
            self.error_message = error_message
        else
            self.error_message = nil
        end
        return result
    end

    local ok, result, error_message = self.command(label, operation)
    if not ok then
        self.error_message = error_message or "command failed"
        return false
    end
    if result == false or result == nil then
        self.error_message = error_message or "command failed"
        return false
    end
    self.error_message = error_message and error_message ~= "" and error_message or nil
    return result
end

function TrackFXMatrixUI:_default_preset_path()
    return self:_preset_directory() .. "Morph Matrix Preset.mmxpreset"
end

function TrackFXMatrixUI:_preset_directory()
    if self.preset_directory ~= "" and not self.preset_directory:match("[\\/]$") then
        return self.preset_directory .. "\\"
    end
    return self.preset_directory
end

function TrackFXMatrixUI:_choose_preset_path(dialog, title)
    local default_path = self:_default_preset_path()
    if dialog then
        return dialog(default_path)
    end

    if not self.reaper_api then
        return nil, "REAPER file dialog API is unavailable"
    end
    if title == "Save" then
        if type(self.reaper_api.GetUserFileName) ~= "function" then
            return nil, "REAPER native Save dialog API is unavailable"
        end

        local accepted, path = self.reaper_api.GetUserFileName(
            0,
            "Save Morph Matrix Preset",
            default_path,
            "Morph Matrix presets|*.mmxpreset|All files|*.*"
        )
        if not accepted then
            return nil
        end
        return path
    end

    local dialog_function = self.reaper_api.GetUserFileNameForRead
    if type(dialog_function) ~= "function" then
        return nil, "REAPER file dialog API is unavailable"
    end

    local selected, path = dialog_function(default_path, title .. " Morph Matrix Preset", "mmxpreset")
    if not selected then
        return nil
    end
    return path
end

function TrackFXMatrixUI:save_preset_from_menu()
    local path, dialog_error = self:_choose_preset_path(self.save_preset_dialog, "Save")
    if not path then
        if dialog_error then
            self.error_message = dialog_error
            return false
        end
        return true
    end

    return self:invoke("Save Morph Matrix Preset", function()
        return self.controller:save_preset(path)
    end)
end

function TrackFXMatrixUI:load_preset_from_menu()
    local path, dialog_error = self:_choose_preset_path(self.load_preset_dialog, "Load")
    if not path then
        if dialog_error then
            self.error_message = dialog_error
            return false
        end
        return true
    end

    return self:invoke("Load Morph Matrix Preset", function()
        return self.controller:load_preset(path)
    end)
end

function TrackFXMatrixUI:draw_menu_bar()
    local imgui = self.imgui
    local ctx = self.context
    if type(imgui.BeginMenuBar) ~= "function" then
        return
    end

    if imgui.BeginMenuBar(ctx) then
        if imgui.BeginMenu(ctx, "File") then
            if imgui.MenuItem(ctx, "Save Preset...") then
                self:save_preset_from_menu()
            end
            if imgui.MenuItem(ctx, "Load Preset...") then
                self:load_preset_from_menu()
            end
            imgui.EndMenu(ctx)
        end
        imgui.EndMenuBar(ctx)
    end
end

function TrackFXMatrixUI:draw_header(show_controls)
    local imgui = self.imgui
    local ctx = self.context
    local preset_name = "None"
    if type(self.controller.get_loaded_preset_name) == "function" then
        preset_name = self.controller:get_loaded_preset_name() or "None"
    end
    imgui.Text(ctx, "Preset: " .. preset_name)

    local focused, focus_error = self.controller:discover_focused_fx()
    self.current_focus_descriptor = focused
    if focused then
        local _, activation_error = self.controller:activate_registered_fx(focused)
        if activation_error then
            self.error_message = activation_error
        end
        imgui.Text(ctx, format_descriptor(focused))
    else
        imgui.Text(ctx, focus_error or "No focused Track FX")
    end

    local active = self.controller:get_active()
    if show_controls ~= false then
        local linked = self:_is_linked_to_focused_fx(active, focused)
        local link_label = linked and "Linked" or "Link"
        local link_tooltip = linked
                and "The focused Track FX is linked to the Matrix"
            or "Link the focused Track FX to the Matrix"
        if self:label_button(
            "link-fx",
            link_label,
            "link",
            132,
            30,
            COLORS.link,
            link_tooltip,
            not linked,
            linked and LINKED_BUTTON_OPACITY or 105
        ) then
            local registered = self:invoke("Register Morph Matrix Track FX", function()
                local linked_active, error_message = self.controller:register_focused_fx()
                if not linked_active then
                    return false, error_message
                end
                return true
            end)
            if registered ~= false then
                self.unlink_feedback_until = 0
            end
        end

        imgui.SameLine(ctx)
        local unlink_feedback = now(self.reaper_api) < self.unlink_feedback_until
        local unlink_color = unlink_feedback and COLORS.unlink_bright
                or linked and COLORS.unlink
                or COLORS.dim
        local unlink_tooltip = linked
                and "Unlink the focused Track FX from the Matrix"
            or "No focused Track FX is linked to the Matrix"
        if self:label_button(
            "unlink-fx",
            "Unlink",
            "unlink",
            122,
            30,
            unlink_color,
            unlink_tooltip,
            linked,
            unlink_feedback and 255 or linked and 145 or 70
        ) then
            local stale_parameter_index = self:_capture_last_touched_parameter()
            local unlinked = self:invoke("Deregister Morph Matrix Track FX", function()
                return self.controller:deregister_active_fx()
            end)
            if unlinked ~= false then
                self:_remember_stale_touch_after_unlink(stale_parameter_index)
                self.unlink_feedback_until = now(self.reaper_api) + 0.35
            end
        end

        imgui.SameLine(ctx)
        local lock_label = self.mappings_locked and "Locked" or "Unlocked"
        local lock_tooltip = self.mappings_locked
                and "Unlock automatic parameter mapping"
            or "Lock automatic parameter mapping"
        local lock_clicked = self:label_button(
            "mapping-lock",
            lock_label,
            self.mappings_locked and "lock" or "unlock",
            122,
            30,
            self.mappings_locked and COLORS.locked or COLORS.unlocked,
            lock_tooltip
        )
        if lock_clicked then
            self:_set_mapping_lock(not self.mappings_locked)
        end
    end

    return active, focused
end

function TrackFXMatrixUI:_draw_top_control_grid(active, snapshot, layout, origin_x, origin_y)
    local imgui = self.imgui
    local ctx = self.context
    origin_x = origin_x or 0
    origin_y = origin_y or 0

    local grid_x = origin_x
        + (layout.group_offset or 0)
        + (layout.matrix_side - TOP_GRID_WIDTH) / 2
    local function draw_button(column, row, id, label, icon, accent, tooltip, enabled, opacity)
        local x = grid_x + (column - 1) * (TOP_BUTTON_WIDTH + TOP_BUTTON_GAP)
        local y = origin_y + (row - 1) * (TOP_BUTTON_HEIGHT + TOP_BUTTON_GAP)
        call_imgui(imgui, "SetCursorScreenPos", ctx, x, y)
        return self:label_button(
            id,
            label,
            icon,
            TOP_BUTTON_WIDTH,
            TOP_BUTTON_HEIGHT,
            accent,
            tooltip,
            enabled,
            opacity
        )
    end

    local focused = self.current_focus_descriptor
    local linked = self:_is_linked_to_focused_fx(active, focused)
    local link_label = linked and "Linked" or "Link"
    local link_tooltip = linked
            and "The focused Track FX is linked to the Matrix"
        or "Link the focused Track FX to the Matrix"
    if draw_button(
        1,
        1,
        "link-fx",
        link_label,
        "link",
        COLORS.link,
        link_tooltip,
        not linked,
        linked and LINKED_BUTTON_OPACITY or 105
    ) then
        local registered = self:invoke("Register Morph Matrix Track FX", function()
            local linked_active, error_message = self.controller:register_focused_fx()
            if not linked_active then
                return false, error_message
            end
            return true
        end)
        if registered ~= false then
            self.unlink_feedback_until = 0
        end
    end

    local unlink_feedback = now(self.reaper_api) < self.unlink_feedback_until
    local unlink_color = unlink_feedback and COLORS.unlink_bright
            or linked and COLORS.unlink
            or COLORS.dim
    local unlink_tooltip = linked
            and "Unlink the focused Track FX from the Matrix"
        or "No focused Track FX is linked to the Matrix"
    if draw_button(
        2,
        1,
        "unlink-fx",
        "Unlink",
        "unlink",
        unlink_color,
        unlink_tooltip,
        linked,
        unlink_feedback and 255 or linked and 145 or 70
    ) then
        local stale_parameter_index = self:_capture_last_touched_parameter()
        local unlinked = self:invoke("Deregister Morph Matrix Track FX", function()
            return self.controller:deregister_active_fx()
        end)
        if unlinked ~= false then
            self:_remember_stale_touch_after_unlink(stale_parameter_index)
            self.unlink_feedback_until = now(self.reaper_api) + 0.35
        end
    end

    local lock_label = self.mappings_locked and "Locked" or "Unlocked"
    local lock_tooltip = self.mappings_locked
            and "Unlock automatic parameter mapping"
        or "Lock automatic parameter mapping"
    if draw_button(
        3,
        1,
        "mapping-lock",
        lock_label,
        self.mappings_locked and "lock" or "unlock",
        self.mappings_locked and COLORS.locked or COLORS.unlocked,
        lock_tooltip,
        true,
        175
    ) then
        self:_set_mapping_lock(not self.mappings_locked)
    end

    local has_parameters = next(snapshot.parameters) ~= nil
    if draw_button(
        1,
        2,
        "randomize-all",
        "Randomize All",
        "dice",
        has_parameters and COLORS.active or COLORS.dim,
        "Randomize all Matrix corners",
        has_parameters,
        has_parameters and 175 or 90
    ) then
        self:invoke("Randomize All Matrix Corners", function()
            return self.controller:randomize_all()
        end)
    end

    if draw_button(
        2,
        2,
        "clear-mappings",
        "Clear Mappings",
        "clear",
        has_parameters and COLORS.active or COLORS.dim,
        "Clear all Matrix corner assignments",
        has_parameters,
        has_parameters and 175 or 90
    ) then
        self:invoke("Clear Matrix Mappings", function()
            return self.controller:clear_mappings()
        end)
    end

    if draw_button(
        3,
        2,
        "mappings",
        "Mappings",
        "fader",
        has_parameters and COLORS.cool or COLORS.dim,
        "Show or hide mapped parameters",
        has_parameters,
        has_parameters and 175 or 90
    ) then
        self:_set_drawer_open(self.drawer_target_open ~= true, true)
    end

    local next_y = origin_y + TOP_GRID_HEIGHT + TOP_GRID_WORKSPACE_GAP
    call_imgui(imgui, "SetCursorScreenPos", ctx, origin_x, next_y)
    return next_y
end

function TrackFXMatrixUI:_draw_corner_target(corner, interactive)
    local imgui = self.imgui
    local ctx = self.context
    local badge_size = 34
    local original_x, original_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
    call_imgui(imgui, "SetCursorScreenPos", ctx, corner.x - badge_size / 2, corner.y - badge_size / 2)

    local clicked = false
    local invisible_button = imgui_member(imgui, "InvisibleButton")
    if type(invisible_button) == "function" then
        invisible_button(ctx, "##matrix_corner_" .. tostring(corner.id), badge_size, badge_size)
        clicked = call_imgui(imgui, "IsItemClicked", ctx) == true
    elseif type(imgui.Button) == "function" then
        clicked = imgui.Button(ctx, tostring(corner.id) .. "##matrix_corner_" .. tostring(corner.id), badge_size, badge_size) == true
    end
    if not interactive then
        clicked = false
    end

    call_imgui(imgui, "SetCursorScreenPos", ctx, original_x, original_y)
    return clicked
end

function TrackFXMatrixUI:_draw_corner_number(corner, x, y, interactive, highlighted)
    local imgui = self.imgui
    local ctx = self.context
    local width = 38
    local height = 36
    local original_x, original_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
    call_imgui(imgui, "SetCursorScreenPos", ctx, x, y)

    local clicked = false
    local hovered = false
    local invisible_button = imgui_member(imgui, "InvisibleButton")
    if type(invisible_button) == "function" then
        invisible_button(ctx, "##matrix_corner_number_" .. tostring(corner.id), width, height)
        hovered = call_imgui(imgui, "IsItemHovered", ctx) == true
        clicked = call_imgui(imgui, "IsItemClicked", ctx) == true
    elseif type(imgui.Button) == "function" then
        clicked = imgui.Button(ctx, tostring(corner.id) .. "##matrix_corner_number_" .. tostring(corner.id), width, height) == true
        hovered = call_imgui(imgui, "IsItemHovered", ctx) == true
    end
    if not interactive then
        clicked = false
    end

    local draw_list = call_imgui(imgui, "GetWindowDrawList", ctx)
    if draw_list then
        local color = interactive and highlighted and CORNER_COLORS[corner.id]
            or color_with_alpha(COLORS.dim, 190)
        self:_draw_text(draw_list, x + 11, y + 2, color, tostring(corner.id), true, 26)
        if self.feedback_corner == corner.id then
            local remaining = clamp((self.feedback_until - now(self.reaper_api)) / 0.45, 0, 1)
            if remaining > 0 then
                self:_draw_list_call(
                    draw_list,
                    "DrawList_AddCircle",
                    x + width / 2,
                    y + height / 2,
                    22 + (1 - remaining) * 12,
                    color_with_alpha(CORNER_COLORS[corner.id], remaining * 220),
                    28,
                    2 + remaining * 2
                )
            end
        end
    end

    if hovered and type(imgui.SetTooltip) == "function" then
        imgui.SetTooltip(ctx, "Snap cursor to corner " .. tostring(corner.id))
    end

    call_imgui(imgui, "SetCursorScreenPos", ctx, original_x, original_y)
    return clicked
end

function TrackFXMatrixUI:_draw_corner_action(corner, action, x, y, interactive, highlighted)
    local imgui = self.imgui
    local ctx = self.context
    local size = 30
    local original_x, original_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
    call_imgui(imgui, "SetCursorScreenPos", ctx, x, y)
    local tooltip = action == "save"
            and "Store all mapped values in corner " .. tostring(corner.id)
            .. "; right-click to clear all mapped parameters"
        or "Randomize corner " .. tostring(corner.id)
    local clicked, _, right_clicked = self:icon_button(
        "corner-" .. tostring(corner.id) .. "-" .. action,
        tooltip,
        action,
        size,
        false,
        interactive,
        highlighted
                and CORNER_COLORS[corner.id]
            or color_with_alpha(CORNER_COLORS[corner.id], INACTIVE_CORNER_ICON_ALPHA),
        true,
        action == "save"
    )
    call_imgui(imgui, "SetCursorScreenPos", ctx, original_x, original_y)
    return clicked, right_clicked
end

function TrackFXMatrixUI:_draw_matrix_background(draw_list, pad_x, pad_y, pad_size, normalized_x, normalized_y)
    normalized_x = clamp(normalized_x, 0, 1)
    normalized_y = clamp(normalized_y, 0, 1)
    local cursor_x = pad_x + normalized_x * pad_size
    local cursor_y = pad_y + normalized_y * pad_size
    local dot_radius = math.max(1.5, math.min(3.5, pad_size / 220))

    for grid_x = 1, MATRIX_GRID_STEPS do
        local point_x = grid_x / (MATRIX_GRID_STEPS + 1)
        for grid_y = 1, MATRIX_GRID_STEPS do
            local point_y = grid_y / (MATRIX_GRID_STEPS + 1)
            local dot_x = pad_x + point_x * pad_size
            local dot_y = pad_y + point_y * pad_size
            self:_draw_list_call(
                draw_list,
                "DrawList_AddCircleFilled",
                dot_x,
                dot_y,
                dot_radius,
                color_with_alpha(COLORS.grid, 62)
            )

            local distance = math.sqrt(
                (point_x - normalized_x) ^ 2
                    + (point_y - normalized_y) ^ 2
            )
            local falloff = clamp(1 - distance / MATRIX_GLOW_RADIUS, 0, 1)
            local reveal = falloff * falloff * (3 - 2 * falloff)
            if reveal > 0 then
                local color = matrix_cursor_color(point_x, point_y)
                local alpha = (8 + reveal * 150) * MATRIX_GLOW_BRIGHTNESS
                self:_draw_list_call(
                    draw_list,
                    "DrawList_AddCircleFilled",
                    dot_x,
                    dot_y,
                    dot_radius,
                    color_with_alpha(color, alpha)
                )
            end
        end
    end
end

function TrackFXMatrixUI:_draw_corner_actions(
    corner,
    pad_size,
    interactive,
    pad_x,
    pad_y,
    actions_enabled,
    corner_mapped
)
    local button_size = 30
    local left = corner.x <= pad_x + pad_size / 2
    local top = corner.y <= pad_y + pad_size / 2
    local frame = self.matrix_frame or 48
    local number_width = 38
    local number_height = 36
    local action_y = top
            and pad_y - frame + (frame - button_size) / 2
        or pad_y + pad_size + (frame - button_size) / 2
    local side_band_x = left and pad_x - frame or pad_x + pad_size
    local save_x = side_band_x + (frame - button_size) / 2
    local number_x = save_x - (number_width - button_size) / 2
    local number_y = action_y - (number_height - button_size) / 2
    local number_clicked, number_right_clicked = self:_draw_corner_number(
        corner,
        number_x,
        number_y,
        interactive and corner_mapped,
        corner_mapped
    )
    local save_y = corner.y - button_size / 2
    local randomize_x = corner.x - button_size / 2

    local save_clicked, save_right_clicked = self:_draw_corner_action(
        corner,
        "save",
        save_x,
        save_y,
        actions_enabled,
        corner_mapped
    )
    if save_right_clicked then
        local cleared = self:invoke("Clear Matrix Corner Mappings", function()
            return self.controller:remove_all_parameters_from_corner(corner.id)
        end)
        if cleared ~= false then
            self:_mark_feedback(corner.id, "clear")
        end
    elseif save_clicked then
        local saved = self:invoke("Save Matrix Corner", function()
            return self.controller:save_corner(corner.id)
        end)
        if saved ~= false then
            local snap_x = (corner.id == 1 or corner.id == 3) and 0 or 1
            local snap_y = (corner.id == 1 or corner.id == 2) and 0 or 1
            local snapped = self:_move_cursor(snap_x, snap_y, corner.id)
            if not snapped then
                self.feedback_until = 0
            end
        end
    end
    if self:_draw_corner_action(
        corner,
        "dice",
        randomize_x,
        action_y,
        actions_enabled and corner_mapped,
        corner_mapped
    ) then
        local randomized = self:invoke("Randomize Matrix Corner", function()
            return self.controller:randomize_corner(corner.id)
        end)
        if randomized ~= false then
            self:_mark_feedback(corner.id, "randomize")
        end
    end
    return number_clicked, number_right_clicked
end

function TrackFXMatrixUI:draw_pad(snapshot, interactive, available_width, available_height)
    local imgui = self.imgui
    local ctx = self.context
    interactive = interactive ~= false
    local layout_x, layout_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
    layout_x = layout_x or 0
    layout_y = layout_y or 0

    local frame = self.matrix_frame or 48

    local pad_size = self.pad_size
    if available_width and available_height then
        local width_limit = math.max(100, available_width - frame * 2)
        local height_limit = math.max(100, available_height - frame * 2)
        pad_size = pad_size and math.min(pad_size, width_limit, height_limit)
            or math.min(width_limit, height_limit)
    end
    pad_size = math.max(100, pad_size or 300)
    self.current_pad_size = pad_size

    local pad_x = layout_x
    local pad_y = layout_y
    if available_width and available_height then
        if self.pad_size then
            pad_x = layout_x + 26
            pad_y = layout_y + 38
        else
            pad_x = layout_x + frame
            pad_y = layout_y + frame
        end
    end
    call_imgui(imgui, "SetCursorScreenPos", ctx, pad_x, pad_y)

    local target_inset = math.min(22, pad_size / 4)

    local invisible_button = imgui_member(imgui, "InvisibleButton")
    if type(invisible_button) == "function" then
        invisible_button(ctx, "##track_fx_matrix_pad", pad_size, pad_size)
    elseif type(imgui.Button) == "function" then
        imgui.Button(ctx, "##track_fx_matrix_pad", pad_size, pad_size)
    end

    local pad_active = interactive
        and call_imgui(imgui, "IsItemActive", ctx) == true
    local pad_hovered = interactive
        and call_imgui(imgui, "IsItemHovered", ctx) == true
    local double_clicked_cursor = false
    if pad_hovered and call_imgui(imgui, "IsMouseDoubleClicked", ctx, 0) == true then
        local mouse_x, mouse_y = call_imgui(imgui, "GetMousePos", ctx)
        local cursor_x = pad_x + snapshot.cursor.x * pad_size
        local cursor_y = pad_y + snapshot.cursor.y * pad_size
        local hit_radius = math.max(20, math.min(30, pad_size * 0.04))
        double_clicked_cursor = mouse_x
                and mouse_y
                and (mouse_x - cursor_x) ^ 2 + (mouse_y - cursor_y) ^ 2 <= hit_radius ^ 2
        if double_clicked_cursor then
            self:_move_cursor(0.5, 0.5)
        end
    end

    if pad_active then
        self.cursor_drag_active = true
        if not double_clicked_cursor then
            local mouse_x, mouse_y = call_imgui(imgui, "GetMousePos", ctx)
            if mouse_x and mouse_y then
                local x = clamp((mouse_x - pad_x) / pad_size, 0, 1)
                local y = clamp((mouse_y - pad_y) / pad_size, 0, 1)
                self:_move_cursor(x, y)
            end
        end
    elseif self.cursor_drag_active then
        self.cursor_drag_active = false
        self:_clear_cursor_trail()
    end

    local draw_list = call_imgui(imgui, "GetWindowDrawList", ctx)
    if draw_list then
        local draw_flags = imgui_member(imgui, "DrawFlags_None") or 0
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", pad_x, pad_y, pad_x + pad_size, pad_y + pad_size, COLORS.panel)
        local half = pad_size / 2
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", pad_x, pad_y, pad_x + half, pad_y + half, color_with_alpha(CORNER_COLORS[1], 14))
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", pad_x + half, pad_y, pad_x + pad_size, pad_y + half, color_with_alpha(CORNER_COLORS[2], 14))
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", pad_x, pad_y + half, pad_x + half, pad_y + pad_size, color_with_alpha(CORNER_COLORS[3], 14))
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", pad_x + half, pad_y + half, pad_x + pad_size, pad_y + pad_size, color_with_alpha(CORNER_COLORS[4], 14))
        self:_draw_list_call(draw_list, "DrawList_AddRect", pad_x, pad_y, pad_x + pad_size, pad_y + pad_size, COLORS.line, 8, draw_flags, 1.5)

        for division = 1, 3 do
            local offset = pad_size * division / 4
            self:_draw_list_call(draw_list, "DrawList_AddLine", pad_x + offset, pad_y, pad_x + offset, pad_y + pad_size, color_with_alpha(COLORS.grid, 95), 1)
            self:_draw_list_call(draw_list, "DrawList_AddLine", pad_x, pad_y + offset, pad_x + pad_size, pad_y + offset, color_with_alpha(COLORS.grid, 95), 1)
        end
        self:_draw_matrix_background(
            draw_list,
            pad_x,
            pad_y,
            pad_size,
            snapshot.cursor.x,
            snapshot.cursor.y
        )

    end

    local corners = {
        {id = 1, x = pad_x + target_inset, y = pad_y + target_inset},
        {id = 2, x = pad_x + pad_size - target_inset, y = pad_y + target_inset},
        {id = 3, x = pad_x + target_inset, y = pad_y + pad_size - target_inset},
        {id = 4, x = pad_x + pad_size - target_inset, y = pad_y + pad_size - target_inset},
    }
    local has_parameters = next(snapshot.parameters) ~= nil
    for _, corner in ipairs(corners) do
        local corner_mapped = corner_has_saved_mapping(snapshot, corner.id)
        local target_clicked = self:_draw_corner_target(corner, interactive and corner_mapped)
        local number_clicked = self:_draw_corner_actions(
            corner,
            pad_size,
            interactive,
            pad_x,
            pad_y,
            interactive and has_parameters,
            corner_mapped
        )
        if target_clicked or number_clicked then
            local snap_x = (corner.id == 1 or corner.id == 3) and 0 or 1
            local snap_y = (corner.id == 1 or corner.id == 2) and 0 or 1
            local snapped = self:_move_cursor(snap_x, snap_y, corner.id)
            if not snapped then
                self.feedback_until = 0
            end
        end
    end

    if draw_list then
        local cursor_x = pad_x + snapshot.cursor.x * pad_size
        local cursor_y = pad_y + snapshot.cursor.y * pad_size
        for history_index = 2, #self.cursor_history do
            local previous = self.cursor_history[history_index - 1]
            local current = self.cursor_history[history_index]
            self:_draw_list_call(
                draw_list,
                "DrawList_AddLine",
                pad_x + previous.x * pad_size,
                pad_y + previous.y * pad_size,
                pad_x + current.x * pad_size,
                pad_y + current.y * pad_size,
                color_with_alpha(COLORS.active, 35 + history_index * 8),
                2
            )
        end
        self:_draw_list_call(draw_list, "DrawList_AddLine", cursor_x, pad_y, cursor_x, pad_y + pad_size, color_with_alpha(COLORS.cursor, 55), 1)
        self:_draw_list_call(draw_list, "DrawList_AddLine", pad_x, cursor_y, pad_x + pad_size, cursor_y, color_with_alpha(COLORS.cursor, 55), 1)
        self:_draw_list_call(draw_list, "DrawList_AddCircleFilled", cursor_x, cursor_y, 18, color_with_alpha(COLORS.active, 35))
        self:_draw_list_call(draw_list, "DrawList_AddCircleFilled", cursor_x, cursor_y, 10, COLORS.cursor)
        self:_draw_list_call(draw_list, "DrawList_AddCircle", cursor_x, cursor_y, 12, COLORS.cursor_shadow, 28, 2)
    end

    if available_width and available_height then
        local dummy = imgui_member(imgui, "Dummy")
        if type(dummy) == "function" then
            call_imgui(
                imgui,
                "SetCursorScreenPos",
                ctx,
                layout_x + available_width - 1,
                layout_y + available_height - 1
            )
            dummy(ctx, 1, 1)
        end
    end

end

function TrackFXMatrixUI:draw_corner_controls(active)
    local imgui = self.imgui
    local ctx = self.context
    active = active or self.controller:get_active()
    local snapshot = active
            and active.engine
            and type(active.engine.get_snapshot) == "function"
            and active.engine:get_snapshot()
        or nil
    local has_parameters = snapshot
            and snapshot.parameters
            and next(snapshot.parameters) ~= nil

    if imgui.Button(ctx, "Randomize All", 142, 28) and has_parameters then
        self:invoke("Randomize All Matrix Corners", function()
            return self.controller:randomize_all()
        end)
    end
    imgui.SameLine(ctx)
    if imgui.Button(ctx, "Clear Mappings", 142, 28) and has_parameters then
        self:invoke("Clear Matrix Mappings", function()
            return self.controller:clear_mappings()
        end)
    end
    imgui.SameLine(ctx)
    local style_color_count = 0
    if not has_parameters and type(imgui.PushStyleColor) == "function" then
        local disabled_button = color_with_alpha(COLORS.dim, 120)
        local disabled_text = color_with_alpha(COLORS.muted, 150)
        local function push_color(name, color)
            local color_id = imgui_member(imgui, name)
            if color_id ~= nil then
                imgui.PushStyleColor(ctx, color_id, color)
                style_color_count = style_color_count + 1
            end
        end
        push_color("Col_Button", disabled_button)
        push_color("Col_ButtonHovered", disabled_button)
        push_color("Col_ButtonActive", disabled_button)
        push_color("Col_Text", disabled_text)
    end
    local mappings_clicked = type(imgui.Button) == "function"
        and imgui.Button(ctx, "Mappings", 142, 28) == true
    if style_color_count > 0 and type(imgui.PopStyleColor) == "function" then
        imgui.PopStyleColor(ctx, style_color_count)
    end
    if mappings_clicked and has_parameters then
        self:_set_drawer_open(self.drawer_target_open ~= true, true)
    end
end

function TrackFXMatrixUI:_read_parameter_value(active, parameter_index, parameter)
    local snapshot = active.engine:get_snapshot()
    local corners = parameter.corners or {}
    local value = corners[1] or parameter.baseline or 0
    if type(snapshot.get_effective_value) == "function" then
        value = snapshot:get_effective_value(parameter_index) or value
    end

    local adapter = active.descriptor and active.descriptor.adapter
    if adapter and type(adapter.get_parameter_normalized) == "function" then
        local ok, live_value = pcall(adapter.get_parameter_normalized, adapter, parameter_index)
        if ok and type(live_value) == "number" then
            value = live_value
        end
    end

    if self.row_edit_index == parameter_index and self.row_display_values[parameter_index] ~= nil then
        value = self.row_display_values[parameter_index]
    else
        self.row_display_values[parameter_index] = nil
    end
    return clamp(value, 0, 1)
end

function TrackFXMatrixUI:_format_parameter_value(active, parameter_index, value)
    local adapter = active.descriptor and active.descriptor.adapter
    if adapter and type(adapter.format_parameter_value) == "function" then
        local ok, formatted = pcall(adapter.format_parameter_value, adapter, parameter_index, value)
        if ok and type(formatted) == "string" and formatted ~= "" then
            return formatted
        end
    end
    return string.format("%.0f%%", value * 100)
end

function TrackFXMatrixUI:_parameter_is_toggle(active, parameter_index)
    local adapter = active.descriptor and active.descriptor.adapter
    if not adapter or type(adapter.get_parameter_step_sizes) ~= "function" then
        return false
    end
    local ok, _, _, _, is_toggle = pcall(
        adapter.get_parameter_step_sizes,
        adapter,
        parameter_index
    )
    return ok and is_toggle == true
end

function TrackFXMatrixUI:_draw_parameter_fader(active, parameter_index, parameter, value, row_width)
    local imgui = self.imgui
    local ctx = self.context
    local fader_width = math.max(90, row_width - 126)
    local fader_height = 22
    local clamp_min, clamp_max = parameter_clamp_bounds(parameter)
    local fader_x, fader_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
    fader_x = fader_x or 0
    fader_y = fader_y or 0

    local invisible_button = imgui_member(imgui, "InvisibleButton")
    if type(invisible_button) == "function" then
        invisible_button(ctx, "##parameter_value_" .. tostring(parameter_index), fader_width, fader_height)
    elseif type(imgui.Button) == "function" then
        imgui.Button(ctx, "##parameter_value_" .. tostring(parameter_index), fader_width, fader_height)
    end

    local row_active = call_imgui(imgui, "IsItemActive", ctx) == true
    if row_active then
        local mouse_x = call_imgui(imgui, "GetMousePos", ctx)
        if mouse_x then
            local minimum_x = fader_x + fader_width * clamp_min
            local maximum_x = fader_x + fader_width * clamp_max
            if self.parameter_drag_index ~= parameter_index then
                local minimum_distance = math.abs(mouse_x - minimum_x)
                local maximum_distance = math.abs(mouse_x - maximum_x)
                local handle_hit_radius = math.max(10, math.min(16, fader_width * 0.08))
                local drag_mode
                if clamp_min == clamp_max and minimum_distance <= handle_hit_radius then
                    drag_mode = mouse_x < minimum_x and "clamp_min" or "clamp_max"
                elseif minimum_distance <= handle_hit_radius
                    and minimum_distance <= maximum_distance then
                    drag_mode = "clamp_min"
                elseif maximum_distance <= handle_hit_radius then
                    drag_mode = "clamp_max"
                else
                    drag_mode = "value"
                end
                self.parameter_drag_index = parameter_index
                self.parameter_drag_mode = drag_mode
            end

            local changed
            local edit_error
            if self.parameter_drag_mode == "clamp_min" then
                local edited_minimum = clamp((mouse_x - fader_x) / fader_width, 0, clamp_max)
                if type(self.controller.set_parameter_clamp) == "function" then
                    changed, edit_error = self.controller:set_parameter_clamp(
                        parameter_index,
                        edited_minimum,
                        clamp_max
                    )
                else
                    changed = false
                    edit_error = "parameter clamp editing is unavailable"
                end
                if changed ~= false then
                    clamp_min = edited_minimum
                    value = clamp(value, clamp_min, clamp_max)
                    self.row_display_values[parameter_index] = value
                end
            elseif self.parameter_drag_mode == "clamp_max" then
                local edited_maximum = clamp((mouse_x - fader_x) / fader_width, clamp_min, 1)
                if type(self.controller.set_parameter_clamp) == "function" then
                    changed, edit_error = self.controller:set_parameter_clamp(
                        parameter_index,
                        clamp_min,
                        edited_maximum
                    )
                else
                    changed = false
                    edit_error = "parameter clamp editing is unavailable"
                end
                if changed ~= false then
                    clamp_max = edited_maximum
                    value = clamp(value, clamp_min, clamp_max)
                    self.row_display_values[parameter_index] = value
                end
            else
                local edited_value = clamp((mouse_x - fader_x) / fader_width, 0, 1)
                if self:_parameter_is_toggle(active, parameter_index) then
                    edited_value = edited_value >= 0.5 and 1 or 0
                end
                changed, edit_error = self.controller:set_parameter_value(
                    parameter_index,
                    edited_value,
                    true
                )
                if changed ~= false then
                    value = edited_value
                    clamp_min = math.min(clamp_min, edited_value)
                    clamp_max = math.max(clamp_max, edited_value)
                    self.row_display_values[parameter_index] = edited_value
                end
            end

            if changed == false then
                self.error_message = edit_error or "unable to edit mapped parameter"
            else
                self.row_edit_index = parameter_index
                self.row_edit_active = true
            end
        end
    end

    local draw_list = call_imgui(imgui, "GetWindowDrawList", ctx)
    if draw_list then
        local draw_flags = imgui_member(imgui, "DrawFlags_None") or 0
        local display_value = clamp(value, 0, 1)
        local minimum_x = fader_x + fader_width * clamp_min
        local maximum_x = fader_x + fader_width * clamp_max
        local fill_color = parameter.bypassed
                and color_with_alpha(COLORS.dim, 170)
            or row_active and COLORS.active
            or COLORS.cool
        local clamp_color = parameter.bypassed
                and color_with_alpha(COLORS.dim, 90)
            or color_with_alpha(COLORS.locked, 85)
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", fader_x, fader_y, fader_x + fader_width, fader_y + fader_height, COLORS.panel_alt, 5)
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", minimum_x, fader_y + 2, maximum_x, fader_y + fader_height - 2, clamp_color, 3)
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", fader_x, fader_y, fader_x + fader_width * display_value, fader_y + fader_height, color_with_alpha(fill_color, 170), 5)
        self:_draw_list_call(draw_list, "DrawList_AddRect", fader_x, fader_y, fader_x + fader_width, fader_y + fader_height, COLORS.line, 5, draw_flags, 1)
        local handle_color = parameter.bypassed and COLORS.dim or COLORS.locked
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", minimum_x - 2, fader_y - 3, minimum_x + 2, fader_y + fader_height + 3, handle_color, 2)
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", maximum_x - 2, fader_y - 3, maximum_x + 2, fader_y + fader_height + 3, handle_color, 2)
        self:_draw_list_call(draw_list, "DrawList_AddCircleFilled", fader_x + fader_width * display_value, fader_y + fader_height / 2, 7, fill_color)
        self:_draw_list_call(draw_list, "DrawList_AddCircle", fader_x + fader_width * display_value, fader_y + fader_height / 2, 8, COLORS.cursor_shadow, 20, 1.5)
    end

    if call_imgui(imgui, "IsItemHovered", ctx) == true and type(imgui.SetTooltip) == "function" then
        local tooltip = self:_format_parameter_value(active, parameter_index, value)
        local mouse_x = call_imgui(imgui, "GetMousePos", ctx)
        if mouse_x then
            local minimum_x = fader_x + fader_width * clamp_min
            local maximum_x = fader_x + fader_width * clamp_max
            local handle_hit_radius = math.max(10, math.min(16, fader_width * 0.08))
            if math.abs(mouse_x - minimum_x) <= handle_hit_radius then
                tooltip = "Lower Matrix clamp: "
                    .. self:_format_parameter_value(active, parameter_index, clamp_min)
            elseif math.abs(mouse_x - maximum_x) <= handle_hit_radius then
                tooltip = "Upper Matrix clamp: "
                    .. self:_format_parameter_value(active, parameter_index, clamp_max)
            end
        end
        imgui.SetTooltip(ctx, tooltip)
    end
    return value, row_active
end

function TrackFXMatrixUI:_draw_parameter_corner_chip(parameter_index, corner_id, active_row, enabled, assigned)
    local imgui = self.imgui
    local ctx = self.context
    local chip_size = 22
    local chip_x, chip_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
    chip_x = chip_x or 0
    chip_y = chip_y or 0
    local left_clicked = false
    local right_clicked = false
    local hovered = false
    local invisible_button = imgui_member(imgui, "InvisibleButton")
    if type(invisible_button) == "function" then
        invisible_button(ctx, "##parameter_corner_" .. parameter_index .. "_" .. corner_id, chip_size, chip_size)
        hovered = call_imgui(imgui, "IsItemHovered", ctx) == true
        left_clicked = call_imgui(imgui, "IsItemClicked", ctx) == true
        if assigned == true then
            local right_button = imgui_member(imgui, "MouseButton_Right")
            right_button = type(right_button) == "number" and right_button or 1
            right_clicked = hovered
                and call_imgui(imgui, "IsItemClicked", ctx, right_button) == true
        end
    elseif type(imgui.Button) == "function" then
        left_clicked = imgui.Button(ctx, tostring(corner_id) .. "##parameter_corner_" .. parameter_index .. "_" .. corner_id, chip_size, chip_size) == true
        hovered = call_imgui(imgui, "IsItemHovered", ctx) == true
        if assigned == true then
            local right_button = imgui_member(imgui, "MouseButton_Right")
            right_button = type(right_button) == "number" and right_button or 1
            right_clicked = hovered
                and call_imgui(imgui, "IsItemClicked", ctx, right_button) == true
        end
    end

    local key_mods = call_imgui(imgui, "GetKeyMods", ctx)
    local ctrl_modifier = imgui_member(imgui, "Mod_Ctrl")
    local ctrl_down = type(key_mods) == "number"
        and type(ctrl_modifier) == "number"
        and (key_mods & ctrl_modifier) ~= 0
    local ctrl_left_clicked = left_clicked and ctrl_down
    local remove_clicked = enabled ~= false
        and assigned == true
        and (right_clicked or ctrl_left_clicked)
    local clicked = enabled ~= false
        and left_clicked
        and not right_clicked
        and not ctrl_left_clicked

    local draw_list = call_imgui(imgui, "GetWindowDrawList", ctx)
    if draw_list then
        local color = CORNER_COLORS[corner_id]
        local label = tostring(corner_id)
        local text_width, text_height = call_imgui(imgui, "CalcTextSize", ctx, label)
        text_width = type(text_width) == "number" and text_width or 8
        text_height = type(text_height) == "number" and text_height or 14
        local alpha = enabled == false and 65
                or assigned == true and 255
                or hovered and 220
            or 115
        self:_draw_list_call(draw_list, "DrawList_AddRectFilled", chip_x, chip_y, chip_x + chip_size, chip_y + chip_size, color_with_alpha(COLORS.panel_alt, 245), 5)
        self:_draw_list_call(draw_list, "DrawList_AddCircleFilled", chip_x + chip_size / 2, chip_y + chip_size / 2, 7, color_with_alpha(color, alpha))
        self:_draw_list_call(
            draw_list,
            "DrawList_AddText",
            chip_x + (chip_size - text_width) / 2,
            chip_y + (chip_size - text_height) / 2,
            color_with_alpha(COLORS.background, alpha),
            label
        )
    end
    if hovered and type(imgui.SetTooltip) == "function" then
        local tooltip = "Store this parameter in corner " .. tostring(corner_id)
        if assigned then
            tooltip = tooltip .. "; right-click or Ctrl-click to remove"
        end
        imgui.SetTooltip(ctx, tooltip)
    end
    return clicked, remove_clicked
end

function TrackFXMatrixUI:_commit_row_edit()
    if not self.row_edit_index then
        return
    end
    if type(self.controller.commit_cursor) == "function" then
        local committed, commit_error = self.controller:commit_cursor()
        if committed == false then
            self.error_message = commit_error or "unable to save mapped parameter"
        end
    end
    self.row_display_values[self.row_edit_index] = nil
    self.row_edit_index = nil
    self.parameter_drag_index = nil
    self.parameter_drag_mode = nil
end

function TrackFXMatrixUI:draw_parameters(active, show_header)
    local imgui = self.imgui
    local ctx = self.context
    if not active or not active.engine then
        return
    end

    local snapshot = active.engine:get_snapshot()
    local parameter_indices = sorted_parameter_indices(snapshot.parameters)
    local previous_edit_index = self.row_edit_index
    local previous_edit_active = self.row_edit_active
    self.row_edit_active = false

    if show_header ~= false then
        imgui.Text(ctx, string.format("MAPPED  %02d", #parameter_indices))
    end
    if #parameter_indices == 0 then
        if previous_edit_index and previous_edit_active then
            self:_commit_row_edit()
        end
        return
    end

    for _, parameter_index in ipairs(parameter_indices) do
        local parameter = snapshot.parameters[parameter_index]
        local row_width = call_imgui(imgui, "GetContentRegionAvail", ctx) or 300
        local value = self:_read_parameter_value(active, parameter_index, parameter)
        local formatted_value = self:_format_parameter_value(active, parameter_index, value)
        local parameter_name = parameter.name ~= "" and parameter.name or "Parameter " .. tostring(parameter_index)

        imgui.Text(ctx, parameter_name)
        imgui.SameLine(ctx)
        imgui.Text(ctx, formatted_value)
        imgui.SameLine(ctx)
        local bypass_clicked = self:icon_button(
            "parameter-bypass-" .. tostring(parameter_index),
            parameter.bypassed and "Include parameter in the Matrix" or "Exclude parameter from the Matrix",
            parameter.bypassed and "lock" or "unlock",
            22,
            parameter.bypassed,
            true
        )
        if bypass_clicked then
            self:invoke("Toggle Matrix Parameter Bypass", function()
                return self.controller:set_bypass(parameter_index, not parameter.bypassed)
            end)
        end
        imgui.SameLine(ctx)
        if self:icon_button(
            "parameter-release-" .. tostring(parameter_index),
            "Release parameter from the Matrix",
            "clear",
            22,
            false,
            true
        ) then
            self:invoke("Release Matrix Parameter", function()
                return self.controller:release_parameter(parameter_index)
            end)
        end

        if type(imgui.NewLine) == "function" then
            imgui.NewLine(ctx)
        end
        value, _ = self:_draw_parameter_fader(active, parameter_index, parameter, value, row_width)
        imgui.SameLine(ctx)
        for corner_id = 1, 4 do
            local assigned = parameter_corner_is_saved(parameter, corner_id)
            local corner_clicked, remove_clicked = self:_draw_parameter_corner_chip(
                parameter_index,
                corner_id,
                self.row_edit_index == parameter_index,
                not parameter.bypassed,
                assigned
            )
            if remove_clicked then
                local removed = self:invoke("Remove Matrix Parameter Corner", function()
                    return self.controller:remove_parameter_from_corner(
                        parameter_index,
                        corner_id
                    )
                end)
                if removed ~= false then
                    self:_mark_feedback(corner_id, "remove")
                end
            elseif corner_clicked then
                local saved = self:invoke("Assign Matrix Parameter Corner", function()
                    return self.controller:save_parameter_to_corner(parameter_index, corner_id)
                end)
                if saved ~= false then
                    self:_mark_feedback(corner_id, "parameter")
                end
            end
            if corner_id < 4 then
                imgui.SameLine(ctx)
            end
        end
        if type(imgui.NewLine) == "function" then
            imgui.NewLine(ctx)
        end
        imgui.Separator(ctx)
    end

    if previous_edit_index and previous_edit_active and not self.row_edit_active then
        self:_commit_row_edit()
    end
end

function TrackFXMatrixUI:_draw_parameter_drawer(active, width, height)
    local imgui = self.imgui
    local ctx = self.context
    local begin_child = imgui_member(imgui, "BeginChild")
    if type(begin_child) ~= "function" then
        self:draw_parameters(active)
        return
    end

    local child_flags = imgui_member(imgui, "ChildFlags_Borders") or 0
    local visible = begin_child(ctx, "##mapped_parameter_drawer", width, height, child_flags, 0)
    if visible then
        self:draw_parameters(active, false)
        imgui.EndChild(ctx)
    end
end

function TrackFXMatrixUI:_draw_matrix_content(active, snapshot, width, height)
    self:draw_pad(snapshot, active ~= nil, width, height)
end

function TrackFXMatrixUI:_get_workspace_layout(snapshot, available_width, available_height)
    local parameter_count = count_parameters(snapshot.parameters)
    self:_sync_drawer_state(parameter_count, available_width)

    local drawer_width = clamp(available_width * 0.31, 300, 360)
    local drawer_visible = parameter_count > 0
        and self.drawer_target_open
    local trailing_width = drawer_visible and drawer_width or 0
    local matrix_available_width = available_width
        - (trailing_width > 0 and trailing_width + 12 or 0)
    local matrix_side = math.max(220, math.min(available_height, matrix_available_width))
    local group_width = matrix_side
        + (trailing_width > 0 and trailing_width + 12 or 0)
    local group_offset = math.max(0, (available_width - group_width) / 2)

    return {
        parameter_count = parameter_count,
        drawer_width = drawer_width,
        drawer_visible = drawer_visible,
        trailing_width = trailing_width,
        matrix_side = matrix_side,
        group_width = group_width,
        group_offset = group_offset,
    }
end

function TrackFXMatrixUI:_draw_workspace(active, snapshot, available_width, available_height, layout)
    local imgui = self.imgui
    local ctx = self.context
    layout = layout or self:_get_workspace_layout(snapshot, available_width, available_height)
    local parameter_count = layout.parameter_count
    local drawer_width = layout.drawer_width
    local drawer_visible = layout.drawer_visible
    local matrix_side = layout.matrix_side
    local group_width = layout.group_width

    local cursor_x, cursor_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
    local group_offset = layout.group_offset
    if cursor_x and cursor_y and type(imgui.SetCursorScreenPos) == "function" then
        imgui.SetCursorScreenPos(ctx, cursor_x + group_offset, cursor_y)
    end

    local begin_child = imgui_member(imgui, "BeginChild")
    if type(begin_child) == "function" then
        local child_flags = imgui_member(imgui, "ChildFlags_None") or 0
        local window_flags = imgui_member(imgui, "WindowFlags_NoScrollbar") or 0
        local main_visible = begin_child(ctx, "##matrix_workspace", matrix_side, matrix_side, child_flags, window_flags)
        if main_visible then
            self:_draw_matrix_content(active, snapshot, matrix_side, matrix_side)
            imgui.EndChild(ctx)
        end
    else
        self:_draw_matrix_content(active, snapshot, matrix_side, matrix_side)
    end

    if drawer_visible then
        imgui.SameLine(ctx)
        self:_draw_parameter_drawer(active, drawer_width, matrix_side)
    end

    if cursor_x and cursor_y and type(imgui.Dummy) == "function" then
        call_imgui(
            imgui,
            "SetCursorScreenPos",
            ctx,
            cursor_x + group_offset + group_width - 1,
            cursor_y + matrix_side - 1
        )
        imgui.Dummy(ctx, 1, 1)
    end
end

function TrackFXMatrixUI:poll_learning()
    if self.mappings_locked then
        return false
    end

    local active = self.controller:get_active()
    if not active then
        return false
    end

    if type(self.controller.is_active_fx_focused) ~= "function"
        or not self.controller:is_active_fx_focused() then
        return false
    end

    if self.learning_record_id ~= active.record_id then
        self.learning_record_id = active.record_id
        self.last_learned_parameter_index = nil
    end

    local parameter_index, error_message = self.controller:get_last_touched_parameter()
    if parameter_index == nil then
        if error_message and error_message ~= "no Track-FX parameter has been touched" then
            self.error_message = error_message
        end
        return false
    end

    if parameter_index == self.stale_last_touched_parameter_index then
        return false
    end
    if self.stale_last_touched_parameter_index ~= nil then
        self.stale_last_touched_parameter_index = nil
    end

    if parameter_index == self.last_learned_parameter_index then
        return false
    end

    local snapshot = active.engine:get_snapshot()
    if snapshot.parameters[parameter_index] then
        self.last_learned_parameter_index = parameter_index
        return false
    end

    self.last_learned_parameter_index = parameter_index
    return self:invoke("Learn Track-FX Parameter", function()
        return self.controller:learn_parameter(parameter_index)
    end)
end

function TrackFXMatrixUI:draw()
    local imgui = self.imgui
    local ctx = self.context
    self:_set_next_window_size()
    self:_push_style()
    local visible, open = imgui.Begin(
        ctx,
        "Morph Matrix - Track FX",
        true,
        imgui_member(imgui, "WindowFlags_MenuBar") or 0
    )
    self.open = open

    if visible then
        self:draw_menu_bar()
        self:draw_header(false)
        local active = self.controller:get_active()
        if active then
            if type(self.controller.reconcile_active_parameters) == "function" then
                local _, reconcile_error = self.controller:reconcile_active_parameters()
                if reconcile_error then
                    self.error_message = reconcile_error
                end
            end
            active = self.controller:get_active()
            if active then
                self:poll_learning()
            end
        end
        local snapshot = active and active.engine:get_snapshot() or {
            cursor = {x = 0.5, y = 0.5},
            parameters = {},
        }
        if type(imgui.NewLine) == "function" then
            imgui.NewLine(ctx)
        end
        local available_width, available_height = call_imgui(imgui, "GetContentRegionAvail", ctx)
        available_width = math.max(220, available_width or self.default_width - 40)
        available_height = math.max(220, available_height or self.default_height - 180)
        local content_x, content_y = call_imgui(imgui, "GetCursorScreenPos", ctx)
        content_x = content_x or 0
        content_y = content_y or 0
        local workspace_height = math.max(
            220,
            available_height - TOP_GRID_HEIGHT - TOP_GRID_WORKSPACE_GAP
        )
        local layout = self:_get_workspace_layout(snapshot, available_width, workspace_height)
        self:_draw_top_control_grid(active, snapshot, layout, content_x, content_y)
        self:_draw_workspace(active, snapshot, available_width, workspace_height, layout)
        if self.error_message then
            imgui.Separator(ctx)
            imgui.Text(ctx, "Status: " .. self.error_message)
        end
        imgui.End(ctx)
    end

    self:_pop_style()
    if not self.open then
        local committed, commit_error = self.controller:commit_cursor()
        if not committed then
            self.error_message = commit_error or "unable to save cursor state"
            self.open = true
        end
    end
    return self.open
end

return TrackFXMatrixUI