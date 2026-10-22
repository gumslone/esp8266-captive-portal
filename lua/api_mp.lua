-- api_mp.lua : 2-player rooms for game_duel.html (tic-tac-toe / 4 in a row
-- between two phones). State lives in RAM (S.rooms), at most ROOMS rooms.
local ROOMS = 4

return function(S, r)
	local k, G = r.k, r.G
	-- room = { g = "ttt"|"c4", b = board ("." empty, "1"/"2" pieces),
	--          n = moves made, p = { id1, id2 }, t = last activity }.
	-- The server only enforces turns and legal cells; pages check wins.
	local code = string.sub(string.upper(string.gsub(G.r or "", "%W", "")), 1, 6)
	local me = string.sub(G.me or "", 1, 12)
	if code == "" or me == "" then S.txt(k, "err") return end
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
	S.txt(k, rm.g .. "|" .. rm.b .. "|" .. rm.n .. "|" .. role .. "|" .. #rm.p)
end
