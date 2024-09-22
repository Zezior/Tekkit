-- power_sender.lua

-- Description:
-- This script collects power data from both PESUs and Advanced Information Panels (AIPs)
-- connected via wired modems on the "back" side and sends the processed data
-- to the Power Mainframe via a wireless modem on the "top" side.

-- Configuration
local wirelessModemSide = "top"      -- Side where the wireless modem is attached
local wiredModemSide = "back"        -- Side where the wired modems are connected
local refreshInterval = 2             -- Time in seconds between data sends
local protocol = "pesu_data"          -- Protocol name for communication

-- Optional: Define mainframe ID if sending to a specific computer
-- If you want to broadcast to all listening computers, set to nil
local mainframeID = nil                -- Replace with the mainframe's Rednet ID if needed (e.g., 5)

-- Default capacity for PESUs (adjust as necessary or retrieve dynamically if available)
local defaultPESUCapacity = 1000000000    -- Example: 1,000,000,000 EU

-- Open Rednet on the wireless modem side
if not peripheral.isPresent(wirelessModemSide) then
    print("Error: No wireless modem found on side '" .. wirelessModemSide .. "'. Please attach a wireless modem.")
    return
end

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
local function collectPESUData(peripheralObj, peripheralName)
    local pesuDataList = {}
    -- Ensure the peripheral has EUOutput and EUStored methods
    if peripheralObj.EUOutput and peripheralObj.EUStored then
        local successOutput, euOutput = pcall(peripheralObj.EUOutput)
        local successStored, euStored = pcall(peripheralObj.EUStored)

        if successOutput and successStored then
            -- Retrieve energy output and stored energy
            local energyOutput = tonumber(euOutput) or 0
            local energyStored = tonumber(euStored) or 0

            -- Assign a unique name or identifier for the PESU
            local pesuName = peripheralObj.getName and peripheralObj.getName() or "PESU_" .. peripheralName

            table.insert(pesuDataList, {
                title = pesuName,
                energy = energyStored,
                capacity = defaultPESUCapacity,
            })
        else
            print("Warning: Failed to retrieve EU data from PESU '" .. peripheralName .. "'.")
        end
    else
        print("Warning: Peripheral '" .. peripheralName .. "' does not have EUOutput and EUStored methods.")
    end
    return pesuDataList
end

-- Function to collect panel data from an AIP peripheral
local function collectPanelData(peripheralObj, peripheralName)
    local panelDataList = {}
    -- Ensure the peripheral has getCardData method
    if peripheralObj.getCardData and type(peripheralObj.getCardData) == "function" then
        local success, cardDataList = pcall(peripheralObj.getCardData)
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
                    print("Warning: Invalid card data format from AIP '" .. peripheralName .. "'. Each card should be a table with at least two elements.")
                end
            end
        else
            print("Warning: Failed to retrieve card data from AIP '" .. peripheralName .. "'.")
        end
    else
        print("Warning: Peripheral '" .. peripheralName .. "' does not have getCardData method.")
    end
    return panelDataList
end

-- Function to collect all data from connected peripherals
local function collectAllData()
    local pesuDataList = {}
    local panelDataList = {}

    -- Get all peripheral names
    local peripheralNames = peripheral.getNames()

    -- Iterate through each peripheral and process accordingly
    for _, peripheralName in ipairs(peripheralNames) do
        -- Skip the wireless modem
        if peripheralName == wirelessModemSide then
            goto continue
        end

        local peripheralObj = peripheral.wrap(peripheralName)
        if peripheralObj then
            -- Determine the type of peripheral
            local isPESU = peripheralObj.EUOutput and peripheralObj.EUStored
            local isAIP = peripheralObj.getCardData and type(peripheralObj.getCardData) == "function"

            if isPESU then
                -- Collect PESU data
                local pesuData = collectPESUData(peripheralObj, peripheralName)
                for _, data in ipairs(pesuData) do
                    table.insert(pesuDataList, data)
                end
            elseif isAIP then
                -- Collect Panel data
                local panelData = collectPanelData(peripheralObj, peripheralName)
                for _, data in ipairs(panelData) do
                    table.insert(panelDataList, data)
                end
            else
                -- Peripheral is neither PESU nor AIP; ignore or handle accordingly
                -- print("Info: Peripheral '" .. peripheralName .. "' is neither PESU nor AIP.")
            end
        else
            print("Warning: Failed to wrap peripheral '" .. peripheralName .. "'.")
        end

        ::continue::
    end

    return pesuDataList, panelDataList
end

-- Main loop to collect and send data
while true do
    -- Collect data from all connected peripherals
    local pesuDataList, panelDataList = collectAllData()

    -- Debugging: Print collected data
    print("Collected PESU Data:")
    for _, pesu in ipairs(pesuDataList) do
        print(pesu.title, pesu.energy, pesu.capacity)
    end

    print("Collected Panel Data:")
    for _, panel in ipairs(panelDataList) do
        print(panel.title, panel.energy, panel.capacity)
    end

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
