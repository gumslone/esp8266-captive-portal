-- adm_exec.lua : run a Lua line (Command box, file list/compile/rename/delete)
-- and reply with what it prints within 800 ms. Reused from fileserver.lua.
-- Output is collected and sent ONCE at the end (sending per printed line made
-- NodeMCU 3.x reboot). node.output gives a string on older firmware but a
-- pipe on NodeMCU 3.x, which must be drained with :read() - both handled.
return function(S, x)
	local k, out, pipe = x.k, {}, nil
	local function drain()
		if not pipe then return end
		repeat
			local d = pipe:read(1400)
			if d and #d > 0 then out[#out + 1] = d end
		until not d or #d == 0
	end
	x.cs.exec = true                                -- socket held open until the timer
	node.output(function(s)
		if type(s) == "string" then out[#out + 1] = s else pipe = s; drain() end
	end, 1)
	node.input(x.G.execute_command or "")
	tmr.create():alarm(800, tmr.ALARM_SINGLE, function()
		drain()
		node.output(nil)
		x.cs.exec = false                           -- next "sent" closes the socket
		local ok = pcall(k.send, k, "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\n" ..
			"Content-Type: text/plain\r\nConnection: close\r\n\r\n" .. table.concat(out))
		if not ok then pcall(k.close, k) end
	end)
end
