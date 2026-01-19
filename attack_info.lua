local sdk = sdk
local imgui = imgui
local re = re
local json = json
local reframework = reframework

local CONFIG_PATH = "attack_info.json"
local SAVE_DELAY = 0.5
local F2_KEY = 0x71

local Config = {}
local Utils = {}
local GameData = {}
local ComboWindow = {}
local UI = {}

-----------------------------------------------------------------------------
-- Config
-----------------------------------------------------------------------------
Config.settings = {
    toggle_all = true,
    toggle_p1 = true,
    toggle_p2 = true,
    toggle_minimal_view = true,
    toggle_minimal_view_p1 = true,
    toggle_minimal_view_p2 = true,  
}

function Config.load()
    local loaded_settings = json.load_file(CONFIG_PATH)
    if loaded_settings then
        for k, v in pairs(loaded_settings) do Config.settings[k] = v end
    else
        Config.save()
    end
end

function Config.save()
    json.dump_file(CONFIG_PATH, Config.settings)
end

-----------------------------------------------------------------------------
-- Utils
-----------------------------------------------------------------------------
function Utils.deep_copy(original)
    if type(original) ~= 'table' then return original end
    local copy = {}
    for key, value in pairs(original) do copy[key] = Utils.deep_copy(value) end
    return copy
end

function Utils.bitand(a, b)
    local result, bitval = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + bitval end
        bitval, a, b = bitval * 2, math.floor(a / 2), math.floor(b / 2)
    end
    return result
end

-----------------------------------------------------------------------------
-- GameData
-----------------------------------------------------------------------------
GameData.TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager")
GameData.gBattle = sdk.find_type_definition("gBattle")
GameData.PlayerField = GameData.gBattle:get_field("Player")
GameData.TeamField = GameData.gBattle:get_field("Team")

function GameData.get_sdk_pointers()
    local sPlayer = GameData.PlayerField:get_data()
    if not sPlayer then return nil, nil, nil end
    local sTeam = GameData.TeamField:get_data()
    return sPlayer, sPlayer.mcPlayer, sTeam and sTeam.mcTeam or nil
end

function GameData.map_player_data(player_index, cPlayer, cTeam)
    local player = cPlayer[player_index]
    if not player then return {} end
    local team = cTeam and cTeam[player_index] or nil
    
    local data = {}
    data.hp_current = player.vital_new or 0
    data.dir = Utils.bitand(player.BitValue or 0, 128) == 128
    data.drive_adjusted = (player.incapacitated) and (player.focus_new - 60000) or player.focus_new
    data.super = team and team.mSuperGauge or 0
    data.combo_count = team and team.mComboCount or 0
    data.death_count = team and team.mDeathCount or 0
    data.pos_x = player.pos and (player.pos.x.v / 65536.0) or 0
    data.gap = (player.vs_distance and player.vs_distance.v or 0) / 65536.0
    
    data.advantage = 0
    if GameData.TrainingManager and GameData.TrainingManager._tCommon then
        local snap = GameData.TrainingManager._tCommon.SnapShotDatas
        if snap and snap[0] then
            local meter = snap[0]._DisplayData.FrameMeterSSData.MeterDatas
            if meter and meter[player_index] then
                local stun_str = string.gsub(meter[player_index].StunFrame or "0", "F", "")
                data.advantage = tonumber(stun_str) or 0
            end
        end
    end
    
    return data
end

-----------------------------------------------------------------------------
-- ComboWindow Logic
-----------------------------------------------------------------------------
ComboWindow.player_states = {
    [0] = { started = false, finished = false, attacker = 0, start = {}, finish = {} },
    [1] = { started = false, finished = false, attacker = 1, start = {}, finish = {} },
}
ComboWindow.p1_prev, ComboWindow.p2_prev = {}, {}

function ComboWindow.update_state(p1, p2)
    for i = 0, 1 do
        local state = ComboWindow.player_states[i]
        local atk, def = (i == 0 and p1 or p2), (i == 0 and p2 or p1)
        local def_prev = (i == 0 and ComboWindow.p2_prev or ComboWindow.p1_prev)

        if not state.started and atk.combo_count > 0 then
            state.started, state.finished = true, false
            state.start = { p1 = Utils.deep_copy(ComboWindow.p1_prev), p2 = Utils.deep_copy(ComboWindow.p2_prev) }
        end

        if state.started then
            state.finish = { p1 = Utils.deep_copy(p1), p2 = Utils.deep_copy(p2) }
            if atk.combo_count == 0 or def.death_count ~= def_prev.death_count then
                state.finished, state.started = true, false
            end
        end
    end
    ComboWindow.p1_prev, ComboWindow.p2_prev = p1, p2
end

-----------------------------------------------------------------------------
-- UI Rendering
-----------------------------------------------------------------------------
UI.prev_key_states = {}
UI.combo_window_fixed_width = 150
UI.save_pending = false
UI.save_timer = 0
UI.key_ready = false

function UI.was_key_down(i)
    local down = reframework:is_key_down(i)
    local prev = UI.prev_key_states[i]
    UI.prev_key_states[i] = down
    return down and not prev
end

function UI.hotkey_handler()
	if UI.was_key_down(F2_KEY) then
		Config.settings.toggle_all = not Config.settings.toggle_all
		UI.mark_for_save()
	end
end

function UI.mark_for_save()
	UI.save_pending = true
	UI.save_timer = SAVE_DELAY
end

function UI.save_handler()
    if UI.save_pending then
        UI.save_timer = UI.save_timer - (1.0 / 60.0)
        if UI.save_timer <= 0 then
            Config.save()
        end
    end
end

function UI.color(val)
    if val > 0 then imgui.text_colored(string.format("%.0f", val), 0xFF00FF00)
    elseif val < 0 then imgui.text_colored(string.format("%.0f", val), 0xFFDDF527)
    else imgui.text("") end
end

function UI.render_columns(start_idx, p1_drv, p1_sup, p2_drv, p2_sup, p1_cry, p2_cry, adv, gap, is_diff)
    imgui.table_set_column_index(start_idx)
    if is_diff then UI.color(p1_drv) else imgui.text(p1_drv == 0 and "" or tostring(p1_drv)) end
    imgui.table_set_column_index(start_idx + 1)
    if is_diff then UI.color(p1_sup) else imgui.text(p1_sup == 0 and "" or tostring(p1_sup)) end
    imgui.table_set_column_index(start_idx + 2)
    if is_diff then UI.color(p2_drv) else imgui.text(p2_drv == 0 and "" or tostring(p2_drv)) end
    imgui.table_set_column_index(start_idx + 3)
    if is_diff then UI.color(p2_sup) else imgui.text(p2_sup == 0 and "" or tostring(p2_sup)) end
    imgui.table_set_column_index(start_idx + 4)
    if is_diff then UI.color(p1_cry) else imgui.text(p1_cry == 0 and "" or string.format("%.0f", p1_cry)) end
    imgui.table_set_column_index(start_idx + 5)
    if is_diff then UI.color(p2_cry) else imgui.text(p2_cry == 0 and "" or string.format("%.0f", p2_cry)) end
    imgui.table_set_column_index(start_idx + 6)
    imgui.text(adv == 0 and "" or tostring(adv))
    imgui.table_set_column_index(start_idx + 7)
    if is_diff then UI.color(gap) else imgui.text(gap == 0 and "" or string.format("%.0f", gap)) end
end

function UI.render_combo_window_table(state)
    local is_p1 = state.attacker == 0
    if is_p1 then
        min_view = Config.settings.toggle_minimal_view_p1
    else
        min_view = Config.settings.toggle_minimal_view_p2
    end
    local minimal_view = min_view or Config.settings.toggle_minimal_view
        
    
    if imgui.begin_table("combo_table_p" .. tostring(state.attacker + 1), 10, 8192 | 64) then
        imgui.table_setup_column("", 18, 50)
        imgui.table_setup_column("Damage", 18, 0)
        imgui.table_setup_column("P1Drive", 18, 0)
        imgui.table_setup_column("P1Super", 18, 0)
        imgui.table_setup_column("P2Drive", 18, 0)
        imgui.table_setup_column("P2Super", 18, 0)
        imgui.table_setup_column("P1Carry", 18, 0)
        imgui.table_setup_column("P2Carry", 18, 0)
        imgui.table_setup_column("Adv", 18, 0)
        imgui.table_setup_column("Gap", 18, 0)
        imgui.table_headers_row()
        imgui.table_next_row()

        local t_hp = is_p1 and (state.start.p2.hp_current - state.finish.p2.hp_current) or (state.start.p1.hp_current - state.finish.p1.hp_current)
        local t_p1_drv = state.finish.p1.drive_adjusted - state.start.p1.drive_adjusted
        local t_p1_sup = state.finish.p1.super - state.start.p1.super
        local t_p2_drv = state.finish.p2.drive_adjusted - state.start.p2.drive_adjusted
        local t_p2_sup = state.finish.p2.super - state.start.p2.super
                
        local t_p1_carry, t_p2_carry = 0, 0
        local cur_dir = (state.attacker == 0) and state.finish.p1.dir or state.finish.p2.dir

        if state.attacker == 0 then
            t_p1_carry = math.abs(state.finish.p1.pos_x - state.start.p1.pos_x)
            t_p2_carry = math.abs(state.start.p2.pos_x - state.finish.p2.pos_x)
        else
            t_p1_carry = math.abs(state.start.p1.pos_x - state.finish.p1.pos_x)
            t_p2_carry = math.abs(state.finish.p2.pos_x - state.start.p2.pos_x)
        end

        if not minimal_view then
            imgui.table_set_column_index(0); imgui.text("Start")
            imgui.table_set_column_index(1); imgui.text(tostring(is_p1 and state.start.p2.hp_current or state.start.p1.hp_current))
            UI.render_columns(2, state.start.p1.drive_adjusted, state.start.p1.super, state.start.p2.drive_adjusted, state.start.p2.super, state.start.p1.pos_x, state.start.p2.pos_x, 0, 0, false)
            imgui.table_next_row()

            imgui.table_set_column_index(0)
            if state.finished then imgui.text("End") else imgui.text("Current") end
            imgui.table_set_column_index(1)
            if state.finished then imgui.text(tostring(is_p1 and state.finish.p2.hp_current or state.finish.p1.hp_current)) else imgui.text("") end
            UI.render_columns(2, state.finish.p1.drive_adjusted, state.finish.p1.super, state.finish.p2.drive_adjusted, state.finish.p2.super, state.finish.p1.pos_x, state.finish.p2.pos_x, 0, 0, false)
        end
        
        local btn_lbl = string.format("Total##%d", state.attacker)
        imgui.table_next_row()
        imgui.table_set_column_index(0)
        if imgui.button(btn_lbl) then
            if state.attacker == 0 then
                Config.settings.toggle_minimal_view_p1 = not Config.settings.toggle_minimal_view_p1
            else 
                Config.settings.toggle_minimal_view_p2 = not Config.settings.toggle_minimal_view_p2
            end
            UI.mark_for_save()
        end
        imgui.table_set_column_index(1)
        UI.color(t_hp)
        UI.render_columns(2, t_p1_drv, t_p1_sup, t_p2_drv, t_p2_sup, t_p1_carry, t_p2_carry, state.finish.p1.advantage, state.finish.p1.gap, true)
        imgui.end_table()
    end
end

function UI.render_windows()
    if not Config.settings.toggle_all then return end
    local display = imgui.get_display_size()
    local center_x, window_y = display.x * 0.5, display.y * 0.004
    imgui.push_font(imgui.load_font(nil, 23))

    if Config.settings.toggle_p1 then
        local state = ComboWindow.player_states[0]
        if state.started or state.finished then
            imgui.set_next_window_pos(center_x - UI.combo_window_fixed_width, window_y, 1 << 1)
            imgui.set_next_window_size(UI.combo_window_fixed_width, 0, 1 << 1)
            if imgui.begin_window("P1 Current Combo", true, 1|8|32) then
                UI.render_combo_window_table(state)
                imgui.end_window()
            end
        end
    end

    if Config.settings.toggle_p2 then
        local state = ComboWindow.player_states[1]
        if state.started or state.finished then
            imgui.set_next_window_pos(center_x, window_y, 1 << 1)
            imgui.set_next_window_size(UI.combo_window_fixed_width, 0, 1 << 1)
            if imgui.begin_window("P2 Current Combo", true, 1|8|32) then
                UI.render_combo_window_table(state)
                imgui.end_window()
            end
        end
    end
    imgui.pop_font()
end

function UI.render_settings()
    if UI.was_key_down(F2_KEY) then
        Config.settings.toggle_all = not Config.settings.toggle_all
        Config.save()
    end
    if imgui.tree_node("Attack Info") then
        local changed = false
        changed, Config.settings.toggle_all = imgui.checkbox("Toggle All (F2)", Config.settings.toggle_all)
        if changed then UI.mark_for_save() end
        changed, Config.settings.toggle_p1 = imgui.checkbox("Show P1", Config.settings.toggle_p1)
        if changed then UI.mark_for_save() end
        imgui.same_line(); changed, Config.settings.toggle_p2 = imgui.checkbox("Show P2", Config.settings.toggle_p2)
        if changed then UI.mark_for_save() end
        imgui.text("Minimal View")
        changed, Config.settings.toggle_minimal_view_p1 = imgui.checkbox("P1", Config.settings.toggle_minimal_view_p1)
        if changed then UI.mark_for_save() end
        imgui.same_line()
        changed, Config.settings.toggle_minimal_view_p2 = imgui.checkbox("P2", Config.settings.toggle_minimal_view_p2)
        if changed then UI.mark_for_save() end
        imgui.tree_pop()
    end
end

function UI.key_handler()
    if not UI.key_ready and not reframework:is_key_down(F2_KEY) then 
        UI.key_ready = true
        return
    elseif UI.key_ready and reframework:is_key_down(F2_KEY) then
        Config.settings.toggle_all = not Config.settings.toggle_all
        UI.mark_for_save()
    end
end

-----------------------------------------------------------------------------
-- Main
-----------------------------------------------------------------------------
re.on_draw_ui(function()
    UI.render_settings()
end)

re.on_frame(function()
    local sPlayer, cPlayer, cTeam = GameData.get_sdk_pointers()
    if sPlayer and sPlayer.prev_no_push_bit ~= 0 then
        local p1 = GameData.map_player_data(0, cPlayer, cTeam)
        local p2 = GameData.map_player_data(1, cPlayer, cTeam)
        UI.hotkey_handler()
        ComboWindow.update_state(p1, p2)
        UI.render_windows()
        UI.save_handler()
    end
end)

Config.load()