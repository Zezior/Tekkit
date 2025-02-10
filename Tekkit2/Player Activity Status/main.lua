-- Player Activity main.lua

local ids = dofile("ids.lua")
local reactorMainframeID = ids.reactorMainframeID

local monitorSide = "right"
local modemSide = "back"
local monitor = peripheral.wrap(monitorSide)

local bgColor = colors.brown
monitor.setPaletteColor(bgColor, 18 / 255, 53 / 255, 36 / 255)
monitor.setBackgroundColor(bgColor)
monitor.setTextColor(colors.white)
monitor.setTextScale(1)
monitor.clear()

local introspectionModules = {
    {side = "top", name = "ReactorKing"}
}

rednet.open(modemSide)

local anyOnline = false

local function checkPlayerOnline(introspection)
    local success, inv = pcall(function()
        return introspection and introspection.getInventory and introspection.getInventory() or nil
    end)
    if success and inv then
        return true
    else
        return false
    end
end

local function getCurrentTime()
    local time = os.date("*t")
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
    local sendInterval = 15

    while true do
        local status = {}
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

        local displayLines = {}
        for _, module in ipairs(introspectionModules) do
            displayLines[#displayLines + 1] = module.name .. ": " .. status[module.name]
        end
        displayLines[#displayLines + 1] = "UK Time: " .. getCurrentTime()
        displayToMonitor(displayLines)

        local currentTime = os.clock()

        if lastStatus == nil then
            if anyOnline then
                waitForChunksToLoad(10, status)
            end
            rednet.send(reactorMainframeID, {command = anyOnline and "player_online" or "player_offline"}, "reactor_control")
            print("Sent initial status to mainframe:", anyOnline and "player_online" or "player_offline")
            lastStatus = anyOnline
            lastSentTime = currentTime
        elseif anyOnline ~= lastStatus then
            if anyOnline then
                waitForChunksToLoad(10, status)
                rednet.send(reactorMainframeID, {command = "player_online"}, "reactor_control")
                print("Sent 'player_online' command to mainframe.")
            else
                rednet.send(reactorMainframeID, {command = "player_offline"}, "reactor_control")
                print("Sent 'player_offline' command to mainframe.")
            end
            lastStatus = anyOnline
            lastSentTime = currentTime
        elseif currentTime - lastSentTime >= sendInterval then
            rednet.send(reactorMainframeID, {command = anyOnline and "player_online" or "player_offline"}, "reactor_control")
            print("Sent regular status update to mainframe:", anyOnline and "player_online" or "player_offline")
            lastSentTime = currentTime
        end

        sleep(1)
    end
end

parallel.waitForAny(mainLoop, handleMessages)
