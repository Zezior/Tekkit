-- aip_script.lua

-- Configuration
local modemSide = "back"         -- Adjust the side where the wired modem is attached
local updateInterval = 5        -- Time in seconds between sending updates
local mainframeID = 4591        -- Mainframe's Rednet ID
local panelSide = "top"        -- Side where the advanced information panel is connected

-- Open the wired modem on the specified side
rednet.open(modemSide)

-- Function to extract panel data
local function getPanelData()
    -- Get panel card data
    local cardData = peripheral.call(panelSide, "getCardData")

    -- Assuming the first line is the panel name and the second is energy information
    local panelName = cardData[1]
    local energyLine = cardData[2]
    local energyValue = extractEnergy(energyLine)

    if panelName and energyValue then
        return {
            title = panelName,
            energy = energyValue,
            activeUsage = 100  -- Placeholder, replace with actual data if available
        }
    else
        return nil
    end
end

-- Function to send panel data
local function sendPanelData()
    local panelData = getPanelData()
    
    if panelData then
        -- Prepare the message to send
        local message = {
            command = "panel_data",
            panelDataList = {
                panelData
            }
        }

        -- Send the data to the mainframe
        rednet.send(mainframeID, message, "panel_data")

        -- Debug print to confirm message sent
        print("Sent panel data to mainframe: " .. panelData.title .. " - Energy: " .. formatNumber(panelData.energy))
    else
        print("Error: Could not retrieve panel data.")
    end
end

-- Main loop to send data at intervals
while true do
    sendPanelData()
    sleep(updateInterval)  -- Wait for the next update
end
