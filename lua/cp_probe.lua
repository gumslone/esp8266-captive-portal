-- cp_probe.lua : for a logged-in guest, answer the phone's connectivity check
-- with "internet works", so it closes its sign-in sheet. Loaded by cp_http
-- only for logged-in guests' unmatched URLs; returns false for anything else.
local APPLE = "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"
local PROBE = { ["/hotspot-detect.html"] = APPLE, ["/library/test/success.html"] = APPLE,
	["/generate_204"] = 204, ["/gen_204"] = 204,                        -- Android / Chrome
	["/connecttest.txt"] = "Microsoft Connect Test", ["/ncsi.txt"] = "Microsoft NCSI",
	["/success.txt"] = "success\n" }                                    -- Firefox

return function(S, x)
	local ok = PROBE[x.path]
	if ok == 204 then x.k:send("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
	elseif ok then S.send_html(x.k, ok)
	else return false end
	return true
end
