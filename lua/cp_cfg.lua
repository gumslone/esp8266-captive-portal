-- cp_cfg.lua : settings load/save (portal_config.lua). Only needed at boot
-- (captive_portal) and when the admin saves (adm_set), so it is loaded for
-- that and dropped - not kept in RAM next to the HTTP server.
local C = {}

function C.lua_q(s)
	s = string.gsub(s or "", "\\", "\\\\")
	s = string.gsub(s, '"', '\\"')
	s = string.gsub(s, "[\r\n]", "")
	return '"' .. s .. '"'
end

-- settings precedence: built-in defaults <- config.portal_* <- portal_config.lua
function C.load()
	local s = {
		ssid = "Guest-WiFi", ap_password = nil, user = "guest",
		password = "changeme", admin_password = "admin-changeme", require_login = false,
		page = "portal_games.html",  -- active captive page (admin picks it)
		login = "login.html",        -- active guest login form (admin picks it)
		welcome = false,             -- open mode: "welcome.html" = first page in the sign-in sheet (admin switches it)
		txpower = 82,                -- radio power 1..82 in 0.25 dBm (82 = max range)
		led = 4,                     -- status LED pin (D4/GPIO2), false = off
	}
	if config then
		s.ssid           = config.portal_ssid           or s.ssid
		s.ap_password    = config.portal_ap_password
		s.user           = config.portal_user           or s.user
		s.password       = config.portal_password       or s.password
		s.admin_password = config.portal_admin_password or s.admin_password
		if config.portal_require_login ~= nil then s.require_login = config.portal_require_login end
		s.page           = config.portal_page           or s.page
		s.login          = config.portal_login          or s.login
		s.txpower        = config.portal_txpower        or s.txpower
		if config.portal_led ~= nil then s.led = config.portal_led end
		s.led_type  = config.portal_led_type or "gpio"
		s.led_low   = config.portal_led_active_low ~= false
		s.led_color = config.portal_led_color
		s.led_power = config.portal_led_power
		if config.portal_welcome ~= nil then s.welcome = config.portal_welcome end
		config = nil                                  -- only read here: free it
	end
	if file.exists("portal_config.lua") then
		pcall(function() dofile("portal_config.lua") end)
		if portal then
			s.ssid        = portal.ssid     or s.ssid
			s.user        = portal.user     or s.user
			s.password    = portal.password or s.password
			s.ap_password = portal.ap_password
			s.page        = portal.page     or s.page
			s.login       = portal.login    or s.login
			s.txpower     = portal.txpower  or s.txpower
			s.admin_password = portal.admin_password or s.admin_password   -- set in admin
			if portal.require_login ~= nil then s.require_login = portal.require_login end
			if portal.welcome ~= nil then s.welcome = portal.welcome end
			portal = nil
		end
	end
	return s
end

function C.save(s)
	local fd = file.open("portal_config.lua", "w+")
	if not fd then return false end
	fd:write("portal = {}\n")
	fd:write("portal.ssid = " .. C.lua_q(s.ssid) .. "\n")
	fd:write("portal.user = " .. C.lua_q(s.user) .. "\n")
	fd:write("portal.password = " .. C.lua_q(s.password) .. "\n")
	fd:write("portal.page = " .. C.lua_q(s.page or "portal_page.html") .. "\n")
	fd:write("portal.login = " .. C.lua_q(s.login or "login.html") .. "\n")
	fd:write("portal.txpower = " .. (tonumber(s.txpower) or 82) .. "\n")
	fd:write("portal.admin_password = " .. C.lua_q(s.admin_password) .. "\n")
	fd:write("portal.require_login = " .. (s.require_login and "true" or "false") .. "\n")
	fd:write("portal.welcome = " .. (s.welcome and C.lua_q(s.welcome) or "false") .. "\n")
	if s.ap_password ~= nil and string.len(s.ap_password) >= 8 then
		fd:write("portal.ap_password = " .. C.lua_q(s.ap_password) .. "\n")
	else
		fd:write("portal.ap_password = nil\n")
	end
	fd:close()
	return true
end

return C
