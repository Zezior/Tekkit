-- pesu_sender.lua

-- Replace with the ID of the power mainframe computer
local powerMainframeID = 4644  -- Update this to your actual mainframe ID

-- Open the modem for Rednet communication
local modemSide = "top"  -- Change if your modem is on a different side
if not peripheral.isPresent(modemSide) then
    print("Error: No modem found on side '" .. modemSide .. "'. Please attach a modem.")
    return
end
rednet.open(modemSide)

-- Lists of connected PESUs and Panels
local pesuPeripherals = {}
local panelPeripherals = {}

-- Function to scan for connected peripherals
local function scanPeripherals()
    local peripherals = peripheral.getNames()
    for _, name in ipairs(peripherals) do
        local type = peripheral.getType(name)
        if type == "ic2:pesu" then
            table.insert(pesuPeripherals, name)
            print("Detected PESU: " .. name)
        elseif type == "info_panel_advanced" then  -- Adjust if your panel type is different
            table.insert(panelPeripherals, name)
            print("Detected Advanced Information Panel: " .. name)
        end
    end

    if #pesuPeripherals == 0 and #panelPeripherals == 0 then
        print("No PESUs or Advanced Information Panels found. Ensure they are connected via wired modems.")
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
            local stored, capacity = 0, 1000000000  -- Default capacity if getEUCapacity() is unavailable
            if type(pesu.getEUStored) == "function" then
                stored = pesu.getEUStored()
            else
                print("Warning: 'getEUStored' function not found for PESU '" .. pesuName .. "'.")
            end
            if type(pesu.getEUCapacity) == "function" then
                capacity = pesu.getEUCapacity()
            else
                print("Warning: 'getEUCapacity' function not found for PESU '" .. pesuName .. "'. Using default capacity: " .. capacity)
            end
            table.insert(pesuDataList, {
                name = pesuName,
                stored = stored,
                capacity = capacity
            })
        else
            print("Error: Unable to wrap PESU peripheral '" .. pesuName .. "'.")
        end
    end

    -- Process Panel data
    local panelDataList = {}
    local currentTime = os.time()
    for _, panelName in ipairs(panelPeripherals) do
        local panel = peripheral.wrap(panelName)
        if panel then
            -- Use getCardDataRaw to get panel data
            if type(panel.getCardDataRaw) ~= "function" then
                print("Error: 'getCardDataRaw' function not found for Panel '" .. panelName .. "'. Skipping this panel.")
                -- Skip to next panel
            else
                local cardData = panel.getCardDataRaw()

                -- Debug: Print the raw card data
                print("Raw Card Data for panel '" .. panelName .. "':")
                for key, value in pairs(cardData) do
                    print("  " .. key .. ": " .. tostring(value))
                end

                -- Extract required data
                local title = cardData.title or "Unknown"
                local energyStr = tostring(cardData.energy)
                local capacityStr = tostring(cardData.capacity)

                -- Debug: Print energy and capacity strings
                print("Parsed Energy String: '" .. energyStr .. "'")
                print("Parsed Capacity String: '" .. capacityStr .. "'")

                -- Convert strings to numbers by removing spaces and commas
                local energyNum = tonumber(energyStr:gsub("[%s,]", "")) or 0
                local capacityNum = tonumber(capacityStr:gsub("[%s,]", "")) or 0

                -- Debug: Print numeric values
                print("Numeric Energy: " .. energyNum)
                print("Numeric Capacity: " .. capacityNum)

                -- Calculate average EU/t over 20 seconds
                local history = panelDataHistory[panelName]
                local averageEUT = nil

                if history then
                    local deltaTime = currentTime - history.lastUpdateTime
                    if deltaTime >= 20 then
                        local deltaEnergy = history.lastEnergy - energyNum
                        averageEUT = deltaEnergy / deltaTime / 20  -- EU/t (20 ticks per second)
                        -- Update history
                        panelDataHistory[panelName].lastUpdateTime = currentTime
                        panelDataHistory[panelName].lastEnergy = energyNum
                        print("Calculated average EU/t for panel '" .. panelName .. "': " .. averageEUT)
                    end
                else
                    -- Initialize history
                    panelDataHistory[panelName] = {
                        lastUpdateTime = currentTime,
                        lastEnergy = energyNum
                    }
                    print("Initialized history for panel '" .. panelName .. "'.")
                end

                -- Format energy and capacity with units
                local formattedEnergy = formatNumber(energyNum)
                local formattedCapacity = formatNumber(capacityNum)

                -- Prepare data to send
                table.insert(panelDataList, {
                    name = panelName,
                    title = title,
                    energy = energyNum,
                    capacity = capacityNum,
                    averageEUT = averageEUT,
                    formattedEnergy = formattedEnergy,
                    formattedCapacity = formattedCapacity
                })
            end
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
    if #pesuDataList > 0 or #panelDataList > 0 then
        rednet.send(powerMainframeID, data, "pesu_data")
        print("Data sent to power mainframe.")
    else
        print("No data to send.")
    end
end

-- Main function
local function main()
    scanPeripherals()

    if #pesuPeripherals == 0 and #panelPeripherals == 0 then
        print("No PESUs or Panels found. Ensure they are connected via wired modems.")
    else
        print("Starting data transmission...")
        -- Send data periodically every 1 second
        while true do
            sendData()
            sleep(1)
        end
    end
end

main()
