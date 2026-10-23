-- adm_scan.lua : list nearby Wi-Fi. The portal runs in STATIONAP mode (idle
-- station) so this needs no mode switch - switching at runtime crashed it.
-- Reply lines: "#\t<our channel>" then "ssid\trssi\tchannel\tauth\tbssid".
return function(S, x)
	local k = x.k
	k:send("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")
	if wifi.getmode() == wifi.SOFTAP then              -- getap() would raise an error
		k:send("!station mode off - restart the device\n")
		return
	end
	x.cs.exec = true                                -- keep socket open until done
	-- reply as a list of lines (send_parts: no big string), all under pcall -
	-- an error in this callback would be "unprotected" and reboot the board
	wifi.sta.getap(1, function(t)
		local ok = pcall(function()
			local out = { "#\t" .. wifi.getchannel() .. "\n" }
			for bssid, v in pairs(t or {}) do
				local ssid, rssi, auth, ch = string.match(v, "^(.*),(-?%d+),(%d+),(%d+)$")
				if ssid then out[#out + 1] = ssid .. "\t" .. rssi .. "\t" .. ch .. "\t" .. auth .. "\t" .. bssid .. "\n" end
			end
			x.cs.exec = false                       -- next "sent" closes the socket
			S.send_parts(k, x.cs, out)
		end)
		if not ok then x.cs.exec = false; pcall(k.close, k) end
	end)
end
