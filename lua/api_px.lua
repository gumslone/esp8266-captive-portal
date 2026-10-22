-- api_px.lua : shared pixel wall (game_pixels.html). /api/px returns the
-- 32x32 board as 1024 hex chars (palette index per pixel); i=&c= paints one.
-- Kept in pixels.txt, so it survives restarts; admin: clear=1.
local PX = 1024

return function(S, r)
	local k, G = r.k, r.G
	if G.clear and r.isadmin then file.remove("pixels.txt") end
	local i, c = tonumber(G.i or ""), string.match(G.c or "", "^%x$")
	if i and c and i >= 0 and i < PX then
		if not file.exists("pixels.txt") then
			local fd = file.open("pixels.txt", "w"); fd:write(string.rep("0", PX)); fd:close()
		end
		local fd = file.open("pixels.txt", "r+")
		if fd then fd:seek("set", i); fd:write(c); fd:close() end
	end
	if not S.send_file(k, r.cs, "pixels.txt") then S.txt(k, string.rep("0", PX)) end
end
