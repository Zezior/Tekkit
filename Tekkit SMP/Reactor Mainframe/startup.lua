-- startup.lua

local githubUrl = "https://raw.githubusercontent.com/Zezior/Tekkit/refs/heads/main/Tekkit%20SMP/Reactor%20Mainframe/"

local filesToUpdate = {
    "Reactors/main.lua",
    "Reactors/ui.lua",
    "Reactors/reactors.lua",
    "Reactors/style.lua",
    "Reactors/rednet.lua",
    "Reactors/ids.lua"
}

local function downloadFile(filePath)
    local url = githubUrl .. filePath
    print("Downloading: " .. url)  -- This will help debug the full URL
    local success, err = pcall(function()
        shell.run("wget", "-f", url, filePath)
    end)

    if not success then
        print("Failed to download " .. filePath .. ": " .. err)
        return false
    else
        print("Updated " .. filePath)
        return true
    end
end

local function fileExists(filePath)
    return fs.exists(filePath)
end

-- Update all files
for _, file in ipairs(filesToUpdate) do
    if downloadFile(file) then
        -- Introduce a small delay to ensure file writes complete
        sleep(0.5)
    end
end

-- Verify that all required files exist before running the main program
local allFilesExist = true
for _, file in ipairs(filesToUpdate) do
    if not fileExists(file) then
        print("Error: File missing - " .. file)
        allFilesExist = false
    end
end

-- Run the main program if all files were successfully downloaded
if allFilesExist then
    local success, err = pcall(function()
        shell.run("Reactors/main.lua")
    end)

    if not success then
        print("Error in startup: " .. err)
    end
else
    print("Startup aborted due to missing files.")
end
