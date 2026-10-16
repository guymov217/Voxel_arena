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

## If something is wrong

- "Could not find Godot": put `Godot_v4.7.2-stable_win64.exe` next to the .bat, or drag the exe
  onto the black window when asked.
- A black window and a wall of "Identifier not declared" errors: the project was not imported.
  Delete the `.godot` folder inside the game's folder and run the .bat again; it imports first.
- The guest never joins: something else holds port 7777, or an antivirus blocks it. Try again
  after a reboot, or run only option 2.
- Send a screenshot of each window's room screen; that is enough to tell what happened.
