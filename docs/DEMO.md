# The Steam demo

The demo is the same game exported with the `demo` feature (`scripts/game/edition.gd`):

- **Campaign:** bouts 1 to 8, alone or as a co-op party, up to the second boss (the Cyclops at
  bout 4, the Big Lion at bout 8). Then a plain "The end of the demo" screen: play it again from
  bout 1, or back to the menu.
- **Arena:** alone, the duel, best of three and the free-for-all. In a room, the players' brawl
  (everyone against everyone) and the free-for-all. The other modes are not on the menu.
- **Training:** the men and beasts of the demo's bouts, plus the bear and the gorilla.
- **Everything else is in:** the forge (voxel by voxel, gems, the gallery), the armourer's bench,
  the yard, the physician, the kill cam.
- **Clips:** every kill puts a marker on the Steam game recording's timeline, so players find a
  moment and clip it in a click (the best kills are flagged as featured). F12 saves a screenshot
  when Steam is not running. No marks or messages are added to the picture.

Try it without exporting: `godot --path . -- --demo`, or `WRECKSMITH_DEMO=1`.

## Shipping it on Steam

### 1. Steamworks

1. **The full game's app.** It needs a store page that is at least *Coming Soon*: a demo cannot
   be released before its game's page is public.
2. **The demo app.** On the full game's app in Steamworks, open *All Associated Packages, DLC,
   Demos and Tools* and choose **Add demo**. Steam gives the demo its own App ID at no fee, with
   its own depots and its own (short) store presence linked to the game.
3. **Depots.** In the demo app's *SteamPipe → Depots*, add a Windows depot (and a Linux one if
   you ship Linux). Note their depot IDs.
4. **Launch options.** Under *Installation → General*, add the executable:
   `WRECKSMITH_Demo.exe` for Windows and `WRECKSMITH_Demo.x86_64` for Linux.
5. **Store page settings.** Set the demo to *free*. In the full game's page settings, turn on
   "show demo on the store page" so the *Download demo* button appears there.

### 2. The project

1. **GodotSteam.** Install the GodotSteam GDExtension (see README, *Multiplayer and GodotSteam*)
   and ship its `addons/` folder and the `steam_api` library with the export. Without it, the
   demo still runs, but without Steam lobbies, the overlay or timeline markers.
2. **App ID file.** Put the **demo's** App ID in `steam_appid.txt` next to the executable for
   testing outside Steam. Do not ship that file in the depot: when launched by Steam, Steam
   passes the App ID itself.

### 3. Build

Run the *Builds* workflow (Actions tab, or push a `v*` tag). Besides the full game, it exports
`wrecksmith-demo-windows`, `wrecksmith-demo-linux` and `wrecksmith-demo-macos`.

Locally:
```
godot --headless --path . --export-release "Windows Desktop (Demo)" build/demo/windows/WRECKSMITH_Demo.exe
godot --headless --path . --export-release "Linux (Demo)" build/demo/linux/WRECKSMITH_Demo.x86_64
```

### 4. Upload (SteamPipe)

1. Put the exported folders in `build/demo/windows/` and `build/demo/linux/`.
2. In `tools/steam/`, replace `DEMO_APP_ID` and the depot IDs in the three `.vdf` files.
3. With the Steamworks SDK's `steamcmd`:
   ```
   steamcmd +login <builder account> +run_app_build ../tools/steam/app_build_demo.vdf +quit
   ```
4. In Steamworks, *SteamPipe → Builds*: set the uploaded build live on the `default` branch.
   Before that, test it on a private beta branch through the Steam client.

### 5. Before release

- **Checks:** play bout 1 to 8 from a fresh save, alone and with a friend over a Steam lobby.
  Check the end screen.
- **Store review:** submit the demo's store presence and build for Steam review. It takes a few
  days.
- **Steam Next Fest:** register in Steamworks (*Marketing → Steam Next Fest*) and have the demo
  live a few weeks before the festival.
- **Trailer:** cut the first seconds from kill cam clips, and lead with the gorilla, the cyclops
  and the forge.
