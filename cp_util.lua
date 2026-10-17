-- cp_util.lua : small helpers + settings persistence.
-- unescape is the project's (setup_functions.lua); the rest are new.
local U = {}

function U.unescape(s)
	if s == nil then return "" end
	s = string.gsub(s, "+", " ")
	s = string.gsub(s, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
	return s
end

function U.he(s)
	s = string.gsub(s or "", "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	s = string.gsub(s, '"', "&quot;")
	return s
end

function U.lua_q(s)
	s = string.gsub(s or "", "\\", "\\\\")
	s = string.gsub(s, '"', '\\"')
	s = string.gsub(s, "[\r\n]", "")
	return '"' .. s .. '"'
end

function U.safe_name(s)        -- flat filesystem: no path separators
	local r = string.gsub(s or "", "[/\\]", "")   -- one value (minifier-safe)
	return r
end

function U.read_file(name)
	if not file.exists(name) then return "" end
	local fd = file.open(name, "r"); if not fd then return "" end
	local out, chunk = "", nil
	repeat chunk = fd:read(512); if chunk then out = out .. chunk end until not chunk
	fd:close()
	return out
end

-- settings precedence: built-in defaults <- config.portal_* <- portal_config.lua
function U.load_settings()
	local s = {
		ssid = "Guest-WiFi", ap_password = nil, user = "guest",
		password = "changeme", admin_password = "admin-changeme", require_login = true,
		page = "portal_page.html",   -- active captive page (admin picks it)
		login = "login.html",        -- active guest login form (admin picks it)
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
			if portal.require_login ~= nil then s.require_login = portal.require_login end
			portal = nil
		end
	end
	return s
end

function U.save_settings(s)
	local fd = file.open("portal_config.lua", "w+")
	if not fd then return false end
	fd:write("portal = {}\n")
	fd:write("portal.ssid = " .. U.lua_q(s.ssid) .. "\n")
	fd:write("portal.user = " .. U.lua_q(s.user) .. "\n")
	fd:write("portal.password = " .. U.lua_q(s.password) .. "\n")
	fd:write("portal.page = " .. U.lua_q(s.page or "portal_page.html") .. "\n")
	fd:write("portal.login = " .. U.lua_q(s.login or "login.html") .. "\n")
	fd:write("portal.require_login = " .. (s.require_login and "true" or "false") .. "\n")
	if s.ap_password ~= nil and string.len(s.ap_password) >= 8 then
		fd:write("portal.ap_password = " .. U.lua_q(s.ap_password) .. "\n")
	else
		fd:write("portal.ap_password = nil\n")
	end
	fd:close()
	return true
end

return U
