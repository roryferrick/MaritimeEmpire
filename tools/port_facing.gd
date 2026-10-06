extends Node
## Works out which way each port's docks face (data/port_facing.json) from the
## map's coastline (WorldMapData.coast_segments, which always runs with the
## land on its right): the sea's direction is the left-hand side of the
## coastline round the port, weighted towards the nearest stretches, turned if
## need be so the docks reach out over open water. Also which
## side of the piers (looking out to sea) has more open water, for the quay,
## tugs and anchorage. Entries under "manual" in the file win and are kept.
##
##   Godot --headless --path . tools/port_facing.tscn

const OUT_PATH := "res://data/port_facing.json"
## Coastline within this many projected degrees of a port counts, nearer counting more.
const REACH := 0.3
const BUCKET := 0.5
## Docks are turned up to TURN_MAX degrees off the coast's own facing (losing
## TURN_PENALTY of their score a degree) so they lie over water out to these
## distances (projected degrees: about a big port's piers and harbour mouth).
const TURN_MAX := 80
const TURN_PENALTY := 0.003
const PIER_SAMPLES: Array[float] = [0.08, 0.16, 0.24, 0.32, 0.4, 0.5]


func _ready() -> void:
	var segments := GameData.world_map.coast_segments
	var buckets := {}
	for i in range(0, segments.size(), 2):
		var mid := (segments[i] + segments[i + 1]) / 2.0
		var cell := _cell(mid)
		var list: PackedInt32Array = buckets.get(cell, PackedInt32Array())
		list.append(i)
		buckets[cell] = list  # (Packed arrays are copied, so put it back.)
	var manual := {}
	if FileAccess.file_exists(OUT_PATH):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT_PATH))
		if old is Dictionary:
			manual = old.get("manual", {})
	var facing := {}
	var weak: Array[String] = []
	var turned: Array[String] = []
	for port: Dictionary in GameData.ports:
		var at := GameData.port_position(port.id)
		var nearby := _nearby(segments, buckets, at, REACH)
		var sea := Vector2.ZERO
		for i: int in nearby:
			var a := segments[i]
			var b := segments[i + 1]
			var way := b - a
			var distance := ((a + b) / 2.0).distance_to(at)
			sea += Vector2(-way.y, way.x).normalized() * way.length() * pow(1.0 - distance / REACH, 2.0)  # Its left: the sea.
		if sea.length() < 0.0001:
			weak.append(port.id)
			continue
		sea = sea.normalized()
		# Docks reach well out: turn them (up to TURN_MAX either way, a little
		# penalty for each degree) to where their whole length is over water,
		# for a port in a bay or a narrow sea.
		var normal := sea
		var best := -INF
		for turn in range(-TURN_MAX, TURN_MAX + 1, 5):
			var way := normal.rotated(deg_to_rad(turn))
			var wet := 0.0
			for reach: float in PIER_SAMPLES:
				wet += _seaness(segments, buckets, at + way * reach)
			var score := wet / PIER_SAMPLES.size() - TURN_PENALTY * absf(turn)
			if score > best:
				best = score
				sea = way
		if sea.angle_to(normal) != 0.0 and absf(rad_to_deg(sea.angle_to(normal))) >= 20.0:
			turned.append("%s %d" % [port.id, roundi(rad_to_deg(-sea.angle_to(normal)))])
		var right := Vector2(sea.y, -sea.x)
		var wet_right := 0.0
		var wet_left := 0.0
		for out: float in [0.04, 0.08]:
			for along: float in [0.06, 0.12, 0.18]:
				wet_right += _seaness(segments, buckets, at + sea * out + right * along)
				wet_left += _seaness(segments, buckets, at + sea * out - right * along)
		facing[port.id] = {bearing = roundi(fposmod(rad_to_deg(atan2(sea.x, sea.y)), 360.0)), quay = "right" if wet_right >= wet_left else "left"}
	var data := {
		_comment = "Which way each port's docks face (tools/port_facing.gd): bearing is the compass bearing out to sea (0 north, 90 east), from the coastline round the port; quay is which side of the piers, looking out to sea, the quay, tugs and anchorage go (the side with more open water). Entries under manual win over the worked-out ones and are kept when the tool runs again.",
		manual = manual,
		facing = facing,
	}
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", false))
	print("Port facing: %d ports, %d with no coast nearby (%s), %d manual" % [facing.size(), weak.size(), ", ".join(weak), manual.size()])
	print("Turned 20 degrees or more off the coast for open water: ", ", ".join(turned))
	get_tree().quit()


func _cell(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / BUCKET), floori(at.y / BUCKET))


func _nearby(segments: PackedVector2Array, buckets: Dictionary, at: Vector2, reach: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cell := _cell(at)
	var span := ceili(reach / BUCKET)
	for dx in range(-span, span + 1):
		for dy in range(-span, span + 1):
			for i: int in buckets.get(cell + Vector2i(dx, dy), PackedInt32Array()):
				if ((segments[i] + segments[i + 1]) / 2.0).distance_to(at) < reach:
					out.append(i)
	return out


## 1 if a point is on the sea side of the coastline nearest it, else 0
## (0.5 with no coast near: open water).
func _seaness(segments: PackedVector2Array, buckets: Dictionary, point: Vector2) -> float:
	var best := -1
	var best_distance := INF
	for i: int in _nearby(segments, buckets, point, 0.15):
		var d := Geometry2D.get_closest_point_to_segment(point, segments[i], segments[i + 1]).distance_to(point)
		if d < best_distance:
			best_distance = d
			best = i
	if best < 0:
		return 1.0
	var a := segments[best]
	var way := segments[best + 1] - a
	return 1.0 if Vector2(-way.y, way.x).dot(point - a) > 0.0 else 0.0
