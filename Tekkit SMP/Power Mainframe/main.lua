-- power_mainframe.lua

-- Open the modem on the appropriate side
rednet.open("top")  -- Adjust if necessary

-- Monitor setup
local monitor = peripheral.wrap("right")  -- Adjust if necessary
monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.clear()

-- Data storage
local pesuDataFromSenders = {}
local panelDataList = {}

-- Variables for monitor dimensions
local w, h = monitor.getSize()

-- Function to format numbers
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

-- Function to display data
local function displayData()
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.write("Power Service Stats")

    local y = 3  -- Starting row for panel data

    for _, panelData in pairs(panelDataList) do
        monitor.setCursorPos(1, y)
        monitor.write(panelData.title or "Panel")
        y = y + 1

        monitor.setCursorPos(1, y)
        monitor.write((panelData.formattedEnergy or "0") .. " / " .. (panelData.formattedCapacity or "0"))
        y = y + 1

        monitor.setCursorPos(1, y)
        if panelData.averageEUT then
            monitor.write("Usage: " .. string.format("%.2f EU/t", panelData.averageEUT))
        else
            monitor.write("Usage: Calculating...")
        end
        y = y + 2  -- Add space between panels
    end

    -- If there are no panels, display a message
    if y == 3 then
        monitor.setCursorPos(1, y)
        monitor.write("No panel data received yet.")
    end
end

-- Start processing data
processData()
