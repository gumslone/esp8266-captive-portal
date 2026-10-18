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
-- status LED: blinks when a phone joins and on guest login
config.portal_led            = 4      -- pin: 4 = D4/GPIO2 (NodeMCU/ESP-12/ESP8285 blue LED),
                                      --      10 = TX/GPIO1 (ESP-01 blue LED - this DISABLES the
                                      --      serial console while the portal runs; to upload,
                                      --      stop it in the 2 s boot window), false = no LED
config.portal_led_type       = "gpio" -- "gpio", or "ws2812" for a WS2812B on D4/GPIO2
                                      -- (needs the ws2812 firmware module)
config.portal_led_active_low = true   -- gpio: on-board LEDs light when the pin is LOW
config.portal_led_color      = { 0, 40, 0 }  -- ws2812: R, G, B (0..255)
