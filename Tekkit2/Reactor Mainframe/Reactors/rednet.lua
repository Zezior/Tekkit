-- Reactor Mainframe rednet.lua

local modemSide = "top"  -- Adjust if needed
rednet.open(modemSide)

-- Function to receive reactor data via rednet
local function receiveReactorData(reactors)
    while true do
        local senderID, message = rednet.receive()

        -- Check if the received message is a table (i.e., reactor data)
        if type(message) == "table" and message.name then
            -- Store the reactor data based on its name
            reactors[message.name] = message
            print("Received data from " .. message.name)

            -- Debugging: Print the full received message
            print("Full data received from reactor:")
            print(textutils.serialize(message))
        else
            print("Received invalid message from " .. senderID)
        end
    end
end

return {
    receiveReactorData = receiveReactorData
}