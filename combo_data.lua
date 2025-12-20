-- Original code from https://github.com/WistfulHopes/SF6Mods

local gBattle = sdk.find_type_definition("gBattle")
if not gBattle then
    log.info("Failed to find gBattle type definition")
    return
end

local function get_safe_field(obj, field_name)
    if not obj then return nil end
    local field = obj:get_field(field_name)
    if not field then return nil end
    return field:get_data(nil)
end

local sPlayer = get_safe_field(gBattle, "Player")
    if not sPlayer then
        log.info("Failed to get sPlayer")
    return
end

local cPlayer = sPlayer.mcPlayer
local BattleTeam = get_safe_field(gBattle, "Team")
if not BattleTeam then
    log.info("Failed to get BattleTeam")
    return
end

local cTeam = BattleTeam.mcTeam

local storageData = get_safe_field(gBattle, "Command")
if not storageData or not storageData.StorageData then
    log.info("Failed to get storageData")
    return
end
storageData = storageData.StorageData

local p1ChargeInfo = nil
local p2ChargeInfo = nil
if storageData.UserEngines and #storageData.UserEngines >= 2 then
    p1ChargeInfo = storageData.UserEngines[0] and storageData.UserEngines[0].m_charge_infos
    p2ChargeInfo = storageData.UserEngines[1] and storageData.UserEngines[1].m_charge_infos
end

local sWork = get_safe_field(gBattle, "Work")
if not sWork then
    log.info("Failed to get sWork")
    return
end
local cWork = sWork.Global_work

local p1 = {}
local p1_prev = {}
local p2 = {}
local p2_prev = {}

local combo_start = {}
combo_start.p1 = {}
combo_start.p2 = {}

local combo_finish = {}
combo_finish.p1 = {}
combo_finish.p2 = {}

local combo_inputs = {}

local combo_started = false
local combo_finished = false

local attacker

local all_combos = {}
local current_combo_index = 0
local max_combos_to_save = 20

local auto_save_combos = true
local show_saved_combos = true 

local function safe_get_player_data(player_index)
    if not cPlayer or not cPlayer[player_index] then
        return {}
    end
    return cPlayer[player_index]
end

local function safe_get_team_data(team_index)
    if not cTeam or not cTeam[team_index] then
        return {}
    end
    return cTeam[team_index]
end

local function deep_copy(original)
    if type(original) ~= 'table' then return original end
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = deep_copy(value)
    end
    return copy
end

local bitand = function(a, b)
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

local abs = function(num)
    return num < 0 and -num or num
end

local function save_combo()
    if combo_finished and combo_start.p1 and combo_start.p2 and combo_finish.p1 and combo_finish.p2 then
        local total_damage = 0
        if attacker == 0 then
            total_damage = (combo_start.p2.current_HP or 0) - (combo_finish.p2.current_HP or 0)
        elseif attacker == 1 then
            total_damage = (combo_start.p1.current_HP or 0) - (combo_finish.p1.current_HP or 0)
        end
        local combo_data = {
            index = current_combo_index,
            start = {
                p1 = deep_copy(combo_start.p1),
                p2 = deep_copy(combo_start.p2)
            },
            finish = {
                p1 = deep_copy(combo_finish.p1),
                p2 = deep_copy(combo_finish.p2)
            },
            totals = {
                attacker = attacker,
                damage = total_damage,
                p1_drive_gain = (combo_finish.p1.drive_adjusted or 0) - (combo_start.p1.drive_adjusted or 0),
                p1_super_gain = (combo_finish.p1.super or 0) - (combo_start.p1.super or 0),
                p2_drive_gain = (combo_finish.p2.drive_adjusted or 0) - (combo_start.p2.drive_adjusted or 0),
                p2_super_gain = (combo_finish.p2.super or 0) - (combo_start.p2.super or 0),
                p1_position_change = (combo_finish.p1.posX or 0) - (combo_start.p1.posX or 0),
                p2_position_change = (combo_finish.p2.posX or 0 ) - (combo_start.p2.posX or 0),
                gap = combo_finish.p1.gap or 0
            }
        }
        
        combo_data.timestamp = os.date("%H:%M:%S")
        
        table.insert(all_combos, 1, combo_data)
        
        if #all_combos > max_combos_to_save then
            table.remove(all_combos, max_combos_to_save + 1)
        end
        
        current_combo_index = current_combo_index + 1
        
        log.info(string.format("Combo %d saved: %.0f damage", combo_data.index, combo_data.totals.damage))
        
        return true
    end
    return false
end

local function clear_all_combos()
    all_combos = {}
    current_combo_index = 0
    log.info("All combos cleared")
end

local function check_combo_started()
    if p1.combo_count > 0 and not combo_started then
        attacker = 0
        return true
    elseif p2.combo_count > 0 and not combo_started then
        attacker = 1
        return true
    else
        return false
    end
end

local function check_combo_finished()
    if combo_started and attacker == 0 and p1.combo_count == 0 then
        return true
    elseif combo_started and attacker == 1 and p2.combo_count == 0 then
        return true
    else
        return false
    end
end

local function check_combo_in_progress()
    if combo_started and not combo_finished then 
        return true
    end
end

local function color(val)
    if val > 0 then
        imgui.text_colored(string.format("%.0f", val), 0xFF00FF00)
    elseif val < 0 then
        imgui.text_colored(string.format("%.0f", val), 0xFFDDF527)
    else
        imgui.text("")
    end
end

local function process_player_info()
    local p1_data = {}
    local p2_data = {}
    local p1HitDT = nil
    local p2HitDT = nil
    
    local player1 = safe_get_player_data(0)
    local player2 = safe_get_player_data(1)
    local team1 = safe_get_team_data(0)
    local team2 = safe_get_team_data(1)
    
    local p1Engine = nil
    local p2Engine = nil
    if player1.mpActParam and player1.mpActParam.ActionPart then
        p1Engine = player1.mpActParam.ActionPart._Engine
    end
    if player2.mpActParam and player2.mpActParam.ActionPart then
        p2Engine = player2.mpActParam.ActionPart._Engine
    end
    
    if p1Engine then
        p1_data.mActionId = p1Engine:get_ActionID()
        p1_data.mActionFrame = p1Engine:get_ActionFrame()
        p1_data.mEndFrame = p1Engine:get_ActionFrameNum()
        p1_data.mMarginFrame = p1Engine:get_MarginFrame()
    end
    
    if p2Engine then
        p2_data.mActionId = p2Engine:get_ActionID()
        p2_data.mActionFrame = p2Engine:get_ActionFrame()
        p2_data.mEndFrame = p2Engine:get_ActionFrameNum()
        p2_data.mMarginFrame = p2Engine:get_MarginFrame()
    end
    
    p1HitDT = player2.pDmgHitDT
    p2HitDT = player1.pDmgHitDT
    
    p1_data.HP_cap = player1.heal_new or 0
    p1_data.current_HP = player1.vital_new or 0
    p1_data.HP_cooldown = player1.healing_wait or 0
    p1_data.dir = bitand(player1.BitValue or 0, 128) == 128
    p1_data.curr_hitstop = player1.hit_stop or 0
    p1_data.max_hitstop = player1.hit_stop_org or 0
    p1_data.curr_hitstun = player1.damage_time or 0
    p1_data.max_hitstun = player1.damage_info and player1.damage_info.time or 0
    p1_data.curr_blockstun = player1.guard_time or 0
    p1_data.stance = player1.pose_st or 0
    p1_data.throw_invuln = player1.catch_muteki or 0
    p1_data.full_invuln = player1.muteki_time or 0
    p1_data.juggle = player1.combo_dm_air or 0
    p1_data.burnout = player1.incapacitated or false
    p1_data.drive = player1.focus_new or 0
    -- Adjusted Drive to account for Burnout
    if p1_data.burnout then
        p1_data.drive_adjusted = p1_data.drive - 60000
    else
        p1_data.drive_adjusted = p1_data.drive
    end
    p1_data.drive_cooldown = player1.focus_wait or 0
    p1_data.super = team1 and team1.mSuperGauge or 0
    p1_data.buff = player1.style_timer or 0
    p1_data.debuff_timer = player1.damage_cond and player1.damage_cond.timer or 0
    p1_data.chargeInfo = p1ChargeInfo
    p1_data.gap = cPlayer[0].vs_distance.v / 65536.0
    if player1.pos and player1.pos.x then
        p1_data.posX = player1.pos.x.v / 65536.0
        p1_data.posY = player1.pos.y.v / 65536.0
    else
        p1_data.posX = 0
        p1_data.posY = 0
    end
    p1_data.combo_count = cPlayer[1].combo_scale.count
    p1_data.combo_scale_now = cPlayer[1].combo_scale.now
    p1_data.combo_scale_start = cPlayer[1].combo_scale.start
    p1_data.combo_scale_buff = cPlayer[1].combo_scale.buff
    p1_data.character = player1.character or 0 -- TODO
    
    p2_data.HP_cap = player2.heal_new or 0
    p2_data.current_HP = player2.vital_new or 0
    p2_data.HP_cooldown = player2.healing_wait or 0
    p2_data.dir = bitand(player2.BitValue or 0, 128) == 128
    p2_data.curr_hitstop = player2.hit_stop or 0
    p2_data.max_hitstop = player2.hit_stop_org or 0
    p2_data.curr_hitstun = player2.damage_time or 0
    p2_data.max_hitstun = player2.damage_info and player2.damage_info.time or 0
    p2_data.curr_blockstun = player2.guard_time or 0
    p2_data.stance = player2.pose_st or 0
    p2_data.throw_invuln = player2.catch_muteki or 0
    p2_data.full_invuln = player2.muteki_time or 0
    p2_data.juggle = player2.combo_dm_air or 0
    p2_data.burnout = player1.incapacitated or false
    p2_data.drive = player2.focus_new or 0    
    if p2_data.burnout then
        p2_data.drive_adjusted = p2_data.drive - 60000
    else
        p2_data.drive_adjusted = p2_data.drive
    end
    p2_data.drive_cooldown = player2.focus_wait or 0
    p2_data.super = team2 and team2.mSuperGauge or 0
    p2_data.buff = player2.style_timer or 0
    p2_data.debuff_timer = player2.damage_cond and player2.damage_cond.timer or 0
    p2_data.chargeInfo = p2ChargeInfo
    p2_data.gap = cPlayer[1].vs_distance.v / 65536.0
    if player2.pos and player2.pos.x then
        p2_data.posX = player2.pos.x.v / 65536.0
        p2_data.posY = player2.pos.y.v / 65536.0
    else
        p2_data.posX = 0
        p2_data.posY = 0
    end
    p2_data.combo_count = cPlayer[0].combo_scale.count
    p2_data.combo_scale_now = cPlayer[0].combo_scale.now
    p2_data.combo_scale_start = cPlayer[0].combo_scale.start
    p2_data.combo_scale_buff = cPlayer[0].combo_scale.buff
    p2_data.character = player2.character or 0 -- TODO
    
    return p1_data, p1HitDT, p2_data, p2HitDT
end

re.on_frame(function()
    if not sPlayer then return end
    if sPlayer.prev_no_push_bit ~= 0 then
        p1_prev, p2_prev = deep_copy(p1), deep_copy(p2)
        p1, p1HitDT, p2, p2HitDT = process_player_info()
        
        if check_combo_started() then
            p1.attacker = attacker
            p2.attacker = attacker
            combo_start.p1 = deep_copy(p1_prev)
            combo_start.p2 = deep_copy(p2_prev)

            -- Check/compensate for DR starter
            -- Temp. fix - find DR flag
            if attacker == 0 then
                if p1.drive_cooldown > 200 then
                    combo_start.p1.drive_adjusted = combo_start.p1.drive_adjusted + 10000
                elseif p1.drive_cooldown <= -120 then
                    combo_start.p1.drive_adjusted = combo_start.p1.drive_adjusted + 20000
                end
            elseif attacker == 1 then
                if p2.drive_cooldown > 200 then
                    combo_start.p2.drive_adjusted = combo_start.p2.drive_adjusted + 10000
                elseif p2.drive_cooldown <= -120 then
                    combo_start.p2.drive_adjusted = combo_start.p2.drive_adjusted + 20000
                end
            end                

            combo_inputs[#combo_inputs] = p1.mActionId
            combo_started = true
            combo_finished = false
        end

        if check_combo_in_progress() then
            if attacker == 0 then
                if combo_inputs[#combo_inputs] ~= p1.mActionId then
                    combo_inputs[#combo_inputs] = p1.mActionId
                end
            elseif attacker == 1 then
                if combo_inputs[#combo_inputs] ~= p2.mActionId then
                    combo_inputs[#combo_inputs] = p2.mActionId
                end
            end
        end
        
        if check_combo_finished() then
            combo_finish.p1 = deep_copy(p1)
            combo_finish.p2 = deep_copy(p2)
            combo_finished = true

            if auto_save_combos then
                save_combo()
            end
            
            combo_started = false
        end
        
        imgui.set_next_item_open(true, 2)
        imgui.begin_window("Combo Data")
        imgui.set_next_item_open(true, 2)
        if imgui.tree_node("Current Combo") then
            if combo_started or combo_finished then
                if imgui.begin_table("current_combo_table", 10) then
                    if attacker == 0 then
                        if combo_start and combo_start.p1.dir then
                            imgui.table_setup_column("P1 (L)", nil, 15)
                        elseif combo_start and not combo_start.p1.dir then
                            imgui.table_setup_column("P1 (R)", nil, 15)
                        end
                    elseif attacker == 1 then
                        if combo_start and combo_start.p2.dir then
                            imgui.table_setup_column("P2 (L)", nil, 15)
                        elseif combo_start and not combo_start.p2.dir then
                            imgui.table_setup_column("P2 (R)", nil, 15)
                        end
                    else
                        imgui.table_setup_column("", nil, 15)    
                    end
                    imgui.table_setup_column("Dmg", nil, 15)
                    imgui.table_setup_column("P1Drive", nil, 20)
                    imgui.table_setup_column("P1Super", nil, 20)
                    imgui.table_setup_column("P2Drive", nil, 20)
                    imgui.table_setup_column("P2Super", nil, 20)
                    imgui.table_setup_column("KD", nil, 10)
                    imgui.table_setup_column("P1Carry", nil, 20)
                    imgui.table_setup_column("P2Carry", nil, 20)
                    imgui.table_setup_column("Gap", nil, 10)
                    imgui.table_headers_row()
                    
                    imgui.table_next_row()
                    imgui.table_set_column_index(0)
                    imgui.text("Start")
                    imgui.table_set_column_index(1)
                    if attacker == 0 then
                        imgui.text(tostring(combo_start.p2.current_HP or ""))
                    elseif attacker == 1 then
                        imgui.text(tostring(combo_start.p1.current_HP or ""))
                    end
                    imgui.table_set_column_index(2)
                    imgui.text(tostring(combo_start.p1.drive_adjusted or ""))
                    imgui.table_set_column_index(3)
                    imgui.text(tostring(combo_start.p1.super or ""))
                    imgui.table_set_column_index(4)
                    imgui.text(tostring(combo_start.p2.drive_adjusted or ""))
                    imgui.table_set_column_index(5)
                    imgui.text(tostring(combo_start.p2.super or ""))
                    imgui.table_set_column_index(7)
                    if combo_start.p1.posX then
                        imgui.text(string.format("%.2f", combo_start.p1.posX))
                    else
                        imgui.text("")            
                    end
                    imgui.table_set_column_index(8)
                    if combo_start.p2.posX then
                        imgui.text(string.format("%.2f", combo_start.p2.posX))
                    else
                        imgui.text("")
                    end

                    imgui.table_next_row()
                    imgui.table_set_column_index(0)
                    imgui.text("Finish")
                    if not combo_started then
                        imgui.table_set_column_index(1)
                        if attacker == 0 then
                            imgui.text(tostring(combo_finish.p2.current_HP or ""))
                        elseif attacker == 1 then
                            imgui.text(tostring(combo_finish.p1.current_HP or ""))
                        end
                        imgui.table_set_column_index(2)
                        imgui.text(tostring(combo_finish.p1.drive_adjusted or ""))
                        imgui.table_set_column_index(3)
                        imgui.text(tostring(combo_finish.p1.super or ""))
                        imgui.table_set_column_index(4)
                        imgui.text(tostring(combo_finish.p2.drive_adjusted or ""))
                        imgui.table_set_column_index(5)
                        imgui.text(tostring(combo_finish.p2.super or ""))
                        imgui.table_set_column_index(7)
                        if combo_finish.p1.posX then
                            imgui.text(string.format("%.2f", combo_finish.p1.posX))
                        else
                            imgui.text("")            
                        end
                        imgui.table_set_column_index(8)
                        if combo_finish.p2.posX then
                            imgui.text(string.format("%.2f", combo_finish.p2.posX))
                        else
                            imgui.text("")            
                        end
                    end

                    imgui.table_next_row()
                    imgui.table_set_column_index(0)
                    imgui.text("Total")
                    if combo_finished then
                        
                        imgui.table_set_column_index(1)
                        if attacker == 0 then
                            local finished_hp_diff = (combo_start.p2.current_HP or 0) - (combo_finish.p2.current_HP or 0)
                            color(finished_hp_diff)
                        elseif attacker == 1 then
                            local finished_hp_diff = (combo_start.p1.current_HP or 0) - (combo_finish.p1.current_HP or 0)
                            color(finished_hp_diff)
                        end
                        
                        imgui.table_set_column_index(2)
                        local finished_p1_drive_diff = (combo_finish.p1.drive_adjusted or 0) - (combo_start.p1.drive_adjusted or 0)
                        color(finished_p1_drive_diff) 
                        
                        imgui.table_set_column_index(3)
                        local finished_p1_super_diff = (combo_finish.p1.super or 0) - (combo_start.p1.super or 0)
                        color(finished_p1_super_diff)
                        
                        imgui.table_set_column_index(4)
                        local finished_p2_drive = (combo_finish.p2.drive_adjusted or 0) - (combo_start.p2.drive_adjusted or 0)
                        color(finished_p2_drive)
                        
                        imgui.table_set_column_index(5)
                        local finished_p2_super = (combo_finish.p2.super or 0) - (combo_start.p2.super or 0)
                        color(finished_p2_super)
                        
                        imgui.table_set_column_index(7)
                        local p1_carry = 0
                        if attacker == 0 and p1.dir then
                            p1_carry = (combo_finish.p1.posX or 0) - (combo_start.p1.posX or 0)
                        elseif attacker == 0 and not p1.dir then
                            p1_carry = (combo_start.p1.posX or 0) - (combo_finish.p1.posX or 0)
                        elseif attacker == 1 and p2.dir then
                            p1_carry = (combo_finish.p1.posX or 0) - (combo_start.p1.posX or 0)
                        elseif attacker == 1 and not p2.dir then
                            p1_carry = (combo_start.p1.posX or 0) - (combo_finish.p1.posX or 0)
                        end
                        color(p1_carry)

                        imgui.table_set_column_index(8)
                        local p2_carry = 0
                        if attacker == 0 and p1.dir then
                                p2_carry = (combo_finish.p2.posX or 0) - (combo_start.p2.posX or 0)
                        elseif attacker == 0 and not p1.dir then
                                p2_carry = (combo_start.p2.posX or 0) - (combo_finish.p2.posX or 0) 
                        elseif attacker == 1 and p2.dir then
                            p2_carry = (combo_finish.p2.posX or 0) - (combo_start.p2.posX or 0)
                        elseif attacker == 1 and not p2.dir then
                            p2_carry = (combo_start.p2.posX or 0) - (combo_finish.p2.posX or 0)
                        end
                        color(p2_carry)

                        imgui.table_set_column_index(9)
                        imgui.text(string.format("%.0f", combo_finish.p1.gap))
                    end
                    imgui.end_table()
                end
            end
            
            if combo_finished and not auto_save_combos then
                imgui.spacing()
                if imgui.button("Save This Combo") then
                    if save_combo() then
                        imgui.same_line()
                        imgui.text_colored("✓ Saved!", 0xFF00FF00)
                    end
                end
            end
            
            imgui.tree_pop()
        end
        
        if show_saved_combos then
            imgui.spacing()
            imgui.set_next_item_open(true, 2)
            if imgui.tree_node(string.format("Saved Combos (%d)", #all_combos)) then
                imgui.spacing()
                imgui.text("Settings:")
                imgui.same_line()
                _, auto_save_combos = imgui.checkbox("Auto-save", auto_save_combos)
                imgui.same_line()
                if imgui.button("Clear All") then
                    clear_all_combos()
                end
                
                imgui.spacing()
                
                if #all_combos > 0 then
                    local table_flags = 0
                    if imgui.table_flags and imgui.table_flags.borders then
                        table_flags = table_flags + imgui.table_flags.borders
                    end
                    if imgui.table_flags and imgui.table_flags.row_bg then
                        table_flags = table_flags + imgui.table_flags.row_bg
                    end
                    
                    if imgui.begin_table("saved_combos_table", 12, table_flags) then
                        imgui.table_setup_column("Time", nil, 22)
                        imgui.table_setup_column("Attacker", nil, 20)
                        imgui.table_setup_column("Dmg", nil, 15)
                        imgui.table_setup_column("P1 Drive", nil, 20)
                        imgui.table_setup_column("P1 Super", nil, 20)
                        imgui.table_setup_column("P2 Drive", nil, 20)
                        imgui.table_setup_column("P2 Super", nil, 20)
                        imgui.table_setup_column("KD", nil, 15)
                        imgui.table_setup_column("P1 Pos", nil, 20)
                        imgui.table_setup_column("Carry", nil, 20)
                        imgui.table_setup_column("Gap", nil, 20)
                        imgui.table_setup_column("Actions", nil, 25)
                        imgui.table_headers_row()
                        
                        for i, combo in ipairs(all_combos) do
                            imgui.table_next_row()
                            
                            imgui.table_set_column_index(0)
                            imgui.text(combo.timestamp or "")

                            imgui.table_set_column_index(1)
                            if combo.totals.attacker == 0 then
                                imgui.text("P1")
                            elseif combo.totals.attacker == 1 then
                                imgui.text("P2")
                            else
                                imgui.text("")
                            end
                            
                            imgui.table_set_column_index(2)
                            imgui.text(string.format("%.0f", combo.totals.damage or 0))
                            
                            imgui.table_set_column_index(3)
                            local p1_drive_gain = combo.totals.p1_drive_gain or 0
                            color(p1_drive_gain)
                            
                            imgui.table_set_column_index(4)
                            local p1_super_gain = combo.totals.p1_super_gain or 0
                            color(p1_super_gain)
                            
                            imgui.table_set_column_index(5)
                            local p2_drive_gain = combo.totals.p2_drive_gain or 0
                            color(p2_drive_gain)
                            
                            imgui.table_set_column_index(6)
                            local p2_super_gain = combo.totals.p2_super_gain or 0
                            color(p2_super_gain)
                            
                            imgui.table_set_column_index(8)
                            local pos_change = combo.totals.p1_position_change or 0
                            color(pos_change)

                            imgui.table_set_column_index(9)
                            local carry = combo.totals.p2_position_change or 0
                            color(carry)
                            
                            imgui.table_set_column_index(10)
                            local finish_gap = combo.totals.gap or 0
                            imgui.text(string.format("%.0f", finish_gap))
                            
                            imgui.table_set_column_index(11)
                            local button_label = "View##combo_" .. i
                            if imgui.small_button(button_label) then
                                imgui.open_popup("combo_details_popup_" .. i)

                            end

                            local function popup_separator()
                                imgui.table_next_row()
                                imgui.table_set_column_index(0)
                                imgui.text("")
                                imgui.table_set_column_index(1)
                                imgui.text("")
                            end
                            
                            if imgui.begin_popup("combo_details_popup_" .. i) then
                                imgui.text(string.format("Combo #%d Details", combo.index))
                                imgui.separator()
                                
                                if imgui.begin_table("combo_details_table_" .. i, 2, 0) then
                                    imgui.table_setup_column("Label", nil, 120)
                                    imgui.table_setup_column("Value", nil, 150)

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Time:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(combo.timestamp or "")

                                    popup_separator()
                                    
                                    imgui.table_next_row()
                                    if combo.totals.attacker == 0 then
                                        imgui.table_set_column_index(0)
                                        imgui.text("Start P2 HP:")
                                        imgui.table_set_column_index(1)
                                        imgui.text(string.format("%.0f", combo.start.p2.current_HP or 0))

                                        imgui.table_next_row()
                                        imgui.table_set_column_index(0)
                                        imgui.text("Finish P2 HP:")
                                        imgui.table_set_column_index(1)
                                        imgui.text(string.format("%.0f", combo.finish.p2.current_HP or 0))

                                    elseif combo.totals.attacker == 1 then
                                        imgui.table_set_column_index(0)
                                        imgui.text("Start P1 HP:")
                                        imgui.table_set_column_index(1)
                                        imgui.text(string.format("%.0f", combo.start.p1.current_HP or 0))

                                        imgui.table_next_row()
                                        imgui.table_set_column_index(0)
                                        imgui.text("Finish P1 HP:")
                                        imgui.table_set_column_index(1)
                                        imgui.text(string.format("%.0f", combo.finish.p1.current_HP or 0))
                                    end
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Total Damage:")
                                    imgui.table_set_column_index(1)
                                    color(combo.totals.damage)

                                    popup_separator()
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Start P1 Drive:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.0f", combo.start.p1.drive_adjusted or 0))
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Finish P1 Drive:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.0f", combo.finish.p1.drive_adjusted or 0))

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Total P1 Drive:")
                                    imgui.table_set_column_index(1)
                                    color(combo.totals.p1_drive_gain)

                                    popup_separator()
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Start P1 Super:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.0f", combo.start.p1.super or 0))

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Finish P1 Super:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.0f", combo.finish.p1.super or 0))

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Total P1 Super:")
                                    imgui.table_set_column_index(1)
                                    color(combo.totals.p1_super_gain)

                                    popup_separator()

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Start P2 Drive:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.0f", combo.start.p2.drive_adjusted or 0))

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Finish P2 Drive:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.0f", combo.finish.p2.drive_adjusted or 0))
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Total P2 Drive:")
                                    imgui.table_set_column_index(1)
                                    color(combo.totals.p2_drive_gain)

                                    popup_separator()
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Start P2 Super:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.0f", combo.start.p2.super or 0))

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Finish P2 Super:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.0f", combo.finish.p2.super or 0))
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Total P2 Super:")
                                    imgui.table_set_column_index(1)
                                    color(combo.totals.p2_super_gain)

                                    popup_separator()
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Start P1 Pos:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.2f", combo.start.p1.posX or 0))

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Finish P1 Pos:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.2f", combo.finish.p1.posX or 0))
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("P1 Pos Δ:")
                                    imgui.table_set_column_index(1)
                                    color(combo.totals.p1_position_change)

                                    popup_separator()

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Start P2 Pos:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.2f", combo.start.p2.posX or 0))

                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Finish P2 Pos:")
                                    imgui.table_set_column_index(1)
                                    imgui.text(string.format("%.2f", combo.finish.p2.posX or 0))
                                    
                                    imgui.table_next_row()
                                    imgui.table_set_column_index(0)
                                    imgui.text("Carry:")
                                    imgui.table_set_column_index(1)
                                    color(combo.totals.p2_position_change)
                                    
                                    imgui.end_table()
                                end
                                imgui.end_popup()
                            end
                        end 
                        imgui.end_table()
                    end
                else
                    imgui.text("No combos saved yet.")
                    imgui.text("Perform a combo to see it here!")
                end
                imgui.tree_pop()
            end
        end
        imgui.end_window()
    end
end)