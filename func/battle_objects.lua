local function battle_objects()
    local this = {}
    
    this.gBattle = sdk.find_type_definition("gBattle")
    this.PlayerField = this.gBattle:get_field("Player")
    this.TeamField = this.gBattle:get_field("Team")

    this.TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager")
    this.TempManager = sdk.get_managed_singleton("app.TemporarilyDataManager")

    -- this.sTeam = function() return this.TeamField:get_data() or {} end
    -- this.sPlayer = function() return this.PlayerField:get_data() or {} end

    return this
end

return battle_objects