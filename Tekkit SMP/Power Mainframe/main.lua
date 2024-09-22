-- power_mainframe.lua

-- Open the ender modem on the "top" side
rednet.open("top")

-- Variables for monitor and button handling
local monitor = peripheral.wrap("right")
monitor.setTextScale(0.5)  -- Set the text scale to a smaller size

-- Clear the monitor fully on startup
monitor.setBackgroundColor(colors.black)
monitor.clear()

local buttonList = {}  -- Store buttons for click detection
local w, h = monitor.getSize() -- Get the monitor's width and height
local page = "home"  -- Start on Home Page
local pagesData = {} -- Data for PESU pages
local refreshInterval = 2  -- Refresh PESU data every 2 seconds
local totalStored, totalCapacity = 0, 0  -- Store totals
local pesusPerColumn = 25  -- Number of PESUs per column
local columnsPerPage = 4   -- Number of columns per page
local pesusPerPage = pesusPerColumn * columnsPerPage  -- Total PESUs per page
local pesuList = {}  -- List of all PESUs
local numPesuPages = 1  -- Number of PESU pages

-- Variables for tracking PESU data from sender computers
local pesuDataFromSenders = {}
local lastEUStored = nil
local averageEUT = 0

-- Variables to store panel data
local panelDataList = {}  -- Stores panel data, indexed by panelID

-- Additional variables for timing
local lastUpdateTime = os.clock()

-- Function to format large numbers
local function formatNumber(num)
    if num >= 1e9 then
        return string.format("%.2fbil", num / 1e9)
    elseif num >= 1e6 then
        return string.format("%.2fmil", num / 1e6)
    elseif num >= 1e3 then
        return string.format("%.2fk", num / 1e3)
    else
        return tostring(num)
    end
end

-- Function to process PESU data from sender computers
local function processPESUData()
    totalStored = 0
    totalCapacity = 0
    pesuList = {}
    local currentTime = os.time()

    for senderID, data in pairs(pesuDataFromSenders) do
        -- Process PESU data
        if data.pesuDataList then
            for _, pesuData in ipairs(data.pesuDataList) do
                totalStored = totalStored + pesuData.stored
                totalCapacity = totalCapacity + pesuData.capacity
                table.insert(pesuList, {
                    stored = pesuData.stored,
                    capacity = pesuData.capacity,
                    senderID = senderID,
                    pesuName = pesuData.name
                })
            end
        end

        -- Process Panel data
        if data.panelDataList then
            for _, panelData in ipairs(data.panelDataList) do
                -- Use senderID and panelName as unique identifier
                local panelID = senderID .. "_" .. panelData.name

                -- Get existing data or initialize
                local existingData = panelDataList[panelID] or {}

                -- Update the panel data
                existingData.title = panelData.title or existingData.title
                existingData.capacity = panelData.capacity
                existingData.energy = panelData.energy

                -- Calculate average EU/t
                if existingData.lastUpdateTime then
                    local deltaTime = currentTime - existingData.lastUpdateTime
                    local deltaEnergy = existingData.lastEnergy - existingData.energy

                    if deltaTime >= 5 then  -- Adjusted to 5 seconds
                        local averageEUT = (deltaEnergy / deltaTime) / 20  -- EU/t (20 ticks per second)
                        existingData.averageEUT = averageEUT
                        existingData.lastUpdateTime = currentTime
                        existingData.lastEnergy = existingData.energy
                    end
                else
                    -- First time receiving data
                    existingData.lastUpdateTime = currentTime
                    existingData.lastEnergy = existingData.energy
                    existingData.averageEUT = nil  -- Cannot calculate yet
                end

                -- Update the panel data in the list
                panelDataList[panelID] = existingData

                -- Debug: Print panel data
                print("Panel Data for", panelID)
                print("Title:", existingData.title)
                print("Energy:", existingData.energy)
                print("Capacity:", existingData.capacity)
                print("Average EU/t:", existingData.averageEUT or "Calculating...")
            end
        end
    end

    -- Update the number of PESU pages
    numPesuPages = math.ceil(#pesuList / pesusPerPage)
    if numPesuPages < 1 then numPesuPages = 1 end

    -- Recalculate button positions
    centerButtons()

    -- Split PESUs into pages
    pagesData = {}
    for i = 1, numPesuPages do
        local startIdx = (i - 1) * pesusPerPage + 1
        local endIdx = math.min(i * pesusPerPage, #pesuList)
        pagesData[i] = {}
        for j = startIdx, endIdx do
            table.insert(pagesData[i], pesuList[j])
        end
    end
end

-- (Rest of the script remains the same)
