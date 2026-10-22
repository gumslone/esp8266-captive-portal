-- cp_login.lua : guest login (login form posts action=login). Loaded by
-- cp_http for that one request and dropped, so it costs no RAM between logins.
-- Optional hook: login_precheck.lua sees _login.ip / _login.user / _login.get
-- and may refuse the attempt with _login.block = true (+ _login.msg).
-- A failed login adds a debug line of WHY it failed to login_fail.txt (never
-- the password; admin-only file, capped at ~2 KB).
return function(S, x)
	local st, k, cs, ip, G = S.st, x.k, x.cs, x.ip, x.G
	local u, p = G.u or "", G.p or ""
	if file.exists("login_precheck.lua") then
		_login = { ip = ip, user = u, get = G }
		local ok, err = pcall(dofile, "login_precheck.lua")
		local hook = _login
		_login = nil
		if not ok then print("login_precheck: " .. tostring(err))
		elseif hook.block then
			S.login_form(k, cs, hook.msg or "Login not allowed right now.")
			return
		end
	end
	if u == st.user and p == st.password then
		if ip then S.allowed[ip] = true end
		if portal_blink then portal_blink() end
		S.client_page(k, cs)
		return
	end
	local fd = file.open("login_fail.txt", "a+")
	if fd then
		if fd:seek("end") < 2048 then
			local ua = string.sub(string.match(x.rq, "[Uu]ser%-[Aa]gent:%s*([^\r\n]*)") or "?", 1, 80)
			fd:write(string.format("uptime=%ds ip=%s user=%q user_ok=%s pass_ok=%s pass_len=%d ua=%q\n",
				tmr.time and tmr.time() or 0, ip or "?", u == st.user and u or "(other)",
				tostring(u == st.user), tostring(p == st.password), #p, ua))
		end
		fd:close()
	end
	S.login_form(k, cs, "Wrong username or password.")
end
