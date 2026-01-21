-- Usage
-- local hotkey_fn = hotkey(some_function(), {keycodes.CONTROL, keycodes.F7}, true)
-- re.on_frame(function() hotkey_fn() end)

local reframework = reframework
local function hotkey(f, keys, hold_mode)
    if not f or not keys or #keys == 0 then return end
    local self = {}
    self.keys = keys
    self.f = f
    self.hold_mode = hold_mode or false
    self.was_pressed = false
    
    local function check_key(key)
        if not key then return false end
        return reframework:is_key_down(key)
    end
    
    local function all_keys_pressed()
        for _, key in ipairs(self.keys) do
            if not check_key(key) then return false end
        end
        return true
    end
    
    return function()
        local is_pressed = all_keys_pressed()
        if self.hold_mode then
            if is_pressed then self.f() end
        elseif is_pressed and not self.was_pressed then self.f() end
        self.was_pressed = is_pressed
    end
end
return hotkey