local F3_KEY = 0X72

local changed
local p1_hit_dt
local p2_hit_dt
local prev_key_states = {}
local hide_ui = false
local p1 = {}
p1.absolute_range = 0
p1.relative_range = 0
local p2 = {}
p2.absolute_range = 0
p2.relative_range = 0

local left_wall_dr_splat_pos = -585.2
local right_wall_dr_splat_pos = 585.2

local gBattle = sdk.find_type_definition("gBattle")
local sPlayer = gBattle:get_field("Player"):get_data(nil)
local cPlayer = sPlayer.mcPlayer
local BattleTeam = gBattle:get_field("Team"):get_data(nil)
local cTeam = BattleTeam.mcTeam
local training_manager = sdk.get_managed_singleton("app.training.TrainingManager")
local display_player_info = true
local display_projectile_info = false

-- Charge Info
local storageData = gBattle:get_field("Command"):get_data(nil).StorageData
local p1ChargeInfo = storageData.UserEngines[0].m_charge_infos
local p2ChargeInfo = storageData.UserEngines[1].m_charge_infos
-- Fireball
local sWork = gBattle:get_field("Work"):get_data(nil)
local cWork = sWork.Global_work

local function was_key_down(i)
    local down = reframework:is_key_down(i)
    local prev = prev_key_states[i]
    prev_key_states[i] = down
    return down and not prev
end

local function bitand(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
      if a % 2 == 1 and b % 2 == 1 then -- test the rightmost bits
          result = result + bitval      -- set the current bit
      end
      bitval = bitval * 2 -- shift left
      a = math.floor(a/2) -- shift right
      b = math.floor(b/2)
    end
    return result
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

local function abs(num)
	if num < 0 then
		return num * -1
	else
		return num
	end
end

local function read_sfix(sfix_obj)
    if sfix_obj.w then
        return Vector4f.new(tonumber(sfix_obj.x:call("ToString()")), tonumber(sfix_obj.y:call("ToString()")), tonumber(sfix_obj.z:call("ToString()")), tonumber(sfix_obj.w:call("ToString()")))
    elseif sfix_obj.z then
        return Vector3f.new(tonumber(sfix_obj.x:call("ToString()")), tonumber(sfix_obj.y:call("ToString()")), tonumber(sfix_obj.z:call("ToString()")))
    elseif sfix_obj.y then
        return Vector2f.new(tonumber(sfix_obj.x:call("ToString()")), tonumber(sfix_obj.y:call("ToString()")))
    end
    return tonumber(sfix_obj:call("ToString()"))
end

function imgui.multi_color(first_text, second_text, second_text_color)
    imgui.text_colored(first_text, 0xFFAAFFFF) 
    imgui.same_line()
	if second_text_color then
	    imgui.text_colored(second_text, second_text_color)
	else
		imgui.text(second_text)
	end
end

local function get_drive_color(drive)
	if drive >= -60000 and drive < -50001 then
		return 0xFFFF0073
	elseif drive >= -50000 and drive < -40001 then
		return 0XFFF7318B
	elseif drive >= -40000 and drive < -30001 then
		return 0XFFF74A99
	elseif drive >= -30000 and drive < -20001 then
		return 0XFFFC68AB
	elseif drive >= -20000 and drive < -10001 then
		return 0XFFF786B9
	elseif drive >= - 10000 and drive < -1 then
		return 0XFFFCAED2
	elseif drive >= 0 and drive < 9999 then
		return 0xFFF55727
	elseif drive >= 10000 and drive < 19999 then
		return 0xFFF5A927
	elseif drive >= 20000 and drive < 29999 then
		return 0xFFF5DD27
	elseif drive >= 30000 and drive < 39999 then
		return 0xFFDDF527
	elseif drive >= 40000 and drive < 49999 then
		return 0xFFBBF527
	elseif drive >= 50000 then
		return 0xFF5EF527
	else
		return 0xFFAAFFFF
	end
end

local function get_super_color(super)
	if super >= 0 and super < 4999 then
		return 0xFFF55727
	elseif super >= 5000 and super < 9999 then
		return 0xFFF5A927
	elseif super >= 10000 and super < 14999 then
		return 0xFFF5DD27
	elseif super >= 15000 and super < 19999 then
		return 0xFFDDF527
	elseif super >= 20000 and super < 24999 then
		return 0xFFBBF527
	elseif super >= 25000 then
		return 0xFF5EF527
	else
		return 0xFFAAFFFF
	end
end

local function get_hitbox_range(player, actParam, list)
	local facingRight = bitand(player.BitValue, 128) == 128
	local maxHitboxEdgeX = nil
	if actParam ~= nil then
		local col = actParam.Collision
		   for j, rect in reverse_pairs(col.Infos._items) do
			if rect ~= nil then
				local posX = rect.OffsetX.v / 65536.0
				local posY = rect.OffsetY.v / 65536.0
				local sclX = rect.SizeX.v / 65536.0 * 2
				local sclY = rect.SizeY.v / 65536.0 * 2
				if rect:get_field("HitPos") ~= nil then
					local hitbox_X
					if rect.TypeFlag > 0 or (rect.TypeFlag == 0 and rect.PoseBit > 0) then
                        if facingRight then
                            hitbox_X = posX + sclX / 2
                        else
                            hitbox_X = posX - sclX / 2
                        end
						if maxHitboxEdgeX == nil then
							maxHitboxEdgeX = hitbox_X
						end
						if maxHitboxEdgeX ~= nil then
							if facingRight and hitbox_X > maxHitboxEdgeX then
								maxHitboxEdgeX = hitbox_X
							elseif hitbox_X < maxHitboxEdgeX then
								maxHitboxEdgeX = hitbox_X
							end
						end
					end
				end
			end
		end
		if maxHitboxEdgeX ~= nil then
			local playerPosX = player.pos.x.v / 65536.0
			-- Replace start_pos because it can fail to track the actual starting location of an action (e.g., DJ 2MK)
			-- local playerStartPosX = player.start_pos.x.v / 65536.0
			local playerStartPosX = player.act_root.x.v / 65536.0
            list.absolute_range = abs(maxHitboxEdgeX - playerStartPosX)
            list.relative_range = abs(maxHitboxEdgeX - playerPosX)
		end
	end
end

local function handle_player_data()
	-- Action Engine
	local p1Engine = cPlayer[0].mpActParam.ActionPart._Engine
	local p2Engine = cPlayer[1].mpActParam.ActionPart._Engine
	-- P1 ActID, Current Frame, Final Frame, IASA Frame
	p1.mActionId = p1Engine:get_ActionID()
	p1.mActionFrame = p1Engine:get_ActionFrame()
	p1.mEndFrame = p1Engine:get_ActionFrameNum()
	p1.mMarginFrame = p1Engine:get_MarginFrame()
	-- P2 ActID, Current Frame, Final Frame, IASA Frame
	p2.mActionId = p2Engine:get_ActionID()
	p2.mActionFrame = p2Engine:get_ActionFrame()
	p2.mEndFrame = p2Engine:get_ActionFrameNum()
	p2.mMarginFrame = p2Engine:get_MarginFrame()
	-- P1 Startup/Active/Recovery Frame
	p1.mMainFrame = p1Engine.mParam.action.ActionFrame.MainFrame
	p1.mFollowFrame = p1Engine.mParam.action.ActionFrame.FollowFrame
	-- P2 Startup/Active/Recovery Frame
	p2.mMainFrame = p2Engine.mParam.action.ActionFrame.MainFrame
	p2.mFollowFrame = p2Engine.mParam.action.ActionFrame.FollowFrame
	-- KD Info from Frame Meter
	local display_data = training_manager._tCommon.SnapShotDatas[0]._DisplayData
	p1.whole_frame = display_data.FrameMeterSSData.MeterDatas[0].WholeFrame
	p1.meaty_frame = display_data.FrameMeterSSData.MeterDatas[0].MeatyFrame
	p1.apper_frame = display_data.FrameMeterSSData.MeterDatas[0].ApperFrame
	p1.apper_frame_str = string.gsub(p1.apper_frame, "F", "")
	p1.apper_frame_int = tonumber(p1.apper_frame_str) or 0
	p1.stun_frame = display_data.FrameMeterSSData.MeterDatas[0].StunFrame
	p1.stun_frame_str = string.gsub(p1.stun_frame, "F", "")
	p1.stun_frame_int = tonumber(p1.stun_frame_str) or 0
	p2.whole_frame = display_data.FrameMeterSSData.MeterDatas[1].WholeFrame
	p2.meaty_frame = display_data.FrameMeterSSData.MeterDatas[1].MeatyFrame
	p2.apper_frame = display_data.FrameMeterSSData.MeterDatas[1].ApperFrame
	p2.apper_frame_str = string.gsub(p2.apper_frame, "F", "")
	p2.apper_frame_int = tonumber(p2.apper_frame_str) or 0
	p2.stun_frame = display_data.FrameMeterSSData.MeterDatas[1].StunFrame
	p2.stun_frame_str = string.gsub(p2.stun_frame, "F", "")
	p2.stun_frame_int = tonumber(p2.stun_frame_str) or 0
	
	p1_hit_dt = cPlayer[1].pDmgHitDT
	p2_hit_dt = cPlayer[0].pDmgHitDT
	
	-- P1 Data
	p1.HP_cap = cPlayer[0].heal_new
	p1.current_HP = cPlayer[0].vital_new
	p1.HP_cooldown = cPlayer[0].healing_wait
	p1.dir = bitand(cPlayer[0].BitValue, 128) == 128
	p1.curr_hitstop = cPlayer[0].hit_stop
	p1.max_hitstop = cPlayer[0].hit_stop_org
	p1.curr_hitstun = cPlayer[0].damage_time
	p1.max_hitstun = cPlayer[0].damage_info.time
	p1.curr_blockstun = cPlayer[0].guard_time
	p1.stance = cPlayer[0].pose_st
	p1.throw_invuln = cPlayer[0].catch_muteki
	p1.full_invuln = cPlayer[0].muteki_time
	p1.juggle = cPlayer[0].combo_dm_air
	p1.burnout =cPlayer[0].incapacitated or false
	p1.startup_frames = p1.apper_frame_int
	p1.active_frames = p1.mFollowFrame - p1.mMainFrame -- TODO Make reliable
	p1.recovery_frames = read_sfix(p1.mMarginFrame) - p1.mFollowFrame -- TODO Make reliable
	p1.total_frames = read_sfix(p1.mMarginFrame) -- TODO Make reliable
	p1.advantage = p1.stun_frame_int
	p1.drive = cPlayer[0].focus_new
	p1.drive_cooldown = cPlayer[0].focus_wait
	p1.super = cTeam[0].mSuperGauge
	p1.buff = cPlayer[0].style_timer
	p1.debuff_timer = cPlayer[0].damage_cond.timer
	p1.chargeInfo = p1ChargeInfo
	p1.posX = cPlayer[0].pos.x.v / 65536.0
	p1.posY = cPlayer[0].pos.y.v / 65536.0
	p1.spdX = cPlayer[0].speed.x.v / 65536.0
	p1.spdY = cPlayer[0].speed.y.v / 65536.0
	p1.aclX = cPlayer[0].alpha.x.v / 65536.0
	p1.aclY = cPlayer[0].alpha.y.v / 65536.0
	p1.pushback = cPlayer[0].vector_zuri.speed.v / 65536.0
	p1.self_pushback = cPlayer[0].vs_vec_zuri.zuri.speed.v / 65536.0
	p1.gap = cPlayer[0].vs_distance.v / 65536.0
	p1.combo_attack_count = cPlayer[1].combo_scale.count
	p1.combo_hit_count = cPlayer[1].combo_dm_cnt
	p1.combo_scale_now = cPlayer[1].combo_scale.now
	p1.combo_scale_start = cPlayer[1].combo_scale.start
	p1.combo_scale_buff = cPlayer[1].combo_scale.buff
	
	-- P2 Data
	p2.HP_cap = cPlayer[1].heal_new
	p2.current_HP = cPlayer[1].vital_new
	p2.HP_cooldown = cPlayer[1].healing_wait
	p2.dir = bitand(cPlayer[1].BitValue, 128) == 128
	p2.curr_hitstop = cPlayer[1].hit_stop
	p2.max_hitstop = cPlayer[1].hit_stop_org
	p2.curr_hitstun = cPlayer[1].damage_time
	p2.max_hitstun = cPlayer[1].damage_info.time
	p2.curr_blockstun = cPlayer[1].guard_time
	p2.stance = cPlayer[1].pose_st
	p2.throw_invuln = cPlayer[1].catch_muteki
	p2.full_invuln = cPlayer[1].muteki_time
	p2.juggle = cPlayer[1].combo_dm_air
	p2.burnout =cPlayer[1].incapacitated or false
	p1.startup_frames = p1.apper_frame_int
	p2.active_frames = p2.mFollowFrame - p2.mMainFrame -- TODO Make reliable
	p2.recovery_frames = read_sfix(p2.mMarginFrame) - p2.mFollowFrame -- TODO Make reliable
	p2.total_frames = read_sfix(p2.mMarginFrame) -- TODO Make reliable
	p1.advantage = p1.stun_frame_int
	p2.drive = cPlayer[1].focus_new
	p2.drive_cooldown = cPlayer[1].focus_wait
	p2.super = cTeam[1].mSuperGauge
	p2.buff = cPlayer[1].style_timer
	p2.debuff_timer = cPlayer[1].damage_cond.timer
	p2.chargeInfo = p2ChargeInfo
	p2.posX = cPlayer[1].pos.x.v / 65536.0
	p2.posY = cPlayer[1].pos.y.v / 65536.0
	p2.spdX = cPlayer[1].speed.x.v / 65536.0
	p2.spdY = cPlayer[1].speed.y.v / 65536.0
	p2.aclX = cPlayer[1].alpha.x.v / 65536.0
	p2.aclY = cPlayer[1].alpha.y.v / 65536.0
	p2.pushback = cPlayer[1].vector_zuri.speed.v / 65536.0
	p2.self_pushback = cPlayer[1].vs_vec_zuri.zuri.speed.v / 65536.0
	p2.gap = cPlayer[1].vs_distance.v / 65536.0
	p2.combo_attack_count = cPlayer[0].combo_scale.count
	p2.combo_hit_count = cPlayer[0].combo_dm_cnt
	p2.combo_scale_now = cPlayer[0].combo_scale.now
	p2.combo_scale_start = cPlayer[0].combo_scale.start
	p2.combo_scale_buff = cPlayer[0].combo_scale.buff

	-- Adjusted Drive to account for Burnout
	if p1.burnout then
		p1.drive_adjusted = p1.drive - 60000
	else
	end
		p1.drive_adjusted = p1.drive

	if p2.burnout then
		p2.drive_adjusted = p2.drive - 60000
	else
		p2.drive_adjusted = p2.drive
	end
	
	-- Max blockstun tracker
	if p1.max_blockstun == nil then
		p1.max_blockstun = 0
	end
	if p1.curr_blockstun > p1.max_blockstun then
		p1.max_blockstun = p1.curr_blockstun
	elseif p1.curr_blockstun == 0 then
		p1.max_blockstun = 0
	end

	if p2.max_blockstun == nil then
		p2.max_blockstun = 0
	end
	if p2.curr_blockstun > p2.max_blockstun then
		p2.max_blockstun = p2.curr_blockstun
	elseif p2.curr_blockstun == 0 then
		p2.max_blockstun = 0
	end
end

re.on_draw_ui(function()
    if imgui.tree_node("Info Display") then
        changed, display_player_info = imgui.checkbox("Display Battle Info", display_player_info)
		changed, display_projectile_info = imgui.checkbox("Display Projectile Info", display_projectile_info)
        imgui.tree_pop()
    end
end)

re.on_frame(function()
    if sPlayer.prev_no_push_bit ~= 0 then
		handle_player_data()

		if was_key_down(F3_KEY) then
			hide_ui = not hide_ui
		end
		
		if display_player_info and not hide_ui then
			imgui.begin_window("Player Data", true, 1|8)
			-- Vitals info
			imgui.set_next_item_open(true, 2)
			if imgui.tree_node("Vitals") then
				imgui.multi_color("Gap:", p1.gap)
				imgui.multi_color("Advantage:", p1.advantage)
				if (p1.dir and p1.posX <= left_wall_dr_splat_pos) or (not p1.dir and p1.posX >= right_wall_dr_splat_pos) then
					imgui.multi_color("P1 Pos:", string.format("%.1f", p1.posX) or "", 0XFFFFEA00)
				else
					imgui.multi_color("P1 Pos:", string.format("%.1f", p1.posX) or "")
				end
				imgui.multi_color("P1 Drive:", p1.drive_adjusted, get_drive_color(p1.drive_adjusted))
				imgui.multi_color("P1 Super:", p1.super, get_super_color(p2.super))
				if (p2.dir and p2.posX <= left_wall_dr_splat_pos) or (not p2.dir and p2.posX >= right_wall_dr_splat_pos) then
					imgui.multi_color("P2 Pos:", string.format("%.1f", p2.posX) or "", 0XFFFFEA00)
				else
					imgui.multi_color("P2 Pos:", string.format("%.1f", p2.posX) or "")
				end
				imgui.multi_color("P2 Drive:", p2.drive_adjusted, get_drive_color(p2.drive_adjusted))
				imgui.multi_color("P2 Super:", p2.super, get_super_color(p2.super))
				imgui.tree_pop()
			end
			-- Player 1 Info
			if imgui.tree_node("P1") then
				if imgui.tree_node("General Info") then
					imgui.multi_color("Current HP:", p1.current_HP)
					imgui.multi_color("HP Cap:", p1.HP_cap)
					imgui.multi_color("HP Regen Cooldown:", p1.HP_cooldown)
					imgui.multi_color("Burnout:", tostring(p1.burnout))
					imgui.multi_color("Drive Gauge:", p1.drive_adjusted)
					imgui.multi_color("Drive Cooldown:", p1.drive_cooldown)
					imgui.multi_color("Super Gauge:", p1.super)
					imgui.multi_color("Buff Duration:", p1.buff)
					imgui.multi_color("Debuff Duration:", p1.debuff_timer)

					imgui.tree_pop()
				end
				if imgui.tree_node("State Info") then
					imgui.multi_color("Action ID:", p1.mActionId)
					imgui.multi_color("Action Frame:", math.floor(read_sfix(p1.mActionFrame)) .. " / " .. math.floor(read_sfix(p1.mMarginFrame)) .. " (" .. math.floor(read_sfix(p1.mEndFrame)) .. ")")
					imgui.multi_color("Current Hitstop:", p1.curr_hitstop .. " / " .. p1.max_hitstop)
					imgui.multi_color("Current Hitstun:", p1.curr_hitstun .. " / " .. p1.max_hitstun)
					imgui.multi_color("Current Blockstun:", p1.curr_blockstun .. " / " .. p1.max_blockstun)
					imgui.multi_color("Throw Protection Timer:", p1.throw_invuln)
					imgui.multi_color("Intangible Timer:", p1.full_invuln)

					imgui.tree_pop()
				end
				if imgui.tree_node("Movement Info") then
					if p1.dir == true then
						imgui.multi_color("Facing:", "Right")
					else
						imgui.multi_color("Facing:", "Left")
					end
					if p1.stance == 0 then
						imgui.multi_color("Stance:", "Standing")
					elseif p1.stance == 1 then
						imgui.multi_color("Stance:", "Crouching")
					else
						imgui.multi_color("Stance:", "Jumping")
					end
					imgui.multi_color("Position X:", string.format("%.2f", p1.posX))
					imgui.multi_color("Position Y:", string.format("%.2f", p1.posY))
					imgui.multi_color("Speed X:", string.format("%.2f", p1.spdX))
					imgui.multi_color("Speed Y:", string.format("%.2f", p1.spdY))
					imgui.multi_color("Acceleration X:", string.format("%.2f", p1.aclX))
					imgui.multi_color("Acceleration Y:", string.format("%.2f", p1.aclY))
					imgui.multi_color("Pushback:", string.format("%.2f", p1.pushback))
					imgui.multi_color("Self Pushback:", string.format("%.2f", p1.self_pushback))
					imgui.multi_color("Distance Between Players:", p1.gap)
					
					imgui.tree_pop()
				end
				if imgui.tree_node("Attack Info") then
					get_hitbox_range(cPlayer[0], cPlayer[0].mpActParam, p1)
					imgui.multi_color("Startup Frames:", p1.startup_frames)
					imgui.multi_color("Active Frames:", p1.active_frames)
					imgui.multi_color("Recovery Frames:", string.format("%.0f", p1.recovery_frames))
					imgui.multi_color("Total Frames:", string.format("%.0f", p1.total_frames))
					imgui.multi_color("Advantage:", p1.advantage)
					imgui.multi_color("Absolute Range:", string.format("%.2f", p1.absolute_range))
					imgui.multi_color("Relative Range:", string.format("%.2f", p1.relative_range))
					imgui.multi_color("Juggle Counter:", p2.juggle)
					imgui.multi_color("Combo Hit Count:", p1.combo_hit_count)
					imgui.multi_color("Combo Attack Count:", p1.combo_attack_count)
					imgui.multi_color("Combo Starter Scaling:", 100 - p1.combo_scale_start .. "%")
					imgui.multi_color("Current Hit Scaling:", p1.combo_scale_now .. "%")

					local p1_next_hit_scaling_calc = 100
					if p1.combo_attack_count == 1 then
						if p1.combo_scale_buff == 10 then
							p1_next_hit_scaling_calc = (100 - p1.combo_scale_start)
						else
							p1_next_hit_scaling_calc = (100 - p1.combo_scale_start) - p1.combo_scale_buff
						end
					elseif p1.combo_attack_count > 1 then
						p1_next_hit_scaling_calc = (100 - p1.combo_scale_start) - p1.combo_scale_buff
					else
						p1_next_hit_scaling_calc = 100 - p1.combo_scale_buff
					end
					imgui.multi_color("Next Hit Scaling:", p1_next_hit_scaling_calc .. "%")

					if imgui.tree_node("Latest Attack Info") then
						if p1_hit_dt == nil then
							imgui.text_colored("No hit yet", 0xFFAAFFFF)
						else
							imgui.multi_color("Damage:", p1_hit_dt.DmgValue)
							imgui.multi_color("Self Drive Gain:", p1_hit_dt.FocusOwn)
							imgui.multi_color("Opponent Drive Gain:", p1_hit_dt.FocusTgt)
							imgui.multi_color("Self Super Gain:", p1_hit_dt.SuperOwn)
							imgui.multi_color("Opponent Super Gain:", p1_hit_dt.SuperTgt)
							imgui.multi_color("Self Hitstop:", p1_hit_dt.HitStopOwner)
							imgui.multi_color("Opponent Hitstop:", p1_hit_dt.HitStopTarget)
							imgui.multi_color("Stun:", p1_hit_dt.HitStun)
							imgui.multi_color("Knockdown Duration:", p1_hit_dt.DownTime)
							imgui.multi_color("Juggle Limit:", p1_hit_dt.JuggleLimit)
							imgui.multi_color("Juggle Increase:", p1_hit_dt.JuggleAdd)
							imgui.multi_color("Juggle Start:", p1_hit_dt.Juggle1st)
							p1_adv = p1_hit_dt.HitStopTarget 
						end
					
						imgui.tree_pop()
					end
					
					imgui.tree_pop()
				end
				if p1.chargeInfo:get_Count() > 0 then
					if imgui.tree_node("Charge Info") then
						for i=0,p1.chargeInfo:get_Count() - 1 do
							local value = p1.chargeInfo:get_Values()._dictionary._entries[i].value
							if value ~= nil then
								imgui.multi_color("Move " .. i + 1 .. " Charge Time:", value.charge_frame)
								imgui.multi_color("Move " .. i + 1 .. " Charge Keep Time:", value.keep_frame)
							end
						end
						
						imgui.tree_pop()
					end
				end
					
				imgui.tree_pop()
			end
			
			-- Player 2 Info
			if imgui.tree_node("P2") then
				if imgui.tree_node("General Info") then
					imgui.multi_color("Current HP:", p2.current_HP)
					imgui.multi_color("HP Cap:", p2.HP_cap)
					imgui.multi_color("HP Regen Cooldown:", p2.HP_cooldown)
					imgui.multi_color("Burnout:", tostring(p2.burnout))
					imgui.multi_color("Drive Gauge:", p2.drive_adjusted)
					imgui.multi_color("Drive Cooldown:", p2.drive_cooldown)
					imgui.multi_color("Super Gauge:", p2.super)
					imgui.multi_color("Buff Duration:", p2.buff)
					imgui.multi_color("Debuff Duration:", p2.debuff_timer)

					imgui.tree_pop()
				end
				if imgui.tree_node("State Info") then
					imgui.multi_color("Action ID:", p2.mActionId)
					imgui.multi_color("Action Frame:", math.floor(read_sfix(p2.mActionFrame)) .. " / " .. math.floor(read_sfix(p2.mMarginFrame)) .. " (" .. math.floor(read_sfix(p2.mEndFrame)) .. ")")
					imgui.multi_color("Current Hitstop:", p2.curr_hitstop .. " / " .. p2.max_hitstop)
					imgui.multi_color("Current Hitstun:", p2.curr_hitstun .. " / " .. p2.max_hitstun)
					imgui.multi_color("Current Blockstun:", p2.curr_blockstun .. " / " .. p2.max_blockstun)
					imgui.multi_color("Throw Protection Timer:", p2.throw_invuln)
					imgui.multi_color("Intangible Timer:", p2.full_invuln)

					imgui.tree_pop()
				end
				if imgui.tree_node("Movement Info") then
					if p2.dir == true then
						imgui.multi_color("Facing:", "Right")
					else
						imgui.multi_color("Facing:", "Left")
					end
					if p2.stance == 0 then
						imgui.multi_color("Stance:", "Standing")
					elseif p2.stance == 1 then
						imgui.multi_color("Stance:", "Crouching")
					else
						imgui.multi_color("Stance:", "Jumping")
					end
					imgui.multi_color("Position X:", string.format("%.2f", p2.posX))
					imgui.multi_color("Position Y:", string.format("%.2f", p2.posY))
					imgui.multi_color("Speed X:", string.format("%.2f", p2.spdX))
					imgui.multi_color("Speed Y:", string.format("%.2f", p2.spdY))
					imgui.multi_color("Acceleration X:", string.format("%.2f", p2.aclX))
					imgui.multi_color("Acceleration Y:", string.format("%.2f", p2.aclY))
					imgui.multi_color("Pushback:", string.format("%.2f", p2.pushback))
					imgui.multi_color("Self Pushback:", string.format("%.2f", p2.self_pushback))
					imgui.multi_color("Distance Between Players:", p2.gap)
					
					imgui.tree_pop()
				end
				if imgui.tree_node("Attack Info") then
					get_hitbox_range(cPlayer[1], cPlayer[1].mpActParam, p2)
					imgui.multi_color("Startup Frames:", p2.startup_frames)
					imgui.multi_color("Active Frames:", p2.active_frames)
					imgui.multi_color("Recovery Frames:", string.format("%.0f", p2.recovery_frames))
					imgui.multi_color("Total Frames:", string.format("%.0f", p2.total_frames))
					imgui.multi_color("Absolute Range:", string.format("%.2f", p2.absolute_range))
					imgui.multi_color("Relative Range:", string.format("%.2f", p2.relative_range))
					imgui.multi_color("Juggle Counter:", p1.juggle)
					imgui.multi_color("Combo Hit Count:", p2.combo_hit_count)
					imgui.multi_color("Combo Attack Count:", p2.combo_attack_count)
					imgui.multi_color("Combo Starter Scaling:", 100 - p2.combo_scale_start .. "%")
					imgui.multi_color("Current Hit Scaling:", p2.combo_scale_now .. "%")

					local p2_next_hit_scaling_calc = 100
					if p2.combo_attack_count == 1 then
						if p2.combo_scale_buff == 10 then
							p2_next_hit_scaling_calc = (100 - p2.combo_scale_start)
						else
							p2_next_hit_scaling_calc = (100 - p2.combo_scale_start) - p2.combo_scale_buff
						end
					elseif p2.combo_attack_count > 1 then
						p2_next_hit_scaling_calc = (100 - p2.combo_scale_start) - p2.combo_scale_buff
					else
						p2_next_hit_scaling_calc = 100 - p2.combo_scale_buff
					end
					imgui.multi_color("Next Hit Scaling:", p2_next_hit_scaling_calc .. "%")

					if imgui.tree_node("Latest Attack Info") then
						if p2_hit_dt == nil then
							imgui.text_colored("No hit yet", 0xFFAAFFFF)
						else
							imgui.multi_color("Damage:", p2_hit_dt.DmgValue)
							imgui.multi_color("Self Drive Gain:", p2_hit_dt.FocusOwn)
							imgui.multi_color("Opponent Drive Gain:", p2_hit_dt.FocusTgt)
							imgui.multi_color("Self Super Gain:", p2_hit_dt.SuperOwn)
							imgui.multi_color("Opponent Super Gain:", p2_hit_dt.SuperTgt)
							imgui.multi_color("Self Hitstop:", p2_hit_dt.HitStopOwner)
							imgui.multi_color("Opponent Hitstop:", p2_hit_dt.HitStopTarget)
							imgui.multi_color("Stun:", p2_hit_dt.HitStun)
							imgui.multi_color("Knockdown Duration:", p2_hit_dt.DownTime)
							imgui.multi_color("Juggle Limit:", p2_hit_dt.JuggleLimit)
							imgui.multi_color("Juggle Increase:", p2_hit_dt.JuggleAdd)
							imgui.multi_color("Juggle Start:", p2_hit_dt.Juggle1st)
						end
					
						imgui.tree_pop()
					end
					
					imgui.tree_pop()
				end
				if p2.chargeInfo:get_Count() > 0 then
					if imgui.tree_node("Charge Info") then
						for i=0,p2.chargeInfo:get_Count() - 1 do
							local value = p2.chargeInfo:get_Values()._dictionary._entries[i].value
							if value ~= nil then
								imgui.multi_color("Move " .. i + 1 .. " Charge Time:", value.charge_frame)
								imgui.multi_color("Move " .. i + 1 .. " Charge Keep Time:", value.keep_frame)
							end
						end
						
						imgui.tree_pop()
					end
				end
					
				imgui.tree_pop()
			end
			
		imgui.end_window()
		end
		
		if display_projectile_info then
			-- Fireball UI
			imgui.begin_window("Projectile Data", true, 0)
			-- P1 Fireball
			if imgui.tree_node("P1 Projectile Info") then		
				for i, obj in pairs(cWork) do
					if obj.owner_add ~= nil and obj.pl_no == 0 then
						local objEngine = obj.mpActParam.ActionPart._Engine
						if imgui.tree_node("Projectile " .. i) then
							imgui.multi_color("Action ID:", obj.mActionId)
							imgui.multi_color("Action Frame:", math.floor(read_sfix(objEngine:get_ActionFrame())) .. " / " .. math.floor(read_sfix(objEngine:get_MarginFrame())) .. " (" .. math.floor(read_sfix(objEngine:get_ActionFrameNum())) .. ")")
							imgui.multi_color("Position X:", obj.pos.x.v / 65536.0)
							imgui.multi_color("Position Y:", obj.pos.y.v / 65536.0)
							imgui.multi_color("Speed X:", obj.speed.x.v / 65536.0)
							imgui.multi_color("Speed Y:", obj.speed.y.v / 65536.0)
							imgui.multi_color("Current Hitstop:", obj.hit_stop .. " / " .. obj.hit_stop_org)
							
							imgui.tree_pop()
						end
					end
				end
					
				imgui.tree_pop()
			end
			-- P2 Fireball
			if imgui.tree_node("P2 Projectile Info") then		
				for i, obj in pairs(cWork) do
					if obj.owner_add ~= nil and obj.pl_no == 1 then
						local objEngine = obj.mpActParam.ActionPart._Engine
						if imgui.tree_node("Projectile " .. i) then
							imgui.multi_color("Action ID:", obj.mActionId)
							imgui.multi_color("Action Frame:", math.floor(read_sfix(objEngine:get_ActionFrame())) .. " / " .. math.floor(read_sfix(objEngine:get_MarginFrame())) .. " (" .. math.floor(read_sfix(objEngine:get_ActionFrameNum())) .. ")")
							imgui.multi_color("Position X:", obj.pos.x.v / 65536.0)
							imgui.multi_color("Position Y:", obj.pos.y.v / 65536.0)
							imgui.multi_color("Speed X:", obj.speed.x.v / 65536.0)
							imgui.multi_color("Speed Y:", obj.speed.y.v / 65536.0)
							imgui.multi_color("Current Hitstop:", obj.hit_stop .. " / " .. obj.hit_stop_org)
							
							imgui.tree_pop()
						end
					end
				end
					
				imgui.tree_pop()
			end
			
			imgui.end_window()
		end
    end 
end)