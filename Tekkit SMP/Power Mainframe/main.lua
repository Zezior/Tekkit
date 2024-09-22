-- power_mainframe.lua

-- Open the modem on the appropriate side
local modemSide = "top"  -- Change if your modem is on a different side
if not peripheral.isPresent(modemSide) then
    print("Error: No modem found on side '" .. modemSide .. "'. Please attach a modem.")
    return
end
rednet.open(modemSide)

-- Monitor setup
local monitorSide = "right"  -- Change if your monitor is on a different side
if not peripheral.isPresent(monitorSide) then
    print("Error: No monitor found on side '" .. monitorSide .. "'. Please attach a monitor.")
    return
end
local monitor = peripheral.wrap(monitorSide)
monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.clear()

-- Data storage
local pesuDataFromSenders = {}
local panelDataList = {}

-- Variables for monitor dimensions
local w, h = monitor.getSize()

-- Current page
local currentPage = "home"

-- Function to format numbers with units (e.g., k, mil, bil)
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

-- Function to set color based on percentage
local function setColorBasedOnPercentage(percentage)
    if percentage >= 0.90 then
        monitor.setTextColor(colors.green)
    elseif percentage >= 0.50 then
        monitor.setTextColor(colors.yellow)
    else
        monitor.setTextColor(colors.red)
    end
end

-- Function to detect if a click is within a button
local function isWithin(x, y, btnX, btnY, btnW, btnH)
    return x >= btnX and x < (btnX + btnW) and y >= btnY and y < (btnY + btnH)
end

-- Function to draw a button
local function drawButton(x, y, width, height, label)
    monitor.setCursorPos(x, y)
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.gray)
    for i = 0, height - 1 do
        for j = 0, width - 1 do
            monitor.setCursorPos(x + j, y + i)
            monitor.write(" ")
        end
    end
    -- Center the label
    local labelX = x + math.floor((width - #label)/2)
    local labelY = y + math.floor(height / 2)
    monitor.setCursorPos(labelX, labelY)
    monitor.write(label)
end

-- Function to clear the monitor
local function clearMonitor()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
end

-- Function to display home page
local function displayHomePage()
    clearMonitor()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.write("Power Service Home")

    -- Display Total Stored and Total Capacity
    local totalStored = 0
    local totalCapacity = 0
    for _, data in pairs(pesuDataFromSenders) do
        for _, pesu in ipairs(data.pesuDataList) do
            totalStored = totalStored + pesu.stored
            totalCapacity = totalCapacity + pesu.capacity
        end
    end

    monitor.setCursorPos(1, 3)
    monitor.write("Total Stored: " .. formatNumber(totalStored))
    monitor.setCursorPos(1, 4)
    monitor.write("Total Capacity: " .. formatNumber(totalCapacity))

    -- Calculate and display overall average EU/t
    local totalAverageEUT = 0
    local count = 0
    for _, data in pairs(pesuDataFromSenders) do
        for _, panel in ipairs(data.panelDataList) do
            if panel.averageEUT then
                totalAverageEUT = totalAverageEUT + panel.averageEUT
                count = count + 1
            end
        end
    end
    if count > 0 then
        local overallAverageEUT = totalAverageEUT / count
        monitor.setCursorPos(1, 5)
        monitor.write("Overall Usage: " .. string.format("%.2f EU/t", overallAverageEUT))
    else
        monitor.setCursorPos(1, 5)
        monitor.write("Overall Usage: Calculating...")
    end

    -- Draw navigation buttons
    drawButton(1, h - 2, 10, 3, "Home")
    drawButton(12, h - 2, 10, 3, "PESU List")
    drawButton(23, h - 2, 15, 3, "Panel Data")
end

-- Function to display PESU list page
local function displayPESUPage()
    clearMonitor()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.write("PESU List")

    local y = 3  -- Starting row

    for senderID, data in pairs(pesuDataFromSenders) do
        for _, pesu in ipairs(data.pesuDataList) do
            if y > h - 4 then break end  -- Prevent writing beyond the monitor
            -- Calculate percentage
            local percentage = 0
            if pesu.capacity > 0 then
                percentage = pesu.stored / pesu.capacity
            end

            -- Set color based on percentage
            setColorBasedOnPercentage(percentage)

            -- Write PESU info
            monitor.setCursorPos(1, y)
            monitor.write(string.format("PESU: %s | %s / %s", pesu.name, formatNumber(pesu.stored), formatNumber(pesu.capacity)))
            y = y + 1
        end
    end

    -- If no PESUs, display message
    if #pesuDataFromSenders == 0 then
        monitor.setCursorPos(1, 3)
        monitor.write("No PESU data received yet.")
    end

    -- Draw navigation buttons
    drawButton(1, h - 2, 10, 3, "Home")
    drawButton(12, h - 2, 10, 3, "PESU List")
    drawButton(23, h - 2, 15, 3, "Panel Data")
end

-- Function to display panel data page
local function displayPanelDataPage()
    clearMonitor()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.write("Panel Data")

    local y = 3  -- Starting row

    for senderID, data in pairs(pesuDataFromSenders) do
        for _, panel in ipairs(data.panelDataList) do
            if y > h - 4 then break end  -- Prevent writing beyond the monitor
            -- Calculate percentage
            local percentage = 0
            if panel.capacity > 0 then
                percentage = panel.energy / panel.capacity
            end

            -- Set color based on percentage
            setColorBasedOnPercentage(percentage)

            -- Write panel info
            monitor.setCursorPos(1, y)
            local usageStr = panel.averageEUT and string.format("%.2f EU/t", panel.averageEUT) or "Calculating..."
            monitor.write(string.format("Panel: %s | %s / %s | Usage: %s", panel.title, formatNumber(panel.energy), formatNumber(panel.capacity), usageStr))
            y = y + 1
        end
    end

    -- If no panel data, display message
    if next(panelDataList) == nil then
        monitor.setCursorPos(1, 3)
        monitor.write("No panel data received yet.")
    end

    -- Draw navigation buttons
    drawButton(1, h - 2, 10, 3, "Home")
    drawButton(12, h - 2, 10, 3, "PESU List")
    drawButton(23, h - 2, 15, 3, "Panel Data")
end

-- Function to display the current page
local function displayCurrentPage()
    if currentPage == "home" then
        displayHomePage()
    elseif currentPage == "pesu" then
        displayPESUPage()
    elseif currentPage == "panel" then
        displayPanelDataPage()
    else
        displayHomePage()
    end
end

-- Function to handle monitor touch events for buttons
local function handleTouch(x, y)
    -- Check which button was pressed
    -- Assuming buttons are:
    -- Home: x=1, y=h-2 to x=10, y=h
    -- PESU List: x=12, y=h-2 to x=21, y=h
    -- Panel Data: x=23, y=h-2 to x=37, y=h
    if isWithin(x, y, 1, h - 2, 10, 3) then
        currentPage = "home"
        displayCurrentPage()
    elseif isWithin(x, y, 12, h - 2, 10, 3) then
        currentPage = "pesu"
        displayCurrentPage()
    elseif isWithin(x, y, 23, h - 2, 15, 3) then
        currentPage = "panel"
        displayCurrentPage()
    end
end

-- Function to display data
local function displayData()
    displayCurrentPage()
end

-- Function to process incoming data
local function processData()
    while true do
        local event, senderID, message, protocol = os.pullEvent("rednet_message")
        if protocol == "pesu_data" then
            if type(message) == "table" and message.command == "pesu_data" then
                -- Store the data
                pesuDataFromSenders[senderID] = message

                -- Process panel data
                for _, panelData in ipairs(message.panelDataList) do
                    local panelID = senderID .. "_" .. panelData.name
                    panelDataList[panelID] = panelData
                end

                -- Update display
                displayData()
            end
        end
    end
end

-- Function to handle monitor touch events
local function monitorHandler()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if side == monitorSide then
            handleTouch(x, y)
        end
    end
end

-- Start processing data and handling UI
print("Power Mainframe is running and waiting for data...")
displayCurrentPage()  -- Display initial page
parallel.waitForAny(processData, monitorHandler)
