local CONFIG_PATH = "better_disp_hitboxes.json"
local SAVE_DELAY = 0.5
local KEY_CTRL = 0x11
local KEY_F1 = 0x70
local KEY_1 = 0x31
local KEY_2 = 0x32

local gBattle, sPlayer, pause_manager
local this = {}

this.prev_key_states, this.presets, this.preset_names, this.string_buffer = {}, {}, {}, {}
this.current_preset_name, this.previous_preset_name, this.new_preset_name, this.rename_temp_name = "", "", "", ""
this.initialized, this.rename_mode, this.create_new_mode = false, false, false
this.key_ready, this.save_pending, this.save_timer, this.changed, this.config, this.pause_type_bit = nil, nil, nil, nil, nil, nil
this.alpha, this.world_pos = nil, nil
this.screenTL, this.screenTR, this.screenBL, this.screenBR = nil, nil, nil, nil
this.posX, this.posY, this.sclX, this.sclY = nil, nil, nil, nil
this.vTL, this.vTR, this.vBL, this.vBR, this.vPos = Vector3f.new(0, 0, 0), Vector3f.new(0, 0, 0), Vector3f.new(0, 0, 0), Vector3f.new(0, 0, 0), Vector3f.new(0, 0, 0)
this.tmpVec2 = Vector2f.new(0, 0)

local function deep_copy(obj)
	if type(obj) ~= 'table' then return obj end
	local copy = {}
	for k, v in pairs(obj) do copy[k] = deep_copy(v) end
	return copy
end

local function bitand(a, b) return (a % (b + b) >= b) and b or 0 end

local function create_default_config()
	local default_toggle = {
		toggle_show = true,
		hitboxes = true,
		hitboxes_outline = true,
		hurtboxes = true,
		hurtboxes_outline = true,
		pushboxes = true,
		pushboxes_outline = true,
		throwboxes = true,
		throwboxes_outline = true,
		throwhurtboxes = true,
		throwhurtboxes_outline = true,
		proximityboxes = true,
		proximityboxes_outline = true,
		clashboxes = true,
		clashboxes_outline = true,
		uniqueboxes = true,
		uniqueboxes_outline = true,
		properties = true,
		position = true	
	}

	local default_opacity = {
		hitbox = 25,
		hitbox_outline = 25,
		hurtbox = 25,
		hurtbox_outline = 25,
		pushbox = 25,
		pushbox_outline = 25,
		throwbox = 25,
		throwbox_outline = 25,
		throwhurtbox = 25,
		throwhurtbox_outline = 25,
		proximitybox = 25,
		proximitybox_outline = 25,
		clashbox = 25,
		clashbox_outline = 25,
		uniquebox = 25,
		uniquebox_outline = 25,
		properties = 100,
		position = 100
	}

	return {
		options = {display_menu = true},
		p1 = {toggle = deep_copy(default_toggle), opacity = deep_copy(default_opacity)},
		p2 = {toggle = deep_copy(default_toggle), opacity = deep_copy(default_opacity)}
	}
end

local function mark_for_save() this.save_pending = true; this.save_timer = SAVE_DELAY; end

local function validate_config(cfg)
	if not cfg.options then cfg.options = { display_menu = true } end
	if not cfg.p1 then cfg.p1 = { toggle = {}, opacity = {} } end
	if not cfg.p2 then cfg.p2 = { toggle = {}, opacity = {} } end
	local default = create_default_config()
	for _, player in ipairs({"p1", "p2"}) do
		if not cfg[player].toggle then cfg[player].toggle = {} end
		if not cfg[player].opacity then cfg[player].opacity = {} end
		for k, v in pairs(default[player].toggle) do
			if cfg[player].toggle[k] == nil then cfg[player].toggle[k] = v end end
		for k, v in pairs(default[player].opacity) do
			if cfg[player].opacity[k] == nil then cfg[player].opacity[k] = v end end
	end
	for k, v in pairs(default.options) do
		if cfg.options[k] == nil then cfg.options[k] = v end end
	return cfg
end

local function save_config()
	local data_to_save = {
		presets = this.presets,
		current_preset = this.current_preset_name,
		config = this.config
	}; json.dump_file(CONFIG_PATH, data_to_save); this.save_pending = false
end

local function load_config()
	local loaded = json.load_file(CONFIG_PATH)
	if loaded then
		if loaded.presets then
			this.presets, this.preset_names = loaded.presets, {}
			for name, _ in pairs(this.presets) do table.insert(this.preset_names, name) end
		end
		if loaded.current_preset then this.current_preset_name = loaded.current_preset end
		if loaded.config then this.config = validate_config(loaded.config)
		else this.config = validate_config(loaded) end
	else
		this.config = create_default_config()
		this.presets, this.current_preset_name, this.preset_names = {}, "", {}
	mark_for_save(); end
end

local function get_preset_name()
	local base_name, i = "Preset ", 1
	while true do local candidate = base_name .. i
		if not this.presets[candidate] then return candidate end; i = i + 1; end
end

local function save_current_preset(name)
	if name and name ~= "" then
		this.presets[name] = {p1 = deep_copy(this.config.p1), p2 = deep_copy(this.config.p2)}
		this.preset_names = {}
		for preset_name, _ in pairs(this.presets) do table.insert(this.preset_names, preset_name) end
		this.current_preset_name, this.previous_preset_name = name, ""
	return true, mark_for_save(); end
	return false, "Invalid preset name"
end

local function load_preset(name)
	if this.presets[name] then
		local default, preset = create_default_config(), this.presets[name]
		for _, player in ipairs({"p1", "p2"}) do
			local merged_toggle = deep_copy(default[player].toggle)
			if preset[player].toggle then
				for k, v in pairs(preset[player].toggle) do
					merged_toggle[k] = v end
			end
			this.config[player].toggle = merged_toggle
			local merged_opacity = deep_copy(default[player].opacity)
			if preset[player].opacity then
				for k, v in pairs(preset[player].opacity) do
					merged_opacity[k] = v end
			end
			this.config[player].opacity = merged_opacity
		end
		this.current_preset_name, this.previous_preset_name = name, ""
		mark_for_save(); return true
	end; return false, "Preset not found"
end

local function delete_preset(name)
	if this.presets[name] then
		this.presets[name], this.preset_names = nil, {}
		for preset_name, _ in pairs(this.presets) do table.insert(this.preset_names, preset_name) end
		if this.current_preset_name == name then
			this.current_preset_name, this.previous_preset_name = "", "" end
		mark_for_save(); return true
	end; return false, "Preset not found"
end

local function rename_preset(old_name, new_name)
	if not old_name or old_name == "" then return false, "No preset selected" end
	if not new_name or new_name == "" then return false, "New name cannot be empty" end
	if new_name == old_name then return false, "New name is the same as the old name" end
	if this.presets[new_name] then return false, "A preset with this name already exists" end
	if this.presets[old_name] then
		this.presets[new_name], this.presets[old_name] = this.presets[old_name], nil
		this.preset_names = {}
		for preset_name, _ in pairs(this.presets) do table.insert(this.preset_names, preset_name) end
		if this.current_preset_name == old_name then
			this.current_preset_name, this.previous_preset_name = new_name, "" end
		mark_for_save(); return true
	end; return false, "Preset not found"
end

local function handle_rename_mode_input()
	this.changed, this.rename_temp_name = imgui.input_text("##preset_name", this.rename_temp_name, 32)
end

local function handle_create_new_mode_input()
	this.changed, this.new_preset_name = imgui.input_text("##preset_name", this.new_preset_name)
end

local function update_current_preset_name(new_name)
	if new_name == this.current_preset_name then return end
	if new_name == "" then
		this.current_preset_name = ""
		this.create_new_mode, this.rename_mode = false, false
	elseif this.presets[new_name] then
		this.current_preset_name, this.create_new_mode, this.rename_mode = new_name, false, false
	else
		if this.previous_preset_name == "" then this.previous_preset_name = this.current_preset_name end
		this.current_preset_name, this.create_new_mode, this.new_preset_name, this.rename_mode = new_name, true, new_name, false
	end
end

local function handle_normal_mode()
	local current_text = this.current_preset_name or ""
	this.changed, current_text = imgui.text(current_text)
end

local function save_rename()
	if this.rename_temp_name == "" then
	elseif this.rename_temp_name == this.current_preset_name then
		this.rename_mode, this.rename_temp_name = false, ""
	elseif this.presets[this.rename_temp_name] then
	else
		local success, error_msg = rename_preset(this.current_preset_name, this.rename_temp_name)
		if success then this.rename_mode, this.rename_temp_name = false, "" end
	end
end

local function handle_rename_mode_buttons()
	if imgui.button("Rename##save_rename") then
		if this.rename_temp_name == "" then
			this.rename_mode, this.rename_temp_name = false, ""
		elseif this.rename_temp_name == this.current_preset_name then
			this.rename_mode, this.rename_temp_name = false, ""
		else
			local success, error_msg = rename_preset(this.current_preset_name, this.rename_temp_name)
			if success then this.rename_mode, this.rename_temp_name = false, "" end end
	end
	imgui.same_line(); if imgui.button("Cancel##cancel_rename") then
		this.rename_mode, this.rename_temp_name = false, "" end
end

local function save_new_preset()
	if this.new_preset_name == "" then
	elseif this.presets[this.new_preset_name] then
		this.current_preset_name = this.new_preset_name
		this.create_new_mode, this.new_preset_name = false, ""
	else
		save_current_preset(this.new_preset_name)
		this.create_new_mode, this.new_preset_name = false, "" end
end

local function cancel_new_preset()
	this.create_new_mode, this.new_preset_name = false, ""
	if this.previous_preset_name ~= "" then
		this.current_preset_name, this.previous_preset_name = this.previous_preset_name, "" end
end

local function create_new_blank_preset()
	if this.previous_preset_name == "" then this.previous_preset_name = this.current_preset_name end
	this.new_preset_name, this.current_preset_name = get_preset_name(), this.new_preset_name
end

local function cancel_blank_preset()
	this.create_new_mode, this.new_preset_name = false, ""
	if this.previous_preset_name ~= "" then
		this.current_preset_name, this.previous_preset_name = this.previous_preset_name, ""
	else this.current_preset_name = "" end
end

local function handle_create_new_mode_buttons()
	if this.new_preset_name == "" then
		if imgui.button("New##new_blank") then create_new_blank_preset() end
		imgui.same_line(); if imgui.button("Cancel##cancel_blank") then cancel_blank_preset() end
	else if imgui.button("Save New##save_new") then save_new_preset() end
		imgui.same_line(); if imgui.button("Cancel##cancel_new") then cancel_new_preset() end end
end

local function is_preset_loaded(preset_name)
	if not preset_name or preset_name == "" then return false end	
	if not this.presets[preset_name] then return false end
	local preset = this.presets[preset_name]
	for _, player in ipairs({"p1", "p2"}) do
		local current_toggle, preset_toggle = this.config[player].toggle, preset[player].toggle
		for toggle_name, preset_value in pairs(preset_toggle) do
			if current_toggle[toggle_name] ~= preset_value then return false end end
		for toggle_name, _ in pairs(current_toggle) do
			if preset_toggle[toggle_name] == nil then return false end end
	end
	for _, player in ipairs({"p1", "p2"}) do
		local current_opacity = this.config[player].opacity
		local preset_opacity = preset[player].opacity
		for opacity_name, preset_value in pairs(preset_opacity) do
			if current_opacity[opacity_name] ~= preset_value then return false end end
		for opacity_name, _ in pairs(current_opacity) do
			if preset_opacity[opacity_name] == nil then return false end end
	end; return true
end

local function preset_has_unsaved_changes(preset_name)
	if not preset_name or preset_name == "" or not this.presets[preset_name] then return false end
	local preset = this.presets[preset_name]
	for _, player in ipairs({"p1", "p2"}) do
		local current_toggle = this.config[player].toggle
		local preset_toggle = preset[player].toggle
		local current_opacity = this.config[player].opacity
		local preset_opacity = preset[player].opacity
		for toggle_name, preset_value in pairs(preset_toggle) do
			if current_toggle[toggle_name] ~= preset_value then return true end end
		for toggle_name, _ in pairs(current_toggle) do
			if preset_toggle[toggle_name] == nil then return true end end
		for opacity_name, preset_value in pairs(preset_opacity) do
			if current_opacity[opacity_name] ~= preset_value then return true end end
		for opacity_name, _ in pairs(current_opacity) do
			if preset_opacity[opacity_name] == nil then return true end end
	end; return false
end

local function handle_normal_mode_buttons()
	if this.current_preset_name ~= "" and this.presets[this.current_preset_name] ~= nil then
		local has_unsaved = preset_has_unsaved_changes(this.current_preset_name)
		if has_unsaved then
			if imgui.button("Save##save_preset_unsaved") then
				save_current_preset(this.current_preset_name) end
			imgui.same_line(); if imgui.button("Discard##load_preset") then
				load_preset(this.current_preset_name) end
		else imgui.text("") end
		imgui.same_line(); if imgui.button("Rename##rename_current") then
			this.rename_mode = true
			this.rename_temp_name = this.current_preset_name end
		imgui.same_line(); if imgui.button("New##create_new") then
			this.create_new_mode = true
			if this.previous_preset_name == "" then
				this.previous_preset_name = this.current_preset_name end
			this.new_preset_name, this.current_preset_name = get_preset_name(), this.new_preset_name end
	elseif this.current_preset_name == "" then
		if imgui.button("New##create_new") then
			this.create_new_mode = true
			if this.previous_preset_name == "" then
				this.previous_preset_name = this.current_preset_name end
			this.new_preset_name, this.current_preset_name = get_preset_name(), this.new_preset_name end
	else
		if imgui.button("Save New##save_new_from_text") then
			save_current_preset(this.current_preset_name)
			this.create_new_mode = false end
		imgui.same_line(); if imgui.button("New##create_new_fallback") then
			this.create_new_mode = true
			if this.previous_preset_name == "" then
				this.previous_preset_name = this.current_preset_name end
			this.new_preset_name, this.current_preset_name = get_preset_name(), this.new_preset_name end
	end
end

local function preset_mode_handler()
	if this.rename_mode then handle_rename_mode_buttons()
	elseif this.create_new_mode then handle_create_new_mode_buttons()
	else handle_normal_mode_buttons() end
end

local function copy_player(player)
	if player == 0 then this.config.p2 = deep_copy(this.config.p1) else this.config.p1 = deep_copy(this.config.p2) end
end

local function reset_all_default(player)
	local default = create_default_config()
	if player == nil then
		this.config.p1 = deep_copy(default.p1)
		this.config.p2 = deep_copy(default.p2)
	elseif player == "p1" or player == "p2" then
		this.config[player] = deep_copy(default[player]) end
	mark_for_save(); return this.config
end

local function reset_toggle_default(player)
	local default = create_default_config()
	if player == nil then
		this.config.p1.toggle = deep_copy(default.p1.toggle)
		this.config.p2.toggle = deep_copy(default.p2.toggle)
	elseif player == "p1" or player == "p2" then
		this.config[player].toggle = deep_copy(default[player].toggle) end
	mark_for_save(); return this.config
end

local function reset_opacity_default(player)
	local default = create_default_config()
	if player == nil then
		this.config.p1.opacity = deep_copy(default.p1.opacity)
		this.config.p2.opacity = deep_copy(default.p2.opacity)
	elseif player == "p1" or player == "p2" then
		this.config[player].opacity = deep_copy(default[player].opacity) end
	mark_for_save(); return this.config
end

local function apply_opacity(alphaInt, colorWithoutAlpha)
	alphaInt = math.max(0, math.min(100, alphaInt))
	this.alpha = math.floor((alphaInt / 100) * 255)
	return this.alpha * 0x1000000 + colorWithoutAlpha
end

local function is_pause_menu_closed()
	if not pause_manager then pause_manager = sdk.get_managed_singleton("app.PauseManager")
	elseif pause_manager then this.pause_type_bit = pause_manager:get_field("_CurrentPauseTypeBit") end
	return this.pause_type_bit == 64 or this.pause_type_bit == 2112
end

local function get_prev_push_bit() return gBattle:get_field("Player"):get_data(nil).prev_no_push_bit end

local function reverse_pairs(aTable)
	local keys = {}
	for k, v in pairs(aTable) do keys[#keys+1] = k end
	table.sort(keys, function (a, b) return a > b end)
	local n = 0
	return function()
		n = n + 1; if n > #keys then return nil, nil end
		return keys[n], aTable[keys[n]] end
end

local function get_screen_dimensions(vtl, vtr, vbl, vbr)
	local dw = draw.world_to_screen
	local tl, tr, bl, br = dw(vtl), dw(vtr), dw(vbl), dw(vbr)
	return (tl.x + tr.x) / 2, (bl.y + tl.y) / 2, (tr.x - tl.x), (tl.y - bl.y)
end

local function draw_hitboxes(work, actParam, player_config)
    local col = actParam.Collision
    for j, rect in reverse_pairs(col.Infos._items) do
        if rect ~= nil then
            this.posX, this.posY = rect.OffsetX.v / 6553600.0, rect.OffsetY.v / 6553600.0
            this.sclX, this.sclY = rect.SizeX.v / 6553600.0 * 2, rect.SizeY.v / 6553600.0 * 2
            this.posX, this.posY = this.posX - this.sclX / 2, this.posY - this.sclY / 2
			this.vTL.x, this.vTL.y, this.vTL.z = this.posX - this.sclX / 2,  this.posY + this.sclY / 2, 0
            this.vTR.x, this.vTR.y, this.vTR.z = this.posX + this.sclX / 2, this.posY + this.sclY / 2, 0
            this.vBL.x, this.vBL.y, this.vBL.z = this.posX - this.sclX / 2, this.posY - this.sclY / 2, 0
            this.vBR.x, this.vBR.y, this.vBR.z = this.posX + this.sclX / 2, this.posY - this.sclY / 2, 0
			local finalPosX, finalPosY, finalSclX, finalSclY = get_screen_dimensions(this.vTL, this.vTR, this.vBL, this.vBR)
			if rect:get_field("HitPos") ~= nil then
				if rect.TypeFlag > 0 then
					if player_config.toggle.hitboxes_outline then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.hitbox_outline, 0x0040C0))
					end
					if player_config.toggle.hitboxes then
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.hitbox, 0x0040C0))
					end
					if player_config.toggle.properties then
						local buffer_idx, has_exceptions, has_combo = 0, false, false
						if bitand(rect.CondFlag, 16) == 16 or bitand(rect.CondFlag, 32) == 32 or 
							bitand(rect.CondFlag, 64) == 64 or bitand(rect.CondFlag, 256) == 256 or 
							bitand(rect.CondFlag, 512) == 512 then
							buffer_idx = buffer_idx + 1
							this.string_buffer[buffer_idx] = "Can't Hit "
							if bitand(rect.CondFlag, 16) == 16 then 
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Standing, " 
							end
							if bitand(rect.CondFlag, 32) == 32 then 
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Crouching, " 
							end
							if bitand(rect.CondFlag, 64) == 64 then 
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Airborne, " 
							end
							if bitand(rect.CondFlag, 256) == 256 then 
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Forward, " 
							end
							if bitand(rect.CondFlag, 512) == 512 then 
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Backwards, " 
							end
							this.string_buffer[buffer_idx] = string.sub(this.string_buffer[buffer_idx], 1, -3)
							buffer_idx = buffer_idx + 1
							this.string_buffer[buffer_idx] = "\n"
							has_exceptions = true
						end
						if bitand(rect.CondFlag, 262144) == 262144 or bitand(rect.CondFlag, 524288) == 524288 then
							buffer_idx = buffer_idx + 1
							this.string_buffer[buffer_idx] = "Combo Only\n"
							has_combo = true
						end
						if has_exceptions or has_combo then
							local fullString = table.concat(this.string_buffer, "", 1, buffer_idx)
							draw.text(fullString, finalPosX, (finalPosY + finalSclY),
								apply_opacity(player_config.opacity.properties, 0xFFFFFF))
						end
					end
				elseif ((rect.TypeFlag == 0 and rect.PoseBit > 0) or rect.CondFlag == 0x2C0) then
					if player_config.toggle.throwboxes_outline then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.throwbox_outline, 0xD080FF))
					end
					if player_config.toggle.throwboxes then
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.throwbox, 0xD080FF))
					end
					if player_config.toggle.properties then
						local buffer_idx, has_exceptions, has_combo = 0, false, false
						if bitand(rect.CondFlag, 16) == 16 or bitand(rect.CondFlag, 32) == 32 or 
							bitand(rect.CondFlag, 64) == 64 or bitand(rect.CondFlag, 256) == 256 or 
							bitand(rect.CondFlag, 512) == 512 then
							buffer_idx = buffer_idx + 1
							this.string_buffer[buffer_idx] = "Can't Hit "
							if bitand(rect.CondFlag, 16) == 16 then
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Standing, " end
							if bitand(rect.CondFlag, 32) == 32 then 
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Crouching, " end
							if bitand(rect.CondFlag, 64) == 64 then 
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Airborne, " end
							if bitand(rect.CondFlag, 256) == 256 then 
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Forward, " end
							if bitand(rect.CondFlag, 512) == 512 then 
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Backwards, " end
							this.string_buffer[buffer_idx] = string.sub(this.string_buffer[buffer_idx], 1, -3)
							buffer_idx = buffer_idx + 1
							this.string_buffer[buffer_idx] = "\n"
							has_exceptions = true
						end
						if bitand(rect.CondFlag, 262144) == 262144 or bitand(rect.CondFlag, 524288) == 524288 then
							buffer_idx = buffer_idx + 1
							this.string_buffer[buffer_idx] = "Combo Only\n"
							has_combo = true
						end
						if has_exceptions or has_combo then
							local fullString = table.concat(this.string_buffer, "", 1, buffer_idx)
							draw.text(fullString, finalPosX, (finalPosY + finalSclY),
								apply_opacity(player_config.opacity.properties, 0xFFFFFF)) end
					end
				elseif rect.GuardBit == 0 then
					if player_config.toggle.clashboxes_outline then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.clashbox_outline, 0x3891E6)) end
					if player_config.toggle.clashboxes then
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.clashbox, 0x3891E6)) end
				else
					if player_config.toggle.proximityboxes_outline then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.proximitybox_outline, 0x5b5b5b)) end
					if player_config.toggle.proximityboxes then
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.proximitybox, 0x5b5b5b)) end
				end
			elseif rect:get_field("Attr") ~= nil then
				if player_config.toggle.pushboxes_outline then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.pushbox_outline, 0x00FFFF)) end
				if player_config.toggle.pushboxes then
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.pushbox, 0x00FFFF)) end
			elseif rect:get_field("HitNo") ~= nil then
				if rect.TypeFlag > 0 then
					if player_config.toggle.hurtboxes or player_config.toggle.hurtboxes_outline then
						if rect.Type == 2 or rect.Type == 1 then
							if player_config.toggle.hurtboxes_outline then
								draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
									apply_opacity(player_config.opacity.hurtbox_outline, 0xFF0080)) end
							if player_config.toggle.hurtboxes then
								draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
									apply_opacity(player_config.opacity.hurtbox, 0xFF0080)) end
						else
							if player_config.toggle.hurtboxes_outline then
								draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
									apply_opacity(player_config.opacity.hurtbox_outline, 0x00FF00)) end
							if player_config.toggle.hurtboxes then
								draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
									apply_opacity(player_config.opacity.hurtbox, 0x00FF00)) end
						end
						if player_config.toggle.properties then
							local buffer_idx = 0
							if rect.TypeFlag == 1 then
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Projectile Invulnerable\n"
							elseif rect.TypeFlag == 2 then
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = "Strike Invulnerable\n" end
							local has_immune = false
							if bitand(rect.Immune, 1) == 1 or bitand(rect.Immune, 2) == 2 or 
								bitand(rect.Immune, 4) == 4 or bitand(rect.Immune, 64) == 64 or 
								bitand(rect.Immune, 128) == 128 then
								has_immune = true
								if bitand(rect.Immune, 1) == 1 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Stand, " end
								if bitand(rect.Immune, 2) == 2 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Crouch, " end
								if bitand(rect.Immune, 4) == 4 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Air, " end
								if bitand(rect.Immune, 64) == 64 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Behind, " end
								if bitand(rect.Immune, 128) == 128 then 
									buffer_idx = buffer_idx + 1
									this.string_buffer[buffer_idx] = "Reverse, " end
								this.string_buffer[buffer_idx] = string.sub(this.string_buffer[buffer_idx], 1, -3)
								buffer_idx = buffer_idx + 1
								this.string_buffer[buffer_idx] = " Attack Intangible\n"
							end
							if buffer_idx > 0 then
								local fullString = table.concat(this.string_buffer, "", 1, buffer_idx)
								draw.text(fullString, finalPosX, (finalPosY + finalSclY),
									apply_opacity(player_config.opacity.properties, 0xFFFFFF)) end
						end
					end
				elseif player_config.toggle.throwhurtboxes or player_config.toggle.throwhurtboxes_outline then
					if player_config.toggle.throwhurtboxes_outline then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.throwhurtbox_outline, 0xFF0000)) end
					if player_config.toggle.throwhurtboxes then
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
							apply_opacity(player_config.opacity.throwhurtbox, 0xFF0000)) end
				end
			elseif rect:get_field("KeyData") ~= nil then
				if player_config.toggle.uniqueboxes_outline then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.uniquebox_outline, 0xEEFF00)) end
				if player_config.toggle.uniqueboxes then
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.uniquebox, 0xEEFF00)) end
			else
				if player_config.toggle.throwhurtboxes_outline then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.throwhurtbox_outline, 0xFF0000)) end
				if player_config.toggle.throwhurtboxes then
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
						apply_opacity(player_config.opacity.throwhurtbox, 0xFF0000)) end
			end
        end
    end
    this.string_buffer = {}
end

local function toggle_setter(label, val)
	local changed, new_val = imgui.checkbox(label, val)
	if changed then mark_for_save() end; return changed, new_val
end

local function opacity_setter(label, val, speed, min, max)
	val = math.max(0, math.min(100, val))
	local changed, new_val = imgui.drag_int(label, val, speed or 1.0, min or 0, max or 100)
	if changed then mark_for_save() end; return changed, new_val
end

local function init_config()
	load_config()
	if this.current_preset_name == "" then this.current_preset_name = get_preset_name() end
	this.initialized = true
end

local function save_handler()
	if this.save_pending then
		this.save_timer = this.save_timer - (1.0 / 60.0)
		if this.save_timer <= 0 then save_config() end
	end
end

local function build_hotkeys()
	if not this.key_ready and not reframework:is_key_down(KEY_1) and not reframework:is_key_down(KEY_2) and not reframework:is_key_down(KEY_F1) then this.key_ready = true end
	if this.key_ready and reframework:is_key_down(KEY_F1) then
		this.config.options.display_menu = not this.config.options.display_menu
		this.key_ready = false end
	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_1) then
		this.config.p1.toggle.toggle_show = not this.config.p1.toggle.toggle_show
		this.key_ready = false; mark_for_save() end
	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_2) then
		this.config.p2.toggle.toggle_show = not this.config.p2.toggle.toggle_show
		this.key_ready = false; mark_for_save() end
end

local function build_toggler_with_opacity(label, config_suffix, opacity_suffix)
	imgui.table_next_row()
	imgui.table_set_column_index(0); imgui.text(label)	
	imgui.table_set_column_index(1)
	if this.config.p1.toggle.toggle_show then
		local id = "##p1_" .. config_suffix
		this.changed, this.config.p1.toggle[config_suffix] = toggle_setter(id, this.config.p1.toggle[config_suffix])
		if opacity_suffix and this.config.p1.opacity[opacity_suffix] ~= nil and this.config.p1.toggle[config_suffix] then
			imgui.same_line(); imgui.push_item_width(70)
			this.changed, this.config.p1.opacity[opacity_suffix] = opacity_setter("##p1_" .. opacity_suffix .. "Opacity", this.config.p1.opacity[opacity_suffix], 0.5, 0, 100)
		imgui.pop_item_width(); end
	end
	imgui.table_set_column_index(2)
	if this.config.p2.toggle.toggle_show then
		local id = "##p2_" .. config_suffix
		this.changed, this.config.p2.toggle[config_suffix] = toggle_setter(id, this.config.p2.toggle[config_suffix])
		if opacity_suffix and this.config.p2.opacity[opacity_suffix] ~= nil and this.config.p2.toggle[config_suffix] then
			imgui.same_line(); imgui.push_item_width(70)
			this.changed, this.config.p2.opacity[opacity_suffix] = opacity_setter("##p2_" .. opacity_suffix .. "Opacity", this.config.p2.opacity[opacity_suffix], 0.5, 0, 100)
		imgui.pop_item_width(); end
	end
end

-- TODO Set up flags
local function imgui_table_setup_columns(widths, flags, names)
	local col_name = ""
	for _, i in pairs(widths) do
		if names then col_name = names[i] or "" end
		imgui.table_setup_column(col_name, 0, i) end
end

local function build_presets_table()
	if not imgui.begin_table("PresetTable", 3) then return end
	imgui_table_setup_columns({150, 60, 60})	
	for _, preset_name in ipairs(this.preset_names) do
		imgui.table_next_row()		
		imgui.table_set_column_index(0); imgui.text(preset_name)
		imgui.table_set_column_index(1)
		if imgui.button("Load##load_" .. preset_name) then
			load_preset(preset_name)
			this.create_new_mode, this.rename_mode, this.new_preset_name, this.rename_temp_name = false, false, "", ""
		end
		imgui.table_set_column_index(2)
		if imgui.button("Delete##delete_" .. preset_name) then
			delete_preset(preset_name)
			if this.current_preset_name == preset_name then
				this.current_preset_name, this.create_new_mode, this.rename_mode = "", false, false
			end; break
		end
	end; imgui.end_table()
end

local function build_presets()
	if not imgui.tree_node("Presets") then return end -- imgui_set_next_item_open(true, 0 << 3)
	if this.create_new_mode then imgui.text("New:")
	elseif this.rename_mode then imgui.text("Rename:")
	else imgui.text("Current:") end
	imgui.same_line(); imgui.push_item_width(100)
	if this.rename_mode then handle_rename_mode_input()
	elseif this.create_new_mode then handle_create_new_mode_input()
	else handle_normal_mode() end
	imgui.pop_item_width(); imgui.same_line()
	preset_mode_handler(); build_presets_table(); imgui.tree_pop()
end

local function build_toggle_header(player_int, changed, toggle)
	if not player_int then return false end
	local imgui_text, header_name = string.format("P%.0f", player_int), string.format("##p%.0f", player_int)
	imgui.text(imgui_text); imgui.same_line()
	local cursor_pos = imgui.get_cursor_pos()
	this.tmpVec2.x, this.tmpVec2.y = cursor_pos.x + 20, cursor_pos.y
	imgui.set_cursor_pos(this.tmpVec2)
end

local function build_toggles()
	if imgui.tree_node("Toggle") then -- imgui.set_next_item_open(true, 0 << 1)
		if imgui.begin_table("ToggleTable", 3) then
			imgui_table_setup_columns({150, 125, 125}, nil, {"", "P1", "P2"}); imgui.table_next_row()
			imgui.table_set_column_index(1); build_toggle_header(1)
			this.changed, this.config.p1.toggle.toggle_show = toggle_setter("##p1_HideAllHeader", this.config.p1.toggle.toggle_show)
			imgui.table_set_column_index(2); build_toggle_header(2)
			this.changed, this.config.p2.toggle.toggle_show = toggle_setter("##p2_HideAllHeader", this.config.p2.toggle.toggle_show)
			if this.config.p1.toggle.toggle_show or this.config.p2.toggle.toggle_show then
				build_toggler_with_opacity("Hitbox", "hitboxes", "hitbox")
				build_toggler_with_opacity("Hitbox Outline", "hitboxes_outline", "hitbox_outline")
				build_toggler_with_opacity("Hurtbox", "hurtboxes", "hurtbox")
				build_toggler_with_opacity("Hurtbox Outline", "hurtboxes_outline", "hurtbox_outline")
				build_toggler_with_opacity("Pushbox", "pushboxes", "pushbox")
				build_toggler_with_opacity("Pushbox Outline", "pushboxes_outline", "pushbox_outline")
				build_toggler_with_opacity("Throwbox", "throwboxes", "throwbox")
				build_toggler_with_opacity("Throwbox Outline", "throwboxes_outline", "throwbox_outline")
				build_toggler_with_opacity("Throw Hurtbox", "throwhurtboxes", "throwhurtbox")
				build_toggler_with_opacity("Throw Hurtbox Outline", "throwhurtboxes_outline", "throwhurtbox_outline")
				build_toggler_with_opacity("Proximity Box", "proximityboxes", "proximitybox")
				build_toggler_with_opacity("Proximity Box Outline", "proximityboxes_outline", "proximitybox_outline")
				build_toggler_with_opacity("Proj. Clash Box", "clashboxes", "clashbox")
				build_toggler_with_opacity("Proj. Clash Box Outline", "clashboxes_outline", "clashbox_outline")
				build_toggler_with_opacity("Unique Box", "uniqueboxes", "uniquebox")
				build_toggler_with_opacity("Unique Box Outline", "uniqueboxes_outline", "uniquebox_outline")
				build_toggler_with_opacity("Properties", "properties", "properties")
				build_toggler_with_opacity("Position", "position", "position")
				imgui.table_next_row()
				imgui.table_set_column_index(0); imgui.text("All")
				imgui.table_set_column_index(1)
				if this.config.p1.toggle.toggle_show then
					local all_checked, any_checked = false, false
					for toggle_name, toggle_value in pairs(this.config.p1.toggle) do
						if toggle_name ~= "toggle_show" then
							if toggle_value then any_checked = true end end
					end
					all_checked = any_checked
					this.changed, all_checked = toggle_setter("##p1_ToggleAll", all_checked)
					if this.changed then
						for toggle_name, _ in pairs(this.config.p1.toggle) do
							if toggle_name ~= "toggle_show" then
								this.config.p1.toggle[toggle_name] = all_checked end
						end
					mark_for_save(); end
					if all_checked then
						imgui.same_line(); imgui.push_item_width(70)
						local current_opacity_slider, all_same, first_opacity = 50, true, nil
						for opacity_name, opacity_value in pairs(this.config.p1.opacity) do
							if first_opacity == nil then first_opacity = opacity_value
							elseif opacity_value ~= first_opacity then all_same = false break end
						end
						if all_same and first_opacity ~= nil then
							current_opacity_slider = first_opacity
						else current_opacity_slider = 50 end
						this.changed, current_opacity_slider = opacity_setter("##p1_GlobalOpacity", current_opacity_slider, 0.5, 0, 100)
						if this.changed then
							for opacity_name, _ in pairs(this.config.p1.opacity) do
								this.config.p1.opacity[opacity_name] = current_opacity_slider end
						mark_for_save(); end; imgui.pop_item_width()
					end
				end
				imgui.table_set_column_index(2)
				if this.config.p2.toggle.toggle_show then
					local all_checked, any_checked = false, false
					for toggle_name, toggle_value in pairs(this.config.p2.toggle) do
						if toggle_name ~= "toggle_show" then
							if toggle_value then any_checked = true end end
					end
					all_checked = any_checked
					this.changed, all_checked = toggle_setter("##p2_ToggleAll", all_checked)
					if this.changed then
						for toggle_name, _ in pairs(this.config.p2.toggle) do
							if toggle_name ~= "toggle_show" then
								this.config.p2.toggle[toggle_name] = all_checked end
						end
					mark_for_save(); end
					if all_checked then
						imgui.same_line(); imgui.push_item_width(70)
						local current_opacity_slider = 50
						local all_same = true
						local first_opacity = nil
						for opacity_name, opacity_value in pairs(this.config.p2.opacity) do
							if first_opacity == nil then first_opacity = opacity_value
							elseif opacity_value ~= first_opacity then all_same = false break end
						end
						if all_same and first_opacity ~= nil then
							current_opacity_slider = first_opacity
						else current_opacity_slider = 50 end
						this.changed, current_opacity_slider = opacity_setter("##p2_GlobalOpacity", current_opacity_slider, 0.5, 0, 100)
						if this.changed then
							for opacity_name, _ in pairs(this.config.p2.opacity) do
								this.config.p2.opacity[opacity_name] = current_opacity_slider
							end
						mark_for_save(); end
					imgui.pop_item_width(); end
				end
			end
		imgui.end_table(); end
	imgui.tree_pop(); end
end

local function build_reset_row(col_name, func)
	local handler_str = "P%.0f##%s_p%.0f"
	local handler_p1, handler_p2 = string.format(handler_str, 1, string.lower(col_name), 1), string.format(handler_str, 2, string.lower(col_name), 2)
	local handler_all = string.format("All##%s_all", string.lower(col_name))
	imgui.table_next_row()
	imgui.table_set_column_index(0); imgui.text(col_name)
	imgui.table_set_column_index(1); if imgui.button(handler_p1) then func('p1') end
	imgui.table_set_column_index(2); if imgui.button(handler_p2) then func('p2') end
	imgui.table_set_column_index(3); if imgui.button(handler_all) then func() end
end

local function build_options()
    if imgui.tree_node("Options") then
        if imgui.tree_node("Copy") then
            if imgui.button("P1 to P2##p1_to_p2") then copy_player(0) end
            imgui.same_line()
            if imgui.button("P2 to P1##p2_to_p1") then copy_player(1) end
		imgui.tree_pop(); end
        if imgui.tree_node("Reset") then
			if imgui.begin_table("ResetTable", 4) then
				imgui_table_setup_columns({100, 35, 35, 35})
				build_reset_row("Toggler", reset_toggle_default)
				build_reset_row("Opacity", reset_opacity_default)
				build_reset_row("All", reset_all_default)
			imgui.end_table(); end
		imgui.tree_pop(); end
	imgui.tree_pop(); end
end

local function draw_position_marker(entity, player_config)
    if not player_config.toggle.position then return end
    if not entity.pos or not entity.pos.x or not entity.pos.y then return end
    local x, y = entity.pos.x.v, entity.pos.y.v
    if not x or not y or (x == 0 and y == 0) then return end -- Prevent 0,0,0 midscreen glitch frame
    this.vPos.x, this.vPos.y, this.vPos.z = x / 6553600.0, y / 6553600.0, 0
    local screenPos = draw.world_to_screen(this.vPos)
    if screenPos then draw.filled_circle(screenPos.x, screenPos.y, 10,
		apply_opacity(player_config.opacity.position, 0xFFFFFF), 10)
    end
end

local function process_entity(entity)
    local config = nil
    if entity:get_IsTeam1P() then config = this.config.p1
    elseif entity:get_IsTeam2P() then config = this.config.p2 end
    if not config or not config.toggle.toggle_show then return end
    draw_hitboxes(entity, entity.mpActParam, config); draw_position_marker(entity, config)
end

local function build_hitboxes()
    local sWork, sPlayer = gBattle:get_field("Work"):get_data(nil), gBattle:get_field("Player"):get_data(nil)
    for _, obj in pairs(sWork.Global_work) do
        if obj.mpActParam and not obj:get_IsR0Die() then process_entity(obj) end end
    for _, player in pairs(sPlayer.mcPlayer) do
        if player.mpActParam then process_entity(player, player.mpActParam) end end
end

local function build_menu()
	imgui.begin_window("Hitboxes", true, 64)
	build_toggles(); build_presets(); build_options(); imgui.end_window()
end

local function build_gui()
	if this.config.options.display_menu then build_menu() end
	if is_pause_menu_closed() and (this.config.p1.toggle.toggle_show or this.config.p2.toggle.toggle_show) then build_hitboxes() end
end

if not this.initialized then init_config() end

re.on_draw_ui(function()
	if imgui.tree_node("Hitbox Viewer") then
		this.changed, this.config.options.display_menu = toggle_setter("Display Options Menu (F1)", this.config.options.display_menu)
	imgui.tree_pop(); end
end)

re.on_frame(function()
	if not gBattle then gBattle = sdk.find_type_definition("gBattle") else
		save_handler(); build_hotkeys(); build_gui() end
end)