-- startup.lua

local githubUrl = "https://raw.githubusercontent.com/Zezior/Tekkit/main/Tekkit%20SMP/Player%20Activity%20Status/"

local filesToUpdate = {
    "main.lua",
}

local function printUsage()
    print("Usage:")
    print("wget <url> <filename>")
end

local function get(sUrl)
    write("Connecting to " .. sUrl .. "... ")

    -- Check if the URL is valid
    local ok, err = http.checkURL(sUrl)
    if not ok then
        print("Failed.")
        if err then
            printError(err)
        end
        return nil
    end

    -- Attempt to download the file
    local response = http.get(sUrl, nil, true)
    if not response then
        print("Failed.")
        return nil
    end

    print("Success.")
    local sResponse = response.readAll()
    response.close()
    return sResponse
end

local function createBlankFileIfMissing(filePath)
    -- Create a blank file if it doesn't exist
    if not fs.exists(filePath) then
        print("File does not exist, creating blank file: " .. filePath)
        local file = fs.open(filePath, "w")  -- Open file for writing (create if missing)
        file.close()
    end
end

local function downloadFile(filePath)
    local url = githubUrl .. filePath
    print("Downloading: " .. url)

    -- Ensure the file exists by creating a blank file if necessary
    createBlankFileIfMissing(filePath)

    -- Use the get function to download the file content
    local res = get(url)
    if res then
        local file = fs.open(filePath, "wb")  -- Open in binary mode for writing
        file.write(res)
        file.close()
        print("Updated " .. filePath)
        return true
    else
        print("Failed to download " .. filePath)
        return false
    end
end

local function fileExists(filePath)
    return fs.exists(filePath)
end

-- Ensure HTTP API is enabled
if not http then
    printError("wget requires http API")
    printError("Set http_enable to true in ComputerCraft.cfg")
    return
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
        shell.run("main.lua")
    end)

    if not success then
        print("Error in startup: " .. err)
    end
else
    print("Startup aborted due to missing files.")
end
