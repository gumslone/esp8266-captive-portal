-- compile_all.lua : run once on the device ( dofile("compile_all.lua") ) to
-- compile the Lua modules to .lc, which saves heap at runtime. Sources are
-- kept. init.lua and config.lua stay as .lua on purpose (boot/config files).
local mods = { "cp_util", "cp_dns", "cp_http", "captive_portal",
	"adm_page", "adm_set", "adm_file", "adm_exec", "adm_scan" }
for _, m in ipairs(mods) do
	local src = m .. ".lua"
	if file.exists(src) then
		local ok = pcall(node.compile, src)
		print(ok and ("compiled -> " .. m .. ".lc") or ("FAILED    " .. src))
		collectgarbage("collect")                     -- lower the peak heap on ESP-01
	end
end
print("done; reset the device to run the compiled modules.")
