-- @description Create a Renders folder beside the current project
-- @version 1.0.0
-- @author Giacomo Frega
-- @about
--   Creates a Renders directory next to the currently saved project.

local function create_renders_folder()
    -- Get the current project file name
    local _, current_project_path = reaper.EnumProjects(-1, '')

    -- Check if it's a new project (unsaved, no path)
    if current_project_path == '' then
        return
    end

    -- Get the directory of the current project
    local project_directory = current_project_path:match("(.*[/\\])")
    if not project_directory then
        return
    end

    -- Define the path for the new "Renders" folder
    local renders_folder_path = project_directory .. 'Renders'

    -- Create the "Renders" folder if it doesn't exist
    reaper.RecursiveCreateDirectory(renders_folder_path, 0)
end

create_renders_folder()

