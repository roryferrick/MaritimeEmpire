# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name BirdIcon
extends Control
## A bird species (Birds) seen from above, as the map draws it, wings spread,
## filling the control.

var info: Dictionary


func _init(for_info: Dictionary, side := 44.0) -> void:
	info = for_info
	custom_minimum_size = Vector2.ONE * side
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	if info.has("raft"):
		MapView.draw_duck(self, size / 2.0 + Vector2(0, size.y * 0.08), -PI / 2.0, info, minf(size.x, size.y) * 1.6, false)  # A sea duck, swimming.
		return
	MapView.draw_bird(self, size / 2.0 + Vector2(0, size.y * 0.06), -PI / 2.0, info, 1.0, minf(size.x, size.y) * 0.95, false)
