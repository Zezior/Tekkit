-- aip_script.lua

-- Configuration
local panelSide = "bottom"         -- Side where the advanced information panel is connected
local mainframeID = 4644        -- Mainframe's Rednet ID
local modemSide = "left"        -- Side where the modem is connected
local updateInterval = 15       -- Time in seconds between sending updates

-- Open the wireless modem for rednet communication
rednet.open(modemSide)  -- Adjust the side where your modem is connected

-- Variables to store energy readings
local previousEnergy = nil
local previousTime = nil

-- Function to extract energy data from getCardData
local function extractEnergy(dataLine)
    local energyStr = dataLine:match("([%d%s]+)%s*EU")
    if energyStr then
        local energyValue = tonumber((energyStr:gsub("%s", "")))
        return energyValue
    else
        return nil
    end
end

-- Function to extract fill percentage from getCardData
local function extractFillPercentage(dataLine)
    local percentage = tonumber(dataLine)
    return percentage
end

-- Function to send panel data
local function sendPanelData()
    -- Wrap the panel peripheral connected directly
    local panelPeripheral = peripheral.wrap(panelSide)

    if not panelPeripheral then
        print("Error: No panel peripheral found on side: " .. panelSide)
        return
    end

    -- Get the card data from the panel
    local cardData = panelPeripheral.getCardData()

    -- Ensure cardData is valid
    if not cardData or #cardData < 5 then
        print("Error: Invalid card data received.")
        return
    end

    -- Extract the panel name (1st line)
    local panelName = cardData[1]

    -- Extract stored energy (2nd line)
    local storedEnergy = extractEnergy(cardData[2])

    -- Extract fill percentage (5th line)
    local fillPercentage = tonumber(cardData[5])

    if not panelName or not storedEnergy or not fillPercentage then
        print("Error: Could not retrieve panel data.")
        return
    end

    -- Calculate energy usage
    local currentTime = os.clock()
    local energyUsage = nil

    if previousEnergy and previousTime then
        local deltaEnergy = previousEnergy - storedEnergy  -- Energy used
        local deltaTime = currentTime - previousTime       -- Time elapsed in seconds
        local totalTicks = deltaTime * 20                  -- Total ticks (20 ticks per second)

        if totalTicks > 0 then
            energyUsage = deltaEnergy / totalTicks  -- EU per tick
        else
            energyUsage = 0
        end
    end

    -- Update previous readings
    previousEnergy = storedEnergy
    previousTime = currentTime

    -- Prepare the message to send
    if energyUsage then
        local message = {
            command = "panel_data",
            panelDataList = {
                {
                    title = panelName,
                    fillPercentage = fillPercentage,
                    energyUsage = energyUsage
                }
            }
        }

        -- Send the data to the mainframe
        rednet.send(mainframeID, message, "panel_data")

        -- Debug print to confirm message sent
        print("Sent panel data to mainframe: " .. panelName .. " - Energy Usage: " .. string.format("%.2f", energyUsage) .. " EU/T - Filled: " .. fillPercentage .. "%")
    else
        print("Waiting for next reading to calculate energy usage...")
    end
end

-- Main loop to send data at intervals
while true do
    sendPanelData()
    sleep(updateInterval)  -- Wait for the next update
end
