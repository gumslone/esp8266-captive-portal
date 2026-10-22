#!/usr/bin/env python3
"""Upload the captive-portal files to a NodeMCU board over serial.

Uses the nodemcu-uploader + pyserial bundled in tools/bugzapper/vendor, so only
python3 is needed (no npm / nodemcu-tool / pip). Flash the NodeMCU firmware
first (./flash.sh or ./bugzapper.sh), then run this.

  tools/upload.py                     # auto-detect port, upload all, compile, restart
  tools/upload.py -p /dev/cu.usbserial-110
  tools/upload.py --only cp_http.lua  # push just some files (still compiles)
  tools/upload.py --dry-run           # show what would run, touch nothing
  tools/upload.py --no-minify         # upload readable Lua (e.g. to debug on device)
  tools/upload.py --lfs               # modules -> lfs.img (needs LFS firmware + tools/luac.cross)

Lua files (all but config.lua, which you edit by hand) are minified with luamin
first - about half the size, so faster uploads and less flash/compile work; the
readable sources stay in this repo (needs node + `npm i -g luamin`; without it
the plain files go up, with a warning; --no-minify to skip). admin.html /
admin.js / style.css are uploaded pre-gzipped and served with
Content-Encoding: gzip. Old .lc files are removed and init.lua recompiles them
on the next boot, when the most heap is free.
"""
import argparse
import glob
import gzip
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(ROOT, "tools", "bugzapper", "vendor")
# the repo keeps sources in folders; the device filesystem is flat, so every
# file is uploaded under its bare name (pages reference /admin.js, login.html ...)
SRC_DIRS = ["lua", "html", "css", "js", "assets", "."]


def src(name):
    """Local path of a device file name (searched in SRC_DIRS)."""
    for d in SRC_DIRS:
        p = os.path.join(ROOT, d, name)
        if os.path.exists(p):
            return p
    return os.path.join(ROOT, name)

CORE = ["init.lua", "config.lua", "captive_portal.lua", "cp_util.lua", "cp_cfg.lua", "cp_dns.lua",
        "cp_http.lua", "cp_login.lua", "cp_probe.lua", "adm_route.lua", "adm_page.lua", "adm_set.lua", "adm_file.lua",
        "adm_exec.lua", "adm_scan.lua", "api_gb.lua", "api_px.lua", "api_mp.lua",
        "api_bz.lua", "api_ch.lua", "api_dev.lua", "admin_login.html"]
OPTIONAL = ["reset_button.lua", "sound.mp3", "audio.mp3"]
GZIPPED = ["admin.html", "admin.js", "style.css", "portal_war.html"]
# game pages (html/game_*.html) are sent gzipped too - no {{tokens}} in them
GZIPPED += sorted(os.path.basename(f) for f in glob.glob(os.path.join(ROOT, "html", "game_*.html")))
NO_MINIFY = ["config.lua"]       # kept readable: settings you edit by hand
# --lfs: these modules go into lfs.img (run from flash) instead of .lua/.lc files
LFS_MODS = ["cp_util", "cp_cfg", "cp_dns", "cp_http", "cp_login", "cp_probe", "adm_route", "captive_portal",
            "adm_page", "adm_set", "adm_file", "adm_exec", "adm_scan",
            "api_gb", "api_px", "api_mp", "api_bz", "api_ch", "api_dev"]
LUAC_CROSS = os.environ.get("LUAC_CROSS") or os.path.join(ROOT, "tools", "luac.cross")

# luamin's library (its CLI's stdin handling is awkward); one node run for all.
# luamin drops "redundant" parentheses, so `return (f())` becomes `return f()`
# (all values, not one) - write `local r = f() return r` in the sources instead.
MINIFY_JS = r"""
const fs = require("fs"), path = require("path"), lm = require("luamin");
const [out, ...files] = process.argv.slice(1);
for (const f of files)
  fs.writeFileSync(path.join(out, path.basename(f)), lm.minify(fs.readFileSync(f, "utf8")) + "\n");
"""

# Runs the bundled nodemcu-uploader with a serial port that opens with RTS/DTR
# held inactive. pyserial asserts both on open; on adapters where they drive
# RST/GPIO0 that resets the board (or drops it into flash mode) right before
# the uploader tries to sync -> "Device not found". Vendored code stays as is.
BOOTSTRAP = r"""
import sys, serial
_S = serial.Serial
class QuietSerial(_S):
    def __init__(self, port=None, *a, **k):
        _S.__init__(self, None, *a, **k)
        self.dtr = False
        self.rts = False
        if port:
            self.port = port
            self.open()
    def setRTS(self, v=True): pass
    def setDTR(self, v=True): pass
serial.Serial = QuietSerial
from nodemcu_uploader.main import main_func
sys.argv = ["nodemcu-uploader"] + sys.argv[1:]
main_func()
"""


def find_port():
    for pat in ("/dev/cu.usbserial*", "/dev/cu.SLAB*", "/dev/cu.wchusb*",
                "/dev/ttyUSB*", "/dev/ttyACM*"):
        hits = sorted(glob.glob(pat))
        if hits:
            return hits[0]
    return None


def minify(names, tmp):
    """Minify the given .lua files into tmp; returns the set that worked."""
    try:
        groot = subprocess.run(["npm", "root", "-g"], capture_output=True, text=True).stdout.strip()
        env = dict(os.environ, NODE_PATH=groot)
        r = subprocess.run(["node", "-e", MINIFY_JS, tmp] + [src(n) for n in names],
                           env=env, capture_output=True, text=True)
    except OSError as e:
        print("!! luamin skipped (" + str(e) + ") - uploading plain Lua")
        return set()
    if r.returncode != 0:
        print("!! luamin failed - uploading plain Lua\n" + r.stderr.strip()[-300:])
        return set()
    return set(names)


def build_lfs(tmp, do_minify=True):
    """Compile LFS_MODS (minified) into tmp/lfs.img with luac.cross."""
    lsrc = os.path.join(tmp, "lfs_src")
    os.makedirs(lsrc)
    names = [m + ".lua" for m in LFS_MODS]
    small = minify(names, lsrc) if do_minify else set()
    files = [os.path.join(lsrc, n) if n in small else src(n) for n in names]
    img = os.path.join(tmp, "lfs.img")
    r = subprocess.run([LUAC_CROSS, "-f", "-o", img] + files, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("luac.cross failed:\n" + r.stdout + r.stderr)
    print("    lfs.img: %d bytes from %d modules" % (os.path.getsize(img), len(files)))
    return img


def file_specs(only, tmp, do_minify=True, lfs=False):
    """nodemcu-uploader 'local[:remote]' specs, in upload order."""
    plain = CORE + sorted(glob.glob(os.path.join(ROOT, "html", "login*.html")) +
                          glob.glob(os.path.join(ROOT, "html", "portal_*.html")))
    plain = [os.path.basename(f) for f in plain if os.path.basename(f) not in GZIPPED]
    if lfs:   # modules travel inside lfs.img instead
        plain = [n for n in plain if n[:-4] not in LFS_MODS]
    plain += [f for f in OPTIONAL if os.path.exists(src(f))]
    plain = [n for n in plain if not only or n in only]
    lua = [n for n in plain if n.endswith(".lua") and n not in NO_MINIFY]
    small = minify(lua, tmp) if do_minify and lua else set()
    specs = []
    for name in plain:
        specs.append((os.path.join(tmp, name) if name in small else src(name)) + ":" + name)
    for name in GZIPPED:
        if only and name not in only and name + ".gz" not in only:
            continue
        gz = os.path.join(tmp, name + ".gz")
        with open(src(name), "rb") as fin, \
                gzip.GzipFile(gz, "wb", compresslevel=9, mtime=0) as dst:
            dst.write(fin.read())
        specs.append(gz + ":" + name + ".gz")
    if lfs:
        specs.append(build_lfs(tmp, do_minify) + ":lfs.img")
    return specs


# Loads lfs.img into the LFS region and waits for the reboot + portal start.
RELOAD = r"""
import sys, time, serial
s = serial.Serial(); s.port, s.baudrate, s.timeout = sys.argv[1], int(sys.argv[2]), 0.5
s.dtr = False; s.rts = False; s.open()
s.write(b"\r\n"); time.sleep(0.3); s.reset_input_buffer()
s.write(b'(node.LFS and node.LFS.reload or node.flashreload)("lfs.img")\r\n')
buf, t0 = b"", time.time()
while time.time() - t0 < 40 and b"Portal ready" not in buf and b"PANIC" not in buf:
    buf += s.read(256)
txt = buf.decode("latin-1")
for l in txt.splitlines():
    if any(w in l for w in ("LFS", "rror", "Portal", "PANIC", "Free heap")):
        print("    " + l.strip())
sys.exit(0 if "Portal ready" in txt else 1)
"""


def lfs_reload(port, baud, env):
    return subprocess.call([sys.executable, "-c", RELOAD, port, str(baud)], cwd=ROOT, env=env) == 0


def uploaded(upload_args):
    """Remote names from an 'upload ...' argument list."""
    return [s.split(":")[-1] for s in upload_args[1:]]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-p", "--port", default=os.environ.get("ESPTOOL_PORT") or find_port())
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("--only", nargs="+", metavar="FILE", help="upload only these files")
    ap.add_argument("--no-minify", action="store_true", help="upload Lua as written (no luamin)")
    ap.add_argument("--lfs", action="store_true",
                    help="put the modules into lfs.img and load it (LFS firmware + tools/luac.cross)")
    ap.add_argument("--no-restart", action="store_true", help="don't restart afterwards")
    ap.add_argument("--dry-run", action="store_true", help="print the commands only")
    a = ap.parse_args()

    if not a.port and not a.dry_run:
        sys.exit("No serial port found - plug the board in or pass -p PORT")
    if not os.path.isdir(os.path.join(VENDOR, "nodemcu_uploader")):
        sys.exit("Bundled nodemcu-uploader missing: " + VENDOR)
    if a.lfs and not os.access(LUAC_CROSS, os.X_OK):
        sys.exit("--lfs needs luac.cross from the same firmware build: " + LUAC_CROSS)

    env = dict(os.environ, PYTHONPATH=VENDOR + os.pathsep + os.environ.get("PYTHONPATH", ""))
    base = [sys.executable, "-c", BOOTSTRAP, "--port", a.port or "PORT",
            "--baud", str(a.baud), "--start_baud", str(a.baud),
            "--timeout", "20"]   # slow flash ops (e.g. big files) can exceed the 5 s default

    with tempfile.TemporaryDirectory() as tmp:
        steps = [("Uploading", ["upload"] + file_specs(a.only, tmp, not a.no_minify, a.lfs))]
        if not a.only or any(f in a.only for f in GZIPPED):
            # plain copies from an older upload would only waste flash
            steps.append(("Removing plain " + "/".join(GZIPPED), ["file", "remove"] + GZIPPED))
        if a.lfs:
            # modules now live in LFS: their .lua/.lc files would only waste flash
            steps.append(("Removing module .lua/.lc (now in LFS)", ["file", "remove"] +
                          [m + ext for m in LFS_MODS for ext in (".lua", ".lc")]))
            # sent directly (nodemcu-uploader's exec is broken on Python 3)
            steps.append(("Loading lfs.img into flash (reboots)", ["@lfs_reload"]))
        else:
            # drop old .lc so init.lua recompiles on the next (fresh) boot: big
            # modules can't compile while the portal runs (not enough heap)
            mods = [os.path.splitext(f)[0] + ".lc" for f in uploaded(steps[0][1]) if f.endswith(".lua")
                    and f not in ("init.lua", "config.lua", "reset_button.lua")]
            if mods:
                steps.append(("Removing old .lc (recompiled at boot)", ["file", "remove"] + mods))
        if not a.no_restart and not a.lfs:
            steps.append(("Restarting", ["node", "restart"]))

        for title, args in steps:
            print("==> " + title)
            if args[0] == "@lfs_reload":
                if a.dry_run:
                    print("    send: node.LFS.reload('lfs.img')  (node.flashreload on older fw)")
                elif not lfs_reload(a.port, a.baud, env):
                    sys.exit("Failed: " + title)
                continue
            cmd = base + args
            if a.dry_run:
                print("    nodemcu-uploader " + " ".join(cmd[3:]))
                continue
            if subprocess.call(cmd, cwd=ROOT, env=env) != 0:
                sys.exit("Failed: " + title)

    if not a.dry_run:
        print("Done. Join the AP, then open http://192.168.1.1/admin")


if __name__ == "__main__":
    main()
