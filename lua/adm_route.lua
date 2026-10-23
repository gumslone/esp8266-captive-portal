-- adm_route.lua : picks the admin module for a request (cp_http hands over
-- /admin, /admin/upload and every action= except the guest login), checks the
-- sign-in, then loads just that adm_*.lua. Returns false when the request is
-- not an admin one after all, so cp_http carries on with it.
local ADMIN_MOD = { admin_login = "adm_page", save_settings = "adm_set", set_page = "adm_set",
	page_append = "adm_file", execute = "adm_exec", scan = "adm_scan", settings = "adm_page",
	files = "adm_ls" }

return function(S, x)
	local k = x.k
	local mod = ADMIN_MOD[x.act] or (x.path == "/admin/upload" and x.method == "POST" and "adm_file")
		or (x.path == "/admin" and "adm_page")
	if not mod then return false end
	if mod ~= "adm_page" and not x.isadmin then          -- sign-in/dashboard are open
		if x.act == "save_settings" then S.send_page(k, x.cs, "admin_login.html", { ERR = "" })
		else k:send("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n") end
		return true
	end
	local handler = require(mod)
	package.loaded[mod] = nil
	handler(S, x)
	return true
end
