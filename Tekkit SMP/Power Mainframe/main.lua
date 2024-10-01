-- Power mainframe main.lua

-- Configuration
local monitorSide = "right"     -- Adjust based on your setup
local modemSide = "top"         -- Adjust based on your setup

-- Open the modem on the specified side with error handling
if peripheral.isPresent(modemSide) then
    rednet.open(modemSide)
    print("Rednet modem opened on side:", modemSide)
else
    print("Error: No modem found on side:", modemSide)
    return
end

-- Output the computer ID
print("Mainframe Computer ID:", os.getComputerID())

-- Load allowed sender IDs from ids.lua with error handling
local status, ids = pcall(require, "ids")
if not status then
    print("Error loading ids.lua:", ids)
    return
end

local reactorMainframeID = ids.reactorMainframeID
local allowedSenderIDs = ids.allowedSenderIDs

-- Variables for monitor and button handling
local monitor = peripheral.wrap(monitorSide)
if not monitor then
    print("Error: No monitor found on side:", monitorSide)
    return
end

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

-- Variable to store total power used
local totalPowerUsed = 0

-- Function to format EU values (for display purposes other than Power Usage)
local function formatEU(value)
    if value >= 1e12 then
        return string.format("%.2fT EU", value / 1e12)
    elseif value >= 1e9 then
        return string.format("%.2fBil EU", value / 1e9)  -- Bil for billion
    elseif value >= 1e6 then
        return string.format("%.2fM EU", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.2fk EU", value / 1e3)
    else
        return string.format("%.0f EU", value)
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
                totalStored = totalStored + pesuData.stored  -- Stored EU
                totalCapacity = totalCapacity + pesuData.capacity  -- Assuming capacity is sent correctly
                table.insert(pesuList, {
                    stored = pesuData.stored,
                    capacity = pesuData.capacity  -- Fixed or variable capacity
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
        local globalIdx = (currentPesuPage - 1) * pesusPerPage + idx
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

            if chunkUnloaded then
                -- Display "Chunk Unloaded" instead of Power Usage
                local unloadedText = "Chunk Unloaded"
                monitor.setCursorPos(rightColumnX + math.floor((rightColumnWidth - #unloadedText) / 2), panelY)
                monitor.write(unloadedText)
                panelY = panelY + 1
            else
                -- Display Power Usage using deltaEnergy
                local usageText = string.format("Power Usage: %.2f EU/t", panelData.deltaEnergy)
                monitor.setCursorPos(rightColumnX + math.floor((rightColumnWidth - #usageText) / 2), panelY)
                monitor.write(usageText)
                panelY = panelY + 1
            end

            -- Display Power Used
            local powerUsedText = string.format("Power Used: %s", formatEU(totalPowerUsed))
            monitor.setCursorPos(rightColumnX + math.floor((rightColumnWidth - #powerUsedText) / 2), panelY)
            monitor.write(powerUsedText)
            panelY = panelY + 1

            -- Display Fill Percentage with color coding
            local fillText = "Filled: " .. string.format("%.2f%%", panelData.fillPercentage)
            setColorBasedOnPercentage(panelData.fillPercentage)
            monitor.setCursorPos(rightColumnX + math.floor((rightColumnWidth - #fillText) / 2), panelY)
            monitor.write(fillText)
            panelY = panelY + 2  -- Add extra space between panels
        end
        monitor.setTextColor(colors.white)
    end

    -- Display reactor status above progress bar
    local function displayReactorStatus()
        local reactorStatusY = h - 12
        if reactorsAreOn then
            monitor.setTextColor(colors.green)
            centerText("Reactors are ON", reactorStatusY)
        else
            monitor.setTextColor(colors.red)
            centerText("Reactors are OFF", reactorStatusY)
        end
        monitor.setTextColor(colors.white)
    end

    -- Display time to full charge
    local function displayTimeToFullCharge()
        local reactorStatusY = h - 12
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
        centerText(timeToFullChargeText, reactorStatusY + 1)
    end

    -- Display total power capacity
    local function displayTotalPowerCapacity()
        local reactorStatusY = h - 12
        local capacityY = reactorStatusY + 2
        monitor.setTextColor(colors.white)
        local capacityText = string.format("Total Power Capacity: %s / %s", formatEU(totalStored), formatEU(totalCapacity))
        -- Center the capacityText
        centerText(capacityText, capacityY)
    end

    -- Display total fill percentage as a progress bar, centered above buttons
    local function displayProgressBar()
        local reactorStatusY = h - 12
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

    -- Function to display all dynamic elements on the Home Page
    local function displayHomePageElements()
        displayReactorStatus()
        displayTimeToFullCharge()
        displayTotalPowerCapacity()
        displayProgressBar()
    end

    -- Function to display the Home Page
    local function displayHomePageFull()
        displayHomePage()
        displayHomePageElements()
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
                if table.contains(allowedSenderIDs, senderID) or senderID == reactorMainframeID then
                    if message.command == "pesu_data" then
                        pesuDataFromSenders[senderID] = message
                        processPESUData()
                    elseif message.command == "panel_data" then
                        panelDataList[senderID] = message.panelDataList[1]
                        if message.panelDataList[1].deltaEnergy > 0 then
                            lastNonZeroDeltaTime = os.time()
                            chunkUnloaded = false
                        end
                        if message.panelDataList[1].totalPowerUsed then
                            totalPowerUsed = message.panelDataList[1].totalPowerUsed
                        end
                    elseif message.command == "reactor_status" then
                        reactorsStatus = message.status  -- "on" or "off"
                        reactorsAreOn = (message.status == "on")
                        calculateTimeToFullCharge()
                    elseif message.command == "total_eu_output" and message.totalEUOutput then
                        totalEUOutput = message.totalEUOutput
                        calculateTimeToFullCharge()
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
                displayHomePageFull()
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
    ```

```lua
-- aip_script.lua

-- Configuration
local panelSide = "bottom"         -- Side where the advanced information panel is connected
print("Panel Side:", panelSide)    -- Debugging line
local mainframeID = 4644           -- Mainframe's Rednet ID (Replace with your actual mainframe ID)
local modemSide = "left"           -- Side where the modem is connected
local updateInterval = 1           -- Time in seconds between sending updates
local logFile = "power_used.txt"   -- File to store total power used

-- Open the wireless modem for rednet communication
if modemSide then
    print("Opening modem on side:", modemSide)
    rednet.open(modemSide)  -- Adjust the side where your modem is connected
else
    print("Error: modemSide is nil!")
    return
end

-- Variable to store the last energy reading
local lastEnergy = nil

-- Variable to store total power used
local totalPowerUsed = 0

-- Function to format EU values
local function formatEU(value)
    if value >= 1e12 then
        return string.format("%.2fT EU", value / 1e12)
    elseif value >= 1e9 then
        return string.format("%.2fBil EU", value / 1e9)  -- Bil for billion
    elseif value >= 1e6 then
        return string.format("%.2fM EU", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.2fk EU", value / 1e3)
    else
        return string.format("%.0f EU", value)
    end
end

-- Function to load total power used from file
local function loadTotalPowerUsed()
    if fs.exists(logFile) then
        local file = fs.open(logFile, "r")
        local content = file.readAll()
        file.close()
        local value = tonumber(content)
        if value then
            totalPowerUsed = value
            print(string.format("Loaded total power used: %s", formatEU(totalPowerUsed)))
        else
            print("Error: Invalid data in power_used.txt. Starting from 0.")
            totalPowerUsed = 0
        end
    else
        totalPowerUsed = 0
        print("No existing power_used.txt found. Starting from 0.")
    end
end

-- Function to save total power used to file
local function saveTotalPowerUsed()
    local file = fs.open(logFile, "w")
    file.write(tostring(totalPowerUsed))
    file.close()
end

-- Function to extract energy data from getCardData
local function extractEnergy(dataLine)
    print("Parsing Energy Line:", dataLine)
    -- Extract the numeric part before 'EU', remove spaces and commas
    local energyStr = dataLine:match("([%d%s,]+)%s*EU")
    if energyStr then
        energyStr = energyStr:gsub("[%s,]", "")  -- Remove spaces and commas
        local energyValue = tonumber(energyStr)
        if energyValue then
            print("Extracted Energy:", energyValue)
            return energyValue
        else
            print("Failed to convert energy string to number:", energyStr)
            return nil
        end
    else
        print("Failed to extract energy from line:", dataLine)
        return nil
    end
end

-- Function to extract fill percentage from getCardData
local function extractFillPercentage(dataLine)
    print("Parsing Fill Percentage Line:", dataLine)
    local percentageStr = dataLine:match("(%d+)")
    if percentageStr then
        local percentage = tonumber(percentageStr)
        print("Extracted Fill Percentage:", percentage)
        return percentage
    else
        print("Failed to extract fill percentage from line:", dataLine)
        return nil
    end
end

-- Function to send panel data
local function sendPanelData()
    -- Debug: Print panelSide before wrapping
    print("Attempting to wrap peripheral on side:", panelSide)
    
    -- Wrap the panel peripheral connected directly
    local panelPeripheral = peripheral.wrap(panelSide)

    if panelPeripheral then
        print("Peripheral successfully wrapped on side:", panelSide)
    else
        print("Error: No peripheral found on side:", panelSide)
        return
    end

    -- Get the card data from the panel
    local cardData = panelPeripheral.getCardData()

    -- Debug: Print raw card data
    if not cardData then
        print("Error: getCardData() returned nil.")
        return
    end

    print("Card Data Received:")
    for i, line in ipairs(cardData) do
        print(i .. ": " .. tostring(line))
    end

    -- Ensure cardData is valid
    if #cardData < 5 then
        print("Error: Expected at least 5 lines of card data, got " .. #cardData)
        return
    end

    -- Extract the panel name (1st line)
    local panelName = cardData[1]
    print("Panel Name:", panelName)

    -- Extract stored energy (2nd line)
    local storedEnergy = extractEnergy(cardData[2])

    -- Extract fill percentage (5th line)
    local fillPercentage = extractFillPercentage(cardData[5])

    if not panelName or not storedEnergy or not fillPercentage then
        print("Error: Could not retrieve panel data.")
        return
    end

    -- Get current time
    local currentTime = os.time()

    if lastEnergy == nil then
        -- First reading; store it and wait for the next reading
        lastEnergy = storedEnergy
        print("First energy reading stored. Awaiting next reading to calculate deltaEnergy.")
        return
    end

    -- Calculate total energy used over the last second
    local deltaEnergy_total = lastEnergy - storedEnergy  -- Total energy used over interval
    local deltaTime = currentTime - (currentTime - 1)  -- Should be 1 second

    print(string.format("Delta Energy (Total): %d EU over Delta Time: %d seconds", deltaEnergy_total, deltaTime))

    if deltaTime > 0 then
        -- Calculate energy usage per tick
        local deltaEnergy = deltaEnergy_total / 20  -- EU per tick (since 20 ticks per second)
        print(string.format("Delta Energy (EU/t): %.2f EU/t", deltaEnergy))

        -- Ensure deltaEnergy is non-negative
        if deltaEnergy < 0 then
            print("Warning: Negative delta energy detected. Setting to 0.")
            deltaEnergy = 0
        end

        -- Update total power used
        totalPowerUsed = totalPowerUsed + deltaEnergy
        print(string.format("Total Power Used: %s", formatEU(totalPowerUsed)))

        -- Save total power used to file
        saveTotalPowerUsed()

        -- Prepare the message to send
        local message = {
            command = "panel_data",
            panelDataList = {
                {
                    title = panelName,
                    fillPercentage = fillPercentage,
                    deltaEnergy = deltaEnergy,          -- EU per tick
                    totalPowerUsed = totalPowerUsed     -- Total EU used
                }
            }
        }

        -- Send the data to the mainframe
        rednet.send(mainframeID, message, "panel_data")

        -- Debug print to confirm message sent
        print(string.format("Sent panel data to mainframe: %s - Delta Energy: %.2f EU/t - Filled: %d%% - Power Used: %s", panelName, deltaEnergy, fillPercentage, formatEU(totalPowerUsed)))
    else
        print("Delta time is zero or negative. Setting delta energy to 0.")
    end

    -- Update lastEnergy for the next calculation
    lastEnergy = storedEnergy
end

-- List all connected peripherals with sides (Debugging Step)
print("Listing all connected peripherals with sides:")
local sides = {"left", "right", "top", "bottom", "front", "back", "up", "down"}

for _, side in ipairs(sides) do
    if peripheral.isPresent(side) then
        print(side .. ": " .. peripheral.getType(side))
    end
end

-- Load total power used from file
loadTotalPowerUsed()

-- Main loop to send data at intervals
while true do
    sendPanelData()
    sleep(updateInterval)  -- Wait for the next update (1 second)
end
1