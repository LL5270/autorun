-- Usage:
---- local hotkey = require("func/hotkey")
---- hotkey(some_function, {"CONTROL", "alt", "X"})
---- hotkey(some_function, {0x11, 0x12, 0x58})

local reframework = reframework

local keycodes = require("func/keycodes")

local function hotkey(f, _keys)
    if not f or type(f) ~= "function" then return false end
    if not _keys or type(_keys) ~= "table" or #_keys == 0 then return false end

    local self = {}
    self.keys = {}
    self.f = f
    self.key_ready = true
    
    for _, k in ipairs(_keys) do
        local key_str = string.upper(tostring(k))
        if keycodes[key_str] then table.insert(self.keys, keycodes[key_str])
        else for _k, _v in pairs(keycodes) do
                if _v == key_str then table.insert(self.keys, _v) break end
            end
        end
    end

    if #self.keys == 0 then return false end

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