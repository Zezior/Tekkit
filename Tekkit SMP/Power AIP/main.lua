-- aip_script.lua

-- Configuration
local panelSide = "top"         -- Side where the advanced information panel is connected
local updateInterval = 5        -- Time in seconds between sending updates
local mainframeID = 4644        -- Updated Mainframe's Rednet ID

-- Open the wireless modem for rednet communication
rednet.open("back")  -- Adjust the side where your modem is connected

-- Function to extract energy data from getCardData
local function extractEnergy(dataLine)
    local energyStr = dataLine:match("Energy:%s*([%d,%.]+)%s*EU")
    if energyStr then
        local energyValue = tonumber((energyStr:gsub(",", "")))
        return energyValue
    else
        return nil
    end
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

    -- Debug: Print the cardData content
    if cardData then
        print("Card Data:")
        for idx, line in ipairs(cardData) do
            print(idx .. ": " .. line)
        end
    else
        print("Error: cardData is nil")
        return
    end

    -- Ensure cardData is valid
    if not cardData or #cardData < 2 then
        print("Error: Invalid card data received.")
        return
    end

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
                    energy = energyValue
                    -- You can add more fields if needed
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
