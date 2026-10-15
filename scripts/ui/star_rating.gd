# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name StarRating
extends Control
## Five stars filling the control from the left, value of them filled to the
## nearest half (a rating out of 5: see Ratings), the rest outlined.

const GOLD := Color(1.0, 0.82, 0.3)
const EMPTY := Color(1.0, 1.0, 1.0, 0.35)

## How many stars it draws (1 for a lone star mark, as on the Ratings button).
var count := 5
var value := 0.0:
	set(new_value):
		value = new_value
		tooltip_text = "%.1f of 5 stars" % value
		queue_redraw()


func _init(start := 0.0, star_px := 18.0, stars := 5) -> void:
	count = stars
	custom_minimum_size = Vector2(star_px * count + (count - 1) * 2.0, star_px)
	value = start


func _draw() -> void:
	var side := minf(size.y, (size.x - (count - 1) * 2.0) / count)
	var halves := roundi(value * 2.0)
	for i in count:
		var origin := Vector2(i * (side + 2.0), (size.y - side) / 2.0)
		var points := star_points(origin, side)
		if halves >= (i + 1) * 2:
			draw_colored_polygon(points, GOLD)
		else:
			var outline := points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, EMPTY, maxf(side * 0.07, 1.0), true)
			if halves == i * 2 + 1:  # A half star: its left half filled.
				var left := PackedVector2Array([origin, origin + Vector2(side / 2.0, 0), origin + Vector2(side / 2.0, side), origin + Vector2(0, side)])
				for piece: PackedVector2Array in Geometry2D.intersect_polygons(points, left):
					draw_colored_polygon(piece, GOLD)


## A five-pointed star filling a square (`side`) at `origin`.
static func star_points(origin: Vector2, side: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var middle := origin + Vector2.ONE * side / 2.0 + Vector2(0, side * 0.05)
	for i in 10:
		var a := -PI / 2.0 + PI * i / 5.0
		var r := side * (0.5 if i % 2 == 0 else 0.21)
		points.append(middle + Vector2(cos(a), sin(a)) * r)
	return points
