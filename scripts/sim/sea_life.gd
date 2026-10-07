# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name SeaLife
extends RefCounted
## Sea animals (data/sea_life.json), just for looking at: pods of dolphins,
## orcas and whales that spend parts of the year in their areas, wandering
## about each, and migrate between them along sea paths found around the land
## (WorldMapData.sea_mask, with Godot's AStarGrid2D).
## Where a pod is follows from the in-game calendar alone (see state()), so
## every player sees the same and nothing is saved or sent.

const DATA_PATH := "res://data/sea_life.json"
## Paths are found on the sea mask's own cells (a quarter of a degree), so
## narrow straits stay open; the grid is filled in GRID_ROWS_A_STEP rows a
## step (see start_warm_up()).
const PATH_CELL := 0.25
const GRID_ROWS_A_STEP := 12
## A pod wanders from spot to spot in its area, one leg every WANDER_DAYS
## calendar days, within WANDER_SHARE of the area's radius; it eases out to
## them over its first RAMP_DAYS there and back to the middle over its last,
## where its migration paths start and end.
const WANDER_DAYS := 2.0
const WANDER_SHARE := 0.8
const RAMP_DAYS := 4.0
## Days of the (non-leap) year each month starts on.
const MONTH_STARTS := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

static var _shared: SeaLife = null

## id -> {name, plural, word, kind, art, length_px, spacing_px, shown, surface, breach, length_m, fact}.
var species := {}
## id -> {name, lon, lat, radius_nm}.
var areas := {}
## Each pod: {species, name, size, stays: [{area, start, end}] (days of the
## year, sorted by start; a stay can run over the new year)}.
var pods: Array[Dictionary] = []

var _mask := PackedByteArray()
var _mask_size := Vector2i.ZERO
var _astar: AStarGrid2D = null
var _grid_rows := 0  # Rows of _astar filled in so far.
## The warm-up's task (-1 when none is running), and whether it's done.
var _task := -1
var _ready := false
## "from>to" -> [points (lon, lat), miles along to each point].
var _paths := {}


## The one SeaLife (loaded the first time it's asked for).
static func shared() -> SeaLife:
	if _shared == null:
		_shared = SeaLife.new()
	return _shared


func _init() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text()) if file else {}
	species = data.get("species", {})
	areas = data.get("areas", {})
	for pod: Dictionary in data.get("pods", []):
		var stays: Array[Dictionary] = []
		for stay: Array in pod.stays:
			stays.append({area = str(stay[0]), start = _day_of(str(stay[1])), end = _day_of(str(stay[2]))})
		stays.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.start < b.start)
		pods.append({species = str(pod.species), name = str(pod.name), size = int(pod.size), stays = stays})
	_mask = GameData.world_map.sea_mask
	_mask_size = GameData.world_map.sea_mask_size


## "06-15" -> the day of the year it starts (0 for 1 Jan).
static func _day_of(month_day: String) -> float:
	var parts := month_day.split("-")
	return float(MONTH_STARTS[int(parts[0]) - 1] + int(parts[1]) - 1)


## True if a (lon, lat) point is at sea (by the sea mask).
func is_sea(lon_lat: Vector2) -> bool:
	if _mask_size.x == 0:
		return true
	var col := posmod(floori((lon_lat.x + 180.0) / 360.0 * _mask_size.x), _mask_size.x)
	var row := clampi(floori((90.0 - lon_lat.y) / 180.0 * _mask_size.y), 0, _mask_size.y - 1)
	var i := row * _mask_size.x + col
	return (_mask[i >> 3] >> (i & 7)) & 1 == 1


# --- Where a pod is ---------------------------------------------------------------

## A pod at a calendar time: {pos (lon, lat), heading (east, north; unit, or
## zero), migrating, area (the stay's, or where it's going), from (the area it
## left, if migrating), progress (0..1 along the way), until (calendar time
## it leaves or arrives)}.
func state(pod_index: int, unix: float) -> Dictionary:
	var here := _place(pod_index, unix)
	var ahead := _place(pod_index, unix + 3.0 * 3600.0)
	var step: Vector2 = ahead.pos - here.pos
	step.x = wrapf(step.x, -180.0, 180.0) * cos(deg_to_rad(here.pos.y))
	here.heading = step.normalized() if step.length() > 0.00001 else Vector2.ZERO
	return here


func _place(pod_index: int, unix: float) -> Dictionary:
	var pod: Dictionary = pods[pod_index]
	var stays: Array = pod.stays
	var day := _year_day(unix)
	var days := unix / 86400.0
	for i in stays.size():
		var stay: Dictionary = stays[i]
		var into := fposmod(day - stay.start, 365.0)
		var length := fposmod(stay.end - stay.start, 365.0)
		if into < length:
			var area: Dictionary = areas[stay.area]
			var center := Vector2(area.lon, area.lat)
			var ramp := smoothstep(0.0, 1.0, minf(into, length - into) / RAMP_DAYS)
			var offset := _wander(pod_index, center, float(area.radius_nm), days) * ramp
			return {pos = _offset(center, offset), migrating = false, area = stay.area, from = "", progress = 0.0,
				until = unix + (length - into) * 86400.0}
	# Between stays: on its way from the last one to the next.
	for i in stays.size():
		var leave: Dictionary = stays[i]
		var reach: Dictionary = stays[(i + 1) % stays.size()]
		var gap := fposmod(reach.start - leave.end, 365.0)
		var gone := fposmod(day - leave.end, 365.0)
		if gone < gap:
			var progress := gone / gap
			return {pos = _along(leave.area, reach.area, progress), migrating = true, area = reach.area, from = leave.area,
				progress = progress, until = unix + (gap - gone) * 86400.0}
	var first: Dictionary = areas[stays[0].area]
	return {pos = Vector2(first.lon, first.lat), migrating = false, area = stays[0].area, from = "", progress = 0.0, until = unix}


## The day of the year (0 to 365) at a calendar time, a leap year squeezed to 365 days.
static func _year_day(unix: float) -> float:
	var date := Time.get_datetime_dict_from_unix_time(int(unix))
	var start := Time.get_unix_time_from_datetime_dict({year = date.year, month = 1, day = 1, hour = 0, minute = 0, second = 0})
	var end := Time.get_unix_time_from_datetime_dict({year = date.year + 1, month = 1, day = 1, hour = 0, minute = 0, second = 0})
	return (unix - start) / float(end - start) * 365.0


## Where in its area a pod has wandered to (nm east and north of the middle):
## between one spot and the next, a leg every WANDER_DAYS. Each spot is picked
## by the pod and leg number, so it's the same for everyone.
func _wander(pod_index: int, center: Vector2, radius_nm: float, days: float) -> Vector2:
	var leg := floorf(days / WANDER_DAYS)
	var t := smoothstep(0.0, 1.0, days / WANDER_DAYS - leg)
	return _spot(pod_index, center, radius_nm, int(leg)).lerp(_spot(pod_index, center, radius_nm, int(leg) + 1), t)


func _spot(pod_index: int, center: Vector2, radius_nm: float, leg: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	for attempt in 6:
		rng.seed = hash([pod_index, leg, attempt])
		var offset := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius_nm * WANDER_SHARE
		if is_sea(_offset(center, offset)):
			return offset
	return Vector2.ZERO


## A (lon, lat) point moved some nm east and north.
static func _offset(lon_lat: Vector2, nm: Vector2) -> Vector2:
	return Vector2(wrapf(lon_lat.x + nm.x / (60.0 * maxf(cos(deg_to_rad(lon_lat.y)), 0.1)), -180.0, 180.0), lon_lat.y + nm.y / 60.0)


# --- Migration paths ------------------------------------------------------------------

## A share (0..1) of the way along the sea path from one area to another,
## easing in and out at the ends.
func _along(from: String, to: String, share: float) -> Vector2:
	var path: Array = path_between(from, to)
	var points: PackedVector2Array = path[0]
	var miles: PackedFloat32Array = path[1]
	if points.size() < 2:
		return points[0] if not points.is_empty() else Vector2.ZERO
	var target := miles[-1] * lerpf(share, smoothstep(0.0, 1.0, share), 0.5)
	for i in range(1, points.size()):
		if miles[i] >= target:
			var span := miles[i] - miles[i - 1]
			var t := (target - miles[i - 1]) / span if span > 0.0 else 0.0
			var a := points[i - 1]
			var b := points[i]
			return Vector2(wrapf(a.x + wrapf(b.x - a.x, -180.0, 180.0) * t, -180.0, 180.0), lerpf(a.y, b.y, t))
	return points[-1]


## The sea path between two areas' middles: [points (lon, lat), miles along
## to each]. Found once (AStarGrid2D on the PATH_CELL grid), then straightened
## where the sea allows.
func path_between(from: String, to: String) -> Array:
	var key := "%s>%s" % [from, to]
	if _paths.has(key):
		return _paths[key]
	var back := "%s>%s" % [to, from]
	if _paths.has(back):  # The way back, reversed.
		var points: PackedVector2Array = _paths[back][0].duplicate()
		points.reverse()
		var total: float = _paths[back][1][-1]
		var miles := PackedFloat32Array()
		for mile: float in _paths[back][1]:
			miles.insert(0, total - mile)
		_paths[key] = [points, miles]
		return _paths[key]
	var a: Dictionary = areas[from]
	var b: Dictionary = areas[to]
	var start := Vector2(a.lon, a.lat)
	var end := Vector2(b.lon, b.lat)
	var grid := _grid()
	var points := PackedVector2Array([start])
	var cells := grid.get_id_path(_nearest_sea_cell(start), _nearest_sea_cell(end), true)
	if cells.is_empty() or cells[-1] != _nearest_sea_cell(end):
		push_warning("No sea path from %s to %s; going as near as there is." % [from, to])
	for cell: Vector2i in cells:
		points.append(_cell_center(cell))
	points.append(end)
	points = _straighten(points)
	var miles := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		miles.append(miles[i - 1] + Geo.distance_nm(points[i - 1], points[i]))
	_paths[key] = [points, miles]
	return _paths[key]


## The path-finding grid: a cell per sea mask cell, land solid (filled in
## GRID_ROWS_A_STEP rows at a time, on the warm-up's thread).
func _grid() -> AStarGrid2D:
	while _fill_grid():
		pass
	return _astar


## Fills in the next GRID_ROWS_A_STEP rows of the path-finding grid; false once it's whole.
func _fill_grid() -> bool:
	if _astar == null:
		_astar = AStarGrid2D.new()
		_astar.region = Rect2i(Vector2i.ZERO, _mask_size)
		_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		_astar.update()
	if _grid_rows >= _mask_size.y:
		return false
	var cols := _mask_size.x
	for row in range(_grid_rows, mini(_grid_rows + GRID_ROWS_A_STEP, _mask_size.y)):
		for col in cols:
			var i := row * cols + col
			if (_mask[i >> 3] >> (i & 7)) & 1 == 0:
				_astar.set_point_solid(Vector2i(col, row))
	_grid_rows += GRID_ROWS_A_STEP
	return _grid_rows < _mask_size.y


## True once a pod's way from one area to the next has been found.
func has_path(from: String, to: String) -> bool:
	return _paths.has("%s>%s" % [from, to]) or _paths.has("%s>%s" % [to, from])


## Gets the sea animals ready off the main thread (WorkerThreadPool): the
## path-finding grid, then every pod's migration paths. The map shows them
## once is_ready(); until then nothing else touches the grid or paths.
func start_warm_up() -> void:
	if _task < 0 and not _ready:
		_task = WorkerThreadPool.add_task(_warm_up, false, "Sea animal paths")


func _warm_up() -> void:
	_grid()
	for pod: Dictionary in pods:
		var stays: Array = pod.stays
		for i in stays.size():
			path_between(stays[i].area, stays[(i + 1) % stays.size()].area)
	_ready = true


## True once the warm-up (start_warm_up()) is done.
func is_ready() -> bool:
	if _ready and _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	return _ready


func _cell_of(lon_lat: Vector2) -> Vector2i:
	return Vector2i(posmod(floori((lon_lat.x + 180.0) / PATH_CELL), roundi(360.0 / PATH_CELL)),
		clampi(floori((90.0 - lon_lat.y) / PATH_CELL), 0, roundi(180.0 / PATH_CELL) - 1))


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(-180.0 + (cell.x + 0.5) * PATH_CELL, 90.0 - (cell.y + 0.5) * PATH_CELL)


## The sea cell nearest a point (an area's middle may sit in a cell that's
## mostly land).
func _nearest_sea_cell(lon_lat: Vector2) -> Vector2i:
	var cell := _cell_of(lon_lat)
	var grid := _grid()
	for ring in 24:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var each := cell + Vector2i(dx, dy)
				if grid.is_in_boundsv(each) and not grid.is_point_solid(each):
					return each
	return cell


## Drops the corners a straight line over open sea can cut: from each point
## the path runs on to the last of the next ones it can still see.
func _straighten(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([points[0]])
	var i := 0
	while i < points.size() - 1:
		var j := i + 1
		while j + 1 < points.size() and _clear(points[i], points[j + 1]):
			j += 1
		out.append(points[j])
		i = j
	return out


## True if the sea mask shows no land on the straight line between two points.
func _clear(a: Vector2, b: Vector2) -> bool:
	var delta := Vector2(wrapf(b.x - a.x, -180.0, 180.0), b.y - a.y)
	var steps := maxi(ceili(delta.length() / 0.1), 1)
	for s in range(1, steps):
		var p := a + delta * (float(s) / steps)
		if not is_sea(Vector2(wrapf(p.x, -180.0, 180.0), p.y)):
			return false
	return true


## A pod's whole year of migration paths, as (lon, lat) point lists.
func pod_paths(pod_index: int) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var stays: Array = pods[pod_index].stays
	for i in stays.size():
		out.append(path_between(stays[i].area, stays[(i + 1) % stays.size()].area)[0])
	return out
