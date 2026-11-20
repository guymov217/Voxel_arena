# The Steam demo

The demo is the same game exported with the `demo` feature (`scripts/game/edition.gd`):

- **Campaign:** bouts 1 to 8, alone or as a co-op party, up to the second boss (the Big Lion at
  bout 4, the Cyclops at bout 8). Then a plain "The end of the demo" screen: play it again from
  bout 1, or back to the menu.
- **Arena:** alone, the duel, best of three, the free-for-all and the endless arena. In a room,
  the players' brawl (everyone against everyone) and the free-for-all. The other modes are not on
  the menu.
- **The endless arena** (main menu, and The Arena → Beasts and waves): its waves come from the
  demo's own men and beasts, and its great foes, every fifth wave, are the Big Lion and the
  Cyclops. When the player falls, the last screen says how many more great foes the full game
  holds, without naming them.
- **Training:** the men and beasts of the demo's bouts, plus the bear and the gorilla.
- **Everything else is in:** the forge (voxel by voxel, gems, the gallery), the armourer's bench,
  the yard, the physician, the kill cam.
- **Clips:** every kill puts a marker on the Steam game recording's timeline, so players find a
  moment and clip it in a click (the best kills are flagged as featured). F12 saves a screenshot
  when Steam is not running. No marks or messages are added to the picture.

Try it without exporting: double-click `play_demo.bat` (Windows; set `GODOT` to your Godot exe if
it is not on the PATH) or run `./play_demo.sh`, or `godot --path . -- --demo`, or `WRECKSMITH_DEMO=1`.
The *Builds* workflow also exports and packs the demo itself (artifacts `wrecksmith-steam` and
`wrecksmith-standalone`), from whatever is on the branch (`docs/PACKAGING.md`).

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

### 3. Build and upload

`docs/PACKAGING.md` has the whole story; in short:

```
tools\package.bat --channel steam --steam-editions demo     exports the demo and packs it into dist/steam/
(put the demo's App id and its depot ids in tools/steam/steam_ids.json, then: tools\package.bat --skip-export)
dist\steam\upload.bat demo preview                          lists what would go up, uploads nothing
dist\steam\upload.bat demo                                  the upload (steamcmd asks the password and the Steam Guard code)
```

Then in Steamworks, *SteamPipe → Builds*: set the uploaded build live on a private beta branch, test it through the Steam
client, and only then on the `default` branch. The *Builds* workflow (Actions tab, or push a `v*` tag) does the same for all
three systems and attaches the result (`wrecksmith-steam`, `wrecksmith-standalone`) to the run. The same command makes the
free download for people without Steam (`dist/standalone/`: a zip, a tar.gz, a Windows installer).

### 4. Steam Cloud, achievements and the content survey

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
  icons are 64×64 PNG, a lit and a grey one each: `art/achievements/<API name>.png` and
  `<API name>_locked.png`, made by `tools/make_achievement_icons.py`):

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
- **Trailer:** `tools\make_trailer75.bat` (`tools/TRAILER.md`), the 75-second one, made from
  the game.
