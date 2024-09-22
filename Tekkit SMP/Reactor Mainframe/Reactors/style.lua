-- style.lua

local monitor = peripheral.wrap("right")

local style = {
    -- Define global theme colors
    backgroundColor = colors.white,       -- Background color
    textColor = colors.black,             -- Default text color
    headerColor = colors.orange,          -- Header text color
    buttonColor = colors.blue,            -- Default button color
    buttonTextColor = colors.white,       -- Button text color

    -- Text scales and sizes
    textScale = 0.5,
}

-- Apply the style to the monitor
local function applyStyle()
    monitor.setBackgroundColor(style.backgroundColor)
    monitor.setTextColor(style.textColor)
    monitor.setTextScale(style.textScale)
    monitor.clear()  -- Clear the screen to apply the background color
end

-- Draw a button using the global style
local function drawStyledButton(label, x, y, width, height)
    monitor.setBackgroundColor(style.buttonColor)
    monitor.setTextColor(style.buttonTextColor)
    for i = 0, height -1 do
        monitor.setCursorPos(x, y + i)
        monitor.write(string.rep(" ", width))
    end
    monitor.setCursorPos(x + math.floor((width - #label) / 2), y + math.floor(height / 2))
    monitor.write(label)
    monitor.setBackgroundColor(style.backgroundColor)  -- Reset background after button
end

return {
    applyStyle = applyStyle,
    drawStyledButton = drawStyledButton,
    style = style  -- Export the style table for further customization
}
