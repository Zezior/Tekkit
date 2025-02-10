-- reactor_sender.lua

local config = {
    mainframeID = 7562,          -- Rednet ID of the main control computer (update if needed)
    updateInterval = 15,         -- Time in seconds between data updates
    redstoneSide = "back",       -- The side where redstone controls the reactor
    infoPanelSide = "bottom",    -- Side where the advanced information panel is connected
    reactorNameFile = "reactor_name.txt"  -- File to store the reactor's name
}

local function detectWirelessModem()
    local peripherals = peripheral.getNames()
    for _, name in ipairs(peripherals) do
        if peripheral.getType(name) == "modem" then
            local modem = peripheral.wrap(name)
            if modem.isWireless() then
                print("Wireless modem detected on side: " .. name)
                rednet.open(name)
                return name
            end
        end
    end
    error("No wireless modem found! Cannot proceed without a wireless modem.")
end

local function detectPeripherals()
    detectWirelessModem()
    if not peripheral.isPresent(config.infoPanelSide) then
        print("[Warning] No advanced information panel detected on side: " .. config.infoPanelSide)
        return nil
    end
    local infoPanel = peripheral.wrap(config.infoPanelSide)
    return infoPanel
end

local function controlReactor(state)
    if state == "on" then
        redstone.setOutput(config.redstoneSide, true)
        print("Reactor turned on via redstone.")
    elseif state == "off" then
        redstone.setOutput(config.redstoneSide, false)
        print("Reactor turned off via redstone.")
    else
        print("[Error] Unknown reactor control state: " .. tostring(state))
    end
end

local function saveReactorName(name)
    local file = fs.open(config.reactorNameFile, "w")
    if file then
        file.write(name)
        file.close()
        print("Saved reactor name to file:", name)
    else
        print("[Error] Failed to save reactor name to file.")
    end
end

local function loadReactorName()
    if fs.exists(config.reactorNameFile) then
        local file = fs.open(config.reactorNameFile, "r")
        if file then
            local name = file.readAll()
            file.close()
            return name
        else
            print("[Error] Failed to read reactor name from file.")
            return "Unknown Reactor"
        end
    else
        return "Unknown Reactor"
    end
end

local function getReactorData()
    local infoPanel = peripheral.wrap(config.infoPanelSide)
    local reactorStatus = "online"
    local reactorName = "Unknown Reactor"

    if not infoPanel then
        print("[Error] Advanced Information Panel not found on side: " .. config.infoPanelSide)
        reactorStatus = "Destroyed"
        reactorName = loadReactorName()
    else
        local success, data = pcall(infoPanel.getCardData)
        if success and data then
            reactorName = data[1] or "Unknown Reactor"
            if reactorName == "Target Not Found" then
                reactorStatus = "Destroyed"
                reactorName = loadReactorName()
            else
                if not fs.exists(config.reactorNameFile) then
                    saveReactorName(reactorName)
                end
            end
        else
            print("[Error] Failed to retrieve reactor info from the panel.")
            reactorStatus = "Destroyed"
            reactorName = loadReactorName()
        end
    end

    local tempValue = "0"
    local outputValue = "0"
    local fuelValue = "N/A"

    if infoPanel and reactorStatus == "online" then
        local data = infoPanel.getCardData()
        tempValue = data[2] and data[2]:gsub("Temp:%s*", ""):gsub("C", ""):gsub("%s", "") or "0"
        outputValue = data[6] and data[6]:gsub("Output:%s*", ""):gsub(" EU/t", ""):gsub("%s", "") or "0"
        fuelValue = data[7] and data[7]:gsub("Remaining:%s*", "") or "N/A"
    end

    return {
        title = reactorName,
        temp = tempValue,
        euOutput = outputValue,
        active = redstone.getOutput(config.redstoneSide),
        fuelRemaining = fuelValue,
        id = os.getComputerID(),
        status = reactorStatus
    }
end

local function sendReactorData()
    local reactorData = getReactorData()
    local dataToSend = {
        id = reactorData.id,
        reactorName = reactorData.title,
        temp = reactorData.temp,
        euOutput = reactorData.euOutput,
        active = reactorData.active,
        fuelRemaining = reactorData.fuelRemaining,
        status = reactorData.status
    }
    print("Sending data to mainframe: ", textutils.serialize(dataToSend))
    rednet.send(config.mainframeID, dataToSend)
    print("Sent reactor and fuel data to mainframe:", config.mainframeID)
end

local function listenForCommands()
    while true do
        local senderID, message = rednet.receive()
        print("Received message from mainframe: " .. senderID)
        if senderID == config.mainframeID and type(message) == "table" and message.command then
            if message.command == "turn_on" then
                controlReactor("on")
            elseif message.command == "turn_off" then
                controlReactor("off")
            elseif message.command == "send_data" then
                sendReactorData()
            else
                print("[Error] Unknown command received: " .. tostring(message.command))
            end
            sleep(1)
            sendReactorData()
        else
            print("[Error] Invalid or malformed message received from ID " .. senderID)
        end
    end
end

local function main()
    detectPeripherals()
    controlReactor("off")
    parallel.waitForAny(
        function()
            while true do
                sendReactorData()
                sleep(config.updateInterval)
            end
        end,
        function()
            listenForCommands()
        end
    )
end

main()
