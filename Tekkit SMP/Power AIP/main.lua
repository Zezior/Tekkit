-- aip_script.lua

-- Configuration
local panelSide = "bottom"         -- Side where the advanced information panel is connected
print("Panel Side:", panelSide)    -- Debugging line
local mainframeID = 4644           -- Mainframe's Rednet ID (Replace with your actual mainframe ID)
local modemSide = "left"           -- Side where the modem is connected
local updateInterval = 1           -- Time in seconds between sending updates
local logFile = "power_used.txt"   -- File to store total power used

-- Open the wireless modem for rednet communication
if modemSide then
    print("Opening modem on side:", modemSide)
    rednet.open(modemSide)  -- Adjust the side where your modem is connected
else
    print("Error: modemSide is nil!")
    return
end

-- Variable to store the last energy reading
local lastEnergy = nil

-- Variable to store total power used
local totalPowerUsed = 0

-- Function to load total power used from file
local function loadTotalPowerUsed()
    if fs.exists(logFile) then
        local file = fs.open(logFile, "r")
        local content = file.readAll()
        file.close()
        local value = tonumber(content)
        if value then
            totalPowerUsed = value
            print(string.format("Loaded total power used: %s", formatEU(totalPowerUsed)))
        else
            print("Error: Invalid data in power_used.txt. Starting from 0.")
            totalPowerUsed = 0
        end
    else
        totalPowerUsed = 0
        print("No existing power_used.txt found. Starting from 0.")
    end
end

-- Function to save total power used to file
local function saveTotalPowerUsed()
    local file = fs.open(logFile, "w")
    file.write(tostring(totalPowerUsed))
    file.close()
end

-- Function to format EU values
local function formatEU(value)
    if value >= 1e12 then
        return string.format("%.2f T EU", value / 1e12)
    elseif value >= 1e9 then
        return string.format("%.2f Bil EU", value / 1e9)  -- Bil for billion
    elseif value >= 1e6 then
        return string.format("%.2f M EU", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.2f k EU", value / 1e3)
    else
        return string.format("%.0f EU", value)
    end
end

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

    if lastEnergy == nil then
        -- First reading; store it and wait for the next reading
        lastEnergy = storedEnergy
        print("First energy reading stored. Awaiting next reading to calculate deltaEnergy.")
        return
    end

    -- Calculate total energy used over the last second
    local deltaEnergy_total = lastEnergy - storedEnergy  -- Total energy used over interval
    local deltaTime = currentTime - (currentTime - 1)  -- Should be 1 second

    print(string.format("Delta Energy (Total): %d EU over Delta Time: %d seconds", deltaEnergy_total, deltaTime))

    if deltaTime > 0 then
        -- Calculate energy usage per tick
        local deltaEnergy = deltaEnergy_total / 20  -- EU per tick (since 20 ticks per second)
        print(string.format("Delta Energy (EU/t): %.2f EU/t", deltaEnergy))

        -- Ensure deltaEnergy is non-negative
        if deltaEnergy < 0 then
            print("Warning: Negative delta energy detected. Setting to 0.")
            deltaEnergy = 0
        end

        -- Update total power used
        totalPowerUsed = totalPowerUsed + deltaEnergy
        print(string.format("Total Power Used: %s", formatEU(totalPowerUsed)))

        -- Save total power used to file
        saveTotalPowerUsed()

        -- Prepare the message to send
        local message = {
            command = "panel_data",
            panelDataList = {
                {
                    title = panelName,
                    fillPercentage = fillPercentage,
                    deltaEnergy = deltaEnergy,          -- EU per tick
                    totalPowerUsed = totalPowerUsed     -- Total EU used
                }
            }
        }

        -- Send the data to the mainframe
        rednet.send(mainframeID, message, "panel_data")

        -- Debug print to confirm message sent
        print(string.format("Sent panel data to mainframe: %s - Delta Energy: %.2f EU/t - Filled: %d%% - Power Used: %s", panelName, deltaEnergy, fillPercentage, formatEU(totalPowerUsed)))
    else
        print("Delta time is zero or negative. Setting delta energy to 0.")
    end

    -- Update lastEnergy for the next calculation
    lastEnergy = storedEnergy
end

-- List all connected peripherals with sides (Debugging Step)
print("Listing all connected peripherals with sides:")
local sides = {"left", "right", "top", "bottom", "front", "back", "up", "down"}

for _, side in ipairs(sides) do
    if peripheral.isPresent(side) then
        print(side .. ": " .. peripheral.getType(side))
    end
end

-- Load total power used from file
loadTotalPowerUsed()

-- Main loop to send data at intervals
while true do
    sendPanelData()
    sleep(updateInterval)  -- Wait for the next update (1 second)
end
