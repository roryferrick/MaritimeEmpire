# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name PageIcon
extends Control
## The marks of the map's page buttons (see GameRoot.open_page()), filling
## the control: Markets a rising price chart, Hubs a harbour crane, Farms a
## wheat sheaf, Makers a saw-tooth factory with a chimney, Energy an oil rig.

var kind := ""
var color := Color(0.92, 0.88, 0.8)


func _init(icon_kind := "") -> void:
	kind = icon_kind
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side := minf(size.x, size.y)
	var o := (size - Vector2.ONE * side) / 2.0
	var at := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * side
	var line := side * 0.08
	match kind:
		"markets":
			# Bars rising left to right, under a price line with an arrowhead.
			for i in 4:
				var h := 0.18 + 0.13 * i
				draw_rect(Rect2(at.call(0.1 + i * 0.21, 0.9 - h), Vector2(0.15, h) * side), color)
			draw_polyline(PackedVector2Array([at.call(0.08, 0.52), at.call(0.35, 0.36), at.call(0.55, 0.44), at.call(0.84, 0.14)]), color, line, true)
			draw_colored_polygon(PackedVector2Array([at.call(0.92, 0.06), at.call(0.88, 0.26), at.call(0.72, 0.12)]), color)
		"contracts":
			# A signed sheet: a page with lines of text and a seal at the foot.
			draw_rect(Rect2(at.call(0.2, 0.08), Vector2(0.6, 0.84) * side), color)
			for k in 4:
				draw_rect(Rect2(at.call(0.28, 0.2 + k * 0.13), Vector2(0.44 if k < 3 else 0.26, 0.05) * side), Color(0.12, 0.16, 0.24))
			draw_circle(at.call(0.64, 0.78), side * 0.09, Color(0.85, 0.3, 0.3))
		"hubs":
			# A quayside crane: a tower, a jib out to the left with its hook, and the quay.
			draw_rect(Rect2(at.call(0.58, 0.18), Vector2(0.12, 0.66) * side), color)
			draw_polyline(PackedVector2Array([at.call(0.14, 0.2), at.call(0.86, 0.2)]), color, line, true)
			draw_polyline(PackedVector2Array([at.call(0.64, 0.06), at.call(0.18, 0.2)]), color, line * 0.6, true)
			draw_polyline(PackedVector2Array([at.call(0.64, 0.06), at.call(0.86, 0.2)]), color, line * 0.6, true)
			draw_line(at.call(0.22, 0.2), at.call(0.22, 0.48), color, line * 0.5, true)
			draw_arc(at.call(0.25, 0.52), side * 0.05, PI * 0.1, PI * 1.1, 8, color, line * 0.6, true)
			draw_rect(Rect2(at.call(0.08, 0.84), Vector2(0.84, 0.08) * side), color)
		"farms":
			# A wheat sheaf: three stalks with ears, bound in the middle.
			for dx: float in [-0.16, 0.0, 0.16]:
				var top: Vector2 = at.call(0.5 + dx * 1.3, 0.12)
				var bottom: Vector2 = at.call(0.5 - dx * 0.8, 0.9)
				draw_line(top, bottom, color, line * 0.6, true)
				for k in 3:
					var p: Vector2 = top.lerp(bottom, 0.06 + k * 0.1)
					draw_circle(p + Vector2(-side * 0.04, 0.0), side * 0.04, color)
					draw_circle(p + Vector2(side * 0.04, 0.0), side * 0.04, color)
			draw_rect(Rect2(at.call(0.34, 0.56), Vector2(0.32, 0.08) * side), color)
		"makers":
			# A factory: saw-tooth roof, a chimney, and its door.
			var shape := PackedVector2Array([at.call(0.08, 0.9), at.call(0.92, 0.9), at.call(0.92, 0.42), at.call(0.8, 0.42), at.call(0.8, 0.1), at.call(0.68, 0.1),
				at.call(0.68, 0.42), at.call(0.52, 0.24), at.call(0.52, 0.42), at.call(0.3, 0.24), at.call(0.3, 0.42), at.call(0.08, 0.24)])
			draw_colored_polygon(shape, color)
			draw_rect(Rect2(at.call(0.42, 0.66), Vector2(0.16, 0.24) * side), Color(0.12, 0.16, 0.24))
		"energy":
			# An oil rig: a derrick over its deck on legs in the sea, a flare off one side.
			draw_colored_polygon(PackedVector2Array([at.call(0.36, 0.56), at.call(0.5, 0.06), at.call(0.64, 0.56)]), color)
			draw_colored_polygon(PackedVector2Array([at.call(0.44, 0.5), at.call(0.5, 0.22), at.call(0.56, 0.5)]), Color(0.12, 0.16, 0.24))
			draw_rect(Rect2(at.call(0.12, 0.56), Vector2(0.76, 0.1) * side), color)
			for x: float in [0.2, 0.42, 0.58, 0.8]:
				draw_line(at.call(x, 0.66), at.call(x, 0.84), color, line * 0.7, true)
			draw_line(at.call(0.8, 0.56), at.call(0.92, 0.36), color, line * 0.5, true)
			draw_circle(at.call(0.93, 0.3), side * 0.06, Color(1.0, 0.62, 0.2))
			for k in 3:
				draw_line(at.call(0.06 + k * 0.32, 0.9), at.call(0.22 + k * 0.32, 0.9), color, line * 0.6, true)
		"research":
			# A submersible over the deep, its sonar pinging down to the seabed.
			var hull := PackedVector2Array()
			for i in range(0, 21):
				var a := TAU * i / 20.0
				hull.append(at.call(0.5 + cos(a) * 0.3, 0.3 + sin(a) * 0.17))
			draw_colored_polygon(hull, color)
			draw_rect(Rect2(at.call(0.42, 0.06), Vector2(0.16, 0.1) * side), color)
			draw_circle(at.call(0.38, 0.3), side * 0.07, Color(0.12, 0.16, 0.24))
			for k in 3:
				draw_arc(at.call(0.5, 0.42), side * (0.14 + 0.13 * k), PI * 0.3, PI * 0.7, 10, color, line * 0.5, true)
			draw_polyline(PackedVector2Array([at.call(0.04, 0.94), at.call(0.24, 0.86), at.call(0.42, 0.92), at.call(0.62, 0.84), at.call(0.8, 0.9), at.call(0.96, 0.84)]), color, line * 0.6, true)
		"industry":
			# A mine cart heaped with ore, on its rails.
			draw_colored_polygon(PackedVector2Array([at.call(0.18, 0.18), at.call(0.38, 0.06), at.call(0.55, 0.14), at.call(0.72, 0.05), at.call(0.86, 0.2), at.call(0.18, 0.3)]), color)
			draw_colored_polygon(PackedVector2Array([at.call(0.08, 0.3), at.call(0.92, 0.3), at.call(0.8, 0.7), at.call(0.2, 0.7)]), color)
			draw_line(at.call(0.14, 0.42), at.call(0.86, 0.42), Color(0.12, 0.16, 0.24), line * 0.5, true)
			for x: float in [0.3, 0.7]:
				draw_circle(at.call(x, 0.78), side * 0.1, color)
				draw_circle(at.call(x, 0.78), side * 0.04, Color(0.12, 0.16, 0.24))
			draw_line(at.call(0.02, 0.92), at.call(0.98, 0.92), color, line * 0.7, true)
