# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Checks every port's marina against the land as the map draws it (the lakes
## as water): its marina at its size band as the port faces (data/port_facing.json),
## its harbour inside the jetty, its mouth and the water in front of the mouth
## (a narrow funnel out to FUNNEL_NM, the way the harbour curves set out), and
## the first miles of every sea lane out of it. Prints the ports that touch land and
## writes the lot to user://port_check.json. With "--fix", it also looks for
## the smallest turn and move (bearing and position) that clears each failing
## port's marina and funnel, printing them and writing user://port_fixes.json
## (to be copied into data/ports.json and port_facing.json "manual").
##
##   Godot --headless --path . tools/port_check.tscn -- [--fix] [--ports A,B] [--lanes-off]

const FACING := "res://data/port_facing.json"
const SHIP_WORLD_ZOOM := 88.235  # (MapView.SHIP_WORLD_ZOOM.)
## How far out the lanes are looked at (nm), and how often along them.
const LANE_NM := 60.0
const STEP_NM := 0.5
## The funnel in front of the mouth: half-angle (degrees) and how far (nm, at
## most the harbour curves' reach).
const FUNNEL_DEG := 20.0
const FUNNEL_NM := 12.0
## How far a port may be moved by --fix (degrees of the globe) and the steps tried.
const MOVE_STEPS: Array[float] = [0.0, 0.02, 0.04, 0.07, 0.1, 0.14, 0.2, 0.28]
## Further, for a port nothing nearer clears (a river port: out to the river's mouth).
const FAR_STEPS: Array[float] = [0.4, 0.55, 0.7, 0.85, 1.0]
const TURN_STEP := 15
## The most of the harbour inside the jetty that may lie over the land for a
## --fix to count (the coast runs through most marinas; a hub's is 17 nm across).
const HARBOUR_LAND_MOST := 0.6
## What --fix must keep to for a port (the user's own instructions, 2026-10-12):
## bearing (compass, fixed), way (the only direction it may move, as a
## compass point), move (it must move at least this far, degrees), nudge
## ([east, north] degrees: moved just so, no search), keep_mouth (turned
## about its mouth: the port itself moves so the mouth stays put).
const CONSTRAINTS := {
	"PIR": {"bearing": 158.0},
	"TUN": {"bearing": 45.0},
	"GIB": {"way": "E", "move": 0.02},
	"TNG": {"way": "W", "move": 0.02, "bearing": 315.0},
	"SOU": {"way": "SE", "move": 0.02},
	"ANR": {"way": "NW", "move": 0.02},
	"BRV": {"bearing": 315.0},
	"HAM": {"bearing": 293.0, "ways": ["NW", "W", "N"], "move": 0.02},
	"IMM": {"nudge": [0.0, -0.015]},
	"GRK": {"bearing": 198.0},
	"GRG": {"nudge": [0.08, 0.03]},
	"LED": {"bearing": 270.0, "keep_mouth": true},
	"TOS": {"way": "NW", "move": 0.02},
	"HFT": {"bearing": 338.0},
	"KKN": {"bearing": 45.0, "way": "N", "move": 0.02},
	"MMK": {"way": "NE", "move": 0.02},
	"ARH": {"way": "NW", "move": 0.02},
	"SBT": {"bearing": 23.0},
}
const WAYS := {"N": [0.0, 1.0], "NE": [1.0, 1.0], "E": [1.0, 0.0], "SE": [1.0, -1.0], "S": [0.0, -1.0], "SW": [-1.0, -1.0], "W": [-1.0, 0.0], "NW": [-1.0, 1.0]}

var _facing := {}
var _manual := {}
var _berths := {}  # Band -> its berths (game_config docks).
var _lakes: Object = null
var _lake_islands: Object = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var started := Time.get_ticks_msec()
	MapView._build_land_cells()
	print("Land cells in %d s" % ((Time.get_ticks_msec() - started) / 1000))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FACING))
	_facing = data.get("facing", {})
	_manual = data.get("manual", {})
	_berths = (GameData.config.get("docks", {}) as Dictionary).get("berths", {})
	# The lakes are inside the land's outlines: masked out (their islands back in).
	var lakes := PackedVector2Array()
	for triangles: PackedVector2Array in GameData.world_map.lake_triangles:
		lakes.append_array(triangles)
	_lakes = ClassDB.instantiate(&"LandTest")
	_lakes.build(lakes, 1.0)
	_lake_islands = ClassDB.instantiate(&"LandTest")
	_lake_islands.build(GameData.world_map.lake_island_triangles, 1.0)
	if "--land" in args:  # (Spot checks: "--land lon,lat;lon,lat".)
		for spot: String in args[args.find("--land") + 1].split(";"):
			var ll := Vector2(float(spot.split(",")[0]), float(spot.split(",")[1]))
			var pr := Geo.project(ll)
			print("  %s: land %s (map land %s, lake %s, lake island %s)" % [ll, _land(ll), MapView._on_land(ll), _lakes.contains(pr), _lake_islands.contains(pr)])
		get_tree().quit()
		return
	var chosen := PackedStringArray()
	if "--ports" in args:
		chosen = args[args.find("--ports") + 1].split(",")
	var lanes_on := not "--lanes-off" in args
	if lanes_on and GameData._lane_index.is_empty():
		GameData._load_lanes()  # (Read when the game starts; not in a tool scene.)
	var out := {}
	var bad := []
	for port: Dictionary in GameData.ports:
		var id: String = port.id
		if not chosen.is_empty() and not chosen.has(id):
			continue
		var at := Vector2(float(port.lon), float(port.lat))
		var entry: Dictionary = _manual.get(id, _facing.get(id, {}))
		var bearing := float(entry.get("bearing", 0.0))
		var flip := 1.0 if str(entry.get("quay", "right")) == "right" else -1.0
		var result := _check(id, at, bearing, flip)
		if lanes_on:
			result.merge(_check_lanes(id, at, bearing, flip, result.reach_nm))
		out[id] = result
		if result.harbour_land > 0 or result.funnel_land > 0 or int(result.get("lanes_bad", 0)) > 0:
			bad.append(id)
	bad.sort_custom(func(a: String, b: String) -> bool: return _score(out[a]) > _score(out[b]))
	print("%d ports checked, %d touch land:" % [out.size(), bad.size()])
	for id: String in bad:
		var r: Dictionary = out[id]
		print("  %-4s %-22s harbour %3d/%3d  mouth %s  funnel %3d/%3d  quay-on-land %3d%%  lanes with land %3d/%3d (worst %s %d)" % [id, GameData.port_name(id).left(22), r.harbour_land, r.harbour_points, "LAND" if r.mouth_land else "sea ", r.funnel_land, r.funnel_points, roundi(r.quay_land * 100.0), r.get("lanes_bad", 0), r.get("lanes_total", 0), r.get("worst_lane", ""), r.get("worst_hits", 0)])
	var file := FileAccess.open("user://port_check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	if "--fix" in args:
		var fixes := {}
		var to_fix: Array = bad.duplicate()
		for id: String in CONSTRAINTS:
			if not to_fix.has(id) and (chosen.is_empty() or chosen.has(id)):
				to_fix.append(id)  # (Asked for, land or not.)
		for id: String in to_fix:
			var r: Dictionary = out.get(id, {harbour_land = 0, harbour_points = 1, funnel_land = 0, mouth_land = false})
			var over_land := float(r.harbour_land) / maxf(float(r.harbour_points), 1.0)
			if not CONSTRAINTS.has(id) and not r.mouth_land and r.funnel_land == 0 and over_land <= HARBOUR_LAND_MOST:
				continue  # (Its jetty a little over the coast, or only its lanes: those are rebuilt, not the port moved.)
			var fix := _fix(id)
			if not fix.is_empty():
				fixes[id] = fix
				print("  FIX %-4s %-22s -> lon %.3f lat %.3f (moved %.2f deg %s) bearing %d (was %d) quay %s: harbour %d funnel %d mouth %s quay-on-land %d%%" % [id, GameData.port_name(id).left(22), fix.lon, fix.lat, fix.moved, fix.way, fix.bearing, fix.was_bearing, fix.quay, fix.harbour_land, fix.funnel_land, "LAND" if fix.mouth_land else "sea", roundi(fix.quay_land * 100.0)])
			else:
				print("  NO FIX %s %s: nothing within %.2f degrees clears it" % [id, GameData.port_name(id), MOVE_STEPS[-1]])
		file = FileAccess.open("user://port_fixes.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(fixes, "\t"))
		file.close()
	print("Done in %d s" % ((Time.get_ticks_msec() - started) / 1000))
	get_tree().quit()


static func _score(r: Dictionary) -> float:
	return float(r.harbour_land) * 10.0 + float(r.funnel_land) * 3.0 + (100.0 if r.mouth_land else 0.0) + float(r.get("lanes_bad", 0))

## True on the land (as the map draws it), the lakes water.
func _land(lon_lat: Vector2) -> bool:
	if not MapView._on_land(lon_lat):
		return false
	var p := Geo.project(Vector2(wrapf(lon_lat.x, -180.0, 180.0), lon_lat.y))
	return not _lakes.contains(p) or _lake_islands.contains(p)

## A port's marina at its size band (data/ports.json size, game_config port_sizes bands).
func _layout(id: String) -> Dictionary:
	var size := float(GameData.get_port(id).get("size", 51))
	var band := "small"
	for entry: Array in (GameData.config.get("port_sizes", {}) as Dictionary).get("bands", []):
		if size >= float(entry[1]):
			band = str(entry[0])
	return MapView._marina_layout(str(_berths.get(band, "ssssss")), false, MapView._is_canal_port(id))


## A marina point (dock units) as (lon, lat), as MapView._dock_lon_lat() has it.
static func _lon_lat(at: Vector2, bearing: float, flip: float, local: Vector2) -> Vector2:
	var off := Vector2(local.x, local.y * flip).rotated(deg_to_rad(bearing - 90.0)) / SHIP_WORLD_ZOOM
	return Vector2(at.x + off.x / maxf(cos(deg_to_rad(at.y)), 0.05), at.y - off.y)


## The marina and its funnel against the land: {harbour_land, harbour_points,
## mouth_land, funnel_land, funnel_points, quay_land (share), reach_nm}.
func _check(id: String, at: Vector2, bearing: float, flip: float) -> Dictionary:
	var layout := _layout(id)
	var radius := float(layout.radius)
	var reach := radius + MapView.JETTY_WIDTH + 1.0
	var harbour := 0
	var harbour_points := 0
	var quay := 0
	var quay_points := 0
	var inland := MapView._quay_inland(layout)
	var x := -reach
	while x <= reach:
		var y := -reach
		while y <= reach:
			var p := Vector2(x, y)
			if p.x > -0.5 and p.length() <= reach:
				harbour_points += 1
				if _land(_lon_lat(at, bearing, flip, p)):
					harbour += 1
			elif p.x >= inland and p.x <= -0.5 and absf(p.y) <= radius:
				quay_points += 1
				if _land(_lon_lat(at, bearing, flip, p)):
					quay += 1
			y += 1.0
		x += 1.0
	# The mouth, and the funnel out from it: the water the harbour curves sail
	# (out to the harbour gate, MapView.GATE_UNITS, and the stretch past it
	# where they join the lane: see MapView._lane_reaches()).
	var mouth: Vector2 = layout.mouth
	var reach_nm := MapView.GATE_UNITS * 60.0 / SHIP_WORLD_ZOOM * (1.0 + MapView.HARBOUR_JOIN_SHARE * MapView.HARBOUR_REACH_GROW)
	var mouth_land := _land(_lon_lat(at, bearing, flip, mouth))
	var funnel := 0
	var funnel_points := 0
	# The channel between the jetty and the mouth first (the marina paints
	# nothing there: ships sail it on the map as drawn, keeping right of the middle).
	var side := float(layout.width) * MapView.KEEP_RIGHT_WIDTHS
	var along := reach + 0.5
	while along < mouth.x:
		for across: float in [-side, 0.0, side]:
			funnel_points += 1
			if _land(_lon_lat(at, bearing, flip, Vector2(along, across))):
				funnel += 1
		along += STEP_NM * SHIP_WORLD_ZOOM / 60.0
	for angle: float in [-FUNNEL_DEG, -FUNNEL_DEG / 2.0, 0.0, FUNNEL_DEG / 2.0, FUNNEL_DEG]:
		var way := Vector2.from_angle(deg_to_rad(angle))
		var nm := 0.0
		while nm <= minf(reach_nm, FUNNEL_NM):
			funnel_points += 1
			if _land(_lon_lat(at, bearing, flip, mouth + way * nm * SHIP_WORLD_ZOOM / 60.0)):
				funnel += 1
			nm += STEP_NM
	return {harbour_land = harbour, harbour_points = harbour_points, mouth_land = mouth_land, funnel_land = funnel, funnel_points = funnel_points,
		quay_land = float(quay) / maxf(quay_points, 1.0), reach_nm = reach_nm, radius = radius}


## The first LANE_NM of every lane out of a port, beyond the harbour curves'
## reach, against the land: {lanes_total, lanes_bad, worst_lane, worst_hits}.
func _check_lanes(id: String, at: Vector2, bearing: float, flip: float, reach_nm: float) -> Dictionary:
	var total := 0
	var bad := 0
	var worst := ""
	var worst_hits := 0
	var root := Geo.project(at)
	for other: Dictionary in GameData.ports:
		if other.id == id:
			continue
		var lane: Variant = GameData.lane(id, other.id, -1)
		if lane == null:
			continue
		total += 1
		var hits := 0
		var points: PackedVector2Array = lane.points
		var miles: PackedFloat64Array = lane.miles
		for i in range(1, points.size()):
			if miles[i - 1] > LANE_NM:
				break
			var span := miles[i] - miles[i - 1]
			var pieces := maxi(ceili(span / STEP_NM), 1)
			for k in range(0, pieces + 1):
				var mile := miles[i - 1] + span * k / pieces
				if mile < reach_nm or mile > LANE_NM:
					continue
				var p := points[i - 1].lerp(points[i], float(k) / pieces)
				if _land(Geo.unproject(p)):
					hits += 1
		if hits > 0:
			bad += 1
			if hits > worst_hits:
				worst_hits = hits
				worst = other.id
	GameData._lane_cache.clear()  # (Thousands a port: not kept.)
	return {lanes_total = total, lanes_bad = bad, worst_lane = worst, worst_hits = worst_hits}


## The smallest turn and move that clears a port's harbour and funnel (the
## quay as much on land as can be): {lon, lat, bearing, quay, moved, way,
## was_bearing, harbour_land, funnel_land, quay_land}, or {} if none within reach.
func _fix(id: String) -> Dictionary:
	var port := GameData.get_port(id)
	var at := Vector2(float(port.lon), float(port.lat))
	var entry: Dictionary = _manual.get(id, _facing.get(id, {}))
	var was := float(entry.get("bearing", 0.0))
	var flip_was := 1.0 if str(entry.get("quay", "right")) == "right" else -1.0
	var rule: Dictionary = CONSTRAINTS.get(id, {})
	var bearings := []
	if rule.has("bearing"):
		bearings = [float(rule.bearing)]
	else:
		for turn in range(0, 360, TURN_STEP):
			bearings.append(fposmod(was + turn, 360.0))
	# Moved just so.
	if rule.has("nudge"):
		var here := Vector2(at.x + float(rule.nudge[0]), at.y + float(rule.nudge[1]))
		var r := _check(id, here, bearings[0], flip_was)
		return {lon = snappedf(here.x, 0.001), lat = snappedf(here.y, 0.001), bearing = roundi(bearings[0]), quay = entry.get("quay", "right"), moved = here.distance_to(at), way = "nudge", was_bearing = roundi(was),
			harbour_land = r.harbour_land, funnel_land = r.funnel_land, quay_land = r.quay_land, mouth_land = r.mouth_land}
	# Turned about its mouth: the port goes where the mouth stays put.
	if rule.get("keep_mouth", false):
		var layout := _layout(id)
		var mouth_at := _lon_lat(at, was, flip_was, layout.mouth)
		var bearing: float = bearings[0]
		var here := at + (mouth_at - _lon_lat(at, bearing, flip_was, layout.mouth))
		var r := _check(id, here, bearing, flip_was)
		return {lon = snappedf(here.x, 0.001), lat = snappedf(here.y, 0.001), bearing = roundi(bearing), quay = entry.get("quay", "right"), moved = here.distance_to(at), way = "about its mouth", was_bearing = roundi(was),
			harbour_land = r.harbour_land, funnel_land = r.funnel_land, quay_land = r.quay_land, mouth_land = r.mouth_land}
	var allowed: Array = rule.get("ways", [rule.way] if rule.has("way") else WAYS.keys())
	var least := float(rule.get("move", 0.0))
	# As it faces first (told to move, not to turn: it keeps its facing if that
	# clears it), then turned; near first, then as far as it takes.
	var passes := []
	for steps: Array in [MOVE_STEPS, FAR_STEPS]:
		if (rule.has("way") or rule.has("ways")) and not rule.has("bearing"):
			passes.append([steps, [was]])
		passes.append([steps, bearings])
	var fallback := {}  # (Nothing clears it: the least land.)
	var fallback_hits := INF
	for pass_: Array in passes:
		var found := _search(id, at, was, flip_was, pass_[0], pass_[1], allowed, least, fallback)
		fallback = found[1]
		if not (found[0] as Dictionary).is_empty():
			return found[0]
	if not fallback.is_empty():
		fallback.way = fallback.way + " (still touches)"
	return fallback


## The best place and facing among moves of `steps` (degrees) along the
## `allowed` ways and the `bearings`: [the nearest that clears the mouth and
## funnel (or {}), the least land seen so far (`fallback` bettered)].
func _search(id: String, at: Vector2, was: float, flip_was: float, steps: Array, bearings: Array, allowed: Array, least: float, fallback: Dictionary) -> Array:
	var best := {}
	var best_cost := INF
	var fallback_hits: float = fallback.get("hits", INF)
	for moved: float in steps:
		if moved < least:
			continue
		var ways: Array = [[0.0, 0.0, "-"]] if moved == 0.0 else allowed.map(func(name: String) -> Array: return [WAYS[name][0], WAYS[name][1], name])
		for way: Array in ways:
			var step := Vector2(float(way[0]), float(way[1])).normalized() * moved
			var here := Vector2(at.x + step.x / maxf(cos(deg_to_rad(at.y)), 0.05), at.y + step.y)
			for bearing: float in bearings:
				var turned := absf(wrapf(bearing - was, -180.0, 180.0))
				for flip: float in [flip_was, -flip_was]:
					# Nearer moves and smaller turns first: a candidate that can't
					# beat the best is skipped before the land is looked at.
					var cost := moved * 100.0 + turned * 0.2 + (5.0 if flip != flip_was else 0.0)
					if cost >= best_cost:
						continue
					var r := _check(id, here, bearing, flip)
					var found := {lon = snappedf(here.x, 0.001), lat = snappedf(here.y, 0.001), bearing = roundi(bearing), quay = "right" if flip > 0.0 else "left",
						moved = moved, way = way[2], was_bearing = roundi(was), harbour_land = r.harbour_land, funnel_land = r.funnel_land, quay_land = r.quay_land, mouth_land = r.mouth_land}
					var hits := float(r.funnel_land) * 3.0 + (100.0 if r.mouth_land else 0.0) + float(r.harbour_land) * 0.3 + moved * 50.0
					if hits < fallback_hits:
						fallback_hits = hits
						fallback = found
						fallback.hits = hits
					if r.mouth_land or r.funnel_land > 0:
						continue
					var over_land := float(r.harbour_land) / maxf(r.harbour_points, 1.0)
					if over_land > HARBOUR_LAND_MOST:
						continue  # (A marina lying wholly over the land, only its mouth on the water: not a fix.)
					cost += (1.0 - r.quay_land) * 30.0 + over_land * 40.0  # (A marina with its quay in the sea, or its jetty over the coast, looks wrong: avoided where it can be.)
					if cost < best_cost:
						best_cost = cost
						best = found
		if not best.is_empty() and best.quay_land >= 0.5 and best.harbour_land < 30:
			break  # (A good one this near: no further.)
	return [best, fallback]
