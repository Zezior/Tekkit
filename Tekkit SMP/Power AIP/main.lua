-- aip_script.lua

-- Configuration
local modemSide = "back"        -- Adjust the side where the wired modem is attached
local updateInterval = 5        -- Time in seconds between sending updates
local mainframeID = 4591        -- Mainframe's Rednet ID
local panelSide = "top"         -- Side where the advanced information panel is connected

-- Open the wired modem on the specified side
rednet.open(modemSide)

-- Function to extract energy data from getCardData
local function extractEnergy(dataLine)
    local energyStr = dataLine:match("Energy:%s*([%d%s]+)%s*EU")
    if energyStr then
        local energyValue = tonumber(energyStr:gsub("%s", ""))  -- Remove spaces and convert to number
        return energyValue
    else
        return nil
    end
end

-- Function to send panel data
local function sendPanelData()
    -- Get the card data from the panel
    local cardData = peripheral.call(panelSide, "getCardData")

    -- Extract the panel name (1st line) and energy (2nd line)
    local panelName = cardData[1]
    local energyLine = cardData[2]
    local energyValue = extractEnergy(energyLine)

    -- Prepare the message to send
    if panelName and energyValue then
        local message = {
            command = "panel_data",
            panelDataList = {
                {
                    title = panelName,
                    energy = energyValue,
                    activeUsage = 100  -- Placeholder for active usage, replace with actual data if available
                }
            }
        }

        -- Send the data to the mainframe
        rednet.send(mainframeID, message, "panel_data")

        -- Debug print to confirm message sent
        print("Sent panel data to mainframe: " .. panelName .. " - Energy: " .. energyValue)
    else
        print("Error: Could not retrieve panel data.")
    end
end

-- Main loop to send data at intervals
while true do
    sendPanelData()
    sleep(updateInterval)  -- Wait for the next update
end
