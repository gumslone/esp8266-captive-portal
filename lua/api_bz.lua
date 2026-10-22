-- api_bz.lua : quiz buzzer (game_buzzer.html). State in RAM (S.bz).

return function(S, r)
	local k, G = r.k, r.G
	-- bz = { r = round no., w = { "name", ... } first 5 presses, h = host id,
	--        ht = host last seen }. The host (or admin) starts each round;
	-- a host gone for 60 s can be replaced. First press lights the LED.
	local bz = S.bz or { r = 1, w = {} }
	S.bz = bz
	local me, now = string.sub(G.me or "", 1, 12), tmr.time()
	if G.host and me ~= "" and (not bz.h or bz.h == me or now - bz.ht > 60) then bz.h = me end
	local host = r.isadmin or (me ~= "" and bz.h == me)
	if bz.h == me then bz.ht = now end
	if G.next and host then
		bz.r, bz.w = bz.r + 1, {}
		if portal_led then portal_led(0, 0, 0) end
	elseif G.press and tonumber(G.press) == bz.r and #bz.w < 5 then
		local n = string.sub(string.gsub(G.n or "", "[\r\n|,]", " "), 1, 20)
		if not string.find(n, "%S") then n = "guest" end
		local dup = false
		for _, v in ipairs(bz.w) do if v == n then dup = true end end
		if not dup then
			bz.w[#bz.w + 1] = n
			if #bz.w == 1 and portal_led then portal_led(120, 0, 0) end
		end
	end
	S.txt(k, bz.r .. "|" .. (host and "1" or "0") .. "|" .. (bz.h and "1" or "0") .. "|" .. table.concat(bz.w, ","))
end
