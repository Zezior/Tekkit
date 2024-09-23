--- pesu_sender.lua

-- Configuration
local wirelessModemSide = "top"          -- Side where the wireless modem is attached
local updateInterval = 5                 -- Time in seconds between sending updates
local mainframeID = 4591                 -- Mainframe's Rednet ID
local pesuPeripheralName = "ic2:pesu_222" -- Detected PESU peripheral name

-- Open the wireless modem for rednet communication
rednet.open(wirelessModemSide)

-- Function to format large numbers
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

-- Main function to send PESU data
local function sendPESUData()
    -- Wrap the PESU peripheral using the actual peripheral name
    local pesuPeripheral = peripheral.wrap(pesuPeripheralName)

    if not pesuPeripheral then
        print("Error: No PESU peripheral found with name: " .. pesuPeripheralName)
        return
    end

    -- Dynamically check for methods (to avoid nil method error)
    local storedEU = pesuPeripheral.getEUStored and pesuPeripheral.getEUStored() or 0
    local outputEU = pesuPeripheral.getEUOutput and pesuPeripheral.getEUOutput() or 0
    local capacityEU = pesuPeripheral.getEUCapacity and pesuPeripheral.getEUCapacity() or 0

    if storedEU > 0 and outputEU > 0 and capacityEU > 0 then
        -- Format the energy values
        local formattedStored = formatNumber(storedEU)
        local formattedCapacity = formatNumber(capacityEU)
        local formattedOutput = formatNumber(outputEU)

        -- Prepare the message to send
        local message = {
            command = "pesu_data",
            pesuDataList = {
                {
                    title = "PESU",
                    energy = storedEU,
                    formattedEnergy = formattedStored,
                    capacity = capacityEU,
                    formattedCapacity = formattedCapacity,
                    euOutput = outputEU,
                    formattedOutput = formattedOutput
                }
            }
        }

        -- Send the data to the mainframe
        rednet.send(mainframeID, message, "pesu_data")

        -- Debug print to confirm message sent
        print("Sent PESU data to mainframe: EU Stored: " .. formattedStored .. " EU Output: " .. formattedOutput)
    else
        print("Error: Could not retrieve PESU data.")
    end
end

-- Main loop to send data at intervals
while true do
    sendPESUData()
    sleep(updateInterval)  -- Wait for the next update
end
