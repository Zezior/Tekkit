-- reactor_sender.lua

local config = {
    mainframeID = 4709,          -- Rednet ID of the main control computer (update if needed)
    updateInterval = 30,         -- Time in seconds between data updates
    redstoneSide = "top",        -- The side where redstone controls the reactor
    infoPanelSide = "front",     -- Side where the advanced information panel is connected
}

-- Function to detect and open the wireless Rednet modem
local function detectWirelessModem()
    local peripherals = peripheral.getNames()
    for _, name in ipairs(peripherals) do
        if peripheral.getType(name) == "modem" then
            local modem = peripheral.wrap(name)
            if modem.isWireless() then
                print("Wireless modem detected on side: " .. name)
                rednet.open(name)  -- Open the wireless modem for Rednet communication
                return name
            end
        end
    end
    error("No wireless modem found! Cannot proceed without a wireless modem.")
end

-- Function to detect peripherals (advanced information panel and modem)
local function detectPeripherals()
    detectWirelessModem()  -- Ensure the wireless modem is detected and opened

    -- Wrap the advanced information panel
    if not peripheral.isPresent(config.infoPanelSide) then
        print("[Warning] No advanced information panel detected on side: " .. config.infoPanelSide)
        return nil
    end

    local infoPanel = peripheral.wrap(config.infoPanelSide)
    return infoPanel
end

-- Function to control the reactor's power state using redstone
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

-- Function to retrieve reactor metadata from the advanced info panel
local function getReactorData()
    local infoPanel = peripheral.wrap(config.infoPanelSide)
    local reactorStatus = "online"

    if not infoPanel then
        print("[Error] Advanced Information Panel not found on side: " .. config.infoPanelSide)
        reactorStatus = "offline"
    end

    local data = nil
    if infoPanel then
        local success, result = pcall(infoPanel.getCardData)
        if success and result then
            data = result
        else
            print("[Error] Failed to retrieve reactor info from the panel.")
            reactorStatus = "offline"
        end
    end

    local tempValue = "N/A"
    local outputValue = "0"
    local fuelValue = "N/A"
    local titleValue = "Unknown"

    if data then
        titleValue = data[1] or "Unknown"
        tempValue = data[2] and data[2]:gsub("Temp:%s*", ""):gsub("C", ""):gsub("%s", "") or "N/A"
        outputValue = data[6] and data[6]:gsub("Output:%s*", ""):gsub(" EU/t", ""):gsub("%s", "") or "0"
        fuelValue = data[7] and data[7]:gsub("Remaining:%s*", "") or "N/A"
    end

    return {
        title = titleValue,                           -- Reactor title/name
        temp = tempValue,                             -- Reactor temperature
        euOutput = outputValue,                       -- Reactor EU Output
        active = redstone.getOutput(config.redstoneSide),  -- Reactor active status based on redstone signal
        fuelRemaining = fuelValue,                    -- Remaining fuel info
        id = os.getComputerID(),                      -- Reactor computer ID
        status = reactorStatus                        -- Reactor status: "online" or "offline"
    }
end

-- Function to send reactor data via Rednet
local function sendReactorData()
    local reactorData = getReactorData()

    -- Prepare a table for Rednet transmission
    local dataToSend = {
        id = reactorData.id,
        reactorName = reactorData.title,
        temp = reactorData.temp,
        euOutput = reactorData.euOutput,
        active = reactorData.active,
        fuelRemaining = reactorData.fuelRemaining,
        status = reactorData.status
    }

    -- Debug: Print exactly what is being sent
    print("Sending data to mainframe: ", textutils.serialize(dataToSend))

    -- Send the data to the mainframe
    rednet.send(config.mainframeID, dataToSend)
    print("Sent reactor and fuel data to mainframe:", config.mainframeID)
end

-- Function to listen for On/Off commands from the mainframe and send immediate data updates
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
                -- Send data immediately
                sendReactorData()
            else
                print("[Error] Unknown command received: " .. tostring(message.command))
            end
            -- Wait briefly to allow reactor to update, then send immediate update
            sleep(1)
            sendReactorData()
        else
            print("[Error] Invalid or malformed message received from ID " .. senderID)
        end
    end
end

-- Main function to run reactor data transmission and command listener
local function main()
    -- Detect peripherals
    detectPeripherals()

    -- Ensure the reactor is off on script startup
    controlReactor("off")

    -- Run the sendReactorData loop and listen for commands in parallel
    parallel.waitForAny(
        function()
            while true do
                -- Send periodic updates every updateInterval seconds
                sendReactorData()
                sleep(config.updateInterval)
            end
        end,
        function()
            -- Listen for commands and send immediate updates
            listenForCommands()
        end
    )
end

-- Start the main function
main()
