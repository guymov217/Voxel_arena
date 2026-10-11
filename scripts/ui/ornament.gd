class_name Ornament
extends Control
## Gold line art for the title screen, drawn rather than shipped as images: a laurel wreath
## ("laurel") and a rule with a diamond in the middle ("rule").

var kind := "rule"
var color := Color(0.85, 0.68, 0.36)

func _init(kind_ := "rule", size_ := Vector2(360, 18)) -> void:
	kind = kind_
	custom_minimum_size = size_
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var w := size.x
	var h := size.y
	var c := Vector2(w * 0.5, h * 0.5)
	match kind:
		"rule":
			draw_line(Vector2(0, c.y), Vector2(c.x - 12, c.y), color * Color(1, 1, 1, 0.8), 1.5, true)
			draw_line(Vector2(c.x + 12, c.y), Vector2(w, c.y), color * Color(1, 1, 1, 0.8), 1.5, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)]), color)
			draw_circle(Vector2(2, c.y), 2.0, color)
			draw_circle(Vector2(w - 2, c.y), 2.0, color)
		"laurel":
			# Two branches curving up from a knot at the bottom, leaves on both sides of each.
			var r := minf(w, h * 2.0) * 0.42
			var base := Vector2(c.x, h - 6)
			for s: float in [-1.0, 1.0]:
				var prev := Vector2.ZERO
				for i in 9:
					var a := lerpf(0.15, 2.35, i / 8.0)
					var p := base + Vector2(s * sin(a) * r, -(1.0 - cos(a)) * r * 0.82)
					if i > 0:
						draw_line(prev, p, color, 2.0, true)
						var d := (p - prev).normalized()
						var nrm: Vector2 = Vector2(-d.y, d.x) * s
						for side: float in [1.0, -1.0]:
							var tip: Vector2 = p + (d * 0.6 + nrm * side * 0.8).normalized() * (11.0 - i * 0.5)
							_leaf(p, tip, 4.0 - i * 0.2)
					prev = p
			draw_circle(base, 3.0, color)

func _leaf(a: Vector2, b: Vector2, wdt: float) -> void:
	var m := (a + b) * 0.5
	var n := (b - a).orthogonal().normalized() * wdt
	draw_colored_polygon(PackedVector2Array([a, m + n, b, m - n]), color)
