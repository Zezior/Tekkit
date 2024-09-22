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
        local pType = peripheral.getType(name)
        if pType == "ic2:pesu" then
            table.insert(pesuPeripherals, name)
            print("Detected PESU: " .. name)
        elseif pType == "info_panel_advanced" then  -- Adjust if your panel type is different
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
    local currentTime = os.time()

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
    for _, panelName in ipairs(panelPeripherals) do
        local panel = peripheral.wrap(panelName)
        if panel then
            -- Use getCardDataRaw to get panel data
            if type(panel.getCardDataRaw) ~= "function" then
                print("Error: 'getCardDataRaw' function not found for Panel '" .. panelName .. "'. Skipping this panel.")
            else
                local cardData = panel.getCardDataRaw()

                -- Debug: Print the raw card data
                print("Raw Card Data for panel '" .. panelName .. "':")
                for _, line in ipairs(cardData) do
                    print("  " .. line)
                end

                -- Initialize variables
                local title = "Unknown"
                local energyNum = 0
                local capacityNum = 0

                -- Extract required data by parsing lines
                for _, line in ipairs(cardData) do
                    if line:find("^Title:") then
                        title = line:match("^Title:%s*(.*)")
                    elseif line:find("^[Ee]nergy:") then
                        local energyStr = line:match("^[Ee]nergy:%s*([%d%s,]+)")
                        if energyStr then
                            print("Parsed Energy String: '" .. energyStr .. "'")
                            energyNum = tonumber(energyStr:gsub("[%s,]", "")) or 0
                            print("Numeric Energy: " .. energyNum)
                        else
                            print("Warning: Energy string not found in line: " .. line)
                        end
                    elseif line:find("^[Cc]apacity:") then
                        local capacityStr = line:match("^[Cc]apacity:%s*([%d%s,]+)")
                        if capacityStr then
                            print("Parsed Capacity String: '" .. capacityStr .. "'")
                            capacityNum = tonumber(capacityStr:gsub("[%s,]", "")) or 0
                            print("Numeric Capacity: " .. capacityNum)
                        else
                            print("Warning: Capacity string not found in line: " .. line)
                        end
                    end
                end

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
                    else
                        print("Not enough time elapsed for panel '" .. panelName .. "' to calculate average EU/t. Delta Time: " .. deltaTime)
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
