-- Power mainframe main.lua

-- Configuration
local monitorSide = "right"     -- Adjust based on your setup
local modemSide = "top"         -- Adjust based on your setup

-- Open the modem on the specified side
rednet.open(modemSide)

-- Output the computer ID
print("Mainframe Computer ID:", os.getComputerID())

-- Load allowed sender IDs from ids.lua
local ids = require("ids")
local reactorMainframeID = ids.reactorMainframeID
local allowedSenderIDs = ids.allowedSenderIDs

-- Debug: Print allowed sender IDs
print("Allowed Sender IDs:")
for _, id in ipairs(allowedSenderIDs) do
    print(id, type(id))
end

-- Variables for monitor and button handling
local monitor = peripheral.wrap(monitorSide)
monitor.setTextScale(0.5)  -- Set the text scale to a smaller size

-- Set custom background color
local bgColor = colors.brown  -- Using 'colors.brown' as the slot for custom color
monitor.setPaletteColor(bgColor, 18 / 255, 53 / 255, 36 / 255)  -- RGB values for #123524

-- Clear the monitor fully on startup
monitor.setBackgroundColor(bgColor)
monitor.clear()

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
local lastEUStored = nil
local averageEUT = 0

-- Variables to store panel data
local panelDataList = {}  -- Stores panel data, indexed by senderID

-- Additional variables for timing
local lastUpdateTime = os.clock()

-- Variable to store reactor status
local reactorsStatus = "off" -- Default status; will be updated based on received messages
local reactorsAreOn = false  -- Track if reactors are on

-- Variables to track reactor output and time to full charge
local totalEUOutput = 0   -- Total EU/t output from reactors
local timeToFullCharge = 0   -- Time in seconds until full charge

-- Variable to track refresh countdown
local refreshCountdown = refreshInterval

-- Function to format EU values
local function formatEU(value)
    if value >= 1e12 then
        return string.format("%.2f T EU", value / 1e12)
    elseif value >= 1e9 then
        return string.format("%.2f Bil", value / 1e9)  -- Changed from G EU to Bil
    elseif value >= 1e6 then
        return string.format("%.2f M EU", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.2f k EU", value / 1e3)
    else
        return string.format("%.0f EU", value)
    end
end

-- Function to format EU/t values
local function formatEUt(value)
    if value >= 1e12 then
        return string.format("%.2f T EU/t", value / 1e12)
    elseif value >= 1e9 then
        return string.format("%.2f Bil/t", value / 1e9)  -- Changed from G EU/t to Bil/t
    elseif value >= 1e6 then
        return string.format("%.2f M EU/t", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.2f k EU/t", value / 1e3)
    else
        return string.format("%.0f EU/t", value)
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
            if x >= button.x and x < button.x + button.width and y >= button.y and y < button.y + button.height then
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
        timeToFullCharge = 0
    else
        local euNeeded = totalCapacity - totalStored
        timeToFullCharge = euNeeded / netInput
    end
end

-- Function to process PESU data from sender computers
local function processPESUData()
    totalStored = 0
    totalCapacity = 0
    pesuList = {}
    local currentTime = os.time()

    for senderID, data in pairs(pesuDataFromSenders) do
        print("Processing PESU data from sender ID:", senderID)
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
function displayPESUPage(pesuData)
    clearMonitorExceptButtons()

    -- Adjusted positions
    local titleY = 1
    local dataStartY = 3  -- Start data display from line 3

    -- Centered Title
    monitor.setTextColor(colors.green)
    centerText("NuclearCity Power Facility", titleY)
    monitor.setTextColor(colors.white)

    -- Display PESUs
    if #pesuData == 0 then
        monitor.setCursorPos(1, dataStartY)
        monitor.write("No PESU data available.")
        return
    end

    local columnWidth = math.floor(w / columnsPerPage)
    local xOffsets = {}
    for i = 1, columnsPerPage do
        xOffsets[i] = (i - 1) * columnWidth + 1
    end

    for idx, data in ipairs(pesuData) do
        local globalIdx = (currentPesuPage - 1) * pesusPerColumn * columnsPerPage + idx
        local column = math.ceil(idx / pesusPerColumn)
        if column > columnsPerPage then column = columnsPerPage end  -- Prevent overflow
        local x = xOffsets[column]
        local y = dataStartY + ((idx - 1) % pesusPerColumn) + 2  -- Adjusted Y position
        local fillPercentage = (data.stored / data.capacity) * 100
        setColorBasedOnPercentage(fillPercentage)

        -- Format PESU number and percentage
        local pesuNumberStr = string.format("PESU %d:", globalIdx)
        local percentageStr = string.format("%.2f%%", fillPercentage)

        -- Calculate positions to align text neatly
        local totalText = pesuNumberStr .. " " .. percentageStr
        local textX = x + math.floor((columnWidth - #totalText) / 2)

        monitor.setCursorPos(textX, y)
        monitor.write(pesuNumberStr .. " " .. percentageStr)
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
    local leftTitle = "Most Drained"
    local leftTitleX = leftColumnX + math.floor((leftColumnWidth - #leftTitle) / 2)
    monitor.setCursorPos(leftTitleX, leftColumnStartY)
    monitor.write(leftTitle)

    if #pesuList == 0 then
        local msg = "No PESU data available."
        local msgX = leftColumnX + math.floor((leftColumnWidth - #msg) / 2)
        monitor.setCursorPos(msgX, leftColumnStartY + 2)
        monitor.write(msg)
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

            -- Calculate positions to align text neatly
            local totalText = pesuNumberStr .. " " .. percentageStr
            local textX = leftColumnX + math.floor((leftColumnWidth - #totalText) / 2)

            monitor.setCursorPos(textX, leftColumnStartY + i)
            monitor.write(pesuNumberStr .. " " .. percentageStr)
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
        local msg = "Getting Power Service Stats"
        local msgX = rightColumnX + math.floor((rightColumnWidth - #msg) / 2)
        monitor.setCursorPos(msgX, panelY)
        monitor.write(msg)
    else
        for senderID, panelData in pairs(panelDataList) do
            monitor.setTextColor(colors.white)
            monitor.setCursorPos(rightColumnX + math.floor((rightColumnWidth - #panelData.title) / 2), panelY)
            monitor.write(panelData.title)
            panelY = panelY + 1

            local usageText = string.format("Power Usage: %.2f EU/T", panelData.energyUsage)
            monitor.setCursorPos(rightColumnX + math.floor((rightColumnWidth - #usageText) / 2), panelY)
            monitor.write(usageText)
            panelY = panelY + 1

            local fillText = "Filled: " .. string.format("%.2f%%", panelData.fillPercentage)
            setColorBasedOnPercentage(panelData.fillPercentage)
            monitor.setCursorPos(rightColumnX + math.floor((rightColumnWidth - #fillText) / 2), panelY)
            monitor.write(fillText)
            panelY = panelY + 2  -- Add extra space between panels
        end
        monitor.setTextColor(colors.white)
    end

    -- Display reactor status above progress bar
    local reactorStatusY = h - 12
    if reactorsAreOn then
        monitor.setTextColor(colors.green)
        centerText("Reactors are ON", reactorStatusY)
    else
        monitor.setTextColor(colors.red)
        centerText("Reactors are OFF", reactorStatusY)
    end
    monitor.setTextColor(colors.white)

    -- Display time to full charge if reactors are on and timeToFullCharge > 0
    local timeToFullChargeText = ""
    if reactorsAreOn and timeToFullCharge > 0 then
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
    monitor.setCursorPos(3, reactorStatusY + 1)
    monitor.write(timeToFullChargeText)

    -- Display total power capacity
    local capacityY = reactorStatusY + 2
    monitor.setTextColor(colors.white)
    local capacityText = string.format("Total Power Capacity: %s / %s", formatEU(totalStored), formatEU(totalCapacity))
    monitor.setCursorPos(3, capacityY)
    monitor.write(capacityText)

    -- Remove UK Time display

    -- Display "Refresh in: X" at the top right corner
    monitor.setCursorPos(w - 15, 1)
    monitor.write("Refresh in: " .. tostring(refreshCountdown))

    -- Display total fill percentage as a progress bar, centered above buttons
    local totalFillPercentage = 0
    if totalCapacity > 0 then
        totalFillPercentage = (totalStored / totalCapacity) * 100
    end
    local progressBarWidth = w - 4  -- Leave some padding on sides
    local filledBars = math.floor((totalFillPercentage / 100) * (progressBarWidth - 2))  -- Adjust for border
    local emptyBars = (progressBarWidth - 2) - filledBars

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
    print("Sent command to reactor mainframe:", command)
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
        elseif allPESUAtFull and lastSentState ~= "turn_off_reactors" then
            sendCommand("turn_off_reactors")
            lastSentState = "turn_off_reactors"
        end

        sleep(5)  -- Adjust sleep time as needed
    end
end

-- Function to handle incoming data
local function handleIncomingData()
    while true do
        local event, senderID, message, protocol = os.pullEvent("rednet_message")
        if type(message) == "table" and message.command then
            -- Debug: Print sender ID and type
            print("Received message from sender ID:", senderID, "Type:", type(senderID))
            if table.contains(allowedSenderIDs, senderID) or senderID == reactorMainframeID then
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
                elseif message.command == "reactor_status" then
                    reactorsStatus = message.status  -- "on" or "off"
                    reactorsAreOn = (message.status == "on")
                    calculateTimeToFullCharge()
                    displayNeedsRefresh = true
                    print("Updated reactor status to:", reactorsStatus)
                elseif message.command == "total_eu_output" and message.totalEUOutput then
                    totalEUOutput = message.totalEUOutput
                    print("Received total EU/t output from reactor mainframe:", totalEUOutput)
                    calculateTimeToFullCharge()
                    displayNeedsRefresh = true
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

-- Function to periodically update time to full charge and refresh display
local function periodicUpdater()
    while true do
        -- Reset refresh countdown
        refreshCountdown = refreshInterval

        -- Update display immediately
        displayNeedsRefresh = true

        -- Countdown loop
        for i = refreshInterval, 1, -1 do
            refreshCountdown = i
            displayNeedsRefresh = true
            sleep(1)
        end
    end
end

-- Function to handle button presses
local function handleButtonPresses()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        local action = detectClick(event, side, x, y)
        if action then
            action()  -- Switch pages based on button click
            displayNeedsRefresh = true  -- Indicate that display needs to be refreshed
        end
        sleep(0.05)  -- Allow for faster reaction to button presses
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
                    centerButtons()  -- Update buttons based on current page
                    if page == "home" then
                        displayHomePage()  -- Refresh homepage with live data
                    elseif page == "pesu" then
                        displayPESUPage(pagesData[currentPesuPage] or {})  -- Refresh PESU list page
                    end
                    displayNeedsRefresh = false
                end
                sleep(0.05)  -- Short sleep for smoother interaction
            end
        end,
        handleButtonPresses,
        handleIncomingData,
        monitorPESU,  -- Add monitorPESU function to parallel execution
        periodicUpdater  -- Add periodicUpdater function
    )
end

-- Start main function
main()
