-- power_sender.lua

-- Description:
-- This script collects power data from both PESUs and Advanced Information Panels (AIPs)
-- connected via wired modems and sends the processed data to the Power Mainframe via wireless Rednet.

-- Configuration
local wirelessModemSide = "back"    -- Side where the wireless modem is attached (e.g., "back")
local wiredModemSides = { "left", "right", "front", "bottom", "top" } -- Sides with wired modems connected to peripherals
local refreshInterval = 2           -- Time in seconds between data sends
local protocol = "pesu_data"        -- Protocol name for communication

-- Optional: Define mainframe ID if sending to a specific computer
-- If you want to broadcast to all listening computers, you can omit the mainframeID or set it to nil
local mainframeID = nil              -- Replace with the mainframe's Rednet ID if needed (e.g., 5)

-- Default capacity for PESUs (adjust as necessary or retrieve dynamically if available)
local defaultPESUCapacity = 1000000000    -- Example: 1,000,000,000 EU

-- Ensure the wireless modem peripheral is available
local wirelessModem = peripheral.wrap(wirelessModemSide)
if not wirelessModem then
    print("Error: No wireless modem found on side '" .. wirelessModemSide .. "'. Please attach a wireless modem.")
    return
end

-- Open the Rednet connection on the specified wireless modem side
rednet.open(wirelessModemSide)
print("Wireless Rednet initialized on side '" .. wirelessModemSide .. "'.")

-- Function to parse energy string and extract numerical value
local function parseEnergy(energyStr)
    -- Example energyStr format: "2: Energy: 217 000 000 EU"
    local numStr = string.match(energyStr, "Energy:%s*([%d%s]+)")
    if numStr then
        -- Remove all spaces to convert to a continuous number
        numStr = string.gsub(numStr, "%s+", "")
        local energy = tonumber(numStr)
        if energy then
            return energy
        else
            print("Warning: Unable to convert energy string to number: '" .. energyStr .. "'")
            return 0
        end
    else
        print("Warning: Energy string format unexpected: '" .. energyStr .. "'")
        return 0
    end
end

-- Function to collect PESU data from a PESU peripheral
local function collectPESUData(wiredModem, side)
    local pesuDataList = {}
    -- Ensure the peripheral has EUOutput and EUStored methods
    if wiredModem.EUOutput and wiredModem.EUStored then
        local successOutput, euOutput = pcall(wiredModem.EUOutput)
        local successStored, euStored = pcall(wiredModem.EUStored)

        if successOutput and successStored then
            -- Retrieve energy output and stored energy
            local energyOutput = tonumber(euOutput) or 0
            local energyStored = tonumber(euStored) or 0

            -- Assign a unique name or identifier for the PESU
            local pesuName = wiredModem.getName and wiredModem.getName() or "PESU_" .. side

            table.insert(pesuDataList, {
                title = pesuName,
                energy = energyStored,
                capacity = defaultPESUCapacity,
            })
        else
            print("Warning: Failed to retrieve EU data from PESU connected to side '" .. side .. "'.")
        end
    else
        print("Warning: Peripheral on side '" .. side .. "' does not have EUOutput and EUStored methods.")
    end
    return pesuDataList
end

-- Function to collect panel data from an AIP peripheral
local function collectPanelData(wiredModem, side)
    local panelDataList = {}
    -- Ensure the peripheral has getCardData method
    if wiredModem.getCardData then
        local success, cardDataList = pcall(wiredModem.getCardData)
        if success and type(cardDataList) == "table" then
            for _, card in ipairs(cardDataList) do
                -- Ensure each card has at least two data points: name and energy
                if type(card) == "table" and #card >= 2 then
                    local name = tostring(card[1])
                    local energyStr = tostring(card[2])
                    local energy = parseEnergy(energyStr)

                    table.insert(panelDataList, {
                        title = name,
                        energy = energy,
                        capacity = defaultPESUCapacity,  -- Replace with actual capacity if available
                    })
                else
                    print("Warning: Invalid card data format from AIP on side '" .. side .. "'. Each card should be a table with at least two elements.")
                end
            end
        else
            print("Warning: Failed to retrieve card data from AIP connected to side '" .. side .. "'.")
        end
    else
        print("Warning: Peripheral on side '" .. side .. "' does not have getCardData method.")
    end
    return panelDataList
end

-- Function to collect all data from connected peripherals
local function collectAllData()
    local pesuDataList = {}
    local panelDataList = {}

    for _, side in ipairs(wiredModemSides) do
        if peripheral.isPresent(side) then
            local wiredModem = peripheral.wrap(side)
            if wiredModem then
                -- Determine the type of peripheral
                local isPESU = wiredModem.EUOutput and wiredModem.EUStored
                local isAIP = wiredModem.getCardData and type(wiredModem.getCardData) == "function"

                if isPESU then
                    -- Collect PESU data
                    local pesuData = collectPESUData(wiredModem, side)
                    for _, data in ipairs(pesuData) do
                        table.insert(pesuDataList, data)
                    end
                elseif isAIP then
                    -- Collect Panel data
                    local panelData = collectPanelData(wiredModem, side)
                    for _, data in ipairs(panelData) do
                        table.insert(panelDataList, data)
                    end
                else
                    print("Warning: Peripheral on side '" .. side .. "' is neither a PESU nor an AIP.")
                end
            else
                print("Warning: Failed to wrap peripheral on side '" .. side .. "'.")
            end
        else
            print("Warning: No peripheral present on side '" .. side .. "'.")
        end
    end

    return pesuDataList, panelDataList
end

-- Main loop to collect and send data
while true do
    -- Collect data from all connected peripherals
    local pesuDataList, panelDataList = collectAllData()

    -- Construct the message to send
    local message = {
        command = "pesu_data",
        pesuDataList = pesuDataList,
        panelDataList = panelDataList,
    }

    -- Send the message via Rednet
    if mainframeID then
        -- Send to a specific mainframe ID
        rednet.send(mainframeID, message, protocol)
        print("Sent PESU and Panel data to Mainframe ID " .. mainframeID)
    else
        -- Broadcast to all listening computers
        rednet.broadcast(message, protocol)
        print("Broadcasted PESU and Panel data to all listening mainframes.")
    end

    -- Wait for the next refresh interval
    sleep(refreshInterval)
end
