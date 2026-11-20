class_name Credits
extends RefCounted
## The game's credits and the licences of what it is made with: what the Credits screen of the menu shows, and the text of
## THIRD_PARTY_LICENSES.txt that every package carries (tools/package.py has the game write that file: `-- --probe
## licenses_dump`). Godot's own terms come from the engine itself (Engine.get_license_text, get_license_info,
## get_copyright_info), so they are always those of the build that is running; the fonts' licences and the sounds'
## credits are the files in art/. DOM-free: tests/test_credits.gd runs it headless.

## Who holds the game's copyright, for the "©" line (data/legal.json). While `holder` is empty the line is left out and
## the packager says so: it is the owner's to say, not to guess.
const LEGAL := "res://data/legal.json"
## The fonts and where each one's licence text is (art/CREDITS.md says what they are used for).
const FONTS := [["Cinzel", "res://art/fonts/OFL-Cinzel.txt"], ["Alegreya Sans", "res://art/fonts/OFL-AlegreyaSans.txt"]]
const SOUND_CREDITS := "res://art/CREDITS.md"
## The screen's sections, in order: [id, title]. (A title goes through Loc.t; the licence texts themselves stay as they are written.)
const SECTIONS := [
	["game", "The game"],
	["godot", "Godot Engine"],
	["godot_parts", "What Godot is made with"],
	["steam", "Steam"],
	["fonts", "Fonts"],
	["art", "Sounds, music and art"],
]


## data/legal.json: {"holder": "", "year": "2026", "site": ""}, each a short text; what is not there is "".
static func legal() -> Dictionary:
	var out := {"holder": "", "year": "", "site": ""}
	var f := FileAccess.open(LEGAL, FileAccess.READ)
	if f == null:
		return out
	var j = JSON.parse_string(f.get_as_text())
	if j is Dictionary:
		for k in out:
			out[k] = str(j.get(k, "")).strip_edges().substr(0, 120)
	return out


## "© 2026 The Holder", or "" while no holder is set.
static func notice(l: Dictionary = {}) -> String:
	if l.is_empty():
		l = legal()
	var holder := String(l.get("holder", "")).strip_edges()
	if holder == "":
		return ""
	var year := String(l.get("year", "")).strip_edges()
	return ("© %s %s" % [year, holder]) if year != "" else ("© " + holder)


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


## The words that turn Markdown (art/CREDITS.md) into plain text: a link keeps its address in brackets, a heading is a line of capitals,
## the code marks and the list dashes go.
static func plain(md: String) -> String:
	var link := RegEx.new()
	link.compile("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	var out := PackedStringArray()
	for line in md.split("\n"):
		var l: String = link.sub(line, "$1 ($2)", true).replace("`", "")
		if l.begins_with("#"):
			l = l.lstrip("# ").to_upper()
			out.append("")
		elif l.begins_with("- "):
			l = "• " + l.substr(2)
		out.append(l)
	return "\n".join(out).strip_edges()


static func _text_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else ""


static func game_text(l: Dictionary = {}) -> String:
	var lines := PackedStringArray(["WRECKSMITH", "Version %s" % version()])
	var n := notice(l)
	if n != "":
		lines.append(n)
	lines.append("")
	lines.append("A game of voxel gladiators: every blow takes the voxels it hits, every limb can be lost.")
	lines.append("")
	lines.append("Made with Godot Engine, with the fonts and the sounds named in the next pages. Their licences are printed in full, as they ask.")
	return "\n".join(lines)


static func godot_text() -> String:
	return "This game is made with Godot Engine %s (https://godotengine.org).\n\n%s" % [str(Engine.get_version_info().get("string", "")), Engine.get_license_text().strip_edges()]


## Every part Godot is made with (its copyright holders and the licence of each), then the texts of those licences.
static func parts_text() -> String:
	var out := PackedStringArray(["Godot Engine contains the following components. The game uses the parts the engine itself uses.", ""])
	for c in Engine.get_copyright_info():
		out.append(str(c.get("name", "")))
		for p in c.get("parts", []):
			var files := PackedStringArray()
			for f in p.get("files", []):
				files.append(str(f))
			out.append("    Files: %s" % ", ".join(files))
			for cp in p.get("copyright", []):
				out.append("    © %s" % str(cp))
			out.append("    Licence: %s" % str(p.get("license", "")))
		out.append("")
	out.append("")
	out.append("THE LICENCES")
	var info: Dictionary = Engine.get_license_info()
	var names := info.keys()
	names.sort()
	for n in names:
		out.append("")
		out.append("-------- %s --------" % str(n))
		out.append(str(info[n]).strip_edges())
	return "\n".join(out)


static func steam_text() -> String:
	return "\n".join([
		"Playing together through Steam uses two extensions for Godot, both open source under the MIT licence:",
		"",
		"• GodotSteam (https://godotsteam.com): Godot's link to Valve's Steamworks library, for the overlay, the lobbies, the invites and the achievements.",
		"• The Steam multiplayer peer (SteamMultiplayerPeer): carries the game's online traffic over Steam's network.",
		"",
		"Their licence texts are in THIRD_PARTY_LICENSES.txt, beside the game, in the Steam version.",
		"",
		"Steamworks SDK © Valve Corporation. Steam and the Steam logo are trademarks and/or registered trademarks of Valve Corporation in the U.S. and/or other countries.",
	])


static func fonts_text() -> String:
	var out := PackedStringArray()
	for f in FONTS:
		out.append("-------- %s --------" % f[0])
		var t := _text_file(f[1])
		out.append(t if t != "" else "(the licence text of %s is not in this build)" % f[0])
		out.append("")
	return "\n".join(out).strip_edges()


static func art_text() -> String:
	var md := _text_file(SOUND_CREDITS)
	return plain(md) if md != "" else "(art/CREDITS.md is not in this build)"


## The text of one section of the screen.
static func text_of(id: String, l: Dictionary = {}) -> String:
	match id:
		"game": return game_text(l)
		"godot": return godot_text()
		"godot_parts": return parts_text()
		"steam": return steam_text()
		"fonts": return fonts_text()
		"art": return art_text()
	return ""


## All of it, in one text: the file every package carries (THIRD_PARTY_LICENSES.txt).
static func full_text(l: Dictionary = {}) -> String:
	var out := PackedStringArray()
	for s in SECTIONS:
		out.append("=".repeat(78))
		out.append(String(s[1]).to_upper())
		out.append("=".repeat(78))
		out.append("")
		out.append(text_of(s[0], l))
		out.append("")
		out.append("")
	return "\n".join(out)
