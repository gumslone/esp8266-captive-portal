-- api_px.lua : shared pixel wall (game_pixels.html). Kept in pixels.txt
-- (1024 hex chars = 32x32 palette indexes), so it survives restarts.
-- /api/px?v=N : first reply line is the wall's version (a RAM counter, bumped
-- on every paint); the board follows only if it changed since version N, so
-- a poll with nothing new is one short line. i=&c= paints one pixel;
-- admin: clear=1. A fresh boot starts the version from 1, so every phone
-- reloads the board once.
local PX = 1024

return function(S, r)
	local k, G = r.k, r.G
	S.px_v = S.px_v or 1
	if G.clear and r.isadmin then file.remove("pixels.txt"); S.px_v = S.px_v + 1 end
	local i, c = tonumber(G.i or ""), string.match(G.c or "", "^%x$")
	if i and c and i >= 0 and i < PX then
		if not file.exists("pixels.txt") then
			local fd = file.open("pixels.txt", "w"); fd:write(string.rep("0", PX)); fd:close()
		end
		local fd = file.open("pixels.txt", "r+")
		if fd then fd:seek("set", i); fd:write(c); fd:close() end
		S.px_v = S.px_v + 1
	end
	if tonumber(G.v or "") == S.px_v then S.txt(k, S.px_v .. "\n") return end
	-- the board in two 512-byte halves: no 1 KB string (see send_parts)
	local parts, fd = { S.TXT .. S.px_v .. "\n" }, file.open("pixels.txt", "r")
	for h = 2, 3 do parts[h] = fd and fd:read(PX / 2) or string.rep("0", PX / 2) end
	if fd then fd:close() end
	S.send_parts(k, r.cs, parts)
end
