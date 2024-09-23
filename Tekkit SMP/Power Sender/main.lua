-- pesu_sender.lua

-- Configuration
local modemSide = "top"         -- Adjust the side where the wired modem is attached
local updateInterval = 5        -- Time in seconds between sending updates
local mainframeID = 4591        -- Mainframe's Rednet ID
local pesuSide = "back"         -- Side where the PESU is connected (adjust as needed)

-- Open the wired modem on the specified side
rednet.open(modemSide)

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
    -- Get the EUOutput and EUStored from the PESU
    local euStored = peripheral.call(pesuSide, "getEUStored")
    local euOutput = peripheral.call(pesuSide, "getEUOutput")

    -- Prepare the message to send
    if euStored and euOutput then
        local message = {
            command = "pesu_data",
            pesuDataList = {
                {
                    title = "PESU",  -- You can change the title to something more specific if needed
                    energy = euStored,
                    capacity = 1000000000,  -- Replace with actual PESU capacity if available
                    euOutput = euOutput
                }
            }
        }

        -- Send the data to the mainframe
        rednet.send(mainframeID, message, "pesu_data")

        -- Debug print to confirm message sent
        print("Sent PESU data to mainframe: EU Stored: " .. formatNumber(euStored) .. " EU Output: " .. formatNumber(euOutput))
    else
        print("Error: Could not retrieve PESU data.")
    end
end

-- Main loop to send data at intervals
while true do
    sendPESUData()
    sleep(updateInterval)  -- Wait for the next update
end
