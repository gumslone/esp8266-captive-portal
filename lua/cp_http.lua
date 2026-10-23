-- cp_http.lua : the HTTP server (guest side). ESP-01 / low-heap friendly:
--   * pages are files on flash; only tiny {{TOKENS}} are substituted, and the
--     substituted pages are small - no multi-KB strings built in RAM;
--   * big assets (admin.js, style.css) and sound.mp3 stream in 1 KB chunks
--     (admin.js / style.css as pre-gzipped .gz when present);
--   * admin routes live in small adm_*.lua modules (picked by adm_route),
--     guest login in cp_login, shared guest pages in api_*.lua, phones'
--     connectivity checks in cp_probe; only the one a request needs is
--     loaded, and dropped afterwards (on an ESP-01 one big admin module did
--     not compile, and loading it left too little heap to serve);
--   * one set of handlers serves every connection (state in a weak table), and
--     a request that arrives when heap is low gets a quick "503 busy" instead
--     of loading code into the last few KB.
-- Request parsing / _GET reuse the reference (setup.lua, fileserver.lua).
local U = require("cp_util")
local H = {}

-- load a per-request module, run it, drop it again (stays out of RAM)
local function run(m, S, x)
	local f = require(m)
	package.loaded[m] = nil
	return f(S, x)
end

-- /api/<x> for the shared guest pages -> module that handles it
local API_MOD = { gb = "api_gb", px = "api_px", mp = "api_mp", bz = "api_bz", ch = "api_ch", led = "api_dev", n = "api_dev" }
local LOW_HEAP = 5120      -- free heap (after a GC) below which requests get "503 busy"

function H.start(st, IP)
	local allowed = {}       -- allowed[ip]  = true : guest passed the gate

	-- files a non-admin may fetch directly; everything else (config.lua,
	-- *.lua, portal_config.lua ...) is NOT served to guests.
	-- (no captive pages here: they are served through the login gate only)
	local PUBLIC = { ["style.css"] = true, ["admin.js"] = true,
		["sound.mp3"] = true, ["favicon.ico"] = true }

	local function ctype(name)
		if string.find(name, "%.css")  then return "text/css"
		elseif string.find(name, "%.js")   then return "text/javascript"
		elseif string.find(name, "%.mp3")  then return "audio/mpeg"
		elseif string.find(name, "%.png")  then return "image/png"
		elseif string.find(name, "%.ico")  then return "image/x-icon"
		elseif string.find(name, "%.html") then return "text/html; charset=utf-8"
		else return "text/plain" end
	end

	local CHUNK     = 1024 -- bytes per streamed file piece (bigger chunks for .mp3
	                       -- made audio stop loading partway: too much heap)
	local TPL_PIECE = 700  -- template piece: every send needs one contiguous network
	                       -- buffer of about its size. 1400 (~one TCP segment) failed
	                       -- with "E:M 1584" on a fragmented heap - a 2 KB page blank

	-- shared with the adm_*.lua modules
	-- admin_ok[ip]: admin signed in; allowed[ip]: guest passed the gate
	local S = { st = st, U = U, admin_ok = {}, allowed = allowed }
	local HTML = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8" ..
		"\r\nCache-Control: no-store, no-cache, must-revalidate\r\nConnection: close\r\n\r\n"

	function S.send_html(k, body) k:send(HTML .. body) end
	function S.txt(k, body)                       -- plain-text reply (api_*.lua)
		k:send("HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8" ..
			"\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" .. body)
	end

	-- send an HTML template, STREAMED: the "sent" handler reads ~1.4 KB of
	-- whole lines at a time and substitutes {{TOKENS}} in just that piece, so a
	-- page never sits in RAM whole (an ESP-01 rebooted rendering admin.html).
	-- Table replacement inserts values literally and keeps unknown tokens.
	function S.send_page(k, cs, name, subs)
		k:send(HTML)
		cs.stream, cs.pos, cs.subs = name, 0, subs or {}
	end

	-- send a file as-is, streamed in CHUNK pieces by the "sent" handler. A
	-- pre-gzipped x.gz (made by tools/upload.py) is preferred over x: fewer
	-- bytes and round trips; the browser unpacks it. Returns false if missing.
	function S.send_file(k, cs, fname)
		local gz = file.exists(fname .. ".gz")
		if not gz and not file.exists(fname) then return false end
		-- admin.js, style, media and the (gzipped, not editable) game pages are
		-- cached so phones don't re-stream them; anything the admin may edit
		-- (html, lua, ...) is always fetched fresh
		local cc = (fname == "admin.js" or string.find(fname, "%.css$") or string.find(fname, "%.mp3$") or
			string.find(fname, "%.ico$") or string.find(fname, "%.png$") or
			(gz and string.find(fname, "^game_"))) and "max-age=3600" or "no-store"
		k:send("HTTP/1.1 200 OK\r\nContent-Type: " .. ctype(fname) ..
			(gz and "\r\nContent-Encoding: gzip" or "") ..
			"\r\nCache-Control: " .. cc .. "\r\nConnection: close\r\n\r\n")
		cs.stream = gz and (fname .. ".gz") or fname; cs.pos = 0; cs.subs = nil
		return true
	end

	-- the captive page shown to a client: the one the admin made active. A
	-- pre-gzipped portal_x.html.gz is sent as-is (smaller, faster; no tokens)
	function S.client_page(k, cs)
		local pg = st.page
		if not (file.exists(pg) or file.exists(pg .. ".gz")) then pg = "portal_page.html" end
		if file.exists(pg .. ".gz") then S.send_file(k, cs, pg)
		else S.send_page(k, cs, pg, { SSID = U.he(st.ssid) }) end
	end
	function S.login_form(k, cs, err)
		local lg = file.exists(st.login) and st.login or "login.html"
		S.send_page(k, cs, lg, { SSID = U.he(st.ssid), ERR = err or "" })
	end

	-- per-connection state, keyed by socket: stream = file being sent, pos =
	-- offset, exec = keep socket open (execute/scan), up = binary upload in
	-- progress, pend = form POST headers waiting for their body packet.
	-- Weak keys: an entry goes with its socket - also when we close it
	-- ourselves, which on 2.2.1 calls no "disconnection" handler. (cs must
	-- never hold its socket, or the entry could not be collected.)
	local CS = setmetatable({}, { __mode = "k" })

	local function on_receive(k, rq)
		local cs = CS[k]
		if not cs then cs = { pos = 0 }; CS[k] = cs end
		-- mid binary upload: stream bytes straight to flash --------------
		local up = cs.up
		if up then
			up.fd:write(rq)
			up.left = up.left - #rq
			if up.left <= 0 then
				up.fd:close(); cs.up = nil
				k:send("HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n")
			end
			return
		end

		-- low on memory: a quick "busy" beats loading code into the last
		-- few KB (a failed allocation reboots the board). Pages retry.
		if node.heap() < LOW_HEAP then
			collectgarbage()
			if node.heap() < LOW_HEAP then
				k:send("HTTP/1.1 503 Service Unavailable\r\nRetry-After: 2\r\nConnection: close\r\n\r\n")
				return
			end
		end

		if cs.pend then rq = cs.pend .. rq; cs.pend = nil end
		local _, _, method, path, vars = string.find(rq, "([A-Z]+) (/[^?]*)%??(.*) HTTP")
		if method == nil then _, _, method, path = string.find(rq, "([A-Z]+) (.+) HTTP") end
		path = path or "/"

		-- small form POST (login forms): fields come from the body. Browsers
		-- may send the body in a 2nd packet, so wait for it (bounded size).
		local body = nil
		if method == "POST" and path ~= "/admin/upload" then
			body = string.match(rq, "\r\n\r\n(.*)$") or ""
			local clen = tonumber(string.match(rq, "[Cc]ontent%-[Ll]ength:%s*(%d+)") or "0")
			if #body < clen and #rq < 2048 then cs.pend = rq; return end
		end

		local G = {}
		for _, q in ipairs({ vars or "", body or "" }) do
			for gk, gv in string.gmatch(q, "([%w_%-]+)=([^%&]*)") do G[gk] = U.unescape(gv) end
		end
		local act = G.action
		local _, ip = k:getpeer()
		local isadmin = ip and S.admin_ok[ip]

		local x = { k = k, rq = rq, method = method, path = path, act = act,
			G = G, ip = ip, isadmin = isadmin, cs = cs }
		-- admin: /admin, /admin/upload, and every action= except the guest
		-- login. adm_route checks the sign-in and loads the one adm_*.lua
		if path == "/admin" or path == "/admin/upload" or (act and act ~= "login") then
			if run("adm_route", S, x) then return end
		end

		-- guest login: cp_login.lua, loaded for this request only ----------
		if act == "login" then
			run("cp_login", S, x)
			return
		end

		-- shared guest pages (guestbook, pixel wall, 2-player, buzzer, LED):
		-- same gate as the games; only that feature's api_*.lua is loaded,
		-- for this request only
		local what = string.match(path, "^/api/(%w+)$")
		if what then
			local amod = API_MOD[what]
			if not amod or (st.require_login and not (ip and allowed[ip]) and not isadmin) then
				k:send("HTTP/1.1 " .. (amod and "403 Forbidden" or "404 Not Found") .. "\r\nConnection: close\r\n\r\n")
				return
			end
			x.what = what
			run(amod, S, x)
			return
		end

		-- explicit file (assets). Guests: whitelist only. Admin: any file -
		local fname = path ~= "/" and U.safe_name(string.gsub(path, "^/", "")) or ""
		-- any .mp3 is public too, so captive pages can play their own sounds;
		-- game_*.html for guests who are through the gate (or in open mode)
		local game = string.find(fname, "^game_.*%.html$") and ((not st.require_login) or (ip and allowed[ip]))
		if fname ~= "" and method == "GET" and (isadmin or PUBLIC[fname] or string.find(fname, "%.mp3$") or game)
			and S.send_file(k, cs, fname) then
			return
		end

		-- missing favicon: cheap 204 instead of a full page per probe -----
		if path == "/favicon.ico" then
			k:send("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
			return
		end

		-- logged-in guest: cp_probe answers the OS connectivity checks with
		-- "online", so the phone closes its sign-in sheet (before login they
		-- get the portal/login page, which is what makes the sheet appear)
		if st.require_login and ip and allowed[ip] and run("cp_probe", S, x) then return end

		-- "/" and anything else (incl. OS captive-probe URLs) --------------
		if (not st.require_login) or (ip and allowed[ip]) then S.client_page(k, cs)
		else S.login_form(k, cs, "") end
	end

	local function on_sent(k)
		local cs = CS[k] or {}
		if cs.exec then return end                   -- execute/scan close it themselves
		if cs.stream then
			local fd = file.open(cs.stream, "r")
			if fd then
				fd:seek("set", cs.pos)
				local chunk, more
				if cs.subs then                        -- template: whole lines + tokens
					local t, n, l = {}, 0, nil
					repeat
						l = fd:readline()
						if l then t[#t + 1] = l; n = n + #l end
					until not l or n >= TPL_PIECE
					more = l ~= nil
					cs.pos = fd:seek("cur")
					if n > 0 then chunk = string.gsub(table.concat(t), "{{([%w_]+)}}", cs.subs) end
				else                                   -- plain/binary asset
					chunk = fd:read(CHUNK)
					more = chunk ~= nil and #chunk == CHUNK
					if chunk then cs.pos = cs.pos + #chunk end
				end
				fd:close()
				if chunk then
					k:send(chunk)
					if more then return end
				end
			end
			cs.stream, cs.subs = nil, nil
		end
		CS[k] = nil
		k:close()
	end

	-- handlers run under pcall: on NodeMCU 3.x a failed send raises an error,
	-- and an error escaping a callback reboots the whole board. Now it only
	-- ends this one connection.
	local function guard(f, k, a)
		local ok, err = pcall(f, k, a)
		if not ok then print("http: " .. tostring(err)); pcall(k.close, k) end
	end
	local function recv(k, rq) guard(on_receive, k, rq) end
	local function sent(k) guard(on_sent, k) end
	local function gone(k)
		local cs = CS[k]
		if cs and cs.up then pcall(function() cs.up.fd:close() end) end
		CS[k] = nil
		-- (no node.output(nil) here: adm_exec restores output itself; resetting
		-- it from other connections cut off a running command's output)
		collectgarbage("collect")
	end

	-- every connection shares these handlers: no new closures per request
	local srv = net.createServer(net.TCP)
	srv:listen(80, function(c)
		CS[c] = { pos = 0 }
		c:on("receive", recv)
		c:on("sent", sent)
		c:on("disconnection", gone)
	end)

	print("HTTP server on :80")
end

return H
