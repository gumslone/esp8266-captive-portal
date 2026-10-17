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

local cfg = { ssid = st.ssid, save = false }
if st.ap_password ~= nil and string.len(st.ap_password) >= 8 then
	cfg.pwd  = st.ap_password
	cfg.auth = wifi.WPA2_PSK
end
wifi.ap.config(cfg)
wifi.ap.setip({ ip = IP, netmask = "255.255.255.0", gateway = IP })

require("cp_dns").start(IP)
require("cp_http").start(st, IP)

print("Portal ready: http://" .. IP .. "/   admin: http://" .. IP .. "/admin")
