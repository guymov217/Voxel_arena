# Trying multiplayer on one computer

No command line. Three things to do once, then one double-click each time.

## Once

1. Download **Godot 4.7.2** (Windows, 64-bit, the plain build, not .NET) from
   https://godotengine.org/download/windows/ and unzip it. You get a file called
   `Godot_v4.7.2-stable_win64.exe`.
2. Put that file **in the game's folder**, next to `project.godot` and `multiplayer_test.bat`.
   (Downloads or the Desktop also work; the script looks there too.) An older Godot, such as
   4.4.1, is refused: the game is made for 4.7.

That is all. The first run imports the project by itself (a minute or two).

## Each time

Double-click **`multiplayer_test.bat`** in the game's folder. It finds Godot and asks:

| Key | What opens |
|-----|------------|
| 1 | A host window and a guest window, both yours. Alt+Tab between them. |
| 2 | A host window for you and a guest played by a bot: a real online bout with one pair of hands. |
| 3 | Like 2, with a pretend poor connection (120 ms delay, 3% packet loss). |
| 4 | A host and two bot guests. |

The host's window is in the **yard** from the first moment: the online lobby with the smith, the
physician, the mission board, the practice dummies and the gate. Each guest walks into that
yard as it joins. At the gate the host picks what everyone plays next, the co-op campaign or one
of the arena modes, and after the bout everyone is back in the yard.

## What to check

- Both players are in the yard and see each other walk about; E by a keeper opens his stall in
  either window, and the purse shown is the same in both.
- The host walks into the gate and picks a bout; the guest's window follows into it.
- Esc in either window: **Settings** (keys, mouse, sound) for every player; for the host also
  **Back to the yard (everyone)** in the middle of a bout; **Leave the room** / **Close the room**.
- A guest who joins late walks into the yard; one who closes the game is gone from it within
  about ten seconds.
- In the fight, both fighters are drawn in both windows; the guest moves and strikes.
- Damage (voxels flying, blood) shows in the other window too.
- The round ends for both at once.
- In the yard, the purse is shared: buying in one window changes the coins in the other.
- With option 3, the guest's movement should feel a little late but never freeze or jump.

## Two real computers on one network

On the host computer double-click `multiplayer_test.bat` and pick 1, then close the guest window
it opened. On the second computer open the game in Godot, go to **Multiplayer**, and join
`192.168.x.x` (the host's address: on the host, `ipconfig` in a command prompt shows it as
IPv4 Address). If Windows asks about the firewall, allow it. Over the internet the host also
needs port 7777 (UDP) forwarded on the router; Steam lobbies avoid that.

## Before any players: what a computer can host

The host's computer runs the physics of every fighter on the sand; a guest's only draws what
the host sends. So the first question, how big a room a computer can host, needs no network
and no players: double-click **`tools/host_bench.bat`** (Windows; `sh tools/host_bench.sh` on
Linux) on that computer. In about a minute it plays fights of 4, 8, 12 and 16 fighters as fast
as the computer goes and says, for each, the time of a physics step against the 8.3 ms there is
(120 steps a second), and the most fighters it hosts smoothly. A fighter counts whoever is on
the sand: players and enemies.

On the cloud test machine (a 2.8 GHz server core): 4 fighters smooth (6.0 ms), 8 at 10.7 ms,
16 at 22.4 ms. A gaming PC is usually faster per core than that.

A bad connection can be tried on one computer too: `set LAG=150 & set LOSS=3` before
`multiplayer_test.bat` holds every message back 150 ms and loses 3% of them; F3 shows what that
does.

## Over Steam, with real players

Nothing on one computer says how a game goes between homes: only real players over Steam do. So
before the demo goes out:

1. **Steam build.** Upload the build to a private beta branch (docs/DEMO.md) and give the testers
   keys or the branch password. The game needs GodotSteam and the Steam client running: the
   Multiplayer menu then offers **Host a Steam lobby**.
2. **Rounds of players.** 2 players first, then 4, then a full room of 8. Each round, a campaign
   bout with enemies and a free-for-all, 10 minutes. Change who hosts: a fast computer, then an
   ordinary one (the host's computer runs the whole fight), and players far apart (another
   country) at least once.
3. **The meter.** Everyone presses **F3** in the room. In the corner:
   - **ping**: the round trip to the host. Green under 80 ms, amber to 150, red over.
   - **host keeps up**: the host's physics steps a second, of 120, and the frames a second it
     draws them in. Steps green from 112; under 95 (red) the host's computer cannot keep up and
     the whole game slows for everyone: fewer players or enemies, or a stronger host. Frames
     green from 45, red under 30. **my game** (guests) says the same of your own window.
   - **snapshots** (guests): about 40 a second, fewer in a full room; **longest wait** under
     90 ms is smooth, over 200 ms is a stutter.
   - **in / out**: KB a second. The host's "out" is his upload: it must stay well under his
     line's upload (1 Mbit/s is 125 KB/s).
4. **What each player says.** Did my fighter answer my mouse at once? Did others move smoothly
   or jump? Did hits land where they looked? Note the time of anything odd.
5. **The record.** While F3 is open the game writes a line a second to `net_log.csv` in its
   data folder (Windows: `%APPDATA%\Godot\app_userdata\WRECKSMITH`, Linux:
   `~/.local/share/godot/app_userdata/WRECKSMITH`). Collect everyone's after the session: the
   numbers at the moments people noted say whether it was the line (ping, waits) or the host
   (steps).

Before that, on one computer: `sh tools/net_load.sh 7` plays a full room of bots over localhost
and says what the host sends and whether it keeps up (README, Load test).

## If everything looks slow (slow motion)

Press **F3** in both windows (the host's and the guest's) and read two lines.

- **host keeps up N/120 steps**: under 100 means the host's world itself is slow, and so is what the guest sees.
  Next to it the frames a second: **red (under 30)** means the host's window draws slowly (two windows on one
  computer, the window behind the other, the first minute after a new build compiling its shaders), and a room
  now lets the game catch up from that (a frame runs up to 12 physics steps, as many as they cost allows, instead
  of the engine's 4); if it is still short, the steps themselves cost too much for the computer (too many fighters:
  `tools/host_bench.bat` says how many it hosts). Close one of the windows, or give the host the stronger computer.
- **my game** (on the guest): the same for the guest's own window; a slow guest is a choppy picture, not a slow game.
- The network is not the usual cause: a guest costs the host about 45 KB a second, a snapshot comes 40 times a second,
  and on one computer the ping is under 10 ms.
- **Two windows on one computer share one graphics card.** In a test video both windows were full screen at 1440p (9 ms
  of graphics card to a frame each): the window in front drew 90 frames a second and the one behind it, the host's, 17;
  the host kept its 120 steps, but it took input and sent the world in bursts every 60 ms, and the guest felt every
  answer late. The game starts full screen unless the player chose otherwise, so the launchers
  (`multiplayer_test.bat`, `tools/mp_local.bat`/`.sh`) now start the windows with `-- --keep-window`: the window stays as
  their `--position`/`--resolution` made it (1100x650, side by side) instead of the saved display mode. Do not maximise
  both; a window at 1100x650 has a fifth of the pixels of one at 1440p.

Send `net_log.csv` (below) from both windows with the time it looked slow: it has the steps, the frames a second and
the cost of one step (ms) of each side every second.

## If something is wrong

- "Could not find Godot": put `Godot_v4.7.2-stable_win64.exe` next to the .bat, or drag the exe
  onto the black window when asked.
- A black window and a wall of "Identifier not declared" errors: the project was not imported.
  Delete the `.godot` folder inside the game's folder and run the .bat again; it imports first.
- The guest never joins: something else holds port 7777, or an antivirus blocks it. Try again
  after a reboot, or run only option 2.
- Send a screenshot of each window's room screen; that is enough to tell what happened.

## Steam: one test with a second person

What `run_tests.sh` plays is the game's own Steam code with a stand-in for Steam (README, "What is tested, and what is
not"). What only Steam shows is Valve's real calls, its relay and the invites, so that needs **two Steam accounts at the same
time**: a friend, a relative, or a second PC with another account (one account cannot join its own lobby). About 15
minutes, and it works **before** Valve has approved the app, with the test app id 480 (Spacewar). Nothing here is shown to the
public: with 480 everybody's test lobbies share one list, which is why the game only lists rooms that carry its own tag and
its own build.

**Once, on each PC**

1. Steam is running and signed in (a different account on each PC).
2. The game, one of two ways:
   - **Your PC (the project):** the project folder with Godot, and in it `addons/godotsteam/` (the build from the Asset Store
     carries the multiplayer peer; `PACKAGING.md` says where to get it and when a separate peer is needed). Double-click **`steam_check.bat`**.
   - **The other person's PC (the built game):** copy the folder `dist/steam/content/full/windows/` (or the Linux one). Put a text
     file `steam_appid.txt` containing `480` beside the program, open a Command Prompt in that folder and run
     `WRECKSMITH.exe -- --steam-check` (Linux: `./WRECKSMITH.x86_64 -- --steam-check`).
3. The check opens a window and writes `steam_check.txt` (in the game's user folder). It must say
   **`Steam multiplayer: READY`**, and its live test (a room opened and joined on this PC alone) must have no FAILED line. If it says
   what is missing instead, stop there and send that text.

**The test** (A hosts, B joins)

| # | A | B | You should see |
|---|---|---|---|
| 1 | Multiplayer → Host a Steam lobby | | A is in a room; Steam shows A as "In an arena" to friends |
| 2 | | Multiplayer → the room list | A's room is listed with A's name and 1 player |
| 3 | | Join it | B appears in A's room; both see each other walk in the yard |
| 4 | Start a bout (the gate) | | both fight; damage and voxels show on both screens; the round ends for both |
| 5 | | Esc → Leave | A sees B go; B lands on the multiplayer screen |
| 6 | **Invite friends (Steam)** | accepts the invite in Steam's overlay | Steam's invite window opens; B lands in A's room |
| 7 | | closes the game; A invites again; B accepts | the game starts by itself and B lands in A's room (`+connect_lobby`) |
| 8 | Esc → Close the room | | B is told the host left; the room is gone from the list |
| 9 | Send me `user://steam_check.txt` and what felt wrong (a hitch, a delay, a voice that stuttered) | same | |

With **different builds** (one PC with an older copy) the room must not be listed for the older one, and an invite must be
refused with "That room runs another version of the game". If both PCs are far apart, note the ping in the F3 meter.

**Before launch**, once more with the real app: upload the build to a private beta branch, install it through Steam on
both PCs, and repeat steps 1 to 8 with no `steam_appid.txt` and no 480 (Steam gives the real id).
