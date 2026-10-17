-- reset_button.lua : OPTIONAL. If present, init.lua runs this ~2 s after boot.
-- Press RST, release it, then within 2 s hold FLASH (GPIO0 / NodeMCU D3) to
-- clear admin-saved settings (portal_config.lua) and fall back to config.lua.
-- (Holding FLASH *during* reset would boot the serial bootloader instead.)
local PIN = 3  -- D3 = GPIO0 (the FLASH button on most NodeMCU/ESP boards)
gpio.mode(PIN, gpio.INPUT, gpio.PULLUP)
if gpio.read(PIN) == 0 then
	print("[reset] FLASH button held - clearing saved portal_config.lua")
	if file.exists("portal_config.lua") then file.remove("portal_config.lua") end
end
