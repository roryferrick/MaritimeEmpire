# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Currents
extends RefCounted
## The ocean currents (data/currents.json): each a path the water flows
## along, felt out to its width (fading to its edge), as strong as its month
## says. Laid once onto a grid of CELL_DEG cells, each holding the strongest
## current there (its velocity at full strength, and which current it is), so
## asking the water's velocity anywhere is a lookup and a multiply.
##
## Ships feel them along their lanes (lane_factors(): faster with the flow,
## slower against it, so fuel goes with the time at sea), the lane tool plans
## each lane's second way round that rides a current (tools/build_map_data.gd
## --currents-only), and the map draws them flowing (MapView).

const PATH := "res://data/currents.json"
const CELL_DEG := 0.5
const COLS := 720  # (-180 to 180.)
const ROWS := 320  # (-80 to 80.)
const SOUTH := -80.0
const KM_PER_DEG := 111.2
## The month index for the year's average.
const MEAN := 12
## Lane factors are worked out on stretches about this long (nm), and runs
## whose speed factor rounds to the same FACTOR_STEP are one zone.
const SAMPLE_NM := 40.0
const FACTOR_STEP := 0.02

static var _shared: Currents = null

## Each current as read, with "flow" (its path as Vector2 lon/lat) and
## "strength" (13 multipliers: the months, then the year's average).
var list: Array[Dictionary] = []
## Per cell: the strongest current's velocity there at strength 1 (knots,
## east and north), and that current's index + 1 (0: none).
var _velocity := PackedVector2Array()
var _which := PackedByteArray()


static func shared() -> Currents:
	if _shared == null:
		_shared = Currents.new()
		_shared._load()
	return _shared


func _load() -> void:
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("Currents: could not read %s" % PATH)
		return
	for item: Dictionary in parsed.get("currents", []):
		var flow := PackedVector2Array()
		for p: Array in item.path:
			flow.append(Vector2(float(p[0]), float(p[1])))
		var strength := PackedFloat32Array()
		var total := 0.0
		for m: float in item.months:
			strength.append(m)
			total += m
		strength.append(total / 12.0)
		item.flow = flow
		item.strength = strength
		list.append(item)
	_build_grid()


## Lays every current onto the grid (the strongest wins a cell).
func _build_grid() -> void:
	_velocity.resize(COLS * ROWS)
	_which.resize(COLS * ROWS)
	var best := PackedFloat32Array()
	best.resize(COLS * ROWS)
	for index in list.size():
		var item := list[index]
		var flow: PackedVector2Array = item.flow
		var speed := float(item.speed_kn)
		var width := float(item.width_km)
		for k in range(1, flow.size()):
			var a := flow[k - 1]
			var b := flow[k]
			var mid_cos := maxf(cos(deg_to_rad((a.y + b.y) / 2.0)), 0.1)
			# In km about the segment's start (east, north).
			var along := Vector2((b.x - a.x) * mid_cos, b.y - a.y) * KM_PER_DEG
			var length := along.length()
			if length <= 0.0:
				continue
			var dir := along / length
			var reach_lat := width / KM_PER_DEG
			var reach_lon := reach_lat / mid_cos
			var row0 := maxi(floori((minf(a.y, b.y) - reach_lat - SOUTH) / CELL_DEG), 0)
			var row1 := mini(floori((maxf(a.y, b.y) + reach_lat - SOUTH) / CELL_DEG), ROWS - 1)
			var col0 := floori((minf(a.x, b.x) - reach_lon + 180.0) / CELL_DEG)
			var col1 := floori((maxf(a.x, b.x) + reach_lon + 180.0) / CELL_DEG)
			for row in range(row0, row1 + 1):
				var lat := SOUTH + (row + 0.5) * CELL_DEG
				for col in range(col0, col1 + 1):
					var lon := -180.0 + (col + 0.5) * CELL_DEG
					var p := Vector2((lon - a.x) * mid_cos, lat - a.y) * KM_PER_DEG
					var t := clampf(p.dot(dir) / length, 0.0, 1.0)
					var d := p.distance_to(along * t)
					if d >= width:
						continue
					var share := 1.0 - (d / width) * (d / width)
					var cell := row * COLS + posmod(col, COLS)
					if share * speed > best[cell]:
						best[cell] = share * speed
						_velocity[cell] = dir * speed * share
						_which[cell] = index + 1


## The water's velocity (knots: x east, y north) at a point (lon, lat) in a
## month (0-11, or MEAN).
func velocity(lon_lat: Vector2, month: int) -> Vector2:
	var cell := _cell(lon_lat)
	if cell < 0 or _which[cell] == 0:
		return Vector2.ZERO
	return _velocity[cell] * float(list[_which[cell] - 1].strength[month])


## The current at a point (its entry in `list`), or {} for none.
func current_at(lon_lat: Vector2) -> Dictionary:
	var cell := _cell(lon_lat)
	if cell < 0 or _which[cell] == 0:
		return {}
	return list[_which[cell] - 1]


func _cell(lon_lat: Vector2) -> int:
	var row := floori((lon_lat.y - SOUTH) / CELL_DEG)
	if row < 0 or row >= ROWS:
		return -1
	return row * COLS + posmod(floori((lon_lat.x + 180.0) / CELL_DEG), COLS)


## The month to feel the currents in at a calendar time (unix): its month,
## 0-11, whatever the seasonal closures setting (like the trees' seasons).
## (No GameState here: the lane tool uses this class too.)
static func month_of(unix: int) -> int:
	return int(Time.get_datetime_dict_from_unix_time(unix).month) - 1


## How a lane's currents speed a ship up or slow it down, as zones
## ([[end mile, speed factor], ...], every mile covered): on each stretch,
## (ref_speed + the current's part along the way) / ref_speed, capped to
## [1 - limit, 1 + limit]. `points` projected, `miles` along them.
func lane_factors(points: PackedVector2Array, miles: PackedFloat64Array, month: int, ref_speed: float, limit: float) -> Array:
	var zones := []
	if points.size() < 2:
		return zones
	var run_factor := 1.0
	var k := 1
	var mile := 0.0
	var total := miles[miles.size() - 1]
	while mile < total:
		var next := minf(mile + SAMPLE_NM, total)
		while k < miles.size() - 1 and miles[k] < (mile + next) / 2.0:
			k += 1
		var a := Geo.unproject(points[k - 1])
		var b := Geo.unproject(points[k])
		var share := clampf(((mile + next) / 2.0 - miles[k - 1]) / maxf(miles[k] - miles[k - 1], 0.001), 0.0, 1.0)
		var here := a.lerp(b, share)
		var way := Vector2((b.x - a.x) * cos(deg_to_rad(here.y)), b.y - a.y)
		var factor := 1.0
		if way.length_squared() > 0.0:
			var push := velocity(here, month).dot(way.normalized())
			factor = clampf((ref_speed + push) / ref_speed, 1.0 - limit, 1.0 + limit)
			factor = 1.0 + snappedf(factor - 1.0, FACTOR_STEP)
		if zones.is_empty() or not is_equal_approx(factor, run_factor):
			if not zones.is_empty():
				zones[-1][0] = mile
			zones.append([next, factor])
			run_factor = factor
		else:
			zones[-1][0] = next
		mile = next
	return zones


## The hours a lane takes at `ref_speed` with its currents in a month (the
## lane tool compares a lane's two ways round by it).
func lane_hours(points: PackedVector2Array, miles: PackedFloat64Array, month: int, ref_speed: float, limit: float) -> float:
	var hours := 0.0
	var start := 0.0
	for zone: Array in lane_factors(points, miles, month, ref_speed, limit):
		hours += (float(zone[0]) - start) / (ref_speed * float(zone[1]))
		start = zone[0]
	return hours


## lane_factors() of the shared currents (for GameData's lane zones).
static func lane_factors_of(points: PackedVector2Array, miles: PackedFloat64Array, month: int, ref_speed: float, limit: float) -> Array:
	return shared().lane_factors(points, miles, month, ref_speed, limit)
