-- pesu_sender_auto.lua

-- Configuration
local wirelessModemSide = "top"    -- Side where the wireless modem is attached
local updateInterval = 5           -- Time in seconds between sending updates
local mainframeID = 4644           -- Mainframe's Rednet ID

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

-- Function to detect PESU peripherals
local function detectPESUs()
    local pesuList = {}
    
    -- Get the names of all peripherals connected to the computer
    local peripheralNames = peripheral.getNames()

    -- Loop through the peripheral names to find PESUs
    for _, name in ipairs(peripheralNames) do
        -- Check if the peripheral is a PESU (assuming the type contains 'pesu')
        if peripheral.getType(name):find("pesu") then
            table.insert(pesuList, name)
        end
    end

    return pesuList
end

-- Main function to send PESU data
local function sendPESUData()
    -- Detect all connected PESUs
    local pesus = detectPESUs()

    if #pesus == 0 then
        print("Error: No PESU peripherals detected.")
        return
    end

    -- Prepare the list of PESU data to send
    local pesuDataList = {}

    for _, pesuName in ipairs(pesus) do
        -- Wrap the PESU peripheral
        local pesuPeripheral = peripheral.wrap(pesuName)

        if pesuPeripheral then
            -- Retrieve EUStored
            local storedEU = pesuPeripheral.getEUStored and pesuPeripheral.getEUStored() or 0

            -- Fixed capacity
            local capacityEU = 1000000000  -- 1,000,000,000 EU

            -- Since PESU IDs are not needed, we set the title to "PESU"
            local pesuTitle = "PESU"

            -- Format the energy values
            local formattedStored = formatNumber(storedEU)

            -- Add the PESU data to the list
            table.insert(pesuDataList, {
                title = pesuTitle,  -- Title for the PESU
                energy = storedEU
            })

            -- Debug print to confirm data
            print("Detected PESU: " .. pesuName .. " - EU Stored: " .. formattedStored)
        else
            print("Error: Could not wrap PESU: " .. pesuName)
        end
    end

    -- Send the PESU data to the mainframe
    if #pesuDataList > 0 then
        local message = {
            command = "pesu_data",
            pesuDataList = pesuDataList
        }

        rednet.send(mainframeID, message, "pesu_data")
        print("Sent PESU data to mainframe.")
    end
end

-- Main loop to send data at intervals
while true do
    sendPESUData()
    sleep(updateInterval)  -- Wait for the next update
end
