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
            table.insert(panels, peripheral.wrap(name))
            print("Detected Advanced Information Panel: " .. name)
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

-- Function to collect data from panels
local function collectPanelData(panels, panelHistory)
    local currentTime = os.time()
    local panelDataList = {}

    for _, panel in ipairs(panels) do
        -- Retrieve card data
        local cardData = panel.getCardDataRaw()

        -- Initialize variables
        local title = "Unknown"
        local energy = nil
        local capacity = nil

        -- Parse card data
        for _, line in ipairs(cardData) do
            if line:find("^Title:") then
                title = line:match("^Title:%s*(.*)")
            elseif line:find("^[Ee]nergy:") then
                energy = line:match("^[Ee]nergy:%s*([%d%s,]+)")
            elseif line:find("^[Cc]apacity:") then
                capacity = line:match("^[Cc]apacity:%s*([%d%s,]+)")
            end
        end

        -- Validate and convert energy and capacity
        if energy and capacity then
            -- Remove spaces and commas, then convert to number
            local energyNum = tonumber(energy:gsub("[%s,]", "")) or 0
            local capacityNum = tonumber(capacity:gsub("[%s,]", "")) or 0

            -- Calculate fill percentage
            local fillPercent = capacityNum > 0 and (energyNum / capacityNum) * 100 or 0

            -- Check if this panel has previous data
            if panelHistory[panel] then
                local deltaEnergy = panelHistory[panel].energy - energyNum
                local deltaTicks = currentTime - panelHistory[panel].lastTime

                if deltaTicks >= 20 then
                    -- Calculate Active Usage (EU/t)
                    local activeUsage = deltaEnergy / 400  -- 20 ticks/sec * 20 sec = 400 ticks

                    -- Update history
                    panelHistory[panel].energy = energyNum
                    panelHistory[panel].lastTime = currentTime

                    -- Prepare data to send
                    table.insert(panelDataList, {
                        title = title,
                        energy = energyNum,
                        fillPercent = fillPercent,
                        activeUsage = activeUsage
                    })

                    print(string.format("Panel '%s' Active Usage: %.2f EU/t", title, activeUsage))
                end
            else
                -- Initialize history for this panel
                panelHistory[panel] = {
                    energy = energyNum,
                    lastTime = currentTime
                }
                print(string.format("Initialized history for panel '%s'.", title))
            end
        else
            print("Warning: Missing Energy or Capacity data in panel.")
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

    -- Table to store history for each panel
    local panelHistory = {}

    while true do
        -- Collect data
        local panelDataList = collectPanelData(panels, panelHistory)

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
        end

        -- Wait for 1 second before next iteration
        sleep(1)
    end
end

main()
