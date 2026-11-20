#!/usr/bin/env python3
"""Checks of tools/package.py that need no Godot: the export presets, the SteamPipe scripts, the archives.
Run:  python tools/test_package.py        (run_tests.sh runs it when Python is there)"""
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

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
            leaves_out = "addons/godotsteam/*" in p.exclude
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


class Basics(unittest.TestCase):
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

    def test_sha256_matches_the_tool(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            f = tmp / "a.bin"
            f.write_bytes(b"abc")
            self.assertEqual(P.sha256(f), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main(verbosity=1)
