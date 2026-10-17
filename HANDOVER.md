# HANDOVER — ESP8266 captive portal

Context for continuing this project in Claude Code. (You can rename or copy this
to `CLAUDE.md` if you want Claude Code to auto-load it as project context.)

## What this is
A captive portal for the owner's **own** NodeMCU/ESP8266 hotspot (including the
low-heap ESP-01). It gates access to the device's own pages, or shows a welcome
splash. Built fresh in this folder, copying features from two reference repos.

**Scope / intent (important):** this is access control for your own AP. In
**login mode** it only *compares* the entered username/password against values
the owner configured — it does **not** store submitted credentials and does
**not** imitate any other brand or service. The SSID is the owner's own network
name. Keep it that way: no credential harvesting, no look-alike/branded login
pages. That boundary is deliberate.

**Hardware reality:** an ESP8266 is an access point, not a NAT router, so the
portal cannot forward internet to clients — it controls access to this device's
pages only. The scarce resource is **heap**, not flash (ESP-01 ≈ tens of KB).

## Reference projects (read-only, on this machine)
- `/Users/oleg/dev/fakeportal`
- `/Users/oleg/tehy_scripts5_18650_dev_refactored`
Reused: `ap.lua` (AP setup), `do_not_upload/dns-liar.lua` (DNS catch-all),
`setup.lua` + `setup_functions.lua` (request/query parse, `unescape`),
`fileserver.lua` + `setup_actions.lua` (`execute`, `file_append` line upload).

## Architecture (and the key decisions)
Low-heap is the guiding constraint, so:
- **Pages are files on flash**, served small; only tiny `{{SSID}}`/`{{ERR}}`/
  settings tokens are substituted (function-replacement in gsub to avoid `%`
  issues). No multi-KB HTML strings are built in RAM — an earlier string-builder
  design (`cp_pages.lua`) was dropped for exactly this reason.
- **Big assets** (`admin.js`, `style.css`) and **`sound.mp3`** stream in
  1 KB chunks (`CHUNK` in cp_http.lua) from the `sent` handler; never held
  whole in RAM. If `x.gz` exists, `/x` serves it with `Content-Encoding: gzip`
  (tools/upload.py uploads admin.js/style.css only as .gz; they are not meant to be
  edited on the device, so .gz files get no "edit" link — change them on the
  Mac and re-run tools/upload.py). admin.js, css, mp3, ico, png are sent with
  `max-age=3600`; after a re-flash, hard-reload /admin to pick up a new admin.js. `drop_stale()` removes
  `x.gz` (and `x.lc` for `x.lua`) when a plain `x` is uploaded or edited.
- **Captive page edits go LINE BY LINE** (`action=page_append`, `first=1`
  truncates then `a+` appends) — the `file_append` pattern, lowest heap for text.
- **`sound.mp3` uploads stream raw body to flash** (`POST /admin/upload?name=`),
  one packet at a time; binary can't go line-by-line and buffering a whole mp3
  would blow the heap. (A streaming multipart parser was prototyped + validated
  byte-exact over 2000 files × 8 packet sizes, but the simpler raw-body stream
  was chosen; the validated multipart algorithm is available if a no-JS upload
  form is ever wanted.)
- Everything is **`action=`-driven** into a `_GET` table (reference regex).

## File map (all runtime files upload to flash)
Repo folders: lua/ (all .lua), html/, css/, js/; tools/upload.py resolves bare
device names via SRC_DIRS and uploads them flat (device FS has no folders).
```
init.lua            boot: 2 s abort window (boot:unregister()); any module .lua
                    on the device is the newest version -> compiled on the
                    fresh heap; a GOOD compile deletes the .lua, a failed one
                    removes the partial .lc and keeps the .lua; then portal
config.lua          settings: SSID, guest creds, admin password, mode
captive_portal.lua  entry: AP up, then require cp_dns + cp_http
cp_util.lua         unescape/he/lua_q/safe_name/read_file + load/save_settings
cp_dns.lua          DNS catch-all ("liar")
cp_http.lua         HTTP server (guest side): parsing, login, streamed pages/files,
                    admin check + dispatch to one adm_*.lua per request
adm_page.lua        admin sign-in (303 -> /admin), dashboard, action=settings
adm_set.lua         save_settings, set_page
adm_file.lua        page_append (line edit), upload start
adm_exec.lua        execute (Command box, file ops)
adm_scan.lua        scan nearby Wi-Fi (no mode switch; AP runs as STATIONAP)
login.html          guest login (login mode)   [tokens: SSID, ERR]
admin_login.html    admin password page         [token: ERR]
admin.html          admin dashboard, STATIC (no tokens; uploaded as admin.html.gz);
                    admin.js fills it from action=settings
admin.js            dashboard logic (streamed)
style.css           admin styles (streamed)
portal_page.html    default captive page (editable; {{SSID}} token)
portal_*.html       other designs (minimal/info/event/offline), each <1 KB;
                    active one = setting `page`, chosen in admin "Captive page"
login_*.html        login designs (minimal/dark/terms); active = setting `login`
compile_all.lua     device-side: node.compile the modules to .lc
reset_button.lua    optional: RST, then hold FLASH(GPIO0/D3) within ~0.5 s -> clear portal_config.lua
flash.sh            root: flash firmware via tools/bugzapper/flash.sh (esptool)
bugzapper.sh        root: BugZapper GUI (title/icon/firmware dir preset)
tools/upload.py     luamin-minify Lua (not config.lua), gzip admin.html/js/css,
                    upload via bundled nodemcu-uploader (RTS/DTR held off),
                    remove stale .lc, restart -> init.lua compiles at boot.
                    luamin drops "redundant" parens: write `local r=f() return r`,
                    never `return (f())`, where only one value must be returned.
tools/bugzapper/    copy of ~/dev/bugzapper (VERSION = source commit); not a
                    submodule because this folder is not a git repo
tools/flash.sh      legacy shim -> tools/upload.py
```
Created at runtime: `portal_config.lua` (admin-saved settings; overrides config.lua).

## Settings precedence
built-in defaults  <-  `config.portal_*` (config.lua)  <-  `portal_config.lua`
Keys: `portal_ssid`, `portal_ap_password` (WPA2 >=8 or nil=open),
`portal_user`, `portal_password`, `portal_admin_password`, `portal_require_login`,
`portal_page` (active captive page file; missing file falls back to portal_page.html),
`portal_login` (active guest login form; missing file falls back to login.html).

## Routes (cp_http.lua)
- Form fields are read from the query string AND from a urlencoded POST body
  (login.html / admin_login.html now POST, so creds stay out of the URL). A
  POST whose body arrives in a 2nd packet is held in `pend` until complete
  (only for requests < 2 KB; /admin/upload is excluded).
- `action=login`         guest creds -> allowed[ip]; serves captive page
  On failure appends a debug line to `login_fail.txt` (admin-only, capped
  ~2 KB): uptime, ip, user (only if it matches, else "(other)"), user_ok,
  pass_ok, pass_len, ua (User-Agent, first 80 chars). The password itself is NEVER written (scope boundary).
  Viewed/cleared from the admin "Failed logins" section (via `execute`).
- `action=set_page&name=[&kind=login]` (admin) make an existing .html the active
                         captive page (or, with kind=login, the guest login form);
                         live (updates st.page) and saved to portal_config.lua
- `action=scan`          (admin) list nearby Wi-Fi via wifi.sta.getap(1,cb); the
                         portal always runs STATIONAP (idle station), because
                         switching modes at runtime crashed the board; replies
                         "#\t<our ch>" + "ssid\trssi\tch\tauth\tbssid" lines.
- `action=admin_login`   admin pass  -> admin_ok[ip]; 303 redirect to /admin
- `action=settings`      (admin) current settings as "key=urlencoded" lines
- `action=save_settings` (admin) write portal_config.lua, then node.restart()
- `action=page_append`   (admin) write a text file one line/request; `name=`
                         (default portal_page.html); first line of `x.lua`
                         removes stale `x.lc`. Used by the admin "Edit file" box.
                         Rename/delete/compile, the Command box and the
                         Restart button all go through `action=execute`.
                         Saving >200 lines asks for confirmation first.
                         Command box has a preset dropdown (list lives in
                         admin.js, so admin.html's in-RAM render stays small).
                         Output = whatever print()/REPL emits within 800 ms.
- `action=execute`       (admin) node.output+node.input (run/compile/delete)
- `POST /admin/upload?name=` (admin) stream raw body to flash (binary-safe);
                         any name (UI "Save as" field); `x.lua` removes stale `x.lc`
- `GET /admin`           admin.html(.gz) or admin_login.html
- `GET /`                captive page (open mode / authed) or login form
- `GET /<file>`          static asset; guests limited to a PUBLIC whitelist
                         (style.css, admin.js, sound.mp3, favicon.ico,
                         portal_page.html). Admins may fetch any file.

## Security model
- Admin actions gated by `admin_ok[ip]` (set after correct admin password).
- Guests **cannot** read `config.lua`/source (only the PUBLIC whitelist is
  served without admin) — this prevents leaking the admin password / WiFi key.
- `execute` runs arbitrary Lua (same capability as reference `fileserver.lua`):
  admin-gated; tell users to set a strong `portal_admin_password`.

## Firmware
`firmware/nodemcu-master-16-modules-2018-05-14-15-13-59-float.bin` (480 KB,
NodeMCU master 2018-05, float, SSL off). Modules: am2320, bme280, dht,
ds18b20, **file, gpio**, http, i2c, mqtt, **net, node**, ow, **tmr**, u8g,
**uart, wifi** (bold = used by the portal). Copied from the owner's home dir;
flash at 0x0 (e.g. BugZapper / `esptool write_flash -fm dio -fs detect 0x0`),
then upload the Lua/HTML files (tools/upload.py).

## Build / run
1. Edit `lua/config.lua` (set `portal_admin_password`; choose login vs open mode).
2. `./flash.sh -e` (firmware, once) then `tools/upload.py` (portal files).
   This uploads all files, runs `compile_all.lua`, and resets.
3. Join the AP; open `http://192.168.1.1/admin`.
Audio autoplay is blocked until a tap, so the default page has a ▶ Play button.

## Firmware on the board now (2026-10-17): minimal NodeMCU 2.2.1
firmware/minimal/nodemcu_2.2.1_minimal_integer.bin (418 KB, single image at
0x0): tag 2.2.1-master_20190405, integer, modules file/gpio/net/node/tmr/uart/
wifi only, no sensors/TLS/LFS (see firmware/minimal/BUILD.txt; source + config
in ~/dev/nodemcu-firmware-2.2.1). node.output passes strings (2.x API).
Measured: 43.9 KB heap bare, ~18.6 KB with the portal (TeHyBug build ~12.7 KB,
2018 build ~14.1 KB); 459 KB free filesystem.
    PYTHONPATH=tools/bugzapper/vendor python3 tools/bugzapper/vendor/esptool.py \
      --port /dev/cu.usbserial-10 --before no_reset write_flash --erase-all \
      -fm dio -fs detect 0x0 firmware/minimal/nodemcu_2.2.1_minimal_integer.bin
    tools/upload.py

## TeHyBug custom build (previous)
firmware/tehybug/0x00000.bin + 0x10000.bin (from github.com/gumslone/tehybug,
lua_scripts/tehybug_firmwares/tehybug_firmware/18650): "Custom build by Oleg
Jusaew", NodeMCU 2.2.0 (2022), Lua 5.1, no LFS; has all portal functions plus
sensor modules and tls. Measured: 41.4 KB heap bare, ~12.7 KB with the portal.
Flash (board needs manual flash mode, so no auto reset), then upload:
    PYTHONPATH=tools/bugzapper/vendor python3 tools/bugzapper/vendor/esptool.py \
      --port /dev/cu.usbserial-10 --before no_reset write_flash --erase-all \
      -fm dio -fs detect 0x00000 firmware/tehybug/0x00000.bin 0x10000 firmware/tehybug/0x10000.bin
    tools/upload.py            # normal .lc mode (no --lfs on this firmware)
ALWAYS erase when switching firmware builds: without it the 2018 build failed
with "unable to format. FS might be compromised".
Also available: firmware/nodemcu-master-16-...-2018...-float.bin (single file,
0x0; ~14 KB heap with portal) and firmware/lfs/ (NodeMCU 3.0 + LFS, below).

## LFS firmware (2026-10-17, tried, NOT in use)
Reverted: gave 38 KB free heap, but NodeMCU 3.x API changes broke things and
each needed hardware rounds: (1) a failed socket send raises a Lua error, which
in a callback reboots the board -> fixed with pcall in cp_dns + cp_http guard;
(2) node.output() passes a PIPE (drain with :read()) not a string -> adm_exec
handles both now; (3) node.output(nil) did not restore console output on 3.x
(unresolved). The fixes for (1)/(2) stay - they are harmless on 2.x.
firmware/nodemcu_integer_release_20261017-1736.bin: NodeMCU 3.0 release
(c8faff2), integer, Lua 5.1, 7 modules, LUA_FLASH_STORE 0x10000. Built from
~/dev/nodemcu-firmware with `docker run --platform linux/amd64 -e INTEGER_ONLY=1
-v $PWD:/opt/nodemcu-firmware marcelstoer/nodemcu-build build` (config edits in
app/include/user_modules.h + user_config.h). tools/luac.cross = native arm64
build of app/lua/luac_cross (cc -include sys/types.h -DLUA_CROSS_COMPILER ...);
its lfs.img is byte-identical to the container's Linux luac.cross.int.
- Deploy: `./flash.sh --no-reset` (this board) then `tools/upload.py --lfs`
  (minify -> luac.cross -f -o lfs.img -> upload -> node.LFS.reload -> reboot).
- init.lua: require() searches LFS first (node.LFS.get / node.flashindex),
  falls back to .lc/.lua, so the same init.lua works on non-LFS firmware.
- Measured: free heap with portal running 38.1 KB (was ~14 KB); loading an
  admin module costs ~150 B (was ~2.4 KB); lfs.img ~14 KB of 64 KB.
- Flashing this board: needs manual flash mode AND esptool --before no_reset;
  writes sometimes hit serial errors ("Invalid head of packet") - just retry.

## Real hardware (2026-10-17): ESP8266EX, 1 MB flash, NodeMCU 2018 build
Flashed + uploaded with ./flash.sh and tools/upload.py; board has no
auto-reset into flash mode (hold FLASH/GPIO0 + reset to flash).
- Free heap: 42 KB bare firmware, ~14 KB with the portal running.
- One big cp_http.lua (14 KB source) could NOT be compiled on the device
  (E:M 8200, even on a fresh boot) and booting from source looped on PANIC.
  -> split into cp_http + adm_*.lua; init.lua compiles missing .lc at boot.
- Loading a monolithic admin module cost 8.6 KB and admin.html rendering in
  RAM then crashed the login. -> templates are streamed line-by-line (~512 B
  pieces, tokens substituted per piece); admin.html is static + gzipped.
- Switching SOFTAP<->STATIONAP for a scan rebooted the board -> STATIONAP always.
- nodemcu-uploader's default open toggles RTS/DTR and resets this board ->
  tools/upload.py opens the port with both held inactive.
- node.stripdebug() has no effect on node.compile in this build (a test file
  compiled to 144 B at level 1 and 3; real modules byte-identical) - so .lc
  files are already as small as this firmware makes them. Not used.
- Verified on device: AP at 192.168.1.1, mode 3, scan (10 nets) without crash.
  Not yet verified on device: full admin page in a phone browser end-to-end.

## Validation done (in the cloud container, not on hardware)
- All Lua modules parse via `luaparser`; `admin.js` passes `node --check`.
- Multipart streaming algorithm proven byte-exact (2000 files × 8 packet sizes).
- Since then: flashed and run on real hardware — see the section above.

## Open items / next steps
- [ ] Flash to a real ESP8266/ESP-01 and smoke-test: AP comes up, captive sheet
      pops (phone), login gate, open mode, admin login, page edit, mp3 upload,
      file list/run/compile/delete, save+restart, factory-reset button.
- [ ] Decide whether a WPA2 AP + the login gate together is the wanted model, or
      open AP + gate. Both work; AP key is `portal_ap_password`.
- [x] Missing `/favicon.ico` now answers a cheap 204 (no page build per probe).
      Still optional: captive-probe tuning per OS if the sign-in sheet is slow.
- [x] Optimization pass (2026-10-17): DNS query parsed with one `find` (no
      per-byte concat; malformed packets ignored); login pages link `style.css`
      instead of inlining CSS (~600 B less RAM per render); css/js/mp3 served
      `max-age=3600` (html stays `no-store`); `config` table freed after load;
      query parser keeps empty values (fields clearable, validation live);
      GC between compiles in `compile_all.lua`; reset-button docs corrected.
- [x] `render()` substitutes all `{{TOKENS}}` in one table-gsub pass (one page
      copy instead of one per token). Admin page makes no extra requests at
      script load: file list fetched on `window.onload`, editor loads only on
      Load/edit (Save asks before overwriting a file that wasn't loaded).
- [x] All `*.lua` pass local `luac -p` (Mac now has luac) and `node --check admin.js`.
- [ ] Optional: cap/compress portal_page.html size guidance for ESP-01.
- [ ] Consider a short idle/deep-sleep policy only if this runs on battery
      (reference setup.lua has one; a portal usually runs on USB power).

## Dev environment notes
- Files live on the user's Mac; this session edited them over the device bridge
  (device_bash, mounts under `$HOME/mnt/...`). In Claude Code locally they are
  just regular files under `/Users/oleg/dev/esp8266-captive-portal`.
- No Lua toolchain on the Mac; syntax was checked in the cloud container with
  `luaparser` (pip) and `node --check`. NodeMCU is Lua 5.1-ish; code sticks to
  plain syntax (no goto/bitops) so any luac also parses it.
