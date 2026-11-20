#!/usr/bin/env python3
"""Checks of tools/package.py that need no Godot: the export presets, the SteamPipe scripts, the archives.
Run:  python tools/test_package.py        (run_tests.sh runs it when Python is there)"""
import os
import json
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package as P  # noqa: E402


class Presets(unittest.TestCase):
    def setUp(self):
        self.presets = P.read_presets(P.ROOT)

    def test_every_edition_channel_and_platform_has_exactly_one_preset(self):
        seen = sorted((p.edition, p.channel, p.platform) for p in self.presets)
        want = sorted((e, c, pl) for e in P.EDITIONS for c in P.CHANNELS for pl in P.PLATFORMS)
        self.assertEqual(seen, want)
        self.assertEqual(len(set(p.name for p in self.presets)), len(self.presets), "preset names must be unique")
        for e, c, pl in want:
            P.find_preset(self.presets, e, c, pl)

    def test_exports_land_where_the_packager_looks(self):
        for p in self.presets:
            ext = {"windows": "exe", "linux": "x86_64", "macos": "zip"}[p.platform]
            exe = "WRECKSMITH_Demo" if p.edition == "demo" else "WRECKSMITH"
            self.assertEqual(p.path, "build/%s/%s/%s/%s.%s" % (p.channel, p.edition, p.platform, exe, ext), p.name)

    def test_standalone_builds_leave_steam_out_and_steam_builds_keep_it(self):
        for p in self.presets:
            leaves_out = "addons/*" in p.exclude
            self.assertEqual(leaves_out, p.channel == "standalone", p.name)
            self.assertIn("standalone" if p.channel == "standalone" else "steam", p.features, p.name)
            self.assertNotIn("steam" if p.channel == "standalone" else "standalone", p.features, p.name)
            self.assertEqual("demo" in p.features, p.edition == "demo", p.name)

    def test_the_store_art_and_the_tests_stay_out_and_the_font_stays_in(self):
        for p in self.presets:
            for need in ("docs/*", "tests/*", "build/*", "dist/*", "extension/*"):
                self.assertIn(need, p.exclude, "%s should exclude %s" % (p.name, need))
            self.assertNotIn("tools/*", p.exclude, "tools/fonts is used by the game (%s)" % p.name)

    def test_the_voxel_core_libraries_are_listed_for_every_platform(self):
        libs = P.native_libraries(P.ROOT)
        for pl in P.PLATFORMS:
            self.assertTrue(libs[pl], pl)
        self.assertTrue(any(l.name.endswith(".dll") for l in libs["windows"]))
        self.assertTrue(any(l.name.endswith(".so") for l in libs["linux"]))


    def test_the_windows_program_carries_the_games_icon_and_name_not_godots(self):
        proj = P.project_version(P.ROOT)
        for p in self.presets:
            if p.platform != "windows":
                continue
            o = p.options
            self.assertEqual(o.get("application/modify_resources"), "true", p.name)
            self.assertEqual(o.get("application/icon"), "res://art/icon/wrecksmith.ico", p.name)
            self.assertEqual(o.get("application/product_name"), P.TITLE[p.edition], p.name)
            self.assertEqual(o.get("application/file_description"), P.TITLE[p.edition], p.name)
            self.assertTrue(o.get("application/company_name"), p.name)
            for k in ("application/file_version", "application/product_version"):
                self.assertTrue(o.get(k, "").startswith(proj + "."), "%s: %s should start with the project's version %s" % (p.name, k, proj))

    def test_the_mac_app_carries_the_games_icon(self):
        for p in self.presets:
            if p.platform == "macos":
                self.assertEqual(p.options.get("application/icon"), "res://art/icon/wrecksmith.icns", p.name)

    def test_the_icon_files_exist_and_the_ico_holds_every_size(self):
        ico = P.ROOT / "art" / "icon" / "wrecksmith.ico"
        data = ico.read_bytes()
        self.assertEqual(data[:4], b"\x00\x00\x01\x00")
        n = int.from_bytes(data[4:6], "little")
        sizes = sorted((data[6 + 16 * i] or 256) for i in range(n))
        for want in (16, 32, 48, 256):
            self.assertIn(want, sizes)
        self.assertTrue((P.ROOT / "art" / "icon" / "wrecksmith.icns").exists())
        self.assertTrue((P.ROOT / "icon.png").exists())

    def test_the_icon_files_are_not_packed_into_the_game(self):
        for p in self.presets:
            self.assertIn("art/icon/*", p.exclude, p.name)

    def test_the_installer_wears_the_games_icon_and_pictures(self):
        nsi = (P.ROOT / "tools" / "installer" / "wrecksmith.nsi").read_text(encoding="utf-8")
        for need in ("MUI_ICON", "MUI_UNICON", "MUI_WELCOMEFINISHPAGE_BITMAP", "MUI_HEADERIMAGE_BITMAP"):
            self.assertIn(need, nsi)
        for f in ("welcome.bmp", "header.bmp"):
            self.assertTrue((P.ROOT / "tools" / "installer" / f).exists(), f)


class Splash(unittest.TestCase):
    def _application(self):
        text = (P.ROOT / "project.godot").read_text(encoding="utf-8")
        sec = text[text.index("[application]"):]
        sec = sec[:sec.index("\n[", 5)] if "\n[" in sec[5:] else sec
        return dict(l.split("=", 1) for l in sec.splitlines() if "=" in l)

    def test_the_game_starts_with_its_own_picture_not_godots_logo(self):
        app = self._application()
        self.assertEqual(app.get("boot_splash/image"), '"res://art/splash.png"')
        self.assertNotEqual(app.get("boot_splash/show_image"), "false", "show_image=false would show no picture at all")
        self.assertEqual(app.get("boot_splash/fullsize"), "true")
        r, g, b = [float(x) for x in re.search(r"Color\(([^)]*)\)", app["boot_splash/bg_color"]).group(1).split(",")[:3]]
        self.assertLess(max(r, g, b), 0.2, "the bars round the picture must be as dark as the picture's edge")

    def test_the_splash_picture_is_a_big_enough_png(self):
        data = (P.ROOT / "art" / "splash.png").read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        w, h = int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
        self.assertGreaterEqual((w, h), (1280, 720))
        self.assertAlmostEqual(w / h, 16 / 9, places=2)

    def test_the_splash_is_not_dropped_by_an_export_filter(self):
        for p in P.read_presets(P.ROOT):
            self.assertNotIn("art/splash.png", p.exclude, p.name)
            self.assertNotIn("art/*", p.exclude, p.name)


class Nsis(unittest.TestCase):
    """The Windows installer needs NSIS; on a machine without it the packager fetches it (Windows) or says how."""

    def _zip(self, path, names):
        with zipfile.ZipFile(str(path), "w") as z:
            for n in names:
                z.writestr(n, b"x")
        return path

    def test_the_pinned_download_is_the_official_zip(self):
        self.assertIn("sourceforge.net/project/nsis/", P.NSIS_URL)
        self.assertIn("nsis-%s.zip" % P.NSIS_VERSION, P.NSIS_URL)
        self.assertRegex(P.NSIS_SHA256, r"^[0-9a-f]{64}$")

    def test_a_downloaded_nsis_is_checked_unpacked_and_leaves_nothing_behind(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            z = self._zip(tmp / "src.zip", ["nsis-%s/makensis.exe" % P.NSIS_VERSION, "nsis-%s/Bin/makensis.exe" % P.NSIS_VERSION])
            base = tmp / "cache"
            exe = P.fetch_nsis(url=z.as_uri(), sha=P.sha256(z), base=base)
            self.assertEqual(Path(exe), base / ("nsis-%s" % P.NSIS_VERSION) / "makensis.exe")
            self.assertTrue(Path(exe).exists())
            self.assertTrue((base / ("nsis-%s" % P.NSIS_VERSION) / "Bin" / "makensis.exe").exists())
            self.assertEqual(sorted(p.name for p in base.iterdir()), ["nsis-%s" % P.NSIS_VERSION], "no .part or .unpacking left")
        finally:
            shutil.rmtree(tmp)

    def test_a_download_with_the_wrong_checksum_is_not_used(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            z = self._zip(tmp / "src.zip", ["nsis-%s/makensis.exe" % P.NSIS_VERSION])
            with mock.patch.object(P.time, "sleep"):
                with self.assertRaises(P.Fail) as cm:
                    P.fetch_nsis(url=z.as_uri(), sha="0" * 64, base=tmp / "cache")
            self.assertIn("checksum", str(cm.exception))
            self.assertEqual([p.name for p in (tmp / "cache").iterdir()], [], "the bad file is deleted")
        finally:
            shutil.rmtree(tmp)

    def test_an_unreachable_address_is_a_clear_stop_not_a_crash(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            with mock.patch.object(P.time, "sleep"):
                with self.assertRaises(P.Fail) as cm:
                    P.fetch_nsis(url=(tmp / "nothing.zip").as_uri(), sha="0" * 64, base=tmp / "cache")
            self.assertIn("could not download", str(cm.exception))
        finally:
            shutil.rmtree(tmp)

    def test_a_zip_that_reaches_outside_its_folder_is_refused(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            z = self._zip(tmp / "evil.zip", ["nsis-%s/makensis.exe" % P.NSIS_VERSION, "../evil.txt"])
            with zipfile.ZipFile(str(z)) as zf:
                with self.assertRaises(P.Fail):
                    P.extract_safely(zf, tmp / "out")
            self.assertFalse((tmp / "evil.txt").exists())
        finally:
            shutil.rmtree(tmp)

    def test_a_zip_without_makensis_is_refused(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            z = self._zip(tmp / "odd.zip", ["something/else.txt"])
            with self.assertRaises(P.Fail):
                P.fetch_nsis(url=z.as_uri(), sha=P.sha256(z), base=tmp / "cache")
        finally:
            shutil.rmtree(tmp)

    def test_the_fetched_copy_is_found_on_windows_and_never_elsewhere(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            exe = tmp / ("nsis-%s" % P.NSIS_VERSION) / "makensis.exe"
            exe.parent.mkdir()
            exe.write_bytes(b"MZ")
            with mock.patch.object(P, "cache_dir", return_value=tmp), mock.patch.object(P.shutil, "which", return_value=None), \
                    mock.patch.dict(os.environ, {"ProgramFiles": str(tmp / "none"), "ProgramFiles(x86)": str(tmp / "none")}):
                with mock.patch.object(sys, "platform", "win32"):
                    self.assertEqual(P.find_makensis(), str(exe))
                with mock.patch.object(sys, "platform", "linux"):
                    self.assertIsNone(P.find_makensis(), "a Windows program is of no use on Linux")
        finally:
            shutil.rmtree(tmp)

    def test_the_cache_is_the_users_not_the_checkouts(self):
        self.assertFalse(str(P.cache_dir()).startswith(str(P.ROOT)))

    def _packager(self, *flags):
        pk = P.Packager(P.parse_args(list(flags)))
        pk.notes.clear()
        return pk

    def test_without_a_terminal_it_asks_nothing_and_says_how_to_get_nsis(self):
        pk = self._packager()
        with mock.patch.object(sys, "platform", "win32"), mock.patch.object(P, "find_makensis", return_value=None), \
                mock.patch.object(P, "fetch_nsis") as fetch, mock.patch.object(sys, "stdin", mock.Mock(isatty=lambda: False)):
            self.assertIsNone(pk.ensure_nsis())
        fetch.assert_not_called()
        self.assertTrue(any("--install-nsis" in n for n in pk.notes), pk.notes)

    def test_install_nsis_fetches_it_without_asking(self):
        pk = self._packager("--install-nsis")
        with mock.patch.object(sys, "platform", "win32"), mock.patch.object(P, "find_makensis", return_value=None), \
                mock.patch.object(P, "fetch_nsis", return_value="C:/cache/nsis/makensis.exe") as fetch:
            self.assertEqual(pk.ensure_nsis(), "C:/cache/nsis/makensis.exe")
        fetch.assert_called_once()
        self.assertEqual(pk.notes, [])

    def test_a_failed_fetch_still_leaves_the_zip(self):
        pk = self._packager("--install-nsis")
        with mock.patch.object(sys, "platform", "win32"), mock.patch.object(P, "find_makensis", return_value=None), \
                mock.patch.object(P, "fetch_nsis", side_effect=P.Fail("NSIS: could not download")):
            self.assertIsNone(pk.ensure_nsis())
        self.assertTrue(any("only the zip" in n for n in pk.notes), pk.notes)

    def test_an_nsis_that_is_there_is_just_used(self):
        pk = self._packager()
        with mock.patch.object(P, "find_makensis", return_value="/usr/bin/makensis"), mock.patch.object(P, "fetch_nsis") as fetch:
            self.assertEqual(pk.ensure_nsis(), "/usr/bin/makensis")
        fetch.assert_not_called()

    def test_on_linux_and_mac_it_says_to_install_it_with_the_package_manager(self):
        pk = self._packager("--install-nsis")
        with mock.patch.object(sys, "platform", "linux"), mock.patch.object(P, "find_makensis", return_value=None), mock.patch.object(P, "fetch_nsis") as fetch:
            self.assertIsNone(pk.ensure_nsis())
        fetch.assert_not_called()
        self.assertTrue(any("apt install nsis" in n for n in pk.notes), pk.notes)

    def test_the_installer_is_built_with_the_compiler_found_up_front_and_the_games_pictures(self):
        pk = self._packager()
        pk.nsis = "/somewhere/makensis"
        tmp = Path(tempfile.mkdtemp())
        seen = {}

        def fake_run(cmd, cwd=None, timeout=None):
            seen["cmd"] = [str(c) for c in cmd]
            Path(seen["cmd"][[i for i, c in enumerate(seen["cmd"]) if c.startswith("-DOUT=")][0]].split("=", 1)[1]).write_bytes(b"MZ")
            return 0, ""
        try:
            with mock.patch.object(P, "run", fake_run):
                out = pk.make_installer("full", tmp, tmp / "WRECKSMITH-0.1-windows-setup.exe")
            self.assertEqual(out, tmp / "WRECKSMITH-0.1-windows-setup.exe")
            self.assertEqual(seen["cmd"][0], "/somewhere/makensis")
            for need in ("-DICON=", "-DWELCOME_BMP=", "-DHEADER_BMP=", "-DPRODUCT=WRECKSMITH"):
                self.assertTrue(any(c.startswith(need) for c in seen["cmd"]), need)
            self.assertEqual(pk.notes, [])
            self.assertIn("-DPUBLISHER=Edella Studios", seen["cmd"], "the installer names who made the game")
            self.assertIn("-DCOPYRIGHT=Copyright (c) 2026 Edella Studios", seen["cmd"])
        finally:
            shutil.rmtree(tmp)

    def test_without_a_named_holder_the_installer_is_given_none_to_print(self):
        pk = self._packager()
        pk.nsis = "/somewhere/makensis"
        pk.root = Path(tempfile.mkdtemp())
        (pk.root / "data").mkdir()
        (pk.root / "data" / "legal.json").write_text('{"holder": "", "year": "2026"}')
        seen = {}

        def fake_run(cmd, cwd=None, timeout=None):
            seen["cmd"] = [str(c) for c in cmd]
            Path([c for c in seen["cmd"] if c.startswith("-DOUT=")][0].split("=", 1)[1]).write_bytes(b"MZ")
            return 0, ""
        tmp = Path(tempfile.mkdtemp())
        try:
            with mock.patch.object(P, "run", fake_run):
                pk.make_installer("full", tmp, tmp / "x-setup.exe")
            self.assertFalse(any(c.startswith(("-DPUBLISHER=", "-DCOPYRIGHT=")) for c in seen["cmd"]), seen["cmd"])
        finally:
            shutil.rmtree(tmp)
            shutil.rmtree(pk.root)

    def test_no_installer_flag_and_the_option_parse(self):
        a = P.parse_args([])
        self.assertFalse(a.install_nsis)
        self.assertTrue(P.parse_args(["--install-nsis"]).install_nsis)


class Basics(unittest.TestCase):
    def test_the_download_without_steam_is_made_for_the_demo_and_the_full_game(self):
        a = P.parse_args([])
        self.assertEqual(sorted(a.standalone_editions.split(",")), ["demo", "full"])
        self.assertEqual(sorted(a.steam_editions.split(",")), ["demo", "full"])

    def test_godot_versions_name_the_templates_folder(self):
        self.assertEqual(P.parse_godot_version("4.7.2.stable.official.ed1daf0bf"), "4.7.2.stable")
        self.assertEqual(P.parse_godot_version("4.7.stable.official.abc"), "4.7.stable")
        self.assertEqual(P.parse_godot_version("4.3.stable.mono.official.77dcf97d8"), "4.3.stable.mono")
        self.assertEqual(P.parse_godot_version("4.8.rc1.official.aaaaaaaa"), "4.8.rc1")

    def test_the_project_version_is_read_from_project_godot(self):
        d = Path(tempfile.mkdtemp())
        try:
            (d / "project.godot").write_text('[application]\n\nconfig/name="X"\nconfig/version="1.2.3"\n')
            self.assertEqual(P.project_version(d), "1.2.3")
            (d / "project.godot").write_text('[application]\nconfig/name="X"\n')
            self.assertEqual(P.project_version(d), "0.0")
        finally:
            shutil.rmtree(d)
        self.assertRegex(P.project_version(P.ROOT), r"^\d")

    def test_artifact_names_round_trip(self):
        self.assertEqual(P.parse_artifact("WRECKSMITH-Demo-0.1-windows-setup.exe"), ("demo", "0.1", "windows", "installer"))
        self.assertEqual(P.parse_artifact("WRECKSMITH-0.2-rc1-linux.tar.gz"), ("full", "0.2-rc1", "linux", "archive"))
        self.assertEqual(P.parse_artifact("WRECKSMITH-Demo-0.1-macos.zip"), ("demo", "0.1", "macos", "archive"))
        self.assertIsNone(P.parse_artifact("SHA256SUMS.txt"))
        self.assertEqual(P.describe_artifact("WRECKSMITH-Demo-0.1-windows-setup.exe"), "WRECKSMITH Demo 0.1, Windows installer")

    def test_a_demo_is_not_mistaken_for_the_full_game_when_old_files_are_cleared(self):
        # The full game's name is a prefix of the demo's: parse_artifact must tell them apart.
        self.assertEqual(P.parse_artifact("WRECKSMITH-Demo-0.1-linux.tar.gz")[0], "demo")
        self.assertEqual(P.parse_artifact("WRECKSMITH-0.1-linux.tar.gz")[0], "full")

    def test_the_steam_ids_file_has_a_slot_for_everything(self):
        ids = P.load_steam_ids(P.ROOT)
        for ed in P.EDITIONS:
            self.assertIsInstance(ids[ed]["app_id"], int)
            self.assertEqual(sorted(ids[ed]["depots"]), sorted(P.PLATFORMS))

    def test_net_gd_never_starts_steam_in_a_standalone_build(self):
        src = (P.ROOT / "scripts" / "net" / "net.gd").read_text(encoding="utf-8")
        body = src[src.index("func _init_steam"):]
        body = body[:body.index("\nfunc ", 5)] if "\nfunc " in body[5:] else body
        self.assertIn('OS.has_feature("standalone")', body)


class SteamScripts(unittest.TestCase):
    def test_the_app_build_script(self):
        v = P.app_build_vdf("123", "WRECKSMITH Demo 0.1 (abc)", "demo", [("124", "depot_demo_windows.vdf"), ("125", "depot_demo_linux.vdf")])
        self.assertEqual(v.count("{"), v.count("}"))
        for line in ('"AppBuild"', '"AppID"\t"123"', '"Preview"\t"0"', '"SetLive"\t""', '"ContentRoot"\t"../content/demo/"',
                     '"124"\t"depot_demo_windows.vdf"', '"125"\t"depot_demo_linux.vdf"'):
            self.assertIn(line, v)
        self.assertIn('"Preview"\t"1"', P.app_build_vdf("1", "d", "demo", [], preview=True))

    def test_the_depot_script(self):
        v = P.depot_build_vdf("124", "windows")
        self.assertEqual(v.count("{"), v.count("}"))
        for line in ('"DepotBuildConfig"', '"DepotID"\t"124"', '"LocalPath"\t"windows/*"', '"DepotPath"\t"."', '"recursive"\t"1"',
                     '"FileExclusion"\t"steam_appid.txt"'):
            self.assertIn(line, v)

    def test_ids_not_set_show_as_placeholders_and_set_ids_as_numbers(self):
        self.assertEqual(P.steam_id({}, "demo", "app"), "DEMO_APP_ID")
        self.assertEqual(P.steam_id({"demo": {"app_id": 0, "depots": {"linux": 0}}}, "demo", "depot", "linux"), "DEMO_LINUX_DEPOT_ID")
        ids = {"full": {"app_id": 4242, "depots": {"windows": 4243}}}
        self.assertEqual(P.steam_id(ids, "full", "app"), "4242")
        self.assertEqual(P.steam_id(ids, "full", "depot", "windows"), "4243")

    def _packager(self, tmp, ids=None):
        pk = P.Packager(P.parse_args(["--out", str(tmp / "dist")]))
        pk.root = tmp / "proj"
        (pk.root / "tools" / "steam").mkdir(parents=True)
        if ids is not None:
            import json
            (pk.root / "tools" / "steam" / "steam_ids.json").write_text(json.dumps(ids))
        return pk

    def test_scripts_are_written_for_what_was_packed_and_upload_refuses_placeholders(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            pk = self._packager(tmp)
            pk.write_steam_scripts({"demo": ["windows", "linux"]})
            s = tmp / "dist" / "steam" / "scripts"
            self.assertEqual(sorted(p.name for p in s.iterdir()), ["app_build_demo.vdf", "app_build_demo_preview.vdf", "depot_demo_linux.vdf", "depot_demo_windows.vdf"])
            self.assertTrue(any("not set" in n for n in pk.notes))
            self.assertIn("WRECKSMITH_Demo.exe", (tmp / "dist" / "steam" / "README.txt").read_text())
            if shutil.which("sh"):
                r = subprocess.run(["sh", str(tmp / "dist" / "steam" / "upload.sh"), "demo"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
                self.assertEqual(r.returncode, 1)
                self.assertIn("not filled in", r.stdout)
        finally:
            shutil.rmtree(tmp)

    def test_filled_in_ids_leave_no_placeholder(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            ids = {"demo": {"app_id": 111, "depots": {"windows": 112, "linux": 113, "macos": 114}}}
            pk = self._packager(tmp, ids)
            pk.write_steam_scripts({"demo": ["windows", "linux", "macos"]})
            for f in (tmp / "dist" / "steam" / "scripts").iterdir():
                self.assertNotIn("_ID", f.read_text(), f.name)
            self.assertIn('"112"\t"depot_demo_windows.vdf"', (tmp / "dist" / "steam" / "scripts" / "app_build_demo.vdf").read_text())
            self.assertEqual(pk.notes, [])
        finally:
            shutil.rmtree(tmp)

    def test_the_depot_gets_the_build_and_its_library_and_never_steam_appid_txt(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            pk = self._packager(tmp)
            out = tmp / "export"
            out.mkdir()
            (out / "WRECKSMITH_Demo.exe").write_bytes(b"MZ")
            (out / "lib.dll").write_bytes(b"x")
            (out / "steam_appid.txt").write_text("480")
            (out / "debug.pdb").write_bytes(b"x")
            preset = P.find_preset(pk.presets, "demo", "steam", "windows")
            dest = pk.stage_steam(preset, out / "WRECKSMITH_Demo.exe")
            self.assertEqual(sorted(p.name for p in dest.iterdir()), ["WRECKSMITH_Demo.exe", "lib.dll"])
            self.assertEqual(dest, tmp / "dist" / "steam" / "content" / "demo" / "windows")
        finally:
            shutil.rmtree(tmp)


class Archives(unittest.TestCase):
    def _tree(self, tmp):
        src = tmp / "src"
        (src / "sub").mkdir(parents=True)
        game = src / "WRECKSMITH_Demo.x86_64"
        game.write_bytes(b"\x7fELF")
        game.chmod(0o755)
        (src / "libvoxelcore.so").write_bytes(b"lib")
        (src / "libvoxelcore.so").chmod(0o644)
        (src / "sub" / "README.txt").write_text("hi")
        return src

    def test_a_tarball_keeps_the_game_runnable_and_the_rest_plain(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            src = self._tree(tmp)
            out = P.pack_targz(src, tmp / "o.tar.gz", "top")
            with tarfile.open(str(out)) as t:
                modes = {m.name: m.mode for m in t.getmembers()}
            self.assertEqual(modes["top/WRECKSMITH_Demo.x86_64"], 0o755)
            self.assertEqual(modes["top/libvoxelcore.so"], 0o644)
            self.assertEqual(modes["top/sub/README.txt"], 0o644)
            self.assertEqual(modes["top"], 0o755)
        finally:
            shutil.rmtree(tmp)

    def test_a_zip_keeps_modes_and_unzip_gives_them_back(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            src = self._tree(tmp)
            out = P.pack_zip(src, tmp / "o.zip", "top")
            with zipfile.ZipFile(str(out)) as z:
                names = z.namelist()
                self.assertIn("top/WRECKSMITH_Demo.x86_64", names)
                self.assertEqual((z.getinfo("top/WRECKSMITH_Demo.x86_64").external_attr >> 16) & 0o777, 0o755)
                self.assertEqual((z.getinfo("top/libvoxelcore.so").external_attr >> 16) & 0o777, 0o644)
            dest = tmp / "out"
            P.unzip_keep_modes(out, dest)
            self.assertTrue(os.access(str(dest / "top" / "WRECKSMITH_Demo.x86_64"), os.X_OK))
            self.assertFalse(os.access(str(dest / "top" / "libvoxelcore.so"), os.X_OK))
        finally:
            shutil.rmtree(tmp)

    def test_the_readme_names_the_program_and_says_it_never_uses_steam(self):
        pk = P.Packager(P.parse_args([]))
        for pl, needle in (("windows", "WRECKSMITH_Demo.exe"), ("linux", "WRECKSMITH_Demo.x86_64"), ("macos", "WRECKSMITH_Demo.app")):
            t = pk.readme_text("demo", pl)
            self.assertIn(needle, t)
            self.assertIn("never connects to Steam", t)
        self.assertIn("The full game", pk.readme_text("full", "linux"))

    def test_the_readme_carries_the_copyright_line_once_a_holder_is_named(self):
        pk = P.Packager(P.parse_args([]))
        self.assertIn("Copyright (c) 2026 Edella Studios", pk.readme_text("full", "windows"))
        pk.root = Path(tempfile.mkdtemp())
        try:
            (pk.root / "data").mkdir()
            (pk.root / "data" / "legal.json").write_text('{"holder": "", "year": "2026"}')
            self.assertNotIn("Copyright (c)", pk.readme_text("full", "windows"), "no holder, no line")
            self.assertEqual(P.copyright_line(pk.root), "")
            (pk.root / "data" / "legal.json").write_text('{"holder": "  Some Studio ", "year": ""}')
            self.assertEqual(P.copyright_line(pk.root), "Copyright (c) Some Studio", "no year, no double space")
        finally:
            shutil.rmtree(pk.root)

    def test_sha256_matches_the_tool(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            f = tmp / "a.bin"
            f.write_bytes(b"abc")
            self.assertEqual(P.sha256(f), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        finally:
            shutil.rmtree(tmp)


def make_elf(*names):
    """A minimal 64-bit little-endian ELF whose version needs (.gnu.version_r) name the given versions ('GLIBC_2.27', ...)."""
    strs = b"\0libc.so.6\0"
    offs = []
    for n in names:
        offs.append(len(strs))
        strs += n.encode() + b"\0"
    verneed = struct.pack("<HHIII", 1, len(names), 1, 16, 0)
    for i, o in enumerate(offs):
        verneed += struct.pack("<IHHII", 0, 0, 2 + i, o, 16 if i + 1 < len(names) else 0)
    dynstr_off = 64
    verneed_off = dynstr_off + len(strs)
    shoff = verneed_off + len(verneed)

    def shdr(typ, off, size, link=0, info=0):
        return struct.pack("<IIQQQQIIQQ", 0, typ, 0, 0, off, size, link, info, 1, 0)

    table = shdr(0, 0, 0) + shdr(3, dynstr_off, len(strs)) + shdr(0x6ffffffe, verneed_off, len(verneed), 1, 1)
    head = b"\x7fELF\x02\x01\x01" + b"\0" * 9 + struct.pack("<HHIQQQIHHHHHH", 3, 62, 1, 0, 0, shoff, 0, 64, 0, 0, 64, 3, 0)
    return head + strs + verneed + table


class LinuxRuntime(unittest.TestCase):
    """Steam runs a Linux game in its Linux runtime (Debian 11, glibc 2.31): a library built on a newer system does not load there."""

    def _file(self, data):
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, str(d), True)
        f = d / "lib.so"
        f.write_bytes(data)
        return f

    def test_the_newest_version_of_each_system_library_is_read_from_the_file(self):
        f = self._file(make_elf("GLIBC_2.2.5", "GLIBC_2.27", "GLIBC_2.14", "GLIBC_PRIVATE", "GLIBCXX_3.4.26", "CXXABI_1.3.11"))
        self.assertEqual(P.elf_version_needs(f), {"GLIBC": (2, 27), "GLIBCXX": (3, 4, 26), "CXXABI": (1, 3, 11)})

    def test_versions_compare_as_numbers_not_as_text(self):
        f = self._file(make_elf("GLIBC_2.9", "GLIBC_2.14", "GLIBC_2.4"))
        self.assertEqual(P.elf_version_needs(f)["GLIBC"], (2, 14))

    def test_a_library_from_a_newer_system_is_flagged_and_an_older_one_is_not(self):
        self.assertEqual(P.too_new_for_steam(self._file(make_elf("GLIBC_2.31", "GLIBCXX_3.4.28", "CXXABI_1.3.12"))), [])
        self.assertEqual(P.too_new_for_steam(self._file(make_elf("GLIBC_2.2.5"))), [])
        bad = P.too_new_for_steam(self._file(make_elf("GLIBC_2.38", "GLIBC_2.17")))
        self.assertEqual(len(bad), 1)
        self.assertIn("GLIBC_2.38", bad[0])
        self.assertIn("2.31", bad[0])
        self.assertEqual(len(P.too_new_for_steam(self._file(make_elf("GLIBCXX_3.4.30")))), 1)

    def test_what_is_not_a_64_bit_elf_is_left_alone(self):
        self.assertEqual(P.too_new_for_steam(self._file(b"")), [])
        self.assertEqual(P.too_new_for_steam(self._file(b"MZ" + b"\0" * 200)), [])
        self.assertEqual(P.too_new_for_steam(self._file(b"\x7fELF\x01\x01\x01" + b"\0" * 100)), [])      # 32-bit
        self.assertEqual(P.too_new_for_steam(self._file(make_elf("GLIBC_2.38")[:90])), [])                  # cut short: no crash

    def test_the_committed_linux_library_fits_the_steam_runtime(self):
        for lib in P.native_libraries(P.ROOT)["linux"]:
            self.assertTrue(lib.exists(), lib)
            self.assertEqual(P.too_new_for_steam(lib), [],
                             "%s was built on a system newer than Steam's Linux runtime: build it in the Ubuntu 20.04 container "
                             "(.github/workflows/build.yml) and commit that one" % lib.name)

    def test_godots_own_linux_template_fits_it_too(self):
        found = 0
        for base in (Path.home() / ".local" / "share" / "godot" / "export_templates").glob("*"):
            exe = base / "linux_release.x86_64"
            if exe.exists():
                found += 1
                self.assertEqual(P.too_new_for_steam(exe), [], str(exe))
        if not found:
            self.skipTest("Godot's Linux export template is not installed here")

    def test_the_builds_workflow_makes_the_linux_library_in_an_old_enough_system(self):
        wf = (P.ROOT / ".github" / "workflows" / "build.yml").read_text(encoding="utf-8")
        self.assertIn("ubuntu:20.04", wf)

    def _smoke(self, channel, lib_needs):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, str(tmp), True)
        pk = P.Packager(P.parse_args(["--skip-tests"]))
        out = tmp / "export"
        out.mkdir()
        exe = out / "WRECKSMITH.x86_64"
        exe.write_bytes(b"not elf")
        for lib in P.native_libraries(P.ROOT)["linux"]:
            (out / lib.name).write_bytes(make_elf(*lib_needs))
        preset = P.find_preset(pk.presets, "full", channel, "linux")
        return pk, pk.smoke(preset, exe)

    def test_a_steam_linux_build_that_asks_for_too_much_is_not_packed(self):
        with self.assertRaises(P.Fail) as cm:
            self._smoke("steam", ["GLIBC_2.38"])
        self.assertIn("glibc 2.31", str(cm.exception))
        self.assertIn("GLIBC_2.38", str(cm.exception))

    def test_a_download_for_people_without_steam_is_warned_about_not_stopped(self):
        pk, verdict = self._smoke("standalone", ["GLIBC_2.38"])
        self.assertTrue(any("GLIBC_2.38" in n for n in pk.notes), pk.notes)
        self.assertNotIn("asks for no more", verdict)

    def test_a_fitting_build_says_so(self):
        pk, verdict = self._smoke("steam", ["GLIBC_2.27", "GLIBCXX_3.4.26"])
        self.assertEqual(pk.notes, [])
        self.assertIn("no more than glibc 2.31", verdict)


GODOTSTEAM_EXT = """[configuration]
entry_symbol = "godotsteam_init"
compatibility_minimum = "4.4"

[libraries]
windows.debug.x86_64 = "res://addons/godotsteam/win64/libgodotsteam.windows.template_debug.x86_64.dll"
windows.release.x86_64 = "res://addons/godotsteam/win64/libgodotsteam.windows.template_release.x86_64.dll"
linux.debug.x86_64 = "res://addons/godotsteam/linux64/libgodotsteam.linux.template_debug.x86_64.so"
linux.release.x86_64 = "res://addons/godotsteam/linux64/libgodotsteam.linux.template_release.x86_64.so"

[dependencies]
windows.release.x86_64 = {"res://addons/godotsteam/win64/steam_api64.dll": ""}
linux.release.x86_64 = {"res://addons/godotsteam/linux64/libsteam_api.so": ""}
"""

PEER_EXT = """[configuration]
entry_symbol = "steam_multiplayer_peer_init"
compatibility_minimum = "4.4"

[libraries]
windows.release.x86_64 = "res://addons/steam_multiplayer_peer/win64/libsteam_multiplayer_peer.windows.template_release.x86_64.dll"
linux.release.x86_64 = "res://addons/steam_multiplayer_peer/linux64/libsteam_multiplayer_peer.linux.template_release.x86_64.so"
"""


class SteamAddons(unittest.TestCase):
    """Steam's two GDExtensions (GodotSteam, and the multiplayer peer) are two downloads; the packager puts both in addons/."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, str(self.tmp), True)
        self.pk = P.Packager(P.parse_args(["--out", str(self.tmp / "dist")]))
        self.pk.root = self.tmp / "proj"
        self.pk.root.mkdir()

    def _zip(self, name, files):
        path = self.tmp / name
        with zipfile.ZipFile(str(path), "w") as z:
            for n, data in files.items():
                z.writestr(n, data)
        return path

    def _godotsteam_zip(self, top="godotsteam-4.x/"):
        a = "addons/godotsteam/"
        return self._zip("gs.zip", {
            top + a + "godotsteam.gdextension": GODOTSTEAM_EXT,
            top + a + "win64/libgodotsteam.windows.template_release.x86_64.dll": b"dll",
            top + a + "win64/steam_api64.dll": b"api",
            top + a + "linux64/libgodotsteam.linux.template_release.x86_64.so": b"so",
            top + a + "linux64/libsteam_api.so": b"api",
            top + "examples/" + a + "godotsteam.gdextension": GODOTSTEAM_EXT,      # a copy inside an example project
        })

    def _peer_zip(self):
        a = "addons/steam_multiplayer_peer/"
        return self._zip("peer.zip", {
            a + "steam_multiplayer_peer.gdextension": PEER_EXT,
            a + "win64/libsteam_multiplayer_peer.windows.template_release.x86_64.dll": b"dll",
            a + "linux64/libsteam_multiplayer_peer.linux.template_release.x86_64.so": b"so",
        })

    def test_a_download_is_copied_whole_under_the_folder_its_own_paths_name(self):
        self.pk.install_steam_addons(self._godotsteam_zip())
        base = self.pk.root / "addons" / "godotsteam"
        self.assertTrue((base / "godotsteam.gdextension").exists())
        self.assertTrue((base / "win64" / "steam_api64.dll").exists())
        self.assertTrue((base / "linux64" / "libsteam_api.so").exists())
        self.assertEqual(sorted(p.name for p in (self.pk.root / "addons").iterdir()), ["godotsteam"], "the example copy must not become a second addon")

    def test_each_of_the_two_downloads_adds_its_own_and_keeps_the_other(self):
        self.pk.install_steam_addons(self._godotsteam_zip())
        self.assertEqual(len(P.steam_addons_missing(self.pk.root)), 1)
        self.assertIn("multiplayer peer", P.steam_addons_missing(self.pk.root)[0])
        self.pk.install_steam_addons(self._peer_zip())
        self.assertEqual(sorted(P.steam_addons(self.pk.root)), ["godotsteam", "steam_multiplayer_peer"])
        self.assertEqual(P.steam_addons_missing(self.pk.root), [])

    def test_one_zip_with_both_gives_both(self):
        both = self._zip("both.zip", {"addons/godotsteam/godotsteam.gdextension": GODOTSTEAM_EXT,
                                      "addons/steam_multiplayer_peer/steam_multiplayer_peer.gdextension": PEER_EXT})
        self.pk.install_steam_addons(both)
        self.assertEqual(P.steam_addons_missing(self.pk.root), [])

    def test_an_unpacked_folder_works_too_even_when_it_is_named_otherwise(self):
        src = self.tmp / "GodotSteam 4.x download"
        (src / "win64").mkdir(parents=True)
        (src / "godotsteam.gdextension").write_text(GODOTSTEAM_EXT)
        (src / "win64" / "steam_api64.dll").write_bytes(b"api")
        self.pk.install_steam_addons(src)
        self.assertTrue((self.pk.root / "addons" / "godotsteam" / "win64" / "steam_api64.dll").exists())

    def test_installing_again_replaces_the_old_copy(self):
        self.pk.install_steam_addons(self._godotsteam_zip())
        stale = self.pk.root / "addons" / "godotsteam" / "old_leftover.txt"
        stale.write_text("x")
        self.pk.install_steam_addons(self._godotsteam_zip())
        self.assertFalse(stale.exists())

    def test_what_is_not_a_download_of_theirs_is_a_clear_stop(self):
        with self.assertRaises(P.Fail):
            self.pk.install_steam_addons(self.tmp / "missing.zip")
        notzip = self.tmp / "x.zip"
        notzip.write_text("not a zip")
        with self.assertRaises(P.Fail):
            self.pk.install_steam_addons(notzip)
        with self.assertRaises(P.Fail) as cm:
            self.pk.install_steam_addons(self._zip("empty.zip", {"readme.txt": "hi"}))
        self.assertIn("GDExtension", str(cm.exception))
        with self.assertRaises(P.Fail):
            self.pk.install_steam_addons(self._zip("slip.zip", {"../escape.txt": "x", "addons/godotsteam/godotsteam.gdextension": GODOTSTEAM_EXT}))
        self.assertFalse((self.tmp / "escape.txt").exists())

    def test_what_is_missing_is_said_in_words(self):
        miss = P.steam_addons_missing(self.pk.root)
        self.assertEqual(len(miss), 2)
        self.assertTrue(any("GodotSteam" in m for m in miss))
        self.assertTrue(any("multiplayer peer" in m for m in miss))
        d = self.pk.root / "addons" / "steam_multiplayer_peer"
        d.mkdir(parents=True)
        (d / "steam_multiplayer_peer.gdextension").write_text(PEER_EXT)
        miss = P.steam_addons_missing(self.pk.root)
        self.assertEqual(len(miss), 1)
        self.assertIn("GodotSteam", miss[0])      # the peer alone is not GodotSteam

    def test_the_peer_is_told_from_godotsteam_by_its_name(self):
        for n in ("steam_multiplayer_peer", "godotsteam_multiplayerpeer", "SteamMultiplayerPeer"):
            self.assertTrue(P.is_steam_peer(n), n)
        for n in ("godotsteam", "GodotSteam"):
            self.assertFalse(P.is_steam_peer(n), n)

    def test_a_zip_from_a_github_branch_has_a_wrapper_folder_and_a_hyphenated_name(self):
        base = "steam-multiplayer-peer-addon/addons/steam-multiplayer-peer/"
        ext = ('[configuration]\nentry_symbol = "x"\ncompatibility_minimum = "4.4"\n\n[libraries]\n'
               'windows.release.x86_64 = "res://addons/steam-multiplayer-peer/windows/libx.dll"\n'
               'linux.release.x86_64 = "res://addons/steam-multiplayer-peer/linux/libx.so"\n')
        z = self._zip("branch.zip", {base + "steam-multiplayer-peer.gdextension": ext,
                                     base + "windows/libx.dll": b"dll", base + "linux/libx.so": b"so"})
        self.pk.install_steam_addons(z)
        self.assertEqual(sorted(P.steam_addons(self.pk.root)), ["steam-multiplayer-peer"])
        self.assertTrue(P.is_steam_peer("steam-multiplayer-peer"))
        self.assertTrue((self.pk.root / "addons" / "steam-multiplayer-peer" / "linux" / "libx.so").exists())
        self.assertEqual(len(P.steam_addons_missing(self.pk.root)), 1, "the peer is there; GodotSteam is still wanted")

    STEAM_CHECK = ("WRECKSMITH 1.0.1.1.full\n"
                   "Steam library (GodotSteam): %s\n"
                   "Steam client: NOT READY (Steam is not running)\n"
                   "Multiplayer extension (SteamMultiplayerPeer): %s\n%s"
                   "Steam multiplayer: not available\n")
    PEER_CALLS = ("  peer call create_host: yes\n  peer call create_client: %s\n  peer call get_steam64_from_peer_id: yes\n")

    def _game_says(self, lib=True, peer=True, join="yes", output=None):
        """The packager's run of `-- --steam-check`, answered as the game would; returns (what was run, the patch)."""
        seen = {}

        def fake_run(cmd, cwd=None, timeout=None, env=None):
            seen["cmd"], seen["env"] = [str(c) for c in cmd], env
            if output is not None:
                return 0, output
            return 0, self.STEAM_CHECK % ("found" if lib else "NOT FOUND (addons/godotsteam is missing, or not loaded)",
                                          "found" if peer else "NOT FOUND", (self.PEER_CALLS % join) if peer else "")
        self.pk.godot = "/fake/godot"
        return seen, mock.patch.object(P, "run", fake_run)

    def test_the_game_itself_says_which_extensions_it_loads(self):
        seen, patch = self._game_says()
        with patch:
            self.assertEqual(self.pk.steam_extensions_found(), (True, True))
            self.assertEqual(self.pk.steam_missing(), [], "both are loaded: nothing is said missing, whatever the folders are called")
        self.assertEqual(seen["cmd"][-2:], ["--", "--steam-check"])
        self.assertIn("--headless", seen["cmd"])
        self.assertEqual(seen["env"]["SteamAppId"], "480", "the test app's id, so that a Steam client that is open does not matter")

    def test_a_download_that_carries_both_needs_no_second_one(self):
        # one zip holding both extensions under one name: the folder names would call the peer missing, the game does not
        self.pk.install_steam_addons(self._godotsteam_zip())
        self.assertEqual(len(P.steam_addons_missing(self.pk.root)), 1)
        seen, patch = self._game_says()
        with patch:
            self.assertEqual(self.pk.steam_missing(), [])

    def test_the_game_names_what_it_does_not_find(self):
        for lib, peer, want in ((False, True, ["GodotSteam"]), (True, False, ["multiplayer peer"]), (False, False, ["GodotSteam", "multiplayer peer"])):
            seen, patch = self._game_says(lib=lib, peer=peer)
            with patch:
                miss = self.pk.steam_missing()
            self.assertEqual(len(miss), len(want), miss)
            for w in want:
                self.assertTrue(any(w in m for m in miss), (w, miss))

    def test_a_peer_without_the_calls_that_open_and_join_a_room_counts_as_missing(self):
        seen, patch = self._game_says(join="MISSING")
        with patch:
            self.assertEqual(self.pk.steam_extensions_found(), (True, False))
            miss = self.pk.steam_missing()
        self.assertEqual(len(miss), 1)
        self.assertIn("multiplayer peer", miss[0])

    def test_when_the_game_cannot_be_run_the_folder_names_decide(self):
        self.pk.install_steam_addons(self._godotsteam_zip())
        seen, patch = self._game_says(output="could not run /fake/godot: no such file")
        with patch:
            self.assertIsNone(self.pk.steam_extensions_found())
            miss = self.pk.steam_missing()
        self.assertEqual(len(miss), 1)
        self.assertIn("multiplayer peer", miss[0])

    def test_the_options_take_several_downloads(self):
        a = P.parse_args(["--godotsteam", "a.zip", "b.zip", "--require-steam-lib"])
        self.assertEqual(a.godotsteam, ["a.zip", "b.zip"])
        self.assertEqual(P.parse_args(["--steam-addons", "x.zip"]).godotsteam, ["x.zip"])
        self.assertIsNone(P.parse_args([]).godotsteam)

    def test_a_depot_without_steams_library_is_told(self):
        self.pk.install_steam_addons(self._godotsteam_zip())
        self.pk.install_steam_addons(self._peer_zip())
        depot = self.tmp / "depot"
        depot.mkdir()
        (depot / "WRECKSMITH.exe").write_bytes(b"MZ")
        gaps = P.steam_depot_gaps(self.pk.root, "windows", depot)
        self.assertIn("steam_api64.dll", gaps)
        self.assertIn("libgodotsteam.windows.template_release.x86_64.dll", gaps)
        self.assertIn("libsteam_multiplayer_peer.windows.template_release.x86_64.dll", gaps)
        for n in gaps:
            (depot / n).write_bytes(b"x")
        self.assertEqual(P.steam_depot_gaps(self.pk.root, "windows", depot), [])
        self.assertIn("libsteam_api.so", P.steam_depot_gaps(self.pk.root, "linux", depot))

    def test_with_no_steam_extension_in_the_project_no_depot_is_faulted(self):
        depot = self.tmp / "depot"
        depot.mkdir()
        self.assertEqual(P.steam_depot_gaps(self.pk.root, "windows", depot), [])

    def test_steam_is_for_windows_and_linux_unless_the_ids_file_says_more(self):
        self.assertEqual(P.steam_platforms(P.load_steam_ids(P.ROOT)), ["windows", "linux"])
        self.assertEqual(P.steam_platforms({}), list(P.PLATFORMS))
        self.assertEqual(P.steam_platforms({"platforms": ["linux", "amiga"]}), ["linux"])
        self.assertEqual(P.steam_platforms({"platforms": []}), list(P.PLATFORMS))


class Licences(unittest.TestCase):
    """Every package carries THIRD_PARTY_LICENSES.txt; the game writes it (its Credits), so it holds the engine's own terms."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, str(self.tmp), True)
        self.pk = P.Packager(P.parse_args(["--out", str(self.tmp / "dist")]))
        self.pk.root = self.tmp / "proj"
        self.pk.build = self.tmp / "build"
        (self.pk.root / "data").mkdir(parents=True)
        (self.pk.root / "data" / "legal.json").write_text('{"holder": "", "year": "2026"}')
        self.pk.godot = "godot"

    def _probe(self, code=0, write=True):
        def fake(cmd, cwd=None, timeout=None, env=None):
            self.assertIn("licenses_dump", [str(c) for c in cmd])
            if write:
                Path(env["LICENSES_OUT"]).write_text("THE GAME\nGODOT ENGINE ... Permission is hereby granted\n")
            return code, ""
        return mock.patch.object(P, "run", side_effect=fake)

    def _extension(self, name="godotsteam", licence="MIT Licence\nCopyright (c) the GodotSteam contributors"):
        d = self.pk.root / "addons" / name
        d.mkdir(parents=True)
        (d / (name + ".gdextension")).write_text("[configuration]\n")
        if licence:
            (d / "LICENSE").write_text(licence)

    def test_the_credits_files_travel_in_every_export(self):
        text = (P.ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        lines = [l for l in text.splitlines() if l.startswith("include_filter=")]
        self.assertEqual(len(lines), 12)
        for l in lines:
            for need in ("data/*.json", "art/CREDITS.md", "art/fonts/OFL-*.txt"):
                self.assertIn(need, l)
        self.assertTrue((P.ROOT / "art" / "CREDITS.md").exists())

    def test_the_game_writes_the_file_and_the_downloads_get_it_as_it_is(self):
        with self._probe():
            self.pk.make_licenses()
        self.assertIn("Permission is hereby granted", self.pk.licenses["standalone"].read_text())
        self.assertEqual(self.pk.licenses["standalone"].name, P.LICENSES_FILE)
        dest = self.tmp / "stage"
        dest.mkdir()
        self.pk.put_licenses("standalone", dest)
        self.assertEqual((dest / P.LICENSES_FILE).read_text(), self.pk.licenses["standalone"].read_text())

    def test_the_steam_extensions_licences_ride_with_the_steam_builds_only(self):
        self._extension()
        self._extension("steam_multiplayer_peer", "The peer's own licence text")
        with self._probe():
            self.pk.make_licenses()
        base = self.pk.licenses["standalone"].read_text()
        steam = self.pk.licenses["steam"].read_text()
        self.assertNotIn("GodotSteam contributors", base, "the downloads have no Steam extension")
        self.assertIn("Copyright (c) the GodotSteam contributors", steam)
        self.assertIn("The peer's own licence text", steam)
        self.assertIn("Permission is hereby granted", steam, "and the Steam file holds the rest as well")
        dest = self.tmp / "depot"
        dest.mkdir()
        self.pk.put_licenses("steam", dest)
        self.assertIn("GodotSteam contributors", (dest / P.LICENSES_FILE).read_text())

    def test_the_depot_gets_the_file(self):
        with self._probe():
            self.pk.make_licenses()
        out = self.tmp / "export"
        out.mkdir()
        (out / "WRECKSMITH.exe").write_bytes(b"MZ")
        preset = P.find_preset(self.pk.presets, "full", "steam", "windows")
        dest = self.pk.stage_steam(preset, out / "WRECKSMITH.exe")
        self.assertTrue((dest / P.LICENSES_FILE).exists())

    def test_no_copyright_holder_is_said_once_and_a_holder_silences_it(self):
        with self._probe():
            self.pk.make_licenses()
        self.assertTrue(any("copyright holder" in n for n in self.pk.notes), self.pk.notes)
        self.pk.notes.clear()
        (self.pk.root / "data" / "legal.json").write_text('{"holder": "Acme Ltd", "year": "2026"}')
        with self._probe():
            self.pk.make_licenses()
        self.assertEqual(self.pk.notes, [])
        self.assertEqual(P.copyright_holder(self.pk.root), "Acme Ltd")
        (self.pk.root / "data" / "legal.json").write_text("not json")
        self.assertEqual(P.copyright_holder(self.pk.root), "")

    def test_a_probe_that_fails_stops_the_packing_unless_only_repacking(self):
        with self._probe(code=1, write=False):
            with self.assertRaises(P.Fail):
                self.pk.make_licenses()
        self.pk.a.skip_export = True
        with self._probe(code=1, write=False):
            self.pk.make_licenses()
        self.assertTrue(any("without it" in n for n in self.pk.notes), self.pk.notes)

    def test_the_project_ships_a_legal_file_and_the_probe(self):
        legal = json.loads((P.ROOT / "data" / "legal.json").read_text(encoding="utf-8"))
        for k in ("holder", "year", "site"):
            self.assertIn(k, legal)
        self.assertTrue((P.ROOT / "tests" / "licenses_dump.gd").exists())
        self.assertTrue((P.ROOT / "scripts" / "game" / "credits.gd").exists())


if __name__ == "__main__":
    unittest.main(verbosity=1)
