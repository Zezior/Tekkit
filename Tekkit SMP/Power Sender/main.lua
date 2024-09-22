-- pesu_sender.lua

-- Configuration
local powerMainframeID = 4644  -- Replace with your actual mainframe computer ID

-- Function to auto-detect available modems
local function autoDetectModem(preferredSides)
    for _, side in ipairs(preferredSides) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            return side
        end
    end
    return nil
end

-- Preferred order: wired first, then wireless
local preferredModemSides = {"back", "top", "left", "right", "front", "bottom"}
local modemSide = autoDetectModem(preferredModemSides)

if not modemSide then
    print("Error: No modem found. Please attach a modem.")
    return
end

rednet.open(modemSide)
print("Rednet opened on side: " .. modemSide)

-- Function to scan and return all info_panel_advanced peripherals
local function getInfoPanels()
    local panels = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "info_panel_advanced" then
            local panel = peripheral.wrap(name)
            if panel then
                table.insert(panels, {name = name, panel = panel})
                print("Detected Advanced Information Panel: " .. name)
            else
                print("Error: Unable to wrap peripheral '" .. name .. "'.")
            end
        end
    end
    return panels
end

-- Function to collect energy data from panels
local function getPanelEnergyData(panels)
    local energyData = {}
    for _, panelInfo in ipairs(panels) do
        local name = panelInfo.name
        local panel = panelInfo.panel

        -- Retrieve card data
        local cardData = panel.getCardDataRaw()

        -- Debug: Print the raw card data
        print("Raw Card Data for panel '" .. name .. "':")
        for _, line in ipairs(cardData) do
            print("  " .. line)
        end

        -- Initialize variables
        local title = "Unknown"
        local energyStr = nil

        -- Parse card data
        for _, line in ipairs(cardData) do
            if line:find("^Title:") then
                title = line:match("^Title:%s*(.*)")
            elseif line:find("^[Ee]nergy:") then
                energyStr = line:match("^[Ee]nergy:%s*([%d%s,EU]+)")
            end
        end

        -- Debug: Print parsed strings
        print("Parsed Title: '" .. tostring(title) .. "'")
        print("Parsed Energy String: '" .. tostring(energyStr) .. "'")

        -- Validate and convert energy
        if energyStr then
            -- Remove spaces, commas, and 'EU', then convert to number
            local energyNum = tonumber(energyStr:gsub("[%s,EU]", "")) or 0

            -- Debug: Print numeric energy
            print(string.format("Numeric Energy: %d EU", energyNum))

            -- Store data
            energyData[name] = {
                title = title,
                energy = energyNum
            }
        else
            print("Warning: Missing Energy data in panel '" .. name .. "'.")
        end
    end
    return energyData
end

-- Function to calculate Active Usage
local function calculateActiveUsage(initialData, finalData)
    local panelDataList = {}
    for name, initial in pairs(initialData) do
        if finalData[name] then
            local deltaEnergy = initial.energy - finalData[name].energy
            -- Assuming deltaEnergy positive means energy was consumed
            local activeUsage = deltaEnergy / 400  -- 400 ticks = 20 seconds

            -- Prevent negative usage (if energy increased)
            if activeUsage < 0 then
                activeUsage = 0
            end

            table.insert(panelDataList, {
                title = initial.title,
                energy = finalData[name].energy,
                activeUsage = activeUsage
            })

            print(string.format("Panel '%s' Active Usage: %.2f EU/t", initial.title, activeUsage))
        else
            print(string.format("Warning: Panel '%s' not found in final energy data.", initial.title))
        end
    end
    return panelDataList
end

-- Main Loop
local function main()
    local panels = getInfoPanels()
    if #panels == 0 then
        print("No Advanced Information Panels found. Ensure they are connected properly.")
        return
    end

    -- Collect initial energy data
    local initialEnergyData = getPanelEnergyData(panels)
    print("Initial energy data collected.")

    while true do
        -- Wait for 20 seconds (400 ticks)
        print("Waiting for 20 seconds to calculate active usage...")
        sleep(20)  -- Sleep for 20 seconds

        -- Collect final energy data
        local finalEnergyData = getPanelEnergyData(panels)
        print("Final energy data collected.")

        -- Calculate active usage
        local panelDataList = calculateActiveUsage(initialEnergyData, finalEnergyData)

        -- Send data to mainframe
        if #panelDataList > 0 then
            local data = {
                command = "panel_data",
                senderID = os.getComputerID(),
                panels = panelDataList,
                timestamp = os.time()
            }

            -- Send data to mainframe
            rednet.send(powerMainframeID, data, "pesu_data")
            print("Data sent to power mainframe.")

            -- Update initial data for next calculation
            initialEnergyData = finalEnergyData
        else
            print("No active usage data to send.")
        end
    end
end

main()
