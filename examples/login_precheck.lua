-- login_precheck.lua : OPTIONAL hook, run before every guest login check.
-- Upload it to the device under this name to enable it (delete it to disable).
--
-- It can read:   _login.ip    client IP, e.g. "192.168.1.3"
--                _login.user  the username that was entered
-- It may set:    _login.block = true      refuse this attempt
--                _login.msg   = "..."     message shown on the login form
-- It runs fresh on each attempt, so anything it must remember between
-- attempts has to live in a global table (here: precheck_state).

-- 1. usernames that are never allowed
local BLOCKED_USERS = { admin = true, root = true }
if BLOCKED_USERS[_login.user] then
	_login.block = true
	_login.msg = "This username is not allowed."
	return
end

-- 2. at most 5 attempts per IP per 60 seconds
local MAX, WINDOW = 5, 60
precheck_state = precheck_state or {}
local now = tmr.time()
local s = precheck_state[_login.ip]
if not s or now - s.since > WINDOW then
	s = { since = now, n = 0 }               -- start a new window for this IP
	precheck_state[_login.ip] = s
end
s.n = s.n + 1
if s.n > MAX then
	_login.block = true
	_login.msg = "Too many attempts - wait a minute and try again."
end
