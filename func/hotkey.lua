local reframework = reframework
local function hotkey(f, keys)
    if not f or type(f) ~= "function" then return false end
    if not keys or type(keys) ~= "table" or #keys == 0 then return false end
    
    local self = {}
    self.keys = keys
    self.f = f
    self.key_ready = true
    
    local function check_key(key)
        if not key then return false end
        local success, result = pcall(function() return reframework:is_key_down(key) end)
        if not success then return false end
        return result
    end
    
    if self.key_ready then
        for _, key in ipairs(self.keys) do
            if not check_key(key) then
                self.key_ready = true
                return true
            end
        end
        self.key_ready = false
    end
    
    if not self.key_ready then
        local success = pcall(self.f)
        if not success then return false end
    end
    
    return true
end

return hotkey