-- Reactor Mainframe - main.lua

local ui = require("ui")
local reactorsModule = require("reactors")
local ids = require("ids")

local reactorIDs = ids.reactorIDs
local activityCheckID = ids.activityCheckID
local powerMainframeID = ids.powerMainframeID

table.sort(reactorIDs)
local minReactorID = reactorIDs[1] or 0

local currentPage = "home"  -- Start on the home page
local reactors = {}  -- Table to store reactor data
local reactorOutputLog = {}  -- Table to store reactor output data

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

-- Dynamically generate the reactorTable based on reactorIDs
local reactorTable = {}
for index, id in ipairs(reactorIDs) do
    reactorTable["Reactor" .. index] = {id = id, name = "Reactor " .. index}
end

-- Initialize reactor states in the repo and reactors table
for _, reactor in pairs(reactorTable) do
    repo.set(reactor.id .. "_state", false)  -- Assuming reactors start off
    reactors[reactor.id] = {
        reactorName = reactor.name,
        temp = "N/A",
        active = false,
        euOutput = "0",
        fuelRemaining = "N/A",
        isMaintenance = false,
        overheating = false,
        destroyed = false,  -- Add destroyed flag
        status = "unknown"  -- Add status field
    }
end

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

-- Function to load power log from file
local function loadPowerLog()
    if fs.exists("power_log.txt") then
        local file = fs.open("power_log.txt", "r")
        if file then
            local lastLine = nil
            repeat
                local line = file.readLine()
                if line then
                    lastLine = line
                end
            until not line
            file.close()
            if lastLine == "turn_on" then
                reactorsOnDueToPESU = true
            else
                reactorsOnDueToPESU = false
            end
        end
    else
        reactorsOnDueToPESU = false
    end
end

-- Function to save power log to file
local function savePowerLog(action)
    local file = fs.open("power_log.txt", "a")
    if file then
        file.writeLine(action)
        file.close()
    end
end

-- Function to request data from all reactors on startup
local function requestReactorData()
    for _, reactor in pairs(reactorTable) do
        rednet.send(reactor.id, {command = "send_data"})
    end
end

-- Compute the number of reactor pages
local totalReactors = #reactorIDs
local reactorsPerPage = 8  -- Updated to match reactors.lua
local numReactorPages = math.ceil(totalReactors / reactorsPerPage)

-- Build pages list
local pages = {
    home = "Home Page"
}

for i = 1, numReactorPages do
    pages["reactor" .. i] = "Reactor Status Page " .. i
end

-- Check if senderID is in the reactor IDs list
local function isReactorID(senderID)
    for _, id in ipairs(reactorIDs) do
        if id == senderID then
            return true
        end
    end
    return false
end

local reactorsOnDueToPESU = false  -- Track if reactors are turned on due to PESU levels
local anyPlayerOnline = false  -- Track player online status

-- Function to switch between pages dynamically
local function switchPage(page)
    if pages[page] then
        currentPage = page
        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU)
        elseif string.sub(currentPage, 1, 7) == "reactor" then
            -- Extract page number
            local pageNumString = string.sub(currentPage, 8)
            local pageNum = tonumber(pageNumString)
            if not pageNum then
                print("Invalid reactor page number:", pageNumString)
                return
            end
            reactorsModule.displayReactorData(reactors, pageNum, numReactorPages, reactorIDs)
        else
            ui.displayPlaceholderPage(currentPage)
        end
    else
        print("Page not found: " .. page)
    end
end

-- Function to send reactor status to power mainframe
local function sendReactorStatus(status)
    rednet.broadcast({command = "reactor_status", status = status}, "reactor_control")
end

-- Function to handle messages from the activity check computer
local function handleActivityCheckMessage(message)
    if message.command == "player_online" then
        print("Received player_online command from activity check computer.")
        anyPlayerOnline = true

        -- Only turn on reactors if both conditions are met
        if reactorsOnDueToPESU then
            for _, reactor in pairs(reactorTable) do
                local id = reactor.id
                local state = repo.get(id .. "_state")
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not state then
                        repo.set(id .. "_state", true)
                        rednet.send(id, {command = "turn_on"})
                    end
                end
            end
            sendReactorStatus("on")
        else
            print("Reactors are not turned on due to PESU levels.")
        end

        -- Update the display
        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU)
        end
    elseif message.command == "player_offline" then
        print("Received player_offline command from activity check computer.")
        anyPlayerOnline = false
        -- Turn off all reactors
        for _, reactor in pairs(reactorTable) do
            local id = reactor.id
            local state = repo.get(id .. "_state")
            if state then
                repo.set(id .. "_state", false)
                rednet.send(id, {command = "turn_off"})
            end
        end
        sendReactorStatus("off")
        -- Update the display
        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU)
        end
    elseif message.command == "check_players" then
        -- Send player online status to the requester
        rednet.send(message.senderID, {playersOnline = anyPlayerOnline}, "player_status")
    else
        print("Unknown command from activity check computer:", message.command)
    end
end

-- Function to handle messages from the power mainframe
local function handlePowerMainframeMessage(message)
    if message.command == "turn_on_reactors" then
        print("Received turn_on_reactors command from power mainframe.")
        reactorsOnDueToPESU = true
        savePowerLog("turn_on")
        -- Turn on reactors only if players are online
        if anyPlayerOnline then
            for _, reactor in pairs(reactorTable) do
                local id = reactor.id
                local state = repo.get(id .. "_state")
                local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                    if not state then
                        repo.set(id .. "_state", true)
                        rednet.send(id, {command = "turn_on"})
                    end
                end
            end
            sendReactorStatus("on")
        else
            print("Players are offline. Reactors will not be turned on.")
        end
    elseif message.command == "turn_off_reactors" then
        print("Received turn_off_reactors command from power mainframe.")
        reactorsOnDueToPESU = false
        savePowerLog("turn_off")
        -- Turn off all reactors
        for _, reactor in pairs(reactorTable) do
            local id = reactor.id
            local state = repo.get(id .. "_state")
            if state then
                repo.set(id .. "_state", false)
                rednet.send(id, {command = "turn_off"})
            end
        end
        sendReactorStatus("off")
    else
        -- Ignore unknown commands from power mainframe
        -- Suppress the "Unknown command" message
    end

    -- Update the display
    if currentPage == "home" then
        ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU)
    end
end

-- Main function for receiving reactor data and handling button presses
local function main()
    -- Load reactor output log
    loadReactorOutputLog()

    -- Load power log
    loadPowerLog()

    -- Display the home page initially
    ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU)

    -- Bind reactor buttons using repo
    ui.bindReactorButtons(reactorTable, repo)

    -- Request data from all reactors on startup
    requestReactorData()

    -- Do not turn on reactors based on power log if they were manually turned on before restart
    reactorsOnDueToPESU = false

    -- Handle button presses and reactor data in parallel
    parallel.waitForAny(
        function()
            -- Handle button presses
            while true do
                local event, side, x, y = os.pullEvent("monitor_touch")
                local action = ui.detectButtonPress(x, y)
                if action then
                    if action == "toggle_all" then
                        -- Toggle all reactors regardless of PESU requirement
                        local anyReactorOff = false
                        for _, reactorData in pairs(reactors) do
                            if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                                if not reactorData.active then
                                    anyReactorOff = true
                                    break
                                end
                            end
                        end
                        for _, reactor in pairs(reactorTable) do
                            local id = reactor.id
                            local state = repo.get(id .. "_state")
                            local reactorData = reactors[id] or { isMaintenance = false, overheating = false, destroyed = false }
                            if not reactorData.isMaintenance and not reactorData.overheating and not reactorData.destroyed then
                                repo.set(id .. "_state", anyReactorOff)
                                if anyReactorOff then
                                    rednet.send(id, {command = "turn_on"})
                                else
                                    rednet.send(id, {command = "turn_off"})
                                end
                            end
                        end
                        -- Reset reactorsOnDueToPESU to false
                        reactorsOnDueToPESU = false
                        savePowerLog("turn_off")
                        sendReactorStatus(anyReactorOff and "on" or "off")
                        -- Update display
                        ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU)
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
                    message.senderID = senderID
                    handleActivityCheckMessage(message)
                elseif senderID == powerMainframeID then
                    -- Handle messages from the power mainframe
                    handlePowerMainframeMessage(message)
                elseif isReactorID(senderID) then
                    -- Handle messages from reactors
                    if type(message) == "table" and message.id then
                        -- Store the latest reactor data
                        reactors[message.id] = message
                        -- Suppress console output for reactor data

                        -- Handle reactor status
                        if message.status == "Destroyed" then
                            reactors[message.id].destroyed = true
                            reactors[message.id].status = "Destroyed"
                            reactors[message.id].active = false
                            -- Update reactor state in repo
                            repo.set(message.id .. "_state", false)
                        else
                            reactors[message.id].destroyed = false
                            reactors[message.id].status = message.status or "online"
                            -- Update reactor state in repo
                            repo.set(message.id .. "_state", message.active)
                        end

                        -- Check for maintenance mode
                        if string.find(message.reactorName, "-M") then
                            reactors[message.id].isMaintenance = true
                        else
                            reactors[message.id].isMaintenance = false
                        end

                        -- Check for overheating only if reactor is not destroyed
                        if not reactors[message.id].destroyed then
                            local tempString = (message.temp or ""):gsub("[^%d%.]", "")
                            local temp = tonumber(tempString)
                            if temp and temp > 4500 then
                                reactors[message.id].overheating = true
                                -- Send command to turn off reactor
                                rednet.send(message.id, {command = "turn_off"})
                                -- Update state in repo
                                repo.set(message.id .. "_state", false)
                                print("Reactor " .. message.id .. " is overheating! Shutting down.")
                            elseif temp and temp < 3000 then
                                -- Clear overheating flag if temp is below threshold
                                reactors[message.id].overheating = false
                            end
                        end

                        -- Save reactor output if euOutput > 1 and not already stored
                        if not reactors[message.id].destroyed then
                            local euOutputNum = tonumber(message.euOutput)
                            if euOutputNum and euOutputNum > 1 then
                                if not reactorOutputLog[message.id] then
                                    reactorOutputLog[message.id] = {
                                        reactorName = message.reactorName,
                                        maxOutput = euOutputNum
                                    }
                                    saveReactorOutputLog()
                                    -- Suppress this print statement
                                end
                            end
                        end

                        -- Update display if on reactor page
                        local index = 0
                        for idx, rid in ipairs(reactorIDs) do
                            if rid == message.id then
                                index = idx
                                break
                            end
                        end
                        local pageNum = math.ceil(index / reactorsPerPage)
                        if currentPage == "reactor" .. pageNum then
                            reactorsModule.displayReactorData(reactors, pageNum, numReactorPages, reactorIDs)
                        end

                        -- Update home page if necessary
                        if currentPage == "home" then
                            ui.displayHomePage(repo, reactorTable, reactors, numReactorPages, reactorOutputLog, reactorsOnDueToPESU)
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
