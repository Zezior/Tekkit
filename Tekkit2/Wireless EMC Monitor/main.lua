local graphic_update_rate = 1
local emc_readings = {}
local storage = peripheral.wrap("bottom")  -- Adjusted to "bottom"
local SECONDS_TO_MILLIS = 1000
local average_buffer = 120 * SECONDS_TO_MILLIS
local day_millis = 24 * 60 * 60 * 1000
local emc_used_file = "emc_used.log"

-- Automatically open Rednet for the modem on this computer (ComputerID 4815)
rednet.open("top")  -- Adjust for your modem side

-- Target Computer ID (Receiver is 4816)
local target_computer_id = 4816

-- Function to load the previous EMC used from file
local function loadEMCUsed()
    if fs.exists(emc_used_file) then
        local file = fs.open(emc_used_file, "r")
        local data = file.readAll()
        file.close()
        return tonumber(data) or 0  -- Return 0 if the file content is invalid
    end
    return 0
end

-- Function to save the current EMC used to file
local function saveEMCUsed(emc_used)
    local file = fs.open(emc_used_file, "w")
    file.write(tostring(emc_used))
    file.close()
end

-- Load the previous EMC used from the log file
local emc_used = loadEMCUsed()

-- Broadcast EMC data to the target computer
local function broadcastEMCData(emc, emc_rate, net_gain, amount, time_str)
    local data = {
        emc = emc,
        emc_rate = emc_rate,
        net_gain = net_gain,
        most_stored = "Red Matter Furnace",  -- Adjust this to dynamically get the most stored item if needed
        amount = amount,
        time_str = time_str,
        emc_used = emc_used  -- Add EMC used to the data sent
    }
    -- Send data via Rednet to the target computer ID (4816)
    rednet.send(target_computer_id, data)
    print("Data sent to computer ID: " .. target_computer_id)
    print("EMC: " .. emc .. ", EMC Rate: " .. emc_rate .. "/min, Net Gain: " .. net_gain .. ", Most Stored: Red Matter Furnace, Amount: " .. amount .. ", EMC Used: " .. emc_used)
end

-- Load the EMC values from emc_values.json
local file_handle = fs.open("emc_values.json", "r")
local json_string = file_handle.readAll()
file_handle.close()

local itemdb = textutils.unserialiseJSON(json_string)
if not itemdb then
    error("Failed to load EMC values from emc_values.json!")
end

local prefixes = {"n", "?", "m", "", "k", "M", "B", "T", "Q", "QT", "ST", "SET"}

local function format_power(n, unit)
    local abs_value = math.abs(n)

    if abs_value == 0 or abs_value == math.huge or abs_value ~= abs_value then
        return ("%.0f %s"):format(abs_value, unit)
    end

    local zeroes = math.floor(math.log10(abs_value) / 3)
    local prefix = prefixes[zeroes + 4] or ""

    local adjusted_value = abs_value / 1000 ^ zeroes
    local decimal_places = adjusted_value % 1 < 0.0001 and 0 or 1

    return ("%.1f%s %s"):format(adjusted_value * (n < 0 and -1 or 1), prefix, unit)
end

local function formatTime(sec)
    return string.format("%.2d:%.2d:%.2d", sec / (60 * 60), sec / 60 % 60, sec % 60)
end

local function count_storage()
    local item_count = 0
    local emc_amount = 0

    local success, list = pcall(function() return storage.list() end)
    if not success then
        print("Error: The block has changed or is unavailable.")
        return 0, 0  -- Return default values to avoid crashing the script
    end

    for slot, item in pairs(list) do
        item_count = item_count + item.count
        local stored = itemdb[("%s|%s"):format(item.name, item.damage)]
        if stored then
            emc_amount = emc_amount + (item.count * stored)
        end
    end

    return emc_amount, item_count
end

local net_gain = 0
local start_time = os.epoch("utc")
local past_emc = count_storage()

while true do
    local emc, amount = count_storage()
    local emc_delta = emc - past_emc

    -- Avoid negative production rate
    if emc_delta < 0 then
        -- Increase EMC used when EMC decreases
        emc_used = emc_used + math.abs(emc_delta)
        saveEMCUsed(emc_used)
    else
        net_gain = net_gain + emc_delta
        table.insert(emc_readings, 1, {emc = emc_delta, time = os.epoch("utc")})
    end

    local current_time = os.epoch("utc")
    local total_gain = 0
    local readings_timeframe = 0

    for i = 1, #emc_readings do
        local time = emc_readings[i].time
        local time_delta = current_time - time
        if time_delta > average_buffer then
            emc_readings[i] = nil
        else
            total_gain = total_gain + emc_readings[i].emc
            readings_timeframe = i
        end
    end

    local emc_gain = total_gain / readings_timeframe
    local emc_rate = math.floor(emc_gain) * 60

    -- Time string
    local time_str = "Time: " .. formatTime(((os.epoch("utc") - start_time) % day_millis) / 1000)

    -- Broadcast EMC data to the target computer (4816)
    broadcastEMCData(emc, emc_rate, net_gain, amount, time_str)

    past_emc = emc

    sleep(1 / graphic_update_rate)
end