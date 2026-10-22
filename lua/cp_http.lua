-- cp_http.lua : the HTTP server (guest side). ESP-01 / low-heap friendly:
--   * pages are files on flash; only tiny {{TOKENS}} are substituted, and the
--     substituted pages are small - no multi-KB strings built in RAM;
--   * big assets (admin.js, style.css) and sound.mp3 stream in 1 KB chunks
--     (admin.js / style.css as pre-gzipped .gz when present);
--   * admin routes live in small adm_*.lua modules; only the one a request
--     needs is loaded, and dropped afterwards (on an ESP-01 one big admin
--     module did not compile, and loading it left too little heap to serve).
-- Request parsing / _GET reuse the reference (setup.lua, fileserver.lua).
local U = require("cp_util")
local H = {}

-- OS connectivity-check URLs -> the reply that means "internet works"
local APPLE = "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"
local PROBE = { ["/hotspot-detect.html"] = APPLE, ["/library/test/success.html"] = APPLE,
	["/generate_204"] = 204, ["/gen_204"] = 204,                        -- Android / Chrome
	["/connecttest.txt"] = "Microsoft Connect Test", ["/ncsi.txt"] = "Microsoft NCSI",
	["/success.txt"] = "success\n" }                                    -- Firefox

-- admin action -> module that handles it
local ADMIN_MOD = { admin_login = "adm_page", save_settings = "adm_set", set_page = "adm_set",
	page_append = "adm_file", execute = "adm_exec", scan = "adm_scan", settings = "adm_page" }

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
	local TPL_PIECE = 1400 -- template piece (~one TCP segment): most pages in 1-2 sends

	-- shared with the adm_*.lua modules
	local S = { st = st, U = U, admin_ok = {} }   -- admin_ok[ip]: admin signed in
	local HTML = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8" ..
		"\r\nCache-Control: no-store, no-cache, must-revalidate\r\nConnection: close\r\n\r\n"

	function S.send_html(k, body) k:send(HTML .. body) end

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
		-- admin.js, style and media are cached so pages don't re-stream them;
		-- anything the admin may edit (html, lua, ...) is always fetched fresh
		local cc = (fname == "admin.js" or string.find(fname, "%.css$") or string.find(fname, "%.mp3$") or
			string.find(fname, "%.ico$") or string.find(fname, "%.png$")) and "max-age=3600" or "no-store"
		k:send("HTTP/1.1 200 OK\r\nContent-Type: " .. ctype(fname) ..
			(gz and "\r\nContent-Encoding: gzip" or "") ..
			"\r\nCache-Control: " .. cc .. "\r\nConnection: close\r\n\r\n")
		cs.stream = gz and (fname .. ".gz") or fname; cs.pos = 0; cs.subs = nil
		return true
	end

	-- the captive page shown to a client: the one the admin made active. A
	-- pre-gzipped portal_x.html.gz is sent as-is (smaller, faster; no tokens)
	local function client_page(k, cs)
		local pg = st.page
		if not (file.exists(pg) or file.exists(pg .. ".gz")) then pg = "portal_page.html" end
		if file.exists(pg .. ".gz") then S.send_file(k, cs, pg)
		else S.send_page(k, cs, pg, { SSID = U.he(st.ssid) }) end
	end
	local function login_form(k, cs, err)
		local lg = file.exists(st.login) and st.login or "login.html"
		S.send_page(k, cs, lg, { SSID = U.he(st.ssid), ERR = err or "" })
	end

	-- failed guest login: debug line of WHY it failed; never the password.
	-- Admin-only file (not in PUBLIC), capped at ~2 KB.
	local function log_fail(rq, ip, u, p)
		local fd = file.open("login_fail.txt", "a+")
		if not fd then return end
		if fd:seek("end") < 2048 then
			local ua = string.sub(string.match(rq, "[Uu]ser%-[Aa]gent:%s*([^\r\n]*)") or "?", 1, 80)
			fd:write(string.format("uptime=%ds ip=%s user=%q user_ok=%s pass_ok=%s pass_len=%d ua=%q\n",
				tmr.time and tmr.time() or 0, ip or "?", u == st.user and u or "(other)",
				tostring(u == st.user), tostring(p == st.password), #p, ua))
		end
		fd:close()
	end


	local srv = net.createServer(net.TCP)
	srv:listen(80, function(c)
		-- per-connection state: stream = file being sent, pos = offset,
		-- exec = keep socket open (execute/scan), up = binary upload in progress,
		-- pend = form POST headers waiting for their body packet
		local cs = { pos = 0 }

		local function on_receive(k, rq)
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

			-- admin routes: load just the module this request needs --------
			local mod = ADMIN_MOD[act] or (path == "/admin/upload" and method == "POST" and "adm_file")
				or (path == "/admin" and "adm_page")
			if mod then
				if mod ~= "adm_page" and not isadmin then    -- sign-in/dashboard are open
					if act == "save_settings" then S.send_page(k, cs, "admin_login.html", { ERR = "" })
					else k:send("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n") end
					return
				end
				local handler = require(mod)
				package.loaded[mod] = nil
				handler(S, { k = k, rq = rq, method = method, path = path, act = act,
					G = G, ip = ip, isadmin = isadmin, cs = cs })
				return
			end

			-- guest login ----------------------------------------------------
			if act == "login" then
				local u, p = G.u or "", G.p or ""
				-- optional hook: login_precheck.lua sees _login.ip / _login.user and
				-- may refuse the attempt with _login.block = true (+ _login.msg)
				if file.exists("login_precheck.lua") then
					_login = { ip = ip, user = u, get = G }
					local ok, err = pcall(dofile, "login_precheck.lua")
					local hook = _login
					_login = nil
					if not ok then print("login_precheck: " .. tostring(err))
					elseif hook.block then
						login_form(k, cs, hook.msg or "Login not allowed right now.")
						return
					end
				end
				if u == st.user and p == st.password then
					if ip then allowed[ip] = true end
					if portal_blink then portal_blink() end
					client_page(k, cs)
				else
					log_fail(rq, ip, u, p)
					login_form(k, cs, "Wrong username or password.")
				end
				return
			end

			-- shared guest pages (guestbook, pixel canvas, 2-player, LED): same
			-- gate as the games; cp_api.lua is loaded for this request only
			if string.find(path, "^/api/") then
				if st.require_login and not (ip and allowed[ip]) and not isadmin then
					k:send("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n")
					return
				end
				local api = require("cp_api")
				package.loaded["cp_api"] = nil
				api(S, { k = k, path = path, G = G, ip = ip, isadmin = isadmin, cs = cs })
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

			-- logged-in guest: answer the OS connectivity checks with "online",
			-- so the phone closes its sign-in sheet (before login they get the
			-- portal/login page, which is what makes the sheet appear)
			if st.require_login and ip and allowed[ip] then
				local ok = PROBE[path]
				if ok == 204 then k:send("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n") return end
				if ok then S.send_html(k, ok) return end
			end

			-- "/" and anything else (incl. OS captive-probe URLs) --------------
			if (not st.require_login) or (ip and allowed[ip]) then client_page(k, cs)
			else login_form(k, cs, "") end
		end

		local function on_sent(k)
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
			k:close()
		end

		-- handlers run under pcall: on NodeMCU 3.x a failed send raises an error,
		-- and an error escaping a callback reboots the whole board. Now it only
		-- ends this one connection.
		local function guard(f, k, a)
			local ok, err = pcall(f, k, a)
			if not ok then print("http: " .. tostring(err)); pcall(k.close, k) end
		end
		c:on("receive", function(k, rq) guard(on_receive, k, rq) end)
		c:on("sent", function(k) guard(on_sent, k) end)

		c:on("disconnection", function(k)
			if cs.up then pcall(function() cs.up.fd:close() end); cs.up = nil end
			-- (no node.output(nil) here: adm_exec restores output itself; resetting
			-- it from other connections cut off a running command's output)
			collectgarbage("collect")
		end)
	end)

	print("HTTP server on :80")
end

return H
