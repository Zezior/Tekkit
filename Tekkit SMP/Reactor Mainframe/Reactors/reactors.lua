-- reactors.lua

local ui = require("ui")
local style = require("style")
local monitor = peripheral.wrap("right")

-- Set text scale globally from style
monitor.setTextScale(style.style.textScale)

-- Function to format numbers with commas
local function formatNumber(number)
    local formatted = tostring(number)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end
    return formatted
end

-- Function to display the reactor data on the monitor with buttons
local function displayReactorData(reactors)
    ui.resetButtons()  -- Reset the button list at the start
    style.applyStyle()  -- Apply global background and text styles
    monitor.clear()
    monitor.setCursorPos(1, 1)

    -- Display header
    monitor.setTextColor(style.style.headerColor)
    monitor.write("NuclearCity - Reactor Status")

    -- Sort reactor IDs to ensure they are displayed in correct order
    local reactorIDs = {}
    for reactorID, _ in pairs(reactors) do
        table.insert(reactorIDs, tonumber(reactorID))
    end
    table.sort(reactorIDs)

    -- Display reactor data in sorted order
    local line = 3  -- Start from line 3 to leave space for header
    for _, reactorID in ipairs(reactorIDs) do
        local data = reactors[reactorID]

        if data then
            -- Display reactor name
            monitor.setTextColor(style.style.textColor)
            monitor.setCursorPos(9, line)
            monitor.write(tostring(data.reactorName))
            line = line + 1

            -- Display temperature
            monitor.setCursorPos(9, line)
            monitor.write("Temperature: " .. tostring(data.temp) .. "C")
            line = line + 1

            -- Display reactor status
            monitor.setCursorPos(9, line)
            monitor.write("Status: " .. (data.active and "On" or "Off"))
            line = line + 1

            -- Display reactor output
            monitor.setCursorPos(9, line)
            monitor.write("Output: " .. tostring(data.euOutput) .. " EU/t")
            line = line + 1

            -- Display reactor fuel remaining time
            monitor.setCursorPos(9, line)
            monitor.write("Fuel Remaining: " .. tostring(data.fuelRemaining))
            line = line + 1

            -- Add buttons dynamically based on status
            ui.addReactorControlButtons(tonumber(reactorID), data.active, line)
            line = line + 2  -- Add a blank line for separation
        else
            print("No data available for reactor: " .. reactorID)
        end
    end

    -- Ensure the button bar is displayed at the bottom
    ui.centerButtons("reactor")
end

return {
    displayReactorData = displayReactorData
}
