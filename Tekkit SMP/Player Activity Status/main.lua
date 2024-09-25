-- activity_check.lua

local ids = dofile("ids.lua")
local reactorMainframeID = ids.reactorMainframeID  -- Add this to your ids.lua

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
    {side = "back", name = "DK_Qemistry"},
    -- {side = "left", name = "Gqlxy"},  -- Uncomment and set thirdPersonEnabled to true to enable
}

local anyPlayerOnlinePreviously = false -- Track if any player was online previously
local chunkLoadWaitCompleted = false    -- Track if we have already waited for chunks

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
            else
                monitor.setTextColor(colors.white)
            end
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

local function sendPlayerStatus()
    while true do
        if anyOnline then
            rednet.send(reactorMainframeID, {command = "player_online"}, "reactor_control")
        else
            rednet.send(reactorMainframeID, {command = "player_offline"}, "reactor_control")
        end
        sleep(60)  -- Send status every 60 seconds
    end
end

local function handleMessages()
    while true do
        local event, senderID, message, protocol = os.pullEvent("rednet_message")
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

        if anyOnline then
            -- Players are online
            if not anyPlayerOnlinePreviously then
                -- Only execute when players just came online

                -- Wait for chunks to load (only once)
                if not chunkLoadWaitCompleted then
                    waitForChunksToLoad(10, status)  -- Countdown for chunk loading
                    chunkLoadWaitCompleted = true    -- Ensure it doesn't repeat
                end

                -- After chunks are loaded, send message to mainframe
                rednet.send(reactorMainframeID, {command = "player_online"}, "reactor_control")
                print("Sent player_online command to mainframe.")

                anyPlayerOnlinePreviously = true  -- Update the flag
            end

            -- Update display
            local displayLines = {}
            for _, module in ipairs(introspectionModules) do
                displayLines[#displayLines + 1] = module.name .. ": " .. status[module.name]
            end
            displayLines[#displayLines + 1] = "UK Time: " .. getCurrentTime()
            displayToMonitor(displayLines)

        else
            -- No players online
            if anyPlayerOnlinePreviously then
                -- Only execute when players just went offline
                -- Send message to mainframe
                rednet.send(reactorMainframeID, {command = "player_offline"}, "reactor_control")
                print("Sent player_offline command to mainframe.")
                chunkLoadWaitCompleted = false  -- Reset chunk load wait flag
                anyPlayerOnlinePreviously = false  -- Update the flag
            end

            -- Pausing countdown
            local waiting = 15
            local timerID = os.startTimer(1)
            while waiting > 0 do
                local event, p1, p2, p3 = os.pullEvent()
                if event == "timer" and p1 == timerID then
                    local displayLines = {}
                    for _, module in ipairs(introspectionModules) do
                        displayLines[#displayLines + 1] = module.name .. ": " .. status[module.name]
                    end
                    displayLines[#displayLines + 1] = "No players online, pausing: " .. waiting
                    displayLines[#displayLines + 1] = "UK Time: " .. getCurrentTime()
                    displayToMonitor(displayLines)
                    waiting = waiting - 1
                    timerID = os.startTimer(1)
                elseif event == "rednet_message" then
                    local senderID, message, protocol = p1, p2, p3
                    if message.command == "check_players" and senderID == reactorMainframeID then
                        rednet.send(reactorMainframeID, {playersOnline = anyOnline}, "player_status")
                    end
                end
            end

            -- After pause, check status again
            local retryLines = {}
            for _, module in ipairs(introspectionModules) do
                retryLines[#retryLines + 1] = module.name .. ": " .. status[module.name]
            end
            retryLines[#retryLines + 1] = "No players online, checking again..."
            retryLines[#retryLines + 1] = "UK Time: " .. getCurrentTime()
            displayToMonitor(retryLines)

            -- Keep checking until someone comes online
            while true do
                anyOnline = false
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

                if anyOnline then
                    displayToMonitor({
                        "At least one player is online, resuming...",
                        "UK Time: " .. getCurrentTime()
                    })
                    sleep(1)
                    break -- Exit loop to continue normal operations
                end

                -- Handle incoming messages during sleep
                local event, p1, p2, p3 = os.pullEvent("rednet_message")
                if event == "rednet_message" then
                    local senderID, message, protocol = p1, p2, p3
                    if message.command == "check_players" and senderID == reactorMainframeID then
                        rednet.send(reactorMainframeID, {playersOnline = anyOnline}, "player_status")
                    end
                end
            end
        end

        -- Short sleep to prevent high CPU usage
        sleep(0.1)
    end
end

-- Run the main function and message handler in parallel
parallel.waitForAny(mainLoop, handleMessages, sendPlayerStatus)
