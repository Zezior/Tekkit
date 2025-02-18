-- Reactor Mainframe ui.lua

local monitor = peripheral.wrap("right")
local style = require("style")
monitor.setTextScale(style.style.textScale)

-- Definitions for PESU paging
local pesusPerColumn = 25
local columnsPerPage = 3

local repo = nil
local reactorIDs = {}  -- Sorted list of reactor IDs (numbers)
local reactors = {}
local pages = {}         -- Will store page info; pages.numReactorPages is used
local reactorOutputLog = {}
local w, h = monitor.getSize()
local buttonList = {}

-- Stub for sendReactorStatus (for logging)
local function sendReactorStatus(status)
    print("sendReactorStatus called with status: " .. status)
end

local function formatPercentage(value)
    return string.format("%.2f%%", value)
end

local function setColorBasedOnPercentage(percentage)
    if percentage >= 100 then
        monitor.setTextColor(colors.blue)
    elseif percentage >= 80 then
        monitor.setTextColor(colors.green)
    elseif percentage >= 50 then
        monitor.setTextColor(colors.yellow)
    elseif percentage >= 20 then
        monitor.setTextColor(colors.orange)
    else
        monitor.setTextColor(colors.red)
    end
end

local function resetButtons()
    buttonList = {}
end

local Button = {}
Button.__index = Button

function Button:new(reactorID, x, y, width, height, text, color, action)
    local button = setmetatable({}, Button)
    button.reactorID = reactorID  -- Number (reactor ID) or nil for navigation buttons
    button.x = x
    button.y = y
    button.width = width
    button.height = height
    button.text = text
    button.color = color
    button.action = action  -- Navigation or command action
    return button
end

function Button:draw()
    monitor.setBackgroundColor(self.color)
    monitor.setTextColor(colors.white)
    for i = 0, self.height - 1 do
        monitor.setCursorPos(self.x, self.y + i)
        monitor.write(string.rep(" ", self.width))
    end
    monitor.setCursorPos(self.x + math.floor((self.width - #self.text) / 2), self.y + math.floor(self.height / 2))
    monitor.write(self.text)
    monitor.setBackgroundColor(style.style.backgroundColor)
end

function Button:handlePress()
    if self.reactorID then
        local id = self.reactorID  -- id is a number
        local currentState = repo.get(id .. "_state")
        local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
        if reactorData.destroyed then
            print("Cannot control reactor " .. id .. " because it is destroyed.")
            return
        end
        if reactorData.overheating then
            print("Cannot turn on reactor " .. id .. " because it is overheating.")
            return
        end
        if reactorData.isMaintenance then
            print("Reactor " .. id .. " is in maintenance mode.")
        end
        local newState = not currentState
        repo.set(id .. "_state", newState)
        reactors[id].active = newState
        rednet.send(id, {command = newState and "turn_on" or "turn_off"})
        print("Sent command to reactor:", id, "New State:", newState)
        self.text = newState and "Off" or "On"
        self.color = newState and colors.red or colors.green
        self:draw()
    else
        if self.action == "toggle_all" then
            manualOverride = true
            local anyReactorOff = false
            for _, id in ipairs(reactorIDs) do
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not reactorData.active then
                        anyReactorOff = true
                        break
                    end
                end
            end
            local reactorsChanged = false
            for _, id in ipairs(reactorIDs) do
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    repo.set(id .. "_state", anyReactorOff)
                    reactors[id].active = anyReactorOff
                    if anyReactorOff then
                        rednet.send(id, {command = "turn_on"})
                    else
                        rednet.send(id, {command = "turn_off"})
                    end
                    reactorsChanged = true
                end
            end
            self.text = anyReactorOff and "All Off" or "All On"
            self.color = anyReactorOff and colors.red or colors.green
            self:draw()
            displayHomePage(repo, reactorTable, reactors, pages.numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        elseif self.action == "reset" then
            manualOverride = false
            local reactorsChanged = false
            if not reactorsOnDueToPESU or not anyPlayerOnline then
                for _, id in ipairs(reactorIDs) do
                    local state = repo.get(id .. "_state")
                    if state then
                        repo.set(id .. "_state", false)
                        reactors[id].active = false
                        rednet.send(id, {command = "turn_off"})
                        reactorsChanged = true
                    end
                end
                if reactorsChanged then
                    sendReactorStatus("off")
                end
            else
                for _, id in ipairs(reactorIDs) do
                    local state = repo.get(id .. "_state")
                    local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                    if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                        if not state then
                            repo.set(id .. "_state", true)
                            reactors[id].active = true
                            rednet.send(id, {command = "turn_on"})
                            reactorsChanged = true
                        end
                    end
                end
                if reactorsChanged then
                    sendReactorStatus("on")
                end
            end
            displayHomePage(repo, reactorTable, reactors, pages.numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        else
            return self.action
        end
    end
end

function bindReactorButtons(reactorTable, passedRepo)
    reactorIDs = {}  -- Build sorted list of reactor IDs (numbers)
    for id, data in pairs(reactorTable) do
        table.insert(reactorIDs, id)
    end
    table.sort(reactorIDs)
    repo = passedRepo
    for _, id in ipairs(reactorIDs) do
        repo.bind(id .. "_state", function(newState)
            for _, button in pairs(buttonList) do
                if button.reactorID == id then
                    button.text = newState and "Off" or "On"
                    button.color = newState and colors.red or colors.green
                    button:draw()
                end
            end
        end)
    end
end

function detectButtonPress(x, y)
    for _, button in ipairs(buttonList) do
        if x >= button.x and x < button.x + button.width and y >= button.y and y < button.y + button.height then
            return button:handlePress()
        end
    end
    return nil
end

local function centerButtons(page, numReactorPages)
    local buttonWidth = 10
    local buttonHeight = 3
    local spacing = 2
    local totalButtons = 1 + numReactorPages
    local buttonsTotalWidth = totalButtons * buttonWidth + (totalButtons - 1) * spacing
    local xStart = math.floor((w - buttonsTotalWidth) / 2) + 1
    local x = xStart

    local homeButton = Button:new(nil, x, h - buttonHeight + 1, buttonWidth, buttonHeight, "Home", page == "home" and colors.green or colors.blue, "home")
    homeButton:draw()
    table.insert(buttonList, homeButton)
    x = x + buttonWidth + spacing

    for i = 1, numReactorPages do
        local pageName = "Reactors " .. i
        local action = "reactor" .. i
        local buttonColor = page == action and colors.green or colors.blue
        local reactorButton = Button:new(nil, x, h - buttonHeight + 1, buttonWidth, buttonHeight, pageName, buttonColor, action)
        reactorButton:draw()
        table.insert(buttonList, reactorButton)
        x = x + buttonWidth + spacing
    end
end

function addReactorControlButtons(reactorID, status, x, y, data, buttonWidth)
    buttonWidth = buttonWidth or 5
    local buttonText = status and "Off" or "On"
    local buttonColor = status and colors.red or colors.green
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
    local button = Button:new(reactorID, x, y, buttonWidth, 2, buttonText, buttonColor)
    table.insert(buttonList, button)
    button:draw()
end

function displayReactorData(reactorsPassed, pageNum, numReactorPages, reactorIDsPassed)
    resetButtons()
    reactors = reactorsPassed
    reactorIDs = reactorIDsPassed
    pages.numReactorPages = numReactorPages
    style.applyStyle()
    monitor.clear()
    local header = "Reactor Status Page " .. pageNum
    local xHeader = math.floor((w - #header) / 2) + 1
    monitor.setCursorPos(xHeader, 1)
    monitor.setTextColor(colors.green)
    monitor.write(header)
    monitor.setTextColor(style.style.textColor)
    local reactorsPerPage = 10
    local startIdx = (pageNum - 1) * reactorsPerPage + 1
    local endIdx = math.min(startIdx + reactorsPerPage - 1, #reactorIDs)
    local reactorsPerColumn = 5
    local columns = 2
    local columnWidth = math.floor(w / columns)
    for idx = startIdx, endIdx do
        local id = reactorIDs[idx]
        local reactorData = reactors[id]
        if reactorData then
            local reactorIndexOnPage = idx - startIdx
            local column = math.floor(reactorIndexOnPage / reactorsPerColumn) + 1
            local row = (reactorIndexOnPage % reactorsPerColumn) + 1
            local x = (column - 1) * columnWidth + 2
            local y = 3 + (row - 1) * 6
            local buttonX = x
            local buttonY = y
            addReactorControlButtons(id, reactorData.active, buttonX, buttonY, reactorData, 6)
            monitor.setCursorPos(x + 6, y)
            monitor.write(reactorData.reactorName)
            monitor.setCursorPos(x + 6, y + 1)
            if reactorData.active then
                monitor.setTextColor(colors.green)
                monitor.write("Status: On")
            else
                monitor.setTextColor(colors.red)
                monitor.write("Status: Off")
            end
            monitor.setTextColor(style.style.textColor)
            monitor.setCursorPos(x + 6, y + 2)
            monitor.write("Temp: " .. reactorData.temp)
            monitor.setCursorPos(x + 6, y + 3)
            monitor.write("EU Output: " .. reactorData.euOutput)
        end
    end
    centerButtons("reactor" .. pageNum, pages.numReactorPages)
end

function displayReactorLists()
    local yStart = 3
    local thirdWidth = math.floor(w / 3)
    local overheatingWidth = 20
    local xOverheating = math.floor((thirdWidth - overheatingWidth) / 2) + 1
    local maintenanceWidth = 20
    local xMaintenance = thirdWidth + math.floor((thirdWidth - maintenanceWidth) / 2) + 1
    local destroyedWidth = 20
    local xDestroyed = 2 * thirdWidth + math.floor((thirdWidth - destroyedWidth) / 2) + 1
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

function formatEUOutput(value)
    if value >= 1000000 then
        return string.format("%.2f M EU/t", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.0f k EU/t", value / 1000)
    else
        return string.format("%.0f EU/t", value)
    end
end

function computeOutputs()
    local totalReactorOutput = 0
    for id, data in pairs(reactorOutputLog) do
        if data.maxOutput then
            totalReactorOutput = totalReactorOutput + data.maxOutput
        end
    end
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
