-- adm_set.lua : save settings (then restart), choose the active captive page
-- or login form (set_page, kind=login). Loaded per request by cp_http.
return function(S, x)
	local st, U, k, G = S.st, S.U, x.k, x.G
	if x.act == "set_page" then
		local name = U.safe_name(G.name or "")
		if string.find(name, "%.html$") and (file.exists(name) or file.exists(name .. ".gz")) then
			if G.kind == "login" then st.login = name else st.page = name end
			U.save_settings(st)
			k:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
		else
			k:send("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
		end
		return
	end
	-- save_settings
	local s2 = {
		ssid = G.s or st.ssid,
		ap_password = (G.w and #G.w > 0) and G.w or nil,
		user = G.u or st.user,
		password = G.p or st.password,
		admin_password = st.admin_password,
		require_login = (G.rl == "1"),
		page = st.page, login = st.login,
	}
	local msg
	if s2.ssid == "" or (s2.require_login and s2.password == "") then
		msg = "Name (and guest password when login is required) cannot be empty."
	elseif s2.ap_password and #s2.ap_password < 8 then   -- would silently become an open AP
		msg = "WPA2 key must be at least 8 characters (leave it blank for an open network)."
	elseif U.save_settings(s2) then
		msg = "Saved. Restarting&hellip;"
		tmr.create():alarm(1500, tmr.ALARM_SINGLE, function() node.restart() end)
	else
		msg = "Could not write portal_config.lua."
	end
	S.send_html(k, "<!DOCTYPE html><meta charset=\"utf-8\"><body style=\"font-family:system-ui;padding:24px\">" ..
		msg .. " <a href=\"/admin\">Back</a></body>")
end
