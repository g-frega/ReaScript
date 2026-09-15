-- @description Morph Matrix - Track FX
-- @version 1.0.3
-- @author Giacomo Frega
-- @about
--   Explicitly register a focused Track FX, map parameters, and morph four Matrix corners.

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_directory = script_path:match("^(.*[\\/])")
local module_directory = script_directory
package.path = module_directory .. "?.lua;" .. package.path

local function load_imgui()
    if type(reaper.ImGui_GetBuiltinPath) ~= "function" then
        return nil, "ReaImGui extension is required"
    end

    local ok, imgui = pcall(function()
        package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
        return require("imgui")("0.10.0.5")
    end)
    if not ok or not imgui then
        return nil, "Unable to load ReaImGui 0.10.0.5"
    end
    return imgui
end

local function run_command(label, operation)
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    local ok, result, error_message = pcall(operation)
    reaper.PreventUIRefresh(-1)

    if ok then
        reaper.UpdateArrange()
        reaper.Undo_EndBlock(label, -1)
        return true, result, error_message
    end

    reaper.Undo_EndBlock(label .. " (failed)", -1)
    return false, nil, tostring(result)
end

local function show_error(message)
    if type(reaper.ShowMessageBox) == "function" then
        reaper.ShowMessageBox(message, "Morph Matrix - Track FX", 0)
    end
end

local function main()
    local imgui, imgui_error = load_imgui()
    if not imgui then
        show_error(imgui_error)
        return
    end

    local ok, Controller = pcall(require, "Core.TrackFXMatrixController")
    if not ok then
        show_error(Controller)
        return
    end
    local ui_ok, MatrixUI = pcall(require, "UI.TrackFXMatrixUI")
    if not ui_ok then
        show_error(MatrixUI)
        return
    end
    local runtime_ok, Runtime = pcall(require, "Core.TrackFXMatrixRuntime")
    if not runtime_ok then
        show_error(Runtime)
        return
    end

    local controller = Controller.new()
    controller:discover_focused_fx()
    local ui = MatrixUI.new(imgui, controller, {
        command = run_command,
    })
    local context = imgui.CreateContext("Morph Matrix - Track FX")
    if not context then
        show_error("Unable to create the ReaImGui context")
        return
    end
    ui:set_context(context)

    local runtime = Runtime.new({
        api = reaper,
        controller = controller,
        ui = ui,
        context = context,
        show_error = show_error,
    })
    local function close_context()
        runtime:close()
    end
    reaper.atexit(close_context)

    local function loop()
        if not runtime:draw_frame() then
            return
        end
        reaper.defer(loop)
    end
    reaper.defer(loop)
end

main()