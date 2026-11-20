# Packaging: for Steam, and for people without Steam

One command exports the game and packs it two ways:

| | What it is | Where |
|---|---|---|
| **Steam** | The files of each Steam depot, the SteamPipe scripts that upload them, and `upload.bat` / `upload.sh` | `dist/steam/` |
| **Without Steam** | A zip (Windows), a tar.gz (Linux), a zip with the `.app` (macOS) and a Windows installer, for people who just want to try the game | `dist/standalone/` |

Each is made for the **demo** and the **full game** (the same game; the demo is the `demo` feature,
`scripts/game/edition.gd`: campaign bouts 1 to 8, see `DEMO.md`). By default Steam gets both,
and the download without Steam gets the demo (`--standalone-editions demo,full` adds the full game).

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
   needs (about 200 MB).
3. **For the Steam builds: the GodotSteam GDExtension** (4.x for Godot 4.7, from godotsteam.com or its GitHub releases).
   Put its `addons/godotsteam` folder in the project, or pass the zip: `package.bat --godotsteam C:\Downloads\godotsteam.zip`.
   Without it the Steam builds still run, but with no overlay, lobbies, achievements or cloud saves, and the report says so
   (`--require-steam-lib` turns that warning into a stop, for a release).
4. **For the Steam upload: your ids**, in `tools/steam/steam_ids.json` (below).
5. **Optional: NSIS** (`makensis`) for the Windows installer; without it you get the zip only. `apt install nsis`, or
   nsis.sourceforge.io on Windows.

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
| `WRECKSMITH-Demo-<version>-windows-setup.exe` | The same, installed: per user (no administrator), a Start menu entry, an optional desktop shortcut, an uninstaller under *Installed apps* |
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
--standalone-editions demo          default demo
--platforms windows,linux,macos     default: every platform whose voxel core library is here
--godot PATH   --version X          Godot's program; the version in the file names (default: config/version)
--skip-export                       pack again what build/ holds (new Steam ids, a changed README)
--skip-tests                        do not run the Linux build to check it
--no-installer                      no Windows installer
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
  Steam, standalone), the SteamPipe scripts, the archives (a Linux program stays executable) and that `net.gd` guards Steam.

## Not done yet

- The Windows program carries Godot's icon and version text (`application/modify_resources=false`); an `.ico` and rcedit
  would set them.
- No code signing; no Windows run of the packaged exe was possible where this was written (a Linux machine): the Windows
  build was checked for its files, the Linux one was run. Try the Windows zip once on a real PC.
- A Steam build was never uploaded (no Steam account here): use the preview.
