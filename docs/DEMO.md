# The Steam demo

The demo is the same game exported with the `demo` feature (`scripts/game/edition.gd`):

- **Campaign:** bouts 1 to 8, alone or as a co-op party, up to the second boss (the Big Lion at
  bout 4, the Cyclops at bout 8). Then a plain "The end of the demo" screen: play it again from
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

### 4b. Steam Cloud, achievements and the content survey

- **Steam Cloud.** The game keeps one save file, `user://save.json` (with `save.json.bak` beside
  it; see `scripts/autoload/save.gd`), so Steam Auto-Cloud covers it without code. In Steamworks,
  *Application → Steam Cloud*: set a per-user quota (1 MB and 2 files are plenty), turn on
  *Enable cloud support for developers only* while testing, and add one Auto-Cloud root:
  root `GodotUserData` (Windows `%APPDATA%\Godot\app_userdata\WRECKSMITH`, Linux
  `~/.local/share/godot/app_userdata/WRECKSMITH`, macOS `~/Library/Application
  Support/Godot/app_userdata/WRECKSMITH`), pattern `save.json*`, with the Linux and macOS
  overrides set to the same path on those platforms. The demo and the full game are two apps,
  so each has its own cloud; Steam does not carry a demo save into the full game.
- **Achievements.** `scripts/game/achievements.gd` marks them: in the save at once (so nothing
  is lost offline) and on Steam when it runs (`setAchievement` + `storeStats`; at the menu the
  save's list is pushed to Steam again, so a client that comes later gets them all). Set them up
  in Steamworks, *Stats & Achievements → Achievements*, with these API names and texts (the
  icons are 64×64 PNG, a lit and a grey one each):

  | API name | Name | Description |
  |---|---|---|
  | `first_blood` | First Blood | Your first kill in the arena. |
  | `headsman` | Headsman | Ten heads taken. |
  | `beast_slayer` | Beast Slayer | Bring down a beast. |
  | `boss` | The Emperor's Pet | Beat a boss of the campaign. |
  | `eight_bouts` | Eight Bouts | Clear the eighth bout of the campaign. |
  | `halfway` | Halfway to the Rudis | Clear the thirty-second bout. |
  | `rudis` | The Rudis | Win the campaign: the wooden sword is yours. |
  | `rudis_again` | Twice Free | Win the campaign a second time round. |
  | `jupiter_hand` | The Hand of Jupiter | Hurl a man hard enough that his landing hurts. |
  | `trained` | A Body of Iron | Take one of the trainer's abilities to its best. |
  | `smith` | Wrecksmith | Keep a weapon of your own design. |
  | `armourer` | Armourer | Keep a piece of armour of your own design. |
  | `lifted` | Brother in Arms | Lift a friend from death's door. |
  | `javelin` | Javelin | Kill a man with a thrown weapon. |
  | `darling` | Darling of the Crowd | Win the whole crowd over in one bout. |

  Set the same list on the demo app (what its eight bouts cannot reach stays unearned; an id
  the app does not know is refused by Steam and simply kept in the save). Publish the
  achievement set from Steamworks before the build goes live, or `setAchievement` is refused.
- **Content survey.** In Steamworks, *Store presence → Content survey*, answer for both apps:
  frequent violence and gore (voxel dismemberment, blood, organs; the Gore setting, Full or
  Reduced, tones the innards down but not the blood), no nudity, no sexual content, no drugs beyond the wine
  of a decree, no real-world gambling (the bets are for in-game denarii), fantasy violence
  against humans and animals. Mature content description for the store page: "Frequent gory
  violence: limbs cut off, blood and innards (can be reduced in the options)".

### 5. Before release

- **Checks:** play bout 1 to 8 from a fresh save, alone and with a friend over a Steam lobby.
  Check the end screen.
- **Store review:** submit the demo's store presence and build for Steam review. It takes a few
  days.
- **Steam Next Fest:** register in Steamworks (*Marketing → Steam Next Fest*) and have the demo
  live a few weeks before the festival.
- **Trailer:** cut the first seconds from kill cam clips, and lead with the gorilla, the cyclops
  and the forge.
