local json = json

local function config_save(config_path, config_settings)
    return json.dump_file(config_path, config_settings)
end

return config_save