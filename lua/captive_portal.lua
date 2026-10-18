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
	if st.led_type == "ws2812" then            -- WS2812B: ws2812 module, always D4/GPIO2
		if not ws2812 then print("LED: no ws2812 module in this firmware - LED off") return end
		local c = st.led_color or { 0, 40, 0 }
		ws2812.init()
		local lit, dark = string.char(c[2], c[1], c[3]), string.char(0, 0, 0)   -- GRB order
		on, off = function() ws2812.write(lit) end, function() ws2812.write(dark) end
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
