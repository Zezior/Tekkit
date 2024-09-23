-- pesu_sender_auto.lua

-- Configuration
local wirelessModemSide = "top"    -- Side where the wireless modem is attached
local updateInterval = 5           -- Time in seconds between sending updates
local mainframeID = 4591           -- Mainframe's Rednet ID

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
        -- Check if the peripheral is a PESU (assuming the type starts with 'ic2:pesu')
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
            -- Retrieve EUStored, EUOutput, and EUCapacity values
            local storedEU = pesuPeripheral.getEUStored and pesuPeripheral.getEUStored() or 0
            local outputEU = pesuPeripheral.getEUOutput and pesuPeripheral.getEUOutput() or 0
            local capacityEU = pesuPeripheral.getEUCapacity and pesuPeripheral.getEUCapacity() or 0

            if storedEU > 0 and capacityEU > 0 then
                -- Format the energy values
                local formattedStored = formatNumber(storedEU)
                local formattedCapacity = formatNumber(capacityEU)
                local formattedOutput = formatNumber(outputEU)

                -- Add the PESU data to the list
                table.insert(pesuDataList, {
                    title = "PESU " .. pesuName,  -- Title for the PESU
                    energy = storedEU,
                    formattedEnergy = formattedStored,
                    capacity = capacityEU,
                    formattedCapacity = formattedCapacity,
                    euOutput = outputEU,
                    formattedOutput = formattedOutput
                })

                -- Debug print to confirm data
                print("Detected PESU: " .. pesuName .. " - EU Stored: " .. formattedStored .. " EU Output: " .. formattedOutput)
            else
                print("Error: Could not retrieve data from PESU: " .. pesuName)
            end
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
