-- reactors.lua

local ui = require("ui")
local style = require("style")
local monitor = peripheral.wrap("right")

-- Set text scale globally from style
monitor.setTextScale(style.style.textScale)

-- Function to display the reactor data on the monitor with buttons
local function displayReactorData(reactors, pageNum, numReactorPages, reactorIDs)
    pageNum = pageNum or 1
    ui.resetButtons()  -- Reset the button list at the start

    -- Apply global background and text styles
    style.applyStyle()
    monitor.clear()

    -- Center and color the header
    local header = "NuclearCity - Reactor Status Page " .. pageNum
    local w, _ = monitor.getSize()
    local xHeader = math.floor((w - #header) / 2) + 1
    monitor.setCursorPos(xHeader, 1)
    monitor.setTextColor(colors.green)
    monitor.write(header)

    -- Constants
    local reactorsPerPage = 8  -- 2 columns of 4 reactors
    local reactorsPerColumn = 4
    local columnsPerPage = 2

    -- Adjusted button width
    local buttonWidth = 6

    -- Adjust content width to allow for more spacing
    local maxDataWidth = 25  -- Estimated maximum width of data displayed
    local contentWidth = buttonWidth + maxDataWidth + 2  -- +2 for padding
    local totalContentWidth = columnsPerPage * contentWidth
    local startX = math.floor((w - totalContentWidth) / 2) + 1

    -- Calculate xOffsets for columns
    local xOffsets = {}
    for i = 1, columnsPerPage do
        xOffsets[i] = startX + (i - 1) * contentWidth
    end

    -- Calculate start and end indices for reactors on this page
    local startIndex = (pageNum - 1) * reactorsPerPage + 1
    local endIndex = math.min(startIndex + reactorsPerPage - 1, #reactorIDs)

    -- Display reactor data
    local column = 1
    local lineInColumn = 3  -- Start from line 3 to leave space for header
    local reactorsInColumn = 0

    for idx = startIndex, endIndex do
        local reactorID = reactorIDs[idx]
        if reactorID then
            local data = reactors[reactorID]
            local x = xOffsets[column]
            local y = lineInColumn

            if data then
                -- Add buttons dynamically based on status
                ui.addReactorControlButtons(reactorID, data.active, x, y, data, buttonWidth)
            else
                -- No data available for this reactor
                -- Create a dummy data object with default values
                data = {
                    reactorName = "Reactor " .. reactorID,
                    temp = "N/A",
                    active = false,
                    euOutput = "0",
                    fuelRemaining = "N/A",
                    isMaintenance = false,
                    overheating = false,
                    destroyed = false,
                    status = "unknown"
                }
                -- Add buttons with default values
                ui.addReactorControlButtons(reactorID, data.active, x, y, data, buttonWidth)
            end
            x = x + buttonWidth + 2  -- Adjust x to leave space for the button and padding

            -- Display reactor name
            monitor.setTextColor(style.style.textColor)
            monitor.setCursorPos(x, y)
            monitor.write(tostring(data.reactorName))
            y = y + 1

            -- Display temperature
            monitor.setCursorPos(x, y)
            -- Check if temperature is over a threshold, set text color to red
            local tempString = tostring(data.temp):gsub("[^%d%.]", "")
            local tempValue = tonumber(tempString)
            if tempValue and tempValue > 4500 then
                monitor.setTextColor(colors.red)
            else
                monitor.setTextColor(style.style.textColor)
            end
            monitor.write("Temperature: " .. tostring(data.temp) .. "C")
            monitor.setTextColor(style.style.textColor) -- Reset color
            y = y + 1

            -- Display reactor status
            monitor.setCursorPos(x, y)
            monitor.write("Status: ")
            if data.destroyed then
                monitor.setTextColor(colors.black)
                monitor.write("Destroyed")
            elseif data.active then
                monitor.setTextColor(colors.green)
                monitor.write("On")
            else
                monitor.setTextColor(colors.red)
                monitor.write("Off")
            end
            monitor.setTextColor(style.style.textColor)
            y = y + 1

            -- Display reactor output
            monitor.setCursorPos(x, y)
            monitor.write("Output: " .. tostring(data.euOutput) .. " EU/t")
            y = y + 1

            -- Display reactor fuel remaining time
            monitor.setCursorPos(x, y)
            monitor.write("Fuel Remaining: " .. tostring(data.fuelRemaining))
            y = y + 1

            y = y + 1  -- Add a blank line for separation

            -- Update lineInColumn
            lineInColumn = y
            reactorsInColumn = reactorsInColumn + 1

            -- If we have displayed reactorsPerColumn reactors in this column, move to next column
            if reactorsInColumn >= reactorsPerColumn and column < columnsPerPage then
                column = column + 1
                lineInColumn = 3  -- Reset lineInColumn for new column
                reactorsInColumn = 0
            end
        else
            print("reactorID is nil at index", idx)
        end
    end

    -- Ensure the button bar is displayed at the bottom
    ui.centerButtons("reactor" .. pageNum, numReactorPages)
end

return {
    displayReactorData = displayReactorData
}
