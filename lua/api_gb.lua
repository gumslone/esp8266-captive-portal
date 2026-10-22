-- api_gb.lua : guestbook (game_guestbook.html, admin Guest pages).
-- /api/gb lists "name|msg" lines; n=&m= adds a note (one per phone per
-- GB_WAIT s); admin: del=N removes note N, clear=1 empties it. One of the
-- small api_*.lua modules cp_http loads for a single /api/ request.
local GB_LINES = 15        -- keeps the newest 15 notes (~2 KB file)
local GB_WAIT = 30         -- seconds between two notes from one phone

return function(S, r)
	local k, G = r.k, r.G
	if G.clear and r.isadmin then file.remove("guestbook.txt") end
	local m = string.sub(string.gsub(G.m or "", "[\r\n|]", " "), 1, 120)
	local del = r.isadmin and tonumber(G.del or "")          -- admin: remove note no. del
	if string.find(m, "%S") or del then
		local now, last = tmr.time(), S.gb_last or {}        -- last[ip] = time of the last note
		S.gb_last = last
		if not del and r.ip and last[r.ip] and now - last[r.ip] < GB_WAIT then
			k:send("HTTP/1.1 429 Too Many Requests\r\nConnection: close\r\n\r\n" .. (GB_WAIT - (now - last[r.ip])))
			return
		end
		local keep, fd = {}, file.open("guestbook.txt", "r")
		if fd then
			repeat local l = fd:readline(); if l then keep[#keep + 1] = l end until not l
			fd:close()
		end
		if del then table.remove(keep, del)
		else
			local n = string.sub(string.gsub(G.n or "", "[\r\n|]", " "), 1, 20)
			if not string.find(n, "%S") then n = "guest" end
			while #keep >= GB_LINES do table.remove(keep, 1) end
			keep[#keep + 1] = n .. "|" .. m .. "\n"
			if r.ip then
				local cnt = 0
				for _ in pairs(last) do cnt = cnt + 1 end
				if cnt > 30 then last = {}; S.gb_last = last end  -- keep the table small
				last[r.ip] = now
			end
		end
		fd = file.open("guestbook.txt", "w")
		if fd then fd:write(table.concat(keep)); fd:close() end
	end
	if not S.send_file(k, r.cs, "guestbook.txt") then S.txt(k, "") end
end
