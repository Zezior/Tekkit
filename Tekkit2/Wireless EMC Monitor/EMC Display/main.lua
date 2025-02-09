local graphic_update_rate = 1
local SECONDS_TO_MILLIS = 1000
local average_buffer = 120 * SECONDS_TO_MILLIS
local day_millis = 24 * 60 * 60 * 1000
local mon_peripheral = peripheral.find("monitor") or error("No monitor found!")
local width, height = mon_peripheral.getSize()
local most_stored = "Red Matter Furnace"
local box_w, box_h = 26, 10

-- Open Rednet for receiving on "back"
rednet.open("back")

local function center_box(p_width, p_height, c_width, c_height)
    return math.ceil(p_width / 2 - c_width / 2 + 0.5),
           math.ceil(p_height / 2 - c_height / 2 + 0.5)
end

local child_x, child_y = center_box(width, height, box_w, box_h)
local mon = window.create(mon_peripheral, child_x, child_y, box_w, box_h)

-- Define the clear function before it is used
local function clear()
    mon.setBackgroundColor(colors.gray)  -- Set background to gray
    mon.clear()
    mon.setTextColor(colors.white)  -- Set default text color to black
    mon_peripheral.setTextScale(1)
end

-- Function for centering text
local function centerText(text, width)
    local padding = math.floor((width - #text) / 2)
    return string.rep(" ", padding) .. text
end

-- Define the format_power function before using it
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

-- Define the formatTime function before using it
local function formatTime(sec)
    return string.format("%.2d:%.2d:%.2d", sec / (60 * 60), sec / 60 % 60, sec % 60)
end

clear()
mon_peripheral.setBackgroundColor(colors.gray)  -- Set default background to gray
mon_peripheral.clear()

-- Function to display the received data
local function displayEMCData(data)
    local emc = data.emc
    local emc_rate = data.emc_rate
    local net_gain = data.net_gain
    local most_stored = data.most_stored
    local amount = data.amount
    local time_str = data.time_str
    local emc_used = data.emc_used  -- New EMC Used data

    clear()

    -- Centered title
    mon.setTextColor(colors.green)  -- Set text color to black for title
    mon.setCursorPos(1, 1)
    mon.setBackgroundColor(colors.gray)  -- Keep the blue background for the title
    local title = "NuclearCity EMC Farm"
    mon.write(centerText(title, box_w))
    mon.setBackgroundColor(colors.gray)  -- Reset background to gray

    -- Centered storage
    mon.setTextColor(colors.purple)
    mon.setCursorPos(2, 3)
    local storageText = "Storage:    " .. format_power(emc, "emc")
    mon.write(centerText(storageText, box_w))

    -- Centered production
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(2, 4)
    local productionText = "Production: " .. format_power(emc_rate, "emc/m")
    mon.write(centerText(productionText, box_w))

    -- Centered net gain
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(2, 5)
    local netGainText = "Net gain:   " .. format_power(net_gain, "emc")
    mon.write(centerText(netGainText, box_w))

    -- Centered most stored item
    mon.setTextColor(colors.red)
    mon.setCursorPos(2, 7)
    mon.write(centerText(most_stored, box_w))
    mon.setCursorPos(2, 8)
    local amountText = "Amount:     " .. format_power(amount, "")
    mon.write(centerText(amountText, box_w))

    -- Centered EMC used
    mon.setTextColor(colors.green)
    mon.setCursorPos(2, 9)
    local emcUsedText = "EMC Used:  " .. format_power(emc_used, "emc")
    mon.write(centerText(emcUsedText, box_w))

    -- Centered time
    mon.setTextColor(colors.white)  -- Set text color for time
    mon.setBackgroundColor(colors.gray)  -- Ensure the background is gray for the time section
    mon.setCursorPos(1, 10)
    mon.write(centerText(time_str, box_w))

    print("EMC Data displayed!")  -- Added for debugging
end

-- Main loop to receive and display data from Rednet
while true do
    local senderID, message = rednet.receive()

    print("Message received: ", message)  -- Added for debugging

    -- Temporarily accept all senders for testing
    if type(message) == "table" then
        displayEMCData(message)  -- Display the EMC data using the original formatting
    else
        print("Invalid message or incorrect sender.")
    end
end