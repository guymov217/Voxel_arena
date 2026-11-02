class_name Loc
## The game in the player's own language (user: no language barrier for players across the
## world; the most played languages on Steam first). Every word shown is written in English in
## the code; res://i18n/<code>.json holds what each English line reads in another language, and
## the TranslationServer swaps them in: a Label's or a Button's text without a word of code, a
## line made up with numbers in it through Loc.t() before the numbers go in. The language is the
## system's unless the player picked one in Options.

## Steam's most played languages first (Steam's hardware and software survey), English the
## fallback for any line not yet put into the others.
const LANGS := [
	["en", "English"],
	["zh_CN", "简体中文"],
	["ru", "Русский"],
	["es", "Español (España)"],
	["es_419", "Español (Latinoamérica)"],
	["pt_BR", "Português (Brasil)"],
	["de", "Deutsch"],
	["ja", "日本語"],
	["fr", "Français"],
	["pl", "Polski"],
	["ko", "한국어"],
	["zh_TW", "繁體中文"],
	["tr", "Türkçe"],
	["it", "Italiano"],
	["uk", "Українська"],
	["th", "ไทย"],
]

static var _loaded: Translation = null
static var _code := "en"

## The language in use ("en", "zh_CN"...).
static func code() -> String:
	return _code

## What the player picked in Options ("auto": the system's).
static func setting() -> String:
	var st = Save.get_value("settings", {})
	return str(st.get("language", "auto")) if st is Dictionary else "auto"

## The language to use for a setting: the system's own when "auto" (its region kept where the game
## has it: Brazil's Portuguese, Latin America's Spanish, Taiwan's and Hong Kong's Chinese).
static func resolve(pick: String) -> String:
	if pick != "auto" and _known(pick):
		return pick
	var os_loc := OS.get_locale()            # e.g. "pt_BR", "zh_Hans_CN", "es_MX", "de_DE"
	var lang := OS.get_locale_language()     # "pt", "zh", "es", "de"
	if lang == "zh":
		return "zh_TW" if os_loc.contains("Hant") or os_loc.ends_with("_TW") or os_loc.ends_with("_HK") or os_loc.ends_with("_MO") else "zh_CN"
	if lang == "pt":
		return "pt_BR"
	if lang == "es":
		return "es" if os_loc == "es" or os_loc.ends_with("_ES") else "es_419"
	return lang if _known(lang) else "en"

static func _known(c: String) -> bool:
	for l in LANGS:
		if l[0] == c:
			return true
	return false

## The language's lines, put in the TranslationServer in place of the last ones (none for
## English, the game's own words). Called at start and when the player picks another.
static func apply(pick := "") -> void:
	var c := resolve(pick if pick != "" else setting())
	if _loaded != null:
		TranslationServer.remove_translation(_loaded)
		_loaded = null
	_code = c
	TranslationServer.set_locale(c)
	if c == "en":
		return
	var path := "res://i18n/%s.json" % c
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	if not (data is Dictionary):
		return
	var tr_ := Translation.new()
	tr_.locale = c
	for k in data:
		var v = data[k]
		if v is String and v != "":
			# (the catalog keeps a line as it is written in the code: "\n" and "\"" unescaped here)
			tr_.add_message(String(k).c_unescape(), String(v).c_unescape())
	TranslationServer.add_translation(tr_)
	_loaded = tr_

## A line made up in code with numbers or names in it: its English wording translated first,
## then the values put in (Loc.t("%d denarii") % n). Static code has no tr() of its own.
static func t(english: String) -> String:
	return TranslationServer.translate(english)

## A name put into the middle of a line ("loses the %s"): in the player's language, in small
## letters as English has it (German keeps its nouns' capitals).
static func lower(english: String) -> String:
	var tr_ := t(english)
	return tr_ if TranslationServer.get_locale().begins_with("de") else tr_.to_lower()

## The name shown in the language picker for a code.
static func name_of(c: String) -> String:
	for l in LANGS:
		if l[0] == c:
			return l[1]
	return c
