local sdk = sdk
local imgui = imgui
local re = re
local reframework = reframework

local F2_KEY = 0x71

local Utils = {}
local GameData = {}
local ComboWindow = {}
local UI = {}

-----------------------------------------------------------------------------
-- Utils
-----------------------------------------------------------------------------
function Utils.deep_copy(original)
    if type(original) ~= 'table' then return original end
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = Utils.deep_copy(value)
    end
    return copy
end

function Utils.bitand(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return result
end

-----------------------------------------------------------------------------
-- GameData
-----------------------------------------------------------------------------
GameData.char_id_table = {
    [0] = "",
    [1] = "Ryu", 
    [2] = "Luke", 
    [3] = "Kimberly", 
    [4] = "ChunLi", 
    [5] = "Manon", 
    [6] = "Zangief", 
    [7] = "JP", 
    [8] = "Dhalsim", 
    [9] = "Cammy", 
    [10] = "Ken", 
    [11] = "DeeJay", 
    [12] = "Lily", 
    [13] = "AKI", 
    [14] = "Rashid", 
    [15] = "Blanka", 
    [16] = "Juri", 
    [17] = "Marisa", 
    [18] = "Guile", 
    [19] = "Ed",
    [20] = "EHonda", 
    [21] = "Jamie", 
    [22] = "Akuma", 
    [26] = "MBison", 
    [27] = "Terry",
    [28] = "Mai",
    [29] = "Elena",
    [25] = "Sagat",
    [30] = "CViper"
}

GameData.TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager")
GameData.gBattle = sdk.find_type_definition("gBattle")
GameData.PlayerField = GameData.gBattle:get_field("Player")
GameData.TeamField = GameData.gBattle:get_field("Team")
GameData.StatsField = GameData.gBattle:get_field("Stats")
GameData.ConfigField = GameData.gBattle:get_field("Config")
GameData.RoundField = GameData.gBattle:get_field("Round")

function GameData.get_sdk_pointers()
    local sPlayer = GameData.PlayerField:get_data()
    if not sPlayer then return nil, nil, nil end
    
    local cPlayer = sPlayer.mcPlayer
    local sTeam = GameData.TeamField:get_data()
    local cTeam = sTeam and sTeam.mcTeam or nil
    
    return sPlayer, cPlayer, cTeam
end

function GameData.map_match_data()
    local battle_config = GameData.ConfigField:get_data()
    local battle_round = GameData.RoundField:get_data()
    
    if not battle_config or not battle_round then return {} end

    local data = {}
    data.game_mode = battle_config._GameMode or nil
    data.round = battle_round.RoundNo or nil
    data.timer = {}
    data.timer.seconds = battle_round.play_timer or 0
    data.timer.extra_frames = battle_round.play_timer_ms or 0
    data.timer.total_frames_remaining = ((data.timer.seconds * 60) + (data.timer.extra_frames or 0)) or 0
    data.timer.seconds_remaining = (data.timer.total_frames_remaining / 60) or 0
    
    return data
end

function GameData.map_player_data(player_index, cPlayer, cTeam, frame_meter)
    local player = cPlayer[player_index]
    if not player then return {} end
    
    local sStats = GameData.StatsField:get_data()
    local stats = sStats and sStats.Info or {}
    local team = cTeam and cTeam[player_index] or nil
    
    local data = {}
    
    -- Action/Engine Data
    if player.mpActParam and player.mpActParam.ActionPart then
        data.char_id = player.mpActParam.ActionPart._CharaID
        local engine = player.mpActParam.ActionPart._Engine
        if engine then
            data.action_id = engine:get_ActionID()
            data.action_frame = engine:get_ActionFrame()
            data.end_frame = engine:get_ActionFrameNum()
            data.margin_frame = engine:get_MarginFrame()
            if engine.mParam and engine.mParam.action and engine.mParam.action.ActionFrame then
                data.main_frame = engine.mParam.action.ActionFrame.MainFrame
                data.follow_frame = engine.mParam.action.ActionFrame.FollowFrame
            end
        end
    end

    -- Frame Advantage Data
    if frame_meter then
        data.stun_frame = frame_meter.StunFrame
        local stun_frame_str = string.gsub(data.stun_frame or "0", "F", "")
        data.advantage = tonumber(stun_frame_str) or 0
    end
    
    -- Vitality/Drive/Super Data
    data.hp_cap = player.heal_new or 0
    data.hp_current = player.vital_new or 0
    data.hp_cooldown = player.healing_wait or 0
    data.dir = Utils.bitand(player.BitValue or 0, 128) == 128
    data.burnout = player.incapacitated or false
    data.drive = player.focus_new or 0
    data.drive_adjusted = data.burnout and (data.drive - 60000) or data.drive
    data.drive_cooldown = player.focus_wait or 0
    data.super = team and team.mSuperGauge or 0
    data.combo_damage = team and team.mComboDamage or 0
    data.combo_count = team and team.mComboCount or 0
    data.death_count = team and team.mDeathCount or 0
    
    -- Position Data
    data.gap = (player.vs_distance and player.vs_distance.v or 0) / 65536.0
    
    if player.pos and player.pos.x then
        data.pos_x = player.pos.x.v / 65536.0
        data.pos_y = player.pos.y.v / 65536.0
    else
        data.pos_x = 0
        data.pos_y = 0
    end
     
    -- Character selection
    data.char_id = data.char_id or 0
    data.char_name = GameData.char_id_table[data.char_id] or "Unknown"
    
    return data
end

function GameData.process_battle_info()
    local sPlayer, cPlayer, cTeam = GameData.get_sdk_pointers()
    if not sPlayer then return nil, nil, nil end

    local frame_meter = nil
    if GameData.TrainingManager then
        local tCommon = GameData.TrainingManager._tCommon
        if tCommon and tCommon.SnapShotDatas and tCommon.SnapShotDatas[0] then
            frame_meter = tCommon.SnapShotDatas[0]._DisplayData.FrameMeterSSData.MeterDatas
        end
    end

    local p1_data = GameData.map_player_data(0, cPlayer, cTeam, frame_meter and frame_meter[0] or nil)
    local p2_data = GameData.map_player_data(1, cPlayer, cTeam, frame_meter and frame_meter[1] or nil)
    local match_data = GameData.map_match_data()
    
    return p1_data, p2_data, match_data
end

-----------------------------------------------------------------------------
-- ComboWindow
-----------------------------------------------------------------------------
local function create_player_state(attacker_idx, defender_idx)
    return {
        started = false,
        finished = false,
        attacker = attacker_idx,
        defender = defender_idx,
        start = { p1 = {}, p2 = {}, match = {} },
        finish = { p1 = {}, p2 = {}, match = {} },
        p1_inputs = {},
        p2_inputs = {},
    }
end

ComboWindow.player_states = {
    [0] = create_player_state(0, 1),
    [1] = create_player_state(1, 0),
}

ComboWindow.p1_prev = {}
ComboWindow.p2_prev = {}
ComboWindow.match_prev = {}
ComboWindow.show_combo_windows = true
ComboWindow.show_p1_combo_window = true
ComboWindow.show_p2_combo_window = true
ComboWindow.show_p1_total_only = false
ComboWindow.show_p2_total_only = false

function ComboWindow.clear_combo_windows()
    ComboWindow.p1_prev = {}
    ComboWindow.p2_prev = {}
    
    for i = 0, 1 do
        ComboWindow.player_states[i].started = false
        ComboWindow.player_states[i].finished = false
    end
end

local function adjust_drive_for_cooldown(state, p1, p2, attacker_idx)
    if attacker_idx == 0 then
        if p1.drive_cooldown > 200 then
            state.start.p1.drive_adjusted = state.start.p1.drive_adjusted + 10000
        elseif p1.drive_cooldown <= -120 then
            state.start.p1.drive_adjusted = state.start.p1.drive_adjusted + 20000
        end
    elseif attacker_idx == 1 then
        if p2.drive_cooldown > 200 then
            state.start.p2.drive_adjusted = state.start.p2.drive_adjusted + 10000
        elseif p2.drive_cooldown <= -120 then
            state.start.p2.drive_adjusted = state.start.p2.drive_adjusted + 20000
        end
    end
end

function ComboWindow.on_combo_start(p1, p2, match_data, attacker_idx, defender_idx)
    local state = ComboWindow.player_states[attacker_idx]
    
    state.attacker = attacker_idx
    state.defender = defender_idx
    state.started = true
    state.finished = false
    state.p1_inputs = {}
    state.p2_inputs = {}
    
    state.start.p1 = Utils.deep_copy(ComboWindow.p1_prev)
    state.start.p2 = Utils.deep_copy(ComboWindow.p2_prev)
    state.start.match = Utils.deep_copy(ComboWindow.match_prev)
    
    adjust_drive_for_cooldown(state, p1, p2, attacker_idx)
end

function ComboWindow.track_inputs(p1, p2, player_idx)
    local state = ComboWindow.player_states[player_idx]
    
    if state.p1_inputs[#state.p1_inputs] ~= p1.action_id then
        table.insert(state.p1_inputs, p1.action_id)
    end
    
    if state.p2_inputs[#state.p2_inputs] ~= p2.action_id then
        table.insert(state.p2_inputs, p2.action_id)
    end
end

function ComboWindow.on_combo_update(p1, p2, match_data, player_idx)
    local state = ComboWindow.player_states[player_idx]
    
    state.finish.p1 = Utils.deep_copy(p1)
    state.finish.p1.inputs = state.p1_inputs
    state.finish.p2 = Utils.deep_copy(p2)
    state.finish.p2.inputs = state.p2_inputs
    state.finish.match = Utils.deep_copy(match_data)
end

function ComboWindow.on_combo_finish(p1, p2, match_data, player_idx)
    local state = ComboWindow.player_states[player_idx]
    
    ComboWindow.on_combo_update(p1, p2, match_data, player_idx)
    state.finished = true
    state.started = false
    
    state.p1_inputs = {}
    state.p2_inputs = {}
end

function ComboWindow.check_started(p1, p2, match_data)
    for i = 0, 1 do
        local state = ComboWindow.player_states[i]
        local player = (i == 0) and p1 or p2
        local opponent = (i == 0) and p2 or p1
        
        if not state.started and player.combo_count > 0 and opponent.hp_current > 0 then
            ComboWindow.on_combo_start(p1, p2, match_data, i, 1 - i)
        end
    end
end

function ComboWindow.check_finished(p1, p2, match_data)
    for i = 0, 1 do
        local state = ComboWindow.player_states[i]
        
        if state.started then
            local player = (i == 0) and p1 or p2
            local opponent = (i == 0) and p2 or p1
            local opponent_prev = (i == 0) and ComboWindow.p2_prev or ComboWindow.p1_prev
            
            local is_finished = opponent.death_count ~= opponent_prev.death_count
            local is_knockdown = player.combo_count == 0
            
            if is_finished or is_knockdown then
                ComboWindow.on_combo_finish(p1, p2, match_data, i)
            else
                ComboWindow.on_combo_update(p1, p2, match_data, i)
            end
        end
    end
end

function ComboWindow.update_state(p1, p2, match_data)
    ComboWindow.check_started(p1, p2, match_data)
    
    for i = 0, 1 do
        local state = ComboWindow.player_states[i]
        if state.started and not state.finished then
            ComboWindow.track_inputs(p1, p2, i)
        end
    end
    
    ComboWindow.check_finished(p1, p2, match_data)
    
    -- Update previous frame data
    ComboWindow.p1_prev = p1
    ComboWindow.p2_prev = p2
    ComboWindow.match_prev = match_data
end

-----------------------------------------------------------------------------
-- UI
-----------------------------------------------------------------------------
UI.prev_key_states = {}
UI.display_size = imgui.get_display_size()
UI.center_x = UI.display_size.x * 0.5
UI.combo_window_width = 1

function UI.was_key_down(i)
    local down = reframework:is_key_down(i)
    local prev = UI.prev_key_states[i] or false
    UI.prev_key_states[i] = down
    return down and not prev
end

function UI.color(val)
    if val > 0 then
        imgui.text_colored(string.format("%.0f", val), 0xFF00FF00)
    elseif val < 0 then
        imgui.text_colored(string.format("%.0f", val), 0xFFDDF527)
    else
        imgui.text("")
    end
end

function UI.render_combo_window_columns(start_idx, p1_drive, p1_super, p2_drive, p2_super, p1_pos, p2_pos, adv, gap, is_diff)
    imgui.table_set_column_index(start_idx)
    if is_diff then UI.color(p1_drive or 0) else imgui.text(p1_drive == 0 and "" or tostring(p1_drive or "")) end

    imgui.table_set_column_index(start_idx + 1)
    if is_diff then UI.color(p1_super or 0) else imgui.text(p1_super == 0 and "" or tostring(p1_super or "")) end

    imgui.table_set_column_index(start_idx + 2)
    if is_diff then UI.color(p2_drive or 0) else imgui.text(p2_drive == 0 and "" or tostring(p2_drive or "")) end

    imgui.table_set_column_index(start_idx + 3)
    if is_diff then UI.color(p2_super or 0) else imgui.text(p2_super == 0 and "" or tostring(p2_super or "")) end

    imgui.table_set_column_index(start_idx + 4)
    if is_diff then 
        UI.color(p1_pos or 0) 
    else 
        imgui.text(p1_pos == 0 and "" or string.format("%.0f", p1_pos or ""))
    end

    imgui.table_set_column_index(start_idx + 5)
    if is_diff then
        UI.color(p2_pos or 0)
    else 
        imgui.text(p2_pos == 0 and "" or string.format("%.0f", p2_pos or ""))
    end
    
    imgui.table_set_column_index(start_idx + 6)
    imgui.text(adv == 0 and "" or tostring(adv or ""))

    imgui.table_set_column_index(start_idx + 7)
    if is_diff then UI.color(gap or 0) else imgui.text(gap == 0 and "" or tostring(gap or "")) end
end

function UI.render_combo_window_row(label, hp, p1_drive, p1_super, p2_drive, p2_super, p1_pos, p2_pos, adv, gap, is_diff)
    imgui.table_next_row()
    imgui.table_set_column_index(0); imgui.text(label)

    imgui.table_set_column_index(1)
    if is_diff then UI.color(hp or 0) else imgui.text(hp == 0 and "" or tostring(hp or "")) end

    UI.render_combo_window_columns(2, p1_drive, p1_super, p2_drive, p2_super, p1_pos, p2_pos, adv, gap, is_diff)
end

function UI.render_combo_window_table(state)
    if imgui.begin_table("current_combo_table", 10) then
        local p1_col_name, p2_col_name = "P1 (R)", "P2 (R)"
        if state.attacker == 0 and state.start and state.start.p1.dir then p1_col_name = "P1 (L)" end
        if state.attacker == 1 and state.start and state.start.p2.dir then p2_col_name = "P2 (L)" end

        if state.attacker == 0 then imgui.table_setup_column(p1_col_name, nil, 1)
        elseif state.attacker == 1 then imgui.table_setup_column(p2_col_name, nil, 1)
        else imgui.table_setup_column("", nil, 1) end

        imgui.table_setup_column("Damage", nil, 1)
        imgui.table_setup_column("P1Drive", nil, 1)
        imgui.table_setup_column("P1Super", nil, 1)
        imgui.table_setup_column("P2Drive", nil, 1)
        imgui.table_setup_column("P2Super", nil, 1)
        imgui.table_setup_column("P1Carry", nil, 1)
        imgui.table_setup_column("P2Carry", nil, 1)
        imgui.table_setup_column("Adv", nil, 1)
        imgui.table_setup_column("Gap", nil, 1)
        imgui.table_headers_row()
        
        -- Start Row
        local show_total_only = (state.attacker == 0) and ComboWindow.show_p1_total_only or ComboWindow.show_p2_total_only
        
        if not show_total_only then
            local s_hp = (state.attacker == 0) and state.start.p2.hp_current or state.start.p1.hp_current
            UI.render_combo_window_row("Start", s_hp, 
                state.start.p1.drive_adjusted, state.start.p1.super,
                state.start.p2.drive_adjusted, state.start.p2.super,
                state.start.p1.pos_x, state.start.p2.pos_x, nil, nil, false)
        end

        local f_hp = (state.attacker == 0) and state.finish.p2.hp_current or state.finish.p1.hp_current

        local t_hp = 0
        if state.attacker == 0 then
            t_hp = (state.start.p2.hp_current or 0) - (state.finish.p2.hp_current or 0)
        elseif state.attacker == 1 then
            t_hp = (state.start.p1.hp_current or 0) - (state.finish.p1.hp_current or 0)
        end

        local t_p1_drive = (state.finish.p1.drive_adjusted or 0) - (state.start.p1.drive_adjusted or 0)
        local t_p1_super = (state.finish.p1.super or 0) - (state.start.p1.super or 0)
        local t_p2_drive = (state.finish.p2.drive_adjusted or 0) - (state.start.p2.drive_adjusted or 0)
        local t_p2_super = (state.finish.p2.super or 0) - (state.start.p2.super or 0)
        
        local t_p1_carry = 0
        if state.attacker == 0 and state.finish.p1.dir then
            t_p1_carry = (state.finish.p1.pos_x or 0) - (state.start.p1.pos_x or 0)
        elseif state.attacker == 0 and not state.finish.p1.dir then
            t_p1_carry = (state.start.p1.pos_x or 0) - (state.finish.p1.pos_x or 0)
        elseif state.attacker == 1 and state.finish.p2.dir then
            t_p1_carry = (state.finish.p1.pos_x or 0) - (state.start.p1.pos_x or 0)
        elseif state.attacker == 1 and not state.finish.p2.dir then
            t_p1_carry = (state.start.p1.pos_x or 0) - (state.finish.p1.pos_x or 0)
        end


        local t_p2_carry = 0
        if state.attacker == 0 and state.finish.p1.dir then
            t_p2_carry = (state.finish.p2.pos_x or 0) - (state.start.p2.pos_x or 0)
        elseif state.attacker == 0 and not state.finish.p1.dir then
            t_p2_carry = (state.start.p2.pos_x or 0) - (state.finish.p2.pos_x or 0) 
        elseif state.attacker == 1 and state.finish.p2.dir then
            t_p2_carry = (state.finish.p2.pos_x or 0) - (state.start.p2.pos_x or 0)
        elseif state.attacker == 1 and not state.finish.p2.dir then
            t_p2_carry = (state.start.p2.pos_x or 0) - (state.finish.p2.pos_x or 0)
        end


        local t_adv = (state.attacker == 0) and state.finish.p1.advantage or state.finish.p2.advantage
        local t_gap = state.finish.p1.gap

        if not state.finished then
            UI.render_combo_window_row("Finish", t_hp, 
                t_p1_drive, t_p1_super,
                t_p2_drive, t_p2_super,
                t_p1_carry, t_p2_carry, t_adv, t_gap, true)
        elseif state.finished then
            if not show_total_only then
                UI.render_combo_window_row("Finish", f_hp, 
                    state.finish.p1.drive_adjusted, state.finish.p1.super,
                    state.finish.p2.drive_adjusted, state.finish.p2.super,
                    state.finish.p1.pos_x, state.finish.p2.pos_x, nil, nil, false)
            end
            UI.render_combo_window_row("Total", t_hp, 
                t_p1_drive, t_p1_super,
                t_p2_drive, t_p2_super,
                t_p1_carry, t_p2_carry, t_adv, t_gap, true)
        end
        imgui.end_table()
    end
end

function UI.render_p1_combo_window()
    if not ComboWindow.show_combo_windows then return end
    
    local window_width = UI.combo_window_width
    local center_x = UI.center_x
    local window_y = UI.display_size.y * .004
    local window_x = window_width - center_x
    
    imgui.set_next_window_pos(window_x, window_y, 0 << 1)
    imgui.set_next_window_size(window_width, 0, 0 << 1)
    
    imgui.begin_window("P1 Current Combo", true, 1|4|8)
    local state = ComboWindow.player_states[0]
    
    local window_pos = imgui.get_window_pos()
    local window_size = imgui.get_window_size()
    local mouse_pos = imgui.get_mouse()
    
    local is_mouse_over_window = (mouse_pos.x >= window_pos.x and mouse_pos.x <= window_pos.x + window_size.x and
                                   mouse_pos.y >= window_pos.y and mouse_pos.y <= window_pos.y + window_size.y)
    
    if is_mouse_over_window and imgui.is_mouse_clicked(0) then
        ComboWindow.show_p1_total_only = not ComboWindow.show_p1_total_only
    end
    
    if state.started or state.finished then
        UI.render_combo_window_table(state)
    else
        imgui.text("P1 Combo")
    end
    
    imgui.end_window()
end

function UI.render_p2_combo_window()
    if not ComboWindow.show_combo_windows then return end
    
    local window_width = UI.combo_window_width
    local center_x = UI.center_x
    local window_y = UI.display_size.y * 0.004
    local window_x = center_x
    
    imgui.set_next_window_pos(window_x, window_y, 0 << 1)
    imgui.set_next_window_size(window_width, 0, 0 << 1)
    
    imgui.begin_window("P2 Current Combo", true, 1|4|8)
    local state = ComboWindow.player_states[1]
    
    local window_pos = imgui.get_window_pos()
    local window_size = imgui.get_window_size()
    local mouse_pos = imgui.get_mouse()
    
    local is_mouse_over_window = (mouse_pos.x >= window_pos.x and mouse_pos.x <= window_pos.x + window_size.x and
                                   mouse_pos.y >= window_pos.y and mouse_pos.y <= window_pos.y + window_size.y)
    
    if is_mouse_over_window and imgui.is_mouse_clicked(0) then
        ComboWindow.show_p2_total_only = not ComboWindow.show_p2_total_only
    end
    
    if state.started or state.finished then
        UI.render_combo_window_table(state)
    else
        imgui.text("P2 Combo")
    end
    
    imgui.end_window()
end

function UI.render_windows()
    local window_font = imgui.load_font(nil, 20)
    imgui.push_font(window_font)
    
    if UI.was_key_down(F2_KEY) then
        ComboWindow.show_combo_windows = not ComboWindow.show_combo_windows
    end
    
    if ComboWindow.show_p1_combo_window and (ComboWindow.player_states[0].started or ComboWindow.player_states[0].finished) then
        UI.render_p1_combo_window()
    end
    if ComboWindow.show_p2_combo_window and (ComboWindow.player_states[1].started or ComboWindow.player_states[1].finished) then
        UI.render_p2_combo_window()
    end

    imgui.pop_font()
end

function UI.render_settings()
    if imgui.tree_node("Attack Info") then
        local changed = false
        
        imgui.text("Windows")
        changed, ComboWindow.show_combo_windows = imgui.checkbox("Toggle (F2)", ComboWindow.show_combo_windows)
        
        changed, ComboWindow.show_p1_combo_window = imgui.checkbox("Show P1", ComboWindow.show_p1_combo_window)
        imgui.same_line()
        changed, ComboWindow.show_p2_combo_window = imgui.checkbox("Show P2", ComboWindow.show_p2_combo_window)

        imgui.tree_pop()
    end
end

-----------------------------------------------------------------------------
-- Main
-----------------------------------------------------------------------------
re.on_draw_ui(function()
    UI.render_settings()
end)

re.on_frame(function()
    local sPlayer, _, _ = GameData.get_sdk_pointers()
    if not sPlayer then return end
    
    if sPlayer.prev_no_push_bit ~= 0 then
        local p1, p2, match_data = GameData.process_battle_info()
        if p1 and p2 then
            ComboWindow.update_state(p1, p2, match_data)
            UI.render_windows()
        end
    end
end)