# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends SceneTree
## Builds data/anchorages.json: for every port, where its ships lie at anchor
## (waiting for a berth, idle, tugs and service ships): anchor points on a
## hexagonal grid round the port, each far enough from every other that two
## ships swung round by the same wind never touch, and each clear of land all
## the way round, as far as the longest ship in the game (the Mammoth) can
## swing about its anchor, whatever way the wind blows. The map leaves out
## those its port's marina could reach (MapView._anchor_spots()) and fills the
## rest nearest the sea first.
##
##   Godot --headless --path . -s tools/build_anchorages.gd
##
## Rerun after changing ports.json, the map (world_map.res) or ship sizes.

const OUT := "res://data/anchorages.json"
const FACING := "res://data/port_facing.json"
## The land raster: cells this many to a degree.
const CELLS_PER_DEG := 16
## Anchor points kept per port, and how far out (nm) to look for them.
const KEEP := 60
## Ships up to this long (dock units) use the closer, denser anchorage.
const SMALL_LENGTH := 9.0
const SEARCH_NM := 420.0
## Extra room (nm) round a swinging ship, and between neighbouring ships.
const MARGIN_NM := 1.0
## Map units (MapView): a dock unit is 1 / SHIP_WORLD_ZOOM degrees of the globe.
const SHIP_WORLD_ZOOM := 75.0
const SHIP_SIZE := 0.35
const BOW_LENGTH_FACTOR := 0.6

var _cols := 360 * CELLS_PER_DEG
var _rows := 180 * CELLS_PER_DEG
var _land := PackedByteArray()


func _init() -> void:
	var started := Time.get_ticks_msec()
	var map: WorldMapData = load("res://data/world_map.res")
	_land.resize(_cols * _rows)
	_fill(map.land_triangles, 1)
	_fill(map.water_triangles, 0)
	for triangles in map.lake_triangles:
		_fill(triangles, 0)
	_fill(map.lake_island_triangles, 1)
	print("Land raster in %d s" % ((Time.get_ticks_msec() - started) / 1000))

	# Two anchorages: one with room for the longest ship of all (the Mammoth),
	# and a closer, denser one for ships up to SMALL_LENGTH (dock units) long.
	var longest := 0.0
	for model: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/ship_models.json")).models:
		var dims: Array = model.get("map_size", [14, 6])
		longest = maxf(longest, (float(dims[0]) + float(dims[1]) * BOW_LENGTH_FACTOR) * SHIP_SIZE)
	var swing_nm := longest * 60.0 / SHIP_WORLD_ZOOM + MARGIN_NM
	var small_swing_nm := SMALL_LENGTH * 60.0 / SHIP_WORLD_ZOOM + MARGIN_NM
	print("Swing room %.1f nm (ships up to %.1f units long: %.1f nm)" % [swing_nm, SMALL_LENGTH, small_swing_nm])

	var facing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FACING)) if FileAccess.file_exists(FACING) else {}
	var out := {}
	var short := []
	for port: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/ports.json")).ports:
		var entry: Dictionary = facing.get("manual", {}).get(port.id, facing.get("facing", {}).get(port.id, {}))
		var bearing := float(entry.get("bearing", NAN))
		var at := Vector2(float(port.lon), float(port.lat))
		var spots := {
			all = _spots(at, bearing, swing_nm, swing_nm + MARGIN_NM),
			small = _spots(at, bearing, small_swing_nm, small_swing_nm + MARGIN_NM),
		}
		out[port.id] = spots
		if spots.all.size() < 8 or spots.small.size() < 12:
			short.append("%s (%d, %d)" % [port.id, spots.all.size(), spots.small.size()])
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		_comment = "Anchor points (lon, lat) round each port, nearest the sea first: built by tools/build_anchorages.gd. all: each clear of land as far as the longest ship can swing about it (%.1f nm), and that far and a little more from the others; small: the same for ships up to small_length dock units long (%.1f nm)." % [swing_nm, small_swing_nm],
		small_length = SMALL_LENGTH,
		ports = out,
	}, "\t", false))
	file.close()
	print("Ports with under 8 anchor points for the longest ships or 12 for the rest: %s" % (", ".join(short) if not short.is_empty() else "none"))
	print("Done in %d s" % ((Time.get_ticks_msec() - started) / 1000))
	quit()


## A port's anchor points: a hexagonal grid (spacing_nm apart, lined up with
## the way to sea) out to SEARCH_NM, keeping those whose swing circle is all
## water, nearest a point out to sea from the port first.
func _spots(at: Vector2, bearing: float, swing_nm: float, spacing_nm: float) -> Array:
	var sea_way := Vector2.ZERO
	var turn := 0.0
	if not is_nan(bearing):
		turn = deg_to_rad(90.0 - bearing)  # Compass bearing to an east-north angle.
		sea_way = Vector2.from_angle(turn)
	var toward := sea_way * swing_nm * 1.5  # Prefer the sea side.
	var found := []
	var rings := ceili(SEARCH_NM / spacing_nm)
	var row_step := spacing_nm * sqrt(3.0) / 2.0
	for row in range(-rings, rings + 1):
		for col in range(-rings, rings + 1):
			var local := Vector2((col + (row % 2) * 0.5) * spacing_nm, row * row_step).rotated(turn)
			if local.length() > SEARCH_NM or local.length() < spacing_nm * 0.5:
				continue
			var point := _offset(at, local)
			if _clear(point, swing_nm):
				found.append([local.distance_to(toward), point])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var spots := []
	for item: Array in found.slice(0, KEEP):
		var point: Vector2 = item[1]
		spots.append([snappedf(point.x, 0.0001), snappedf(point.y, 0.0001)])
	return spots


## A (lon, lat) moved by east and north nm.
static func _offset(at: Vector2, nm: Vector2) -> Vector2:
	var lat := at.y + nm.y / 60.0
	return Vector2(wrapf(at.x + nm.x / (60.0 * maxf(cos(deg_to_rad(at.y)), 0.05)), -180.0, 180.0), lat)


## True if every land raster cell within radius_nm of a point is water.
func _clear(point: Vector2, radius_nm: float) -> bool:
	if absf(point.y) > 84.0:
		return false
	var lat_cells := ceili(radius_nm / 60.0 * CELLS_PER_DEG) + 1
	var cos_lat := maxf(cos(deg_to_rad(point.y)), 0.05)
	var lon_cells := ceili(radius_nm / (60.0 * cos_lat) * CELLS_PER_DEG) + 1
	var center_col := floori((point.x + 180.0) * CELLS_PER_DEG)
	var center_row := floori((90.0 - point.y) * CELLS_PER_DEG)
	for dr in range(-lat_cells, lat_cells + 1):
		var row := center_row + dr
		if row < 0 or row >= _rows:
			return false
		var dy := float(dr) / CELLS_PER_DEG * 60.0
		for dc in range(-lon_cells, lon_cells + 1):
			var dx := float(dc) / CELLS_PER_DEG * 60.0 * cos_lat
			# The cell's nearest corner within reach, not just its middle.
			if Vector2(maxf(absf(dx) - 60.0 * cos_lat / CELLS_PER_DEG, 0.0), maxf(absf(dy) - 60.0 / CELLS_PER_DEG, 0.0)).length() > radius_nm:
				continue
			if _land[row * _cols + posmod(center_col + dc, _cols)] != 0:
				return false
	return true


## Marks the cells whose middles are inside the triangles (projected map
## coordinates) with a value (1 land, 0 water). Land also marks the cells its
## corners are in, so an islet smaller than a cell isn't missed.
func _fill(triangles: PackedVector2Array, value: int) -> void:
	for i in range(0, triangles.size() - 2, 3):
		var a := Geo.unproject(triangles[i])
		var b := Geo.unproject(triangles[i + 1])
		var c := Geo.unproject(triangles[i + 2])
		if value != 0:
			for corner: Vector2 in [a, b, c]:
				var corner_row := clampi(floori((90.0 - corner.y) * CELLS_PER_DEG), 0, _rows - 1)
				_land[corner_row * _cols + posmod(floori((corner.x + 180.0) * CELLS_PER_DEG), _cols)] = value
		var col_from := floori((minf(a.x, minf(b.x, c.x)) + 180.0) * CELLS_PER_DEG)
		var col_to := floori((maxf(a.x, maxf(b.x, c.x)) + 180.0) * CELLS_PER_DEG)
		var row_from := floori((90.0 - maxf(a.y, maxf(b.y, c.y))) * CELLS_PER_DEG)
		var row_to := floori((90.0 - minf(a.y, minf(b.y, c.y))) * CELLS_PER_DEG)
		for row in range(maxi(row_from, 0), mini(row_to, _rows - 1) + 1):
			var lat := 90.0 - (row + 0.5) / CELLS_PER_DEG
			for col in range(col_from, col_to + 1):
				var p := Vector2((col + 0.5) / CELLS_PER_DEG - 180.0, lat)
				if Geometry2D.point_is_inside_triangle(p, a, b, c):
					_land[row * _cols + posmod(col, _cols)] = value
