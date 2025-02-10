-- Power sender 
-- main.lua

-- Configuration
local wirelessModemSide = "top"    -- Side where the wireless modem is attached
local updateInterval = 10           -- Time in seconds between sending updates
local mainframeID = 7560            -- Mainframe's Rednet ID

rednet.open(wirelessModemSide)

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

local function detectPESUs()
    local pesuList = {}
    local peripheralNames = peripheral.getNames()
    for _, name in ipairs(peripheralNames) do
        if peripheral.getType(name):find("pesu") then
            table.insert(pesuList, name)
        end
    end
    return pesuList
end

local function sendPESUData()
    local pesus = detectPESUs()
    if #pesus == 0 then
        print("Error: No PESU peripherals detected.")
        return
    end
    local pesuDataList = {}
    for _, pesuName in ipairs(pesus) do
        local pesuPeripheral = peripheral.wrap(pesuName)
        if pesuPeripheral then
            local storedEU = pesuPeripheral.getEUStored and pesuPeripheral.getEUStored() or 0
            table.insert(pesuDataList, {
                energy = storedEU
            })
            print("Detected PESU - EU Stored: " .. formatNumber(storedEU))
        else
            print("Error: Could not wrap PESU: " .. pesuName)
        end
    end
    if #pesuDataList > 0 then
        local message = {
            command = "pesu_data",
            pesuDataList = pesuDataList
        }
        rednet.send(mainframeID, message, "pesu_data")
        print("Sent PESU data to mainframe.")
    end
end

while true do
    sendPESUData()
    sleep(updateInterval)
end
