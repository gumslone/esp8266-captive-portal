-- cp_api.lua : small guest APIs behind the shared pages (game_guestbook,
-- game_pixels, game_duel, game_led). Loaded per request by cp_http and
-- dropped afterwards, like the adm_*.lua modules. Replies are plain text.
--   /api/gb   guestbook: GET lists "name|msg" lines; n=&m= adds one
--   /api/px   pixel canvas: 32x32 board as 1024 hex chars; i=&c= paints one
--   /api/mp   2-player rooms (tic-tac-toe / 4 in a row), state in RAM
--   /api/led  c=rrggbb lights the status LED (ws2812 only)
local GB_LINES = 15        -- guestbook keeps the newest 15 notes (~2 KB file)
local PX = 1024            -- 32 x 32 canvas, one hex char (palette index) per pixel
local ROOMS = 4            -- at most 4 live 2-player rooms

return function(S, r)
	local k, G, cs = r.k, r.G, r.cs
	local function txt(s)
		k:send("HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8" ..
			"\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" .. s)
	end
	local what = string.match(r.path, "^/api/(%w+)")

	if what == "gb" then
		if G.clear and r.isadmin then file.remove("guestbook.txt") end
		local m = string.sub(string.gsub(G.m or "", "[\r\n|]", " "), 1, 120)
		if string.find(m, "%S") then
			local n = string.sub(string.gsub(G.n or "", "[\r\n|]", " "), 1, 20)
			if not string.find(n, "%S") then n = "guest" end
			local keep, fd = {}, file.open("guestbook.txt", "r")
			if fd then
				repeat local l = fd:readline(); if l then keep[#keep + 1] = l end until not l
				fd:close()
			end
			while #keep >= GB_LINES do table.remove(keep, 1) end
			keep[#keep + 1] = n .. "|" .. m .. "\n"
			fd = file.open("guestbook.txt", "w")
			if fd then fd:write(table.concat(keep)); fd:close() end
		end
		if not S.send_file(k, cs, "guestbook.txt") then txt("") end

	elseif what == "px" then
		if G.clear and r.isadmin then file.remove("pixels.txt") end
		local i, c = tonumber(G.i or ""), string.match(G.c or "", "^%x$")
		if i and c and i >= 0 and i < PX then
			if not file.exists("pixels.txt") then
				local fd = file.open("pixels.txt", "w"); fd:write(string.rep("0", PX)); fd:close()
			end
			local fd = file.open("pixels.txt", "r+")
			if fd then fd:seek("set", i); fd:write(c); fd:close() end
		end
		if not S.send_file(k, cs, "pixels.txt") then txt(string.rep("0", PX)) end

	elseif what == "mp" then
		-- room = { g = "ttt"|"c4", b = board ("." empty, "1"/"2" pieces),
		--          n = moves made, p = { id1, id2 }, t = last activity }.
		-- The server only enforces turns and legal cells; pages check wins.
		local code = string.sub(string.upper(string.gsub(G.r or "", "%W", "")), 1, 6)
		local me = string.sub(G.me or "", 1, 12)
		if code == "" or me == "" then txt("err") return end
		local rooms = S.rooms or {}
		S.rooms = rooms
		local rm = rooms[code]
		if not rm then
			local cnt, old = 0, nil
			for c, v in pairs(rooms) do cnt = cnt + 1; if not old or v.t < rooms[old].t then old = c end end
			if cnt >= ROOMS then rooms[old] = nil end          -- drop the quietest room
			local g = G.g == "c4" and "c4" or "ttt"
			rm = { g = g, b = string.rep(".", g == "c4" and 42 or 9), n = 0, p = {} }
			rooms[code] = rm
		end
		local now = tmr.time()
		rm.t = now
		rm.s = rm.s or {}                                       -- s[seat] = when that player last polled
		local role = (rm.p[1] == me and 1) or (rm.p[2] == me and 2) or 0
		if role == 0 and #rm.p < 2 then rm.p[#rm.p + 1] = me; role = #rm.p end
		for i = 1, 2 do                                         -- seat left for 30 s: free for a newcomer
			if role == 0 and now - (rm.s[i] or now) > 30 then rm.p[i] = me; role = i end
		end
		if G.new and role > 0 then                              -- rematch: the other player starts
			rm.b, rm.n, rm.p[1], rm.p[2], rm.s[1], rm.s[2] = string.gsub(rm.b, "%d", "."), 0, rm.p[2], rm.p[1], rm.s[2], rm.s[1]
			role = 3 - role
		end
		if role > 0 then rm.s[role] = now end
		local m = tonumber(G.m or "")
		if m and role > 0 and #rm.p == 2 and rm.n % 2 == role - 1 then
			local at
			if rm.g == "c4" then                                -- m = column: lowest free row
				for row = 5, 0, -1 do
					if m >= 0 and m < 7 and string.sub(rm.b, row * 7 + m + 1, row * 7 + m + 1) == "." then at = row * 7 + m; break end
				end
			elseif m >= 0 and m < 9 and string.sub(rm.b, m + 1, m + 1) == "." then at = m end
			if at then
				rm.b = string.sub(rm.b, 1, at) .. role .. string.sub(rm.b, at + 2)
				rm.n = rm.n + 1
			end
		end
		txt(rm.g .. "|" .. rm.b .. "|" .. rm.n .. "|" .. role .. "|" .. #rm.p)

	elseif what == "led" then
		local cr, cg, cb = string.match(G.c or "", "^(%x%x)(%x%x)(%x%x)$")
		if cr and portal_led then
			portal_led(tonumber(cr, 16), tonumber(cg, 16), tonumber(cb, 16))
			txt("ok")
		else txt(portal_led and "bad colour" or "no LED on this board") end

	else
		k:send("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n")
	end
end
