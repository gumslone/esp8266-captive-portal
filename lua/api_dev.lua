-- api_dev.lua : the box itself. /api/led c=rrggbb lights the status LED
-- (ws2812 only, game_led.html); /api/n = how many phones are connected
-- (games menu).
return function(S, r)
	if r.what == "n" then
		local cnt = 0
		for _ in pairs(wifi.ap.getclient() or {}) do cnt = cnt + 1 end
		S.txt(r.k, tostring(cnt))
		return
	end
	local cr, cg, cb = string.match(r.G.c or "", "^(%x%x)(%x%x)(%x%x)$")
	if cr and portal_led then
		portal_led(tonumber(cr, 16), tonumber(cg, 16), tonumber(cb, 16))
		S.txt(r.k, "ok")
	else S.txt(r.k, portal_led and "bad colour" or "no LED on this board") end
end
