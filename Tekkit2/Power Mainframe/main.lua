-- main.lua

-- Configuration
local monitorSide = "right"     -- Side where the monitor is connected
local modemSide = "top"         -- Side where the modem is connected

-- Load IDs Configuration
local status, ids = pcall(require, "ids")
if not status then
    print("Error loading ids.lua:", ids)
    return
end

local reactorMainframeID = ids.reactorMainframeID
local allowedSenderIDs = ids.allowedSenderIDs

-- Open the wireless modem for rednet communication
if peripheral.isPresent(modemSide) then
    rednet.open(modemSide)
    print("Rednet modem opened on side:", modemSide)
else
    print("Error: No modem found on side:", modemSide)
    return
end

-- Output the computer ID
print("Mainframe Computer ID:", os.getComputerID())

-- Wrap the monitor peripheral
local monitor = peripheral.wrap(monitorSide)
if not monitor then
    print("Error: No monitor found on side:", monitorSide)
    return
end

-- Monitor Setup
monitor.setTextScale(0.5)  -- Set the text scale to a smaller size

-- Set custom background color
local bgColor = colors.brown  -- Using 'colors.brown' as the slot for custom color
monitor.setPaletteColor(bgColor, 18 / 255, 53 / 255, 36 / 255)  -- RGB values for #123524

-- Clear the monitor fully on startup
monitor.setBackgroundColor(bgColor)
monitor.clear()

-- Button and UI Variables
local buttonList = {}  -- Store buttons for click detection
local w, h = monitor.getSize() -- Get the monitor's width and height
local page = "home"  -- Start on Home Page
local pagesData = {} -- Data for PESU pages
local refreshInterval = 5  -- Refresh data every 5 seconds
local totalStored, totalCapacity = 0, 0  -- Store totals
local pesusPerColumn = 25  -- Number of PESUs per column
local columnsPerPage = 3   -- Number of columns per page on PESU page
local pesuList = {}  -- List of all PESUs
local numPesuPages = 1  -- Number of PESU pages
local currentPesuPage = 1 -- Current PESU page displayed
local lastSentState = nil  -- Track the last sent state to prevent spamming messages

-- Variables for tracking PESU data from sender computers
local pesuDataFromSenders = {}

-- Variables to store panel data
local panelDataList = {}  -- Stores panel data, indexed by senderID

-- Variable to store reactor status
local reactorsStatus = "off" -- Default status; will be updated based on received messages
local reactorsAreOn = false  -- Track if reactors are on

-- Variables to track reactor output and time to full charge
local totalEUOutput = 0   -- Total EU/t output from reactors
local timeToFullCharge = nil   -- Time in seconds until full charge

-- Flag to indicate if display needs refresh
local displayNeedsRefresh = false

-- Variables for chunk unloaded state
local lastNonZeroDeltaTime = os.time()
local chunkUnloaded = false

-- Function to format EU values (for display purposes other than Power Usage)
local function formatEU(value)
    if value >= 1e12 then
        return string.format("%.2f T EU", value / 1e12)       -- Teraeu
    elseif value >= 1e9 then
        return string.format("%.2f Bil EU", value / 1e9)      -- Billion EU
    elseif value >= 1e6 then
        return string.format("%.2f M EU", value / 1e6)        -- Million EU
    elseif value >= 1e3 then
        return string.format("%.2f k EU", value / 1e3)        -- Thousand EU
    else
        return string.format("%.0f EU", value)                -- EU
    end
end

-- Function to format percentages
local function formatPercentage(value)
    return string.format("%.2f%%", value)
end

-- Helper function to check if a value exists in a table
function table.contains(tbl, element)
    for _, value in pairs(tbl) do
        if tonumber(value) == tonumber(element) then
            return true
        end
    end
    return false
end

-- Function to center a text within a specified column width
local function centerTextInColumn(text, columnX, columnWidth, y)
    local x = columnX + math.floor((columnWidth - #text) / 2)
    if x < columnX then x = columnX end
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

-- Function to center text across the entire screen
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
    monitor.setBackgroundColor(bgColor)
end

-- Function to define a button
local function defineButton(name, x, y, width, height, action, color)
    color = color or colors.blue  -- Default color is blue
    table.insert(buttonList, {name = name, x = x, y = y, width = width, height = height, action = action, color = color})
    drawButton(name, x, y, width, height, color)
end

-- Function to center buttons at the bottom of the screen
local function centerButtons()
    local buttonWidth = 10  -- Width of each button
    local buttonHeight = 3  -- Height of each button
    local totalButtons = 2  -- Home button + PESU page
    if numPesuPages > 1 and page == "pesu" then
        totalButtons = totalButtons + 2  -- Add Previous and Next buttons
    end
    local totalWidth = totalButtons * buttonWidth + (totalButtons - 1) * 2
    local startX = math.floor((w - totalWidth) / 2) + 1

    buttonList = {}  -- Reset button list

    -- Define Home button
    local homeButtonColor = (page == "home") and colors.green or colors.blue
    defineButton("Home", startX, h - buttonHeight + 1, buttonWidth, buttonHeight, function()
        page = "home"
        displayNeedsRefresh = true
        centerButtons()
    end, homeButtonColor)
    startX = startX + buttonWidth + 2

    -- Define PESU page button
    local pesuButtonColor = (page == "pesu") and colors.green or colors.blue
    defineButton("PESUs", startX, h - buttonHeight + 1, buttonWidth, buttonHeight, function()
        page = "pesu"
        currentPesuPage = 1
        displayNeedsRefresh = true
        centerButtons()
    end, pesuButtonColor)
    startX = startX + buttonWidth + 2

    if page == "pesu" and numPesuPages > 1 then
        -- Define Previous Page button
        defineButton("Prev", startX, h - buttonHeight + 1, buttonWidth, buttonHeight, function()
            if currentPesuPage > 1 then
                currentPesuPage = currentPesuPage - 1
                displayNeedsRefresh = true
            end
        end)
        startX = startX + buttonWidth + 2

        -- Define Next Page button
        defineButton("Next", startX, h - buttonHeight + 1, buttonWidth, buttonHeight, function()
            if currentPesuPage < numPesuPages then
                currentPesuPage = currentPesuPage + 1
                displayNeedsRefresh = true
            end
        end)
    end
end

-- Function to clear the monitor except for the buttons
local function clearMonitorExceptButtons()
    monitor.setBackgroundColor(bgColor)
    monitor.clear()
    -- Redraw buttons after clearing the screen
    for _, button in ipairs(buttonList) do
        drawButton(button.name, button.x, button.y, button.width, button.height, button.color)
    end
end

-- Check if a player clicked on a button
local function detectClick(event, side, x, y)
    if event == "monitor_touch" then
        for _, button in ipairs(buttonList) do
            if x >= button.x and x < (button.x + button.width) and y >= button.y and y < (button.y + button.height) then
                return button.action
            end
        end
    end
    return nil
end

-- Function to calculate time to full charge
local function calculateTimeToFullCharge()
    local netInput = totalEUOutput * 20  -- Convert EU/t to EU per second (20 ticks per second)
    if netInput <= 0 then
        timeToFullCharge = nil
    else
        local euNeeded = totalCapacity - totalStored
        if euNeeded <= 0 then
            timeToFullCharge = 0
        else
            timeToFullCharge = euNeeded / netInput
        end
    end
end

-- Function to process PESU data from sender computers
local function processPESUData()
    totalStored = 0
    totalCapacity = 0
    pesuList = {}

    for senderID, data in pairs(pesuDataFromSenders) do
        if data.pesuDataList then
            for _, pesuData in ipairs(data.pesuDataList) do
                totalStored = totalStored + pesuData.energy  -- Stored EU
                totalCapacity = totalCapacity + 1000000000  -- Fixed capacity 1,000,000,000 EU
                table.insert(pesuList, {
                    stored = pesuData.energy,
                    capacity = 1000000000  -- Fixed capacity
                })
            end
        end
    end

    -- Calculate number of PESU pages
    local pesusPerPage = pesusPerColumn * columnsPerPage
    numPesuPages = math.ceil(#pesuList / pesusPerPage)

    -- Recalculate button positions
    centerButtons()

    -- Organize PESUs into pages
    pagesData = {}
    for pageNum = 1, numPesuPages do
        pagesData[pageNum] = {}
        local startIdx = (pageNum - 1) * pesusPerPage + 1
        local endIdx = math.min(pageNum * pesusPerPage, #pesuList)
        for idx = startIdx, endIdx do
            table.insert(pagesData[pageNum], pesuList[idx])
        end
    end

    -- Recalculate time to full charge
    calculateTimeToFullCharge()
    displayNeedsRefresh = true
end

-- Function to display the PESU Page
local function displayPESUPage(pesuData)
    clearMonitorExceptButtons()

    -- Display PESUs
    if #pesuData == 0 then
        centerText("No PESU data available.", 3)
        return
    end

    local pesusPerPage = pesusPerColumn * columnsPerPage
    local rowsPerColumn = pesusPerColumn
    local columnWidth = math.floor(w / columnsPerPage)
    local xOffsets = {}
    for i = 1, columnsPerPage do
        xOffsets[i] = (i - 1) * columnWidth + 1
    end

    for idx, data in ipairs(pesuData) do
        local column = math.ceil(idx / rowsPerColumn)
        if column > columnsPerPage then column = columnsPerPage end  -- Prevent overflow
        local x = xOffsets[column]
        local y = 4 + ((idx - 1) % rowsPerColumn)  -- Adjusted Y position
        local fillPercentage = (data.stored / data.capacity) * 100
        setColorBasedOnPercentage(fillPercentage)

        -- Format PESU number and percentage
        local pesuNumberStr = string.format("PESU %d:", (currentPesuPage - 1) * pesusPerPage + idx)
        local percentageStr = string.format("%.2f%%", fillPercentage)

        -- Combine for total text
        local totalText = pesuNumberStr .. " " .. percentageStr

        -- Calculate positions to align text neatly within the column
        local textX = x + math.floor((columnWidth - #totalText) / 2)
        if textX < x then textX = x end  -- Ensure text doesn't go beyond the column

        monitor.setCursorPos(textX, y)
        monitor.write(totalText)
    end
    monitor.setTextColor(colors.white)
end

-- Function to display the Home Page
local function displayHomePage()
    clearMonitorExceptButtons()

    -- **Top Title**: Centered across the entire screen
    monitor.setTextColor(colors.green)
    centerText("NuclearCity Power Facility", 1)
    monitor.setTextColor(colors.white)

    -- **Left Column: Most Drained**
    local leftColumnWidth = math.floor(w / 2) - 1
    local leftColumnX = 1
    local leftTitleY = 3
    centerTextInColumn("Most Drained", leftColumnX, leftColumnWidth, leftTitleY)

    if #pesuList == 0 then
        centerTextInColumn("No PESU data available.", leftColumnX, leftColumnWidth, leftTitleY + 2)
    else
        local top10 = {}
        for idx, pesu in ipairs(pesuList) do
            table.insert(top10, {stored = pesu.stored, capacity = pesu.capacity, index = idx})
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

            -- Format PESU number and percentage
            local pesuNumberStr = string.format("PESU %d:", pesu.index)
            local percentageStr = string.format("%.2f%%", fillPercentage)

            -- Combine for total text
            local totalText = pesuNumberStr .. " " .. percentageStr

            -- Calculate positions to align text neatly within the left column
            local textX = leftColumnX + math.floor((leftColumnWidth - #totalText) / 2)
            if textX < leftColumnX then textX = leftColumnX end

            monitor.setCursorPos(textX, leftTitleY + i)
            monitor.write(totalText)
        end
        monitor.setTextColor(colors.white)
    end

    -- **Right Column: NuclearCity Power Service**
    local rightColumnWidth = math.floor(w / 2) - 1
    local rightColumnX = math.floor(w / 2) + 1
    local rightTitleY = 3
    centerTextInColumn("NuclearCity Power Service", rightColumnX, rightColumnWidth, rightTitleY)

    local panelY = rightTitleY + 1
    if next(panelDataList) == nil then
        centerText("Getting Power Stats", panelY)
    else
        for senderID, panelData in pairs(panelDataList) do
            -- Set Data Color to Blue
            monitor.setTextColor(colors.blue)
            local titleX = rightColumnX + math.floor((rightColumnWidth - #panelData.title) / 2)
            monitor.setCursorPos(titleX, panelY)
            monitor.write(panelData.title)
            panelY = panelY + 1

            if chunkUnloaded then
                -- Display "Chunk Unloaded" instead of Power Usage
                centerTextInColumn("Chunk Unloaded", rightColumnX, rightColumnWidth, panelY)
                panelY = panelY + 1
            else
                -- Display Power Usage using deltaEnergy
                local usageText = string.format("Power Usage: %.2f EU/t", panelData.deltaEnergy)  -- Added space before EU/t
                centerTextInColumn(usageText, rightColumnX, rightColumnWidth, panelY)
                panelY = panelY + 1
            end

            -- Display Fill Percentage
            local fillPercentage = panelData.fillPercentage  -- Numeric value
            local fillText = string.format("Filled: %.2f%%", fillPercentage)
            setColorBasedOnPercentage(fillPercentage)
            centerTextInColumn(fillText, rightColumnX, rightColumnWidth, panelY)
            panelY = panelY + 1  -- Increment by 1 to remove extra space
        end
        monitor.setTextColor(colors.white)
    end

    -- **Aggregating Total Power Used**
    local totalPowerUsed = 0
    for _, panelData in pairs(panelDataList) do
        if panelData.totalPowerUsed then
            totalPowerUsed = totalPowerUsed + panelData.totalPowerUsed
        end
    end

    if next(panelDataList) ~= nil then
        -- Display "Power Used: Value EU" below the Power Service section only if data is present
        monitor.setTextColor(colors.blue)  -- Set text color to blue
        local powerUsedText = string.format("Power Used: %s", formatEU(totalPowerUsed))
        centerTextInColumn(powerUsedText, rightColumnX, rightColumnWidth, panelY)
        panelY = panelY + 1
        monitor.setTextColor(colors.white)  -- Reset text color to white
    end

    -- **New Section**: Centered Texts Near the Bottom
    -- Calculate Y positions near the bottom, just above the progress bar
    local reactorStatusY = h - 10  -- Positioned above the time to full charge
    local timeToFullChargeY = h - 9 -- Just above "Total Power Capacity"
    local capacityY = h - 8        -- Just above the progress bar

    -- Display reactor status above time to full charge
    if reactorsAreOn then
        monitor.setTextColor(colors.green)
        centerText("Reactors are ON", reactorStatusY)
    else
        monitor.setTextColor(colors.red)
        centerText("Reactors are OFF", reactorStatusY)
    end
    monitor.setTextColor(colors.white)

    -- Display time to full charge
    local timeToFullChargeText = ""
    if timeToFullCharge and timeToFullCharge > 0 then
        local hours = math.floor(timeToFullCharge / 3600)
        local minutes = math.floor((timeToFullCharge % 3600) / 60)
        local seconds = math.floor(timeToFullCharge % 60)
        if hours > 0 then
            timeToFullChargeText = string.format("Power facility fully charged in: %dh %dm %ds", hours, minutes, seconds)
        elseif minutes > 0 then
            timeToFullChargeText = string.format("Power facility fully charged in: %dm %ds", minutes, seconds)
        else
            timeToFullChargeText = string.format("Power facility fully charged in: %ds", seconds)
        end
    else
        timeToFullChargeText = "Power facility fully charged in: N/A"
    end
    -- Center the timeToFullChargeText
    centerText(timeToFullChargeText, timeToFullChargeY)

    -- Display total power capacity
    monitor.setTextColor(colors.blue)  -- Set text color to blue
    local capacityText = string.format("Total Power Capacity: %s / %s", formatEU(totalStored), formatEU(totalCapacity))
    -- Center the capacityText
    centerText(capacityText, capacityY)
    monitor.setTextColor(colors.white)  -- Reset text color to white

    -- Display total fill percentage as a progress bar, centered above buttons
    local totalFillPercentage = 0
    if totalCapacity > 0 then
        totalFillPercentage = (totalStored / totalCapacity) * 100
    end
    local progressBarWidth = w - 4  -- Leave some padding on sides
    local filledBars = math.floor((totalFillPercentage / 100) * (progressBarWidth - 2))  -- Adjust for border

    local progressBarY = h - 7

    -- Draw progress bar border
    monitor.setCursorPos(3, progressBarY)
    monitor.setBackgroundColor(colors.black)
    monitor.write(string.rep(" ", progressBarWidth))  -- Top border

    monitor.setCursorPos(3, progressBarY + 1)
    monitor.write(" ")  -- Left border
    monitor.setCursorPos(2 + progressBarWidth, progressBarY + 1)
    monitor.write(" ")  -- Right border

    monitor.setCursorPos(3, progressBarY + 2)
    monitor.write(string.rep(" ", progressBarWidth))  -- Bottom border

    -- Draw filled portion
    setColorBasedOnPercentage(totalFillPercentage)
    monitor.setBackgroundColor(colors.black)
    monitor.setCursorPos(4, progressBarY + 1)
    monitor.write(string.rep(" ", progressBarWidth - 2))  -- Clear inside

    monitor.setBackgroundColor(monitor.getTextColor())
    monitor.setCursorPos(4, progressBarY + 1)
    monitor.write(string.rep(" ", filledBars))

    -- Write percentage over the progress bar
    monitor.setBackgroundColor(colors.black)  -- Set background to black for percentage text
    monitor.setTextColor(colors.white)
    local percentageText = formatPercentage(totalFillPercentage)
    local percentageX = math.floor((w - #percentageText) / 2) + 1
    monitor.setCursorPos(percentageX, progressBarY + 1)
    monitor.write(percentageText)

    monitor.setBackgroundColor(bgColor)
    monitor.setTextColor(colors.white)
end

-- Function to send commands to reactor mainframe
local function sendCommand(command)
    rednet.send(reactorMainframeID, {command = command}, "reactor_control")
end

-- Function to request reactor data
local function requestReactorData()
    rednet.send(reactorMainframeID, {command = "request_reactor_status"}, "reactor_control")
    rednet.send(reactorMainframeID, {command = "request_total_eu_output"}, "reactor_control")
end

-- Function to monitor PESU levels and control reactors
local function monitorPESU()
    while true do
        -- Calculate fill percentages
        local anyPESUBelowThreshold = false
        local allPESUAtFull = true

        for _, pesu in ipairs(pesuList) do
            local fillPercentage = (pesu.stored / pesu.capacity) * 100
            if fillPercentage <= 0.01 then
                anyPESUBelowThreshold = true
            end
            if fillPercentage < 100 then
                allPESUAtFull = false
            end
        end

        if anyPESUBelowThreshold and lastSentState ~= "turn_on_reactors" then
            sendCommand("turn_on_reactors")
            lastSentState = "turn_on_reactors"
            print("Command sent: turn_on_reactors")
        elseif allPESUAtFull and lastSentState ~= "turn_off_reactors" then
            sendCommand("turn_off_reactors")
            lastSentState = "turn_off_reactors"
            print("Command sent: turn_off_reactors")
        end

        sleep(5)  -- Adjust sleep time as needed
    end
end

-- Function to handle incoming data
local function handleIncomingData()
    while true do
        local event, senderID, message, protocol = os.pullEvent("rednet_message")
        if type(message) == "table" and message.command then
            if table.contains(allowedSenderIDs, senderID) or senderID == reactorMainframeID then
                if message.command == "pesu_data" then
                    pesuDataFromSenders[senderID] = message
                    processPESUData()
                elseif message.command == "panel_data" then
                    panelDataList[senderID] = message.panelDataList[1]
                    print(string.format("Received panel_data from sender %d: Total Power Used = %s EU", senderID, formatEU(message.panelDataList[1].totalPowerUsed)))
                    if message.panelDataList[1].deltaEnergy > 0 then
                        lastNonZeroDeltaTime = os.time()
                        chunkUnloaded = false
                    end
                elseif message.command == "reactor_status" then
                    reactorsStatus = message.status  -- "on" or "off"
                    reactorsAreOn = (message.status == "on")
                    calculateTimeToFullCharge()
                    print(string.format("Reactor Status Updated: %s", reactorsStatus))
                elseif message.command == "total_eu_output" and message.totalEUOutput then
                    totalEUOutput = message.totalEUOutput
                    calculateTimeToFullCharge()
                    print(string.format("Total EU Output Updated: %s EU/t", formatEU(totalEUOutput)))
                end
                -- Update chunk unloaded state
                if page == "home" then
                    if os.time() - lastNonZeroDeltaTime >= 20 then
                        chunkUnloaded = true
                    else
                        chunkUnloaded = false
                    end
                end
                displayNeedsRefresh = true
            else
                print("Received message from unauthorized sender ID:", senderID)
            end
        end
    end
end

-- Function to periodically request reactor data and refresh display
local function periodicUpdater()
    while true do
        requestReactorData()
        displayNeedsRefresh = true
        sleep(refreshInterval)
    end
end

-- Function to handle button presses
local function handleButtonPresses()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        local action = detectClick(event, side, x, y)
        if action then
            action()
            displayNeedsRefresh = true
        end
        sleep(0.05)
    end
end

-- Function to update the display based on current page
local function updateDisplay()
    if displayNeedsRefresh then
        if page == "home" then
            -- Check if chunk is unloaded
            if os.time() - lastNonZeroDeltaTime >= 20 then
                chunkUnloaded = true
            else
                chunkUnloaded = false
            end
            displayHomePage()
        elseif page == "pesu" then
            displayPESUPage(pagesData[currentPesuPage] or {})
        end
        displayNeedsRefresh = false
    end
end

-- Function to refresh the monitor display
local function displayLoop()
    while true do
        updateDisplay()
        sleep(0.1)
    end
end

-- Main function
local function main()
    page = "home"  -- Ensure the page is set to "home" on start

    centerButtons()  -- Center the buttons at the start

    -- Clear the monitor fully on startup
    monitor.setBackgroundColor(bgColor)
    monitor.clear()

    displayNeedsRefresh = true  -- Flag to indicate display needs refresh

    -- Start data processing and page refreshing in parallel
    parallel.waitForAll(
        handleIncomingData,
        monitorPESU,
        periodicUpdater,
        handleButtonPresses,
        displayLoop
    )
end

-- Start main function
main()
