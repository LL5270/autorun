local json = json

function config_load(config_path)
    return json.load_file(CONFIG_PATH)
end

return config_load