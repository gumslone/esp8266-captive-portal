-- captive_portal.lua : entry point. Brings up the AP, then starts the DNS
-- redirector and the HTTP server. See README.md for the full picture.
--
-- For YOUR OWN hotspot. Login mode compares entered credentials against the
-- values you set (stores nothing, imitates nothing); open mode shows the
-- captive page immediately. The ESP8266 is an AP, not a NAT router, so this
-- gates access to THIS device's pages - it does not forward internet.
local U = require("cp_util")
local st = U.load_settings()
local IP = "192.168.1.1"

print("Captive portal: AP '" .. st.ssid .. "'  login=" .. tostring(st.require_login))
-- STATIONAP with an idle station (never connects): only so the admin page can
-- scan for nearby networks - switching modes at runtime crashed the board.
-- save=false: don't rewrite the wifi config in flash on every boot.
wifi.setmode(wifi.STATIONAP, false)
pcall(wifi.sta.autoconnect, 0)
wifi.nullmodesleep(false)
wifi.setphymode(wifi.PHYMODE_N)
if wifi.setmaxtxpower then wifi.setmaxtxpower(st.txpower) end   -- signal strength / range

local cfg = { ssid = st.ssid, save = false }
if st.ap_password ~= nil and string.len(st.ap_password) >= 8 then
	cfg.pwd  = st.ap_password
	cfg.auth = wifi.WPA2_PSK
end
wifi.ap.config(cfg)
wifi.ap.setip({ ip = IP, netmask = "255.255.255.0", gateway = IP })

-- status LED: short blink when a phone joins and on guest login (see config.lua)
local function led_setup()
	local on, off
	if st.led_type == "ws2812" then            -- WS2812B / SK6812
		if not ws2812 then print("LED: no ws2812 module in this firmware - LED off") return end
		local c = st.led_color or { 0, 40, 0 }
		local lit, dark = string.char(c[2], c[1], c[3]), string.char(0, 0, 0)   -- GRB order
		local dpin = st.led                    -- data pin (NodeMCU index)
		local pwr = st.led_power               -- optional pin that powers the LED
		if pwr then gpio.mode(pwr, gpio.OUTPUT); gpio.write(pwr, gpio.HIGH) end  -- keep powered
		if ws2812.write_pin then               -- patched firmware: data on any pin.
			-- a single bit-banged frame can glitch while WiFi runs (interrupts
			-- stretch the pulses), which most hurts the all-zero "off" frame -
			-- send "off" a few times so a clean frame lands.
			on  = function() ws2812.write_pin(dpin, lit) end
			off = function() for _ = 1, 3 do ws2812.write_pin(dpin, dark) end end
		else                                   -- stock module: UART, data fixed to D4/GPIO2
			if dpin ~= 4 then print("LED: this firmware drives ws2812 on D4/GPIO2 only") end
			ws2812.init()
			on, off = function() ws2812.write(lit) end, function() ws2812.write(dark) end
		end
	elseif st.led then                         -- plain LED on a GPIO pin
		local pin = st.led
		if pin == 10 then print("LED on TX/GPIO1: serial console output stops now") end
		local lit, dark = st.led_low and gpio.LOW or gpio.HIGH, st.led_low and gpio.HIGH or gpio.LOW
		gpio.mode(pin, gpio.OUTPUT)
		on, off = function() gpio.write(pin, lit) end, function() gpio.write(pin, dark) end
	else
		return
	end
	off()
	function portal_blink()
		on(); tmr.create():alarm(80, tmr.ALARM_SINGLE, off)
	end
	if wifi.eventmon then wifi.eventmon.register(wifi.eventmon.AP_STACONNECTED, portal_blink) end
end
led_setup()

require("cp_dns").start(IP)
require("cp_http").start(st, IP)

print("Portal ready: http://" .. IP .. "/   admin: http://" .. IP .. "/admin")
