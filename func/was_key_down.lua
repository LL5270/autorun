local reframework = reframework

local prev_key_states = {}

local function was_key_down(i)
    if i == nil then return false end
    
    local down = reframework:is_key_down(i)
    local prev = prev_key_states[i]
    prev_key_states[i] = down
    
    if prev == nil then return false end
    
    return down and not prev
end

return was_key_down