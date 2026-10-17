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
Runtime (upload all to the device's flash; compile the `.lua` to `.lc`):
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
portal_*.html       more captive page designs: minimal, info, event, offline;
                    the admin picks the active one (Captive page section)
login_*.html        more guest login designs: minimal, dark, terms (checkbox);
                    the admin picks the active one (Login form section)
```

Optional / tooling:
```
compile_all.lua     run once on the device to compile modules to .lc (saves heap)
reset_button.lua    press RST, then hold FLASH (GPIO0/D3) right after, to clear saved settings
flash.sh            flash the NodeMCU firmware (wraps tools/bugzapper/flash.sh)
bugzapper.sh        BugZapper GUI: flash + serial monitor + Lua upload tab
firmware/           NodeMCU firmware .bin (2018 master, 16 modules)
tools/upload.py     upload portal files + compile + restart (bundled nodemcu-uploader)
tools/bugzapper/    BugZapper copy (esptool 2.8, pyserial, nodemcu-uploader vendored)
```
Created at runtime: `portal_config.lua` (admin-saved settings; overrides
`config.lua`).

## Configure (`config.lua`)
```lua
config.portal_ssid           = "Guest-WiFi"
config.portal_ap_password    = nil              -- WPA2 key (>=8 chars) or nil = open
config.portal_user           = "guest"
config.portal_password       = "changeme"
config.portal_admin_password = "admin-changeme" -- CHANGE THIS
config.portal_require_login   = true            -- false = open splash
config.portal_page            = "portal_page.html" -- active captive page
config.portal_login           = "login.html"       -- active guest login form
```

## Flash it (only python3 needed)
BugZapper (flasher + serial monitor, with bundled esptool, pyserial and
nodemcu-uploader) lives in `tools/bugzapper/`. Plug the board in, then:
```sh
./flash.sh -e            # 1. erase + flash firmware/nodemcu_*.bin (once per board)
tools/upload.py --lfs    # 2. upload pages + lfs.img, load LFS, reboot into the portal
```
Board without auto-reset (you hold FLASH + press reset by hand)? Use
`./flash.sh --no-reset` - esptool's own reset would undo your flash mode.

**Firmware in use:** `firmware/minimal/` - NodeMCU 2.2.1 built with only the
7 modules the portal needs (no sensors, TLS or LFS): ~18.6 KB free heap with
the portal running. Flash it at 0x0 with a full erase (exact command in
HANDOVER.md), then `tools/upload.py` (normal `.lc` mode, no `--lfs`). Also kept:
the TeHyBug build (`firmware/tehybug/`), the 2018 build, and the LFS build
below (tried and reverted).

**LFS firmware (not in use)** (`firmware/lfs/BUILD.txt`): NodeMCU 3.0 release, integer, Lua 5.1,
modules file/gpio/net/node/tmr/uart/wifi, **64 KB LFS** - the portal's modules
run from flash (Lua Flash Store), so ~38 KB heap stays free with the portal
running (vs ~14 KB with .lc files on the old 2018 build, kept in
`firmware/old/`). `tools/luac.cross` is the matching host compiler that builds
`lfs.img`; rebuild it together with the firmware (source in ~/dev/nodemcu-firmware,
built with the marcelstoer/nodemcu-build Docker image). On firmware without LFS,
use `tools/upload.py` without `--lfs` (modules as .lc, compiled at boot).
Or use the GUI: `./bugzapper.sh` (Flash tab for the firmware, monitor for the
boot log; its Lua tab can upload single files too).
`tools/upload.py` minifies the Lua with **luamin** (`npm i -g luamin`; all
`.lua` except `config.lua`, ~24 KB -> ~13 KB), sends `admin.html` / `admin.js` /
`style.css` gzipped, removes stale `.lc` and restarts; `init.lua` recompiles the
modules on that fresh boot. The device therefore holds minified Lua - the
readable sources live in this repo. Options: `-p PORT`, `--only FILE...`,
`--no-minify`, `--no-compile`, `--no-restart`, `--dry-run`.

`init.lua` loads `.lc` if present, else `.lua`, so compiling is optional but
saves heap.

## Use
1. Join the AP → login form (login mode) or splash (open mode).
2. `http://192.168.1.1/admin` → enter the admin password.
3. Change settings (Save & restart), edit the captive page (Save page — applied
   live), upload any file under a name you choose (`.lua`, `sound.mp3`, ...),
   or manage files (list with free space, view, edit text files in place,
   rename, run, compile `.lua`, delete). A Command box runs any Lua line
   (e.g. `=node.heap()`), and a Restart button reboots the device.
   Uploading `x.lua` removes a stale `x.lc` so the new source is what runs.
4. `{{SSID}}` in the captive page is replaced with the network name.
5. **Captive page** section: pick any `portal_*.html` and press *Make active*
   (applied live, remembered across restarts). Add your own design by
   uploading or creating a new `portal_<name>.html`; it appears in the list.
   The **Login form** section works the same for `login*.html`.
6. **Nearby networks**: *Scan* lists other Wi-Fi networks (SSID, signal,
   channel, security) and highlights this portal's channel, to help pick a
   quiet one.

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
