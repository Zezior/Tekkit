local peripherals = peripheral.getNames()

print("Connected peripherals:")
for _, name in ipairs(peripherals) do
    print("- " .. name)
end
