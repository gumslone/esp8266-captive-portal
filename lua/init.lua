-- init.lua : boot for a dedicated captive-portal device.
-- Waits 2 s first, so a crashing build can always be stopped from the serial
-- console:  boot:unregister()   (then fix files; node.restart() to retry)
--
-- Modules come from LFS (Lua Flash Store, code runs from flash - no RAM for
-- it) when the firmware has one and lfs.img was loaded (tools/upload.py --lfs).
-- Otherwise from .lc/.lua files, compiled here on a fresh boot.
-- node.LFS.get on current firmware, node.flashindex on older; nil without LFS
local lfs = node.LFS and node.LFS.get or node.flashindex

local function run(m)
	local f = lfs and lfs(m)
	if type(f) == "function" then f()
	elseif file.exists(m .. ".lc") then dofile(m .. ".lc")
	elseif file.exists(m .. ".lua") then dofile(m .. ".lua") end
end

-- require() looks in LFS first, then the usual .lc/.lua files
if lfs then
	table.insert(package.loaders, 2, function(m)
		local f = lfs(m)
		if type(f) == "function" then return f end
	end)
end

boot = tmr.create()
boot:alarm(2000, tmr.ALARM_SINGLE, function()
	boot = nil
	-- compile modules that have no .lc yet (and aren't in LFS), on a fresh
	-- boot (most free heap) and before the portal loads: big modules can't
	-- compile once it runs. Once the .lc exists the .lua is deleted (saves
	-- flash; tools/upload.py re-uploads sources when a module changes).
	for _, m in ipairs({ "cp_util", "cp_dns", "cp_http", "captive_portal",
		"adm_page", "adm_set", "adm_file", "adm_exec", "adm_scan" }) do
		if not (lfs and type(lfs(m)) == "function") and file.exists(m .. ".lua") then
			if not file.exists(m .. ".lc") then
				collectgarbage()
				print((pcall(node.compile, m .. ".lua") and "compiled " or "COMPILE FAILED ") .. m)
			end
			if file.exists(m .. ".lc") then file.remove(m .. ".lua") end
		end
	end
	collectgarbage()
	if not pcall(function() dofile("config.lua") end) then
		print("config.lua missing/invalid - using built-in defaults")
	end
	run("reset_button")    -- optional factory-reset hook (no-op if not uploaded)
	run("captive_portal")
end)
print("Portal starts in 2 s - type  boot:unregister()  to stop it")
