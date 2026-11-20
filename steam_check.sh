#!/bin/sh
# Steam check: what this game finds of Steam on this PC (the GodotSteam library, the running Steam client, the
# multiplayer extension, the lobby calls). Run it with Steam open, before trying a room with a friend
# (docs/PACKAGING.md). The app id is 480 (Valve's test app) unless SteamAppId is set. Godot: $GODOT, else `godot`.
G=${GODOT:-godot}
cd "$(dirname "$0")" || exit 1
SteamAppId=${SteamAppId:-480} SteamGameId=${SteamAppId:-480} exec "$G" --path . -- --steam-check "$@"
