#!/usr/bin/env python3
"""WRECKSMITH packaging: the game exported and packed for Steam, and for people who do not have Steam.

    python tools/package.py                       everything the checkout can build (see below)
    python tools/package.py --channel standalone  only the downloads for people without Steam (the demo and the full game)
    python tools/package.py --channel steam --steam-editions demo --platforms windows
    python tools/package.py --skip-export         pack again what is already in build/ (new Steam ids, say)
    python tools/package.py --install-templates   fetch the export templates it needs (only those, not 1.3 GB)

Two channels, each for the full game and for the demo (the same game with the "demo" feature, scripts/game/edition.gd):

  steam       dist/steam/content/<edition>/<platform>/   exactly what goes into each Steam depot, plus the SteamPipe
              scripts (dist/steam/scripts/*.vdf: the real build, and a "preview" one that uploads nothing) and
              upload.bat / upload.sh. Steam's App and depot ids come from tools/steam/steam_ids.json.
  standalone  dist/standalone/: a zip (Windows), a tar.gz (Linux), a zip with the .app (macOS) and a Windows installer
              (a Setup.exe, made with NSIS: on Windows it is fetched for you the first time, 2 MB), for people who
              download the game and try it without Steam. These builds never start Steam (the "standalone" feature,
              scripts/net/net.gd), and have no Steam library.

It needs Godot 4.7 with its export templates (Editor > Manage Export Templates, or --install-templates), and the
voxel core library for each platform (native/bin/; macOS's is only built on a Mac, by the Builds workflow). Python
3.8+, no packages. dist/PACKAGE_REPORT.md says what was built, how big, the checksums and what is still to do.
"""
import argparse
import configparser
import datetime
import hashlib
import io
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = ("windows", "linux", "macos")
EDITIONS = ("demo", "full")
CHANNELS = ("steam", "standalone")
GODOT_PLATFORM = {"Windows Desktop": "windows", "Linux": "linux", "macOS": "macos"}
# What each platform's release export needs in the export templates folder.
TEMPLATE_FILES = {"windows": ["windows_release_x86_64.exe", "windows_release_x86_64_console.exe"],
                  "linux": ["linux_release.x86_64"], "macos": ["macos.zip"]}
TITLE = {"full": "WRECKSMITH", "demo": "WRECKSMITH Demo"}
SLUG = {"full": "WRECKSMITH", "demo": "WRECKSMITH-Demo"}
JUNK = ("steam_appid.txt", ".DS_Store", "Thumbs.db")
JUNK_SUFFIX = (".pdb", ".debug", ".dSYM")
LICENSES_FILE = "THIRD_PARTY_LICENSES.txt"       # in every package, beside the game: the licences of what it is made with
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


class Fail(Exception):
    """Something the packager cannot go on without; the message says what to do."""


# ---------- small helpers ----------

def say(msg=""):
    print(msg, flush=True)


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return "%d %s" % (n, unit) if unit == "B" else "%.1f %s" % (n, unit)
        n /= 1024.0


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd, cwd=None, timeout=None, env=None):
    """(exit code, output) of a command, its error output folded in; a timeout is exit code -1."""
    try:
        p = subprocess.run([str(c) for c in cmd], cwd=str(cwd) if cwd else None, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=timeout, env=env)
        return p.returncode, ANSI.sub("", p.stdout.decode("utf-8", "replace"))
    except subprocess.TimeoutExpired as e:
        return -1, ANSI.sub("", (e.stdout or b"").decode("utf-8", "replace")) + "\nTIMED OUT after %s s" % timeout
    except OSError as e:
        return -2, "could not run %s: %s" % (cmd[0], e)


def error_lines(text):
    """The lines of an engine's output that are errors (Godot prints ERROR: / SCRIPT ERROR: / USER ERROR:)."""
    return [l.strip() for l in text.splitlines() if re.match(r"\s*(SCRIPT |USER |)ERROR:", l)]


def write_file(path, text, newline="\n"):
    """Text to a file as UTF-8 with the given line ending (Path.write_text has no newline argument before Python 3.10)."""
    with open(str(path), "w", encoding="utf-8", newline=newline) as f:
        f.write(text)


NSIS_VERSION = "3.10"
NSIS_URL = "https://downloads.sourceforge.net/project/nsis/NSIS%%203/%s/nsis-%s.zip" % (NSIS_VERSION, NSIS_VERSION)
# The portable zip as nsis.sourceforge.io serves it (2,358,406 bytes; the MD5 SourceForge lists for it is e3e2803a13ead75e4471a51069d04c20).
NSIS_SHA256 = "fcdce3229717a2a148e7cda0ab5bdb667f39d8fb33ede1da8dabc336bd5ad110"


def cache_dir():
    """Where the packager keeps what it fetches for itself: the user's cache, not the checkout (--clean empties build/ and dist/)."""
    if sys.platform.startswith("win"):
        base = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Caches"
    else:
        base = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return base / "WRECKSMITH" / "tools"


def find_makensis():
    """NSIS's compiler: on the PATH, where its Windows installer puts it, or where fetch_nsis unpacked it (Windows)."""
    found = shutil.which("makensis")
    if found:
        return found
    for var in ("ProgramFiles(x86)", "ProgramFiles"):
        base = os.environ.get(var)
        if base and (Path(base) / "NSIS" / "makensis.exe").exists():
            return str(Path(base) / "NSIS" / "makensis.exe")
    cached = cache_dir() / ("nsis-%s" % NSIS_VERSION) / "makensis.exe"
    if sys.platform.startswith("win") and cached.exists():
        return str(cached)
    return None


def extract_safely(zf, dest):
    """Extract a zip, refusing any entry that would land outside `dest` (a "zip slip")."""
    root = os.path.realpath(str(dest))
    for info in zf.infolist():
        target = os.path.realpath(os.path.join(root, info.filename))
        if target != root and not target.startswith(root + os.sep):
            raise Fail("the archive holds an entry outside its folder (%s): not unpacking it" % info.filename)
    zf.extractall(str(dest))


def fetch_nsis(url=None, sha=None, base=None):
    """Download NSIS's portable zip (2 MB), check its checksum and unpack it into the user's cache; the path of its makensis.exe.
    Nothing is installed: no administrator, no registry, nothing outside the cache folder."""
    import urllib.request
    url, sha = url or NSIS_URL, sha or NSIS_SHA256
    base = Path(base) if base else cache_dir()
    base.mkdir(parents=True, exist_ok=True)
    part = base / ("nsis-%s.zip.part" % NSIS_VERSION)
    problem = None
    for attempt in range(3):        # a mirror can be down or serve a page instead of the file: the next try may land on another
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "WRECKSMITH-packager"})
            with urllib.request.urlopen(req, timeout=60) as r, open(str(part), "wb") as out:
                shutil.copyfileobj(r, out, 1 << 20)
        except OSError as e:
            problem = "could not download %s: %s" % (url, e)
        else:
            got = sha256(part)
            if got == sha:
                problem = None
                break
            problem = "the download has the wrong checksum (%s, expected %s)" % (got[:16], sha[:16])
        time.sleep(2 * (attempt + 1))
    if problem:
        if part.exists():
            part.unlink()
        raise Fail("NSIS: %s" % problem)
    tmp = base / ("nsis-%s.unpacking" % NSIS_VERSION)
    if tmp.exists():
        shutil.rmtree(str(tmp))
    try:
        with zipfile.ZipFile(str(part)) as z:
            extract_safely(z, tmp)
        inner = tmp / ("nsis-%s" % NSIS_VERSION)
        if not (inner / "makensis.exe").exists():
            raise Fail("NSIS: the zip does not hold nsis-%s/makensis.exe" % NSIS_VERSION)
        target = base / ("nsis-%s" % NSIS_VERSION)
        if target.exists():
            shutil.rmtree(str(target))
        inner.replace(target)
    finally:
        shutil.rmtree(str(tmp), ignore_errors=True)
        if part.exists():
            part.unlink()
    return str(target / "makensis.exe")


def link_or_copy(src, dst):
    """A hard link where the disk allows it (the staged builds are big), else a copy."""
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def fresh_dir(path):
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)
    return path


# ---------- the project ----------

class Preset:
    def __init__(self, name, platform, edition, channel, path, features, exclude="", options=None):
        self.name, self.platform, self.edition, self.channel, self.path, self.features = name, platform, edition, channel, path, features
        self.exclude = [x.strip() for x in exclude.split(",") if x.strip()]
        self.options = options or {}      # the preset's [preset.N.options] (icon, product name, version...), quotes removed

    @property
    def exe(self):
        return Path(self.path).name

    def __repr__(self):
        return "Preset(%s: %s/%s/%s -> %s)" % (self.name, self.channel, self.edition, self.platform, self.path)


def read_presets(root=ROOT):
    """The export presets of export_presets.cfg, each as (edition, channel, platform) from its features and platform."""
    cp = configparser.RawConfigParser(strict=False)
    cp.optionxform = str
    cp.read(str(Path(root) / "export_presets.cfg"), encoding="utf-8")
    out = []
    for sec in cp.sections():
        if not re.fullmatch(r"preset\.\d+", sec):
            continue
        def get(k, d=""):
            return cp.get(sec, k, fallback=d).strip().strip('"')
        plat = GODOT_PLATFORM.get(get("platform"))
        if plat is None:
            continue
        feats = set(f for f in get("custom_features").split(",") if f)
        opts = {k: v.strip().strip('"') for k, v in cp.items(sec + ".options")} if cp.has_section(sec + ".options") else {}
        out.append(Preset(get("name"), plat, "demo" if "demo" in feats else "full", "standalone" if "standalone" in feats else "steam",
                          get("export_path"), feats, get("exclude_filter"), opts))
    return out


def find_preset(presets, edition, channel, platform):
    hit = [p for p in presets if (p.edition, p.channel, p.platform) == (edition, channel, platform)]
    if len(hit) != 1:
        raise Fail("export_presets.cfg has %d presets for %s / %s / %s (it needs exactly one)" % (len(hit), channel, edition, platform))
    return hit[0]


def project_version(root=ROOT):
    m = re.search(r'^config/version="([^"]*)"', (Path(root) / "project.godot").read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else "0.0"


def git_rev(root=ROOT):
    code, out = run(["git", "rev-parse", "--short", "HEAD"], cwd=root)
    if code != 0:
        return "nogit"
    rev = out.strip().splitlines()[-1]
    code, st = run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=root)
    return rev + ("-dirty" if code == 0 and st.strip() else "")


def extension_libraries(ext, root=ROOT):
    """{platform: [paths]} of the libraries one .gdextension file loads (its [libraries] section)."""
    ext = Path(ext)
    libs = {p: [] for p in PLATFORMS}
    if not ext.exists():
        return libs
    in_libs = False
    for line in ext.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("["):
            in_libs = line == "[libraries]"
            continue
        m = re.match(r'(\w+)(?:\.[\w.]+)?\s*=\s*"res://([^"]+)"', line)
        if in_libs and m and m.group(1) in libs:
            libs[m.group(1)].append(Path(root) / m.group(2))
    return libs


def native_libraries(root=ROOT):
    """{platform: [paths]} of the voxel core libraries native/voxel_core.gdextension loads."""
    return extension_libraries(Path(root) / "native" / "voxel_core.gdextension", root)


def platforms_with_library(root=ROOT):
    libs = native_libraries(root)
    return [p for p in PLATFORMS if libs[p] and all(x.exists() for x in libs[p])]


# ---------- Linux libraries: the oldest system they must run on ----------

# What a Linux game on Steam may ask of the system: Steam runs it in the Steam Linux Runtime 3.0 "sniper" (Debian 11),
# which has glibc 2.31 and GCC 10's C++ library. A library built on a newer system (say Ubuntu 22.04: glibc 2.35) names
# newer versions in its needs and does not load there: the game then starts with no voxel core, or not at all.
STEAM_RUNTIME_LIMITS = {"GLIBC": (2, 31), "GLIBCXX": (3, 4, 28), "CXXABI": (1, 3, 12)}


def elf_version_needs(path):
    """{'GLIBC': (2, 27), 'GLIBCXX': (3, 4, 26), ...}: the newest version of each system library an ELF 64-bit little-endian
    file asks for (its .gnu.version_r). {} when it asks for none, or is not such a file. Pure Python, so it runs anywhere."""
    with open(str(path), "rb") as f:
        head = f.read(64)
        if len(head) < 64 or head[:4] != b"\x7fELF" or head[4] != 2 or head[5] != 1:
            return {}
        shoff = struct.unpack_from("<Q", head, 0x28)[0]
        shentsize, shnum = struct.unpack_from("<HH", head, 0x3A)
        if not shoff or not shnum or shentsize < 64:
            return {}
        f.seek(shoff)
        table = f.read(shentsize * shnum)
        # Each section header: name, type, flags, addr, offset, size, link, info, align, entry size.
        secs = [struct.unpack_from("<IIQQQQIIQQ", table, i * shentsize) for i in range(shnum)]
        found = {}
        for sec in secs:
            if sec[1] != 0x6ffffffe:                 # SHT_GNU_verneed
                continue
            f.seek(sec[4])
            data = f.read(sec[5])
            link = secs[sec[6]]
            f.seek(link[4])
            strs = f.read(link[5])
            pos = 0
            for _ in range(sec[7]):                  # sh_info: how many files it needs versions of
                _ver, cnt, _file, aux, nxt = struct.unpack_from("<HHIII", data, pos)
                apos = pos + aux
                for _ in range(cnt):
                    _hash, _flags, _other, nameoff, anext = struct.unpack_from("<IHHII", data, apos)
                    name = strs[nameoff:strs.index(b"\0", nameoff)].decode("ascii", "replace")
                    m = re.fullmatch(r"(GLIBCXX|GLIBC|CXXABI)_(\d+(?:\.\d+)+)", name)
                    if m:
                        v = tuple(int(x) for x in m.group(2).split("."))
                        if v > found.get(m.group(1), ()):
                            found[m.group(1)] = v
                    if not anext:
                        break
                    apos += anext
                if not nxt:
                    break
                pos += nxt
        return found


def too_new_for_steam(path):
    """What an ELF file asks for that the Steam Linux Runtime does not have, as readable lines ([] when it is fine)."""
    try:
        needs = elf_version_needs(path)
    except (OSError, ValueError, IndexError, struct.error):
        return []
    return ["%s_%s (the Steam Linux Runtime has %s)" % (k, ".".join(map(str, v)), ".".join(map(str, STEAM_RUNTIME_LIMITS[k])))
            for k, v in sorted(needs.items()) if v > STEAM_RUNTIME_LIMITS[k]]


# ---------- Steam's two GDExtensions: GodotSteam, and the multiplayer peer ----------

def is_steam_peer(name):
    """SteamMultiplayerPeer's folder (steam_multiplayer_peer, godotsteam_multiplayerpeer...), not GodotSteam's own."""
    n = name.lower()
    return "multiplayer" in n or "peer" in n


def addon_name(ext):
    """The folder an addon has to sit in: the one its own paths name (res://addons/<name>/...), else its .gdextension's name."""
    names = re.findall(r"res://addons/([^/\"']+)/", Path(ext).read_text(encoding="utf-8", errors="replace"))
    return max(set(names), key=names.count) if names else Path(ext).stem


def find_addons(src):
    """{addon folder name: the folder to copy} for every GDExtension in an unpacked download (the shallowest one of a name)."""
    src = Path(src)
    found = {}
    for ext in sorted(src.rglob("*.gdextension"), key=lambda p: (len(p.parts), str(p))):
        name = addon_name(ext)
        folder = ext.parent
        for up in [folder] + list(folder.parents):       # the .gdextension may sit deeper than addons/<name>/
            if up.name == name:
                folder = up
                break
            if up == src:
                break
        found.setdefault(name, folder)
    return found


def steam_addons(root=ROOT):
    """{addon folder name: its .gdextension} of what addons/ holds."""
    out = {}
    for ext in sorted((Path(root) / "addons").glob("*/*.gdextension")):
        out.setdefault(ext.parent.name, ext)
    return out


def steam_addons_missing(root=ROOT):
    """What the Steam builds still lack of Steam's two extensions, in words; [] when both are in addons/."""
    names = list(steam_addons(root))
    miss = []
    if not any("godotsteam" in n.lower() and not is_steam_peer(n) for n in names):
        miss.append("GodotSteam (the overlay, lobbies, rich presence, achievements and cloud saves)")
    if not any(is_steam_peer(n) for n in names):
        miss.append("the Steam multiplayer peer (SteamMultiplayerPeer: playing together through Steam's lobbies)")
    return miss


def addon_licences(root):
    """[(addon name, text)]: the licence files that came with the extensions in addons/ (LICENSE, LICENCE, COPYING, NOTICE)."""
    out = []
    for name, ext in steam_addons(root).items():
        for f in sorted(ext.parent.iterdir()):
            if f.is_file() and re.match(r"(?i)(licen[sc]e|copying|notice)", f.name):
                out.append((name, f.read_text(encoding="utf-8", errors="replace").strip()))
    return out


def copyright_holder(root=ROOT):
    """The holder named in data/legal.json for the Credits screen's © line ('' while the owner has not said)."""
    try:
        return str(json.loads((Path(root) / "data" / "legal.json").read_text(encoding="utf-8")).get("holder", "")).strip()
    except (OSError, ValueError):
        return ""


def steam_depot_gaps(root, platform, depot):
    """What a Steam depot of this platform lacks of the Steam extensions that are in addons/: file names. The extension's own
    release library and Steam's (steam_api64.dll / libsteam_api.so) must be beside the game's program."""
    have = {p.name for p in Path(depot).rglob("*") if p.is_file()}
    lacking = []
    for name, ext in steam_addons(root).items():
        for lib in extension_libraries(ext, root)[platform]:
            if ".release." in lib.name or ".template_release." in lib.name:
                if lib.name not in have and lib.name not in lacking and lib.exists():
                    lacking.append(lib.name)
    api = {"windows": "steam_api64.dll", "linux": "libsteam_api.so"}.get(platform)
    if api and steam_addons(root) and api not in have:
        lacking.append(api)
    return lacking


# ---------- Godot and its export templates ----------

def parse_godot_version(text):
    """'4.7.2.stable.official.ed1daf0bf' -> '4.7.2.stable' (the export templates folder's name; '.mono' kept)."""
    parts = text.strip().split(".")
    out = []
    for i, p in enumerate(parts):
        out.append(p)
        if re.fullmatch(r"[a-z]+\d*", p) and i >= 2:
            if i + 1 < len(parts) and parts[i + 1] == "mono":
                out.append("mono")
            break
    return ".".join(out)


def find_godot(explicit=None):
    cands = []
    if explicit:
        cands.append(Path(explicit))
    if os.environ.get("GODOT"):
        cands.append(Path(os.environ["GODOT"]))
    for n in ("godot", "godot4"):
        w = shutil.which(n)
        if w:
            cands.append(Path(w))
    homes = [ROOT, ROOT.parent, Path("/opt/godot"), Path("D:/godot"), Path("C:/godot"), Path.home() / "Downloads", Path.home() / "Desktop"]
    for d in homes:
        if d.is_dir():
            cands += sorted(d.glob("Godot_v4.7*")) + sorted(d.glob("Godot*/Godot_v4.7*"))
    for c in cands:
        if c.is_file() and not c.name.endswith((".zip", ".tpz")):
            # On Windows the *_console.exe prints to the terminal; the plain one does not.
            if sys.platform.startswith("win") and "console" not in c.name.lower():
                con = c.with_name(c.stem + "_console" + c.suffix)
                if con.exists():
                    return con
            return c
    raise Fail("Godot 4.7 not found. Put its path in the GODOT variable or pass --godot PATH "
               "(download: https://godotengine.org/download).")


def godot_version(godot):
    code, out = run([godot, "--version"], timeout=60)
    if code != 0:
        raise Fail("could not run %s --version: %s" % (godot, out.strip()[:200]))
    return parse_godot_version(out.strip().splitlines()[-1])


def templates_dir(version):
    if sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming") / "Godot"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share") / "godot"
    return base / "export_templates" / version


def missing_templates(version, platforms):
    d = templates_dir(version)
    return [(p, f) for p in platforms for f in TEMPLATE_FILES[p][:1] if not (d / f).exists()]


class HttpRange(io.RawIOBase):
    """A file on a web server read by range requests, so a zip can be opened without downloading all of it."""

    BLOCK = 8 << 20

    def __init__(self, url):
        import urllib.request
        self._ur = urllib.request
        req = self._ur.Request(url, method="HEAD")
        with self._ur.urlopen(req, timeout=60) as r:
            self.url = r.geturl()
            self.size = int(r.headers["Content-Length"])
            if r.headers.get("Accept-Ranges", "").lower() != "bytes":
                raise Fail("%s does not take range requests" % url)
        self.pos = 0
        self.cache = {}

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def _block(self, i):
        if i not in self.cache:
            a = i * self.BLOCK
            b = min(self.size, a + self.BLOCK) - 1
            req = self._ur.Request(self.url, headers={"Range": "bytes=%d-%d" % (a, b)})
            with self._ur.urlopen(req, timeout=120) as r:
                data = r.read()
            if len(data) != b - a + 1:
                raise IOError("short range read %d-%d (got %d bytes)" % (a, b, len(data)))
            if len(self.cache) > 4:
                self.cache.pop(next(iter(self.cache)))
            self.cache[i] = data
        return self.cache[i]

    def readinto(self, buf):
        n = min(len(buf), self.size - self.pos)
        got = 0
        while got < n:
            i = (self.pos + got) // self.BLOCK
            blk = self._block(i)
            off = (self.pos + got) - i * self.BLOCK
            take = min(n - got, len(blk) - off)
            buf[got:got + take] = blk[off:off + take]
            got += take
        self.pos += n
        return n


def install_templates(version, platforms):
    """Put the release templates of `platforms` into Godot's templates folder, taken out of the official archive."""
    m = re.fullmatch(r"(\d+\.\d+(?:\.\d+)?)\.stable", version)
    if not m:
        raise Fail("--install-templates only knows stable releases (this is %s): install the templates in the editor." % version)
    num = m.group(1)
    url = os.environ.get("TPZ_URL") or "https://github.com/godotengine/godot/releases/download/%s-stable/Godot_v%s-stable_export_templates.tpz" % (num, num)
    dest = templates_dir(version)
    dest.mkdir(parents=True, exist_ok=True)
    say("Reading the template archive (only the parts needed are downloaded): %s" % url)
    z = zipfile.ZipFile(io.BufferedReader(HttpRange(url), buffer_size=8 << 20))
    names = ["version.txt"] + [f for p in platforms for f in TEMPLATE_FILES[p]]
    for name in names:
        info = z.getinfo("templates/" + name)
        out = dest / name
        if out.exists() and out.stat().st_size == info.file_size:
            say("  have %s" % name)
            continue
        say("  getting %s (%s)" % (name, human(info.file_size)))
        tmp = out.with_name(out.name + ".part")
        with z.open(info) as src, open(str(tmp), "wb") as dst:
            shutil.copyfileobj(src, dst, 1 << 20)
        tmp.replace(out)
        if not name.endswith((".txt", ".zip")):
            out.chmod(0o755)
    say("Templates are in %s" % dest)


# ---------- Steam: ids, SteamPipe scripts ----------

def vdf(pairs, depth=0):
    """Valve's text format from a list of (key, value) where a value is a string or a list of pairs."""
    tab = "\t" * depth
    out = []
    for k, v in pairs:
        if isinstance(v, list):
            out.append('%s"%s"\n%s{\n%s%s}' % (tab, k, tab, vdf(v, depth + 1) + "\n", tab))
        else:
            out.append('%s"%s"\t"%s"' % (tab, k, str(v).replace('"', "'")))
    return "\n".join(out)


def load_steam_ids(root=ROOT):
    p = Path(root) / "tools" / "steam" / "steam_ids.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def steam_platforms(ids):
    """The systems the game is sold for on Steam: steam_ids.json "platforms" (every system when the file says nothing)."""
    got = [p for p in ids.get("platforms", PLATFORMS) if p in PLATFORMS]
    return got or list(PLATFORMS)


def steam_id(ids, edition, what, platform=None):
    """The App id (what='app') or a platform's depot id of an edition; a clear placeholder while it is not set yet."""
    e = ids.get(edition, {})
    v = e.get("app_id") if what == "app" else e.get("depots", {}).get(platform)
    if isinstance(v, int) and v > 0:
        return str(v)
    return "%s_APP_ID" % edition.upper() if what == "app" else "%s_%s_DEPOT_ID" % (edition.upper(), platform.upper())


def app_build_vdf(app_id, desc, edition, depots, preview=False, set_live=""):
    """The SteamPipe app build script. `depots` is a list of (depot id, script file name). Paths are relative to the script."""
    return vdf([("AppBuild", [
        ("AppID", app_id), ("Desc", desc), ("Preview", "1" if preview else "0"), ("SetLive", set_live),
        ("ContentRoot", "../content/%s/" % edition), ("BuildOutput", "../output/"),
        ("Depots", [(d, f) for d, f in depots]),
    ])]) + "\n"


def depot_build_vdf(depot_id, platform):
    return vdf([("DepotBuildConfig", [
        ("DepotID", depot_id),
        ("FileMapping", [("LocalPath", "%s/*" % platform), ("DepotPath", "."), ("recursive", "1")]),
        ("FileExclusion", "*.pdb"),
        ("FileExclusion", "steam_appid.txt"),
    ])]) + "\n"


UPLOAD_BAT = r"""@echo off
rem Uploads a build to Steam with steamcmd (SteamPipe).
rem   upload.bat demo           the demo's build        upload.bat full           the full game's
rem   upload.bat demo preview   same, but nothing is uploaded: it lists what would be (try this first)
rem It asks for your Steam builder account; steamcmd asks for the password and the Steam Guard code itself.
rem steamcmd: the STEAMCMD variable, C:\steamcmd, D:\steamcmd, or steamcmd on the PATH (the Steamworks SDK's
rem tools\ContentBuilder\builder\steamcmd.exe will do).
setlocal
set "ED=%~1"
if "%ED%"=="" goto usage
set "VDF=%~dp0scripts\app_build_%ED%.vdf"
if /i "%~2"=="preview" set "VDF=%~dp0scripts\app_build_%ED%_preview.vdf"
if not exist "%VDF%" goto novdf
findstr /C:"_ID" "%VDF%" >nul
if not errorlevel 1 goto noids
set "SC=%STEAMCMD%"
if "%SC%"=="" if exist "C:\steamcmd\steamcmd.exe" set "SC=C:\steamcmd\steamcmd.exe"
if "%SC%"=="" if exist "D:\steamcmd\steamcmd.exe" set "SC=D:\steamcmd\steamcmd.exe"
if "%SC%"=="" where steamcmd >nul 2>nul && set "SC=steamcmd"
if "%SC%"=="" goto nosteamcmd
set /p ACC=Steam builder account: 
"%SC%" +login %ACC% +run_app_build "%VDF%" +quit
exit /b %ERRORLEVEL%
:usage
echo usage: upload.bat demo^|full [preview]
exit /b 1
:novdf
echo No build script "%VDF%" - did the packaging build the %ED% edition?
exit /b 1
:noids
echo The App and depot ids in "%VDF%" are not filled in yet. Put them in tools\steam\steam_ids.json and run tools\package.bat --skip-export.
exit /b 1
:nosteamcmd
echo steamcmd not found: set the STEAMCMD variable to its steamcmd.exe
exit /b 1
"""

UPLOAD_SH = """#!/bin/sh
# Uploads a build to Steam with steamcmd (SteamPipe).
#   ./upload.sh demo           the demo's build        ./upload.sh full           the full game's
#   ./upload.sh demo preview   same, but nothing is uploaded: it lists what would be (try this first)
# It asks for your Steam builder account; steamcmd asks for the password and the Steam Guard code itself.
# steamcmd: $STEAMCMD, or steamcmd on the PATH. Upload the Linux depot from Linux or macOS, so the
# executable bit of the game's file is kept.
ED=$1
[ -n "$ED" ] || { echo "usage: ./upload.sh demo|full [preview]"; exit 1; }
D=$(cd "$(dirname "$0")" && pwd)
VDF=$D/scripts/app_build_$ED.vdf
[ "$2" = "preview" ] && VDF=$D/scripts/app_build_${ED}_preview.vdf
[ -f "$VDF" ] || { echo "No build script $VDF - did the packaging build the $ED edition?"; exit 1; }
if grep -q "_ID" "$VDF"; then echo "The App and depot ids in $VDF are not filled in yet. Put them in tools/steam/steam_ids.json and run tools/package.py --skip-export."; exit 1; fi
SC=${STEAMCMD:-$(command -v steamcmd)}
[ -n "$SC" ] || { echo "steamcmd not found: set STEAMCMD to it"; exit 1; }
printf "Steam builder account: "; read -r ACC
exec "$SC" +login "$ACC" +run_app_build "$VDF" +quit
"""


# ---------- archives ----------

def file_mode(path):
    """Unix mode to give a packed file: programs (the game, scripts) 755, everything else 644."""
    name = path.name
    if name.endswith((".x86_64", ".sh", ".arm64")) or name == "WRECKSMITH" or name == "WRECKSMITH_Demo":
        return 0o755
    return 0o644


def pack_zip(src_dir, out_file, top):
    """src_dir's files in a zip under the folder `top`, Unix modes kept (a .app's programs stay runnable)."""
    out_file.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(str(out_file), "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for p in sorted(src_dir.rglob("*")):
            rel = "%s/%s" % (top, p.relative_to(src_dir).as_posix())
            if p.is_dir():
                zi = zipfile.ZipInfo(rel + "/")
                zi.external_attr = (0o40755 << 16) | 0x10
                z.writestr(zi, b"")
                continue
            zi = zipfile.ZipInfo(rel, date_time=time.localtime(p.stat().st_mtime)[:6])
            zi.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if (p.stat().st_mode & stat.S_IXUSR or file_mode(p) == 0o755) else 0o644
            zi.external_attr = (0o100000 | mode) << 16
            with open(str(p), "rb") as f, z.open(zi, "w") as w:
                shutil.copyfileobj(f, w, 1 << 20)
    return out_file


def pack_targz(src_dir, out_file, top):
    out_file.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(str(out_file), "w:gz", compresslevel=6) as t:
        def norm(ti):
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = ""
            ti.mode = 0o755 if ti.isdir() else (0o755 if (ti.mode & 0o100 or file_mode(Path(ti.name)) == 0o755) else 0o644)
            return ti
        t.add(str(src_dir), arcname=top, filter=norm)
    return out_file


def unzip_keep_modes(zip_path, dest):
    """Extract a zip with the Unix modes it records (zipfile alone drops them)."""
    with zipfile.ZipFile(str(zip_path)) as z:
        for info in z.infolist():
            target = Path(z.extract(info, str(dest)))
            mode = (info.external_attr >> 16) & 0o7777
            if mode and not info.is_dir():
                target.chmod(mode)


def parse_artifact(name):
    """(edition, version, platform, kind) of a file name made by stage_standalone, else None."""
    m = re.match(r"WRECKSMITH(-Demo)?-(.+?)-(windows|linux|macos)(-setup)?\.(zip|tar\.gz|exe)$", name)
    if not m:
        return None
    return ("demo" if m.group(1) else "full", m.group(2), m.group(3), "installer" if m.group(4) else "archive")


def describe_artifact(name):
    info = parse_artifact(name)
    if not info:
        return name
    ed, ver, pl, kind = info
    return "%s %s, %s%s" % (TITLE[ed], ver, {"windows": "Windows", "linux": "Linux", "macos": "macOS"}[pl], " installer" if kind == "installer" else "")


# ---------- the build ----------

class Packager:
    def __init__(self, args):
        self.a = args
        self.root = ROOT
        self.build = ROOT / "build"
        self.dist = Path(args.out) if os.path.isabs(args.out) else ROOT / args.out
        self.version = args.version or project_version(ROOT)
        self.rev = git_rev(ROOT)
        self.presets = read_presets(ROOT)
        self.notes = []          # warnings for the report
        self.results = []        # (channel, edition, platform, exe path, size, smoke text)
        self.godot = None
        self.gver = None
        self.licenses = {"standalone": None, "steam": None}     # the THIRD_PARTY_LICENSES.txt of each channel, once make_licenses has written them
        self.nsis = False        # NSIS's compiler once ensure_nsis has looked (a path, or None when there is none); False = not looked yet

    # -- setup --

    def warn(self, msg):
        self.notes.append(msg)
        say("WARNING: " + msg)

    def check_setup(self, platforms):
        self.godot = find_godot(self.a.godot)
        self.gver = godot_version(self.godot)
        say("Godot %s (%s)" % (self.gver, self.godot))
        if sys.platform.startswith("win") and "console" not in Path(self.godot).name.lower():
            self.warn("this is Godot's plain exe: it shows no engine messages here, so an export error would be hard to read. "
                      "Godot_v%s-stable_win64_console.exe (in the same zip) shows them: put it beside it, or point GODOT at it." % self.gver.split(".stable")[0])
        if not self.a.skip_export:
            miss = missing_templates(self.gver, platforms)
            cmd = "tools\\package.bat --install-templates" if sys.platform.startswith("win") else "python3 tools/package.py --install-templates"
            if miss and not self.a.install_templates and sys.stdin is not None and sys.stdin.isatty():
                say("Godot's export templates for %s are not installed (%s missing in %s)." % (self.gver, ", ".join(f for _, f in miss), templates_dir(self.gver)))
                try:
                    ans = input("Fetch just the ones needed now (a few tens of MB per system, not the whole 1.3 GB)? [Y/n] ").strip().lower()
                except EOFError:
                    ans = "n"
                self.a.install_templates = ans in ("", "y", "yes")
            if miss and self.a.install_templates:
                install_templates(self.gver, sorted(set(p for p, _ in miss)))
                miss = missing_templates(self.gver, platforms)
            if miss:
                raise Fail("Godot's export templates for %s are not installed (%s missing in %s).\n"
                           "  Run:  %s     (fetches only what is needed)\n"
                           "  or in the Godot editor: Editor > Manage Export Templates > Download and Install (1.3 GB)."
                           % (self.gver, ", ".join(f for _, f in miss), templates_dir(self.gver), cmd))

    def install_steam_addons(self, src):
        """Copy the GDExtensions of a download (a zip, or its folder) into addons/. Steam's two come as two downloads
        (GodotSteam, and the Steam multiplayer peer), each a zip with addons/<name>/<name>.gdextension in it; this takes
        whatever it finds, so it is run once for each (or the one zip, if it holds both)."""
        src = Path(src)
        if not src.exists():
            raise Fail("%s is not there (--godotsteam takes the downloaded zip, or the folder it was unpacked to)" % src)
        tmp = None
        if src.is_file():
            if not zipfile.is_zipfile(str(src)):
                raise Fail("%s is not a zip file (the GodotSteam and the Steam multiplayer peer downloads are zips)" % src)
            tmp = Path(tempfile.mkdtemp(prefix="steam_addons_"))
            with zipfile.ZipFile(str(src)) as z:
                extract_safely(z, tmp)
            src = tmp
        try:
            found = find_addons(src)
            if not found:
                raise Fail("%s holds no GDExtension (no *.gdextension in it): the download has addons/<name>/<name>.gdextension" % src)
            dest = self.root / "addons"
            dest.mkdir(exist_ok=True)
            for name, folder in found.items():
                target = dest / name
                if target.exists():
                    shutil.rmtree(str(target))
                shutil.copytree(str(folder), str(target))
                say("%s copied into %s" % (name, target))
        finally:
            if tmp:
                shutil.rmtree(str(tmp), ignore_errors=True)
        self.need_import = True

    def ensure_imported(self):
        cache = self.root / ".godot" / "global_script_class_cache.cfg"
        if cache.exists() and not getattr(self, "need_import", False):
            return
        say("Importing the project (the first time takes a minute or two)...")
        code, out = run([self.godot, "--headless", "--path", self.root, "--import"], timeout=1800)
        if code != 0:
            raise Fail("importing the project failed (exit %s):\n%s" % (code, "\n".join(out.splitlines()[-15:])))
        errs = error_lines(out)
        if errs:
            self.warn("importing the project printed %d error line(s), the first: %s" % (len(errs), errs[0]))

    # -- export --

    def make_licenses(self):
        """THIRD_PARTY_LICENSES.txt for the packages: the game's credits written by the game itself (`-- --probe licenses_dump`: with the
        Godot that exports it, so the engine's licence terms are those of the build), and for the Steam builds the licence files of the
        extensions in addons/, verbatim. build/THIRD_PARTY_LICENSES.txt for the downloads, build/THIRD_PARTY_LICENSES.steam.txt for Steam."""
        self.licenses = {"standalone": None, "steam": None}
        base = self.build / LICENSES_FILE
        self.build.mkdir(parents=True, exist_ok=True)
        if base.exists():
            base.unlink()
        env = dict(os.environ, LICENSES_OUT=str(base))
        code, out = run([self.godot, "--headless", "--path", self.root, "--", "--probe", "licenses_dump"], timeout=300, env=env)
        errs = error_lines(out)
        if code != 0 or errs or not base.exists():
            msg = "could not write %s (exit %s)%s" % (LICENSES_FILE, code, (": " + "; ".join(errs[:3])) if errs else "")
            if self.a.skip_export:
                self.warn(msg + ": the packages are made without it")
                return
            raise Fail(msg)
        text = base.read_text(encoding="utf-8")
        steam = self.build / "THIRD_PARTY_LICENSES.steam.txt"
        extra = addon_licences(self.root)
        parts = [text.rstrip(), ""]
        for name, lic in extra:
            parts += ["=" * 78, "STEAM EXTENSION: %s" % name.upper(), "=" * 78, "", lic, ""]
        write_file(steam, "\n".join(parts) + "\n")
        self.licenses = {"standalone": base, "steam": steam}
        if not copyright_holder(self.root):
            self.warn("data/legal.json has no copyright holder: the Credits screen and %s have no (c) line. Put the name that should stand "
                      "there (a person or a company) in it, and run again." % LICENSES_FILE)

    def put_licenses(self, kind, dest):
        """The licences file of a package, into the folder that is packed (or uploaded)."""
        src = getattr(self, "licenses", {}).get(kind)
        if src and Path(src).exists():
            shutil.copy2(str(src), str(Path(dest) / LICENSES_FILE))

    def export_dir(self, preset):
        return self.root / Path(preset.path).parent

    def export(self, preset):
        out_dir = self.export_dir(preset)
        exe = out_dir / preset.exe
        if self.a.skip_export:
            if not exe.exists():
                raise Fail("--skip-export, but %s is not there: run without it once." % exe)
            return exe
        fresh_dir(out_dir)
        say("Exporting %-34s -> %s" % (preset.name, Path(preset.path)))
        t0 = time.time()
        code, out = run([self.godot, "--headless", "--path", self.root, "--export-release", preset.name, exe], timeout=1800)
        errs = error_lines(out)
        if code != 0 or errs or not exe.exists():
            tail = "\n".join(out.splitlines()[-12:])
            raise Fail("exporting %r failed (exit %s)%s\n%s" % (preset.name, code, ("\n  " + "\n  ".join(errs[:8])) if errs else "", tail))
        say("    done in %.0f s, %s" % (time.time() - t0, human(sum(p.stat().st_size for p in out_dir.rglob("*") if p.is_file()))))
        return exe

    def smoke(self, preset, exe):
        """Run what can be run on this machine; look inside what cannot. Returns a one-line verdict, or raises Fail."""
        out_dir = exe.parent
        libs = native_libraries(self.root)[preset.platform]
        if preset.platform == "windows":
            with open(str(exe), "rb") as f:
                if f.read(2) != b"MZ":
                    raise Fail("%s is not a Windows program" % exe)
            absent = [l.name for l in libs if not (out_dir / l.name).exists()]
            if absent:
                raise Fail("%s: the voxel core library is not next to the exe: %s" % (preset.name, ", ".join(absent)))
            if sys.platform.startswith("win") and not self.a.skip_tests:
                code, out = run([exe, "--headless", "--quit-after", "150"], cwd=out_dir, timeout=300)
                if code != 0:
                    raise Fail("%s starts badly (exit %s)" % (preset.name, code))
                return "ran headless for 150 frames: exit 0 (a windowed program shows no engine output, so errors would not show here)"
            return "checked (Windows build: the exe and its library are in place; not run on this machine)"
        if preset.platform == "macos":
            with zipfile.ZipFile(str(exe)) as z:
                names = z.namelist()
            if not any(".app/Contents/MacOS/" in n for n in names):
                raise Fail("%s: no program inside the macOS zip" % preset.name)
            if not any(".framework" in n for n in names):
                self.warn("%s: no voxel core framework inside the macOS zip (the game runs without the C++ core, slower)" % preset.name)
            return "checked (macOS build: the .app is in the zip; not run on this machine)"
        absent = [l.name for l in libs if not (out_dir / l.name).exists()]
        if absent:
            raise Fail("%s: the voxel core library is not next to the program: %s" % (preset.name, ", ".join(absent)))
        # Looked at on every system (a file read, no running): does anything ask for more than Steam's Linux runtime has?
        new = ["%s asks for %s" % (p.name, line) for p in sorted(out_dir.iterdir()) if p.is_file() and (p.suffix == ".so" or p == exe)
               for line in too_new_for_steam(p)]
        if new:
            msg = ("%s: this Linux build does not fit Steam's Linux runtime (Debian 11, glibc 2.31): %s. Players on Steam or on an older "
                   "Linux would not get the game started. Rebuild the library on an older system: the Builds workflow does it in "
                   "an Ubuntu 20.04 container (docs/PACKAGING.md)." % (preset.name, "; ".join(new)))
            if preset.channel == "steam":
                raise Fail(msg)
            self.warn(msg)
        fits = "" if new else "asks for no more than glibc %s" % ".".join(map(str, STEAM_RUNTIME_LIMITS["GLIBC"]))
        if self.a.skip_tests:
            return "not run (--skip-tests)" + ("; " + fits if fits else "")
        if not sys.platform.startswith("linux"):
            return "not run (a Linux build, on another system)" + ("; " + fits if fits else "")
        code, out = run([exe, "--headless", "--quit-after", "150"], cwd=out_dir, timeout=300)
        errs = error_lines(out)
        if code != 0 or errs:
            raise Fail("%s starts badly (exit %s):\n  %s" % (preset.name, code, "\n  ".join(errs[:6] or out.splitlines()[-6:])))
        return "ran headless for 150 frames: exit 0, no errors" + ("; " + fits if fits else "")

    # -- steam --

    def stage_steam(self, preset, exe):
        dest = self.dist / "steam" / "content" / preset.edition / preset.platform
        fresh_dir(dest)
        src = exe.parent
        if preset.platform == "macos":
            unzip_keep_modes(exe, dest)
        else:
            for p in sorted(src.rglob("*")):
                rel = p.relative_to(src)
                if p.is_dir():
                    (dest / rel).mkdir(parents=True, exist_ok=True)
                elif p.name not in JUNK and not p.name.endswith(JUNK_SUFFIX):
                    (dest / rel).parent.mkdir(parents=True, exist_ok=True)
                    link_or_copy(p, dest / rel)
        self.put_licenses("steam", dest)
        return dest

    def write_steam_scripts(self, editions_platforms):
        ids = load_steam_ids(self.root)
        sdir = self.dist / "steam"
        scripts = sdir / "scripts"
        scripts.mkdir(parents=True, exist_ok=True)
        lines = []
        for ed, plats in editions_platforms.items():
            depots = []
            for pl in plats:
                did = steam_id(ids, ed, "depot", pl)
                fname = "depot_%s_%s.vdf" % (ed, pl)
                write_file(scripts / fname, depot_build_vdf(did, pl))
                depots.append((did, fname))
            app = steam_id(ids, ed, "app")
            desc = "%s %s (%s)" % (TITLE[ed], self.version, self.rev)
            for preview in (False, True):
                name = "app_build_%s%s.vdf" % (ed, "_preview" if preview else "")
                write_file(scripts / name, app_build_vdf(app, desc + (" preview" if preview else ""), ed, depots, preview=preview))
            if app.endswith("_APP_ID") or any(d.endswith("_DEPOT_ID") for d, _ in depots):
                self.warn("Steam ids for the %s are not set in tools/steam/steam_ids.json: its scripts hold placeholders "
                          "(fill them in and run again with --skip-export)." % ed)
        write_file(sdir / "upload.bat", UPLOAD_BAT, "\r\n")
        sh = sdir / "upload.sh"
        write_file(sh, UPLOAD_SH)
        sh.chmod(0o755)
        for ed, plats in editions_platforms.items():
            for pl in plats:
                exe = find_preset(self.presets, ed, "steam", pl).exe
                lines.append("  %-14s %-8s  launch option: %s" % (TITLE[ed], pl, exe if pl != "macos" else "%s.app" % Path(exe).stem))
        readme = [
            "WRECKSMITH for Steam: %s, build %s" % (self.version, self.rev), "",
            "content/<edition>/<platform>/   what goes into each Steam depot (nothing else; no steam_appid.txt)",
            "scripts/                        the SteamPipe build scripts (ids from tools/steam/steam_ids.json)",
            "upload.bat / upload.sh          run steamcmd on them:  upload.bat demo preview   (lists the files, uploads nothing)",
            "                                                        upload.bat demo           (the real upload)", "",
            "Steamworks > Installation > General > Launch Options, one per depot's system:", *lines, "",
            "Steam Cloud, achievements, store page: docs/PACKAGING.md and docs/DEMO.md.",
        ]
        write_file(sdir / "README.txt", "\n".join(readme) + "\n")

    # -- standalone --

    def readme_text(self, edition, platform):
        demo = edition == "demo"
        run_line = {"windows": "Double-click %s.exe (Windows may warn that the publisher is unknown: choose More info, then Run anyway)." % SLUG[edition].replace("-", "_"),
                    "linux": "Run ./%s.x86_64 (make it executable first if your system lost the flag: chmod +x)." % SLUG[edition].replace("-", "_"),
                    "macos": "Open %s.app (the first time: right-click it and choose Open; the game is not signed)." % SLUG[edition].replace("-", "_")}[platform]
        what = ("The free demo: the campaign's first eight bouts up to the second boss, the arena (duel, best of three, free-for-all, "
                "the endless arena), training, the forge, the armourer's bench and the yard." if demo else "The full game.")
        return "\n".join([
            "%s %s" % (TITLE[edition], self.version), "=" * (len(TITLE[edition]) + len(self.version) + 1), "",
            what, "",
            "Start", "-----", run_line, "Keep all the files of this folder together: the game needs the library file beside it.", "",
            "This is the download for people without Steam. It never connects to Steam. Playing with friends is by address:",
            "one player hosts a room (UDP port 7777), the others join with the host's address. The Steam version adds Steam",
            "lobbies, the overlay, achievements and cloud saves.", "",
            "Your saves and settings are in the game's user folder:",
            "  Windows  %APPDATA%\\Godot\\app_userdata\\WRECKSMITH",
            "  Linux    ~/.local/share/godot/app_userdata/WRECKSMITH",
            "  macOS    ~/Library/Application Support/Godot/app_userdata/WRECKSMITH", "",
            "Build %s." % self.rev, ""])

    def stage_standalone(self, preset, exe):
        ed, pl = preset.edition, preset.platform
        top = "%s-%s-%s" % (SLUG[ed], self.version, pl)
        sdir = self.dist / "standalone"
        sdir.mkdir(parents=True, exist_ok=True)
        for old in sdir.iterdir():
            info = parse_artifact(old.name)
            if info and info[0] == ed and info[2] == pl:
                old.unlink()
        stage = Path(tempfile.mkdtemp(prefix="wrecksmith_stage_"))
        try:
            if pl == "macos":
                unzip_keep_modes(exe, stage)
            else:
                for p in exe.parent.iterdir():
                    if p.name not in JUNK and not p.name.endswith(JUNK_SUFFIX):
                        (shutil.copytree(str(p), str(stage / p.name)) if p.is_dir() else shutil.copy2(str(p), str(stage / p.name)))
            write_file(stage / "README.txt", self.readme_text(ed, pl), "\r\n" if pl == "windows" else "\n")
            self.put_licenses("standalone", stage)
            if pl == "linux":
                pack_targz(stage, sdir / (top + ".tar.gz"), top)
            else:
                pack_zip(stage, sdir / (top + ".zip"), top)
            if pl == "windows" and not self.a.no_installer:
                self.make_installer(ed, stage, sdir / (top + "-setup.exe"))
        finally:
            shutil.rmtree(str(stage), ignore_errors=True)

    def ensure_nsis(self):
        """NSIS's compiler, for the Windows installer: found, or (on Windows, when the user says yes or passes --install-nsis)
        fetched into the user's cache. None, with a warning that says why, when there is none: the zip is made all the same."""
        found = find_makensis()
        if found:
            return found
        if not sys.platform.startswith("win"):
            self.warn("makensis (NSIS) is not installed: no Windows installer, only the zip (Linux: apt install nsis; macOS: brew install makensis).")
            return None
        want = self.a.install_nsis
        if not want and sys.stdin is not None and sys.stdin.isatty():
            say("The Windows installer (a real Setup.exe) is made with NSIS, which is not installed here.")
            try:
                ans = input("Fetch NSIS %s now (a 2 MB zip from nsis.sourceforge.io, unpacked into %s: nothing is installed on the system)? [Y/n] "
                            % (NSIS_VERSION, cache_dir())).strip().lower()
            except EOFError:
                ans = "n"
            want = ans in ("", "y", "yes")
        if not want:
            self.warn("NSIS is not installed: no Windows installer, only the zip. Run again with --install-nsis to fetch it (2 MB), "
                      "or install it from nsis.sourceforge.io.")
            return None
        say("Fetching NSIS %s ..." % NSIS_VERSION)
        try:
            path = fetch_nsis()
        except (Fail, OSError, zipfile.BadZipFile) as e:
            self.warn("could not fetch NSIS (%s): no Windows installer, only the zip." % e)
            return None
        say("  NSIS is in %s" % Path(path).parent)
        return path

    def make_installer(self, edition, stage, out_file):
        if self.nsis is False:
            self.nsis = self.ensure_nsis()
        nsis = self.nsis
        if not nsis:
            return None             # ensure_nsis said why
        exe = find_preset(self.presets, edition, "standalone", "windows").exe
        cmd = [nsis, "-V2", "-DPRODUCT=%s" % TITLE[edition], "-DVERSION=%s" % self.version, "-DEXE=%s" % exe, "-DSRC=%s" % stage,
               "-DOUT=%s" % out_file, "-DSLUG=%s" % SLUG[edition], "-DICON=%s" % (self.root / "art" / "icon" / "wrecksmith.ico"),
               "-DWELCOME_BMP=%s" % (self.root / "tools" / "installer" / "welcome.bmp"), "-DHEADER_BMP=%s" % (self.root / "tools" / "installer" / "header.bmp"),
               str(self.root / "tools" / "installer" / "wrecksmith.nsi")]
        code, out = run(cmd, timeout=1200)
        if code != 0 or not out_file.exists():
            self.warn("the Windows installer was not built (makensis exit %s): %s" % (code, " | ".join(out.strip().splitlines()[-4:])))
            return None
        return out_file

    # -- the whole run --

    def run(self):
        a = self.a
        channels = CHANNELS if a.channel == "both" else (a.channel,)
        steam_eds = [e for e in a.steam_editions.split(",") if e] if "steam" in channels else []
        stand_eds = [e for e in a.standalone_editions.split(",") if e] if "standalone" in channels else []
        for e in steam_eds + stand_eds:
            if e not in EDITIONS:
                raise Fail("unknown edition %r (demo, full)" % e)
        have = platforms_with_library(self.root)
        wanted = [p for p in a.platforms.split(",") if p] if a.platforms else have
        for p in wanted:
            if p not in PLATFORMS:
                raise Fail("unknown platform %r (windows, linux, macos)" % p)
            if p not in have:
                if a.platforms:
                    raise Fail("the voxel core library for %s is not in native/bin/ (macOS's is built on a Mac, or by the Builds workflow)." % p)
        plats = [p for p in wanted if p in have]
        for p in PLATFORMS:
            if p not in have and not a.platforms:
                self.warn("no %s build: its voxel core library is not in native/bin/ (the Builds workflow makes the macOS one)." % p)
        if a.clean:
            for d in (self.build, self.dist):
                if d.exists():
                    shutil.rmtree(str(d))
        if not steam_eds and not stand_eds:
            raise Fail("nothing to build (check --channel and the edition lists)")
        say("WRECKSMITH %s, build %s: %s" % (self.version, self.rev, ", ".join(
            ["steam %s" % "+".join(steam_eds)] * bool(steam_eds) + ["standalone %s" % "+".join(stand_eds)] * bool(stand_eds))))
        say("Platforms: %s" % ", ".join(plats))
        self.need_import = False
        self.check_setup(plats)
        if stand_eds and "windows" in plats and not a.no_installer:
            self.nsis = self.ensure_nsis()      # asked now, not after the exports, so the questions are over before the long part
        for src in a.godotsteam or []:
            self.install_steam_addons(src)
        miss = steam_addons_missing(self.root) if steam_eds else []
        if miss:
            msg = ("the Steam builds lack %s. They are made without, so they run, but %s. Put the extension in addons/ "
                   "(or pass --godotsteam <its zip or folder>, once for each) and run again; docs/PACKAGING.md says where to get them."
                   % (" and ".join(miss), "without Steam's overlay, lobbies, achievements and cloud saves, and with no playing together "
                      "through Steam (by address still works)" if len(miss) == 2 else
                      "without Steam's overlay, lobbies, achievements and cloud saves" if "GodotSteam" in miss[0] else
                      "with no playing together through Steam's lobbies (by address still works)"))
            if a.require_steam_lib:
                raise Fail(msg)
            self.warn(msg)
        if not a.skip_export:
            self.ensure_imported()
        self.make_licenses()
        steam_done = {}
        # The systems the game is sold for on Steam (tools/steam/steam_ids.json "platforms"; a --platforms list overrides it).
        shipped = steam_platforms(load_steam_ids(self.root))
        steam_plats = plats if a.platforms else [p for p in plats if p in shipped]
        left_out = [p for p in plats if p not in steam_plats]
        if steam_eds and left_out:
            say("Not for Steam (steam_ids.json \"platforms\" lists %s): %s." % (", ".join(shipped), ", ".join(left_out)))
        for channel, eds in (("steam", steam_eds), ("standalone", stand_eds)):
            for ed in eds:
                for pl in (steam_plats if channel == "steam" else plats):
                    preset = find_preset(self.presets, ed, channel, pl)
                    exe = self.export(preset)
                    verdict = self.smoke(preset, exe)
                    say("    %s" % verdict)
                    self.results.append((channel, ed, pl, exe, verdict))
                    if channel == "steam":
                        depot = self.stage_steam(preset, exe)
                        steam_done.setdefault(ed, []).append(pl)
                        gaps = steam_depot_gaps(self.root, pl, depot) if pl != "macos" else []
                        if gaps:
                            self.warn("the %s %s Steam depot lacks %s: Steam's extension was not exported with the game, so its Steam "
                                      "features would not start there. Check addons/ (the extension's own .gdextension names what it needs)."
                                      % (ed, pl, ", ".join(gaps)))
                    else:
                        self.stage_standalone(preset, exe)
        if steam_done:
            self.write_steam_scripts(steam_done)
        self.write_report()
        return 0

    def write_report(self):
        """PACKAGE_REPORT.md and SHA256SUMS.txt, over what dist/ holds now (this run's checks beside the files it made)."""
        sdir = self.dist / "standalone"
        files = sorted(p for p in sdir.iterdir() if parse_artifact(p.name)) if sdir.exists() else []
        sums, rows = [], []
        for path in files:
            h = sha256(path)
            sums.append("%s  %s" % (h, path.name))
            rows.append("| %s | `%s` | %s | `%s` |" % (describe_artifact(path.name), path.relative_to(self.dist).as_posix(), human(path.stat().st_size), h[:16]))
        if sums:
            write_file(sdir / "SHA256SUMS.txt", "\n".join(sums) + "\n")
        checked = {(c, e, p): v for c, e, p, _, v in self.results}
        steam_rows = []
        content = self.dist / "steam" / "content"
        if content.exists():
            for ed_dir in sorted(content.iterdir()):
                for pl_dir in sorted(ed_dir.iterdir()):
                    size = sum(f.stat().st_size for f in pl_dir.rglob("*") if f.is_file())
                    exe = find_preset(self.presets, ed_dir.name, "steam", pl_dir.name).exe
                    steam_rows.append("| %s | %s | `%s` | %s | %s |" % (ed_dir.name, pl_dir.name, exe, human(size),
                                                                      checked.get(("steam", ed_dir.name, pl_dir.name), "from an earlier run")))
        out = ["# WRECKSMITH packages", "",
               "Version %s, build `%s`, packed %s with Godot %s." % (self.version, self.rev, datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"), self.gver), ""]
        if steam_rows:
            out += ["## Steam (`dist/steam/`)", "", "| edition | platform | program (launch option) | depot size | check |", "|---|---|---|---|---|"] + steam_rows
            out += ["", "Content to upload: `dist/steam/content/<edition>/<platform>/`. Scripts: `dist/steam/scripts/`. "
                    "Try `upload.bat demo preview` (or `./upload.sh demo preview`) first: it uploads nothing and lists the files.", ""]
        if rows:
            out += ["## Without Steam (`dist/standalone/`)", "", "| what | file | size | sha256 |", "|---|---|---|---|"] + rows + [""]
            sa = ["%s %s: %s" % (e, p, v) for (c, e, p), v in sorted(checked.items()) if c == "standalone"]
            if sa:
                out += ["Checks: " + "; ".join(sa), ""]
        if self.notes:
            out += ["## To know", ""] + ["- %s" % n for n in self.notes] + [""]
        write_file(self.dist / "PACKAGE_REPORT.md", "\n".join(out))
        say("")
        say("Report: %s" % (self.dist / "PACKAGE_REPORT.md"))
        for path in files:
            say("  %-44s %9s  %s" % (path.name, human(path.stat().st_size), describe_artifact(path.name)))


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="Export and pack WRECKSMITH for Steam and for download without Steam.")
    ap.add_argument("--channel", choices=("steam", "standalone", "both"), default="both")
    ap.add_argument("--steam-editions", default="demo,full", help="editions for the Steam depots (default demo,full)")
    ap.add_argument("--standalone-editions", default="demo,full", help="editions for the download without Steam (default demo,full)")
    ap.add_argument("--platforms", default="", help="windows,linux,macos (default: every platform whose voxel core library is here)")
    ap.add_argument("--godot", help="the Godot 4.7 executable (else $GODOT, the PATH, the usual places)")
    ap.add_argument("--version", help="the version in file names (default: config/version of project.godot)")
    ap.add_argument("--out", default="dist")
    ap.add_argument("--skip-export", action="store_true", help="pack what build/ already holds")
    ap.add_argument("--skip-tests", action="store_true", help="do not run the Linux build to check it")
    ap.add_argument("--no-installer", action="store_true", help="no Windows installer (needs NSIS) beside the zip")
    ap.add_argument("--install-nsis", action="store_true", help="fetch NSIS (a 2 MB zip, Windows only) when it is missing, for the Windows installer")
    ap.add_argument("--clean", action="store_true", help="empty build/ and dist/ first")
    ap.add_argument("--install-templates", action="store_true", help="fetch missing export templates (only the needed ones)")
    ap.add_argument("--godotsteam", "--steam-addons", dest="godotsteam", nargs="+", metavar="ZIP_OR_FOLDER",
                    help="the Steam GDExtensions (GodotSteam, and the Steam multiplayer peer: a zip or a folder each) to put in addons/ for the Steam builds")
    ap.add_argument("--require-steam-lib", action="store_true", help="fail when the Steam builds would lack GodotSteam or the Steam multiplayer peer")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        return Packager(args).run()
    except Fail as e:
        say("\nSTOPPED: %s" % e)
        return 2
    except KeyboardInterrupt:
        say("\nStopped.")
        return 130


if __name__ == "__main__":
    sys.exit(main())
