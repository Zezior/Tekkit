-- Reactor Mainframe main.lua

-- Import required modules
local ui = require("ui")
local ids = require("ids")

-- Get IDs from ids.lua
local activityCheckID = ids.activityCheckID
local powerMainframeID = ids.powerMainframeID
local reactorMainframeID = ids.reactorMainframeID
local reactorIDsFromFile = ids.reactorIDs  -- Assuming reactor IDs are listed here

-- Initialize variables
local currentPage = "home"  -- Start on the home page
local reactors = {}  -- Table to store reactor data
local reactorOutputLog = {}  -- Table to store reactor output data
local reactorTable = {}  -- Table to store reactor information
local pages = {}  -- Pages for UI navigation
local numReactorPages = 0  -- Number of reactor pages

-- Initialize the repo for managing reactor states
local repo = {
    data = {},
    bindings = {}
}

-- Function to bind state changes
function repo.bind(key, callback)
    if not repo.bindings[key] then
        repo.bindings[key] = {}
    end
    table.insert(repo.bindings[key], callback)
end

-- Function to get the current state
function repo.get(key)
    return repo.data[key]
end

-- Function to set a new state and trigger bound callbacks
function repo.set(key, value)
    if repo.data[key] ~= value then
        repo.data[key] = value
        if repo.bindings[key] then
            for _, callback in ipairs(repo.bindings[key]) do
                callback(value)
            end
        end
    end
end

-- Ensure Rednet is open on the mainframe
rednet.open("back")  -- Adjust the side as needed for the modem

-- Function to load reactor output log from file
local function loadReactorOutputLog()
    if fs.exists("Reactor_log.txt") then
        local file = fs.open("Reactor_log.txt", "r")
        if file then
            local content = file.readAll()
            file.close()
            local data = textutils.unserialize(content)
            if data then
                reactorOutputLog = data
            else
                reactorOutputLog = {}
            end
        end
    else
        reactorOutputLog = {}
    end
end

-- Function to save reactor output log to file
local function saveReactorOutputLog()
    local file = fs.open("Reactor_log.txt", "w")
    if file then
        file.write(textutils.serialize(reactorOutputLog))
        file.close()
    end
end

-- Function to load the last power command from file
local function loadLastPowerCommand()
    if fs.exists("power_log.txt") then
        local file = fs.open("power_log.txt", "r")
        if file then
            local lastCommand = file.readAll()
            file.close()
            if lastCommand == "turn_on_reactors" or lastCommand == "turn_off_reactors" then
                return lastCommand
            end
        end
    end
    return nil
end

-- Function to save the last power command to file
local function saveLastPowerCommand(command)
    local file = fs.open("power_log.txt", "w")
    if file then
        file.write(command)
        file.close()
    end
end

-- Function to request data from all reactors on startup
local function requestReactorData()
    for _, reactorID in ipairs(reactorIDs) do
        rednet.send(reactorID, {command = "send_data"})
    end
end

-- Function to check if senderID is in the reactor IDs list
local function isReactorID(senderID)
    for _, reactorID in ipairs(reactorIDs) do
        if reactorID == senderID then
            return true
        end
    end
    return false
end

local reactorsOnDueToPESU = false  -- Track if reactors are turned on due to PESU levels
local anyPlayerOnline = false  -- Track player online status
local manualOverride = false  -- Track if manual override is active

-- Function to send reactor status to power mainframe
local function sendReactorStatus(status)
    rednet.send(powerMainframeID, {command = "reactor_status", status = status}, "reactor_control")
    print("Sent reactor status to power mainframe:", status)
end

-- Function to calculate total EU/t output from all reactors
local function calculateTotalReactorOutput()
    local totalOutput = 0
    for _, reactorID in ipairs(reactorIDs) do
        local reactorData = reactors[reactorID]
        if reactorData and not reactorData.destroyed then
            local euOutputNum = tonumber(reactorData.euOutput)
            if euOutputNum then
                totalOutput = totalOutput + euOutputNum
            end
        end
    end
    return totalOutput
end

-- Function to handle messages from the activity check computer
local function handleActivityCheckMessage(message)
    print("Received message from activity check computer:", textutils.serialize(message))
    if message.command == "player_online" then
        print("Received player_online command from activity check computer.")
        anyPlayerOnline = true

        if reactorsOnDueToPESU and not manualOverride then
            local reactorsTurnedOn = false
            for _, id in ipairs(reactorIDs) do
                local state = repo.get(id .. "_state")
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not state then
                        repo.set(id .. "_state", true)
                        reactors[id].active = true
                        rednet.send(id, {command = "turn_on"})
                        reactorsTurnedOn = true
                    end
                end
            end
            if reactorsTurnedOn then
                sendReactorStatus("on")
                sleep(10)
                local totalEUOutput = calculateTotalReactorOutput()
                rednet.send(powerMainframeID, {command = "total_eu_output", totalEUOutput = totalEUOutput}, "reactor_output")
                print("Sent total EU/t output to Power Mainframe:", totalEUOutput)
            end
        else
            print("Reactors are not turned on due to PESU levels or manual override.")
        end

        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        end
    elseif message.command == "player_offline" then
        print("Received player_offline command from activity check computer.")
        anyPlayerOnline = false
        if not manualOverride then
            local reactorsTurnedOff = false
            for _, id in ipairs(reactorIDs) do
                local state = repo.get(id .. "_state")
                if state then
                    repo.set(id .. "_state", false)
                    reactors[id].active = false
                    rednet.send(id, {command = "turn_off"})
                    reactorsTurnedOff = true
                end
            end
            if reactorsTurnedOff then
                sendReactorStatus("off")
            end
        else
            print("Manual override active. Reactors remain unchanged.")
        end
        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        end
    elseif message.command == "check_players" then
        rednet.send(activityCheckID, {playersOnline = anyPlayerOnline}, "player_status")
    elseif message.playersOnline ~= nil then
        anyPlayerOnline = message.playersOnline
        print("Received player status from activity check computer. Players online:", anyPlayerOnline)
        if anyPlayerOnline and reactorsOnDueToPESU and not manualOverride then
            local reactorsTurnedOn = false
            for _, id in ipairs(reactorIDs) do
                local state = repo.get(id .. "_state")
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not state then
                        repo.set(id .. "_state", true)
                        reactors[id].active = true
                        rednet.send(id, {command = "turn_on"})
                        reactorsTurnedOn = true
                    end
                end
            end
            if reactorsTurnedOn then
                sendReactorStatus("on")
                sleep(10)
                local totalEUOutput = calculateTotalReactorOutput()
                rednet.send(powerMainframeID, {command = "total_eu_output", totalEUOutput = totalEUOutput}, "reactor_output")
                print("Sent total EU/t output to Power Mainframe:", totalEUOutput)
            end
            if currentPage == "home" then
                ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
            end
        else
            print("Reactors are not turned on due to PESU levels, no players online, or manual override.")
        end
    else
        print("Unknown command from activity check computer:", message.command)
    end
end

-- Function to handle messages from the power mainframe
local function handlePowerMainframeMessage(message)
    if manualOverride then
        print("Manual override active. Ignoring power mainframe commands.")
        return
    end
    if message.command == "turn_on_reactors" then
        print("Received turn_on_reactors command from power mainframe.")
        reactorsOnDueToPESU = true
        saveLastPowerCommand("turn_on_reactors")
        if anyPlayerOnline then
            local reactorsTurnedOn = false
            for _, id in ipairs(reactorIDs) do
                local state = repo.get(id .. "_state")
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not state then
                        repo.set(id .. "_state", true)
                        reactors[id].active = true
                        rednet.send(id, {command = "turn_on"})
                        reactorsTurnedOn = true
                    end
                end
            end
            if reactorsTurnedOn then
                sendReactorStatus("on")
                sleep(10)
                local totalEUOutput = calculateTotalReactorOutput()
                rednet.send(powerMainframeID, {command = "total_eu_output", totalEUOutput = totalEUOutput}, "reactor_output")
                print("Sent total EU/t output to Power Mainframe:", totalEUOutput)
            end
        else
            print("Players are offline. Reactors will turn on when a player comes online.")
        end
    elseif message.command == "turn_off_reactors" then
        print("Received turn_off_reactors command from power mainframe.")
        reactorsOnDueToPESU = false
        saveLastPowerCommand("turn_off_reactors")
        local reactorsTurnedOff = false
        for _, id in ipairs(reactorIDs) do
            local state = repo.get(id .. "_state")
            if state then
                repo.set(id .. "_state", false)
                reactors[id].active = false
                rednet.send(id, {command = "turn_off"})
                reactorsTurnedOff = true
            end
        end
        if reactorsTurnedOff then
            sendReactorStatus("off")
        end
    end

    if currentPage == "home" then
        ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
    end
end

-- Function to switch between pages dynamically
local function switchPage(page)
    if pages[page] then
        currentPage = page
        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        elseif string.sub(currentPage, 1, 7) == "reactor" then
            local pageNumString = string.sub(currentPage, 8)
            local pageNum = tonumber(pageNumString)
            if not pageNum then
                print("Invalid reactor page number:", pageNumString)
                return
            end
            ui.displayReactorData(reactors, pageNum, numReactorPages, reactorIDs)
        end
    else
        print("Page not found: " .. page)
    end
end

-- Function to rebuild reactorTable, reactorIDs, numReactorPages, and pages
local function rebuildReactorDataStructures()
    reactorIDs = {}
    reactorTable = {}
    reactors = {}

    for _, reactorID in ipairs(reactorIDsFromFile) do
        table.insert(reactorIDs, reactorID)
    end

    local seen = {}
    local uniqueReactorIDs = {}
    for _, id in ipairs(reactorIDs) do
        if not seen[id] then
            table.insert(uniqueReactorIDs, id)
            seen[id] = true
        end
    end
    reactorIDs = uniqueReactorIDs

    table.sort(reactorIDs)

    for index, reactorID in ipairs(reactorIDs) do
        local reactorName = reactorOutputLog[reactorID] and reactorOutputLog[reactorID].reactorName or (reactorID == 7559 and "Reactor 1" or "Reactor " .. reactorID)
        reactorTable[reactorID] = {id = reactorID, name = reactorName}
        repo.set(reactorID .. "_state", false)
        reactors[reactorID] = {
            reactorName = reactorName,
            temp = "N/A",
            active = false,
            euOutput = "0",
            fuelRemaining = "N/A",
            isMaintenance = false,
            overheating = false,
            destroyed = false,
            status = "unknown"
        }
    end

    local totalReactors = #reactorIDs
    local reactorsPerPage = 10
    numReactorPages = math.ceil(totalReactors / reactorsPerPage)

    pages = {
        home = "Home Page"
    }

    for i = 1, numReactorPages do
        pages["reactor" .. i] = "Reactor Status Page " .. i
    end
end

-- Main function for receiving reactor data and handling button presses
local function main()
    loadReactorOutputLog()
    rebuildReactorDataStructures()

    local lastPowerCommand = loadLastPowerCommand()
    if lastPowerCommand == "turn_on_reactors" then
        reactorsOnDueToPESU = true
        rednet.send(activityCheckID, {command = "check_players"}, "player_status")
    elseif lastPowerCommand == "turn_off_reactors" then
        reactorsOnDueToPESU = false
        local reactorsTurnedOff = false
        for _, id in ipairs(reactorIDs) do
            local state = repo.get(id .. "_state")
            if state then
                repo.set(id .. "_state", false)
                reactors[id].active = false
                rednet.send(id, {command = "turn_off"})
                reactorsTurnedOff = true
            end
        end
        if reactorsTurnedOff then
            sendReactorStatus("off")
        end
    end

    ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
    ui.bindReactorButtons(reactorTable, repo)
    requestReactorData()

    parallel.waitForAny(
        function()
            while true do
                local event, side, x, y = os.pullEvent("monitor_touch")
                local action = ui.detectButtonPress(x, y)
                if action then
                    if action == "toggle_all" then
                        manualOverride = true
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
                        self = {}  -- dummy assignment for button object context
                        self.text = anyReactorOff and "All Off" or "All On"
                        self.color = anyReactorOff and colors.red or colors.green
                        ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
                    elseif action == "reset" then
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
                        ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
                    else
                        switchPage(action)
                    end
                end
            end
        end,
        function()
            while true do
                local senderID, message, protocol = rednet.receive()
                if senderID == activityCheckID then
                    handleActivityCheckMessage(message)
                elseif senderID == powerMainframeID then
                    handlePowerMainframeMessage(message)
                elseif isReactorID(senderID) then
                    if type(message) == "table" and message.id then
                        local reactorID = message.id
                        if message.reactorName then
                            reactors[reactorID].reactorName = message.reactorName
                        end
                        reactors[reactorID] = reactors[reactorID] or {}
                        for k, v in pairs(message) do
                            reactors[reactorID][k] = v
                        end
                        if message.status == "Destroyed" then
                            reactors[reactorID].destroyed = true
                            reactors[reactorID].status = "Destroyed"
                            reactors[reactorID].active = false
                            repo.set(reactorID .. "_state", false)
                        else
                            reactors[reactorID].destroyed = false
                            reactors[reactorID].status = message.status or "online"
                            repo.set(reactorID .. "_state", message.active)
                        end
                        if string.find(message.reactorName, "-M") then
                            reactors[reactorID].isMaintenance = true
                        else
                            reactors[reactorID].isMaintenance = false
                        end
                        if not reactors[reactorID].destroyed then
                            local euOutputNum = tonumber(message.euOutput)
                            if euOutputNum and euOutputNum > 1 then
                                if reactorOutputLog[reactorID] then
                                    if euOutputNum > reactorOutputLog[reactorID].maxOutput then
                                        reactorOutputLog[reactorID].maxOutput = euOutputNum
                                        saveReactorOutputLog()
                                    end
                                else
                                    reactorOutputLog[reactorID] = {
                                        reactorName = message.reactorName,
                                        maxOutput = euOutputNum
                                    }
                                    saveReactorOutputLog()
                                end
                            end
                        end
                        local index = 0
                        for idx, id in ipairs(reactorIDs) do
                            if id == reactorID then
                                index = idx
                                break
                            end
                        end
                        local reactorsPerPage = 10
                        local pageNum = math.ceil(index / reactorsPerPage)
                        if currentPage == "reactor" .. pageNum then
                            ui.displayReactorData(reactors, pageNum, numReactorPages, reactorIDs)
                        end
                        if currentPage == "home" then
                            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
                        end
                    else
                        print("Invalid message received from reactor ID:", senderID)
                    end
                else
                    print("Received message from unknown sender ID:", senderID)
                end
            end
        end
    )
end

main()
