-- adm_ls.lua : the admin file list (action=files), "name\tsize" lines then
-- "#\t<free bytes>". Never one table of all files: file.list() of ~70 files
-- needs one ~2 KB block for its table, which a fragmented heap may not have -
-- that PANIC-rebooted the board. So it lists in small groups by name pattern
-- (the biggest ~14 files, a ~0.5 KB table), freed after each group, and sends
-- the lines with send_parts. Runs inside cp_http's protected handler.
local GROUPS = { "^ad", "^a[^d]", "^[bc]", "^l", "^p", "^[rs]", "^[^abcglprs]",
	"^g[^a]", "^ga[^m]", "^gam[^e]", "^game[^_]", "^game_[0-9a-l]", "^game_[^0-9a-l]",
	"^[ag]$", "^game_$" }   -- together: every name exactly once

return function(S, x)
	local out = { "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" }
	for _, p in ipairs(GROUPS) do
		for k, v in pairs(file.list(p)) do out[#out + 1] = k .. "\t" .. v .. "\n" end
		collectgarbage()
	end
	out[#out + 1] = "#\t" .. file.fsinfo() .. "\n"   -- first value: bytes free
	S.send_parts(x.k, x.cs, out)
end
