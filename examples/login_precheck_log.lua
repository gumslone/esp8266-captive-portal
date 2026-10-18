-- login_precheck_log.lua : example hook that LOGS each guest login attempt.
-- Upload it to the device as login_precheck.lua to enable it.
--
-- Appends one line per attempt to login_log.txt:
--     uptime=123s ip=192.168.1.3 user="guest"
-- (the hook only gets _login.ip and _login.user - never the password).
-- The log stops growing at ~4 KB so it can't fill the flash; view it in the
-- admin file list, delete it there to start over. Nothing is blocked.

local MAX_BYTES = 4096

local fd = file.open("login_log.txt", "a+")
if fd then
	if fd:seek("end") < MAX_BYTES then
		fd:write(string.format("uptime=%ds ip=%s user=%q\n",
			tmr.time(), _login.ip or "?", string.sub(_login.user or "", 1, 32)))
	end
	fd:close()
end
