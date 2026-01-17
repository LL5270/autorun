local CONFIG_PATH = "disp_hitboxes.json"
local SAVE_DELAY = 0.5
local KEY_CTRL = 0x11
local KEY_F1 = 0x70
local KEY_1 = 0x31
local KEY_2 = 0x32

local gBattle
local sPlayer
local pause_manager

local this = {}
this.save_pending = nil
this.save_timer = nil
this.changed = nil
this.config = nil
this.key_ready = nil
this.pause_type_bit = nil
this.prev_key_states = {}
this.presets = {}
this.preset_names = {}
this.current_preset_name = ""
this.initialized = false
this.create_new_mode = false
this.new_preset_name = ""
this.rename_mode = false
this.rename_temp_name = ""
this.rename_select_all = false
this.world_pos = nil
this.screenTL = nil
this.screenTR = nil
this.screenBL = nil
this.screenBR = nil
this.posX = nil
this.posY = nil
this.sclX = nil
this.sclY = nil
this.vTL = Vector3f.new(0, 0, 0)
this.vTR = Vector3f.new(0, 0, 0)
this.vBL = Vector3f.new(0, 0, 0)
this.vBR = Vector3f.new(0, 0, 0)
this.vPos = Vector3f.new(0, 0, 0)
this.world_to_screen = draw.world_to_screen
this.outline_rect = draw.outline_rect
this.filled_rect = draw.filled_rect
this.alpha = nil
this.string_buffer = {}

local function deep_copy(obj)
	if type(obj) ~= 'table' then
		return obj
	end
	local copy = {}
	for k, v in pairs(obj) do
		copy[k] = deep_copy(v)
	end
	return copy
end

local function bitand(a, b)
	return (a % (b + b) >= b) and b or 0 
end

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
		options = {
			display_menu = true
		},
		p1 = {
			toggle = deep_copy(default_toggle),
			opacity = deep_copy(default_opacity)
		},
		p2 = {
			toggle = deep_copy(default_toggle),
			opacity = deep_copy(default_opacity)
		}
	}
end

local function mark_for_save()
	this.save_pending = true
	this.save_timer = SAVE_DELAY
end

local function validate_config(cfg)
	if not cfg.options then
		cfg.options = { display_menu = true }
	end
	if not cfg.p1 then
		cfg.p1 = { toggle = {}, opacity = {} }
	end
	if not cfg.p2 then
		cfg.p2 = { toggle = {}, opacity = {} }
	end
	
	local default = create_default_config()
	for _, player in ipairs({"p1", "p2"}) do
		if not cfg[player].toggle then
			cfg[player].toggle = {}
		end
		if not cfg[player].opacity then
			cfg[player].opacity = {}
		end
		
		for k, v in pairs(default[player].toggle) do
			if cfg[player].toggle[k] == nil then
				cfg[player].toggle[k] = v
			end
		end
		
		for k, v in pairs(default[player].opacity) do
			if cfg[player].opacity[k] == nil then
				cfg[player].opacity[k] = v
			end
		end
	end
	
	for k, v in pairs(default.options) do
		if cfg.options[k] == nil then
			cfg.options[k] = v
		end
	end
	
	return cfg
end

local function save_config()
	local data_to_save = {
		presets = this.presets,
		current_preset = this.current_preset_name,
		config = this.config
	}
	json.dump_file(CONFIG_PATH, data_to_save)
	this.save_pending = false
end

local function load_config()
	local loaded = json.load_file(CONFIG_PATH)
	if loaded then
		if loaded.presets then
			this.presets = loaded.presets
			this.preset_names = {}
			for name, _ in pairs(this.presets) do
				table.insert(this.preset_names, name)
			end
		end
		
		if loaded.current_preset then
			this.current_preset_name = loaded.current_preset
		end
		
		if loaded.config then
			this.config = validate_config(loaded.config)
		else
			this.config = validate_config(loaded)
		end
	else
		this.config = create_default_config()
		this.presets = {}
		this.current_preset_name = ""
		this.preset_names = {}
		mark_for_save()
	end
end

local function get_dummy_preset_name()
	local base_name = "Preset "
	local i = 1
	while true do
		local candidate = base_name .. i
		if not this.presets[candidate] then
			return candidate
		end
		i = i + 1
	end
end

local function save_current_preset(name)
	if name and name ~= "" then
		this.presets[name] = {
			p1 = deep_copy(this.config.p1),
			p2 = deep_copy(this.config.p2)
		}
		
		this.preset_names = {}
		for preset_name, _ in pairs(this.presets) do
			table.insert(this.preset_names, preset_name)
		end
		
		this.current_preset_name = name
		mark_for_save()
		return true
	end
	return false, "Invalid preset name"
end

local function load_preset(name)
	if this.presets[name] then
		this.config.p1 = deep_copy(this.presets[name].p1)
		this.config.p2 = deep_copy(this.presets[name].p2)
		this.current_preset_name = name
		mark_for_save()
		return true
	end
	return false, "Preset not found"
end

local function delete_preset(name)
	if this.presets[name] then
		this.presets[name] = nil
		
		this.preset_names = {}
		for preset_name, _ in pairs(this.presets) do
			table.insert(this.preset_names, preset_name)
		end
		
		if this.current_preset_name == name then
			this.current_preset_name = ""
		end
		
		mark_for_save()
		return true
	end
	return false, "Preset not found"
end

local function rename_preset(old_name, new_name)
	if not old_name or old_name == "" then
		return false, "No preset selected"
	end
	
	if not new_name or new_name == "" then
		return false, "New name cannot be empty"
	end
	
	if new_name == old_name then
		return false, "New name is the same as the old name"
	end
	
	if this.presets[new_name] then
		return false, "A preset with this name already exists"
	end
	
	if this.presets[old_name] then
		this.presets[new_name] = this.presets[old_name]
		this.presets[old_name] = nil
		
		this.preset_names = {}
		for preset_name, _ in pairs(this.presets) do
			table.insert(this.preset_names, preset_name)
		end
		
		if this.current_preset_name == old_name then
			this.current_preset_name = new_name
		end
		
		mark_for_save()
		return true
	end
	
	return false, "Preset not found"
end

local function handle_rename_mode_input()
	this.changed, this.rename_temp_name = imgui.input_text("##preset_name", this.rename_temp_name, 32)
end

local function handle_create_new_mode_input()
	this.changed, this.new_preset_name = imgui.input_text("##preset_name", this.new_preset_name)
end

local function update_current_preset_name(new_name)
	if new_name == this.current_preset_name then
		return
	end
	
	if new_name == "" then
		this.current_preset_name = ""
		this.create_new_mode = false
		this.rename_mode = false
	elseif this.presets[new_name] then
		this.current_preset_name = new_name
		this.create_new_mode = false
		this.rename_mode = false
	else
		this.current_preset_name = new_name
		this.create_new_mode = true
		this.new_preset_name = new_name
		this.rename_mode = false
	end
end

local function handle_normal_mode_input()
	local current_text = this.current_preset_name or ""
	this.changed, current_text = imgui.input_text("##preset_name", current_text)
	
	if this.changed then
		update_current_preset_name(current_text)
	end
end

local function save_rename()
	if this.rename_temp_name == "" then
	elseif this.rename_temp_name == this.current_preset_name then
		this.rename_mode = false
		this.rename_temp_name = ""
	elseif this.presets[this.rename_temp_name] then
	else
		rename_preset(this.current_preset_name, this.rename_temp_name)
		this.rename_mode = false
		this.rename_temp_name = ""
	end
end

local function handle_rename_mode_buttons()
	if imgui.button("Rename##save_rename") then
		if this.rename_temp_name == "" then
			this.rename_mode = false
			this.rename_temp_name = ""
		elseif this.rename_temp_name == this.current_preset_name then
			this.rename_mode = false
			this.rename_temp_name = ""
		else
			local success, error_msg = rename_preset(this.current_preset_name, this.rename_temp_name)
			if success then
				this.rename_mode = false
				this.rename_temp_name = ""
			end
		end
	end
	
	imgui.same_line()
	
	if imgui.button("Cancel##cancel_rename") then
		this.rename_mode = false
		this.rename_temp_name = ""
	end
end

local function save_new_preset()
	if this.new_preset_name == "" then
	elseif this.presets[this.new_preset_name] then
		this.current_preset_name = this.new_preset_name
		this.create_new_mode = false
		this.new_preset_name = ""
	else
		save_current_preset(this.new_preset_name)
		this.create_new_mode = false
		this.new_preset_name = ""
	end
end

local function cancel_new_preset()
	if this.current_preset_name and this.presets[this.current_preset_name] then
		this.create_new_mode = false
		this.new_preset_name = ""
	else
		this.current_preset_name = ""
		this.create_new_mode = false
		this.new_preset_name = ""
	end
end

local function create_new_blank_preset()
	this.new_preset_name = get_dummy_preset_name()
	this.current_preset_name = this.new_preset_name
end

local function cancel_blank_preset()
	if this.current_preset_name and this.presets[this.current_preset_name] then
		this.create_new_mode = false
		this.new_preset_name = ""
	else
		this.current_preset_name = ""
		this.create_new_mode = false
		this.new_preset_name = ""
	end
end

local function handle_create_new_mode_buttons()
	if this.new_preset_name == "" then
		if imgui.button("New##new_blank") then
			create_new_blank_preset()
		end
		
		imgui.same_line()
		
		if imgui.button("Cancel##cancel_blank") then
			cancel_blank_preset()
		end
	else
		if imgui.button("Save New##save_new") then
			save_new_preset()
		end
		
		imgui.same_line()
		
		if imgui.button("Cancel##cancel_new") then
			cancel_new_preset()
		end
	end
end

local function is_preset_loaded(preset_name)
	if not preset_name or preset_name == "" then
		return false
	end
	
	if not this.presets[preset_name] then
		return false
	end
	
	local preset = this.presets[preset_name]
	
	for _, player in ipairs({"p1", "p2"}) do
		local current_toggle = this.config[player].toggle
		local preset_toggle = preset[player].toggle
		
		for toggle_name, preset_value in pairs(preset_toggle) do
			if current_toggle[toggle_name] ~= preset_value then
				return false
			end
		end
		
		for toggle_name, _ in pairs(current_toggle) do
			if preset_toggle[toggle_name] == nil then
				return false
			end
		end
	end
	
	for _, player in ipairs({"p1", "p2"}) do
		local current_opacity = this.config[player].opacity
		local preset_opacity = preset[player].opacity
		
		for opacity_name, preset_value in pairs(preset_opacity) do
			if current_opacity[opacity_name] ~= preset_value then
				return false
			end
		end
		
		for opacity_name, _ in pairs(current_opacity) do
			if preset_opacity[opacity_name] == nil then
				return false
			end
		end
	end
	
	return true
end

local function handle_loaded_preset_buttons()
	if imgui.button("Save##save_preset") then
		save_current_preset(this.current_preset_name)
	end
	
	imgui.same_line()
	if imgui.button("Rename##rename_current") then
		this.rename_mode = true
		this.rename_temp_name = this.current_preset_name
	end
	
	imgui.same_line()
	if imgui.button("Delete##delete_current") then
		delete_preset(this.current_preset_name)
		this.current_preset_name = ""
		this.create_new_mode = false
		this.rename_mode = false
	end
end

local function handle_unloaded_preset_buttons()
	if imgui.button("Load##load_preset") then
		load_preset(this.current_preset_name)
	end
end

local function handle_empty_preset_buttons()
	if imgui.button("New##create_new") then
		this.create_new_mode = true
		this.new_preset_name = get_dummy_preset_name()
		this.current_preset_name = this.new_preset_name
	end
end

local function handle_fallback_buttons()
	if imgui.button("New##create_new_fallback") then
		this.create_new_mode = true
		this.new_preset_name = get_dummy_preset_name()
		this.current_preset_name = this.new_preset_name
	end
end

local function preset_has_unsaved_changes(preset_name)
	if not preset_name or preset_name == "" or not this.presets[preset_name] then
		return false
	end
	
	local preset = this.presets[preset_name]
	
	for _, player in ipairs({"p1", "p2"}) do
		local current_toggle = this.config[player].toggle
		local preset_toggle = preset[player].toggle
		local current_opacity = this.config[player].opacity
		local preset_opacity = preset[player].opacity
		
		for toggle_name, preset_value in pairs(preset_toggle) do
			if current_toggle[toggle_name] ~= preset_value then
				return true
			end
		end
		
		for toggle_name, _ in pairs(current_toggle) do
			if preset_toggle[toggle_name] == nil then
				return true
			end
		end
		
		for opacity_name, preset_value in pairs(preset_opacity) do
			if current_opacity[opacity_name] ~= preset_value then
				return true
			end
		end
		
		for opacity_name, _ in pairs(current_opacity) do
			if preset_opacity[opacity_name] == nil then
				return true
			end
		end
	end
	
	return false
end

local function handle_normal_mode_buttons()
	if this.current_preset_name ~= "" and this.presets[this.current_preset_name] ~= nil then
		local has_unsaved = preset_has_unsaved_changes(this.current_preset_name)
		
		if has_unsaved then
			if imgui.button("Save##save_preset_unsaved") then
				save_current_preset(this.current_preset_name)
			end
		
			imgui.same_line()
			
			if imgui.button("Discard##load_preset") then
				load_preset(this.current_preset_name)
			end
		else
			imgui.text("")
		end
		
		imgui.same_line()
		
		if imgui.button("Rename##rename_current") then
			this.rename_mode = true
			this.rename_temp_name = this.current_preset_name
		end
		
		imgui.same_line()
		
		if imgui.button("New##create_new") then
			this.create_new_mode = true
			this.new_preset_name = get_dummy_preset_name()
			this.current_preset_name = this.new_preset_name
		end
		
	elseif this.current_preset_name == "" then
		if imgui.button("New##create_new") then
			this.create_new_mode = true
			this.new_preset_name = get_dummy_preset_name()
			this.current_preset_name = this.new_preset_name
		end
	else
		if imgui.button("Save New##save_new_from_text") then
			save_current_preset(this.current_preset_name)
			this.create_new_mode = false
		end
		
		imgui.same_line()
		
		if imgui.button("New##create_new_fallback") then
			this.create_new_mode = true
			this.new_preset_name = get_dummy_preset_name()
			this.current_preset_name = this.new_preset_name
		end
	end
end

local function preset_mode_handler()
	if this.rename_mode then
		handle_rename_mode_buttons()
	elseif this.create_new_mode then
		handle_create_new_mode_buttons()
	else
		handle_normal_mode_buttons()
	end
end

local function reset_all_default(player)
	local default = create_default_config()
	if player == nil then
		this.config.p1 = deep_copy(default.p1)
		this.config.p2 = deep_copy(default.p2)
	elseif player == "p1" or player == "p2" then
		this.config[player] = deep_copy(default[player])
	end
	mark_for_save()
	return this.config
end

local function reset_toggle_default(player)
	local default = create_default_config()
	if player == nil then
		this.config.p1.toggle = deep_copy(default.p1.toggle)
		this.config.p2.toggle = deep_copy(default.p2.toggle)
	elseif player == "p1" or player == "p2" then
		this.config[player].toggle = deep_copy(default[player].toggle)
	end
	mark_for_save()
	return this.config
end

local function reset_opacity_default(player)
	local default = create_default_config()
	if player == nil then
		this.config.p1.opacity = deep_copy(default.p1.opacity)
		this.config.p2.opacity = deep_copy(default.p2.opacity)
	elseif player == "p1" or player == "p2" then
		this.config[player].opacity = deep_copy(default[player].opacity)
	end
	mark_for_save()
	return this.config
end

local function apply_opacity(alphaInt, colorWithoutAlpha)
	alphaInt = math.max(0, math.min(100, alphaInt))
	this.alpha = math.floor((alphaInt / 100) * 255)
	return this.alpha * 0x1000000 + colorWithoutAlpha
end

local function get_pause_type_bit()
	if not pause_manager then
		pause_manager = sdk.get_managed_singleton("app.PauseManager")
	end
	
	this.pause_type_bit = pause_manager:get_field("_CurrentPauseTypeBit")
end

local function is_pause_menu_closed()
	get_pause_type_bit()
	if this.pause_type_bit == 64 or this.pause_type_bit == 2112 then
		return true
	end
end

local function get_prev_push_bit()
	sPlayer = gBattle:get_field("Player"):get_data(nil)
	return sPlayer.prev_no_push_bit
end

local function reverse_pairs(aTable)
	local keys = {}
	for k,v in pairs(aTable) do keys[#keys+1] = k end
	table.sort(keys, function (a, b) return a>b end)
	local n = 0
	return function ( )
		n = n + 1
		if n > #keys then return nil, nil end
		return keys[n], aTable[keys[n] ]
	end
end

local function draw_hitboxes(work, actParam, player_config)
    local col = actParam.Collision

    for j, rect in reverse_pairs(col.Infos._items) do
        if rect ~= nil then
            this.posX = rect.OffsetX.v / 6553600.0
            this.posY = rect.OffsetY.v / 6553600.0
            this.sclX = rect.SizeX.v / 6553600.0 * 2
            this.sclY = rect.SizeY.v / 6553600.0 * 2

            this.posX = this.posX - this.sclX / 2
            this.posY = this.posY - this.sclY / 2

            this.vTL.x = this.posX - this.sclX / 2
            this.vTL.y = this.posY + this.sclY / 2
            this.vTL.z = 0
            
            this.vTR.x = this.posX + this.sclX / 2
            this.vTR.y = this.posY + this.sclY / 2
            this.vTR.z = 0
            
            this.vBL.x = this.posX - this.sclX / 2
            this.vBL.y = this.posY - this.sclY / 2
            this.vBL.z = 0
            
            this.vBR.x = this.posX + this.sclX / 2
            this.vBR.y = this.posY - this.sclY / 2
            this.vBR.z = 0

            this.screenTL = draw.world_to_screen(this.vTL)
            this.screenTR = draw.world_to_screen(this.vTR)
            this.screenBL = draw.world_to_screen(this.vBL)
            this.screenBR = draw.world_to_screen(this.vBR)

            if this.screenTL and this.screenTR and this.screenBL and this.screenBR then
                local finalPosX = (this.screenTL.x + this.screenTR.x) / 2
                local finalPosY = (this.screenBL.y + this.screenTL.y) / 2
                local finalSclX = (this.screenTR.x - this.screenTL.x)
                local finalSclY = (this.screenTL.y - this.screenBL.y)

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
                            -- Use table for string building instead of concatenation
                            local buffer_idx = 0
                            local has_exceptions = false
                            local has_combo = false

                            -- Build exceptions string
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
                                
                                -- Remove trailing comma and space
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
                            local buffer_idx = 0
                            local has_exceptions = false
                            local has_combo = false

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

                    elseif rect.GuardBit == 0 then
                        if player_config.toggle.clashboxes_outline then
                            draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                                apply_opacity(player_config.opacity.clashbox_outline, 0x3891E6))
                        end
                        if player_config.toggle.clashboxes then
                            draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                                apply_opacity(player_config.opacity.clashbox, 0x3891E6))
                        end

                    else
                        if player_config.toggle.proximityboxes_outline then
                            draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                                apply_opacity(player_config.opacity.proximitybox_outline, 0x5b5b5b))
                        end
                        if player_config.toggle.proximityboxes then
                            draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                                apply_opacity(player_config.opacity.proximitybox, 0x5b5b5b))
                        end
                    end

                elseif rect:get_field("Attr") ~= nil then
                    if player_config.toggle.pushboxes_outline then
                        draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                            apply_opacity(player_config.opacity.pushbox_outline, 0x00FFFF))
                    end
                    if player_config.toggle.pushboxes then
                        draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                            apply_opacity(player_config.opacity.pushbox, 0x00FFFF))
                    end

                elseif rect:get_field("HitNo") ~= nil then
                    if player_config.toggle.hurtboxes or player_config.toggle.hurtboxes_outline then
                        if rect.Type == 2 or rect.Type == 1 then
                            if player_config.toggle.hurtboxes_outline then
                                draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                                    apply_opacity(player_config.opacity.hurtbox_outline, 0xFF0080))
                            end
                            if player_config.toggle.hurtboxes then
                                draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                                    apply_opacity(player_config.opacity.hurtbox, 0xFF0080))
                            end
                        else
                            if player_config.toggle.hurtboxes_outline then
                                draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                                    apply_opacity(player_config.opacity.hurtbox_outline, 0x00FF00))
                            end
                            if player_config.toggle.hurtboxes then
                                draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                                    apply_opacity(player_config.opacity.hurtbox, 0x00FF00))
                            end
                        end

                        if player_config.toggle.properties then
                            local buffer_idx = 0

                            if rect.TypeFlag == 1 then
                                buffer_idx = buffer_idx + 1
                                this.string_buffer[buffer_idx] = "Projectile Invulnerable\n"
                            elseif rect.TypeFlag == 2 then
                                buffer_idx = buffer_idx + 1
                                this.string_buffer[buffer_idx] = "Strike Invulnerable\n"
                            end

                            local has_immune = false
                            if bitand(rect.Immune, 1) == 1 or bitand(rect.Immune, 2) == 2 or 
                               bitand(rect.Immune, 4) == 4 or bitand(rect.Immune, 64) == 64 or 
                               bitand(rect.Immune, 128) == 128 then
                                has_immune = true
                                
                                if bitand(rect.Immune, 1) == 1 then 
                                    buffer_idx = buffer_idx + 1
                                    this.string_buffer[buffer_idx] = "Stand, " 
                                end
                                if bitand(rect.Immune, 2) == 2 then 
                                    buffer_idx = buffer_idx + 1
                                    this.string_buffer[buffer_idx] = "Crouch, " 
                                end
                                if bitand(rect.Immune, 4) == 4 then 
                                    buffer_idx = buffer_idx + 1
                                    this.string_buffer[buffer_idx] = "Air, " 
                                end
                                if bitand(rect.Immune, 64) == 64 then 
                                    buffer_idx = buffer_idx + 1
                                    this.string_buffer[buffer_idx] = "Behind, " 
                                end
                                if bitand(rect.Immune, 128) == 128 then 
                                    buffer_idx = buffer_idx + 1
                                    this.string_buffer[buffer_idx] = "Reverse, " 
                                end
                                
                                this.string_buffer[buffer_idx] = string.sub(this.string_buffer[buffer_idx], 1, -3)
                                buffer_idx = buffer_idx + 1
                                this.string_buffer[buffer_idx] = " Attack Intangible\n"
                            end

                            if buffer_idx > 0 then
                                local fullString = table.concat(this.string_buffer, "", 1, buffer_idx)
                                draw.text(fullString, finalPosX, (finalPosY + finalSclY),
                                    apply_opacity(player_config.opacity.properties, 0xFFFFFF))
                            end
                        end
                    end

                elseif rect:get_field("KeyData") ~= nil then
                    if player_config.toggle.uniqueboxes_outline then
                        draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                            apply_opacity(player_config.opacity.uniquebox_outline, 0xEEFF00))
                    end
                    if player_config.toggle.uniqueboxes then
                        draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                            apply_opacity(player_config.opacity.uniquebox, 0xEEFF00))
                    end

                else
                    if player_config.toggle.throwhurtboxes_outline then
                        draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                            apply_opacity(player_config.opacity.throwhurtbox_outline, 0xFF0000))
                    end
                    if player_config.toggle.throwhurtboxes then
                        draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY,
                            apply_opacity(player_config.opacity.throwhurtbox, 0xFF0000))
                    end
                end
            end
        end
    end
end

local function toggle_setter(label, val)
	local changed, new_val = imgui.checkbox(label, val)
	if changed then
		mark_for_save()
	end
	return changed, new_val
end

local function opacity_setter(label, val, speed, min, max)
	val = math.max(0, math.min(100, val))
	local changed, new_val = imgui.drag_int(label, val, speed or 1.0, min or 0, max or 100)
	if changed then
		mark_for_save()
	end
	return changed, new_val
end

local function init_config()
	load_config()
	if this.current_preset_name == "" then
		this.current_preset_name = get_dummy_preset_name()
	end
	this.initialized = true
end

local function save_handler()
	if this.save_pending then
		this.save_timer = this.save_timer - (1.0 / 60.0)
		if this.save_timer <= 0 then
			save_config()
		end
	end
end

local function build_hotkeys()
	if not this.key_ready and not reframework:is_key_down(KEY_1) and not reframework:is_key_down(KEY_2) and not reframework:is_key_down(KEY_F1) then
		this.key_ready = true
	end

	if this.key_ready and reframework:is_key_down(KEY_F1) then
		this.config.options.display_menu = not this.config.options.display_menu
		this.key_ready = false
		mark_for_save()
	end

	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_1) then
		this.config.p1.toggle.toggle_show = not this.config.p1.toggle.toggle_show
		this.key_ready = false
		mark_for_save()
	end

	if this.key_ready and reframework:is_key_down(KEY_CTRL) and reframework:is_key_down(KEY_2) then
		this.config.p2.toggle.toggle_show = not this.config.p2.toggle.toggle_show
		this.key_ready = false
		mark_for_save()
	end
end

local function build_toggler_with_opacity(label, config_suffix, opacity_suffix)
	imgui.table_next_row()
	
	imgui.table_set_column_index(0)
	imgui.text(label)
	
	imgui.table_set_column_index(1)
	if this.config.p1.toggle.toggle_show then
		local id = "##p1_" .. config_suffix
		this.changed, this.config.p1.toggle[config_suffix] = toggle_setter(id, this.config.p1.toggle[config_suffix])
		
		if opacity_suffix and this.config.p1.opacity[opacity_suffix] ~= nil and this.config.p1.toggle[config_suffix] then
			imgui.same_line()
			imgui.push_item_width(70)
			this.changed, this.config.p1.opacity[opacity_suffix] = opacity_setter("##p1_" .. opacity_suffix .. "Opacity", 
				this.config.p1.opacity[opacity_suffix], 0.5, 0, 100)
			imgui.pop_item_width()
		end
	end
	
	imgui.table_set_column_index(2)
	if this.config.p2.toggle.toggle_show then
		local id = "##p2_" .. config_suffix
		this.changed, this.config.p2.toggle[config_suffix] = toggle_setter(id, this.config.p2.toggle[config_suffix])
		
		if opacity_suffix and this.config.p2.opacity[opacity_suffix] ~= nil and this.config.p2.toggle[config_suffix] then
			imgui.same_line()
			imgui.push_item_width(70)
			this.changed, this.config.p2.opacity[opacity_suffix] = opacity_setter("##p2_" .. opacity_suffix .. "Opacity", 
				this.config.p2.opacity[opacity_suffix], 0.5, 0, 100)
			imgui.pop_item_width()
		end
	end
end

local function build_presets_table()
	imgui.set_next_item_open(true)
	if not imgui.begin_table("PresetTable", 3) then
		return
	end
	
	imgui.table_setup_column("", nil, 150)
	imgui.table_setup_column("", nil, 60)
	imgui.table_setup_column("", nil, 60)
	imgui.table_headers_row()
	
	for _, preset_name in ipairs(this.preset_names) do
		imgui.table_next_row()
		
		imgui.table_set_column_index(0)
		imgui.text(preset_name)
		
		imgui.table_set_column_index(1)
		if imgui.button("Load##load_" .. preset_name) then
			load_preset(preset_name)
			this.create_new_mode = false
			this.rename_mode = false
			this.new_preset_name = ""
			this.rename_temp_name = ""
		end
		
		imgui.table_set_column_index(2)
		if imgui.button("Delete##delete_" .. preset_name) then
			delete_preset(preset_name)
			if this.current_preset_name == preset_name then
				this.current_preset_name = ""
				this.create_new_mode = false
				this.rename_mode = false
			end
			break
		end
	end
	
	imgui.end_table()
end

local function build_presets()
	if not imgui.tree_node("Presets") then
		return
	end

	imgui.text("Current:")
	imgui.same_line()
	imgui.push_item_width(100)
	
	if this.rename_mode then
		handle_rename_mode_input()
	elseif this.create_new_mode then
		handle_create_new_mode_input()
	else
		handle_normal_mode_input()
	end
	
	imgui.pop_item_width()
	imgui.same_line()
	
	preset_mode_handler()
	
	build_presets_table()
	
	imgui.tree_pop()
end

local function build_toggles()
	imgui.set_next_item_open(true)
	if imgui.tree_node("Toggle") then
		if imgui.begin_table("ToggleTable", 3) then
			imgui.table_setup_column("", nil, 150)
			imgui.table_setup_column("P1", nil, 125)
			imgui.table_setup_column("P2", nil, 125)
			
			imgui.table_next_row()
			
			imgui.table_set_column_index(0)
			imgui.text("")
			
			imgui.table_set_column_index(1)
			imgui.text("P1")
			-- imgui.same_line()
			-- local cursor_pos = imgui.get_cursor_pos()
			-- imgui.set_cursor_pos(Vector2f.new(cursor_pos.x + 20, cursor_pos.y))
			-- this.changed, this.config.p1.toggle.toggle_show = toggle_setter("##p1_HideAllHeader", this.config.p1.toggle.toggle_show)
			-- 
			imgui.table_set_column_index(2)
			imgui.text("P2")
			-- imgui.same_line()
			-- cursor_pos = imgui.get_cursor_pos()
			-- imgui.set_cursor_pos(Vector2f.new(cursor_pos.x + 20, cursor_pos.y))
			-- this.changed, this.config.p2.toggle.toggle_show = toggle_setter("##p2_HideAllHeader", this.config.p2.toggle.toggle_show)
			-- 

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
				
				imgui.table_set_column_index(0)
				imgui.text("All")
				
				imgui.table_set_column_index(1)
				if this.config.p1.toggle.toggle_show then
					local all_checked = false
					local any_checked = false
					
					for toggle_name, toggle_value in pairs(this.config.p1.toggle) do
						if toggle_name ~= "toggle_show" then
							if toggle_value then
								any_checked = true
							end
						end
					end
					
					all_checked = any_checked
					
					this.changed, all_checked = toggle_setter("##p1_ToggleAll", all_checked)
					if this.changed then
						for toggle_name, _ in pairs(this.config.p1.toggle) do
							if toggle_name ~= "toggle_show" then
								this.config.p1.toggle[toggle_name] = all_checked
							end
						end
						mark_for_save()
					end
					
					if all_checked then
						imgui.same_line()
						imgui.push_item_width(70)
						
						local current_opacity_slider = 50
						
						local all_same = true
						local first_opacity = nil
						for opacity_name, opacity_value in pairs(this.config.p1.opacity) do
							if first_opacity == nil then
								first_opacity = opacity_value
							elseif opacity_value ~= first_opacity then
								all_same = false
								break
							end
						end
						
						if all_same and first_opacity ~= nil then
							current_opacity_slider = first_opacity
						else
							current_opacity_slider = 50
						end
						
						this.changed, current_opacity_slider = opacity_setter("##p1_GlobalOpacity", current_opacity_slider, 0.5, 0, 100)
						if this.changed then
							for opacity_name, _ in pairs(this.config.p1.opacity) do
								this.config.p1.opacity[opacity_name] = current_opacity_slider
							end
							mark_for_save()
						end
						imgui.pop_item_width()
					end
				end
				
				imgui.table_set_column_index(2)
				if this.config.p2.toggle.toggle_show then
					local all_checked = false
					local any_checked = false
					
					for toggle_name, toggle_value in pairs(this.config.p2.toggle) do
						if toggle_name ~= "toggle_show" then
							if toggle_value then
								any_checked = true
							end
						end
					end
					
					all_checked = any_checked
					
					this.changed, all_checked = toggle_setter("##p2_ToggleAll", all_checked)
					if this.changed then
						for toggle_name, _ in pairs(this.config.p2.toggle) do
							if toggle_name ~= "toggle_show" then
								this.config.p2.toggle[toggle_name] = all_checked
							end
						end
						mark_for_save()
					end
					
					if all_checked then
						imgui.same_line()
						imgui.push_item_width(70)
						
						local current_opacity_slider = 50
						
						local all_same = true
						local first_opacity = nil
						for opacity_name, opacity_value in pairs(this.config.p2.opacity) do
							if first_opacity == nil then
								first_opacity = opacity_value
							elseif opacity_value ~= first_opacity then
								all_same = false
								break
							end
						end
						
						if all_same and first_opacity ~= nil then
							current_opacity_slider = first_opacity
						else
							current_opacity_slider = 50
						end
						
						this.changed, current_opacity_slider = opacity_setter("##p2_GlobalOpacity", current_opacity_slider, 0.5, 0, 100)
						if this.changed then
							for opacity_name, _ in pairs(this.config.p2.opacity) do
								this.config.p2.opacity[opacity_name] = current_opacity_slider
							end
							mark_for_save()
						end
						imgui.pop_item_width()
					end
				end
			end
			imgui.end_table()
		end
		imgui.tree_pop()
	end
end

local function build_options()
	if imgui.tree_node("Options") then
		if imgui.tree_node("Reset") then
			if imgui.begin_table("ResetTable", 4) then
				imgui.table_setup_column("", nil, 100)
				imgui.table_setup_column("", nil, 35)
				imgui.table_setup_column("", nil, 35)
				imgui.table_setup_column("", nil, 35)

				imgui.table_next_row()
				imgui.table_set_column_index(0)
				imgui.text("Toggles")
				imgui.table_set_column_index(1)
				if imgui.button("P1##toggle_p1") then reset_toggle_default('p1') end
				imgui.table_set_column_index(2)
				if imgui.button("P2##toggle_p2") then reset_toggle_default('p2') end
				imgui.table_set_column_index(3)
				if imgui.button("All##toggle_all") then reset_toggle_default() end
				
				imgui.table_next_row()
				imgui.table_set_column_index(0)
				imgui.text("Opacity")
				imgui.table_set_column_index(1)
				if imgui.button("P1##opacity_p1") then reset_opacity_default('p1') end
				imgui.table_set_column_index(2)
				if imgui.button("P2##opacity_p2") then reset_opacity_default('p2') end
				imgui.table_set_column_index(3)
				if imgui.button("All##opacity_all") then reset_opacity_default() end
				
				imgui.table_next_row()
				imgui.table_set_column_index(0)
				imgui.text("All")
				imgui.table_set_column_index(1)
				if imgui.button("P1##all_p1") then reset_all_default('p1') end
				imgui.table_set_column_index(2)
				if imgui.button("P2##all_p2") then reset_all_default('p2') end
				imgui.table_set_column_index(3)
				if imgui.button("All##all_all") then reset_all_default() end
				
				imgui.end_table()
			end
			imgui.tree_pop()
		end
		imgui.tree_pop()
	end
	imgui.end_window()
end

local function build_hitboxes()
	local sWork = gBattle:get_field("Work"):get_data(nil)
	local cWork = sWork.Global_work
	
	for i, obj in pairs(cWork) do
		local actParam = obj.mpActParam
		if actParam and not obj:get_IsR0Die() then
			if obj:get_IsTeam1P() and this.config.p1.toggle.toggle_show then
				draw_hitboxes(obj, actParam, this.config.p1)
				if this.config.p1.toggle.position then
					this.vPos.x = obj.pos.x.v / 6553600.0
					this.vPos.y = obj.pos.y.v / 6553600.0
					this.vPos.z = 0
					local objPos = draw.world_to_screen(this.vPos)
					if objPos then
						draw.filled_circle(objPos.x, objPos.y, 10, apply_opacity(this.config.p1.opacity.position, 0xFFFFFF), 10)
					end
				end
			end
			if obj:get_IsTeam2P() and this.config.p2.toggle.toggle_show then
				draw_hitboxes(obj, actParam, this.config.p2)
				if this.config.p2.toggle.position then
					this.vPos.x = obj.pos.x.v / 6553600.0
					this.vPos.y = obj.pos.y.v / 6553600.0
					this.vPos.z = 0
					local objPos = draw.world_to_screen(this.vPos)
					if objPos then
						draw.filled_circle(objPos.x, objPos.y, 10, apply_opacity(this.config.p2.opacity.position, 0xFFFFFF), 10)
					end
				end
			end
		end
	end
	
	local sPlayer = gBattle:get_field("Player"):get_data(nil)
	local cPlayer = sPlayer.mcPlayer
	for i, player in pairs(cPlayer) do
		local actParam = player.mpActParam
		if actParam then
			if i == 0 and this.config.p1.toggle.toggle_show then
				draw_hitboxes(player, actParam, this.config.p1)
				if this.config.p1.toggle.position then
					this.vPos.x = player.pos.x.v / 6553600.0
					this.vPos.y = player.pos.y.v / 6553600.0
					this.vPos.z = 0
					local worldPos = draw.world_to_screen(this.vPos)
					if worldPos then
						draw.filled_circle(worldPos.x, worldPos.y, 10, apply_opacity(this.config.p1.opacity.position, 0xFFFFFF), 10)
					end
				end
			end
			if i == 1 and this.config.p2.toggle.toggle_show then
				draw_hitboxes(player, actParam, this.config.p2)
				if this.config.p2.toggle.position then
					this.vPos.x = player.pos.x.v / 6553600.0
					this.vPos.y = player.pos.y.v / 6553600.0
					this.vPos.z = 0
					local worldPos = draw.world_to_screen(this.vPos)
					if worldPos then
						draw.filled_circle(worldPos.x, worldPos.y, 10, apply_opacity(this.config.p2.opacity.position, 0xFFFFFF), 10)
					end
				end
			end
		end
	end
end

local function build_gui()
	if this.config.options.display_menu and get_prev_push_bit() ~= 0 then
		imgui.set_next_item_open(true, 2)
		imgui.begin_window("Hitboxes", true, 64)
		build_toggles()
		build_presets()
		build_options()
	end

	if is_pause_menu_closed() then
		build_hitboxes()
	end
end

if not this.initialized then
	init_config()
end

re.on_draw_ui(function()
	if imgui.tree_node("Hitbox Viewer") then
		this.changed, this.config.options.display_menu = toggle_setter("Display Options Menu", this.config.options.display_menu)
		imgui.tree_pop()
	end
end)

re.on_frame(function()
	if not gBattle then
		gBattle = sdk.find_type_definition("gBattle")
	else
		save_handler()
		build_hotkeys()
		build_gui()
	end
end)