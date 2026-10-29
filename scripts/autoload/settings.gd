# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## The player's own settings (the Settings page, from the Esc menu: see
## SettingsPage), kept on this computer in user://settings.cfg for every game
## (not in a save): how ships look from afar, day and night, the birds, and
## the sound's volumes. The
## sound plays through its own audio buses, made here, so each has a volume:
## the music (Music's soundtrack), the sea and the weather (Ambience's loops),
## the animals' calls, and the ships' horns, all under Master.

## How ships far off are drawn (MapView): as now (a small dot once too small to
## make out), as a bigger dot, or grown so their art always shows (as they
## used to be: never smaller than SHIP_GROW_MIN_SCALE, see MapView._ship_draw_scale()).
const SHIP_LOOKS := ["dot", "big_dot", "grow"]
const SHIP_LOOK_NAMES := {dot = "Small dots (default)", big_dot = "Bigger dots", grow = "Ships grow as you zoom out"}
## The volumes (0 to 1; Master to MASTER_MOST, louder than everything's own
## level), by bus: [bus, name on the page].
const VOLUMES := [["Master", "Master"], ["Music", "Music"], ["Sea", "Sea and weather"], ["Wildlife", "Wildlife"], ["Ships", "Ship horns"]]
const MASTER_MOST := 2.0

## The most a bus's volume goes to (1, or MASTER_MOST for Master).
static func volume_most(bus: String) -> float:
	return MASTER_MOST if bus == "Master" else 1.0
const PATH := "user://settings.cfg"

## A setting changed (the map and the page follow).
signal changed

var ship_look := "dot":
	set(value):
		ship_look = value if value in SHIP_LOOKS else "dot"
		_save()
		changed.emit()
## Day and night on the map (the dark side of the globe and its lights):
## "off" (always day), "half" (the night only half as dark) or "full"
## (MapView._update_night(), NIGHT_SHARES for the darkness each).
const NIGHTS := ["off", "half", "full"]
const NIGHT_NAMES := {off = "Always day", half = "Half as dark", full = "Full night"}
const NIGHT_SHARES := {off = 0.0, half = 0.5, full = 1.0}
var night := "full":
	set(value):
		night = value if value in NIGHTS else "full"
		_save()
		changed.emit()
## Whether the night falls at all (the night setting is not "off").
var day_night: bool:
	get: return night != "off"
	set(value): night = "full" if value else "off"
## How dark the night gets, 0 to 1 of the full dark.
func night_share() -> float:
	return float(NIGHT_SHARES.get(night, 1.0))
## Only this player's own routes drawn with the Routes switch (not the other
## companies', players' or AI rivals': MapView._draw_active_lanes()).
var own_routes_only := false:
	set(value):
		own_routes_only = value
		_save()
		changed.emit()
## How many of the other shipping firms' ships the map draws at once (the
## ambient traffic: AmbientTraffic.CAPS), as a word: "off", "light", "busy" or "heavy".
const TRAFFICS := ["off", "light", "busy", "heavy"]
const TRAFFIC_NAMES := {off = "None", light = "Light", busy = "Busy (default)", heavy = "Heavy"}
var traffic := "busy":
	set(value):
		traffic = value if value in TRAFFICS else "busy"
		_save()
		changed.emit()
## How big an offer must be to pause the game with a card (x Contracts.IMPORTANT_SHARE of the company's value): "low", "normal" or "high".
const OFFER_BARS := ["low", "normal", "high"]
const OFFER_BAR_NAMES := {low = "Low (more pop-ups)", normal = "Normal", high = "High (only the biggest)"}
const OFFER_BAR_VALUES := {low = 0.5, normal = 1.0, high = 3.0}
var offer_bar_level := "normal":
	set(value):
		offer_bar_level = value if value in OFFER_BARS else "normal"
		_save()
		changed.emit()
var offer_bar: float:
	get: return float(OFFER_BAR_VALUES.get(offer_bar_level, 1.0))
## The birds drawn on the map (off: none drawn or clicked; their calls still play).
var birds := true:
	set(value):
		birds = value
		_save()
		changed.emit()
## Antialiasing on the map (MapView's edge pass, scripts/ui/antialias.gdshader):
## 0 off (no pass at all), 1 low, 2 medium, 3 high: on each edge pixel the
## pass blends 3, 5 or 9 pixels along the edge (ANTIALIAS_SPANS).
const ANTIALIAS_NAMES := ["Off", "Low (3)", "Medium (5)", "High (9)"]
const ANTIALIAS_SPANS := [0, 3, 5, 9]
var antialias := 0:
	set(value):
		antialias = clampi(value, 0, ANTIALIAS_SPANS.size() - 1)
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
		var dark := str(config.get_value("general", "night", "full" if bool(config.get_value("general", "day_night", true)) else "off"))
		night = dark if dark in NIGHTS else "full"
		birds = bool(config.get_value("general", "birds", true))
		var busy := str(config.get_value("general", "traffic", "busy"))
		traffic = busy if busy in TRAFFICS else "busy"
		var bar := str(config.get_value("general", "offer_bar", "normal"))
		offer_bar_level = bar if bar in OFFER_BARS else "normal"
		own_routes_only = bool(config.get_value("general", "own_routes_only", false))
		antialias = int(config.get_value("general", "antialias", 0))
		for entry: Array in VOLUMES:
			_volumes[entry[0]] = clampf(float(config.get_value("audio", str(entry[0]), 1.0)), 0.0, volume_most(str(entry[0])))
	for entry: Array in VOLUMES:
		_apply_volume(str(entry[0]))


## A bus's volume (0 to 1).
func volume(bus: String) -> float:
	return float(_volumes.get(bus, 1.0))


func set_volume(bus: String, share: float) -> void:
	_volumes[bus] = clampf(share, 0.0, volume_most(bus))
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
	config.set_value("general", "night", night)
	config.set_value("general", "birds", birds)
	config.set_value("general", "traffic", traffic)
	config.set_value("general", "offer_bar", offer_bar_level)
	config.set_value("general", "own_routes_only", own_routes_only)
	config.set_value("general", "antialias", antialias)
	for entry: Array in VOLUMES:
		config.set_value("audio", str(entry[0]), volume(str(entry[0])))
	config.save(PATH)
