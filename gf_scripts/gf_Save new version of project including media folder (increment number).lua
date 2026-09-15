-- @description Save an incremented project copy and duplicate its audio folder
-- @version 1.0.1
-- @author Giacomo Frega
-- @about
--   Saves a numbered project copy and copies its matching audio folder.

-- # Giacomo Frega, February 2026
-- Auto-Incrementing Project Backup Script
-- Saves a new copy of the project with incrementing numbers and copies audio files
-- Folder structure:
--   Project_Name/
--     Project_Name.RPP, Project_Name-01.RPP, Project_Name-02.RPP ...
--     Audio Files/, Audio Files-01/, Audio Files-02/ ...

local function copy_file(src, dst)
    local f_in = io.open(src, "rb")
    if not f_in then return false end
    local content = f_in:read("*a")
    f_in:close()
    local f_out = io.open(dst, "wb")
    if not f_out then return false end
    f_out:write(content)
    f_out:close()
    return true
end

local function main()
    -- EnumProjects returns (ReaProject, full_file_path)
    local _, proj_full_path = reaper.EnumProjects(-1, "")

    if not proj_full_path or proj_full_path == "" then
        reaper.ShowMessageBox("Project has not been saved yet. Please save the project first.", "Error", 0)
        return
    end

    -- Normalize to forward slashes
    proj_full_path = proj_full_path:gsub("\\", "/")

    -- Split into parent directory and filename
    local parent_dir = proj_full_path:match("(.+)/")
    local proj_filename = proj_full_path:match("([^/]+)$")

    if not parent_dir or not proj_filename then
        reaper.ShowMessageBox("Could not parse project path:\n" .. proj_full_path, "Error", 0)
        return
    end

    -- Separate name from extension (preserves original case of extension)
    local name_no_ext, ext = proj_filename:match("^(.+)(%.%w+)$")
    if not name_no_ext then
        reaper.ShowMessageBox("Could not parse project filename:\n" .. proj_filename, "Error", 0)
        return
    end

    -- Parse optional number suffix: "Project_Name-01" → base="Project_Name", num=1
    local base_name, current_num_str = name_no_ext:match("^(.+)-(%d+)$")

    local current_num
    local num_width = 2 -- default zero-padded width
    if base_name and current_num_str then
        current_num = tonumber(current_num_str)
        num_width = #current_num_str
    else
        -- No number suffix (original project, e.g. "Project_Name.RPP")
        base_name = name_no_ext
        current_num = 0
    end

    -- Increment
    local new_num = current_num + 1
    local new_num_str = string.format("%0" .. num_width .. "d", new_num)

    -- New project filename
    local new_proj_name = base_name .. "-" .. new_num_str .. ext
    local new_proj_path = parent_dir .. "/" .. new_proj_name

    -- Current and new audio folder names (just the folder name, no parent path)
    local current_audio_suffix
    if current_num > 0 then
        current_audio_suffix = "Audio Files-" .. string.format("%0" .. num_width .. "d", current_num)
    else
        current_audio_suffix = "Audio Files"
    end
    local new_audio_suffix = "Audio Files-" .. new_num_str

    -- Full paths
    local current_audio_folder = parent_dir .. "/" .. current_audio_suffix
    local new_audio_folder = parent_dir .. "/" .. new_audio_suffix

    -- Check that the new project file doesn't already exist
    local check = io.open(new_proj_path, "r")
    if check then
        check:close()
        reaper.ShowMessageBox("Project file already exists:\n" .. new_proj_name .. "\n\nAborting to avoid overwriting.", "Error", 0)
        return
    end

    -- Create new audio folder
    reaper.RecursiveCreateDirectory(new_audio_folder, 0)

    -- Copy audio files from current audio folder to new one
    local file_count = 0
    local idx = 0
    local file = reaper.EnumerateFiles(current_audio_folder, 0)
    if file then
        while file do
            if copy_file(current_audio_folder .. "/" .. file, new_audio_folder .. "/" .. file) then
                file_count = file_count + 1
            end
            idx = idx + 1
            file = reaper.EnumerateFiles(current_audio_folder, idx)
        end
    else
        reaper.ShowMessageBox("Current audio folder not found or empty:\n" .. current_audio_folder, "Warning", 0)
    end

    -- Save current project so the RPP file on disk is up to date
    reaper.Main_SaveProject(0, false)

    -- Read the current RPP, replace audio folder references, write as new RPP
    local rpp_in = io.open(proj_full_path, "rb")
    if not rpp_in then
        reaper.ShowMessageBox("Could not read current project file.", "Error", 0)
        return
    end
    local rpp_content = rpp_in:read("*a")
    rpp_in:close()

    -- Replace old audio folder name with new one in the RPP text
    if current_num > 0 then
        -- Numbered case: safe direct replacement (e.g. "Audio Files-01" → "Audio Files-02")
        local escaped_old = current_audio_suffix:gsub("%-", "%%-")
        rpp_content = rpp_content:gsub(escaped_old, new_audio_suffix)
    else
        -- Unnumbered case: "Audio Files" but NOT "Audio Files-NN"
        -- Match "Audio Files" only when not followed by a hyphen
        rpp_content = rpp_content:gsub("(Audio Files)([^%-])", "%1-" .. new_num_str .. "%2")
        rpp_content = rpp_content:gsub("(Audio Files)$", "%1-" .. new_num_str)
    end

    local rpp_out = io.open(new_proj_path, "wb")
    if not rpp_out then
        reaper.ShowMessageBox("Could not write new project file.", "Error", 0)
        return
    end
    rpp_out:write(rpp_content)
    rpp_out:close()

    -- Open the new project
    reaper.Main_openProject(new_proj_path)

    reaper.ShowMessageBox(
        string.format(
            "Done!\n\nNew project: %s\nAudio files copied: %d\nFrom: %s\nTo: %s",
            new_proj_name, file_count, current_audio_suffix, new_audio_suffix
        ),
        "Success", 0
    )
end

local function run_safe()
    reaper.PreventUIRefresh(1)
    local ok, err = pcall(main)
    reaper.PreventUIRefresh(-1)

    if not ok then
        reaper.ShowMessageBox("Script failed:\n" .. tostring(err), "Error", 0)
    end
end

run_safe()