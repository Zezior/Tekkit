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

-- Function to clear the monitor
local function clearMonitor()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
end

-- Function to display data
local function displayData()
    clearMonitor()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.write("Power Service Stats")

    local y = 3  -- Starting row for panel data

    for _, panelData in pairs(panelDataList) do
        -- Display Title
        monitor.setCursorPos(1, y)
        monitor.write(panelData.title or "Panel")
        y = y + 1

        -- Display Energy and Capacity
        monitor.setCursorPos(1, y)
        local energyCapacityStr = (panelData.formattedEnergy or "0") .. " / " .. (panelData.formattedCapacity or "0")
        monitor.write(energyCapacityStr)
        y = y + 1

        -- Display Usage
        monitor.setCursorPos(1, y)
        if panelData.averageEUT then
            monitor.write("Usage: " .. string.format("%.2f EU/t", panelData.averageEUT))
        else
            monitor.write("Usage: Calculating...")
        end
        y = y + 2  -- Add space between panels

        -- Ensure we don't exceed monitor height
        if y > h - 2 then
            y = 3
            monitor.setCursorPos(w / 2, 1)
            monitor.write("Additional Panels")
            y = y + 1
        end
    end

    -- If there are no panels, display a message
    if next(panelDataList) == nil then
        monitor.setCursorPos(1, y)
        monitor.write("No panel data received yet.")
    end
end

-- Start processing data
print("Power Mainframe is running and waiting for data...")
processData()
