-- cp_dns.lua : DNS catch-all ("liar") - answers every query with our IP so a
-- joining client is steered to the portal. Adapted from do_not_upload/dns-liar.lua.
local D = {}

function D.start(ip)
	local i1, i2, i3, i4 = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
	local sIP = string.char(tonumber(i1), tonumber(i2), tonumber(i3), tonumber(i4))
	-- answer record: pointer to the question name, type A, class IN, TTL 60 s, our IP
	local ANSWER = "\192\12\0\1\0\1\0\0\0\60\0\4" .. sIP

	-- keep the socket on the module table: a `local` here gets garbage-collected
	-- after start() returns (cp_http runs collectgarbage on every disconnection),
	-- which silently closes the DNS catch-all. D stays alive via package.loaded.
	D.sock = net.createUDPSocket()
	D.sock:on("receive", function(sk, data, port, rip)
		-- question = name (from byte 13 to its 0 terminator) + type + class
		local e = string.find(data, "\0", 13, true)
		if not e or #data < e + 4 then return end         -- malformed: ignore
		-- only A (IPv4) questions get our IP; AAAA, HTTPS etc. get a valid empty
		-- answer. The question is echoed unchanged - replying "A" to an AAAA
		-- question made phones distrust the reply and slowed captive detection.
		local is_a = string.byte(data, e + 1) == 0 and string.byte(data, e + 2) == 1
		local reply = string.sub(data, 1, 2) .. "\129\128\0\1" .. (is_a and "\0\1" or "\0\0") ..
			"\0\0\0\0" .. string.sub(data, 13, e + 4) .. (is_a and ANSWER or "")
		-- pcall: on NodeMCU 3.x a failed send (radio buffers full during a burst
		-- of lookups) raises an error, which in a callback reboots the board.
		-- A dropped reply is harmless - the client simply asks again.
		pcall(sk.send, sk, port, rip, reply)
	end)
	D.sock:listen(53)
	print("DNS redirector listening. Free heap:", node.heap())
end

return D
