-- @noindex

local TrackFXMatrixRuntime = {}
TrackFXMatrixRuntime.__index = TrackFXMatrixRuntime

function TrackFXMatrixRuntime.new(options)
    options = options or {}
    if not options.controller or not options.ui then
        error("TrackFXMatrixRuntime requires a controller and UI")
    end

    return setmetatable({
        api = options.api or reaper,
        controller = options.controller,
        ui = options.ui,
        context = options.context,
        show_error = options.show_error,
        context_alive = true,
    }, TrackFXMatrixRuntime)
end

function TrackFXMatrixRuntime:_report(message)
    if type(self.show_error) == "function" then
        pcall(self.show_error, message)
    end
end

function TrackFXMatrixRuntime:_commit_controller_state()
    local active
    if type(self.controller.get_active) == "function" then
        active = self.controller:get_active()
    else
        active = self.controller.active
    end
    if not active then
        return true
    end

    local dirty
    if type(self.controller.has_dirty_state) == "function" then
        dirty = self.controller:has_dirty_state()
    else
        dirty = self.controller.cursor_dirty or self.controller.parameters_dirty
    end
    if not dirty then
        return true
    end

    local ok, committed, error_message = pcall(
        self.controller.commit_cursor,
        self.controller
    )
    if not ok then
        return false, tostring(committed)
    end
    if not committed then
        return false, error_message or "unable to save cursor state"
    end
    return true
end

function TrackFXMatrixRuntime:close()
    if not self.context_alive then
        return true
    end
    self.context_alive = false

    local commit_call_ok, commit_result, commit_error = pcall(
        self._commit_controller_state,
        self
    )
    local committed = commit_result
    if not commit_call_ok then
        committed = false
        commit_error = tostring(commit_result)
    end
    if not committed then
        self:_report("Unable to save Morph Matrix state: " .. tostring(commit_error))
    end

    local destroyed = true
    local destroy_error
    if self.context and type(self.api.ImGui_DestroyContext) == "function" then
        local destroy_ok, destroy_result = pcall(
            self.api.ImGui_DestroyContext,
            self.context
        )
        destroyed = destroy_ok
        if not destroy_ok then
            destroy_error = tostring(destroy_result)
            self:_report("Unable to destroy Morph Matrix context: " .. destroy_error)
        end
    end

    if not committed then
        return false, commit_error
    end
    if not destroyed then
        return false, destroy_error
    end
    return true
end

function TrackFXMatrixRuntime:draw_frame()
    if not self.context_alive then
        return false
    end

    local draw_ok, draw_result = pcall(self.ui.draw, self.ui)
    if not draw_ok then
        self:_report("Morph Matrix UI error: " .. tostring(draw_result))
        self:close()
        return false, draw_result
    end
    if not draw_result then
        self:close()
        return false
    end
    return true
end

return TrackFXMatrixRuntime