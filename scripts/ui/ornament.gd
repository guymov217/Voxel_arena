class_name Ornament
extends Control
## Gold line art for the title screen, drawn rather than shipped as images: a laurel wreath
## ("laurel") and a rule with a diamond in the middle ("rule").

var kind := "rule"
var color := Color(0.85, 0.68, 0.36)
var pad := Vector2.ZERO   # ("frame") drawn this far out past its own rect: to a panel's edge from inside its margins

func _init(kind_ := "rule", size_ := Vector2(360, 18)) -> void:
	kind = kind_
	custom_minimum_size = size_
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

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
		"frame":
			# A gold hairline inset from the edge, and at each corner a bracket with a diamond.
			var inset := 7.0
			var col := Color(color, 0.5)
			var o := -pad
			var full := size + pad * 2.0
			draw_rect(Rect2(o + Vector2(inset, inset), full - Vector2(inset, inset) * 2.0), col, false, 1.0)
			var arm := 22.0
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				var p := o + Vector2(lerpf(3.0, full.x - 3.0, corner.x), lerpf(3.0, full.y - 3.0, corner.y))
				var dx := 1.0 if corner.x == 0 else -1.0
				var dy := 1.0 if corner.y == 0 else -1.0
				draw_line(p, p + Vector2(arm * dx, 0), color, 2.0, true)
				draw_line(p, p + Vector2(0, arm * dy), color, 2.0, true)
				var d := p + Vector2(10 * dx, 10 * dy)
				draw_colored_polygon(PackedVector2Array([d + Vector2(0, -3.5), d + Vector2(3.5, 0), d + Vector2(0, 3.5), d + Vector2(-3.5, 0)]), color)
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
