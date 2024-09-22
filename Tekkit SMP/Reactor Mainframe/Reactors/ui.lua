-- ui.lua
local monitor = peripheral.wrap("right")
local style = require("style")
monitor.setTextScale(style.style.textScale)
local repo = nil  -- This will be assigned the passed repo object from main.lua
local reactorIDs = {}  -- Initialize the reactorIDs table
local reactors = {}
local pages = {}
local w, h = monitor.getSize()

-- Button logic
local buttonList = {}

-- Function to reset the button list
function resetButtons()
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
        print("Button pressed for reactorID:", self.reactorID)
        local id = self.reactorID
        local currentState = repo.get(id .. "_state")
        local reactorData = reactors[id] or { isMaintenance = false, overheating = false }

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
            -- Toggle all reactors that are not in maintenance mode and not overheating
            local anyReactorOff = false
            for _, reactor in pairs(reactorIDs) do
                local id = reactor.id
                local state = repo.get(id .. "_state")
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false }
                if not state and not reactorData.isMaintenance and not reactorData.overheating then
                    anyReactorOff = true
                    break
                end
            end

            local newState = anyReactorOff  -- If any reactor is off, we turn all on; else, we turn all off
            for _, reactor in pairs(reactorIDs) do
                local id = reactor.id
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false }
                if not reactorData.isMaintenance and not reactorData.overheating then
                    repo.set(id .. "_state", newState)
                    -- Send command to reactor
                    rednet.send(id, {command = newState and "turn_on" or "turn_off"})
                end
            end
            -- Update the master button's appearance
            self.text = newState and "All Off" or "All On"
            self.color = newState and colors.red or colors.green
            self:draw()
        else
            -- Navigation button action
            return self.action
        end
    end
end

-- Function to bind the reactor state to button updates
function bindReactorButtons(reactorTable, passedRepo)
    -- Check if reactorTable and repo are valid tables
    if type(reactorTable) ~= "table" or type(passedRepo) ~= "table" then
        error("Invalid reactorTable or repo passed to bindReactorButtons")
    end

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
    local totalWidth = totalButtons * (buttonWidth + 2)
    local startX = math.floor((w - totalWidth) / 2) + 1

    local buttons = {}
    local x = startX
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
    buttonWidth = buttonWidth or 6  -- Default button width if not provided
    print("Adding button for reactorID:", reactorID, "at position:", x, y)
    local buttonText = status and "Off" or "On"
    local buttonColor = status and colors.red or colors.green

    -- Adjust button if reactor is overheating or in maintenance mode
    if data.overheating then
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

-- Display the reactor lists on the home page
function displayReactorLists()
    -- Lists start from line 3
    local yStart = 3
    local halfWidth = math.floor(w / 2)

    -- Calculate starting positions for the lists
    local overheatingWidth = 20  -- Adjust the width as needed
    local xOverheating = math.floor((halfWidth - overheatingWidth) / 2) + 1

    local maintenanceWidth = 20  -- Adjust the width as needed
    local xMaintenance = halfWidth + math.floor((halfWidth - maintenanceWidth) / 2) + 1

    -- Display Overheating Reactors
    monitor.setCursorPos(xOverheating, yStart)
    monitor.setTextColor(colors.red)
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

    -- Display Maintenance Reactors
    monitor.setCursorPos(xMaintenance, yStart)
    monitor.setTextColor(colors.orange)
    monitor.write("Maintenance Reactors")
    y = yStart + 1
    for id, reactor in pairs(reactors) do
        if reactor.isMaintenance then
            monitor.setCursorPos(xMaintenance, y)
            monitor.setTextColor(style.style.textColor)
            monitor.write(reactor.reactorName)
            y = y + 1
        end
    end
end

-- Display Home Page
function displayHomePage(repoPassed, reactorTablePassed, reactorsPassed, numReactorPagesPassed)
    resetButtons()
    repo = repoPassed
    reactorIDs = reactorTablePassed
    reactors = reactorsPassed
    pages.numReactorPages = numReactorPagesPassed
    style.applyStyle()
    monitor.clear()
    -- Center and color the header
    local header = "NuclearCity - Reactor Main Frame"
    local xHeader = math.floor((w - #header) / 2) + 1
    monitor.setCursorPos(xHeader, 1)
    monitor.setTextColor(colors.green)
    monitor.write(header)

    -- Determine initial state for the master button
    local anyReactorOff = false
    for _, reactor in pairs(reactorIDs) do
        local id = reactor.id
        local state = repo.get(id .. "_state")
        local reactorData = reactors[id] or { isMaintenance = false, overheating = false }
        if not state and not reactorData.isMaintenance and not reactorData.overheating then
            anyReactorOff = true
            break
        end
    end
    local masterButtonText = anyReactorOff and "All On" or "All Off"
    local masterButtonColor = anyReactorOff and colors.green or colors.red

    -- Add master on/off button in the bottom left corner
    local masterButton = Button:new(nil, 2, h - 7, 8, 3, masterButtonText, masterButtonColor, "toggle_all")
    masterButton:draw()
    table.insert(buttonList, masterButton)

    -- Display overheating and maintenance reactors lists
    displayReactorLists()

    -- Call the centerButtons function to display buttons at the bottom
    centerButtons("home", pages.numReactorPages)
end

return {
    bindReactorButtons = bindReactorButtons,
    detectButtonPress = detectButtonPress,
    addReactorControlButtons = addReactorControlButtons,
    displayHomePage = displayHomePage,
    centerButtons = centerButtons,
    resetButtons = resetButtons
}
