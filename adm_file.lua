-- adm_file.lua : write files - line-by-line text edit (page_append) and the
-- start of a raw binary upload (POST /admin/upload; cp_http streams the rest
-- via cs.up). Loaded per request by cp_http.
local OK = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"

-- a freshly written x.lua / x must win over a stale x.lc / x.gz
local function drop_stale(name)
	local lc = string.match(name, "^(.+)%.lua$")
	if lc then file.remove(lc .. ".lc") end
	if not string.find(name, "%.gz$") then file.remove(name .. ".gz") end
end

return function(S, x)
	local k, G = x.k, x.G
	local name = S.U.safe_name(G.name or "")
	if x.act == "page_append" then
		if name == "" then name = "portal_page.html" end
		local first = (G.first == "1")
		if first then drop_stale(name) end
		local fd = file.open(name, first and "w" or "a+")
		if fd then fd:write((G.line or "") .. "\n"); fd:close() end
		k:send(OK)
		return
	end
	-- upload start
	if name == "" then k:send("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n"); return end
	local clen   = tonumber(string.match(x.rq, "[Cc]ontent%-[Ll]ength:%s*(%d+)") or "0")
	local bstart = string.match(x.rq, "\r\n\r\n(.*)$") or ""
	drop_stale(name)
	local fd = file.open(name, "w")
	if not fd then k:send("HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\n"); return end
	if #bstart > 0 then fd:write(bstart) end
	local left = clen - #bstart
	if left <= 0 then fd:close(); k:send(OK)
	else x.cs.up = { fd = fd, left = left } end
end
