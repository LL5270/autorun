-- Config file handler with nested table support and custom ticker notifications
-- Usage: local Config, settings = config(path, settings, init_load)
--   path: path to config file - default is (script_name).json
--   settings: table of settings
--   init_load: load settings on init, default true
--
-- Methods:
-- Config.add(key, val, table_name, show_ticker) Add single setting (top level table default)
-- Config.add(table, table_name, show_ticker) Add multiple settings
-- Config.remove(key, table_name, show_ticker) Remove single setting
-- Config.remove(table, table_name, show_ticker) Remove multiple settings
-- Config.save(show_ticker) Manually force immediate save
-- Config.load_all() Load all settings from file
-- Config.load(key, table_name) Load single setting
-- Config.get_table(table_name) Get reference to nested table

local json = json
local fs = fs
local re = re

local ticker_func = require("func/show_custom_ticker")

local function get_default_path()
    local traceback = debug.traceback(nil, 3)
    local filename = traceback:match("([^\\/:]+)%.lua")
    return filename and filename .. ".json" or "config.json"
end

local function file_exists(path)
    if not path then return false end
    local f = io.open(path, "r")
    if f then io.close(f) return true end
    return false
end

local function is_empty(t) return not t or next(t) == nil end

local function config(path, settings, init_load)
    local self = {
        path = path or get_default_path(),
        settings = settings or {},
        dirty = false,
        frame_counter = 0,
        last_save_frame = 0,
        save_throttle_frames = 300,
        changed_keys = {},
    }

    function self.show_save_ticker(changed_count)
        local message = string.format(
            "Config saved: %d setting%s changed",
            changed_count,
            changed_count == 1 and "" or "s"
        )
        
        ticker_func(message, 0.4, 8)
    end

    function self.save_now(show_ticker)
        if not self.path or is_empty(self.settings) then return false end
        
        local result = json.dump_file(self.path, self.settings)
        if result then 
            self.dirty = false
            self.last_save_frame = self.frame_counter
            
            local changed_count = 0
            for _ in pairs(self.changed_keys) do
                changed_count = changed_count + 1
            end
            
            if show_ticker and changed_count > 0 then
                self.show_save_ticker(changed_count)
            end
            
            self.changed_keys = {}
        end
        return result
    end

    function self.save(show_ticker)
        if not self.dirty then return false end
        
        local frames_since_last_save = self.frame_counter - self.last_save_frame
        
        if frames_since_last_save >= self.save_throttle_frames then
            return self.save_now(show_ticker)
        end
        
        if show_ticker then
            self.pending_ticker = true
        end
        
        return true
    end

    function self.get_table(table_name)
        if not table_name then return self.settings end
        
        if not self.settings[table_name] then
            self.settings[table_name] = {}
        elseif type(self.settings[table_name]) ~= 'table' then
            self.settings[table_name] = {}
        end
        return self.settings[table_name]
    end

    function self.add_one(k, v, table_name)
        if not (k and v ~= nil) then return false end
        
        local target = table_name and self.settings[table_name] or self.settings
        
        if table_name and not target then
            target = {}
            self.settings[table_name] = target
        end
        
        if target[k] ~= v then
            target[k] = v
            self.dirty = true
            
            local key_identifier = table_name and (table_name .. "." .. k) or k
            self.changed_keys[key_identifier] = true
            
            return true
        end
        return false
    end

    function self.add_many(t, table_name)
        if not t or is_empty(t) then return false end
        local changed = false
        for k, v in pairs(t) do
            if self.add_one(k, v, table_name) then
                changed = true
            end
        end
        return changed
    end

    function self.add(k_or_t, v_or_table, table_name_or_ticker, show_ticker)
        if not k_or_t then return false end
        local changed = false
        local actual_table_name = nil
        local actual_show_ticker = false
        
        if type(k_or_t) == 'table' then
            actual_table_name = type(v_or_table) == 'string' and v_or_table or nil
            actual_show_ticker = type(table_name_or_ticker) == 'boolean' and table_name_or_ticker or false
            changed = self.add_many(k_or_t, actual_table_name)
        elseif type(k_or_t) == 'string' and v_or_table ~= nil then
            actual_table_name = type(table_name_or_ticker) == 'string' and table_name_or_ticker or nil
            actual_show_ticker = type(show_ticker) == 'boolean' and show_ticker or false
            changed = self.add_one(k_or_t, v_or_table, actual_table_name)
        end
        
        if changed then return self.save(actual_show_ticker) end 
        return changed
    end

    function self.remove_one(k, table_name)
        local target = table_name and self.settings[table_name] or self.settings
        
        if not k or not target or target[k] == nil then return false end
        
        target[k] = nil
        self.dirty = true
        
        local key_identifier = table_name and (table_name .. "." .. k) or k
        self.changed_keys[key_identifier] = true
        
        return true
    end

    function self.remove_many(t, table_name)
        if not t or is_empty(t) then return false end
        local changed = false
        for _, k in ipairs(t) do
            if self.remove_one(k, table_name) then
                changed = true
            end
        end
        return changed
    end

    function self.remove(k_or_t, table_name_or_ticker, show_ticker)
        if not k_or_t then return false end
        
        local changed = false
        local actual_table_name = nil
        local actual_show_ticker = false
        
        if type(k_or_t) == 'table' then
            actual_table_name = type(table_name_or_ticker) == 'string' and table_name_or_ticker or nil
            actual_show_ticker = type(show_ticker) == 'boolean' and show_ticker or false
            changed = self.remove_many(k_or_t, actual_table_name)
        elseif type(k_or_t) == 'string' then
            actual_table_name = type(table_name_or_ticker) == 'string' and table_name_or_ticker or nil
            actual_show_ticker = type(show_ticker) == 'boolean' and show_ticker or false
            changed = self.remove_one(k_or_t, actual_table_name)
        end
        
        if changed then
            return self.save(actual_show_ticker)
        end
        return changed
    end
    
    function self.load_all()
        if not file_exists(self.path) then return false end
        return json.load_file(self.path)
    end

    function self.load(k, table_name)
        if not k or not file_exists(self.path) then return false end
        local loaded = json.load_file(self.path)
        if not loaded then return false end
        
        local source = table_name and loaded[table_name] or loaded
        local target = table_name and (self.settings[table_name] or {}) or self.settings
        
        if source and source[k] ~= target[k] then
            target[k] = source[k]
            return true
        end
        return false
    end

    if init_load ~= false then self.settings = self.load_all() or {} end
    re.on_script_reset(function() if self.dirty then self.save_now(false) end end)
    re.on_config_save(function() if self.dirty then self.save_now(false) end end)
    re.on_frame(function()
        self.frame_counter = self.frame_counter + 1
        if self.dirty then
            local frames_since_last_save = self.frame_counter - self.last_save_frame
            if frames_since_last_save >= self.save_throttle_frames then
                self.save_now(self.pending_ticker or false)
                self.pending_ticker = false
            end
        end
    end)
    
    return self, self.settings
end

return config