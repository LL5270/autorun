local sdk = sdk

local function fighter_settings()
    local this = {}
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    local data = tm._tData
    if data then
        local pds = data.SelectMenu.PlayerDatas
        this.fighter_id = pds[0].FighterID
        this.color_id = pds[0].ColorID
        this.cosutume_id = pds[0].CosutumeID
        this.input_type = pds[0].InputType
        this.negative_edge = pds[0].NegativeEdge
        this.low_stick_sensitivity = pds[0].LowStickSensitivity
        this.key_config_preset = pds[0].KeyConfigPreset
    end
    return this
end

-- local function fighter_settings()
--     local this = {}
--     local tm = sdk.get_managed_singleton("app.training.TrainingManager")
--     local tdm = sdk.get_managed_singleton("app.TemporarilyDataManager")
--     local _temp_man = tdm.Data
--     this.tm_state = tm._TrainingState
--     this.fighter_id = _temp_man._MatchingFighterId
--     this.theme_id = _temp_man.ThemeId
--     this.comment_id = _temp_man.CommentId
--     this.comment_option = _temp_man.CommentOption
--     this.pose_id = _temp_man.AvatarPose
--     local miscData = _temp_man.MatchingFighterSetting:ToArray()
--     for _, v in pairs(miscData) do
--         if v.FighterId == this.fighter_id then
--             this.title_id = v.TitleId
--             this.input_type = v.MatchingFighterInputStyle
--         end
--     end
    
--     return this
-- end

return fighter_settings