extends Node
## The game in other languages (loc.gd, i18n/<code>.json): every language keeps each line's
## placeholders, so a line made up in code never breaks or swaps its values; and the names put
## together in code (a key's action, a material without its note) read in the chosen language.

var t

const ForgeUI := preload("res://scripts/ui/forge.gd")

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return d if d is Dictionary else {}

## The placeholders of a line in order (%s, %d, %.1f, %%) and its {names} sorted. A line from the
## data files is shown as it is, never formatted: a per cent before a space there is a per cent.
func _marks(s: String, from_data: bool) -> Array:
	if from_data:
		s = RegEx.create_from_string("%(?=\\s)").sub(s, "", true)
	var out := []
	for m in RegEx.create_from_string("%[-+ 0#]*\\d*(?:\\.\\d+)?[sdif%]").search_all(s):
		out.append(m.get_string())
	var names := []
	for m in RegEx.create_from_string("\\{\\w+\\}").search_all(s):
		names.append(m.get_string())
	names.sort()
	return [out, names]

func test_every_language_keeps_the_placeholders() -> void:
	var cat := _read("res://i18n/catalog.json")
	t.check(cat.size() > 2000, "the catalog of English lines: %d" % cat.size())
	for l in Loc.LANGS:
		var c: String = l[0]
		if c == "en":
			continue
		var d := _read("res://i18n/%s.json" % c)
		t.check(d.size() >= cat.size() - 5, "%s: %d of %d lines" % [c, d.size(), cat.size()])
		var bad := []
		for k in d:
			var src: Array = cat.get(k, [])
			var from_data := src.any(func(w): return String(w).begins_with("data/"))
			if _marks(k, from_data) != _marks(String(d[k]), from_data):
				bad.append(k)
		t.check(bad.is_empty(), "%s: every line keeps its placeholders (%s)" % [c, ", ".join(bad.slice(0, 3))])

func test_names_made_in_code_read_in_the_language() -> void:
	var was := Loc.code()
	Loc.apply("de")
	t.eq(Loc.t("Walk forward"), "Vorwärts gehen", "a rebinding label")
	t.eq(Loc.t("right hand: %s") % "Gladius", "rechte Hand: Gladius", "the hand that throws")
	t.check(ForgeUI.material_stats("lead").begins_with("Blei "), "a material by its German name, its note in brackets left out: " + ForgeUI.material_stats("lead"))
	Loc.apply("ja")
	var ruby: String = ForgeUI.material_stats("ruby")
	t.check(ruby.begins_with("ルビー") and not ruby.contains("（"), "and the Japanese one without its full-width brackets: " + ruby)
	Loc.apply("en")
	t.check(ForgeUI.material_stats("lead").begins_with("Lead "), "English again: " + ForgeUI.material_stats("lead"))
	Loc.apply(was)
