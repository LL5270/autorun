local COMBO_SAVE_DIR = "combo_data/"
local MOVE_DICT_DIR = "move_dicts/"
local F2_KEY = 0x71

local combo_save_path
local json_files
local move_dict_path
local p1_char_dict
local p2_char_dict
local named_action
local named_action_list
local meter_datas
local p1_action_ids
local p2_action_ids
local attacker
local prev_key_states = {}
local p1 = {}
local p1_prev = {}
local p2 = {}
local p2_prev = {}
local p1_combo_inputs = {}
local p2_combo_inputs = {}
local all_combos = {}
local combo_start = {}
local combo_finish = {}
local hide_ui = false
local combo_started = false
local combo_finished = false
local auto_save_combos = true
local show_saved_combos = true
local current_combo_index = 0
local max_combos_to_save = 200
local max_combos_to_load = 100
combo_start.p1 = {}
combo_start.p2 = {}
combo_finish.p1 = {}
combo_finish.p2 = {}

local char_id_table = {
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
	[26] = "M Bison", 
	[27] = "Terry",
	[28] = "Mai",
	[29] = "Elena",
	[25] = "Sagat",
	[30] = "CViper"
}

re.on_config_save(function()
	local filename = os.date("%y%m%d_%H%M%S") .. ".json"
	combo_save_path = COMBO_SAVE_DIR .. filename
	jsonify_table(all_combos)
	json.dump_file(combo_save_path, all_combos)
end)

local function load_json()
	json_files = fs.glob([[combo_data\\.*json]])
	if json_files then
		for _, file_path in ipairs(json_files) do
			local data = json.load_file(file_path)
			if data then
				for _, combo in ipairs(data) do
					if #all_combos < max_combos_to_load then
						table.insert(all_combos, combo)
					end
				end
			end
		end
	end
end

load_json()

local function get_char_dict(char_id)
	move_dict_path = tostring(char_id) .. ".json"
	return json.load_file(MOVE_DICT_DIR .. move_dict_path) or {}
end

local function format_action_id(action_id)
	if action_id == nil then return "0000" end
	local id_str = tostring(action_id)
	while #id_str < 4 do
		id_str = "0" .. id_str
	end
	return id_str
end

local function format_action_id_list(action_id_list)
	local formatted_action_id_list = {}
	local formatted_id
	for k, v in pairs(action_id_list) do
		formatted_id = format_action_id(v)
		table.insert(formatted_action_id_list, formatted_id)
	end
	return formatted_action_id_list
end

local function format_named_action_list(formatted_id_list, char_dict)
	named_action_list = {}
	named_action = ""
	for k, v in pairs(formatted_id_list) do
		if v then
			named_action = char_dict[v]    
		end
		table.insert(named_action_list, named_action)
	end
	return named_action_list
end

local function get_field(obj, field_name)
	if not obj then return nil end
	local field = obj:get_field(field_name)
	if not field then return nil end
	return field:get_data(nil)
end

local gBattle = sdk.find_type_definition("gBattle")
local sPlayer = get_field(gBattle, "Player")
local cPlayer = sPlayer.mcPlayer
local BattleTeam = get_field(gBattle, "Team")
local cTeam = BattleTeam.mcTeam
local TrainingManager = sdk.get_managed_singleton("app.training.TrainingManager")

local function get_player_data(player_index)
	if not cPlayer or not cPlayer[player_index] then
		return {}
	end
	return cPlayer[player_index]
end

local function get_team_data(team_index)
	if not cTeam or not cTeam[team_index] then
		return {}
	end
	return cTeam[team_index]
end

local function get_meter_data(player_index)
	if not meter_datas or not meter_datas[player_index] then
		return {}
	end
	return meter_datas[player_index]
end

local function deep_copy(original)
	if type(original) ~= 'table' then return original end
	local copy = {}
	for key, value in pairs(original) do
		copy[key] = deep_copy(value)
	end
	return copy
end

local function bitand(a, b)
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

local function save_combo()
	if combo_finished and combo_start.p1 and combo_start.p2 and combo_finish.p1 and combo_finish.p2 then
		local total_damage = 0
		if attacker == 0 then
			total_damage = (combo_start.p2.hp_current or 0) - (combo_finish.p2.hp_current or 0)
		elseif attacker == 1 then
			total_damage = (combo_start.p1.hp_current or 0) - (combo_finish.p1.hp_current or 0)
		end
		p1_char_dict = get_char_dict(tostring(combo_finish.p1.char_id))
		p2_char_dict = get_char_dict(tostring(combo_finish.p2.char_id))
		p1_action_ids = format_action_id_list(combo_finish.p1.inputs)
		p2_action_ids = format_action_id_list(combo_finish.p2.inputs)
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
				gap = combo_finish.p1.gap or 0,
				attacker = attacker,
				damage = total_damage,
				p1_char_id = combo_finish.p1.char_id,
				p1_char_name = combo_finish.p1.char_name,
				p1_dir = combo_finish.p1.dir,
				p1_advantage = combo_finish.p1.advantage,
				p1_drive = (combo_finish.p1.drive_adjusted or 0) - (combo_start.p1.drive_adjusted or 0),
				p1_super = (combo_finish.p1.super or 0) - (combo_start.p1.super or 0),
				p1_position = (combo_finish.p1.pos_x or 0) - (combo_start.p1.pos_x or 0),
				p1_actions = p1_action_ids,
				p1_actions_named = format_named_action_list(p1_action_ids, p1_char_dict) or {},
				p2_char_id = combo_finish.p2.char_id,
				p2_char_name = combo_finish.p2.char_name,                
				p2_dir = combo_finish.p2.dir,
				p2_advantage = combo_finish.p2.advantage,
				p2_drive = (combo_finish.p2.drive_adjusted or 0) - (combo_start.p2.drive_adjusted or 0),
				p2_super = (combo_finish.p2.super or 0) - (combo_start.p2.super or 0),
				p2_position = (combo_finish.p2.pos_x or 0 ) - (combo_start.p2.pos_x or 0),
				p2_actions = p2_action_ids,
				p2_actions_named = format_named_action_list(p2_action_ids, p2_char_dict) or {}
			}
		}
		
		combo_data.timestamp = os.date("%H%M%S_%y%m%d")
		
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

local function was_key_down(i)
    local down = reframework:is_key_down(i)
    local prev = prev_key_states[i]
    prev_key_states[i] = down
    return down and not prev
end

local function hotkey_toggler()
	if was_key_down(F2_KEY) then
		hide_ui = not hide_ui
	end
end

local function process_player_info()
	meter_datas = TrainingManager._tCommon.SnapShotDatas[0]._DisplayData.FrameMeterSSData.MeterDatas

	local p1_data = {}
	local p2_data = {}
	local player1 = get_player_data(0)
	local player2 = get_player_data(1)
	local team1 = get_team_data(0)
	local team2 = get_team_data(1)
	local meter1 = meter_datas[0]
	local meter2 = meter_datas[1]
	local p1_engine = nil
	local p2_engine = nil
	local p1_char_id = nil
	local p2_char_id = nil

	if player1.mpActParam and player1.mpActParam.ActionPart then
		p1_char_id = player1.mpActParam.ActionPart._CharaID
		p1_engine = player1.mpActParam.ActionPart._Engine
	end
	if player2.mpActParam and player2.mpActParam.ActionPart then
		p2_char_id = player2.mpActParam.ActionPart._CharaID
		p2_engine = player2.mpActParam.ActionPart._Engine
	end

	local p1_hit_dt = cPlayer[1].pDmgHitDT
	local p2_hit_dt = cPlayer[0].pDmgHitDT
	
	if p1_engine then
		p1_data.action_id = p1_engine:get_ActionID()
		p1_data.action_frame = p1_engine:get_ActionFrame()
		p1_data.end_frame = p1_engine:get_ActionFrameNum()
		p1_data.margin_frame = p1_engine:get_MarginFrame()
		p1_data.main_frame = p1_engine.mParam.action.ActionFrame.MainFrame
		p1_data.follow_frame = p1_engine.mParam.action.ActionFrame.FollowFrame
	end
	
	if p2_engine then
		p2_data.action_id = p2_engine:get_ActionID()
		p2_data.action_frame = p2_engine:get_ActionFrame()
		p2_data.end_frame = p2_engine:get_ActionFrameNum()
		p2_data.margin_frame = p2_engine:get_MarginFrame()
		p2_data.main_frame = p2_engine.mParam.action.ActionFrame.MainFrame
		p2_data.follow_frame = p2_engine.mParam.action.ActionFrame.FollowFrame        
	end

	p1.stun_frame = meter1.StunFrame
	p1.stun_frame_str = string.gsub(p1.stun_frame, "F", "")
	p1.stun_frame_int = tonumber(p1.stun_frame_str) or 0
	
	p1_data.hp_cap = player1.heal_new or 0
	p1_data.hp_current = player1.vital_new or 0
	p1_data.hp_cooldown = player1.healing_wait or 0
	p1_data.dir = bitand(player1.BitValue or 0, 128) == 128
	p1_data.burnout = player1.incapacitated or false
	p1_data.drive = player1.focus_new or 0
	if p1_data.burnout then
		p1_data.drive_adjusted = p1_data.drive - 60000
	else
		p1_data.drive_adjusted = p1_data.drive
	end
	p1_data.drive_cooldown = player1.focus_wait or 0
	p1_data.super = team1 and team1.mSuperGauge or 0
	p1_data.buff = player1.style_timer or 0
	p1_data.debuff_timer = player1.damage_cond and player1.damage_cond.timer or 0
	p1_data.gap = cPlayer[0].vs_distance.v / 65536.0
	if player1.pos and player1.pos.x then
		p1_data.pos_x = player1.pos.x.v / 65536.0
		p1_data.pos_y = player1.pos.y.v / 65536.0
	else
		p1_data.pos_x = 0
		p1_data.pos_y = 0
	end
	p1_data.combo_count = cPlayer[1].combo_scale.count
	p1_data.combo_scale_now = cPlayer[1].combo_scale.now
	p1_data.combo_scale_start = cPlayer[1].combo_scale.start
	p1_data.combo_scale_buff = cPlayer[1].combo_scale.buff
	p1_data.advantage = p1.stun_frame_int
	p1_data.char_id = p1_char_id or 0
	p1_data.char_name = char_id_table[p1_data.char_id or 0]
	p1_data.char_dict_file = MOVE_DICT_DIR .. tostring(p1_data.char_id) .. ".json"

	p2.stun_frame = meter2.StunFrame
	p2.stun_frame_str = string.gsub(p2.stun_frame, "F", "")
	p2.stun_frame_int = tonumber(p2.stun_frame_str) or 0
	
	p2_data.hp_cap = player2.heal_new or 0
	p2_data.hp_current = player2.vital_new or 0
	p2_data.hp_cooldown = player2.healing_wait or 0
	p2_data.dir = bitand(player2.BitValue or 0, 128) == 128
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
	p2_data.gap = cPlayer[1].vs_distance.v / 65536.0
	if player2.pos and player2.pos.x then
		p2_data.pos_x = player2.pos.x.v / 65536.0
		p2_data.pos_y = player2.pos.y.v / 65536.0
	else
		p2_data.pos_x = 0
		p2_data.pos_y = 0
	end
	p2_data.combo_count = cPlayer[0].combo_scale.count
	p2_data.combo_scale_now = cPlayer[0].combo_scale.now
	p2_data.combo_scale_start = cPlayer[0].combo_scale.start
	p2_data.combo_scale_buff = cPlayer[0].combo_scale.buff
	p2_data.advantage = p2.stun_frame_int
	p2_data.char_id = p2_char_id or 0
	p2_data.char_name = char_id_table[p2_data.char_id or 0]
	p2_data.char_dict_file = MOVE_DICT_DIR .. tostring(p2_data.char_id) .. ".json"
	
	return p1_data, p2_data
end

-- TODO Fix redundant saves on script reset
re.on_script_reset(function()
	clear_all_combos()
end)

re.on_frame(function()
	if not sPlayer then return end
	if sPlayer.prev_no_push_bit ~= 0 then
		hotkey_toggler()
		p1_prev, p2_prev = deep_copy(p1), deep_copy(p2)
		p1, p2 = process_player_info()
		
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

			combo_started = true
			combo_finished = false
		end

		if check_combo_in_progress() then
			if p1_combo_inputs[#p1_combo_inputs] ~= p1.action_id then
				table.insert(p1_combo_inputs, p1.action_id)
			end
			if p2_combo_inputs[#p2_combo_inputs] ~= p2.action_id then
				table.insert(p2_combo_inputs, p2.action_id)
			end
		end
		
		if check_combo_finished() then
			if (attacker == 0 and p1.advantage ~= 0) or (attacker == 1 and p2.advantage ~= 0) then
				combo_finish.p1 = deep_copy(p1)
				combo_finish.p1.inputs = p1_combo_inputs
				combo_finish.p2 = deep_copy(p2)
				combo_finish.p2.inputs = p2_combo_inputs
				combo_finished = true

				if auto_save_combos then
					save_combo()
				end
				
				combo_started = false
			end
		end
		if not hide_ui then
			imgui.begin_window("Combo Data", true, 1|8)
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
						imgui.table_setup_column("Health", nil, 15)
						imgui.table_setup_column("P1Drive", nil, 20)
						imgui.table_setup_column("P1Super", nil, 20)
						imgui.table_setup_column("P2Drive", nil, 20)
						imgui.table_setup_column("P2Super", nil, 20)
						imgui.table_setup_column("P1Carry", nil, 20)
						imgui.table_setup_column("P2Carry", nil, 20)
						imgui.table_setup_column("Adv", nil, 10)
						imgui.table_setup_column("Gap", nil, 10)
						imgui.table_headers_row()
						
						imgui.table_next_row()

						imgui.table_set_column_index(0)
						imgui.text("Start")

						imgui.table_set_column_index(1)
						if attacker == 0 then
							imgui.text(tostring(combo_start.p2.hp_current or ""))
						elseif attacker == 1 then
							imgui.text(tostring(combo_start.p1.hp_current or ""))
						end

						imgui.table_set_column_index(2)
						imgui.text(combo_start.p1.drive_adjusted or "")

						imgui.table_set_column_index(3)
						imgui.text(combo_start.p1.super or "")

						imgui.table_set_column_index(4)
						imgui.text(combo_start.p2.drive_adjusted or "")

						imgui.table_set_column_index(5)
						imgui.text(tostring(combo_start.p2.super or ""))

						imgui.table_set_column_index(6)
						if combo_start.p1.pos_x then
							imgui.text(string.format("%.1f", combo_start.p1.pos_x))
						else
							imgui.text("")            
						end

						imgui.table_set_column_index(7)
						if combo_start.p2.pos_x then
							imgui.text(string.format("%.1f", combo_start.p2.pos_x))
						else
							imgui.text("")
						end

						imgui.table_next_row()

						imgui.table_set_column_index(0)
						imgui.text("Finish")
						
						if not combo_started then
							imgui.table_set_column_index(1)
							if attacker == 0 then
								imgui.text(tostring(combo_finish.p2.hp_current or ""))
							elseif attacker == 1 then
								imgui.text(tostring(combo_finish.p1.hp_current or ""))
							end
							
							imgui.table_set_column_index(2)
							imgui.text(tostring(combo_finish.p1.drive_adjusted or ""))
							
							imgui.table_set_column_index(3)
							imgui.text(tostring(combo_finish.p1.super or ""))
							
							imgui.table_set_column_index(4)
							imgui.text(tostring(combo_finish.p2.drive_adjusted or ""))
							
							imgui.table_set_column_index(5)
							imgui.text(tostring(combo_finish.p2.super or ""))
							
							imgui.table_set_column_index(6)
							if combo_finish.p1.pos_x then
								imgui.text(string.format("%.1f", combo_finish.p1.pos_x))
							else
								imgui.text("")            
							end
							
							imgui.table_set_column_index(7)
							if combo_finish.p2.pos_x then
								imgui.text(string.format("%.1f", combo_finish.p2.pos_x))
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
								local finished_hp_diff = (combo_start.p2.hp_current or 0) - (combo_finish.p2.hp_current or 0)
								color(finished_hp_diff)
							elseif attacker == 1 then
								local finished_hp_diff = (combo_start.p1.hp_current or 0) - (combo_finish.p1.hp_current or 0)
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

							imgui.table_set_column_index(6)
							local p1_carry = 0
							if attacker == 0 and combo_finish.p1.dir then
								p1_carry = (combo_finish.p1.pos_x or 0) - (combo_start.p1.pos_x or 0)
							elseif attacker == 0 and not combo_finish.p1.dir then
								p1_carry = (combo_start.p1.pos_x or 0) - (combo_finish.p1.pos_x or 0)
							elseif attacker == 1 and combo_finish.p2.dir then
								p1_carry = (combo_finish.p1.pos_x or 0) - (combo_start.p1.pos_x or 0)
							elseif attacker == 1 and not combo_finish.p2.dir then
								p1_carry = (combo_start.p1.pos_x or 0) - (combo_finish.p1.pos_x or 0)
							end
							color(p1_carry)
							
							imgui.table_set_column_index(7)
							local p2_carry = 0
							if attacker == 0 and combo_finish.p1.dir then
								p2_carry = (combo_finish.p2.pos_x or 0) - (combo_start.p2.pos_x or 0)
							elseif attacker == 0 and not combo_finish.p1.dir then
								p2_carry = (combo_start.p2.pos_x or 0) - (combo_finish.p2.pos_x or 0) 
							elseif attacker == 1 and combo_finish.p2.dir then
								p2_carry = (combo_finish.p2.pos_x or 0) - (combo_start.p2.pos_x or 0)
							elseif attacker == 1 and not combo_finish.p2.dir then
								p2_carry = (combo_start.p2.pos_x or 0) - (combo_finish.p2.pos_x or 0)
							end
							color(p2_carry)

							imgui.table_set_column_index(8)
							if attacker == 0 then
								imgui.text(combo_finish.p1.advantage)
							elseif attacker == 1 then
								imgui.text(combo_finish.p2.advantage)
							end

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
							imgui.table_setup_column("Char", nil, 22)
							imgui.table_setup_column("Dmg", nil, 15)
							imgui.table_setup_column("P1Drive", nil, 20)
							imgui.table_setup_column("P1Super", nil, 20)
							imgui.table_setup_column("P2Drive", nil, 20)
							imgui.table_setup_column("P2Super", nil, 20)
							imgui.table_setup_column("P1Pos", nil, 15)
							imgui.table_setup_column("P2Pos", nil, 15)
							imgui.table_setup_column("Adv", nil, 20)
							imgui.table_setup_column("Gap", nil, 20)
							imgui.table_setup_column("Actions", nil, 23)
							imgui.table_headers_row()
							
							for i, combo in ipairs(all_combos) do
								imgui.table_next_row()
								
								imgui.table_set_column_index(0)
								imgui.text(combo.timestamp or "")

								imgui.table_set_column_index(1)
								if combo.totals.attacker == 0 then
									imgui.text(combo.totals.p1_char_name)
								elseif combo.totals.attacker == 1 then
									imgui.text(combo.totals.p2_char_name)
								else
									imgui.text("")
								end
								
								imgui.table_set_column_index(2)
								imgui.text(string.format("%.0f", combo.totals.damage or 0))
								
								imgui.table_set_column_index(3)
								local p1_drive = combo.totals.p1_drive or 0
								color(p1_drive)
								
								imgui.table_set_column_index(4)
								local p1_super = combo.totals.p1_super or 0
								color(p1_super)
								
								imgui.table_set_column_index(5)
								local p2_drive = combo.totals.p2_drive or 0
								color(p2_drive)
								
								imgui.table_set_column_index(6)
								local p2_super = combo.totals.p2_super or 0
								color(p2_super)

								imgui.table_set_column_index(7)
								if combo.totals.attacker == 0 then
									if combo.totals.p1_dir then
										color(combo.totals.p1_position)
									else
										color(-1 * combo.totals.p1_position)
									end
								elseif combo.totals.attacker == 1 then
									if combo.totals.p2_dir then
									color(combo.totals.p1_position)
									else
										color(-1 * combo.totals.p1_position)
									end
								end
								
								imgui.table_set_column_index(8)
								if combo.totals.attacker == 0 then
									if combo.totals.p1_dir then
										color(combo.totals.p2_position)
									else
										color(-1 * combo.totals.p2_position)
									end
								elseif combo.totals.attacker == 1 then
									if combo.totals.p2_dir then
									color(combo.totals.p2_position)
									else
										color(-1 * combo.totals.p2_position)
									end
								end

								imgui.table_set_column_index(9)
								if combo.totals.attacker == 0 then
									imgui.text(combo.totals.p1_advantage)
								elseif combo.totals.attacker == 1 then
									imgui.text(combo.totals.p2_advantage)
								end
								
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

										imgui.table_next_row()
										imgui.table_set_column_index(0)
										imgui.text("P1 Character:")

										imgui.table_set_column_index(1)
										imgui.text(combo.finish.p1.char_name)

										imgui.table_next_row()
										imgui.table_set_column_index(0)
										imgui.text("P2 Character:")

										imgui.table_set_column_index(1)
										imgui.text(combo.finish.p2.char_name)

										popup_separator()
										
										imgui.table_next_row()
										if combo.totals.attacker == 0 then
											imgui.table_set_column_index(0)
											imgui.text("Start P2 HP:")
											
											imgui.table_set_column_index(1)
											imgui.text(combo.start.p2.hp_current or 0)

											imgui.table_next_row()

											imgui.table_set_column_index(0)
											imgui.text("Finish P2 HP:")
											
											imgui.table_set_column_index(1)
											imgui.text(combo.finish.p2.hp_current or 0)

										elseif combo.totals.attacker == 1 then
											imgui.table_set_column_index(0)
											imgui.text("Start P1 HP:")
											
											imgui.table_set_column_index(1)
											imgui.text(combo.start.p1.hp_current or 0)

											imgui.table_next_row()
											
											imgui.table_set_column_index(0)
											imgui.text("Finish P1 HP:")
											
											imgui.table_set_column_index(1)
											imgui.text(combo.finish.p1.hp_current or 0)
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
										imgui.text(combo.start.p1.drive_adjusted or 0)
										
										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Finish P1 Drive:")
										
										imgui.table_set_column_index(1)
										imgui.text(combo.finish.p1.drive_adjusted or 0)

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Total P1 Drive:")
										
										imgui.table_set_column_index(1)
										color(combo.totals.p1_drive)

										popup_separator()
										
										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Start P1 Super:")
										
										imgui.table_set_column_index(1)
										imgui.text(combo.start.p1.super or 0)

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Finish P1 Super:")
										
										imgui.table_set_column_index(1)
										imgui.text(combo.finish.p1.super or 0)

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Total P1 Super:")
										
										imgui.table_set_column_index(1)
										color(combo.totals.p1_super)

										popup_separator()

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Start P2 Drive:")
										
										imgui.table_set_column_index(1)
										imgui.text(combo.start.p2.drive_adjusted or 0)

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Finish P2 Drive:")
										
										imgui.table_set_column_index(1)
										imgui.text(combo.finish.p2.drive_adjusted or 0)
										
										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Total P2 Drive:")
										
										imgui.table_set_column_index(1)
										color(combo.totals.p2_drive)

										popup_separator()
										
										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Start P2 Super:")
										
										imgui.table_set_column_index(1)
										imgui.text(combo.start.p2.super or 0)

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Finish P2 Super:")
										
										imgui.table_set_column_index(1)
										imgui.text(combo.finish.p2.super or 0)
										
										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Total P2 Super:")
										
										imgui.table_set_column_index(1)
										color(combo.totals.p2_super)

										popup_separator()
										
										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Start P1 Pos:")
										
										imgui.table_set_column_index(1)
										imgui.text(string.format("%.1f", combo.start.p1.pos_x or 0))

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Finish P1 Pos:")
										
										imgui.table_set_column_index(1)
										imgui.text(string.format("%.1f", combo.finish.p1.pos_x or 0))
										
										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("P1 Pos Δ:")
										
										imgui.table_set_column_index(1)
										if combo.totals.attacker == 0 then
											if not combo.totals.p1_dir then
												color(-1 * combo.totals.p1_position)
											else
												color(combo.totals.p1_position)
											end
										elseif combo.totals.attacker == 1 then
											if not combo.totals.p2_dir then
												color(-1 * combo.totals.p1_position)
											else
												color(combo.totals.p1_position)
											end
										end

										popup_separator()

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Start P2 Pos:")
										
										imgui.table_set_column_index(1)
										imgui.text(string.format("%.1f", combo.start.p2.pos_x or 0))

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Finish P2 Pos:")
										
										imgui.table_set_column_index(1)
										imgui.text(string.format("%.2f", combo.finish.p2.pos_x or 0))
										
										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("P2 Pos Δ:")
										
										imgui.table_set_column_index(1)
										if combo.totals.attacker == 0 then
											if not combo.totals.p1_dir then
												color(-1 * combo.totals.p2_position)
											else
												color(combo.totals.p2_position)
											end
										elseif combo.totals.attacker == 1 then
											if not combo.totals.p2_dir then
												color(-1 * combo.totals.p2_position)
											else
												color(combo.totals.p2_position)
											end
										end

										popup_separator()

										imgui.table_next_row()
										imgui.table_set_column_index(0)
										imgui.text("Advantage:")

										imgui.table_set_column_index(1)
										if combo.totals.attacker == 0 then
											imgui.text(combo.totals.p1_advantage)
										elseif combo.totals.attacker == 1 then
											imgui.text(combo.totals.p2_advantage)
										end

										imgui.table_next_row()
										
										imgui.table_set_column_index(0)
										imgui.text("Gap:")

										imgui.table_set_column_index(1)
										imgui.text(combo.totals.gap)

										popup_separator()

										imgui.table_next_row()

										imgui.table_set_column_index(0)
										imgui.text("P1 Actions:")

										imgui.table_set_column_index(1)
										local p1_inputs = ""
										for k, v in pairs(combo.finish.p1.inputs) do
											p1_inputs = tostring(p1_inputs) .. v .. " "
										end
										imgui.text(p1_inputs)

										imgui.table_next_row()

										imgui.table_set_column_index(0)
										imgui.text("P2 Actions:")

										imgui.table_set_column_index(1)
										local p2_inputs = ""
										for k, v in pairs(combo.finish.p2.inputs) do
											p2_inputs = tostring(p2_inputs) .. v .. " "
										end
										imgui.text(p2_inputs)

										popup_separator()

										imgui.table_next_row()

										imgui.table_set_column_index(0)
										imgui.text("P1 Action Names:")

										imgui.table_set_column_index(1)
										local p1_named = ""
										for k, v in pairs(combo.totals.p1_actions_named) do
											p1_named = tostring(p1_named) .. v .. " "
										end
										imgui.text(p1_named)
										

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
	end
end)