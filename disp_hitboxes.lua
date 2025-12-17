-- Original code from https://github.com/WistfulHopes/SF6Mods

local reframework = reframework
local CONFIG_PATH = "disp_hitboxes.json"
local config = json.load_file(CONFIG_PATH) or {}

local SAVE_DELAY = 0.5
local save_pending = false
local save_timer = 0

local changed
local gBattle
local isUnpaused = true
local default = {}

default.options = {}
default.options.display_menu = true

default.p1 = {}
default.p1.toggle = {
	hide_all = false,
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
default.p1.opacity = {
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

default.p2 = {}
default.p2.toggle = {
	hide_all = false,
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
default.p2.opacity = {
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

setup_hook("app.training.TrainingManager", "BattleStart", nil, function(retval)
    isUnpaused = true
    return retval
end)

setup_hook("app.PauseManager", "requestPauseStart", nil, function(retval)
    isUnpaused = false
    return retval
end)

setup_hook("app.PauseManager", "requestPauseEnd", nil, function(retval)
    isUnpaused = true
    return retval
end)

local apply_opacity = function ( alphaInt, colorWithoutAlpha )
	if alphaInt < 0 then alphaInt = 0 end
	if alphaInt > 100 then alphaInt = 100 end

	local alpha = math.floor((alphaInt / 100) * 255)
    return alpha * 0x1000000 + colorWithoutAlpha
end

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
					if rect.TypeFlag > 0 then
						if config.p1.toggle.hitboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.hitbox_outline, 0x0040C0))
						end
						if config.p1.toggle.hitboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.hitbox, 0x0040C0))
						end
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
						if config.p1.toggle.properties then
							local fullString = ""
							if string.len(hitboxExceptions) > 10 then
								-- Remove final commma
								hitboxExceptions = string.sub(hitboxExceptions, 1, -3)
								fullString = fullString .. hitboxExceptions .. "\n"
							end
							if string.len(comboOnly) > 6 then
								fullString = fullString .. comboOnly .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), apply_opacity(config.p1.opacity.properties, 0xFFFFFF))
						end
					-- Throws almost* universally have a TypeFlag of 0 and a PoseBit > 0 
					-- Except for JP's command grab projectile which has neither and must be caught with CondFlag of 0x2C0
					elseif ((rect.TypeFlag == 0 and rect.PoseBit > 0) or rect.CondFlag == 0x2C0) then
						if config.p1.toggle.throwboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.throwbox_outline, 0xD080FF))
						end
						if config.p1.toggle.throwboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.throwbox, 0xD080FF))
						end
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
						if config.p1.toggle.properties then
							local fullString = ""
							if string.len(hitboxExceptions) > 10 then
								-- Remove final comma
								hitboxExceptions = string.sub(hitboxExceptions, 1, -3)
								fullString = fullString .. hitboxExceptions .. "\n"
							end
							if string.len(comboOnly) > 6 then
								fullString = fullString .. comboOnly .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), apply_opacity(config.p1.opacity.properties, 0xFFFFFF))
						end
					-- Projectile Clash boxes have a GuardBit of 0 (while most other boxes have either 7 or some random, non-zero, positive integer)
					elseif rect.GuardBit == 0 then
						if config.p1.toggle.clashboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.clashbox_outline, 0x3891E6))
						end
						if config.p1.toggle.clashboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.clashbox, 0x3891E6))
						end
					-- Any remaining boxes are drawn as proximity boxes
					elseif config.p1.toggle.proximityboxes or config.p1.toggle.proximityboxes_outline then
						if config.p1.toggle.proximityboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.proximitybox_outline, 0x5b5b5b))
						end
						if config.p1.toggle.proximityboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.proximitybox, 0x5b5b5b))
						end
					end
				-- If the box contains the Attr field, then it is a pushbox
				elseif rect:get_field("Attr") ~= nil then
					if config.p1.toggle.pushboxes_outline then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.pushbox_outline, 0x00FFFF))
					end
					if config.p1.toggle.pushboxes then
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.pushbox, 0x00FFFF))
					end
				-- If the rectangle has a HitNo field, the box falls under hurt boxes
				elseif rect:get_field("HitNo") ~= nil then
					if config.p1.toggle.hurtboxes or config.p1.toggle.hurtboxes_outline then
						-- Armor (Type: 1) & Parry (Type: 2) Boxes
						if rect.Type == 2 or rect.Type == 1 then
							if config.p1.toggle.hurtboxes_outline then	
								draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.hurtbox_outline, 0xFF0080))
							end
							if config.p1.toggle.hurtboxes then
								draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.hurtbox, 0xFF0080))
							end
						-- All other hurtboxes
						else
							if config.p1.toggle.hurtboxes_outline then
								draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.hurtbox, 0xFF0080))
							end
							if config.p1.toggle.hurtboxes then
								draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.hurtbox, 0x00FF00))
							end
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
						if config.p1.toggle.properties then
							local fullString = ""
							if string.len(hurtInvuln) > 0 then
								-- Remove final commma
								hurtInvuln = hurtInvuln .. " Invulnerable"
								fullString = fullString .. hurtInvuln .. "\n"
							end
							if string.len(hurtImmune) > 0 then
								hurtImmune = string.sub(hurtImmune, 1, -3)
								hurtImmune = hurtImmune .. " Attack Intangible"
								fullString = fullString .. hurtImmune .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), apply_opacity(config.p1.opacity.properties, 0xFFFFFF))
						end
					end
				-- Uniqueboxes have a special field called KeyData
				elseif rect:get_field("KeyData") ~= nil then
					if config.p1.toggle.uniqueboxes_outline then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.uniquebox_outline))
					end
					if config.p1.toggle.uniqueboxes then
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.uniquebox, 0xEEFF00))
					end
				-- Any remaining rectangles are drawn as a grab box
				elseif rect:get_field("KeyData") == nil and config.p1.toggle.throwhurtboxes then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFFF0000)
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p1.opacity.throwhurtbox, 0xFF0000))
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
					if rect.TypeFlag > 0 then
						if config.p2.toggle.hitboxes_outline then 
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.hitbox_outline, 0x0040C0))
						end
						if config.p2.toggle.hitboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.hitbox, 0x0040C0))
						end
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
						if config.p2.toggle.properties then
							local fullString = ""
							if string.len(hitboxExceptions) > 10 then
								-- Remove final commma
								hitboxExceptions = string.sub(hitboxExceptions, 1, -3)
								fullString = fullString .. hitboxExceptions .. "\n"
							end
							if string.len(comboOnly) > 6 then
								fullString = fullString .. comboOnly .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), apply_opacity(config.p2.properties, 0xFFFFFF))
						end
					-- Throws almost* universally have a TypeFlag of 0 and a PoseBit > 0 
					-- Except for JP's command grab projectile which has neither and must be caught with CondFlag of 0x2C0
					elseif ((rect.TypeFlag == 0 and rect.PoseBit > 0) or rect.CondFlag == 0x2C0) then
						if config.p2.toggle.throwboxes_outline then 
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.throwbox_outline, 0xD080FF))
						end
						if config.p2.toggle.throwboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.throwbox, 0xD080FF))
						end
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
						if config.p2.toggle.properties then
							local fullString = ""
							if string.len(hitboxExceptions) > 10 then
								-- Remove final commma
								hitboxExceptions = string.sub(hitboxExceptions, 1, -3)
								fullString = fullString .. hitboxExceptions .. "\n"
							end
							if string.len(comboOnly) > 6 then
								fullString = fullString .. comboOnly .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), apply_opacity(config.p2.opacity.properties, 0xFFFFFF))
						end
					-- Projectile Clash boxes have a GuardBit of 0 (while most other boxes have either 7 or some random, non-zero, positive integer)
					elseif rect.GuardBit == 0 then
						if config.p2.toggle.clashboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.clashbox_outline, 0x3891E6))
						end
						if config.p2.toggle.clashboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.clashbox, 0x3891E6))
						end
					-- Any remaining boxes are drawn as proximity boxes
					elseif config.p2.toggle.proximityboxes or config.p2.toggle.proximityboxes_outline then
						if config.p2.toggle.proximityboxes_outline then
							draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.proximitybox_outline, 0x5b5b5b))
						end
						if config.p2.toggle.proximityboxes then
							draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.proximitybox, 0x5b5b5b))
						end
					end
				-- If the box contains the Attr field, then it is a pushbox
				elseif rect:get_field("Attr") ~= nil then
					if config.p2.toggle.pushboxes_outline then
						draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.pushbox_outline, 0x00FFFF))
					end
					if config.p2.toggle.pushboxes then
						draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.pushbox, 0x00FFFF))
					end
				-- If the rectangle has a HitNo field, the box falls under hurt boxes
				elseif rect:get_field("HitNo") ~= nil then
					if config.p2.toggle.hurtboxes or config.p2.toggle.hurtboxes_outline then
						-- Armor (Type: 1) & Parry (Type: 2) Boxes
						if rect.Type == 2 or rect.Type == 1 then
							if config.p2.toggle.hurtboxes_outline then
								draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.hurtbox_outline, 0xFF0080))
							end
							if config.p2.toggle.hurtboxes then
								draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.hurtbox, 0xFF0080))
							end
						-- All other hurtboxes
						else
							if config.p2.toggle.hurtboxes_outline then
								draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.hurtbox_outline, 0x00FF00))
							end
							if config.p2.toggle.hurtboxes then
								draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.hurtbox, 0x00FF00))
							end
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
						if config.p2.toggle.properties then
							local fullString = ""
							if string.len(hurtInvuln) > 0 then
								-- Remove final commma
								hurtInvuln = hurtInvuln .. " Invulnerable"
								fullString = fullString .. hurtInvuln .. "\n"
							end
							if string.len(hurtImmune) > 0 then
								hurtImmune = string.sub(hurtImmune, 1, -3)
								hurtImmune = hurtImmune .. " Attack Intangible"
								fullString = fullString .. hurtImmune .. "\n"
							end
							draw.text(fullString, finalPosX, (finalPosY + finalSclY), apply_opacity(config.p2.opacity.properties, 0xFFFFFF))
						end
					end
				-- Uniqueboxes have a special field called KeyData
				elseif rect:get_field("KeyData") ~= nil and config.p2.toggle.uniqueboxes then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFEEFF00)
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.uniquebox, 0xEEFF00))
				-- Any remaining rectangles are drawn as a grab box
				elseif rect:get_field("KeyData") == nil and config.p2.toggle.throwhurtboxes then
					draw.outline_rect(finalPosX, finalPosY, finalSclX, finalSclY, 0xFFFF0000)
					draw.filled_rect(finalPosX, finalPosY, finalSclX, finalSclY, apply_opacity(config.p2.opacity.throwhurtbox, 0xFF0000))
				end
			end
		end
	end
end

-- Prevent I/O spam
local function mark_for_save()
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
        mark_for_save()
    end
    return changed, new_val
end

local function saver_drag_int(label, val, speed, min, max)
	if val < 0 then
		val = 0
	elseif val > 100 then
		val = 100
	end
    
	local changed, new_val = imgui.drag_int(label, val, speed or 1.0, min or 0, max or 100)
    if changed then
        mark_for_save()
    end
    return changed, new_val
end

local function set_toggler(label, config_suffix, id_suffix)
    imgui.table_next_row()
    imgui.table_set_column_index(0)
    imgui.text(label)
    imgui.table_set_column_index(1)
    if not config.p1.toggle.hide_all then
        changed, config.p1.toggle[config_suffix] = saver_checkbox("##p1_" .. id_suffix, config.p1.toggle[config_suffix])
    end
    imgui.table_set_column_index(2)
    if not config.p2.toggle.hide_all then
        changed, config.p2.toggle[config_suffix] = saver_checkbox("##p2_" .. id_suffix, config.p2.toggle[config_suffix])
    end
end

local function set_opacifier(label, box_type, opacity_suffix)
    -- Check if either player has this box type enabled
    if config.p1.toggle[box_type] or config.p2.toggle[box_type] then
        imgui.table_next_row()
        imgui.table_set_column_index(0)
        imgui.text(label)
        imgui.table_set_column_index(1)
        -- P1 opacity slider
        if not config.p1.toggle.hide_all and config.p1.toggle[box_type] then
            changed, config.p1.opacity[opacity_suffix] = saver_drag_int("##p1_" .. opacity_suffix .. "Opacity", config.p1.opacity[opacity_suffix], 0.5, 0, 100)
        end
        imgui.table_set_column_index(2)
        -- P2 opacity slider
        if not config.p2.toggle.hide_all and config.p2.toggle[box_type] then
            changed, config.p2.opacity[opacity_suffix] = saver_drag_int("##p2_" .. opacity_suffix .. "Opacity", config.p2.opacity[opacity_suffix], 0.5, 0, 100)
        end
    end
end

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

local function reset_all(player)
    if player == nil then
        config = deep_copy(default)
    else
        config[player] = deep_copy(default[player])
    end
    mark_for_save()
    return config
end

local function reset_toggle(player)
    if player == nil then
        config.p1.toggle = deep_copy(default.p1.toggle)
        config.p2.toggle = deep_copy(default.p2.toggle)
    else
        config[player].toggle = deep_copy(default[player].toggle)
    end
    mark_for_save()
    return config
end

local function reset_opacity(player)
    if player == nil then 
        config.p1.opacity = deep_copy(default.p1.opacity)
        config.p2.opacity = deep_copy(default.p2.opacity)
    else
        config[player].opacity = deep_copy(default[player].opacity)
    end
    mark_for_save()
    return config
end

re.on_draw_ui(function()
    if imgui.tree_node("Hitbox Viewer") then
		changed, config.options.display_menu = saver_checkbox("Display Options Menu", config.options.display_menu)
		imgui.tree_pop()
	end
end)

re.on_frame(function()
	if save_pending then
		save_timer = save_timer - (1.0 / 60.0)
		if save_timer <= 0 then
			save_config()
		end
	end

    gBattle = sdk.find_type_definition("gBattle")
    if gBattle then
		local sPlayer = gBattle:get_field("Player"):get_data(nil)
		if config.options.display_menu and sPlayer.prev_no_push_bit ~= 0 then

			imgui.begin_window("Hitboxes", true, 64)
			if imgui.tree_node("Toggle") then
				if imgui.begin_table("ToggleTable", 3) then
					imgui.table_setup_column("", nil, 150)
					imgui.table_setup_column("P1", nil, 76)
					imgui.table_setup_column("P2", nil, 76)
					imgui.table_headers_row()

					imgui.table_next_row()
					imgui.table_set_column_index(0)
					imgui.text("Hide All")
					imgui.table_set_column_index(1)
					changed, config.p1.toggle.hide_all = saver_checkbox("##p1_Hide", config.p1.toggle.hide_all)
					imgui.table_set_column_index(2)
					changed, config.p2.toggle.hide_all = saver_checkbox("##p2_Hide", config.p2.toggle.hide_all)
					if not config.p1.toggle.hide_all or not config.p2.toggle.hide_all then
						set_toggler("Hitbox", "hitboxes", "Hitboxes")
						set_toggler("Hitbox Outline", "hitboxes_outline", "HitboxesOutline")
						set_toggler("Hurtbox", "hurtboxes", "Hurtboxes")
						set_toggler("Hurtbox Outline", "hurtboxes_outline", "HurtboxesOutline")
						set_toggler("Pushbox", "pushboxes", "Pushboxes")
						set_toggler("Pushbox Outline", "pushboxes_outline", "PushboxesOutline")
						set_toggler("Throwbox", "throwboxes", "Throwboxes")
						set_toggler("Throwbox Outline", "throwboxes_outline", "ThrowboxesOutline")
						set_toggler("Throw Hurtbox", "throwhurtboxes", "ThrowHurtboxes")
						set_toggler("Throw Hurtbox Outline", "throwhurtboxes_outline", "ThrowHurtboxesOutline")
						set_toggler("Proximity Box", "proximityboxes", "ProximityBoxes")
						set_toggler("Proximity Box Outline", "proximityboxes_outline", "ProximityboxesOutline")
						set_toggler("Proj. Clash Box", "clashboxes", "ProjectileClash")
						set_toggler("Proj. Clash Box Outline", "clashboxes_outline", "ProjectileClashOutline")
						set_toggler("Unique Box", "uniqueboxes", "Uniqueboxes")
						set_toggler("Unique Box Outline", "uniqueboxes_outline", "UniqueboxesOutline")
						set_toggler("Properties", "properties", "Properties")
						set_toggler("Position", "position", "Position")
					end
					imgui.end_table()
				end
				imgui.tree_pop()
			end

			if not config.p1.toggle.hide_all or not config.p2.toggle.hide_all then
				if imgui.tree_node("Opacity") then
					if not config.p1.toggle.hide_all or not config.p2.toggle.hide_all then
						if imgui.begin_table("OpacityTable", 3) then
							imgui.table_setup_column("", nil, 150)
							if not config.p1.toggle.hide_all then imgui.table_setup_column("", nil, 65)
							else imgui.table_setup_column("", nil, 65) end
							if not config.p2.toggle.hide_all then imgui.table_setup_column("", nil, 65)
							else imgui.table_setup_column("", nil, 65) end
							set_opacifier("Hitbox", "hitboxes", "hitbox")
							set_opacifier("Hitbox Outline", "hitboxes_outline", "hitbox_outline")
							set_opacifier("Hurtbox", "hurtboxes", "hurtbox")
							set_opacifier("Hurtbox Outline", "hurtboxes_outline", "hurtbox_outline")
							set_opacifier("Pushbox", "pushboxes", "pushbox")
							set_opacifier("Pushbox Outline", "pushboxes_outline", "pushbox_outline")
							set_opacifier("Throwbox", "throwboxes", "throwbox")
							set_opacifier("Throwbox Outline", "throwboxes_outline", "throwbox_outline")
							set_opacifier("Throw Hurtbox", "throwhurtboxes", "throwhurtbox")
							set_opacifier("Throw Hurtbox Outline", "throwhurtboxes_outline", "throwhurtbox_outline")
							set_opacifier("Proximity Box", "proximityboxes", "proximitybox")
							set_opacifier("Proximity Box Outline", "proximityboxes_outline", "proximitybox_outline")
							set_opacifier("Proj. Clash Box", "clashboxes", "clashbox")
							set_opacifier("Proj. Clash Box Outline", "clashboxes_outline", "clashbox_outline")
							set_opacifier("Unique Box", "uniqueboxes", "uniquebox")
							set_opacifier("Unique Box Outline", "uniqueboxes_outline", "uniquebox_outline")
							set_opacifier("Properties", "properties", "properties")
							set_opacifier("Position", "position", "position")
							imgui.end_table()
						end
					end
					imgui.tree_pop()
				end
			end
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
						if imgui.button("P1##toggle_p1") then
							reset_toggle('p1')
						end
						imgui.table_set_column_index(2)
						if imgui.button("P2##toggle_p2") then
							reset_toggle('p2')
						end
						imgui.table_set_column_index(3)
						if imgui.button("All##toggle_all") then
							reset_toggle()
						end
						imgui.table_next_row()
						imgui.table_set_column_index(0)
						imgui.text("Opacity")
						imgui.table_set_column_index(1)
						if imgui.button("P1##opacity_p1") then
							reset_opacity('p1')
						end
						imgui.table_set_column_index(2)
						if imgui.button("P2##opacity_p2") then
							reset_opacity('p2')
						end
						imgui.table_set_column_index(3)
						if imgui.button("All##opacity_all") then
							reset_opacity()
						end
						imgui.table_next_row()
						imgui.table_set_column_index(0)
						imgui.text("All")
						imgui.table_set_column_index(1)
						if imgui.button("P1##all_p1") then
							reset_all('p1')
						end
						imgui.table_set_column_index(2)
						if imgui.button("P2##all_p2") then
							reset_all('p2')
						end
						imgui.table_set_column_index(3)
						if imgui.button("All##all_all") then
							reset_all()
						end
						imgui.end_table()
					end
					imgui.tree_pop()
				end
				imgui.tree_pop()
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
						if objPos and config.p1.toggle.position then
						draw.filled_circle(objPos.x, objPos.y, 10, apply_opacity(config.p1.opacity.position, 0xFFFFFF), 10);
					end
				end
				if actParam and not obj:get_IsR0Die() and obj:get_IsTeam2P() then
					draw_p2_boxes(obj, actParam)
					local objPos = draw.world_to_screen(Vector3f.new(obj.pos.x.v / 6553600.0, obj.pos.y.v / 6553600.0, 0))
						if objPos and config.p2.toggle.position then
						draw.filled_circle(objPos.x, objPos.y, 10, apply_opacity(config.p2.opacity.position, 0xFFFFFF), 10);
					end
				end
			end
			local sPlayer = gBattle:get_field("Player"):get_data(nil)
			local cPlayer = sPlayer.mcPlayer
			for i, player in pairs(cPlayer) do
				local actParam = player.mpActParam
				if i == 0 and actParam and not config.p1.toggle.hide_all then
					draw_p1_boxes(player, actParam)
					local worldPos = draw.world_to_screen(Vector3f.new(player.pos.x.v / 6553600.0, player.pos.y.v / 6553600.0, 0))
					if worldPos and config.p1.toggle.position then
						draw.filled_circle(worldPos.x, worldPos.y, 10, apply_opacity(config.p1.opacity.position, 0xFFFFFF), 10);
					end
				end
				if i == 1 and actParam and not config.p2.toggle.hide_all then
					draw_p2_boxes(player, actParam)
					local worldPos = draw.world_to_screen(Vector3f.new(player.pos.x.v / 6553600.0, player.pos.y.v / 6553600.0, 0))
					if worldPos and config.p2.toggle.position then
						draw.filled_circle(worldPos.x, worldPos.y, 10, apply_opacity(config.p2.opacity.position, 0xFFFFFF), 10);
					end
				end
			end
        end
    end
end)