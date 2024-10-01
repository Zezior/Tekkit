-- aip_script.lua

-- Configuration
local panelSide = "bottom"         -- Side where the advanced information panel is connected
print("Panel Side:", panelSide)    -- Debugging line
local mainframeID = 4644           -- Mainframe's Rednet ID
local modemSide = "left"           -- Side where the modem is connected
local updateInterval = 1           -- Time in seconds between sending updates

-- Open the wireless modem for rednet communication
if modemSide then
    print("Opening modem on side:", modemSide)
    rednet.open(modemSide)  -- Adjust the side where your modem is connected
else
    print("Error: modemSide is nil!")
    return
end

-- Variables to store energy readings
local energyHistory = {}  -- Stores {time, energy} tuples
local calculationInterval = 20  -- Calculate energy usage over 20 seconds

-- Function to extract energy data from getCardData
local function extractEnergy(dataLine)
    print("Parsing Energy Line:", dataLine)
    -- Extract the numeric part before 'EU', remove spaces and commas
    local energyStr = dataLine:match("([%d%s,]+)%s*EU")
    if energyStr then
        energyStr = energyStr:gsub("[%s,]", "")  -- Remove spaces and commas
        local energyValue = tonumber(energyStr)
        if energyValue then
            print("Extracted Energy:", energyValue)
            return energyValue
        else
            print("Failed to convert energy string to number:", energyStr)
            return nil
        end
    else
        print("Failed to extract energy from line:", dataLine)
        return nil
    end
end

-- Function to extract fill percentage from getCardData
local function extractFillPercentage(dataLine)
    print("Parsing Fill Percentage Line:", dataLine)
    local percentageStr = dataLine:match("(%d+)")
    if percentageStr then
        local percentage = tonumber(percentageStr)
        print("Extracted Fill Percentage:", percentage)
        return percentage
    else
        print("Failed to extract fill percentage from line:", dataLine)
        return nil
    end
end

-- Function to send panel data
local function sendPanelData()
    -- Debug: Print panelSide before wrapping
    print("Attempting to wrap peripheral on side:", panelSide)
    
    -- Wrap the panel peripheral connected directly
    local panelPeripheral = peripheral.wrap(panelSide)

    if panelPeripheral then
        print("Peripheral successfully wrapped on side:", panelSide)
    else
        print("Error: No peripheral found on side:", panelSide)
        return
    end

    -- Get the card data from the panel
    local cardData = panelPeripheral.getCardData()

    -- Debug: Print raw card data
    if not cardData then
        print("Error: getCardData() returned nil.")
        return
    end

    print("Card Data Received:")
    for i, line in ipairs(cardData) do
        print(i .. ": " .. tostring(line))
    end

    -- Ensure cardData is valid
    if #cardData < 5 then
        print("Error: Expected at least 5 lines of card data, got " .. #cardData)
        return
    end

    -- Extract the panel name (1st line)
    local panelName = cardData[1]
    print("Panel Name:", panelName)

    -- Extract stored energy (2nd line)
    local storedEnergy = extractEnergy(cardData[2])

    -- Extract fill percentage (5th line)
    local fillPercentage = extractFillPercentage(cardData[5])

    if not panelName or not storedEnergy or not fillPercentage then
        print("Error: Could not retrieve panel data.")
        return
    end

    -- Get current time
    local currentTime = os.time()

    -- Append current reading to energyHistory
    table.insert(energyHistory, {time = currentTime, energy = storedEnergy})

    -- Remove readings older than calculationInterval seconds
    while #energyHistory > 0 and (currentTime - energyHistory[1].time) > calculationInterval do
        table.remove(energyHistory, 1)
    end

    -- Ensure we have data over the calculationInterval
    if #energyHistory < 2 then
        print("Not enough data to calculate energy usage. Need 20 seconds of data.")
        return
    end

    -- Find the earliest reading within the calculationInterval
    local earliestReading = energyHistory[1]
    local deltaEnergy = earliestReading.energy - storedEnergy  -- Energy used
    local deltaTime = currentTime - earliestReading.time   -- Time elapsed in seconds

    print(string.format("Delta Energy: %d EU over Delta Time: %d seconds", deltaEnergy, deltaTime))

    if deltaTime > 0 then
        -- Calculate energy usage per tick
        local energyUsage = deltaEnergy / (deltaTime * 20)  -- EU per tick
        print(string.format("Energy Usage: %.2f EU/t", energyUsage))

        -- Prepare the message to send
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
        print(string.format("Sent panel data to mainframe: %s - Energy Usage: %.2f EU/t - Filled: %d%%", panelName, energyUsage, fillPercentage))
    else
        print("Delta time is zero or negative. Setting energy usage to 0.")
    end
end

-- List all connected peripherals with sides (Debugging Step)
print("Listing all connected peripherals with sides:")
local sides = {"left", "right", "top", "bottom", "front", "back", "up", "down"}

for _, side in ipairs(sides) do
    if peripheral.isPresent(side) then
        print(side .. ": " .. peripheral.getType(side))
    end
end

-- Main loop to send data at intervals
while true do
    sendPanelData()
    sleep(updateInterval)  -- Wait for the next update (1 second)
end