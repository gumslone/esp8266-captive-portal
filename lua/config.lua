-- config.lua : edit these for your hotspot. The /admin page can change the
-- same values at runtime (saved to portal_config.lua, which overrides this).
config = {}
config.portal_ssid           = "Guest-WiFi"      -- network name clients see
config.portal_ap_password    = nil              -- WPA2 key (>=8 chars) or nil = open radio
config.portal_user           = "guest"           -- guest login username (login mode)
config.portal_password       = "changeme"        -- guest login password (login mode)
config.portal_admin_password = "admin-changeme"  -- ADMIN password (change this!)
config.portal_require_login  = false             -- true = guests log in first; false = open, page shown immediately
config.portal_page           = "portal_games.html" -- captive page shown to guests (admin can switch;
                                                  -- "portal_welcome.html" = address + "Open in
                                                  -- browser" first, then the games)
config.portal_login          = "login.html"       -- guest login form (admin can switch)
config.portal_txpower        = 82                 -- signal strength 1..82 (x0.25 dBm): 82 full, 40 one room
-- status LED: blinks when a phone joins and on guest login.
-- pins are NodeMCU indices: 4 = D4/GPIO2, 6 = GPIO12, 2 = GPIO4, 10 = TX/GPIO1.
config.portal_led_type       = "ws2812" -- "gpio" (plain LED) or "ws2812" (WS2812B/SK6812;
                                      -- needs the ws2812 module. firmware/minimal-ws2812 drives
                                      -- D4/GPIO2 only; the patched build drives any data pin)
config.portal_led            = 6      -- data pin (ws2812) or LED pin (gpio). This MicroBug board:
                                      -- 6 = GPIO12. For an ESP-01 plain LED use 10 (TX/GPIO1, which
                                      -- stops serial output while the portal runs). false = no LED.
config.portal_led_power      = 2      -- ws2812: pin that powers the LED (2 = GPIO4), false if always on
config.portal_led_active_low = true   -- gpio:   on-board LEDs light when the pin is LOW
config.portal_led_color      = { 0, 40, 0 }  -- ws2812: R, G, B (0..255)
