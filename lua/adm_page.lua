-- adm_page.lua : admin sign-in, the dashboard and its settings. One of the
-- small adm_*.lua modules cp_http loads for a single admin request.
-- admin.html is static (served gzipped); admin.js fills it from action=settings.
local function enc(v)                              -- urlencode for the settings reply
	local r = string.gsub(tostring(v or ""), "[^%w%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c)) end)
	return r                                       -- one value (minifier-safe)
end

return function(S, x)
	local k, st = x.k, S.st
	if x.act == "admin_login" then
		if (x.G.ap or "") == st.admin_password then
			if x.ip then S.admin_ok[x.ip] = true end
			-- redirect, so a page refresh doesn't re-send the password
			k:send("HTTP/1.1 303 See Other\r\nLocation: /admin\r\nConnection: close\r\n\r\n")
		else
			S.send_page(k, x.cs, "admin_login.html", { ERR = "Wrong admin password." })
		end
	elseif not x.isadmin then
		if x.act == "settings" then k:send("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n")
		else S.send_page(k, x.cs, "admin_login.html", { ERR = "" }) end
	elseif x.act == "settings" then
		k:send("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" ..
			"ssid=" .. enc(st.ssid) .. "\nwpa=" .. enc(st.ap_password) .. "\nuser=" .. enc(st.user) ..
			"\npass=" .. enc(st.password) .. "\nrl=" .. (st.require_login and "1" or "0") ..
			"\nwl=" .. (st.welcome and "1" or "0") ..
			"\npage=" .. enc(st.page) .. "\nlogin=" .. enc(st.login) .. "\ntx=" .. (st.txpower or 82) .. "\n")
	else
		S.send_file(k, x.cs, "admin.html")
	end
end
