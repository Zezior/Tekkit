-- Reactor Mainframe - main.lua

-- Import required modules
local ui = require("ui")
local ids = require("ids")

-- Get IDs from ids.lua
local activityCheckID = ids.activityCheckID
local powerMainframeID = ids.powerMainframeID
local reactorMainframeID = ids.reactorMainframeID

-- Initialize variables
local currentPage = "home"  -- Start on the home page
local reactors = {}  -- Table to store reactor data
local reactorOutputLog = {}  -- Table to store reactor output data
local reactorIDs = {}  -- List of reactor IDs
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
                callback(value)  -- Trigger the bound function with the new value
            end
        end
    end
end

-- Ensure Rednet is open on the mainframe
rednet.open("top")  -- Adjust the side as needed for the modem

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

-- Function to switch between pages dynamically
local function switchPage(page)
    if pages[page] then
        currentPage = page
        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        elseif string.sub(currentPage, 1, 7) == "reactor" then
            -- Extract page number
            local pageNumString = string.sub(currentPage, 8)
            local pageNum = tonumber(pageNumString)
            if not pageNum then
                print("Invalid reactor page number:", pageNumString)
                return
            end
            ui.displayReactorData(reactors, pageNum, numReactorPages, reactorIDs)
        else
            -- Placeholder for other pages if needed
        end
    else
        print("Page not found: " .. page)
    end
end

-- Function to send reactor status to power mainframe
local function sendReactorStatus(status)
    rednet.send(powerMainframeID, {command = "reactor_status", status = status}, "reactor_control")
    print("Sent reactor status to power mainframe:", status)
end

-- Function to handle messages from the activity check computer
local function handleActivityCheckMessage(message)
    if message.command == "player_online" then
        print("Received player_online command from activity check computer.")
        anyPlayerOnline = true

        -- Only turn on reactors if both conditions are met
        if reactorsOnDueToPESU and not manualOverride then
            local reactorsTurnedOn = false
            for _, reactorID in ipairs(reactorIDs) do
                local id = reactorID
                local state = repo.get(id .. "_state")
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not state then
                        repo.set(id .. "_state", true)
                        rednet.send(id, {command = "turn_on"})
                        reactorsTurnedOn = true
                    end
                end
            end
            if reactorsTurnedOn then
                sendReactorStatus("on")
            end
        else
            print("Reactors are not turned on due to PESU levels or manual override.")
        end

        -- Update the display
        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        end
    elseif message.command == "player_offline" then
        print("Received player_offline command from activity check computer.")
        anyPlayerOnline = false
        -- Turn off all reactors if not in manual override
        if not manualOverride then
            local reactorsTurnedOff = false
            for _, reactorID in ipairs(reactorIDs) do
                local id = reactorID
                local state = repo.get(id .. "_state")
                if state then
                    repo.set(id .. "_state", false)
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
        -- Update the display
        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
        end
    elseif message.command == "check_players" then
        -- Send player online status to the requester
        rednet.send(activityCheckID, {playersOnline = anyPlayerOnline}, "player_status")
    elseif message.playersOnline ~= nil then
        -- Received player status
        anyPlayerOnline = message.playersOnline
        print("Received player status from activity check computer. Players online:", anyPlayerOnline)
        -- After updating player status, check if we need to turn on reactors
        if anyPlayerOnline and reactorsOnDueToPESU and not manualOverride then
            local reactorsTurnedOn = false
            -- Turn on reactors
            for _, reactorID in ipairs(reactorIDs) do
                local id = reactorID
                local state = repo.get(id .. "_state")
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not state then
                        repo.set(id .. "_state", true)
                        rednet.send(id, {command = "turn_on"})
                        reactorsTurnedOn = true
                    end
                end
            end
            if reactorsTurnedOn then
                sendReactorStatus("on")
            end
            -- Update the display
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
        -- Turn on reactors only if players are online
        if anyPlayerOnline then
            local reactorsTurnedOn = false
            for _, reactorID in ipairs(reactorIDs) do
                local id = reactorID
                local state = repo.get(id .. "_state")
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not state then
                        repo.set(id .. "_state", true)
                        rednet.send(id, {command = "turn_on"})
                        reactorsTurnedOn = true
                    end
                end
            end
            if reactorsTurnedOn then
                sendReactorStatus("on")
            end
        else
            print("Players are offline. Reactors will turn on when a player comes online.")
        end
    elseif message.command == "turn_off_reactors" then
        print("Received turn_off_reactors command from power mainframe.")
        reactorsOnDueToPESU = false
        saveLastPowerCommand("turn_off_reactors")
        -- Turn off all reactors
        local reactorsTurnedOff = false
        for _, reactorID in ipairs(reactorIDs) do
            local id = reactorID
            local state = repo.get(id .. "_state")
            if state then
                repo.set(id .. "_state", false)
                rednet.send(id, {command = "turn_off"})
                reactorsTurnedOff = true
            end
        end
        if reactorsTurnedOff then
            sendReactorStatus("off")
        end
    else
        -- Ignore unknown commands from power mainframe
    end

    -- Update the display
    if currentPage == "home" then
        ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
    end
end

-- Function to rebuild reactorTable, reactorIDs, numReactorPages, and pages
local function rebuildReactorDataStructures()
    reactorIDs = {}
    reactorTable = {}
    reactors = {}
    for reactorID, data in pairs(reactorOutputLog) do
        table.insert(reactorIDs, reactorID)
    end
    table.sort(reactorIDs)

    for index, reactorID in ipairs(reactorIDs) do
        local reactorName = reactorOutputLog[reactorID].reactorName or "Reactor " .. index
        reactorTable[reactorID] = {id = reactorID, name = reactorName}
        repo.set(reactorID .. "_state", false)  -- Assuming reactors start off
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

    -- Compute the number of reactor pages
    local totalReactors = #reactorIDs
    local reactorsPerPage = 10  -- Adjust as needed
    numReactorPages = math.ceil(totalReactors / reactorsPerPage)

    -- Build pages list
    pages = {
        home = "Home Page"
    }

    for i = 1, numReactorPages do
        pages["reactor" .. i] = "Reactor Status Page " .. i
    end
end

-- Main function for receiving reactor data and handling button presses
local function main()
    -- Load reactor output log
    loadReactorOutputLog()

    -- Rebuild reactor data structures
    rebuildReactorDataStructures()

    -- Load last power command and act accordingly
    local lastPowerCommand = loadLastPowerCommand()
    if lastPowerCommand == "turn_on_reactors" then
        reactorsOnDueToPESU = true
        -- Request player status from Activity Check Computer
        rednet.send(activityCheckID, {command = "check_players"}, "player_status")
        -- Reactors will turn on if players are online (handled in handleActivityCheckMessage)
    elseif lastPowerCommand == "turn_off_reactors" then
        reactorsOnDueToPESU = false
        -- Ensure reactors are off
        local reactorsTurnedOff = false
        for _, reactorID in ipairs(reactorIDs) do
            local state = repo.get(reactorID .. "_state")
            if state then
                repo.set(reactorID .. "_state", false)
                rednet.send(reactorID, {command = "turn_off"})
                reactorsTurnedOff = true
            end
        end
        if reactorsTurnedOff then
            sendReactorStatus("off")
        end
    end

    -- Display the home page initially
    ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)

    -- Bind reactor buttons using repo
    ui.bindReactorButtons(reactorTable, repo)

    -- Request data from all reactors on startup
    requestReactorData()

    -- Handle button presses and reactor data in parallel
    parallel.waitForAny(
        function()
            -- Handle button presses
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
                        for _, reactorID in ipairs(reactorIDs) do
                            local id = reactorID
                            local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                            if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                                repo.set(id .. "_state", anyReactorOff)
                                reactors[id].active = anyReactorOff  -- Update the reactors table
                                if anyReactorOff then
                                    rednet.send(id, {command = "turn_on"})
                                else
                                    rednet.send(id, {command = "turn_off"})
                                end
                                reactorsChanged = true
                            end
                        end
                        -- Update display
                        ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
                    elseif action == "reset" then
                        manualOverride = false
                        -- Restore reactors to automated control
                        local reactorsChanged = false
                        if not reactorsOnDueToPESU or not anyPlayerOnline then
                            -- Turn off reactors
                            for _, reactorID in ipairs(reactorIDs) do
                                local id = reactorID
                                local state = repo.get(id .. "_state")
                                if state then
                                    repo.set(id .. "_state", false)
                                    reactors[id].active = false  -- Update the reactors table
                                    rednet.send(id, {command = "turn_off"})
                                    reactorsChanged = true
                                end
                            end
                        else
                            -- Turn on reactors
                            for _, reactorID in ipairs(reactorIDs) do
                                local id = reactorID
                                local state = repo.get(id .. "_state")
                                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                                    if not state then
                                        repo.set(id .. "_state", true)
                                        reactors[id].active = true  -- Update the reactors table
                                        rednet.send(id, {command = "turn_on"})
                                        reactorsChanged = true
                                    end
                                end
                            end
                        end
                        -- Update display
                        ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
                    else
                        switchPage(action)  -- Switch pages based on the action
                    end
                end
            end
        end,
        function()
            -- Continuously receive messages
            while true do
                local senderID, message, protocol = rednet.receive()
                if senderID == activityCheckID then
                    -- Handle messages from the activity check computer
                    handleActivityCheckMessage(message)
                elseif senderID == powerMainframeID then
                    -- Handle messages from the power mainframe
                    handlePowerMainframeMessage(message)
                else
                    -- Handle messages from reactors
                    if type(message) == "table" and message.id then
                        local reactorID = message.id
                        -- Check if reactor is new
                        if not reactors[reactorID] then
                            print("New reactor detected: " .. reactorID)
                            -- Add reactor to reactorOutputLog
                            reactorOutputLog[reactorID] = {
                                reactorName = message.reactorName,
                                maxOutput = tonumber(message.euOutput) or 0
                            }
                            saveReactorOutputLog()
                            -- Rebuild reactor data structures
                            rebuildReactorDataStructures()
                            -- Re-bind reactor buttons
                            ui.bindReactorButtons(reactorTable, repo)
                            -- Update the display
                            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
                        end

                        -- Store the latest reactor data
                        reactors[reactorID] = reactors[reactorID] or {}
                        for k, v in pairs(message) do
                            reactors[reactorID][k] = v
                        end

                        -- Handle reactor status
                        if message.status == "Destroyed" then
                            reactors[reactorID].destroyed = true
                            reactors[reactorID].status = "Destroyed"
                            reactors[reactorID].active = false
                            -- Update reactor state in repo
                            repo.set(reactorID .. "_state", false)
                        else
                            reactors[reactorID].destroyed = false
                            reactors[reactorID].status = message.status or "online"
                            -- Update reactor state in repo
                            repo.set(reactorID .. "_state", message.active)
                        end

                        -- Check for maintenance mode
                        if string.find(message.reactorName, "-M") then
                            reactors[reactorID].isMaintenance = true
                        else
                            reactors[reactorID].isMaintenance = false
                        end

                        -- Check for overheating only if reactor is not destroyed
                        if not reactors[reactorID].destroyed then
                            local tempString = (message.temp or ""):gsub("[^%d%.]", "")
                            local temp = tonumber(tempString)
                            if temp and temp > 4500 then
                                reactors[reactorID].overheating = true
                                -- Send command to turn off reactor
                                rednet.send(reactorID, {command = "turn_off"})
                                -- Update state in repo
                                repo.set(reactorID .. "_state", false)
                                print("Reactor " .. reactorID .. " is overheating! Shutting down.")
                            elseif temp and temp < 3000 then
                                -- Clear overheating flag if temp is below threshold
                                reactors[reactorID].overheating = false
                            end
                        end

                        -- Save reactor output if euOutput > 1 and update maxOutput if higher
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

                        -- Update display if on reactor page
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

                        -- Update home page if necessary
                        if currentPage == "home" then
                            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU, manualOverride)
                        end
                    else
                        print("Received message from unknown sender ID:", senderID)
                    end
                end
            end
        end
    )
end

main()
