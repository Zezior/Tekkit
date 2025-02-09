-- Player Activity main.lua

local ids = dofile("ids.lua")
local reactorMainframeID = ids.reactorMainframeID  -- Ensure this is defined in your ids.lua

local monitorSide = "right"
local modemSide = "front"
local monitor = peripheral.wrap(monitorSide)

-- Set custom background color
local bgColor = colors.brown  -- Using 'colors.brown' as the slot for custom color
monitor.setPaletteColor(bgColor, 18 / 255, 53 / 255, 36 / 255)  -- RGB values for #123524

-- Apply background color and text settings
monitor.setBackgroundColor(bgColor)
monitor.setTextColor(colors.white)
monitor.setTextScale(1)  -- Increased text scale for larger font
monitor.clear()

-- List of introspection modules and corresponding player names
local introspectionModules = {
    {side = "top", name = "ReactorKing"},
    -- {side = "back", name = "N/A"},
    -- {side = "left", name = "N/A"},  -- Uncomment and set thirdPersonEnabled to true to enable
}

-- Open the wireless modem
rednet.open(modemSide)

local anyOnline = false  -- Global variable to track if any player is online

local function checkPlayerOnline(introspection)
    -- Attempt to access the inventory and return the result
    local success, inv = pcall(function()
        return introspection and introspection.getInventory and introspection.getInventory() or nil
    end)
    
    -- Check if we retrieved inventory data successfully
    if success and inv then
        return true
    else
        return false
    end
end

local function getCurrentTime()
    local time = os.date("*t")
    time.hour = time.hour + 1
    if time.hour >= 24 then
        time.hour = time.hour - 24
    end
    return string.format("%02d:%02d:%02d", time.hour, time.min, time.sec)
end

local function drawBorder()
    monitor.setTextColor(colors.orange)
    local w, h = monitor.getSize()
    monitor.setCursorPos(1, 1)
    for i = 1, w do
        monitor.setCursorPos(i, 1)
        monitor.write(" ")
        monitor.setCursorPos(i, h)
        monitor.write(" ")
    end
    for i = 1, h do
        monitor.setCursorPos(1, i)
        monitor.write(" ")
        monitor.setCursorPos(w, i)
        monitor.write(" ")
    end
    monitor.setTextColor(colors.white)
end

local function centerText(text, y)
    local w, h = monitor.getSize()
    local x = math.floor((w - string.len(text)) / 2) + 1
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

local function displayToMonitor(lines)
    monitor.clear()
    drawBorder()
    local w, h = monitor.getSize()
    local startLine = math.ceil(h / 2 - #lines / 2) + 1

    for i, line in ipairs(lines) do
        local name, status = string.match(line, "^(.-): (.+)$")
        if name and status then
            if status == "Online" then
                monitor.setTextColor(colors.green)
            elseif status == "Offline" then
                monitor.setTextColor(colors.red)
            elseif status:find("Waiting for Chunks") then
                monitor.setTextColor(colors.yellow)
            elseif status == "Unavailable" then
                monitor.setTextColor(colors.gray)
            else
                monitor.setTextColor(colors.white)
            end
            centerText(line, startLine + i - 1)
        else
            monitor.setTextColor(colors.white)
            centerText(line, startLine + i - 1)
        end
    end
    monitor.setTextColor(colors.white)
end

local function waitForChunksToLoad(seconds, status)
    local timerID = os.startTimer(1)
    local waitingTime = seconds
    while waitingTime > 0 do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == timerID then
            local lines = {}
            for _, module in ipairs(introspectionModules) do
                lines[#lines + 1] = module.name .. ": " .. status[module.name]
            end
            lines[#lines + 1] = "Waiting for Chunks to load: " .. waitingTime
            lines[#lines + 1] = "UK Time: " .. getCurrentTime()
            displayToMonitor(lines)
            waitingTime = waitingTime - 1
            timerID = os.startTimer(1)
        elseif event == "rednet_message" then
            local senderID, message, protocol = p1, p2, p3
            if message.command == "check_players" and senderID == reactorMainframeID then
                rednet.send(reactorMainframeID, {playersOnline = anyOnline}, "player_status")
            end
        end
    end
end

local function handleMessages()
    while true do
        local event, p1, p2, p3 = os.pullEvent("rednet_message")
        local senderID, message, protocol = p1, p2, p3
        if message.command == "check_players" and senderID == reactorMainframeID then
            rednet.send(reactorMainframeID, {playersOnline = anyOnline}, "player_status")
        end
    end
end

local function mainLoop()
    -- Initial countdown
    local countdown = 10
    local timerID = os.startTimer(1)
    while countdown > 0 do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == timerID then
            displayToMonitor({
                "Script starting in: " .. countdown,
                "UK Time: " .. getCurrentTime()
            })
            countdown = countdown - 1
            timerID = os.startTimer(1)
        elseif event == "rednet_message" then
            local senderID, message, protocol = p1, p2, p3
            if message.command == "check_players" and senderID == reactorMainframeID then
                rednet.send(reactorMainframeID, {playersOnline = anyOnline}, "player_status")
            end
        end
    end

    local lastStatus = nil
    local lastSentTime = os.clock()
    local sendInterval = 15  -- seconds

    while true do
        local status = {}
        anyOnline = false

        -- Check each introspection module
        for _, module in ipairs(introspectionModules) do
            local introspection = peripheral.wrap(module.side)
            if introspection then
                local playerOnline = checkPlayerOnline(introspection)
                local playerStatus = playerOnline and "Online" or "Offline"
                status[module.name] = playerStatus
                if playerOnline then
                    anyOnline = true
                end
            else
                status[module.name] = "Unavailable"
                print("Introspection module on side " .. module.side .. " is unavailable.")
            end
        end

        -- Update display
        local displayLines = {}
        for _, module in ipairs(introspectionModules) do
            displayLines[#displayLines + 1] = module.name .. ": " .. status[module.name]
        end
        displayLines[#displayLines + 1] = "UK Time: " .. getCurrentTime()
        displayToMonitor(displayLines)

        local currentTime = os.clock()

        if lastStatus == nil then
            -- First run, send status immediately
            if anyOnline then
                -- Wait for chunks to load (only once)
                waitForChunksToLoad(10, status)
            end
            rednet.send(reactorMainframeID, {command = anyOnline and "player_online" or "player_offline"}, "reactor_control")
            print("Sent initial status to mainframe:", anyOnline and "player_online" or "player_offline")
            lastStatus = anyOnline
            lastSentTime = currentTime
        elseif anyOnline ~= lastStatus then
            -- Status changed, send message immediately
            if anyOnline then
                -- Player came online
                waitForChunksToLoad(10, status)
                rednet.send(reactorMainframeID, {command = "player_online"}, "reactor_control")
                print("Sent 'player_online' command to mainframe.")
            else
                -- Player went offline
                rednet.send(reactorMainframeID, {command = "player_offline"}, "reactor_control")
                print("Sent 'player_offline' command to mainframe.")
            end
            lastStatus = anyOnline
            lastSentTime = currentTime
        elseif currentTime - lastSentTime >= sendInterval then
            -- Send regular status update
            rednet.send(reactorMainframeID, {command = anyOnline and "player_online" or "player_offline"}, "reactor_control")
            print("Sent regular status update to mainframe:", anyOnline and "player_online" or "player_offline")
            lastSentTime = currentTime
        end

        -- Sleep for 1 second before next check
        sleep(1)
    end
end

-- Run the main function and message handler in parallel
parallel.waitForAny(mainLoop, handleMessages)
