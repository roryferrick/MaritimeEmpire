# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## The player's own settings (the Settings page, from the Esc menu: see
## SettingsPage), kept on this computer in user://settings.cfg for every game
## (not in a save): how ships look from afar, day and night, the birds, and
## the sound's volumes. The
## sound plays through its own audio buses, made here, so each has a volume:
## the sea and the weather (Ambience's loops), the animals' calls, and the
## ships' horns, all under Master.

## How ships far off are drawn (MapView): as now (a small dot once too small to
## make out), as a bigger dot, or grown so their art always shows (as they
## used to be: never smaller than SHIP_GROW_MIN_SCALE, see MapView._ship_draw_scale()).
const SHIP_LOOKS := ["dot", "big_dot", "grow"]
const SHIP_LOOK_NAMES := {dot = "Small dots (default)", big_dot = "Bigger dots", grow = "Ships grow as you zoom out"}
## The volumes (0 to 1), by bus: [bus, name on the page].
const VOLUMES := [["Master", "Master"], ["Sea", "Sea and weather"], ["Wildlife", "Wildlife"], ["Ships", "Ship horns"]]
const PATH := "user://settings.cfg"

## A setting changed (the map and the page follow).
signal changed

var ship_look := "dot":
	set(value):
		ship_look = value if value in SHIP_LOOKS else "dot"
		_save()
		changed.emit()
## Day and night on the map (the dark side of the globe and its lights); off,
## always day (MapView._update_night()).
var day_night := true:
	set(value):
		day_night = value
		_save()
		changed.emit()
## Only this player's own routes drawn with the Routes switch (not the other
## companies', players' or AI rivals': MapView._draw_active_lanes()).
var own_routes_only := false:
	set(value):
		own_routes_only = value
		_save()
		changed.emit()
## The birds drawn on the map (off: none drawn or clicked; their calls still play).
var birds := true:
	set(value):
		birds = value
		_save()
		changed.emit()
var _volumes := {}


func _ready() -> void:
	for entry: Array in VOLUMES:
		var bus := str(entry[0])
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		var look := str(config.get_value("general", "ship_look", "dot"))
		ship_look = look if look in SHIP_LOOKS else "dot"
		day_night = bool(config.get_value("general", "day_night", true))
		birds = bool(config.get_value("general", "birds", true))
		own_routes_only = bool(config.get_value("general", "own_routes_only", false))
		for entry: Array in VOLUMES:
			_volumes[entry[0]] = clampf(float(config.get_value("audio", str(entry[0]), 1.0)), 0.0, 1.0)
	for entry: Array in VOLUMES:
		_apply_volume(str(entry[0]))


## A bus's volume (0 to 1).
func volume(bus: String) -> float:
	return float(_volumes.get(bus, 1.0))


func set_volume(bus: String, share: float) -> void:
	_volumes[bus] = clampf(share, 0.0, 1.0)
	_apply_volume(bus)
	_save()
	changed.emit()


func _apply_volume(bus: String) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	var share := volume(bus)
	AudioServer.set_bus_mute(index, share <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(share, 0.001)))


func _save() -> void:
	if not is_node_ready():
		return  # (Loading: nothing new to write.)
	var config := ConfigFile.new()
	config.set_value("general", "ship_look", ship_look)
	config.set_value("general", "day_night", day_night)
	config.set_value("general", "birds", birds)
	config.set_value("general", "own_routes_only", own_routes_only)
	for entry: Array in VOLUMES:
		config.set_value("audio", str(entry[0]), volume(str(entry[0])))
	config.save(PATH)
