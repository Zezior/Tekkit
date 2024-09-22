-- pesu_sender.lua

-- Configuration
local powerMainframeID = 4644  -- Replace with your actual mainframe computer ID
local modemSide = "top"        -- Adjust based on your setup

-- Open Rednet
if not peripheral.isPresent(modemSide) then
    print("Error: No modem found on side '" .. modemSide .. "'. Please attach a modem.")
    return
end
rednet.open(modemSide)

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

-- Function to format large numbers with units
local function formatNumber(num)
    if num >= 1e9 then
        return string.format("%.2fbil", num / 1e9)
    elseif num >= 1e6 then
        return string.format("%.2fmil", num / 1e6)
    elseif num >= 1e3 then
        return string.format("%.2fk", num / 1e3)
    else
        return tostring(num)
    end
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
        local capacityStr = nil

        -- Parse card data
        for _, line in ipairs(cardData) do
            if line:find("^Title:") then
                title = line:match("^Title:%s*(.*)")
            elseif line:find("^[Ee]nergy:") then
                energyStr = line:match("^[Ee]nergy:%s*([%d%s,%.]+)")
            elseif line:find("^[Cc]apacity:") then
                capacityStr = line:match("^[Cc]apacity:%s*([%d%s,%.]+)")
            end
        end

        -- Debug: Print parsed strings
        print("Parsed Energy String: '" .. tostring(energyStr) .. "'")
        print("Parsed Capacity String: '" .. tostring(capacityStr) .. "'")

        -- Validate and convert energy and capacity
        if energyStr and capacityStr then
            -- Remove spaces, commas, and 'EU', then convert to number
            local energyNum = tonumber(energyStr:gsub("[%s,EU]", "")) or 0
            local capacityNum = tonumber(capacityStr:gsub("[%s,EU]", "")) or 0

            -- Calculate fill percentage
            local fillPercent = capacityNum > 0 and (energyNum / capacityNum) * 100 or 0

            -- Debug: Print numeric values
            print(string.format("Numeric Energy: %d EU", energyNum))
            print(string.format("Numeric Capacity: %d EU", capacityNum))
            print(string.format("Fill Percentage: %.2f%%", fillPercent))

            -- Store data
            energyData[name] = {
                title = title,
                energy = energyNum,
                capacity = capacityNum,
                fillPercent = fillPercent
            }
        else
            print("Warning: Missing Energy or Capacity data in panel '" .. name .. "'.")
        end
    end
    return energyData
end

-- Main Loop
local function main()
    local panels = getInfoPanels()
    if #panels == 0 then
        print("No Advanced Information Panels found. Ensure they are connected properly.")
        return
    end

    -- Table to store initial energy data
    local panelHistory = getPanelEnergyData(panels)
    print("Initial energy data collected.")

    while true do
        -- Wait for 20 seconds (400 ticks)
        print("Waiting for 20 seconds to calculate active usage...")
        sleep(20)

        -- Collect energy data again
        local finalEnergy = getPanelEnergyData(panels)
        print("Final energy data collected.")

        -- Calculate active usage and prepare data to send
        local panelDataList = {}
        for name, initial in pairs(panelHistory) do
            if finalEnergy[name] then
                local deltaEnergy = initial.energy - finalEnergy[name].energy
                -- Assuming deltaEnergy positive means energy was consumed
                local activeUsage = deltaEnergy / 400  -- 400 ticks = 20 seconds

                -- Prevent negative usage (if energy increased)
                if activeUsage < 0 then
                    activeUsage = 0
                end

                table.insert(panelDataList, {
                    title = initial.title,
                    energy = finalEnergy[name].energy,
                    fillPercent = finalEnergy[name].fillPercent,
                    activeUsage = activeUsage
                })

                print(string.format("Panel '%s' Active Usage: %.2f EU/t", initial.title, activeUsage))

                -- Update history
                panelHistory[name] = finalEnergy[name]
            else
                print(string.format("Warning: Panel '%s' not found in final energy data.", initial.title))
            end
        end

        -- Prepare data packet
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
        else
            print("No active usage data to send.")
        end
    end
end

main()
