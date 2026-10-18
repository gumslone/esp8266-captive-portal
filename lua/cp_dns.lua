-- cp_dns.lua : DNS catch-all ("liar") - answers every query with our IP so a
-- joining client is steered to the portal. Adapted from do_not_upload/dns-liar.lua.
local D = {}

function D.start(ip)
	local i1, i2, i3, i4 = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
	local x00, x01 = string.char(0), string.char(1)
	local s1 = string.char(128) .. x00 .. x00 .. x01 .. x00 .. x01 .. x00 .. x00 .. x00 .. x00
	local s2 = x00 .. x01 .. x00 .. x01 .. string.char(192) .. string.char(12) ..
		x00 .. x01 .. x00 .. x01 .. x00 .. x00 .. string.char(3) .. x00 .. x00 .. string.char(4)
	local sIP = string.char(tonumber(i1), tonumber(i2), tonumber(i3), tonumber(i4))

	-- keep the socket on the module table: a `local` here gets garbage-collected
	-- after start() returns (cp_http runs collectgarbage on every disconnection),
	-- which silently closes the DNS catch-all. D stays alive via package.loaded.
	D.sock = net.createUDPSocket()
	D.sock:on("receive", function(sk, data, port, rip)
		-- query name runs from byte 13 up to and including its 0 terminator
		local e = string.find(data, "\0", 13, true)
		if not e then return end                     -- malformed: ignore
		-- pcall: on NodeMCU 3.x a failed send (radio buffers full during a burst
		-- of lookups) raises an error, which in a callback reboots the board.
		-- A dropped reply is harmless - the client simply asks again.
		pcall(sk.send, sk, port, rip, string.sub(data, 1, 2) .. s1 .. string.sub(data, 13, e) .. s2 .. sIP)
	end)
	D.sock:listen(53)
	print("DNS redirector listening. Free heap:", node.heap())
end

return D
