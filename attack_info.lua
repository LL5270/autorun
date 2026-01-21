local sdk = sdk
local imgui = imgui
local re = re
local json = json
local reframework = reframework

local CONFIG_PATH = "attack_info.json"
local SAVE_DELAY = 0.5
local LEFT_CLICK = 0x01
local RIGHT_CLICK = 0x02
local F2_KEY = 0x71

local Config = {}
local Utils = {}
local GameObjects = {}
local ComboData = {}
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

-------------------------
-- Utils
-------------------------

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

-------------------------
-- GameObjects
-------------------------

GameObjects.TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager")
GameObjects.gBattle = sdk.find_type_definition("gBattle")
GameObjects.PlayerField = GameObjects.gBattle:get_field("Player")
GameObjects.TeamField = GameObjects.gBattle:get_field("Team")

function GameObjects.get_sdk_pointers()
    local sPlayer = GameObjects.PlayerField:get_data()
    if not sPlayer then return nil, nil, nil end
    local sTeam = GameObjects.TeamField:get_data()
    return sPlayer, sPlayer.mcPlayer, sTeam and sTeam.mcTeam or nil
end

function GameObjects.map_player_data(cPlayer, cTeam)
    local data_vals = {}
    for player_index = 0, 1 do
        local player = cPlayer[player_index]
        if not player then return {} end
        local team = cTeam and cTeam[player_index] or nil
        local data = {}
        data.hp_current = player.vital_new or 0
        data.hp_max = player.vital_max or 0
        data.dir = Utils.bitand(player.BitValue or 0, 128) == 128
        data.drive_adjusted = (player.incapacitated) and (player.focus_new - 60000) or player.focus_new
        data.super = team and team.mSuperGauge or 0
        data.combo_count = team and team.mComboCount or 0
        data.death_count = team and team.mDeathCount or 0
        data.pos_x = player.pos and (player.pos.x.v / 65536.0) or 0
        data.gap = (player.vs_distance and player.vs_distance.v or 0) / 65536.0
        data.advantage = 0
        if GameObjects.TrainingManager and GameObjects.TrainingManager._tCommon then
            local snap = GameObjects.TrainingManager._tCommon.SnapShotDatas
            if snap and snap[0] then
                local meter = snap[0]._DisplayData.FrameMeterSSData.MeterDatas
                if meter and meter[player_index] then
                    local stun_str = string.gsub(meter[player_index].StunFrame or "0", "F", "")
                    data.advantage = tonumber(stun_str) or 0
                end
            end
        end
        data_vals[player_index] = data
    end
    return data_vals[0], data_vals[1]
end

------------------
-- ComboData Logic
------------------

ComboData.player_states = {
    [0] = { started = false, finished = false, attacker = 0, start = {}, finish = {} },
    [1] = { started = false, finished = false, attacker = 1, start = {}, finish = {} },
}
ComboData.p1_prev, ComboData.p2_prev = {}, {}

function ComboData.update_state(p1, p2)
    for i = 0, 1 do
        local state = ComboData.player_states[i]
        local atk, def = (i == 0 and p1 or p2), (i == 0 and p2 or p1)
        local def_prev = (i == 0 and ComboData.p2_prev or ComboData.p1_prev)

        if not state.started and atk.combo_count > 0 then
            state.started, state.finished = true, false
            state.start = { p1 = Utils.deep_copy(ComboData.p1_prev), p2 = Utils.deep_copy(ComboData.p2_prev) }
        end

        if state.started then
            state.finish = { p1 = Utils.deep_copy(p1), p2 = Utils.deep_copy(p2) }
            if atk.combo_count == 0 or def.death_count ~= def_prev.death_count then
                state.finished, state.started = true, false
            end
        end
    end
    ComboData.p1_prev, ComboData.p2_prev = p1, p2
end

-------------------------
-- UI Rendering
-------------------------

UI.prev_key_states = {}
UI.save_pending = false
UI.save_timer = 0
UI.key_ready = false
UI.right_click_this_frame = false
UI.gradient_max = {
    dmg = 5000,
    p1_drv = 40000,
    p1_sup = 10000,
    p2_drv = 40000,
    p2_sup = 10000,
    p1_cry = 10000,
    p2_cry = 10000,
    adv = 0,
    gap = 0,
}

function UI.was_key_down(i)
    local down = reframework:is_key_down(i)
    local prev = UI.prev_key_states[i]
    UI.prev_key_states[i] = down
    return down and not prev
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

function UI.get_font_size(size)
    return imgui.push_font(imgui.load_font(nil, size))
end

function UI.large_font() return UI.get_font_size(28) end
function UI.medium_font() return UI.get_font_size(24) end
function UI.small_font() return UI.get_font_size(16) end

function UI.center_text(txt, idx)
    if not txt then return end
    local col_left = 0
    local col_right = 70
    local text_width = imgui.calc_text_size(txt).x
    local cursor = imgui.get_cursor_pos()
    -- imgui.set_cursor_pos(Vector2f.new((win_width - text_width) * 0.5, cursor.y))
    imgui.set_cursor_pos(Vector2f.new((col_left + col_right - text_width) * 0.5, cursor.y))
end

function UI.value_to_hex_color(value, max_val)
    max_val = max_val or 7500
    value = math.max(1, math.min(max_val, value))
    
    local normalized = (value - 1) / (max_val - 1)
    
    local hue = normalized * 5
    local red, green, blue
    
    if hue < 1 then
        red = 0
        green = 255
        blue = math.floor(255 * (1 - hue))
    elseif hue < 2 then
        red = math.floor(255 * (hue - 1))
        green = 255
        blue = 0
    elseif hue < 3 then
        red = 255
        green = math.floor(255 * (1 - (hue - 2) * 0.5))
        blue = 0
    elseif hue < 4 then
        red = 255
        green = math.floor(128 * (1 - (hue - 3)))
        blue = math.floor(255 * (hue - 3))
    else
        red = math.floor(255 * (1 - (hue - 4)))
        green = math.floor(255 * (hue - 4))
        blue = 255
    end
    
    local rgb = (red * 0x10000) + (green * 0x100) + blue
    return 0xFF000000 + rgb
end

function UI.color(val, idx)
    local color = nil
    color = UI.value_to_hex_color(val)
    local item_str = string.format("%.0f", val)
    -- UI.center_text(item_str, idx)
    return imgui.text_colored(item_str, color)
end


function process_columns(elements, is_color, column_keys)
    local idx = 0
    for _, e in ipairs(elements) do
        imgui.table_set_column_index(idx)
        if e ~= 0 then
            if is_color then
                local column_key = column_keys and column_keys[idx + 1] or nil
                local max_val = (column_key and UI.gradient_max[column_key]) or 1
                
                local normalized_val = max_val > 0 and (e / max_val) or 0
                local color = UI.value_to_hex_color(normalized_val)
                local item_str = string.format("%.0f", e)
                imgui.text_colored(item_str, color)
            else
                imgui.text(string.format("%.0f", e))
            end
        end
        idx = idx + 1
    end
end

function UI.render_columns(dmg,p1_drv, p1_sup, p2_drv, p2_sup, p1_cry, p2_cry, adv, gap, is_color)
    process_columns({dmg, p1_drv, p1_sup, p2_drv, p2_sup, p1_cry, p2_cry, adv, gap}, is_color)
end

UI.col_widths = {70, 80, 80, 80, 80, 50, 50, 40, 30}
UI.combo_window_fixed_width = UI.col_widths[1] + UI.col_widths[2] + UI.col_widths[3] + UI.col_widths[4] + UI.col_widths[5] + UI.col_widths[6] + UI.col_widths[7] + UI.col_widths[8] + UI.col_widths[9]

-- TODO: Add percentage display
function UI.render_combo_window_table(state)
    
    local is_p1 = state.attacker == 0
    local min_view = false
    if is_p1 then
        min_view = Config.settings.toggle_minimal_view_p1
    else
        min_view = Config.settings.toggle_minimal_view_p2
    end
    local minimal_view = min_view or Config.settings.toggle_minimal_view

    if imgui.begin_table("combo_table_p" .. tostring(state.attacker + 1), 9, 4096|8192, Vector2f.new(UI.combo_window_fixed_width, 0)) then
        UI.small_font()
        imgui.table_setup_column("Damage", 8|8192, UI.col_widths[1])
        imgui.table_setup_column("P1 Drive", 8|8192, UI.col_widths[2])
        imgui.table_setup_column("P1 Super", 8|8192, UI.col_widths[3])
        imgui.table_setup_column("P2 Drive", 8|8192, UI.col_widths[4])
        imgui.table_setup_column("P2 Super", 8|8192, UI.col_widths[5])
        imgui.table_setup_column("P1 Carry", 8|8192, UI.col_widths[6])
        imgui.table_setup_column("P2 Carry", 8|8192, UI.col_widths[7])
        imgui.table_setup_column("Gap", 8|8192, UI.col_widths[8])
        imgui.table_setup_column("Adv", 8|8192, UI.col_widths[9])
        imgui.table_headers_row()
        imgui.table_next_row(nil, 0)
        imgui.pop_font()
        
        if not minimal_view then
            imgui.table_set_column_index(0)
            UI.medium_font()
            UI.render_columns(is_p1 and state.start.p2.hp_current or state.start.p1.hp_current, state.start.p1.drive_adjusted, state.start.p1.super, state.start.p2.drive_adjusted, state.start.p2.super, state.start.p1.pos_x, state.start.p2.pos_x, 0, 0, false)
            imgui.table_next_row(nil, 0)
            imgui.pop_font()

            imgui.table_set_column_index(0)
            UI.medium_font()
            UI.render_columns(is_p1 and state.finish.p2.hp_current or state.finish.p1.hp_current, state.finish.p1.drive_adjusted, state.finish.p1.super, state.finish.p2.drive_adjusted, state.finish.p2.super, state.finish.p1.pos_x, state.finish.p2.pos_x, 0, 0, false)
            imgui.table_next_row(nil, 0)
            imgui.pop_font()
        end
        
        imgui.table_next_row(nil, 0)

        local t_hp = is_p1 and (state.start.p2.hp_current - state.finish.p2.hp_current) or (state.start.p1.hp_current - state.finish.p1.hp_current)
        local t_p1_drv = state.finish.p1.drive_adjusted - state.start.p1.drive_adjusted
        local t_p1_sup = state.finish.p1.super - state.start.p1.super
        local t_p2_drv = state.finish.p2.drive_adjusted - state.start.p2.drive_adjusted
        local t_p2_sup = state.finish.p2.super - state.start.p2.super
    
        local t_p1_carry = state.attacker == 0 and math.abs(state.finish.p1.pos_x - state.start.p1.pos_x) or math.abs(state.start.p2.pos_x - state.finish.p2.pos_x)
        local t_p2_carry = state.attacker == 1 and math.abs(state.start.p1.pos_x - state.finish.p1.pos_x) or math.abs(state.finish.p2.pos_x - state.start.p2.pos_x)
        
        imgui.table_set_column_index(0)
        UI.render_columns(t_hp, t_p1_drv, t_p1_sup, t_p2_drv, t_p2_sup, t_p1_carry, t_p2_carry, is_p1 and state.finish.p1.gap or state.finish.p2.gap, is_p1 and state.finish.p1.advantage or state.finish.p2.advantage, state.finish.p1.gap, true)
        imgui.end_table()
    end
end

function UI.in_window_range()
    local mouse_pos = imgui.get_mouse()
    local win_pos = imgui.get_window_pos()
    local win_size = imgui.get_window_size()
    return mouse_pos.x >= win_pos.x and mouse_pos.x <= win_pos.x + win_size.x and
        mouse_pos.y >= win_pos.y and mouse_pos.y <= win_pos.y + win_size.y
end

function UI.is_toggle_view_clicked()
    if not UI.in_window_range() then return false end
    return UI.right_click_this_frame
end

function UI.render_player_combo_window(player_index, window_title, posx, pos_y, toggle_setting, minimal_view_setting)
    local state = ComboData.player_states[player_index]
    if not (state.started or state.finished) then return end
    
    imgui.set_next_window_pos(Vector2f.new(posx, pos_y), 1 << 3)
    imgui.set_next_window_size(UI.combo_window_fixed_width, 0, 1 << 1)
    
    if imgui.begin_window(window_title, true, 1|8|32) then
        if UI.is_toggle_view_clicked() then
            Config.settings[minimal_view_setting] = not Config.settings[minimal_view_setting]
            UI.mark_for_save()
        end
        
        UI.render_combo_window_table(state)
        imgui.end_window()
    end
end

function UI.render_windows()
    if not Config.settings.toggle_all then return end
    UI.right_click_this_frame = UI.was_key_down(RIGHT_CLICK)

    local display = imgui.get_display_size()
    local center_x, window_y = display.x * 0.5, display.y * 0.002
    UI.large_font()

    if Config.settings.toggle_p1 then
        UI.render_player_combo_window(0, "P1 Current Combo", center_x - UI.combo_window_fixed_width - 100, window_y, "toggle_p1", "toggle_minimal_view_p1")
    end

    if Config.settings.toggle_p2 then
        UI.render_player_combo_window(1, "P2 Current Combo", (center_x + 100), window_y, "toggle_p2", "toggle_minimal_view_p2")
    end
    
    imgui.pop_font()
end

function UI.render_settings()
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

-------------------------
-- Main
-------------------------

re.on_draw_ui(function()
    UI.render_settings()
end)

re.on_frame(function()
    local sPlayer, cPlayer, cTeam = GameObjects.get_sdk_pointers()
    if sPlayer and sPlayer.prev_no_push_bit ~= 0 then
        local p1, p2 = GameObjects.map_player_data(cPlayer, cTeam)
        ComboData.update_state(p1, p2)
        UI.render_windows()
        UI.save_handler()
    end
end)

Config.load()