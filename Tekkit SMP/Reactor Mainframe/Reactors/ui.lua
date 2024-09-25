-- ui.lua

local ui = {}

-- Define colors
local colors = {
    white = colors.white,
    black = colors.black,
    red = colors.red,
    green = colors.green,
    blue = colors.blue,
    yellow = colors.yellow,
    orange = colors.orange,
    brown = colors.brown,
    custom = colors.brown  -- Using 'colors.brown' for custom color
}

-- Set custom background color
local bgColor = colors.custom
local monitor = peripheral.wrap("right")  -- Adjust monitor side as needed
monitor.setPaletteColor(bgColor, 18 / 255, 53 / 255, 36 / 255)  -- RGB values for #123524

-- Initialize button list
local buttonList = {}

-- Function to add a button
function ui.addButton(name, x, y, width, height)
    buttonList[name] = {x = x, y = y, width = width, height = height}
end

-- Function to detect button press
function ui.detectButtonPress(x, y)
    for name, button in pairs(buttonList) do
        if x >= button.x and x <= (button.x + button.width - 1) and y >= button.y and y <= (button.y + button.height -1) then
            return name
        end
    end
    return nil
end

-- Function to clear buttons
function ui.clearButtons()
    buttonList = {}
end

-- Function to bind reactor buttons
function ui.bindReactorButtons(reactorTable, repo)
    for name, reactor in pairs(reactorTable) do
        repo.bind(reactor.id .. "_state", function(newState)
            -- Update UI when reactor state changes
            -- Not used in this implementation
        end)
    end
end

-- Function to display the home page
function ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU)
    monitor.setBackgroundColor(bgColor)
    monitor.clear()
    monitor.setTextScale(0.5)

    -- Clear previous buttons
    ui.clearButtons()

    -- Draw the header
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.green)
    monitor.write("NuclearCity Reactor Control")
    monitor.setTextColor(colors.white)

    -- Get monitor size
    local w, h = monitor.getSize()

    -- Display reactor status
    local reactorsAreOn = false
    for _, reactorData in pairs(reactors) do
        if reactorData.active then
            reactorsAreOn = true
            break
        end
    end

    local statusText = reactorsAreOn and "Reactors Are ON" or "Reactors Are OFF"
    local statusColor = reactorsAreOn and colors.green or colors.red
    monitor.setTextColor(statusColor)
    monitor.setCursorPos(1, 3)
    monitor.write(statusText)
    monitor.setTextColor(colors.white)

    -- Display total reactor output
    local totalOutput = 0
    for _, data in pairs(reactors) do
        local output = tonumber(data.euOutput) or 0
        totalOutput = totalOutput + output
    end
    monitor.setCursorPos(1, 4)
    monitor.write("Total Reactor Output: " .. totalOutput .. " EU/t")

    -- Draw the "All On"/"All Off" button at the bottom left corner
    local buttonText = reactorsAreOn and "All Off" or "All On"
    local buttonColor = reactorsAreOn and colors.red or colors.green
    -- Define the button dimensions
    local buttonWidth = 8
    local buttonHeight = 3
    local buttonX = 2  -- Far bottom left corner
    local buttonY = h - buttonHeight + 1

    -- Draw the button
    monitor.setBackgroundColor(buttonColor)
    monitor.setTextColor(colors.white)
    for i = 0, buttonHeight - 1 do
        monitor.setCursorPos(buttonX, buttonY + i)
        monitor.write(string.rep(" ", buttonWidth))
    end
    -- Center the button text
    local labelX = buttonX + math.floor((buttonWidth - #buttonText) / 2)
    local labelY = buttonY + math.floor(buttonHeight / 2)
    monitor.setCursorPos(labelX, labelY)
    monitor.write(buttonText)
    monitor.setBackgroundColor(bgColor)

    -- Add the button to the button list for interaction
    ui.addButton("toggle_all", buttonX, buttonY, buttonWidth, buttonHeight)

    -- Display navigation buttons for reactor pages
    local pageButtonWidth = 10
    local pageButtonHeight = 3
    local pageButtonY = h - pageButtonHeight + 1
    local pageButtonX = w - pageButtonWidth - 2  -- Right side

    -- Draw Reactor Pages button
    monitor.setBackgroundColor(colors.blue)
    monitor.setTextColor(colors.white)
    for i = 0, pageButtonHeight - 1 do
        monitor.setCursorPos(pageButtonX, pageButtonY + i)
        monitor.write(string.rep(" ", pageButtonWidth))
    end
    local pageButtonText = "Reactors"
    local pageLabelX = pageButtonX + math.floor((pageButtonWidth - #pageButtonText) / 2)
    local pageLabelY = pageButtonY + math.floor(pageButtonHeight / 2)
    monitor.setCursorPos(pageLabelX, pageLabelY)
    monitor.write(pageButtonText)
    monitor.setBackgroundColor(bgColor)

    -- Add the button to the button list
    ui.addButton("reactor1", pageButtonX, pageButtonY, pageButtonWidth, pageButtonHeight)

    -- Display reactor logs or statuses
    monitor.setCursorPos(1, 6)
    monitor.write("Reactor Output Logs:")
    local y = 7
    for id, log in pairs(reactorOutputLog) do
        if y > h - buttonHeight - 1 then
            break
        end
        monitor.setCursorPos(1, y)
        monitor.write(log.reactorName .. ": " .. log.maxOutput .. " EU/t")
        y = y + 1
    end
end

-- Function to display reactor data pages
function ui.displayReactorData(reactors, pageNum, numReactorPages, reactorIDs)
    monitor.setBackgroundColor(bgColor)
    monitor.clear()
    monitor.setTextScale(0.5)

    -- Clear previous buttons
    ui.clearButtons()

    -- Draw the header
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.green)
    monitor.write("Reactor Status Page " .. pageNum)
    monitor.setTextColor(colors.white)

    -- Get monitor size
    local w, h = monitor.getSize()

    -- Display reactors per page
    local reactorsPerPage = 8
    local startIdx = (pageNum - 1) * reactorsPerPage + 1
    local endIdx = math.min(startIdx + reactorsPerPage -1, #reactorIDs)
    local y = 3

    for idx = startIdx, endIdx do
        local reactorID = reactorIDs[idx]
        local reactorData = reactors[reactorID]
        if reactorData then
            monitor.setCursorPos(1, y)
            monitor.write("Reactor " .. idx .. ":")
            y = y + 1
            monitor.setCursorPos(3, y)
            monitor.write("Status: " .. (reactorData.active and "Active" or "Inactive"))
            y = y + 1
            monitor.setCursorPos(3, y)
            monitor.write("Temp: " .. reactorData.temp)
            y = y + 1
            monitor.setCursorPos(3, y)
            monitor.write("EU Output: " .. reactorData.euOutput)
            y = y + 1
            y = y + 1  -- Extra space between reactors
        end
    end

    -- Navigation buttons
    local buttonWidth = 8
    local buttonHeight = 3
    local buttonY = h - buttonHeight + 1
    local prevButtonX = 2
    local nextButtonX = w - buttonWidth - 2

    -- Previous Page Button
    if pageNum > 1 then
        monitor.setBackgroundColor(colors.blue)
        monitor.setTextColor(colors.white)
        for i = 0, buttonHeight - 1 do
            monitor.setCursorPos(prevButtonX, buttonY + i)
            monitor.write(string.rep(" ", buttonWidth))
        end
        local prevButtonText = "Prev"
        local prevLabelX = prevButtonX + math.floor((buttonWidth - #prevButtonText) / 2)
        local prevLabelY = buttonY + math.floor(buttonHeight / 2)
        monitor.setCursorPos(prevLabelX, prevLabelY)
        monitor.write(prevButtonText)
        monitor.setBackgroundColor(bgColor)

        ui.addButton("prev_page", prevButtonX, buttonY, buttonWidth, buttonHeight)
    end

    -- Next Page Button
    if pageNum < numReactorPages then
        monitor.setBackgroundColor(colors.blue)
        monitor.setTextColor(colors.white)
        for i = 0, buttonHeight - 1 do
            monitor.setCursorPos(nextButtonX, buttonY + i)
            monitor.write(string.rep(" ", buttonWidth))
        end
        local nextButtonText = "Next"
        local nextLabelX = nextButtonX + math.floor((buttonWidth - #nextButtonText) / 2)
        local nextLabelY = buttonY + math.floor(buttonHeight / 2)
        monitor.setCursorPos(nextLabelX, nextLabelY)
        monitor.write(nextButtonText)
        monitor.setBackgroundColor(bgColor)

        ui.addButton("next_page", nextButtonX, buttonY, buttonWidth, buttonHeight)
    end

    -- Home Button
    local homeButtonWidth = 8
    local homeButtonHeight = 3
    local homeButtonX = (w - homeButtonWidth) // 2
    local homeButtonY = h - homeButtonHeight + 1

    monitor.setBackgroundColor(colors.blue)
    monitor.setTextColor(colors.white)
    for i = 0, homeButtonHeight - 1 do
        monitor.setCursorPos(homeButtonX, homeButtonY + i)
        monitor.write(string.rep(" ", homeButtonWidth))
    end
    local homeButtonText = "Home"
    local homeLabelX = homeButtonX + math.floor((homeButtonWidth - #homeButtonText) / 2)
    local homeLabelY = homeButtonY + math.floor(homeButtonHeight / 2)
    monitor.setCursorPos(homeLabelX, homeLabelY)
    monitor.write(homeButtonText)
    monitor.setBackgroundColor(bgColor)

    ui.addButton("home", homeButtonX, homeButtonY, homeButtonWidth, homeButtonHeight)
end

-- Return the ui module
return ui
