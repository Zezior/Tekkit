-- power_mainframe.lua

-- Configuration
local monitorSide = "right"     -- Adjust based on your setup
local modemSide = "top"         -- Adjust based on your setup

-- Open Rednet
if not peripheral.isPresent(modemSide) then
    print("Error: No modem found on side '" .. modemSide .. "'. Please attach a modem.")
    return
end
rednet.open(modemSide)

-- Wrap Monitor
if not peripheral.isPresent(monitorSide) then
    print("Error: No monitor found on side '" .. monitorSide .. "'. Please attach a monitor.")
    return
end
local monitor = peripheral.wrap(monitorSide)
monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.clear()

-- Data Storage
local panelDataList = {}

-- UI State
local currentPage = "home"

-- Function to format large numbers with units
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
    if percentage >= 90 then
        monitor.setTextColor(colors.green)
    elseif percentage >= 50 then
        monitor.setTextColor(colors.yellow)
    else
        monitor.setTextColor(colors.red)
    end
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

-- Function to display Home Page
local function displayHomePage()
    clearMonitor()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.write("Power Service Home")

    -- Calculate total energy
    local totalEnergy = 0
    for _, panel in pairs(panelDataList) do
        if panel.energy then
            totalEnergy = totalEnergy + panel.energy
        end
    end

    -- Display statistics
    monitor.setCursorPos(1, 3)
    monitor.write("Total Energy: " .. formatNumber(totalEnergy) .. " EU")

    -- Calculate and display active usage
    local totalActiveUsage = 0
    local count = 0
    for _, panel in pairs(panelDataList) do
        if panel.activeUsage then
            totalActiveUsage = totalActiveUsage + panel.activeUsage
            count = count + 1
        end
    end
    if count > 0 then
        local averageActiveUsage = totalActiveUsage / count
        monitor.setCursorPos(1, 4)
        monitor.write(string.format("Active Usage: %.2f EU/t", averageActiveUsage))
    else
        monitor.setCursorPos(1, 4)
        monitor.write("Active Usage: Calculating...")
    end

    -- Draw Navigation Buttons
    drawButton(1, 6, 10, 3, "Home")
    drawButton(12, 6, 10, 3, "PESU List")
    drawButton(23, 6, 15, 3, "Panel Data")
    drawButton(39, 6, 20, 3, "Messaging Reactor")
end

-- Function to display PESU List Page
local function displayPESUListPage()
    clearMonitor()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.write("PESU List")

    local y = 3  -- Starting row

    for _, panel in pairs(panelDataList) do
        if y > 16 then break end  -- Prevent writing beyond the monitor
        if panel.title and panel.energy then
            -- Set color based on energy level (example logic)
            setColorBasedOnPercentage(panel.energy / 1e6 * 100)  -- Adjust as needed

            -- Write PESU info
            monitor.setCursorPos(1, y)
            monitor.write(string.format("PESU: %s", panel.title))
            monitor.setCursorPos(1, y + 1)
            monitor.write(string.format("Energy: %s EU", formatNumber(panel.energy)))
            y = y + 3
        else
            print("Warning: Incomplete data for a PESU. Skipping display.")
        end
    end

    -- If no PESUs, display message
    if next(panelDataList) == nil then
        monitor.setCursorPos(1, 3)
        monitor.write("No PESU data received yet.")
    end

    -- Draw Navigation Buttons
    drawButton(1, 6, 10, 3, "Home")
    drawButton(12, 6, 10, 3, "PESU List")
    drawButton(23, 6, 15, 3, "Panel Data")
    drawButton(39, 6, 20, 3, "Messaging Reactor")
end

-- Function to display Panel Data Page
local function displayPanelDataPage()
    clearMonitor()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.write("Panel Data")

    local y = 3  -- Starting row

    for _, panel in pairs(panelDataList) do
        if y > 16 then break end  -- Prevent writing beyond the monitor
        if panel.title and panel.energy and panel.activeUsage then
            -- Set color based on active usage (example logic)
            setColorBasedOnPercentage(panel.activeUsage / 100 * 100)  -- Adjust as needed

            -- Write Panel info
            monitor.setCursorPos(1, y)
            monitor.write(string.format("Panel: %s", panel.title))
            monitor.setCursorPos(1, y + 1)
            monitor.write(string.format("Energy: %s EU", formatNumber(panel.energy)))
            monitor.setCursorPos(1, y + 2)
            monitor.write(string.format("Active Usage: %.2f EU/t", panel.activeUsage))
            y = y + 4
        else
            print("Warning: Incomplete data for a Panel. Skipping display.")
        end
    end

    -- If no panel data, display message
    if next(panelDataList) == nil then
        monitor.setCursorPos(1, 3)
        monitor.write("No panel data received yet.")
    end

    -- Draw Navigation Buttons
    drawButton(1, 6, 10, 3, "Home")
    drawButton(12, 6, 10, 3, "PESU List")
    drawButton(23, 6, 15, 3, "Panel Data")
    drawButton(39, 6, 20, 3, "Messaging Reactor")
end

-- Function to display Messaging Reactor Mainframe Page
local function displayMessagingReactorPage()
    clearMonitor()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.write("Messaging Reactor")

    local y = 3  -- Starting row

    -- Placeholder for Messaging Reactor data
    -- Customize this based on your reactor's setup
    monitor.setCursorPos(1, y)
    monitor.write("Reactor Status: Active")
    y = y + 1

    monitor.setCursorPos(1, y)
    monitor.write("Messages:")
    y = y + 1

    monitor.setCursorPos(1, y)
    monitor.write("- Reactor connected.")
    y = y + 1

    monitor.setCursorPos(1, y)
    monitor.write("- Player activity: Idle")
    y = y + 1

    -- Draw Navigation Buttons
    drawButton(1, 6, 10, 3, "Home")
    drawButton(12, 6, 10, 3, "PESU List")
    drawButton(23, 6, 15, 3, "Panel Data")
    drawButton(39, 6, 20, 3, "Messaging Reactor")
end

-- Function to display the current page
local function displayCurrentPage()
    if currentPage == "home" then
        displayHomePage()
    elseif currentPage == "pesu" then
        displayPESUListPage()
    elseif currentPage == "panel" then
        displayPanelDataPage()
    elseif currentPage == "messaging" then
        displayMessagingReactorPage()
    else
        displayHomePage()
    end
end

-- Function to handle monitor touch events for buttons
local function handleTouch(x, y)
    -- Define button regions based on drawButton positions
    if y >= 6 and y <= 8 then
        if x >= 1 and x <= 10 then
            currentPage = "home"
            displayCurrentPage()
        elseif x >= 12 and x <= 21 then
            currentPage = "pesu"
            displayPESUListPage()
        elseif x >= 23 and x <= 37 then
            currentPage = "panel"
            displayPanelDataPage()
        elseif x >= 39 and x <= 58 then
            currentPage = "messaging"
            displayMessagingReactorPage()
        end
    end
end

-- Function to process incoming data
local function processData()
    while true do
        local event, senderID, message, protocol = os.pullEvent("rednet_message")
        if protocol == "pesu_data" then
            if type(message) == "table" and message.command == "panel_data" then
                -- Update panel data
                for _, panel in ipairs(message.panels) do
                    panelDataList[panel.title] = panel
                end
                print("Received data from Sender ID: " .. senderID)
                displayCurrentPage()
            else
                print("Warning: Received malformed data from Sender ID: " .. senderID)
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

-- Main Execution
print("Power Mainframe is running and waiting for data...")
displayCurrentPage()  -- Display initial Home Page
parallel.waitForAny(processData, monitorHandler)
