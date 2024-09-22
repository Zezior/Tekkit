-- power_sender.lua

-- Configuration
local modemSide = "top"         -- Adjust the side where the modem is attached
local updateInterval = 5        -- Time in seconds between sending updates
local mainframeID = 4591        -- Mainframe's Rednet ID
local peripheralSide = "back"   -- Side where the PESU is connected

-- Open the modem on the specified side
rednet.open(modemSide)

-- Function to format large numbers (with conversion)
local function formatNumber(num)
    if num >= 1e12 then
        return string.format("%.1ftril", num / 1e12)
    elseif num >= 1e9 then
        return string.format("%.1fbil", num / 1e9)
    elseif num >= 1e6 then
        return string.format("%.1fmil", num / 1e6)
    elseif num >= 1e3 then
        return string.format("%.1fk", num / 1e3)
    else
        return tostring(num)
    end
end

-- Function to extract energy value from string
local function extractEnergy(dataLine)
    local energyStr = dataLine:match("Energy:%s*([%d%s]+)%s*EU")
    if energyStr then
        local energyValue = tonumber(energyStr:gsub("%s", ""))  -- Remove spaces and convert to number
        return energyValue
    else
        return nil
    end
end

-- Main function to send PESU data
local function sendPESUData()
    -- Get PESU card data
    local cardData = peripheral.call(peripheralSide, "getCardData")

    -- Extract the PESU name (1st bit of data) and energy value (2nd bit of data)
    local pesuName = cardData[1]
    local energyLine = cardData[2]
    local energyValue = extractEnergy(energyLine)

    if pesuName and energyValue then
        -- Format the energy value for easier reading
        local formattedEnergy = formatNumber(energyValue)

        -- Prepare the message to send
        local message = {
            command = "pesu_data",
            pesuDataList = {
                {
                    title = pesuName,
                    energy = energyValue,
                    capacity = 1000000000  -- Example capacity, replace with actual capacity if available
                }
            }
        }

        -- Send the data to the mainframe
        rednet.send(mainframeID, message, "pesu_data")

        -- Debug print to confirm message sent
        print("Sent PESU data to mainframe: " .. pesuName .. " - Energy: " .. formattedEnergy)
    else
        print("Error: Could not extract PESU data.")
    end
end

-- Main loop to send data at intervals
while true do
    sendPESUData()
    sleep(updateInterval)  -- Wait for the next update
end
