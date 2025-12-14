-- Original code from https://github.com/WistfulHopes/SF6Mods
local CONFIG_PATH = "disp_hitboxes.json"
local config = json.load_file(CONFIG_PATH) or {}

local SAVE_DELAY = 0.5
local save_pending = false
local save_timer = 0

local changed
local gBattle
local isUnpaused = true
local default = {
	hide_p1 = false,
	display_p1_hitboxes = true,
	display_p1_hurtboxes = true,
	display_p1_pushboxes = true,
	display_p1_throwboxes = true,
	display_p1_throwhurtboxes = true,
	display_p1_proximityboxes = true,
	display_p1_uniqueboxes = true,
	display_p1_properties = true,
	display_p1_position = true,
	display_p1_clashbox = true,
	p1_hitbox_opacity = 25,
	p1_hurtbox_opacity = 25,
	p1_pushbox_opacity = 25,
	p1_proximitybox_opacity = 25,
	p1_position_opacity = 100,
	hide_p2 = false,
	display_p2_hitboxes = true,
	display_p2_hurtboxes = true,
	display_p2_pushboxes = true,
	display_p2_throwboxes = true,
	display_p2_throwhurtboxes = true,
	display_p2_proximityboxes = true,
	display_p2_uniqueboxes = true,
	display_p2_properties = true,
	display_p2_position = true,
	display_p2_clashbox = true,
	p2_hitbox_opacity = 25,
	p2_hurtbox_opacity = 25,
	p2_pushbox_opacity = 25,
	p2_proximitybox_opacity = 25,
	p2_position_opacity = 100,
	display_options_menu = true
}
for k, v in pairs(default) do
	if config[k] == nil then
		config[k] = v
	end
end

local function setup_hook(type_name, method_name, pre_func, post_func)
    local type_def = sdk.find_type_definition(type_name)
    if type_def then
        local method = type_def:get_method(method_name)
        if method then
            sdk.hook(method, pre_func, post_func)
        end
    end
end

-- Hide drawn objects when game is paused
setup_hook("app.PauseManager", "requestPauseStart", nil, function(retval)
    isUnpaused = false
    return retval
end)

setup_hook("app.PauseManager", "requestPauseEnd", nil, function(retval)
    isUnpaused = true
    return retval
end)

local reversePairs = function ( aTable )
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

function bitand(a, b)
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

local applyOpacity = function ( alphaInt, colorWithoutAlpha )
	if alphaInt < 0 then alphaInt = 0 end
	if alphaInt > 100 then alphaInt = 100 end

	local alpha = math.floor((alphaInt / 100) * 255)
    return alpha * 0x1000000 + colorWithoutAlpha
end

local draw_p1_boxes = function ( work, actParam )
    local col = actParam.Collision
    for j, rect in reversePairs(col.Infos._items) do
        if rect ~= nil then
			local posX = rect.OffsetX.v / 6553600.0
			local posY = rect.OffsetY.v / 6553600.0
			local sclX = rect.SizeX.v / 6553600.0 * 2
            local sclY = rect.SizeY.v / 6553600.0 * 2
			posX = posX - sclX / 2
			posY = posY - sclY / 2

			local screenTL = draw.world_to_screen(Vector3f.new(posX - sclX / 2, posY + sclY / 2, 0))
			local screenTR = draw.world_to_screen(Vector3f.new(posX + sclX / 2, posY + sclY / 2, 0))
			local screenBL = draw.world_to_screen(Vector3f.new(posX - sclX / 2, posY - sclY / 2, 0))
			local screenBR = draw.world_to_screen(Vector3f.new(posX + sclX / 2, posY - sclY / 2, 0))

			if screenTL and screenTR and screenBL and screenBR then
			
				local finalPosX = (screenTL.x + screenTR.x) / 2
				local finalPosY = (screenBL.y + screenTL.y) / 2
				local finalSclX = (screenTR.x - screenTL.x)
				local finalSclY = (screenTL.y - screenBL.y)
				
				-- If the rectangle has a HitPos field, it falls under attack boxes
				if rect:get_field("HitPos") ~= nil then
					-- TypeFlag > 0 indicates a regular hitbox
					if rect.TypeFlag > 0 and config.display_p1_hitboxes then 
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF0040C0)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p1_hitbox_opacity, 0x0040C0))
						-- Identify hitbox properties
						local hitboxExceptions = "Can't Hit "
						local comboOnly = "Combo "
						-- CondFlag: 16		(Can't hit standing opponent)
						-- CondFlag: 32		(Can't hit crouching opponents)
						-- CondFlag: 64		(Can't hit airborne)
						-- CondFlag: 256	(Can't hit in front of the player)
						-- CondFlag: 512	(Can't hit behind the player)
						-- CondFlag: 262144	(Strike that can only hit a juggled/combo'd opponent)
						-- CondFlag: 524288 (Projectile that can only hit a juggled/combo'd opponent)
						if bitand(rect.CondFlag, 16) == 16 then
							hitboxExceptions = hitboxExceptions .. "Standing, "
						end
						if bitand(rect.CondFlag, 32) == 32 then
							hitboxExceptions = hitboxExceptions .. "Crouching, "
						end
						if bitand(rect.CondFlag, 64) == 64 then
							hitboxExceptions = hitboxExceptions .. "Airborne, "
						end
						if bitand(rect.CondFlag, 256) == 256 then
							hitboxExceptions = hitboxExceptions .. "Forward, "
						end
						if bitand(rect.CondFlag, 512) == 512 then
							hitboxExceptions = hitboxExceptions .. "Backwards, "
						end	
						if bitand(rect.CondFlag, 262144) == 262144 then 
							comboOnly = comboOnly .. "Only"
						end
						if bitand(rect.CondFlag, 524288) == 524288 then
							comboOnly = comboOnly .. "Only"
						end
						if config.display_p1_properties then
							local fullString = ""
							if string.len(hitboxExceptions) > 10 then
								-- Remove final commma
								hitboxExceptions = string.sub(hitboxExceptions, 0, -3)
								fullString = fullString .. hitboxExceptions .. "\n"
							end
							if string.len(comboOnly) > 6 then
								fullString = fullString .. comboOnly .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), 0xFFFFFFFF)
						end
					-- Throws almost* universally have a TypeFlag of 0 and a PoseBit > 0 
					-- Except for JP's command grab projectile which has neither and must be caught with CondFlag of 0x2C0
					elseif ((rect.TypeFlag == 0 and rect.PoseBit > 0) or rect.CondFlag == 0x2C0) and config.display_p1_throwboxes then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFD080FF)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0x4DD080FF)
						-- Identify hitbox properties
						local hitboxExceptions = "Can't Hit "
						local comboOnly = "Combo "
						-- CondFlag: 16		(Can't hit standing opponent)
						-- CondFlag: 32		(Can't hit crouching opponents)
						-- CondFlag: 64		(Can't hit airborne)
						-- CondFlag: 256	(Can't hit in front of the player)
						-- CondFlag: 512	(Can't hit behind the player)
						-- CondFlag: 262144	(Strike that can only hit a juggled/combo'd opponent)
						-- CondFlag: 524288 (Projectile that can only hit a juggled/combo'd opponent)
						if bitand(rect.CondFlag, 16) == 16 then
							hitboxExceptions = hitboxExceptions .. "Standing, "
						end
						if bitand(rect.CondFlag, 32) == 32 then
							hitboxExceptions = hitboxExceptions .. "Crouching, "
						end
						if bitand(rect.CondFlag, 64) == 64 then
							hitboxExceptions = hitboxExceptions .. "Airborne, "
						end
						if bitand(rect.CondFlag, 256) == 256 then
							hitboxExceptions = hitboxExceptions .. "Forward, "
						end
						if bitand(rect.CondFlag, 512) == 512 then
							hitboxExceptions = hitboxExceptions .. "Backwards, "
						end	
						if bitand(rect.CondFlag, 262144) == 262144 then 
							comboOnly = comboOnly .. "Only"
						end
						if bitand(rect.CondFlag, 524288) == 524288 then
							comboOnly = comboOnly .. "Only"
						end
						-- Display hitbox properties
						if config.display_p1_properties then
							local fullString = ""
							if string.len(hitboxExceptions) > 10 then
								-- Remove final commma
								hitboxExceptions = string.sub(hitboxExceptions, 0, -3)
								fullString = fullString .. hitboxExceptions .. "\n"
							end
							if string.len(comboOnly) > 6 then
								fullString = fullString .. comboOnly .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), 0xFFFFFFFF)
						end
					-- Projectile Clash boxes have a GuardBit of 0 (while most other boxes have either 7 or some random, non-zero, positive integer)
					elseif rect.GuardBit == 0 and config.display_p1_clashbox then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF3891E6)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0x403891E6)
					-- Any remaining boxes are drawn as proximity boxes
					elseif config.display_p1_proximityboxes then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF5b5b5b)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p1_proximitybox_opacity, 0x5b5b5b))
					end
				-- If the box contains the Attr field, then it is a pushbox
				elseif rect:get_field("Attr") ~= nil then
					if config.display_p1_pushboxes then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF00FFFF)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p1_pushbox_opacity, 0x00FFFF))
					end
				-- If the rectangle has a HitNo field, the box falls under hurt boxes
				elseif rect:get_field("HitNo") ~= nil then
					if config.display_p1_hurtboxes then
						-- Armor (Type: 1) & Parry (Type: 2) Boxes
						if rect.Type == 2 or rect.Type == 1 then			
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFFF0080)
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p1_hurtbox_opacity, 0xFF0080))
						-- All other hurtboxes
						else
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF00FF00)
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p1_hurtbox_opacity, 0x00FF00))
						end
						-- Identify HurtboxType as text (each at a unique height)
						local hurtInvuln = ""
						-- TypeFlag:	1	(Projectile Invuln)
						-- TypeFlag:	2	(Strike Invuln)
						if rect.TypeFlag == 1 then
							hurtInvuln = hurtInvuln .. "Projectile"
						end
						if rect.TypeFlag == 2 then
							hurtInvuln = hurtInvuln .. "Strike"
						end
						-- Identify Hurtbox Immunities as text (each at a unique height)
						local hurtImmune = ""
						-- Immune:		1	(Stand Attack Intangibility)
						-- Immune:		2	(Crouch Attack Intangibility)
						-- Immune:		4	(Air Attack Intangibility)
						-- Immune:		64	(Cross-Up Attack Intangibility)
						-- Immune:		128	(Reverse Hit Intangibility)
						if bitand(rect.Immune, 1) == 1 then
							hurtImmune = hurtImmune .. "Stand, "
						end
						if bitand(rect.Immune, 2) == 2 then
							hurtImmune = hurtImmune .. "Crouch, "
						end
						if bitand(rect.Immune, 4) == 4 then
							hurtImmune = hurtImmune .. "Air, "
						end
						if bitand(rect.Immune, 64) == 64 then
							hurtImmune = hurtImmune .. "Behind, "
						end
						if bitand(rect.Immune, 128) == 128 then
							hurtImmune = hurtImmune .. "Reverse, "
						end
						-- Display hurtbox properties
						if config.display_p1_properties then
							local fullString = ""
							if string.len(hurtInvuln) > 0 then
								-- Remove final commma
								hurtInvuln = hurtInvuln .. " Invulnerable"
								fullString = fullString .. hurtInvuln .. "\n"
							end
							if string.len(hurtImmune) > 0 then
								hurtImmune = string.sub(hurtImmune, 0, -3)
								hurtImmune = hurtImmune .. " Attack Intangible"
								fullString = fullString .. hurtImmune .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), 0xFFFFFFFF)
						end
					end
				-- UniqueBoxes have a special field called KeyData
				elseif rect:get_field("KeyData") ~= nil and config.display_p1_uniqueboxes then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFEEFF00)
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0x4DEEFF00)
				-- Any remaining rectangles are drawn as a grab box
				elseif rect:get_field("KeyData") == nil and config.display_p1_throwhurtboxes then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFFF0000)
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0x4DFF0000)
				end
			end
		end
	end
end

local draw_p2_boxes = function ( work, actParam )
    local col = actParam.Collision
    for j, rect in reversePairs(col.Infos._items) do
        if rect ~= nil then
			local posX = rect.OffsetX.v / 6553600.0
			local posY = rect.OffsetY.v / 6553600.0
			local sclX = rect.SizeX.v / 6553600.0 * 2
            local sclY = rect.SizeY.v / 6553600.0 * 2
			posX = posX - sclX / 2
			posY = posY - sclY / 2

			local screenTL = draw.world_to_screen(Vector3f.new(posX - sclX / 2, posY + sclY / 2, 0))
			local screenTR = draw.world_to_screen(Vector3f.new(posX + sclX / 2, posY + sclY / 2, 0))
			local screenBL = draw.world_to_screen(Vector3f.new(posX - sclX / 2, posY - sclY / 2, 0))
			local screenBR = draw.world_to_screen(Vector3f.new(posX + sclX / 2, posY - sclY / 2, 0))

			if screenTL and screenTR and screenBL and screenBR then
			
				local finalPosX = (screenTL.x + screenTR.x) / 2
				local finalPosY = (screenBL.y + screenTL.y) / 2
				local finalSclX = (screenTR.x - screenTL.x)
				local finalSclY = (screenTL.y - screenBL.y)
				
				-- If the rectangle has a HitPos field, it falls under attack boxes
				if rect:get_field("HitPos") ~= nil then
					-- TypeFlag > 0 indicates a regular hitbox
					if rect.TypeFlag > 0 and config.display_p2_hitboxes then 
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF0040C0)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p2_hitbox_opacity, 0x0040C0))
						-- Identify hitbox properties
						local hitboxExceptions = "Can't Hit "
						local comboOnly = "Combo "
						-- CondFlag: 16		(Can't hit standing opponent)
						-- CondFlag: 32		(Can't hit crouching opponents)
						-- CondFlag: 64		(Can't hit airborne)
						-- CondFlag: 256	(Can't hit in front of the player)
						-- CondFlag: 512	(Can't hit behind the player)
						-- CondFlag: 262144	(Strike that can only hit a juggled/combo'd opponent)
						-- CondFlag: 524288 (Projectile that can only hit a juggled/combo'd opponent)
						if bitand(rect.CondFlag, 16) == 16 then
							hitboxExceptions = hitboxExceptions .. "Standing, "
						end
						if bitand(rect.CondFlag, 32) == 32 then
							hitboxExceptions = hitboxExceptions .. "Crouching, "
						end
						if bitand(rect.CondFlag, 64) == 64 then
							hitboxExceptions = hitboxExceptions .. "Airborne, "
						end
						if bitand(rect.CondFlag, 256) == 256 then
							hitboxExceptions = hitboxExceptions .. "Forward, "
						end
						if bitand(rect.CondFlag, 512) == 512 then
							hitboxExceptions = hitboxExceptions .. "Backwards, "
						end	
						if bitand(rect.CondFlag, 262144) == 262144 then 
							comboOnly = comboOnly .. "Only"
						end
						if bitand(rect.CondFlag, 524288) == 524288 then
							comboOnly = comboOnly .. "Only"
						end
						if config.display_p2_properties then
							local fullString = ""
							if string.len(hitboxExceptions) > 10 then
								-- Remove final commma
								hitboxExceptions = string.sub(hitboxExceptions, 0, -3)
								fullString = fullString .. hitboxExceptions .. "\n"
							end
							if string.len(comboOnly) > 6 then
								fullString = fullString .. comboOnly .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), 0xFFFFFFFF)
						end
					-- Throws almost* universally have a TypeFlag of 0 and a PoseBit > 0 
					-- Except for JP's command grab projectile which has neither and must be caught with CondFlag of 0x2C0
					elseif ((rect.TypeFlag == 0 and rect.PoseBit > 0) or rect.CondFlag == 0x2C0) and config.display_p2_throwboxes then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFD080FF)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0x4DD080FF)
						-- Identify hitbox properties
						local hitboxExceptions = "Can't Hit "
						local comboOnly = "Combo "
						-- CondFlag: 16		(Can't hit standing opponent)
						-- CondFlag: 32		(Can't hit crouching opponents)
						-- CondFlag: 64		(Can't hit airborne)
						-- CondFlag: 256	(Can't hit in front of the player)
						-- CondFlag: 512	(Can't hit behind the player)
						-- CondFlag: 262144	(Strike that can only hit a juggled/combo'd opponent)
						-- CondFlag: 524288 (Projectile that can only hit a juggled/combo'd opponent)
						if bitand(rect.CondFlag, 16) == 16 then
							hitboxExceptions = hitboxExceptions .. "Standing, "
						end
						if bitand(rect.CondFlag, 32) == 32 then
							hitboxExceptions = hitboxExceptions .. "Crouching, "
						end
						if bitand(rect.CondFlag, 64) == 64 then
							hitboxExceptions = hitboxExceptions .. "Airborne, "
						end
						if bitand(rect.CondFlag, 256) == 256 then
							hitboxExceptions = hitboxExceptions .. "Forward, "
						end
						if bitand(rect.CondFlag, 512) == 512 then
							hitboxExceptions = hitboxExceptions .. "Backwards, "
						end	
						if bitand(rect.CondFlag, 262144) == 262144 then 
							comboOnly = comboOnly .. "Only"
						end
						if bitand(rect.CondFlag, 524288) == 524288 then
							comboOnly = comboOnly .. "Only"
						end
						-- Display hitbox properties
						if config.display_p2_properties then
							local fullString = ""
							if string.len(hitboxExceptions) > 10 then
								-- Remove final commma
								hitboxExceptions = string.sub(hitboxExceptions, 0, -3)
								fullString = fullString .. hitboxExceptions .. "\n"
							end
							if string.len(comboOnly) > 6 then
								fullString = fullString .. comboOnly .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), 0xFFFFFFFF)
						end
					-- Projectile Clash boxes have a GuardBit of 0 (while most other boxes have either 7 or some random, non-zero, positive integer)
					elseif rect.GuardBit == 0 and config.display_p2_clashbox then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF3891E6)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0x403891E6)
					-- Any remaining boxes are drawn as proximity boxes
					elseif config.display_p2_proximityboxes then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF5b5b5b)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p2_proximitybox_opacity, 0x5b5b5b))
					end
				-- If the box contains the Attr field, then it is a pushbox
				elseif rect:get_field("Attr") ~= nil then
					if config.display_p2_pushboxes then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF00FFFF)
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p2_pushbox_opacity, 0x00FFFF))
					end
				-- If the rectangle has a HitNo field, the box falls under hurt boxes
				elseif rect:get_field("HitNo") ~= nil then
					if config.display_p2_hurtboxes then
						-- Armor (Type: 1) & Parry (Type: 2) Boxes
						if rect.Type == 2 or rect.Type == 1 then			
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFFF0080)
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p2_hurtbox_opacity, 0xFF0080))
						-- All other hurtboxes
						else
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFF00FF00)
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, applyOpacity(config.p2_hurtbox_opacity, 0x00FF00))
						end
						-- Identify HurtboxType as text (each at a unique height)
						local hurtInvuln = ""
						-- TypeFlag:	1	(Projectile Invuln)
						-- TypeFlag:	2	(Strike Invuln)
						if rect.TypeFlag == 1 then
							hurtInvuln = hurtInvuln .. "Projectile"
						end
						if rect.TypeFlag == 2 then
							hurtInvuln = hurtInvuln .. "Strike"
						end
						-- Identify Hurtbox Immunities as text (each at a unique height)
						local hurtImmune = ""
						-- Immune:		1	(Stand Attack Intangibility)
						-- Immune:		2	(Crouch Attack Intangibility)
						-- Immune:		4	(Air Attack Intangibility)
						-- Immune:		64	(Cross-Up Attack Intangibility)
						-- Immune:		128	(Reverse Hit Intangibility)
						if bitand(rect.Immune, 1) == 1 then
							hurtImmune = hurtImmune .. "Stand, "
						end
						if bitand(rect.Immune, 2) == 2 then
							hurtImmune = hurtImmune .. "Crouch, "
						end
						if bitand(rect.Immune, 4) == 4 then
							hurtImmune = hurtImmune .. "Air, "
						end
						if bitand(rect.Immune, 64) == 64 then
							hurtImmune = hurtImmune .. "Behind, "
						end
						if bitand(rect.Immune, 128) == 128 then
							hurtImmune = hurtImmune .. "Reverse, "
						end
						-- Display hurtbox properties
						if config.display_p2_properties then
							local fullString = ""
							if string.len(hurtInvuln) > 0 then
								-- Remove final commma
								hurtInvuln = hurtInvuln .. " Invulnerable"
								fullString = fullString .. hurtInvuln .. "\n"
							end
							if string.len(hurtImmune) > 0 then
								hurtImmune = string.sub(hurtImmune, 0, -3)
								hurtImmune = hurtImmune .. " Attack Intangible"
								fullString = fullString .. hurtImmune .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), 0xFFFFFFFF)
						end
					end
				-- UniqueBoxes have a special field called KeyData
				elseif rect:get_field("KeyData") ~= nil and config.display_p2_uniqueboxes then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFEEFF00)
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0x4DEEFF00)
				-- Any remaining rectangles are drawn as a grab box
				elseif rect:get_field("KeyData") == nil and config.display_p2_throwhurtboxes then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFFF0000)
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0x4DFF0000)
				end
			end
		end
	end
end

-- Prevent I/O spam
local function mark_config_dirty()
    save_pending = true
    save_timer = SAVE_DELAY
end

local function save_config()
    json.dump_file(CONFIG_PATH, config)
	save_pending = false
end

local function saver_checkbox(label, val)
    local changed, new_val = imgui.checkbox(label, val)
    if changed then
        mark_config_dirty()
    end
    return changed, new_val
end

local function saver_drag_int(label, val, speed, min, max)
    local changed, new_val = imgui.drag_int(label, val, speed or 1.0, min or 0, max or 100)
    if changed then
        mark_config_dirty()
    end
    return changed, new_val
end

local function set_toggler(label, config_suffix, id_suffix)
    imgui.table_next_row()
    imgui.table_set_column_index(0)
    imgui.text(label)
    imgui.table_set_column_index(1)
    if not config.hide_p1 then
        changed, config["display_p1_" .. config_suffix] = saver_checkbox("##p1_" .. id_suffix, config["display_p1_" .. config_suffix])
    end
    imgui.table_set_column_index(2)
    if not config.hide_p2 then
        changed, config["display_p2_" .. config_suffix] = saver_checkbox("##p2_" .. id_suffix, config["display_p2_" .. config_suffix])
    end
end

local function set_opacitier(label, box_type, opacity_suffix)
    local p1_display = "display_p1_" .. box_type
    local p2_display = "display_p2_" .. box_type
    local p1_opacity = "p1_" .. opacity_suffix .. "_opacity"
    local p2_opacity = "p2_" .. opacity_suffix .. "_opacity"
    
    if config[p1_display] or config[p2_display] then
        imgui.table_next_row()
        imgui.table_set_column_index(0)
        imgui.text(label)
        imgui.table_set_column_index(1)
        if not config.hide_p1 and config[p1_display] then
            changed, config[p1_opacity] = saver_drag_int("##p1_" .. opacity_suffix .. "Opacity", config[p1_opacity], 0.5, 0, 100)
        end
        imgui.table_set_column_index(2)
        if not config.hide_p2 and config[p2_display] then
            changed, config[p2_opacity] = saver_drag_int("##p2_" .. opacity_suffix .. "Opacity", config[p2_opacity], 0.5, 0, 100)
        end
    end
end

re.on_draw_ui(function()
    if imgui.tree_node("Hitbox Viewer") then
		changed, config.display_options_menu = saver_checkbox("Display Options Menu", config.display_options_menu)
		imgui.tree_pop()
	end
end)

re.on_frame(function()
	if save_pending then
		save_timer = save_timer - (1.0 / 60.0)  -- Assume 60 FPS
		if save_timer <= 0 then
			save_config()
		end
	end

    gBattle = sdk.find_type_definition("gBattle")
    if gBattle then
		local sPlayer = gBattle:get_field("Player"):get_data(nil)

		if config.display_options_menu and sPlayer.prev_no_push_bit ~= 0 then
			imgui.begin_window("Hitboxes", true, 0)

			if imgui.tree_node("Toggle") then
				
				if imgui.begin_table("OptionsTable", 3) then
					imgui.table_setup_column("", nil, 60)
					imgui.table_setup_column("P1", nil, 20)
					imgui.table_setup_column("P2", nil, 20)
					
					imgui.table_headers_row()

					imgui.table_next_row()
					imgui.table_set_column_index(0)
					imgui.text("Hide All")
					imgui.table_set_column_index(1)
					changed, config.hide_p1 = saver_checkbox("##p1_Hide", config.hide_p1)
					imgui.table_set_column_index(2)
					changed, config.hide_p2 = saver_checkbox("##p2_Hide", config.hide_p2)
					
					if not config.hide_p1 or not config.hide_p2 then
						set_toggler("Hitbox", "hitboxes", "Hitboxes")
						set_toggler("Hurtbox", "hurtboxes", "Hurtboxes")
						set_toggler("Pushbox", "pushboxes", "Pushboxes")
						set_toggler("Throwbox", "throwboxes", "ThrowBoxes")
						set_toggler("Throw Hurtbox", "throwhurtboxes", "ThrowHurtboxes")
						set_toggler("Proximity Box", "proximityboxes", "ProximityBoxes")
						set_toggler("Proj. Clash Box", "clashbox", "ProjectileClash")
						set_toggler("Unique Box", "uniqueboxes", "UniqueBoxes")
						set_toggler("Properties", "properties", "Properties")
						set_toggler("Position", "position", "Position")
					end
					imgui.end_table()
				end
				imgui.tree_pop()
			end

			if not config.hide_p1 or not config.hide_p2 then
				if imgui.tree_node("Opacity") then

					if not config.hide_p1 or not config.hide_p2 then
						if imgui.begin_table("OpacityTable", 3) then
							imgui.table_setup_column("", nil, 60)

							if not config.hide_p1 then imgui.table_setup_column("P1", nil, 20)
							else imgui.table_setup_column("", nil, 20) end

							if not config.hide_p2 then imgui.table_setup_column("P2", nil, 20)
							else imgui.table_setup_column("", nil, 20) end

							imgui.table_headers_row()

							set_opacitier("Hitbox", "hitboxes", "hitbox")
							set_opacitier("Hurtbox", "hurtboxes", "hurtbox")
							set_opacitier("Pushbox", "pushboxes", "pushbox")
							set_opacitier("Proximity", "proximityboxes", "proximitybox")
							set_opacitier("Position", "position", "position")
							
							imgui.end_table()
						end
					end
				imgui.tree_pop()
				end
			end
		imgui.end_window()
		end

		if isUnpaused then
			local sWork = gBattle:get_field("Work"):get_data(nil)
			local cWork = sWork.Global_work
			for i, obj in pairs(cWork) do
				local actParam = obj.mpActParam
				if actParam and not obj:get_IsR0Die() and obj:get_IsTeam1P() then
					draw_p1_boxes(obj, actParam)
					local objPos = draw.world_to_screen(Vector3f.new(obj.pos.x.v / 6553600.0, obj.pos.y.v / 6553600.0, 0))
						if objPos and config.display_p1_position then
						draw.filled_circle(objPos.x, objPos.y, 10, applyOpacity(config.p1_position_opacity, 0xFFFFFF), 10);
					end
				end
				if actParam and not obj:get_IsR0Die() and obj:get_IsTeam2P() then
					draw_p2_boxes(obj, actParam)
					local objPos = draw.world_to_screen(Vector3f.new(obj.pos.x.v / 6553600.0, obj.pos.y.v / 6553600.0, 0))
						if objPos and config.display_p2_position then
						draw.filled_circle(objPos.x, objPos.y, 10, applyOpacity(config.p2_position_opacity, 0xFFFFFF), 10);
					end
				end
			end
			local sPlayer = gBattle:get_field("Player"):get_data(nil)
			local cPlayer = sPlayer.mcPlayer
			for i, player in pairs(cPlayer) do
				local actParam = player.mpActParam
				if i == 0 and actParam and not config.hide_p1 then
					draw_p1_boxes(player, actParam)
					local worldPos = draw.world_to_screen(Vector3f.new(player.pos.x.v / 6553600.0, player.pos.y.v / 6553600.0, 0))
					if worldPos and config.display_p1_position then
						draw.filled_circle(worldPos.x, worldPos.y, 10, applyOpacity(config.p1_position_opacity, 0xFFFFFF), 10);
					end
				end
				if i == 1 and actParam and not config.hide_p2 then
					draw_p2_boxes(player, actParam)
					local worldPos = draw.world_to_screen(Vector3f.new(player.pos.x.v / 6553600.0, player.pos.y.v / 6553600.0, 0))
					if worldPos and config.display_p2_position then
						draw.filled_circle(worldPos.x, worldPos.y, 10, applyOpacity(config.p2_position_opacity, 0xFFFFFF), 10);
					end
				end
			end
        end
    end
end)