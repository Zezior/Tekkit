-- power_mainframe.lua

-- Configuration
local monitorSide = "right"     -- Adjust based on your setup

-- Open the modem on the "top" side
rednet.open("top")

-- Output the computer ID
print("Mainframe Computer ID:", os.getComputerID())

-- Load allowed sender IDs from ids.lua
local ids = dofile("ids.lua")
local allowedSenderIDs = ids.allowedSenderIDs

-- Variables for monitor and button handling
local monitor = peripheral.wrap(monitorSide)
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
local pesuList = {}  -- List of all PESUs
local numPesuPages = 1  -- Number of PESU pages is 1
local lastSentState = nil  -- Track the last sent state to prevent spamming messages

-- Variables for tracking PESU data from sender computers
local pesuDataFromSenders = {}
local lastEUStored = nil
local averageEUT = 0

-- Variables to store panel data
local panelDataList = {}  -- Stores panel data, indexed by senderID

-- Additional variables for timing
local lastUpdateTime = os.clock()

-- Function to format percentages
local function formatPercentage(value)
    return string.format("%.2f%%", value)
end

-- Helper function to check if a value exists in a table
function table.contains(tbl, element)
    for _, value in pairs(tbl) do
        if value == element then
            return true
        end
    end
    return false
end

-- Function to center a text on the monitor screen
local function centerText(text, y)
    local x = math.floor((w - #text) / 2) + 1
    if x < 1 then x = 1 end
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

-- Function to set color based on percentage
local function setColorBasedOnPercentage(percentage)
    if percentage >= 100 then
        monitor.setTextColor(colors.blue)
    elseif percentage >= 80 then
        monitor.setTextColor(colors.green)
    elseif percentage >= 50 then
        monitor.setTextColor(colors.yellow)
    elseif percentage >= 20 then
        monitor.setTextColor(colors.orange)
    else
        monitor.setTextColor(colors.red)
    end
end

-- Function to draw a button
local function drawButton(label, x, y, width, height, color)
    monitor.setBackgroundColor(color)
    monitor.setTextColor(colors.white)
    for i = 0, height - 1 do
        monitor.setCursorPos(x, y + i)
        monitor.write(string.rep(" ", width))
    end
    -- Center the label
    local labelX = x + math.floor((width - #label) / 2)
    local labelY = y + math.floor(height / 2)
    monitor.setCursorPos(labelX, labelY)
    monitor.write(label)
    monitor.setBackgroundColor(colors.black)
end

-- Function to define a button
local function defineButton(name, x, y, width, height, action)
    table.insert(buttonList, {name = name, x = x, y = y, width = width, height = height, action = action})
    drawButton(name, x, y, width, height, colors.blue)
end

-- Function to center buttons at the bottom of the screen
local function centerButtons()
    local buttonWidth = 10  -- Width of each button
    local buttonHeight = 3  -- Height of each button
    local totalButtons = 2  -- Home button + PESU page
    local totalWidth = totalButtons * buttonWidth + (totalButtons - 1) * 2
    local startX = math.floor((w - totalWidth) / 2) + 1

    buttonList = {}  -- Reset button list

    -- Define Home button
    defineButton("Home", startX, h - buttonHeight + 1, buttonWidth, buttonHeight, function() page = "home"; displayNeedsRefresh = true end)
    startX = startX + buttonWidth + 2

    -- Define PESU page button
    defineButton("PESUs", startX, h - buttonHeight + 1, buttonWidth, buttonHeight, function() page = "pesu"; displayNeedsRefresh = true end)
end

-- Function to clear the monitor except for the buttons
local function clearMonitorExceptButtons()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    -- Redraw buttons after clearing the screen
    for _, button in ipairs(buttonList) do
        drawButton(button.name, button.x, button.y, button.width, button.height, colors.blue)
    end
end

-- Check if a player clicked on a button
local function detectClick(event, side, x, y)
    if event == "monitor_touch" then
        for _, button in ipairs(buttonList) do
            if x >= button.x and x < button.x + button.width and y >= button.y and y < button.y + button.height then
                return button.action
            end
        end
    end
    return nil
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
                totalStored = totalStored + pesuData.energy  -- Stored EU
                totalCapacity = totalCapacity + 1000000000  -- Fixed capacity 1,000,000,000
                table.insert(pesuList, {
                    stored = pesuData.energy,
                    capacity = 1000000000  -- Fixed capacity
                })
            end
        end
    end

    -- All PESUs on one page
    numPesuPages = 1

    -- Recalculate button positions
    centerButtons()

    -- All PESUs on one page
    pagesData = {}
    pagesData[1] = pesuList

    -- Debug print
    print("Processed PESU Data. Total PESUs:", #pesuList)
end

-- Function to display the PESU Page
local function displayPESUPage(pesuData)
    clearMonitorExceptButtons()

    -- Adjusted positions
    local titleY = 1
    local dataStartY = 3  -- Start data display from line 3

    -- Centered Title
    monitor.setTextColor(colors.green)
    centerText("NuclearCity Power Facility", titleY)
    monitor.setTextColor(colors.white)

    monitor.setCursorPos(1, dataStartY)
    monitor.write("PESU List (Fill Percentage):")

    if #pesuData == 0 then
        monitor.setCursorPos(1, dataStartY + 2)
        monitor.write("No PESU data available.")
        return
    end

    local columnWidth = math.floor(w / columnsPerPage)
    local xOffsets = {}
    for i = 1, columnsPerPage do
        xOffsets[i] = (i - 1) * columnWidth + 1
    end

    for idx, data in ipairs(pesuData) do
        local column = math.ceil(idx / pesusPerColumn)
        if column > columnsPerPage then column = columnsPerPage end  -- Prevent overflow
        local x = xOffsets[column]
        local y = dataStartY + ((idx - 1) % pesusPerColumn) + 2  -- Adjusted Y position
        local fillPercentage = (data.stored / data.capacity) * 100
        setColorBasedOnPercentage(fillPercentage)
        monitor.setCursorPos(x, y)
        monitor.write(string.format("PESU: %s", formatPercentage(fillPercentage)))
    end
    monitor.setTextColor(colors.white)
end

-- Function to display the Home Page
local function displayHomePage()
    clearMonitorExceptButtons()

    -- Adjusted positions
    local titleY = 1
    local leftColumnStartY = 4
    local rightColumnStartY = 4

    -- Centered Title with green font
    monitor.setTextColor(colors.green)
    centerText("NuclearCity Power Facility", titleY)
    monitor.setTextColor(colors.white)

    local leftColumnWidth = math.floor(w / 2)
    local rightColumnWidth = w - leftColumnWidth - 1
    local leftColumnX = 1
    local rightColumnX = leftColumnWidth + 2

    -- Left Column Title centered in left half
    local leftTitle = "Most drained"
    local leftTitleX = leftColumnX + math.floor((leftColumnWidth - #leftTitle) / 2)
    monitor.setCursorPos(leftTitleX, leftColumnStartY)
    monitor.write(leftTitle)

    if #pesuList == 0 then
        monitor.setCursorPos(leftColumnX, leftColumnStartY + 2)
        monitor.write("No PESU data available.")
    else
        local top10 = {}
        for idx, pesu in ipairs(pesuList) do
            table.insert(top10, {stored = pesu.stored, capacity = pesu.capacity})
        end

        -- Sort PESUs by percentage drained (ascending)
        table.sort(top10, function(a, b)
            local aPercent = (a.stored / a.capacity)
            local bPercent = (b.stored / b.capacity)
            return aPercent < bPercent
        end)

        -- Display top 10
        for i = 1, math.min(10, #top10) do
            local pesu = top10[i]
            local fillPercentage = (pesu.stored / pesu.capacity) * 100
            setColorBasedOnPercentage(fillPercentage)
            monitor.setCursorPos(leftColumnX + 2, leftColumnStartY + i)
            monitor.write(string.format("PESU: %s", formatPercentage(fillPercentage)))
        end
        monitor.setTextColor(colors.white)
    end

    -- Right Column Title centered in right half
    local rightTitle = "NuclearCity Power Service"
    local rightTitleX = rightColumnX + math.floor((rightColumnWidth - #rightTitle) / 2)
    monitor.setCursorPos(rightTitleX, rightColumnStartY)
    monitor.write(rightTitle)

    local panelY = rightColumnStartY + 1
    if next(panelDataList) == nil then
        monitor.setCursorPos(rightColumnX, panelY)
        monitor.write("No Panel data available.")
    else
        for senderID, panelData in pairs(panelDataList) do
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(rightColumnX + 2, panelY)
            monitor.write(panelData.title)
            panelY = panelY + 1

            monitor.setCursorPos(rightColumnX + 2, panelY)
            monitor.write(string.format("Power Usage: %.2f EU/T", panelData.energyUsage))
            panelY = panelY + 1

            monitor.setCursorPos(rightColumnX + 2, panelY)
            setColorBasedOnPercentage(panelData.fillPercentage)
            monitor.write(string.format("Filled: %s", formatPercentage(panelData.fillPercentage)))
            panelY = panelY + 2  -- Add extra space between panels
        end
        monitor.setTextColor(colors.white)
    end

    -- Display total fill percentage as a progress bar, centered above buttons
    local totalFillPercentage = (totalStored / totalCapacity) * 100
    local progressBarWidth = w - 4  -- Leave some padding on sides
    local filledBars = math.floor((totalFillPercentage / 100) * progressBarWidth)
    local emptyBars = progressBarWidth - filledBars

    local progressBar = string.rep("|", filledBars) .. string.rep(" ", emptyBars)
    local progressBarY = h - 6
    setColorBasedOnPercentage(totalFillPercentage)
    monitor.setCursorPos(3, progressBarY)
    monitor.write(progressBar)
    monitor.setTextColor(colors.white)
    -- Write percentage over the progress bar
    local percentageText = formatPercentage(totalFillPercentage)
    local percentageX = math.floor((w - #percentageText) / 2) + 1
    monitor.setCursorPos(percentageX, progressBarY)
    monitor.write(percentageText)
end

-- Main function for live page updates and data processing
local function main()
    page = "home"  -- Ensure the page is set to "home" on start

    centerButtons()  -- Center the buttons at the start

    -- Clear the monitor fully on startup
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local displayNeedsRefresh = true  -- Flag to indicate display needs refresh

    -- Start data processing and page refreshing in parallel
    parallel.waitForAny(
        function()  -- PESU Data Processing Loop
            while true do
                processPESUData()
                displayNeedsRefresh = true  -- Indicate that display needs to be refreshed
                sleep(refreshInterval)  -- Wait for the next update
            end
        end,
        function()  -- UI Loop for Live Page Updates
            while true do
                if displayNeedsRefresh then
                    if page == "home" then
                        displayHomePage()  -- Refresh homepage with live data
                    elseif page == "pesu" then
                        displayPESUPage(pesuList)  -- Refresh PESU list page
                    end
                    displayNeedsRefresh = false
                end
                sleep(0.05)  -- Short sleep for smoother interaction
            end
        end,
        function()  -- Handle Button Presses in Parallel
            while true do
                local event, side, x, y = os.pullEvent("monitor_touch")
                local action = detectClick(event, side, x, y)
                if action then
                    action()  -- Switch pages based on button click
                    displayNeedsRefresh = true  -- Indicate that display needs to be refreshed
                end
                sleep(0.05)  -- Allow for faster reaction to button presses
            end
        end,
        function()  -- Handle Incoming Data
            while true do
                local event, senderID, message, protocol = os.pullEvent("rednet_message")
                print("Received message from ID:", senderID)
                if type(message) == "table" and message.command then
                    if table.contains(allowedSenderIDs, senderID) then
                        if message.command == "pesu_data" then
                            -- Store the PESU data from the sender
                            pesuDataFromSenders[senderID] = message
                            processPESUData()  -- Update data processing
                            displayNeedsRefresh = true
                            print("Processed PESU data from sender ID:", senderID)
                        elseif message.command == "panel_data" then
                            -- Store the panel data from the sender
                            panelDataList[senderID] = message.panelDataList[1]
                            displayNeedsRefresh = true
                            print("Processed panel data from sender ID:", senderID)
                        else
                            print("Unknown command from sender ID:", senderID)
                        end
                    else
                        print("Ignored data from sender ID:", senderID)
                    end
                else
                    print("Warning: Received malformed data from Sender ID:", senderID)
                end
            end
        end
    )
end

-- Start main function
main()
