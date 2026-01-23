local math = math
function val_to_color(val, max)
    local t = math.max(0, math.min(val / max, 1))
    local u = math.min(t / 0.5, 1)

    u = u * u * (3 - 2 * u)
    local r = 255 * (1 - u)
    local g = 255 * u
    local b = 0

    return 0xFF000000
        + (math.floor(b) << 16)
        + (math.floor(g) << 8)
        + math.floor(r)
end
return val_to_color