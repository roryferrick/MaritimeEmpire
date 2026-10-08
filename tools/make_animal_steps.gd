# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends SceneTree
## Makes each land animal's in-between step (art/decor/<animal>_step.svg; see
## MapView._animal_frame()) from its drawing: its legs (the straight strokes
## reaching down to its feet) swung about their tops, every other one forward
## and the rest back, so it walks by turns between the two. Animals without
## such legs (a penguin's feet, a perched bird) get none.
##
##   Godot --headless --path . -s tools/make_animal_steps.gd

const DIR := "res://art/decor/"
## How far (radians) each leg swings, and how low a stroke's end must reach
## (art units, of 64) to be a leg.
const SWING := 0.32
const FEET_Y := 54.0


func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/birds.json"))
	var leg := RegEx.create_from_string("M([0-9.]+),([0-9.]+) L([0-9.]+),([0-9.]+)(?=[\" ])")
	for id: String in (data as Dictionary).land_animals:
		var svg := FileAccess.get_file_as_string(DIR + id + ".svg")
		# Each leg once (its outline and fill share a top), left to right.
		var tops: Array[float] = []
		for found in leg.search_all(svg):
			var end_y := float(found.get_string(4))
			var top_x := float(found.get_string(1))
			if end_y >= FEET_Y and end_y > float(found.get_string(2)) and not tops.has(top_x):
				tops.append(top_x)
		if tops.size() < 2:
			continue
		tops.sort()
		var out := svg
		for found in leg.search_all(svg):
			var top := Vector2(float(found.get_string(1)), float(found.get_string(2)))
			var end := Vector2(float(found.get_string(3)), float(found.get_string(4)))
			var which := tops.find(top.x)
			if which < 0 or end.y < FEET_Y:
				continue
			var swung := top + (end - top).rotated(SWING if which % 2 == 0 else -SWING)
			out = out.replace(found.get_string(0), "M%s,%s L%.1f,%.1f" % [found.get_string(1), found.get_string(2), swung.x, swung.y])
		var file := FileAccess.open(DIR + id + "_step.svg", FileAccess.WRITE)
		file.store_string(out)
		print("%s: %d legs" % [id, tops.size()])
	quit()
