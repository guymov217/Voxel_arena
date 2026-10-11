extends Node
## Every script in the project loads (an import run only compiles scripts with a class name).

var t

func _scan(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_scan(dir.path_join(sub), out)

func test_all_scripts_compile() -> void:
	var list := []
	_scan("res://scripts", list)
	for p in list:
		var s = load(p)
		t.check(s != null and s.can_instantiate(), "%s compiles" % p)
	t.check(list.size() > 10, "found the scripts")
