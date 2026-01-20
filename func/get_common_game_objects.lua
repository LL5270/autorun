local function get_common_game_objects()
    local objects = {
        ["gBattle"] = {},
        ["PlayerField"] = {},
        ["TeamField"] = {},
        ["TrainingManager"] = {},
    }
    
    objects.gBattle = sdk.find_type_definition("gBattle")
    objects.PlayerField = GameData.gBattle:get_field("Player")
    objects.TeamField = GameData.gBattle:get_field("Team")
    objects.TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager") or {}

    return objects
end

return get_common_game_objects