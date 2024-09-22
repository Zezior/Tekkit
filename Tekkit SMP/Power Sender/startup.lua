-- pesu_sender.lua

-- Replace with the ID of the power mainframe computer
local powerMainframeID = 4644  -- Set this to the correct ID

-- Open the modem for Rednet communication
rednet.open("top")  -- Adjust this if your modem is on a different side

-- List of connected PESUs
local pesuPeripherals = {}

-- List of connected Advanced Information Panels
local panelPeripherals = {}

-- Function to scan for connected peripherals
local function scanPeripherals()
    local peripherals = peripheral.getNames()
    for _, name in ipairs(peripherals) do
        local type = peripheral.getType(name)
        if type == "ic2:pesu" then
            table.insert(pesuPeripherals, name)
        elseif type == "info_panel_advanced" then  -- Advanced Information Panel
            table.insert(panelPeripherals, name)
        end
    end
end

-- Function to format large numbers with units (e.g., k, mil, bil)
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

-- Table to store previous energy values and last update times for panels
local panelDataHistory = {}  -- Indexed by panelName

-- Function to send data to the power mainframe
local function sendData()
    -- Process PESU data
    local pesuDataList = {}
    for _, pesuName in ipairs(pesuPeripherals) do
        local pesu = peripheral.wrap(pesuName)
        if pesu then
            local stored = pesu.getEUStored()
            local capacity = pesu.getEUCapacity()
            table.insert(pesuDataList, {
                name = pesuName,
                stored = stored,
                capacity = capacity
            })
        end
    end

    -- Process Panel data
    local panelDataList = {}
    local currentTime = os.time()
    for _, panelName in ipairs(panelPeripherals) do
        local panel = peripheral.wrap(panelName)
        if panel then
            -- Use getCardDataRaw to get panel data
            local cardData = panel.getCardDataRaw()

            -- Debug: Print the raw card data
            -- Uncomment the following lines if you want to see the raw data
            -- print("Raw Card Data for panel:", panelName)
            -- for key, value in pairs(cardData) do
            --     print(key .. ": " .. tostring(value))
            -- end

            -- Extract required data
            local title = cardData.title or "Unknown"
            local energyStr = cardData.energy or "0"
            local capacityStr = cardData.capacity or "0"

            -- Remove spaces from energy and capacity strings
            local energy = tonumber(energyStr:gsub("%s", "")) or 0
            local capacity = tonumber(capacityStr:gsub("%s", "")) or 0

            -- Calculate average EU/t over 20 seconds
            local history = panelDataHistory[panelName]
            local averageEUT = nil

            if history then
                local deltaTime = currentTime - history.lastUpdateTime
                if deltaTime >= 20 then
                    local deltaEnergy = history.lastEnergy - energy
                    averageEUT = deltaEnergy / deltaTime / 20  -- EU/t (20 ticks per second)
                    -- Update history
                    history.lastUpdateTime = currentTime
                    history.lastEnergy = energy
                end
            else
                -- Initialize history
                panelDataHistory[panelName] = {
                    lastUpdateTime = currentTime,
                    lastEnergy = energy
                }
            end

            -- Format energy and capacity with units
            local formattedEnergy = formatNumber(energy)
            local formattedCapacity = formatNumber(capacity)

            -- Prepare data to send
            table.insert(panelDataList, {
                name = panelName,
                title = title,
                energy = energy,
                capacity = capacity,
                averageEUT = averageEUT,
                formattedEnergy = formattedEnergy,
                formattedCapacity = formattedCapacity
            })
        end
    end

    -- Prepare the data to send
    local data = {
        command = "pesu_data",
        senderID = os.getComputerID(),
        pesuDataList = pesuDataList,
        panelDataList = panelDataList,
        timestamp = currentTime
    }

    -- Send data to the power mainframe
    rednet.send(powerMainframeID, data, "pesu_data")
end

-- Main function
local function main()
    scanPeripherals()

    if #pesuPeripherals == 0 and #panelPeripherals == 0 then
        print("No PESUs or Panels found. Ensure they are connected via wired modems.")
        return
    end

    print("Found PESUs:")
    for _, pesuName in ipairs(pesuPeripherals) do
        print("- " .. pesuName)
    end

    print("Found Panels:")
    for _, panelName in ipairs(panelPeripherals) do
        print("- " .. panelName)
    end

    -- Send data periodically
    while true do
        sendData()
        sleep(1)  -- Send data every second
    end
end

main()
