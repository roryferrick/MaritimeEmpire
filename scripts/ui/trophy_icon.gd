# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name TrophyIcon
extends Control
## A trophy cup (the achievements' mark): a bowl with handles on a stem and a
## stepped base, filling the control.

var color := Color(0.92, 0.88, 0.8)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side := minf(size.x, size.y)
	var o := (size - Vector2.ONE * side) / 2.0
	var at := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * side
	# The bowl: a wide rim narrowing to a rounded bottom.
	var bowl := PackedVector2Array([at.call(0.22, 0.08), at.call(0.78, 0.08)])
	for i in range(0, 13):
		var a := PI * i / 12.0
		bowl.append(at.call(0.5 + cos(a) * 0.28, 0.36 + sin(a) * 0.22))
	draw_colored_polygon(bowl, color)
	# The handles: arcs either side.
	draw_arc(at.call(0.22, 0.27), side * 0.12, PI * 0.5, PI * 1.5, 12, color, side * 0.06, true)
	draw_arc(at.call(0.78, 0.27), side * 0.12, -PI * 0.5, PI * 0.5, 12, color, side * 0.06, true)
	# The stem and the base.
	draw_rect(Rect2(at.call(0.45, 0.56), Vector2(0.1, 0.2) * side), color)
	draw_rect(Rect2(at.call(0.32, 0.74), Vector2(0.36, 0.08) * side), color)
	draw_rect(Rect2(at.call(0.25, 0.82), Vector2(0.5, 0.1) * side), color)


## A five-pointed star filling a square (`side`) at `origin`: filled, or
## outlined (one not earned yet).
static func draw_star(item: CanvasItem, origin: Vector2, side: float, fill: Color, filled: bool) -> void:
	var points := PackedVector2Array()
	var middle := origin + Vector2.ONE * side / 2.0 + Vector2(0, side * 0.05)
	for i in 10:
		var a := -PI / 2.0 + PI * i / 5.0
		var r := side * (0.5 if i % 2 == 0 else 0.21)
		points.append(middle + Vector2(cos(a), sin(a)) * r)
	if filled:
		item.draw_colored_polygon(points, fill)
	else:
		points.append(points[0])
		item.draw_polyline(points, fill, maxf(side * 0.07, 1.0), true)
