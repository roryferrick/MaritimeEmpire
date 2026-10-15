# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CompanyTypeIcon
extends Control
## A company type's mark (game_config company_types), filling the control in
## the type's color: stacked containers (Cargo & Ore), a car (Vehicles), an
## ear of wheat (Agriculture), a drop of oil (Tankers), a fish (Seafood), or a
## compass star for a company from before types (every type: "All").

var type_id := ""
var color := Color.WHITE


func _init(for_type := "", tint := Color(-1, 0, 0)) -> void:
	type_id = for_type
	color = tint if tint.r >= 0.0 else type_color(for_type)
	mouse_filter = MOUSE_FILTER_IGNORE


## A type's color (game_config company_types color), a pale gold for "All".
static func type_color(for_type: String) -> Color:
	if for_type.is_empty():
		return Color(0.95, 0.85, 0.55)
	return Color.from_string(str(Progression.company_type(for_type).get("color", "#ffffff")), Color.WHITE)


func _draw() -> void:
	var side := minf(size.x, size.y)
	var o := (size - Vector2.ONE * side) / 2.0
	var at := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * side
	var dark := color.darkened(0.45)
	match type_id:
		"cargo":
			# Three containers stacked two over one, with their ribs.
			for box: Array in [[0.06, 0.52, 0.42], [0.52, 0.52, 0.42], [0.29, 0.14, 0.42]]:
				var rect := Rect2(at.call(box[0], box[1]), Vector2(box[2], 0.34) * side)
				draw_rect(rect, color)
				for k in range(1, 4):
					var x: float = rect.position.x + rect.size.x * k / 4.0
					draw_line(Vector2(x, rect.position.y + side * 0.05), Vector2(x, rect.end.y - side * 0.05), dark, maxf(side * 0.04, 1.0))
		"vehicles":
			# A car side on: the body, the cabin with its windows, two wheels.
			draw_colored_polygon(PackedVector2Array([at.call(0.04, 0.68), at.call(0.04, 0.5), at.call(0.24, 0.46), at.call(0.36, 0.26),
				at.call(0.68, 0.26), at.call(0.8, 0.46), at.call(0.96, 0.52), at.call(0.96, 0.68)]), color)
			draw_colored_polygon(PackedVector2Array([at.call(0.39, 0.32), at.call(0.5, 0.32), at.call(0.5, 0.46), at.call(0.31, 0.46)]), dark)
			draw_colored_polygon(PackedVector2Array([at.call(0.55, 0.32), at.call(0.66, 0.32), at.call(0.74, 0.46), at.call(0.55, 0.46)]), dark)
			for x in [0.26, 0.74]:
				draw_circle(at.call(x, 0.7), side * 0.12, dark)
				draw_circle(at.call(x, 0.7), side * 0.06, color)
		"agriculture":
			# An ear of wheat: a stalk with grains either side up to a tip.
			draw_line(at.call(0.5, 0.95), at.call(0.5, 0.2), color, maxf(side * 0.06, 1.0), true)
			for k in 4:
				var y := 0.72 - k * 0.15
				for s in [-1.0, 1.0]:
					var middle: Vector2 = at.call(0.5 + s * 0.13, y)
					_draw_grain(middle, side * 0.09, side * 0.17, s * 0.5)
			_draw_grain(at.call(0.5, 0.14), side * 0.08, side * 0.16, 0.0)
		"tankers":
			# A drop of oil with a highlight.
			var drop := PackedVector2Array([at.call(0.5, 0.04)])
			for i in range(0, 17):
				var a := -PI * 0.15 + PI * 1.3 * i / 16.0
				drop.append(at.call(0.5 + cos(a) * 0.3, 0.62 + sin(a) * 0.3))
			draw_colored_polygon(drop, color)
			draw_arc(at.call(0.5, 0.62), side * 0.19, PI * 0.55, PI * 0.95, 8, color.lightened(0.55), maxf(side * 0.05, 1.0), true)
		"seafood":
			# A fish facing left: body, tail, eye.
			var body := PackedVector2Array()
			for i in range(0, 25):
				var a := TAU * i / 24.0
				body.append(at.call(0.42 + cos(a) * 0.32, 0.5 + sin(a) * 0.2))
			draw_colored_polygon(body, color)
			draw_colored_polygon(PackedVector2Array([at.call(0.68, 0.5), at.call(0.96, 0.26), at.call(0.96, 0.74)]), color)
			draw_circle(at.call(0.24, 0.44), side * 0.05, dark)
			draw_arc(at.call(0.36, 0.5), side * 0.12, -PI * 0.4, PI * 0.4, 6, dark, maxf(side * 0.035, 1.0), true)
		"cruises":
			# A cruise ship side on: the hull, three tiers of decks with their windows, a funnel.
			draw_colored_polygon(PackedVector2Array([at.call(0.02, 0.6), at.call(0.98, 0.6), at.call(0.86, 0.84), at.call(0.12, 0.84)]), color)
			for deck: Array in [[0.12, 0.47, 0.76], [0.2, 0.35, 0.58], [0.3, 0.24, 0.38]]:
				draw_rect(Rect2(at.call(deck[0], deck[1]), Vector2(deck[2], 0.13) * side), color)
				for k in int(float(deck[2]) / 0.09):
					draw_rect(Rect2(at.call(float(deck[0]) + 0.04 + k * 0.09, float(deck[1]) + 0.045), Vector2(0.045, 0.045) * side), dark)
			draw_colored_polygon(PackedVector2Array([at.call(0.6, 0.24), at.call(0.62, 0.08), at.call(0.74, 0.08), at.call(0.72, 0.24)]), color)
			draw_rect(Rect2(at.call(0.62, 0.08), Vector2(0.12, 0.04) * side), dark)
		_:
			# A compass star: every type.
			var star := PackedVector2Array()
			for i in 16:
				var a := -PI / 2.0 + TAU * i / 16.0
				var r := 0.46 if i % 4 == 0 else (0.24 if i % 2 == 0 else 0.13)
				star.append(at.call(0.5 + cos(a) * r, 0.5 + sin(a) * r))
			draw_colored_polygon(star, color)
			draw_circle(at.call(0.5, 0.5), side * 0.07, dark)


## One grain of wheat: an ellipse tilted by `lean` radians.
func _draw_grain(middle: Vector2, half_width: float, half_height: float, lean: float) -> void:
	var points := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		points.append(middle + Vector2(cos(a) * half_width, sin(a) * half_height).rotated(lean))
	draw_colored_polygon(points, color)
