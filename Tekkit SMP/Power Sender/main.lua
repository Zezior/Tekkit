-- pesu_sender.lua

-- Configuration
local wirelessModemSide = "top"     -- Side where the wireless modem is attached
local updateInterval = 5            -- Time in seconds between sending updates
local mainframeID = 4591            -- Mainframe's Rednet ID
local wiredModemSide = "back"       -- Side where the wired modem is attached (connected to PESUs)

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
    -- Find the PESU peripheral connected via the wired modem
    local pesuPeripheral = peripheral.find("PESU")  -- Replace "PESU" with the actual type if necessary

    if not pesuPeripheral then
        print("Error: No PESU peripheral found.")
        return
    end

    -- Get the name of the PESU peripheral
    local pesuName = peripheral.getName(pesuPeripheral)

    -- List available methods for debugging
    local methods = peripheral.getMethods(pesuName)
    print("Available methods for PESU:")
    for _, method in ipairs(methods) do
        print(method)
    end

    -- Retrieve EUStored and EUOutput values based on available methods
    local euStoredMethod = pesuPeripheral.getEUStored or pesuPeripheral.getStoredEU or pesuPeripheral.getEUStorage
    local euOutputMethod = pesuPeripheral.getEUOutput or pesuPeripheral.getOutputEU

    if euStoredMethod and euOutputMethod then
        local storedEU = euStoredMethod()
        local outputEU = euOutputMethod()

        local message = {
            command = "pesu_data",
            pesuDataList = {
                {
                    title = "PESU",  -- You can change the title to something more specific if needed
                    energy = storedEU,
                    capacity = 1000000000,  -- Replace with actual PESU capacity if available
                    euOutput = outputEU
                }
            }
        }

        -- Send the data to the mainframe
        rednet.send(mainframeID, message, "pesu_data")

        -- Debug print to confirm message sent
        print("Sent PESU data to mainframe: EU Stored: " .. formatNumber(storedEU) .. " EU Output: " .. formatNumber(outputEU))
    else
        print("Error: Could not retrieve EUStored or EUOutput methods.")
    end
end

-- Main loop to send data at intervals
while true do
    sendPESUData()
    sleep(updateInterval)  -- Wait for the next update
end
