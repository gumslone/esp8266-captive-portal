-- api_ch.lua : live chat (game_chat.html). Phones poll /api/ch?s=N and get
-- only the messages after number N; the first reply line is always the
-- newest number, so a poll with nothing new is one short line and never
-- touches flash. No s (a phone just opened the chat): the number only - no
-- history is sent. So chat.txt ("no|name|text" lines) is just a short buffer
-- for phones between polls, trimmed to the newest ~half once it passes
-- CH_MAX bytes. The counter is in RAM, so the chat starts empty after a
-- restart. n=&m= posts; admin: clear=1.
local CH_MAX = 1200        -- bytes kept in chat.txt before trimming (~10 messages)
local CH_WAIT = 3          -- seconds between two messages from one phone

return function(S, r)
	local k, G = r.k, r.G
	if not S.ch_no or (G.clear and r.isadmin) then        -- fresh boot / admin clear
		file.remove("chat.txt")
		S.ch_no, S.ch_last = 0, {}
	end
	local m = string.sub(string.gsub(G.m or "", "[\r\n|]", " "), 1, 120)
	if string.find(m, "%S") then
		local now, last = tmr.time(), S.ch_last
		if r.ip and last[r.ip] and now - last[r.ip] < CH_WAIT then
			k:send("HTTP/1.1 429 Too Many Requests\r\nConnection: close\r\n\r\n")
			return
		end
		if r.ip then
			local cnt = 0
			for _ in pairs(last) do cnt = cnt + 1 end
			if cnt > 30 then last = {}; S.ch_last = last end  -- keep the table small
			last[r.ip] = now
		end
		local n = string.sub(string.gsub(G.n or "", "[\r\n|]", " "), 1, 20)
		if not string.find(n, "%S") then n = "guest" end
		S.ch_no = S.ch_no + 1
		local fd = file.open("chat.txt", "a+")
		if fd then
			fd:write(S.ch_no .. "|" .. n .. "|" .. m .. "\n")
			local size = fd:seek("end")
			fd:close()
			if size > CH_MAX then                         -- keep the newer half (whole lines)
				fd = file.open("chat.txt", "r")
				fd:seek("set", size - CH_MAX / 2)
				fd:readline()                             -- skip the cut-off line
				local tail = fd:read(CH_MAX) or ""
				fd:close()
				fd = file.open("chat.txt", "w")
				if fd then fd:write(tail); fd:close() end
			end
		end
	end
	local since = tonumber(G.s or "") or S.ch_no          -- just opened: nothing old
	if since > S.ch_no then since = 0 end                 -- board restarted: send all
	local out = { S.TXT .. S.ch_no .. "\n" }       -- reply as a list of lines (send_parts)
	if since < S.ch_no then
		local fd = file.open("chat.txt", "r")
		if fd then
			repeat
				local l = fd:readline()
				if l and (tonumber(string.match(l, "^(%d+)|")) or 0) > since then out[#out + 1] = l end
			until not l
			fd:close()
		end
	end
	S.send_parts(k, r.cs, out)
end
