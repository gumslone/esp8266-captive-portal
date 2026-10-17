-- config.lua : edit these for your hotspot. The /admin page can change the
-- same values at runtime (saved to portal_config.lua, which overrides this).
config = {}
config.portal_ssid           = "Guest-WiFi"      -- network name clients see
config.portal_ap_password    = nil              -- WPA2 key (>=8 chars) or nil = open radio
config.portal_user           = "guest"           -- guest login username (login mode)
config.portal_password       = "changeme"        -- guest login password (login mode)
config.portal_admin_password = "admin-changeme"  -- ADMIN password (change this!)
config.portal_require_login  = true              -- false = open splash shown immediately
config.portal_page           = "portal_page.html" -- captive page shown to guests (admin can switch)
config.portal_login          = "login.html"       -- guest login form (admin can switch)
config.portal_txpower        = 82                 -- signal strength 1..82 (x0.25 dBm): 82 full, 40 one room
