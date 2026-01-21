-- Config file handler
-- Usage: config(path, settings, init_load)
-- path: path to config file - default is (script_name).json
-- settings: table of settings
-- init_load: load settings on init, default true

local json = json
local fs = fs

local function get_default_path()
    local traceback = debug.traceback(nil, 3)
    local filename = traceback:match("([^\\/:]+)%.lua")
    return filename and filename .. ".json" or "config.json"
end

local function file_exists(path)
    if not path then return false end
    local f = io.open(path, "r")
    if f then
        io.close(f)
        return true
    end
    return false
end

local function is_empty(t)
    return not t or next(t) == nil
end

local function config(path, settings, init_load)
    local self = {
        path = path or get_default_path(),
        settings = settings or {}
    }

    function self.save()
        if not self.path or is_empty(self.settings) then return false end
        return json.dump_file(self.path, self.settings)
    end
    
    function self.load(preserve_existing)
        if not file_exists(self.path) then return false end
        
        local loaded = json.load_file(self.path)
        if is_empty(loaded) then return false end
        
        for k, v in pairs(loaded) do
            if not (preserve_existing and self.settings[k] ~= nil) then
                self.settings[k] = v
            end
        end
        return true
    end
    
    if init_load ~= false then
        self.load()
    end
    
    return self
end

return config