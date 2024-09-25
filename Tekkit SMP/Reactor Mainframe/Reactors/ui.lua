-- ui.lua

local monitor = peripheral.wrap("right")  -- Adjust as necessary
local style = require("style")
monitor.setTextScale(style.style.textScale)
local repo = nil  -- This will be assigned the passed repo object from main.lua
local reactorIDs = {}  -- Initialize the reactorIDs table
local reactors = {}
local pages = {}
local reactorOutputLog = {}
local w, h = monitor.getSize()

-- Button logic
local buttonList = {}

-- Function to reset the button list
local function resetButtons()
    buttonList = {}
end

-- Button class definition to ensure we can create button objects
local Button = {}
Button.__index = Button

function Button:new(reactorID, x, y, width, height, text, color, action)
    local button = setmetatable({}, Button)
    button.reactorID = reactorID  -- Store the reactor ID this button controls
    button.x = x
    button.y = y
    button.width = width
    button.height = height
    button.text = text
    button.color = color
    button.action = action  -- Action string for navigation or reactor buttons
    return button
end

-- Function to draw the button on the monitor
function Button:draw()
    monitor.setBackgroundColor(self.color)
    monitor.setTextColor(colors.white)
    for i = 0, self.height - 1 do
        monitor.setCursorPos(self.x, self.y + i)
        monitor.write(string.rep(" ", self.width))  -- Clear the button area
    end
    monitor.setCursorPos(self.x + math.floor((self.width - #self.text) / 2), self.y + math.floor(self.height / 2))
    monitor.write(self.text)
    monitor.setBackgroundColor(style.style.backgroundColor)  -- Reset background after button
end

-- Function to handle button presses
function Button:handlePress()
    if self.reactorID then
        -- Reactor control button
        local id = self.reactorID
        local currentState = repo.get(id .. "_state")
        local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }

        -- Check if reactor is destroyed
        if reactorData.destroyed then
            print("Cannot control reactor " .. id .. " because it is destroyed.")
            return
        end

        -- Check if reactor is overheating or in maintenance mode
        if reactorData.overheating then
            print("Cannot turn on reactor " .. id .. " because it is overheating.")
            return
        end
        if reactorData.isMaintenance then
            print("Reactor " .. id .. " is in maintenance mode.")
            -- Allow individual control even in maintenance mode
        end

        -- Toggle the reactor state
        local newState = not currentState
        repo.set(id .. "_state", newState)  -- Update the state locally

        -- Send the turn_on/turn_off command via Rednet to the correct reactor ID
        rednet.send(self.reactorID, {command = newState and "turn_on" or "turn_off"})
        print("Sent command to reactor:", self.reactorID, "New State:", newState)

        -- Update the button's appearance immediately based on the new state
        self.text = newState and "Off" or "On"
        self.color = newState and colors.red or colors.green
        self:draw()  -- Redraw the button with the updated state
    else
        -- Navigation or other action button
        if self.action == "toggle_all" then
            manualOverride = true  -- Activate manual override
            local anyReactorOff = false
            for _, reactorData in pairs(reactors) do
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not reactorData.active then
                        anyReactorOff = true
                        break
                    end
                end
            end
            local reactorsChanged = false
            for _, reactor in pairs(reactorIDs) do
                local id = reactor.id
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    repo.set(id .. "_state", anyReactorOff)
                    if anyReactorOff then
                        rednet.send(id, {command = "turn_on"})
                    else
                        rednet.send(id, {command = "turn_off"})
                    end
                    reactorsChanged = true
                end
            end
            -- Update the button's appearance
            self.text = anyReactorOff and "All Off" or "All On"
            self.color = anyReactorOff and colors.red or colors.green
            self:draw()
            -- Update display
            displayHomePage(repo, reactorIDs, reactors, pages.numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        elseif self.action == "reset" then
            manualOverride = false  -- Deactivate manual override
            -- Restore reactors to automated control
            local reactorsChanged = false
            if not reactorsOnDueToPESU or not anyPlayerOnline then
                -- Turn off reactors
                for _, reactor in pairs(reactorIDs) do
                    local id = reactor.id
                    local state = repo.get(id .. "_state")
                    if state then
                        repo.set(id .. "_state", false)
                        rednet.send(id, {command = "turn_off"})
                        reactorsChanged = true
                    end
                end
            else
                -- Turn on reactors
                for _, reactor in pairs(reactorIDs) do
                    local id = reactor.id
                    local state = repo.get(id .. "_state")
                    local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                    if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                        if not state then
                            repo.set(id .. "_state", true)
                            rednet.send(id, {command = "turn_on"})
                            reactorsChanged = true
                        end
                    end
                end
            end
            -- Update display
            displayHomePage(repo, reactorIDs, reactors, pages.numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        else
            -- Navigation button action
            return self.action
        end
    end
end

-- Function to bind the reactor state to button updates
function bindReactorButtons(reactorTable, passedRepo)
    reactorIDs = reactorTable -- Assign the reactorIDs table passed from main.lua
    repo = passedRepo  -- Assign the passed repo object

    -- Bind the reactor state to the button display update
    for reactorName, reactorData in pairs(reactorIDs) do
        local reactorID = reactorData.id
        repo.bind(reactorID .. "_state", function(newState)
            -- Update the button text and color based on the new state
            for _, button in pairs(buttonList) do
                if button.reactorID == reactorID then
                    button.text = newState and "Off" or "On"
                    button.color = newState and colors.red or colors.green
                    button:draw()  -- Redraw the button with updated appearance
                end
            end
        end)
    end
end

-- Function to detect button presses
function detectButtonPress(x, y)
    for _, button in ipairs(buttonList) do
        if x >= button.x and x < button.x + button.width and y >= button.y and y < button.y + button.height then
            return button:handlePress()  -- Return the action string
        end
    end
    return nil
end

-- Function to create the navigation buttons at the bottom
local function centerButtons(page, numReactorPages)
    local buttonWidth = 10
    local buttonHeight = 3
    local totalButtons = 1 + numReactorPages  -- Home + reactor pages
    local x = 2  -- Start from the left edge with some padding

    -- Define the Home button
    local homeButton = Button:new(nil, x, h - buttonHeight + 1, buttonWidth, buttonHeight, "Home", page == "home" and colors.green or colors.blue, "home")
    homeButton:draw()
    table.insert(buttonList, homeButton)
    x = x + buttonWidth + 2

    -- Define Reactor page buttons
    for i = 1, numReactorPages do
        local pageName = "Reactors " .. i
        local action = "reactor" .. i
        local buttonColor = page == action and colors.green or colors.blue
        local reactorButton = Button:new(nil, x, h - buttonHeight + 1, buttonWidth, buttonHeight, pageName, buttonColor, action)
        reactorButton:draw()
        table.insert(buttonList, reactorButton)
        x = x + buttonWidth + 2
    end
end

-- Function to add reactor control buttons dynamically based on reactor status
function addReactorControlButtons(reactorID, status, x, y, data, buttonWidth)
    buttonWidth = buttonWidth or 5  -- Adjusted button width
    local buttonText = status and "Off" or "On"
    local buttonColor = status and colors.red or colors.green

    -- Adjust button if reactor is destroyed
    if data.destroyed then
        buttonText = "X"
        buttonColor = colors.black
    elseif data.overheating then
        buttonText = "OH"
        buttonColor = colors.gray
    elseif data.isMaintenance then
        buttonText = "M"
        buttonColor = colors.orange
    end

    -- Create a new button object for this reactor
    local button = Button:new(reactorID, x, y, buttonWidth, 2, buttonText, buttonColor)

    -- Add the button to the list of buttons
    table.insert(buttonList, button)

    -- Draw the button on the monitor
    button:draw()
end

-- Function to display reactor data on reactor pages
function displayReactorData(reactorsPassed, pageNum, numReactorPages, reactorIDsPassed)
    resetButtons()
    reactors = reactorsPassed
    reactorIDs = reactorIDsPassed
    pages.numReactorPages = numReactorPages
    style.applyStyle()
    monitor.clear()
    -- Center and color the header
    local header = "Reactor Status Page " .. pageNum
    local xHeader = math.floor((w - #header) / 2) + 1
    monitor.setCursorPos(xHeader, 1)
    monitor.setTextColor(colors.green)
    monitor.write(header)
    monitor.setTextColor(style.style.textColor)

    -- Display reactors per page
    local reactorsPerPage = 10  -- 5 reactors per column, 2 columns
    local startIdx = (pageNum - 1) * reactorsPerPage + 1
    local endIdx = math.min(startIdx + reactorsPerPage -1, #reactorIDs)

    local reactorsPerColumn = 5
    local columns = 2
    local columnWidth = math.floor(w / columns)

    for idx = startIdx, endIdx do
        local reactorID = reactorIDs[idx]
        local reactorData = reactors[reactorID]
        if reactorData then
            -- Determine column and row
            local reactorIndexOnPage = idx - startIdx
            local column = math.floor(reactorIndexOnPage / reactorsPerColumn) + 1
            local row = (reactorIndexOnPage % reactorsPerColumn) + 1

            local x = (column - 1) * columnWidth + 2  -- Adjust 2 for padding
            local y = 3 + (row - 1) * 6  -- Adjust vertical spacing

            -- Add reactor control button to the left
            local buttonX = x
            local buttonY = y
            addReactorControlButtons(reactorID, reactorData.active, buttonX, buttonY, reactorData)

            -- Display reactor info
            monitor.setCursorPos(x + 6, y)
            monitor.write("Reactor " .. idx .. ": " .. reactorData.reactorName)
            monitor.setCursorPos(x + 6, y +1)
            monitor.write("Status: " .. (reactorData.active and "Active" or "Inactive"))
            monitor.setCursorPos(x + 6, y +2)
            monitor.write("Temp: " .. reactorData.temp)
            monitor.setCursorPos(x + 6, y +3)
            monitor.write("EU Output: " .. reactorData.euOutput)
        end
    end

    -- Call the centerButtons function to display navigation buttons
    centerButtons("reactor" .. pageNum, pages.numReactorPages)
end

-- Function to display the home page
function displayHomePage(repoPassed, reactorTablePassed, reactorsPassed, numReactorPagesPassed, reactorOutputLogPassed, reactorsOnDueToPESUPassed, manualOverridePassed)
    resetButtons()
    repo = repoPassed
    reactorIDs = reactorTablePassed
    reactors = reactorsPassed
    pages.numReactorPages = numReactorPagesPassed
    reactorOutputLog = reactorOutputLogPassed
    reactorsOnDueToPESU = reactorsOnDueToPESUPassed
    manualOverride = manualOverridePassed
    style.applyStyle()
    monitor.clear()
    -- Center and color the header
    local header = "NuclearCity - Reactor Main Frame"
    local xHeader = math.floor((w - #header) / 2) + 1
    monitor.setCursorPos(xHeader, 1)
    monitor.setTextColor(colors.green)
    monitor.write(header)

    -- Display overheating, maintenance, and destroyed reactors lists
    displayReactorLists()

    -- Compute total operational reactors and active reactors
    local totalOperationalReactors = 0
    local activeReactors = 0

    for _, reactor in pairs(reactors) do
        if not reactor.isMaintenance and not reactor.destroyed then
            totalOperationalReactors = totalOperationalReactors + 1
            if reactor.active then
                activeReactors = activeReactors + 1
            end
        end
    end

    -- Calculate the fill percentage for the progress bar
    local fillPercentage = 0
    if totalOperationalReactors > 0 then
        fillPercentage = (activeReactors / totalOperationalReactors) * 100
    end

    -- Compute total reactor output
    local totalReactorOutput, currentReactorOutput = computeOutputs()

    -- Positions
    local progressBarY = h - 7  -- Adjust as needed
    local currentOutputY = progressBarY - 2
    local totalOutputY = currentOutputY - 1

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

    -- Center the status text
    local xStatus = math.floor((w - #statusText) / 2) + 1
    monitor.setCursorPos(xStatus, totalOutputY - 1)
    monitor.write(statusText)
    monitor.setTextColor(style.style.textColor)

    -- Display "Total Reactor Output:"
    monitor.setCursorPos(1, totalOutputY)
    monitor.clearLine()
    local totalOutputText = "Total Reactor Output: " .. formatEUOutput(totalReactorOutput)
    monitor.setCursorPos(1, totalOutputY)
    monitor.write(totalOutputText)

    -- Display "Current Reactor Output:"
    monitor.setCursorPos(1, currentOutputY)
    monitor.clearLine()
    local currentOutputText = "Current Reactor Output: " .. formatEUOutput(currentReactorOutput)
    monitor.setCursorPos(1, currentOutputY)
    monitor.write(currentOutputText)

    -- Add "All On/Off" and "Reset" buttons on the far left
    local buttonY = totalOutputY
    local buttonWidth = 8
    local buttonHeight = 2
    local buttonX = w - buttonWidth - 2  -- Place on the far right

    -- Determine button text and color
    local anyReactorOff = false
    for _, reactorData in pairs(reactors) do
        if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
            if not reactorData.active then
                anyReactorOff = true
                break
            end
        end
    end
    local masterButtonText = anyReactorOff and "All On" or "All Off"
    local masterButtonColor = anyReactorOff and colors.green or colors.red

    -- Create "All On/Off" button
    local masterButton = Button:new(nil, 2, buttonY, buttonWidth, buttonHeight, masterButtonText, masterButtonColor, "toggle_all")
    masterButton:draw()
    table.insert(buttonList, masterButton)

    -- Create "Reset" button next to it
    local resetButton = Button:new(nil, 2, buttonY + buttonHeight + 1, buttonWidth, buttonHeight, "Reset", colors.orange, "reset")
    resetButton:draw()
    table.insert(buttonList, resetButton)

    -- Indicate if manual override is active
    if manualOverride then
        monitor.setCursorPos(2, buttonY - 1)
        monitor.setTextColor(colors.orange)
        monitor.write("Manual Override Active")
        monitor.setTextColor(style.style.textColor)
    end

    -- Draw progress bar
    local progressBarWidth = w - 4  -- Leave some padding on sides
    local filledBars = math.floor((fillPercentage / 100) * (progressBarWidth - 2))  -- Adjust for border
    local emptyBars = (progressBarWidth - 2) - filledBars

    -- Draw progress bar border
    monitor.setCursorPos(3, progressBarY)
    monitor.setBackgroundColor(colors.black)
    monitor.write(string.rep(" ", progressBarWidth))  -- Top border

    monitor.setCursorPos(3, progressBarY + 1)
    monitor.write(" ")  -- Left border
    monitor.setCursorPos(2 + progressBarWidth, progressBarY + 1)
    monitor.write(" ")  -- Right border

    monitor.setCursorPos(3, progressBarY + 2)
    monitor.write(string.rep(" ", progressBarWidth))  -- Bottom border

    -- Draw filled portion
    -- Set color based on percentage
    if fillPercentage >= 100 then
        monitor.setTextColor(colors.blue)
    elseif fillPercentage >= 80 then
        monitor.setTextColor(colors.green)
    elseif fillPercentage >= 50 then
        monitor.setTextColor(colors.yellow)
    elseif fillPercentage >= 20 then
        monitor.setTextColor(colors.orange)
    else
        monitor.setTextColor(colors.red)
    end
    monitor.setBackgroundColor(colors.black)
    monitor.setCursorPos(4, progressBarY + 1)
    monitor.write(string.rep(" ", progressBarWidth - 2))  -- Clear inside

    monitor.setBackgroundColor(monitor.getTextColor())
    monitor.setCursorPos(4, progressBarY + 1)
    monitor.write(string.rep(" ", filledBars))

    -- Write percentage over the progress bar
    monitor.setBackgroundColor(colors.black)  -- Set background to black for percentage text
    monitor.setTextColor(colors.white)
    local percentageText = string.format("%.2f%%", fillPercentage)
    local percentageX = math.floor((w - #percentageText) / 2) + 1
    monitor.setCursorPos(percentageX, progressBarY + 1)
    monitor.write(percentageText)

    -- Reset colors
    monitor.setBackgroundColor(style.style.backgroundColor)
    monitor.setTextColor(style.style.textColor)

    -- Call the centerButtons function to display buttons at the bottom
    centerButtons("home", pages.numReactorPages)
end

-- Function to display reactor lists on the home page
function displayReactorLists()
    -- Lists start from line 3
    local yStart = 3
    local thirdWidth = math.floor(w / 3)

    -- Calculate starting positions for the lists
    local overheatingWidth = 20  -- Adjust the width as needed
    local xOverheating = math.floor((thirdWidth - overheatingWidth) / 2) + 1

    local maintenanceWidth = 20  -- Adjust the width as needed
    local xMaintenance = thirdWidth + math.floor((thirdWidth - maintenanceWidth) / 2) + 1

    local destroyedWidth = 20  -- Adjust the width as needed
    local xDestroyed = 2 * thirdWidth + math.floor((thirdWidth - destroyedWidth) / 2) + 1

    -- Display Overheating Reactors
    monitor.setCursorPos(xOverheating, yStart)
    monitor.setTextColor(colors.yellow)
    monitor.write("Overheating Reactors")
    local y = yStart + 1
    for id, reactor in pairs(reactors) do
        if reactor.overheating then
            monitor.setCursorPos(xOverheating, y)
            monitor.setTextColor(style.style.textColor)
            monitor.write(reactor.reactorName .. " - " .. reactor.temp .. "C")
            y = y + 1
        end
    end

    -- Display Reactor Maintenance
    monitor.setCursorPos(xMaintenance, yStart)
    monitor.setTextColor(colors.blue)
    monitor.write("Reactor Maintenance")
    y = yStart + 1
    for id, reactor in pairs(reactors) do
        if reactor.isMaintenance then
            monitor.setCursorPos(xMaintenance, y)
            monitor.setTextColor(style.style.textColor)
            monitor.write(reactor.reactorName)
            y = y + 1
        end
    end

    -- Display Destroyed Reactors
    monitor.setCursorPos(xDestroyed, yStart)
    monitor.setTextColor(colors.red)
    monitor.write("Destroyed Reactors")
    y = yStart + 1
    for id, reactor in pairs(reactors) do
        if reactor.destroyed then
            monitor.setCursorPos(xDestroyed, y)
            monitor.setTextColor(style.style.textColor)
            monitor.write(reactor.reactorName)
            y = y + 1
        end
    end
end

-- Function to format EU output
function formatEUOutput(value)
    if value >= 1000000 then
        return string.format("%.2f M EU/t", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.0f k EU/t", value / 1000)
    else
        return string.format("%.0f EU/t", value)
    end
end

-- Function to compute total outputs
function computeOutputs()
    -- Compute total reactor output
    local totalReactorOutput = 0
    for id, data in pairs(reactorOutputLog) do
        totalReactorOutput = totalReactorOutput + data.maxOutput
    end

    -- Compute current reactor output
    local currentReactorOutput = 0
    for id, reactor in pairs(reactors) do
        if reactor.active and not reactor.isMaintenance and not reactor.destroyed then
            local euOutputNum = tonumber(reactor.euOutput)
            if euOutputNum then
                currentReactorOutput = currentReactorOutput + euOutputNum
            end
        end
    end

    return totalReactorOutput, currentReactorOutput
end

return {
    bindReactorButtons = bindReactorButtons,
    detectButtonPress = detectButtonPress,
    addReactorControlButtons = addReactorControlButtons,
    displayHomePage = displayHomePage,
    displayReactorData = displayReactorData,
    centerButtons = centerButtons,
    resetButtons = resetButtons,
    displayReactorLists = displayReactorLists,
    formatEUOutput = formatEUOutput,
    computeOutputs = computeOutputs
}
