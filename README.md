# ESP8266 captive portal (access gate / welcome splash)

A small captive portal for **your own** NodeMCU/ESP8266 hotspot (incl. the
low-heap ESP-01). Visitors joining the AP are steered to a page you control.

* **Login mode** — visitors enter the username + password you preset. The
  portal only *compares* what is typed against your configured values; it
  stores nothing and imitates no other service.
* **Open mode** — no login; the captive page is shown immediately and can play
  a sound.

A password-protected **/admin** page (its own `config.portal_admin_password`,
separate from the guest password) switches mode, changes the SSID / WPA2 key /
guest credentials, edits the captive page, and manages files
(list / upload / run / compile / delete).

> **Hardware note.** An ESP8266 is an access point, not a NAT router. The gate
> controls access to *this device's* pages — it does not forward internet to
> clients. (That's the normal shape of an ESP8266 captive portal.)

## Why it's built this way (ESP-01 / low heap)
The scarce resource is **heap**, not flash. So:
* **Pages are files on flash**, served small; only tiny `{{SSID}}`/`{{ERR}}`
  tokens are substituted. No multi-KB HTML strings are ever built in RAM.
* **Big assets** (`admin.js`, `style.css`) and **`sound.mp3`** stream in
  1 KB chunks — never held whole in memory. `tools/upload.py` uploads
  `admin.js` / `style.css` pre-gzipped (`admin.js.gz`, `style.css.gz`); the
  server sends `x.gz` with `Content-Encoding: gzip` whenever `/x` is asked for
  (≈60% fewer bytes and round trips). Editing/uploading a plain `x` removes `x.gz`.
* **The captive page is edited line by line** (`action=page_append`, one tiny
  request per line — the `file_append` pattern from the reference project):
  the lowest-heap way to write text.
* **`sound.mp3` uploads stream straight to flash** one packet at a time
  (binary can't go line by line, and buffering a whole mp3 would blow the heap).

## Files
Repo layout (the device filesystem is flat - `tools/upload.py` uploads every
file under its bare name, so pages keep referring to `/admin.js`, `login.html`):
```
lua/        all Lua: init.lua, config.lua, captive_portal.lua, cp_*.lua, adm_*.lua, ...
html/       pages: admin.html, admin_login.html, login*.html, portal_*.html
css/        style.css
js/         admin.js
firmware/   NodeMCU images (minimal/ in use, tehybug/, lfs/, 2018 build)
tools/      upload.py, luac.cross, bugzapper/ (flasher + vendored esptool etc.)
flash.sh, bugzapper.sh   firmware flashing (CLI / GUI)
```

Runtime files (all uploaded flat to the device; modules end up as `.lc`):
```
init.lua            boot: 2 s abort window, compile missing .lc (then delete that
                    module's .lua - only .lc stay on the device), then captive_portal
config.lua          your settings (SSID, credentials, admin password, mode)
captive_portal.lua  entry: bring up AP, start DNS + HTTP
cp_util.lua         helpers + settings persistence (portal_config.lua)
cp_dns.lua          DNS catch-all (steers clients to the portal)
cp_http.lua         HTTP server (guest side; streams pages and files)
adm_*.lua           admin actions, one small module loaded per admin request
login.html          guest login page (login mode)
admin_login.html    admin password page
admin.html          admin dashboard (static, sent gzipped; admin.js fills in values)
admin.js            admin dashboard logic (streamed asset)
style.css           admin stylesheet (streamed asset)
portal_page.html    default captive page shown to clients (editable; {{SSID}} token)
portal_*.html       more captive page designs: minimal, info, event, offline, war;
                    the admin picks the active one (Captive page section).
                    portal_war.html is uploaded gzipped (portal_war.html.gz) and
                    plays assets/audio.mp3 (uploaded as audio.mp3)
game_*.html         small offline games: tic-tac-toe, 4 in a row, memory, snake, 2048,
                    minesweeper, 15 puzzle, simon, whack-a-mole, breakout (some vs computer
                    or 2 players); sent gzipped, open to guests after login.
                    portal_games.html is a captive page that links to them
login_*.html        more guest login designs: minimal, dark, terms (checkbox);
                    the admin picks the active one (Login form section)
```

Optional / tooling:
```
reset_button.lua    press RST, then hold FLASH (GPIO0/D3) right after, to clear saved settings
flash.sh            flash the NodeMCU firmware (wraps tools/bugzapper/flash.sh)
bugzapper.sh        BugZapper GUI: flash + serial monitor + Lua upload tab
firmware/           NodeMCU firmware .bin (2018 master, 16 modules)
tools/upload.py     upload portal files + compile + restart (bundled nodemcu-uploader)
tools/bugzapper/    BugZapper copy (esptool 2.8, pyserial, nodemcu-uploader vendored)
```
Created at runtime: `portal_config.lua` (admin-saved settings; overrides
`config.lua`).

## Configure (`lua/config.lua`)
```lua
config.portal_ssid           = "Guest-WiFi"
config.portal_ap_password    = nil              -- WPA2 key (>=8 chars) or nil = open
config.portal_user           = "guest"
config.portal_password       = "changeme"
config.portal_admin_password = "admin-changeme" -- CHANGE THIS
config.portal_require_login   = true            -- false = open splash
config.portal_page            = "portal_page.html" -- active captive page
config.portal_login           = "login.html"       -- active guest login form
config.portal_txpower         = 82                 -- signal strength 1..82 (x0.25 dBm)
config.portal_led             = 4                  -- status LED pin: 4 = D4/GPIO2, 10 = TX (ESP-01), false = off
config.portal_led_type        = "gpio"             -- or "ws2812" (WS2812B on D4; needs the ws2812 module)
config.portal_led_active_low  = true               -- gpio LED lights on LOW
config.portal_led_color       = { 0, 40, 0 }       -- ws2812 colour R, G, B
```

## Flash it (only python3 needed)
BugZapper (flasher + serial monitor, with bundled esptool, pyserial and
nodemcu-uploader) lives in `tools/bugzapper/`. Plug the board in, then:
```sh
./flash.sh -e            # 1. erase + flash firmware/minimal/*.bin (once per board)
tools/upload.py          # 2. upload the portal, restart; modules compile at boot
```
- **Board without auto-reset** (you hold FLASH, press reset, release FLASH):
  use `./flash.sh --no-reset -e` - esptool's own reset would undo flash mode.
- **Always erase (`-e`) when switching firmware builds** - otherwise the new
  firmware may fail to format its filesystem.
- GUI alternative: `./bugzapper.sh` (flash, serial monitor, single-file upload).

`tools/upload.py` minifies the Lua with **luamin** (`npm i -g luamin`; all
`.lua` except `config.lua`, ~24 KB -> ~13 KB), sends `admin.html` / `admin.js` /
`style.css` gzipped, removes stale `.lc` and restarts. On that boot `init.lua`
compiles each uploaded module and deletes its `.lua` after a good compile (a
failed compile keeps the source), so the device holds only `.lc` files - the
readable sources live in this repo. Options: `-p PORT`, `--only FILE...`,
`--no-minify`, `--no-restart`, `--dry-run`, `--lfs` (LFS firmware only).

### Firmware
| Folder | Build | Free heap with portal |
|---|---|---|
| `firmware/minimal/` **(in use)** | NodeMCU 2.2.1, only file/gpio/net/node/tmr/uart/wifi, integer, no TLS/LFS | ~18.6 KB |
| `firmware/minimal-ws2812/` | minimal + `ws2812` module, for a WS2812B status LED (`portal_led_type = "ws2812"`) | not measured yet |
| `firmware/minimal-ws2812-anypin/` | minimal + **patched** `ws2812` (`write_pin`): WS2812B/SK6812 on any data pin (e.g. GPIO12). See `firmware/patches/` | not measured yet |
| `firmware/tehybug/` | TeHyBug custom build (NodeMCU 2.2.0, sensors + TLS); two files at 0x0 and 0x10000 | ~12.7 KB |
| `firmware/*2018*.bin` | NodeMCU master 2018, 16 modules, float | ~14 KB |
| `firmware/lfs/` | NodeMCU 3.0 + 64 KB LFS (`tools/upload.py --lfs`, needs `tools/luac.cross`) | ~38 KB, **not used** |

The LFS build was tried and reverted: NodeMCU 3.x changed APIs the portal
relies on (a failed socket send raises an error; `node.output` passes a pipe,
not a string). The guards added for that stay in the code and are harmless
on 2.x. Each folder has a `BUILD.txt` (or see the table) describing how it
was built (marcelstoer/nodemcu-build Docker image).

## Use
1. Join the AP → login form (login mode) or splash (open mode).
2. `http://192.168.1.1/admin` → enter the admin password.
3. Change settings (Save & restart), edit the captive page (Save page — applied
   live), upload any file under a name you choose (`.lua`, `sound.mp3`, ...),
   or manage files (list with free space, view, edit text files in place,
   rename, run, delete). A Command box runs any Lua line
   (e.g. `=node.heap()`), and a Restart button reboots the device.
   Uploading `x.lua` removes a stale `x.lc` so the new source is what runs.
4. `{{SSID}}` in the captive page is replaced with the network name.
5. **Captive page** section: pick any `portal_*.html` and press *Make active*
   (a pre-gzipped `portal_<name>.html.gz` works too and loads faster - gzip it
   on your computer, e.g. `gzip -9k portal_x.html`, and upload it under that
   name; such a page can't use `{{SSID}}`)
   (applied live, remembered across restarts). Add your own design by
   uploading or creating a new `portal_<name>.html`; it appears in the list.
   The **Login form** section works the same for `login*.html`.
6. **Nearby networks**: *Scan* lists other Wi-Fi networks (SSID, signal,
   channel, security) and highlights this portal's channel, to help pick a
   quiet one.
7. **Admin password** can be changed on the settings form (blank = keep). It is
   saved in `portal_config.lua`; the FLASH-button reset falls back to
   `config.portal_admin_password`. **Backup**: download `portal_config.lua` from
   the admin page; restore by uploading it under that name and restarting.

After a guest logs in, the portal answers the phone's connectivity checks
(iOS/macOS, Android, Windows, Firefox) with "online", so the sign-in sheet
closes by itself. The status LED blinks when a phone joins and on guest login.

### Login precheck hook (optional)
Upload a `login_precheck.lua` to the device (admin page -> Upload file) and it
runs before every guest login check. It can read `_login.ip` and
`_login.user`, and refuse the attempt with `_login.block = true` (plus an
optional `_login.msg` shown on the form). It never sees the password. A broken
hook is only logged; logins keep working. See `examples/login_precheck.lua`
(blocks some usernames, max 5 attempts per IP per minute) and
`examples/login_precheck_log.lua` (logs IP + username of each attempt to
`login_log.txt`, capped at ~4 KB). Only one hook is active at a time - upload
the one you want as `login_precheck.lua`; delete it to disable.

### Editing the login forms
`login.html` and `admin_login.html` can be edited freely (layout, text, style).
The server only needs these fields, and accepts them via **GET or POST**
(query string, urlencoded body, or both mixed; any `action=` path):

| Form | Fields |
|---|---|
| guest login (`login.html`) | `action=login`, `u` (username), `p` (password) |
| admin login (`admin_login.html`) | `action=admin_login`, `ap` (admin password) |

Keep the default form encoding — `enctype="multipart/form-data"` is not parsed.
Tokens: `{{SSID}}`, `{{ERR}}` (error message, empty on first view).

Audio autoplay is blocked by browsers until a tap, so the default page keeps a
▶ Play button as a fallback.

## Security notes
* `/admin`, file upload, line-edit, and execute are gated by the admin password
  (tracked per client IP for the session). Guests cannot read `config.lua` or
  other source files — only whitelisted assets are served without admin.
* `execute` runs arbitrary Lua on the device (same capability as the reference
  `fileserver.lua`). Use a strong `config.portal_admin_password`.

## Reused from the reference projects
`ap.lua` (AP setup), `do_not_upload/dns-liar.lua` (DNS catch-all),
`setup.lua` / `setup_functions.lua` (request & query parsing, `unescape`),
`fileserver.lua` / `setup_actions.lua` (`execute`, `file_append` line upload).
