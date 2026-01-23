local sdk = sdk
local pause_manager
local pause_type_bit

local function is_paused()
	if not pause_manager then
		pause_manager = sdk.get_managed_singleton("app.PauseManager")
	end
	
	pause_type_bit = pause_manager:get_field("_CurrentPauseTypeBit")
	if pause_type_bit == 64 or pause_type_bit == 2112 then
		return false
	end
	return true
end

return is_paused