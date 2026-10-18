class_name NetMeter
extends CanvasLayer
## F3 in a room: how the connection is doing, in the corner of the screen, green, amber or
## red: the round trip to the host (each guest's, on the host), whether the host's game keeps
## up (120 physics steps a second), how often snapshots come and the longest wait between two,
## and what goes in and out. While it is open a line a second goes to user://net_log.csv, the
## record of a test to send on.

const LOG := "user://net_log.csv"
var label: RichTextLabel
var _t := 1.0
var _in0 := 0
var _out0 := 0

func _ready() -> void:
	layer = 50
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-330, 12)
	panel.custom_minimum_size = Vector2(318, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.03, 0.82)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 14)
	panel.add_child(label)
	if not FileAccess.file_exists(LOG):
		var f := FileAccess.open(LOG, FileAccess.WRITE)
		if f:
			f.store_line("time,role,transport,players,ping_ms,host_steps,my_steps,snaps_per_s,longest_wait_ms,in_kbs,out_kbs")

func _process(dt: float) -> void:
	_t += dt
	if _t < 1.0:
		return
	_t = 0.0
	var host := Net.is_host()
	var inb := _sum(Net.stats_in)
	var outb := _sum(Net.stats)
	var in_k := (inb - _in0) / 1024.0
	var out_k := (outb - _out0) / 1024.0
	_in0 = inb
	_out0 = outb
	var ping := Net.ping_ms
	if host:
		ping = -1.0
		for id in Net.guest_pings:
			ping = maxf(ping, float(Net.guest_pings[id]))
	var steps: float = Net.step_rate if host else Net.host_rate
	var lines := []
	lines.append("[b]NET[/b] %s · %s · %d players   [color=#9a8f80](F3)[/color]" % ["host" if host else "guest", Net.transport, Net.peers.size() + 1])
	lines.append("%s %s" % ["worst ping" if host else "ping", _grade("%d ms" % ping if ping >= 0.0 else "…", ping, 80.0, 150.0, false)])
	lines.append("host keeps up %s" % _grade("%d/120 steps" % roundi(steps) if steps >= 0.0 else "…", steps, 112.0, 95.0, true))
	if not host:
		lines.append("snapshots %s, longest wait %s" % [_grade("%d/s" % roundi(Net.snap_rate), Net.snap_rate, 25.0, 12.0, true), _grade("%d ms" % Net.snap_gap, float(Net.snap_gap), 90.0, 200.0, false)])
		lines.append("my game %s" % _grade("%d/120 steps" % roundi(Net.step_rate), Net.step_rate, 112.0, 95.0, true))
	lines.append("in %.0f KB/s   out %.0f KB/s" % [in_k, out_k])
	label.text = "\n".join(lines)
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line("%s,%s,%s,%d,%d,%d,%d,%d,%d,%.1f,%.1f" % [Time.get_datetime_string_from_system(), "host" if host else "guest", Net.transport, Net.peers.size() + 1, roundi(ping), roundi(steps), roundi(Net.step_rate), roundi(Net.snap_rate), Net.snap_gap, in_k, out_k])

static func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n

## Green when it is good, amber when it is getting bad, red when it is bad (`up`: more is better).
static func _grade(text: String, v: float, good: float, bad: float, up: bool) -> String:
	if v < 0.0:
		return text
	var ok := v >= good if up else v <= good
	var poor := v < bad if up else v > bad
	return "[color=%s]%s[/color]" % ["#d9534f" if poor else ("#7ac36a" if ok else "#e0b44c"), text]
