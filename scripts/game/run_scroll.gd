class_name RunScroll
## The run's scroll for one man alone (user: the scroll a party gets, for the single player too):
## kept bout by bout through a campaign run (the bouts won, the kills, the limbs he cut off and
## those he lost, the times he fell, the weapon that killed the most), unrolled when the run ends:
## the rudis won, or the death that ends it. DOM-free: the match counts (Match._tally), the menu
## keeps it in the save ("run_scroll") and shows it.

const ROWS := [["bouts", "Bouts won"], ["kills", "Kills"], ["cut", "Limbs cut off"], ["limbs", "Limbs lost"], ["falls", "Falls"]]
const WEAPON := "w:"   # (a bout's tally of kills by weapon: "w:" and its name)

## A bout's tallies for him (`row`: kills, cut, limbs, and WEAPON + name: kills by that weapon)
## set down on the scroll, the bout won or lost (a fall).
static func add_bout(scroll: Dictionary, row: Dictionary, won: bool) -> Dictionary:
	var out := scroll.duplicate(true)
	for k in ["kills", "cut", "limbs"]:
		out[k] = int(out.get(k, 0)) + int(row.get(k, 0))
	if won:
		out["bouts"] = int(out.get("bouts", 0)) + 1
	else:
		out["falls"] = int(out.get("falls", 0)) + 1
	var w: Dictionary = out.get("weapons", {}) if out.get("weapons") is Dictionary else {}
	for k in row:
		if String(k).begins_with(WEAPON) and String(k).length() > WEAPON.length():
			var n := String(k).substr(WEAPON.length())
			w[n] = int(w.get(n, 0)) + int(row[k])
	out["weapons"] = w
	return out

## The weapon that killed the most on the scroll: [name, kills], or [] when none did.
static func best_weapon(scroll: Dictionary) -> Array:
	var best := ""
	var most := 0
	var w: Dictionary = scroll.get("weapons", {}) if scroll.get("weapons") is Dictionary else {}
	for n in w:
		if int(w[n]) > most:
			best = String(n)
			most = int(w[n])
	return [best, most] if best != "" else []
