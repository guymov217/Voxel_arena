extends Node
## The credits and the licences (scripts/game/credits.gd): that every part of what the game is made with has its text, that
## Godot's own terms are the engine's, that no holder means no © line, and that the screen shows them.

var t

func test_every_section_has_its_text() -> void:
	for s in Credits.SECTIONS:
		t.check(Credits.text_of(s[0]).length() > 40, "%s has text" % s[0])
	t.eq(Credits.text_of("nonsense"), "", "an unknown section is empty")

func test_godots_own_terms_come_from_the_engine() -> void:
	var g := Credits.text_of("godot")
	t.check(g.contains("godotengine.org"), "it says where the engine is from")
	t.check(g.contains("Permission is hereby granted"), "and carries the MIT licence's words")
	t.check(g.contains(str(Engine.get_version_info().get("string", "?"))), "of this version")
	var parts := Credits.text_of("godot_parts")
	t.check(parts.contains("Licence: Expat"), "the components' holders and licences are listed")
	t.check(parts.split("-------- ").size() > 10, "and the texts of the licences follow (%d)" % (parts.split("-------- ").size() - 1))
	t.check(parts.contains("-------- Expat --------"), "the MIT licence among them")

func test_the_fonts_licences_are_printed_in_full() -> void:
	var f := Credits.text_of("fonts")
	for name_ in ["Cinzel", "Alegreya Sans"]:
		t.check(f.contains("-------- %s --------" % name_), "%s has its heading" % name_)
	t.check(f.count("SIL OPEN FONT LICENSE") >= 2, "and each its licence's text (the OFL asks for it to travel with the font)")
	for file in Credits.FONTS:
		t.check(FileAccess.file_exists(file[1]), "%s is in the project" % file[1])

func test_the_sounds_credits_read_as_plain_text() -> void:
	var a := Credits.text_of("art")
	t.check(a.contains("Versilian"), "the music's sample libraries are named")
	t.check(a.contains("freesound.org"), "and the voices' recordings")
	t.check(not a.contains("]("), "no Markdown link is left in it")
	t.check(not a.contains("`"), "no code marks either")
	t.eq(Credits.plain("a [link](http://x.y) here"), "a link (http://x.y) here", "a link keeps its address in brackets")
	t.check(Credits.plain("## Fonts\n- one").begins_with("FONTS"), "a heading is a line of capitals")
	t.check(Credits.plain("- one").begins_with("• one"), "a list item gets its bullet")

func test_there_is_no_copyright_line_until_the_owner_says_who_it_is() -> void:
	t.eq(Credits.notice({"holder": "", "year": "2026"}), "", "no holder, no line")
	t.eq(Credits.notice({"holder": "  ", "year": "2026"}), "", "a blank holder is none")
	t.eq(Credits.notice({"holder": "Acme Ltd", "year": "2026"}), "© 2026 Acme Ltd", "with a holder and a year")
	t.eq(Credits.notice({"holder": "Acme Ltd", "year": ""}), "© Acme Ltd", "a holder alone")
	t.check(Credits.game_text({"holder": "Acme Ltd", "year": "2026"}).contains("© 2026 Acme Ltd"), "the first page carries it")
	t.check(not Credits.game_text({"holder": "", "year": "2026"}).contains("©"), "and without a holder has none")
	var l := Credits.legal()
	for k in ["holder", "year", "site"]:
		t.check(l.has(k), "data/legal.json gives %s" % k)

func test_the_whole_text_has_every_section_in_order() -> void:
	var all := Credits.full_text()
	var at := -1
	for s in Credits.SECTIONS:
		var i := all.find(String(s[1]).to_upper())
		t.check(i > at, "%s comes in its turn" % s[1])
		at = i
	t.check(all.length() > 50000, "and it is the whole of it (%d characters)" % all.length())
	t.check(all.contains("Valve Corporation"), "Steam's trademark line is there")

func test_the_screen_shows_the_section_that_is_open() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	menu.show_screen("credits")
	var box := _box(menu)
	t.check(box != null, "the screen has its text box")
	if box == null:
		return
	t.eq(box.text, Credits.text_of("game"), "it opens on the first page")
	t.check(not box.editable, "which cannot be written in")
	menu.credits_section = "fonts"
	menu.show_screen("credits")
	t.check(_box(menu).text.contains("SIL OPEN FONT LICENSE"), "the tab picked is what is shown")
	t.eq(menu.screen, "credits", "and the screen is the credits")

func _box(menu: Node) -> TextEdit:
	var found: Array = menu.find_children("*", "TextEdit", true, false)
	return found[0] if not found.is_empty() else null
