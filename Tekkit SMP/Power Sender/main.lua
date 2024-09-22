-- power_sender.lua

-- Description:
-- This script collects power data from PESU cards using the `getCardData` function
-- and sends the processed data to the Power Mainframe via wireless Rednet.

-- Configuration
local modemSide = "back"        -- Side where the wireless modem is attached (e.g., "back")
local refreshInterval = 2       -- Time in seconds between data sends
local protocol = "pesu_data"    -- Protocol name for communication

-- Optional: Define mainframe ID if sending to a specific computer
-- If you want to broadcast to all listening computers, you can omit the mainframeID or set it to nil
local mainframeID = nil          -- Replace with the mainframe's Rednet ID if needed (e.g., 5)

-- Default capacity for PESUs (adjust as necessary)
local defaultCapacity = 1000000000  -- Example: 1,000,000,000 EU

-- Ensure the modem peripheral is available
local modem = peripheral.wrap(modemSide)
if not modem then
    print("Error: No modem found on side '" .. modemSide .. "'. Please attach a wireless modem.")
    return
end

-- Open the Rednet connection on the specified modem side
rednet.open(modemSide)
print("Rednet initialized on side '" .. modemSide .. "'.")

-- Function to parse the energy string and extract the numerical value
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

-- Main loop to collect and send PESU data
while true do
    -- Retrieve the list of PESU cards
    local success, cardDataList = pcall(getCardData)
    if not success then
        print("Error: Failed to retrieve card data. Ensure that 'getCardData' is defined and functioning.")
    elseif type(cardDataList) ~= "table" then
        print("Error: 'getCardData' did not return a table. Received type: " .. type(cardDataList))
    else
        -- Prepare the PESU data list to send
        local pesuDataList = {}

        for _, card in ipairs(cardDataList) do
            -- Ensure each card has at least two data points: name and energy
            if type(card) == "table" and #card >= 2 then
                local name = tostring(card[1])
                local energyStr = tostring(card[2])
                local energy = parseEnergy(energyStr)

                -- You can customize how capacity is determined.
                -- For now, we use a default capacity. Modify as needed.
                local capacity = defaultCapacity

                table.insert(pesuDataList, {
                    title = name,
                    energy = energy,
                    capacity = capacity,
                })
            else
                print("Warning: Invalid card data format. Each card should be a table with at least two elements.")
            end
        end

        -- Construct the message to send
        local message = {
            command = "pesu_data",
            pesuDataList = pesuDataList,
            -- If you have panel data, you can include it here as well
            -- panelDataList = panelDataList,  -- Add if applicable
        }

        -- Send the message via Rednet
        if mainframeID then
            -- Send to a specific mainframe ID
            rednet.send(mainframeID, message, protocol)
            print("Sent PESU data to Mainframe ID " .. mainframeID)
        else
            -- Broadcast to all listening computers
            rednet.broadcast(message, protocol)
            print("Broadcasted PESU data to all listening mainframes.")
        end
    end

    -- Wait for the next refresh interval
    sleep(refreshInterval)
end
