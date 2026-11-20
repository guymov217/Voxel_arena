# Packaging: for Steam, and for people without Steam

One command exports the game and packs it two ways:

| | What it is | Where |
|---|---|---|
| **Steam** | The files of each Steam depot, the SteamPipe scripts that upload them, and `upload.bat` / `upload.sh` | `dist/steam/` |
| **Without Steam** | A zip (Windows), a tar.gz (Linux), a zip with the `.app` (macOS) and a Windows installer, for people who just want to try the game | `dist/standalone/` |

Each is made for the **demo** and the **full game** (the same game; the demo is the `demo` feature,
`scripts/game/edition.gd`: campaign bouts 1 to 8, see `DEMO.md`). By default both channels get both
(`--standalone-editions demo` or `--steam-editions full` narrow it).

```
tools\package.bat            Windows: double-click it (or run it in a terminal)
python tools/package.py      anywhere (Python 3, nothing to install; tried with 3.11 to 3.13)
tools/package.sh             Linux, macOS, CI
```

When it ends it says what it made and writes `dist/PACKAGE_REPORT.md` (the files, sizes, checksums,
what each check found) and `dist/standalone/SHA256SUMS.txt`.

## What you need once

1. **Godot 4.7** (it finds it by itself: `GODOT`, `--godot PATH`, the folders Godot is usually unzipped to, the PATH).
   Close the editor while packaging.
2. **Godot's export templates** for the same version. Editor → *Manage Export Templates* → *Download and Install*
   (1.3 GB), or `package.bat --install-templates`, which fetches only the Windows, Linux and macOS release templates it
   needs (about 200 MB; 70 MB for Windows and Linux). Run by hand with templates missing, the packager asks whether to
   fetch them and goes on.
3. **For the Steam builds: the GodotSteam GDExtension** (4.x for Godot 4.7, from godotsteam.com or its GitHub releases).
   Put its `addons/godotsteam` folder in the project, or pass the zip: `package.bat --godotsteam C:\Downloads\godotsteam.zip`.
   Without it the Steam builds still run, but with no overlay, lobbies, achievements or cloud saves, and the report says so
   (`--require-steam-lib` turns that warning into a stop, for a release).
4. **For the Steam upload: your ids**, in `tools/steam/steam_ids.json` (below).
5. **NSIS** (`makensis`) for the Windows installer (a real `Setup.exe`). On Windows the packager asks, the first time, whether
   to fetch it: a 2 MB zip from nsis.sourceforge.io, checked against a checksum kept in `tools/package.py` and unpacked into
   `%LOCALAPPDATA%\WRECKSMITH\tools\` (nothing is installed on the system, no administrator, and `--clean` leaves it).
   `package.bat --install-nsis` does it without asking. Elsewhere: `apt install nsis` or `brew install makensis`. Without
   NSIS you get the zip only, and the report says so.

The voxel core library (`native/bin/`) must be there for each platform: Windows and Linux are committed; macOS's is
built on a Mac, so a local run skips macOS (and says so). The **Builds** workflow makes all three (below).

## Steam

### 1. Once, in Steamworks

`DEMO.md` has the steps: the full game's app and its store page, the demo as its own app, a depot per system, and the
launch options. The packager prints the launch option of each build (`dist/steam/README.txt`):

| Edition | Windows | Linux | macOS |
|---|---|---|---|
| Full game | `WRECKSMITH.exe` | `WRECKSMITH.x86_64` | `WRECKSMITH.app` |
| Demo | `WRECKSMITH_Demo.exe` | `WRECKSMITH_Demo.x86_64` | `WRECKSMITH_Demo.app` |

### 2. Put the ids in

Edit `tools/steam/steam_ids.json`: each app's id and its depots' ids (Steamworks → the app → *SteamPipe → Depots*).
`0` means "not yet": the scripts are still written, with placeholders, and `upload.bat` refuses to run until they are
real. After editing, `package.bat --skip-export` writes the scripts again without exporting.

### 3. Pack, then preview, then upload

```
tools\package.bat --channel steam            (or leave the channel out to make everything)
dist\steam\upload.bat demo preview           lists what would go up; uploads nothing
dist\steam\upload.bat demo                   the real upload (steamcmd asks the password and the Steam Guard code)
dist\steam\upload.bat full
```

`upload.bat` finds `steamcmd` through the `STEAMCMD` variable, `C:\steamcmd`, `D:\steamcmd` or the PATH (the Steamworks
SDK's `tools\ContentBuilder\builder\steamcmd.exe` will do). Then, in Steamworks → *SteamPipe → Builds*, set the build live
on a beta branch, test it through the Steam client, and only then on `default`. The scripts do not set anything live.

What goes into a depot is exactly `dist/steam/content/<edition>/<platform>/`: the game's program and the voxel core
library beside it, nothing else. **`steam_appid.txt` is never in it** (Steam gives the app id itself when it starts the
game; the file is only for running outside Steam while testing).

Worth knowing:

- **Linux depots: upload from Linux or macOS** (`upload.sh`), so the program's executable bit is kept. A Linux build
  uploaded from Windows may not start on a player's machine ("permission denied").
- **The scripts follow the SteamPipe sample layout** (`AppBuild` + one `DepotBuildConfig` per depot, `ContentRoot`
  `../content/<edition>/`, paths relative to the script). That page of Valve's documentation could not be read while this
  was written, so run the **preview** first: it shows the file list SteamPipe would take, and nothing is uploaded.
- **Steam Cloud, achievements, the content survey:** `DEMO.md` (section 4).

## Without Steam

`dist/standalone/` holds, for each platform:

| File | For |
|---|---|
| `WRECKSMITH-Demo-<version>-windows.zip` | Unzip, double-click `WRECKSMITH_Demo.exe` |
| `WRECKSMITH-Demo-<version>-windows-setup.exe` | The same, installed, as in any game: a wizard (welcome page, folder, finish page with *Run WRECKSMITH*), per user (no administrator), a Start menu entry, an optional desktop shortcut, an uninstaller under *Installed apps*. The wizard, the exe and the shortcuts all wear the game's icon |
| `WRECKSMITH-Demo-<version>-linux.tar.gz` | `tar xzf`, run `WRECKSMITH_Demo.x86_64` |
| `WRECKSMITH-Demo-<version>-macos.zip` | Unzip, right-click the `.app` → Open the first time |

Each has a `README.txt` beside the game (how to start, where the saves are, how to play with friends by address).
**These builds never start Steam**: they are exported with the `standalone` feature, which `scripts/net/net.gd` checks
before it touches Steam, and the GodotSteam library is left out of them. (Without that, a player with Steam open would
show up as playing Valve's test app 480.) Steam lobbies, the overlay, achievements and cloud saves are Steam-only;
online play by address works in both.

Nothing is **signed**: Windows SmartScreen will say the publisher is unknown (*More info → Run anyway*), and macOS asks for
a right-click → Open. Signing needs a code-signing certificate (Windows) or an Apple developer account (macOS, which Steam
also wants for a macOS build).

Where to put them is yours to choose (your website, itch.io with `butler push dist/standalone/<file> user/game:windows`,
a Discord). `SHA256SUMS.txt` lets people check a download.

## The game's own look: icon, start-up picture, installer pictures

Everything the player sees before the game's menu is the game's, not Godot's:

| What | Where it comes from |
|---|---|
| The `.exe`'s icon (Explorer, the taskbar, shortcuts, *Installed apps*), its name and version in *Properties → Details* | The Windows presets (`export_presets.cfg`: `application/icon`, `product_name`, `file_version`...; Godot 4.7 writes them into the exe itself, no `rcedit`); the version is `config/version` of `project.godot` |
| The macOS `.app`'s icon | `application/icon` of the macOS presets (`art/icon/wrecksmith.icns`) |
| The picture shown while the game starts (it was Godot's logo) | `art/splash.png`, set in `project.godot` (`application/boot_splash/*`): the emblem over the logo on the menus' dark brown. The bars round it, in a window that is not 16:9, are the same brown |
| The first two seconds and a half of the game | `scripts/ui/intro.gd` plays that picture again as the first scene, alive: the swords strike (the emblem flares, a warm light and a ring go out, sparks fly, a clang), a gleam runs across the logo (`shaders/intro_gleam.gdshader`), embers drift up. Its first frame is the boot splash's, so the two join without a seam; the menu is built behind its last frame and it fades off the menu. Any key skips it; it is not played in the tests, probes, headless runs or with `-- --no-intro` |
| The installer's icon, welcome and finish pages, header | `art/icon/wrecksmith.ico`, `tools/installer/welcome.bmp`, `header.bmp` |

`python tools/make_app_icon.py` (Python with Pillow) makes all of them from `icon.png` (the emblem) and
`docs/store/capsules/logo_stacked.png` (the logo), and the emblem and the logo each alone on a clear frame
(`art/intro/`) for the opening to animate; run it again when either changes and commit what it writes (it prints where
the pieces are: `EMBLEM_CENTRE` and `LOGO_BOX` in `intro.gd` must follow, `tests/test_intro.gd` checks them). The
`art/icon/` files are for the packager and are not packed into the game.

## The Builds workflow (all three platforms)

`.github/workflows/build.yml` builds the C++ core for Windows, Linux and macOS, runs the tests and then `tools/package.py`
with all three platforms, and attaches `wrecksmith-steam`, `wrecksmith-standalone` and `package-report` to the run. Start it
from the repository's *Actions* tab, or push a tag such as `v0.1`. To put GodotSteam in the Steam builds there, set the
repository variable `GODOTSTEAM_URL` (Settings → Secrets and variables → Actions → Variables) to the address of the
GodotSteam GDExtension zip.

## The options

```
--channel steam|standalone|both     default both
--steam-editions demo,full          default demo,full
--standalone-editions demo,full     default demo,full
--platforms windows,linux,macos     default: every platform whose voxel core library is here
--godot PATH   --version X          Godot's program; the version in the file names (default: config/version)
--skip-export                       pack again what build/ holds (new Steam ids, a changed README)
--skip-tests                        do not run the Linux build to check it
--no-installer                      no Windows installer
--install-nsis                      fetch NSIS (2 MB, Windows) when it is missing, for the installer
--install-templates                 fetch the missing export templates (only the needed ones)
--godotsteam PATH                   the GodotSteam zip or folder, put in addons/ for the Steam builds
--require-steam-lib                 stop if the Steam builds would have no GodotSteam
--clean                             empty build/ and dist/ first
```

## What it checks

- Every export must finish with no `ERROR` line from Godot, and its program must exist.
- **Linux builds are run** (headless, 150 frames): exit 0 and no error line, which also catches a missing voxel core
  library. Windows builds are run when packaging on Windows; elsewhere they are checked for the library beside the exe.
  macOS zips are checked for the `.app` (and its framework).
- `python tools/test_package.py` (also in `run_tests.sh`) pins the presets (twelve: full and demo × Windows, Linux, macOS ×
  Steam, standalone), the SteamPipe scripts, the archives (a Linux program stays executable), that `net.gd` guards Steam,
  the icon and the start-up picture, and the NSIS fetch (checksum, unpacking, a zip that reaches outside its folder).

## Not done yet

- No code signing (`RELEASE_HE.md` says what it costs and when it matters); no Windows run of the packaged exe was possible where this was written (a Linux machine): the Windows
  build was checked for its files, the Linux one was run. Try the Windows zip once on a real PC.
- A Steam build was never uploaded (no Steam account here): use the preview.
