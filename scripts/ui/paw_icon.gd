# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name PawIcon
extends Control
## A bear's paw print (the field guide's mark): a broad pad and five toes in
## an arc above it, filling the control.

var color := Color(0.92, 0.88, 0.8)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side := minf(size.x, size.y)
	var middle := size / 2.0
	# The pad: a wide, rounded heel, a little narrower at the back.
	var pad := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		var wide := 0.36 if sin(a) < 0.0 else 0.3
		pad.append(middle + Vector2(cos(a) * side * wide, sin(a) * side * 0.21 + side * 0.22))
	draw_colored_polygon(pad, color)
	# Five toes in an arc clear above it, the outer ones lower and smaller.
	var toes := [[-0.38, -0.12, 0.075], [-0.19, -0.28, 0.085], [0.0, -0.34, 0.09], [0.19, -0.28, 0.085], [0.38, -0.12, 0.075]]
	for toe: Array in toes:
		draw_circle(middle + Vector2(float(toe[0]), float(toe[1])) * side, side * float(toe[2]), color, true, -1.0, true)
