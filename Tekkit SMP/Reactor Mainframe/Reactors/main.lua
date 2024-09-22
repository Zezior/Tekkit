-- main.lua
local ui = require("ui")
local reactorsModule = require("reactors")
local allowedIDs = require("ids")

local currentPage = "home"  -- Start on the home page
local reactors = {}  -- Table to store reactor data

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

-- Dynamically generate the reactorTable based on allowedIDs
local reactorTable = {}
for index, id in ipairs(allowedIDs) do
    reactorTable["Reactor" .. index] = {id = id, name = "Reactor " .. index}
end

-- Initialize reactor states in the repo
for _, reactor in pairs(reactorTable) do
    repo.set(reactor.id .. "_state", false)  -- Assuming reactors start off
end

-- List of pages, allowing for dynamic page addition
local pages = {
    home = "Home Page",
    reactor = "Reactor Status"
}

-- Check if senderID is in the allowed list
local function isAllowedID(senderID)
    for _, id in ipairs(allowedIDs) do
        if id == senderID then
            return true
        end
    end
    return false
end

-- Function to switch between pages dynamically
local function switchPage(page)
    if pages[page] then
        currentPage = page
        if currentPage == "home" then
            ui.displayHomePage(repo, reactorTable)  -- Pass repo and reactorTable
        elseif currentPage == "reactor" then
            reactorsModule.displayReactorData(reactors)
        else
            ui.displayPlaceholderPage(currentPage)  -- Placeholder for other pages
        end
    else
        print("Page not found: " .. page)
    end
end

-- Main function for receiving reactor data and handling button presses
local function main()
    -- Display the home page initially
    ui.displayHomePage(repo, reactorTable)

    -- Bind reactor buttons using repo
    ui.bindReactorButtons(reactorTable, repo)

    -- Listen for button presses and reactor data in parallel
    parallel.waitForAny(
        function()
            -- Handle button presses
            while true do
                local event, side, x, y = os.pullEvent("monitor_touch")
                local action = ui.detectButtonPress(x, y)
                if action then
                    switchPage(action)  -- Switch pages based on the action
                end
            end
        end,
        function()
            -- Continuously receive reactor data
            while true do
                local senderID, message = rednet.receive()
                if isAllowedID(senderID) then
                    print("Received authorized message from reactor ID:", senderID)
                    if type(message) == "table" and message.id then
                        reactors[message.id] = message  -- Store the latest reactor data
                        print("Reactor data received for ID:", message.id)
                        print("Message content:", textutils.serialize(message))

                        -- Update reactor state in repo
                        repo.set(message.id .. "_state", message.active)

                        -- Update display if on reactor page
                        if currentPage == "reactor" then
                            reactorsModule.displayReactorData(reactors)
                        end
                    else
                        print("Invalid message received from:", senderID)
                    end
                else
                    print("Unauthorized sender ID:", senderID)
                end
            end
        end
    )
end

main()
