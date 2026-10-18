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
   - **host keeps up**: the host's physics steps a second, of 120. Green from 112. Under 95
     (red) the host's computer cannot keep up and the whole game slows for everyone: fewer
     players or enemies, or a stronger host.
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

## If something is wrong

- "Could not find Godot": put `Godot_v4.7.2-stable_win64.exe` next to the .bat, or drag the exe
  onto the black window when asked.
- A black window and a wall of "Identifier not declared" errors: the project was not imported.
  Delete the `.godot` folder inside the game's folder and run the .bat again; it imports first.
- The guest never joins: something else holds port 7777, or an antivirus blocks it. Try again
  after a reboot, or run only option 2.
- Send a screenshot of each window's room screen; that is enough to tell what happened.
