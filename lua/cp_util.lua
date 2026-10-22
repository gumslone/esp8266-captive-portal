-- cp_util.lua : small helpers the HTTP server keeps loaded. Settings
-- load/save live in cp_cfg.lua (loaded only when needed).
-- unescape is the project's (setup_functions.lua); the rest are new.
local U = {}

function U.unescape(s)
	if s == nil then return "" end
	s = string.gsub(s, "+", " ")
	s = string.gsub(s, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
	return s
end

function U.he(s)
	s = string.gsub(s or "", "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	s = string.gsub(s, '"', "&quot;")
	return s
end

function U.safe_name(s)        -- flat filesystem: no path separators
	local r = string.gsub(s or "", "[/\\]", "")   -- one value (minifier-safe)
	return r
end

return U
