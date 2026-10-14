# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Builds data/anchorages.json: for every port, where its ships lie at anchor
## (waiting for a berth, idle, tugs and service ships): anchor points on a
## hexagonal grid round the port, each far enough from every other that two
## ships swung round by the same wind never touch, each clear of land all
## the way round, as far as the longest ship in the game (the Mammoth) can
## swing about its anchor, whatever way the wind blows, none in the funnel
## in front of the harbour mouth, where every ship in or out sails
## (FUNNEL_DEG either side of the way to sea, out past the harbour gate to
## where the ships' curves have joined the lane: see MapView._lane_reaches()),
## and none on any port's approach (data/approaches.json: its lanes' fixed
## way from its gate out to open sea). The map leaves out those its port's
## marina could reach (MapView._anchor_spots()) and fills the rest nearest
## the port first, favouring the sides over straight out in front (where the
## lanes come in), and never one a lane sailed now runs through
## (MapView._anchors_in_lanes()).
##
##   Godot --headless --path . tools/build_anchorages.tscn
##
## Rerun after changing ports.json, the map (world_map.res), ship sizes or
## the marinas' sizes.

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
const SHIP_WORLD_ZOOM := 88.235  # (MapView.SHIP_WORLD_ZOOM.)
const SHIP_SIZE := 0.245
const BOW_LENGTH_FACTOR := 0.6
## Water no ship anchors in (lon west, lat south, lon east, lat north): the
## Strait of Messina, a shipping passage too narrow for parked ships.
const EXCLUDE_BOXES := [[15.45, 37.95, 15.80, 38.40]]

## The funnel in front of the harbour mouth no ship anchors in: this far
## either side of the way to sea (degrees), out past the harbour gate to
## where the ships' curves have joined the lane (see _ready()), at least FUNNEL_MIN_NM.
const FUNNEL_DEG := 30.0
const FUNNEL_MIN_NM := 6.0
const APPROACHES := "res://data/approaches.json"
## A spot straight out in front counts this much further than one the same
## distance off to the side (so the sides fill first; the lanes come in in
## front), and one behind the port (where a ship coming to anchor would
## have to go round the marina) further still.
const FRONT_PENALTY := 0.6
const BACK_PENALTY := 1.5
## No spot further round than this (degrees off the way to sea): a ship coming
## to anchor sails there from the harbour mouth, and behind the port that's
## through the marina.
const BEHIND_DEG := 110.0

var _cols := 360 * CELLS_PER_DEG
var _rows := 180 * CELLS_PER_DEG
var _land := PackedByteArray()


func _ready() -> void:
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

	# The funnel's reach: out to the harbour gate (MapView.GATE_UNITS, where
	# every lane starts) and the stretch past it where the ships' curves join
	# the lane (see MapView._lane_reaches()); the same at every port.
	var hub_berths := str((GameData.config.get("docks", {}) as Dictionary).get("hub_berths", "sssBBsss"))
	var funnels := {}
	for canal in [false, true]:
		funnels[canal] = maxf(MapView.GATE_UNITS * 60.0 / SHIP_WORLD_ZOOM * (1.0 + MapView.HARBOUR_JOIN_SHARE * MapView.HARBOUR_REACH_GROW), FUNNEL_MIN_NM)
	print("Funnel in front of the mouth: %.0f degrees either side, out to %.1f nm" % [FUNNEL_DEG, funnels[false]])
	# And every port's approach (data/approaches.json: its lanes' fixed way
	# from its gate out to open sea), (lon, lat) points: no anchoring on it.
	var approaches := {}
	if FileAccess.file_exists(APPROACHES):
		for id: String in JSON.parse_string(FileAccess.get_file_as_string(APPROACHES)).ports:
			var points := PackedVector2Array()
			for p: Array in JSON.parse_string(FileAccess.get_file_as_string(APPROACHES)).ports[id].points:
				points.append(Vector2(float(p[0]), float(p[1])))
			approaches[id] = points
	else:
		print("No %s: build the lanes first (tools/build_map_data.gd); the approaches aren't kept clear" % APPROACHES)

	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT)) if FileAccess.file_exists(OUT) else {}
	var facing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FACING)) if FileAccess.file_exists(FACING) else {}
	# No anchoring in another port's marina (the biggest it can be), nor so near
	# it that a ship swinging there could reach it, nor in its funnel.
	var widest := 0.0
	for canal in [false, true]:
		widest = maxf(widest, float(MapView._marina_layout(hub_berths, true, canal).radius))
	var keep_off_nm := (widest + MapView.JETTY_WIDTH) * 60.0 / SHIP_WORLD_ZOOM + swing_nm + MARGIN_NM
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/ports.json")).ports
	var places := []  # [port id, (lon, lat), bearing, funnel nm]
	for port: Dictionary in ports:
		var entry: Dictionary = facing.get("manual", {}).get(port.id, facing.get("facing", {}).get(port.id, {}))
		places.append([port.id, Vector2(float(port.lon), float(port.lat)), float(entry.get("bearing", NAN)), funnels[MapView._is_canal_port(port.id)]])
	var out := {}
	var short := []
	var in_funnel := 0
	var worst := []
	for place: Array in places:
		var port := {id = place[0]}
		var at: Vector2 = place[1]
		var bearing: float = place[2]
		var funnel_nm: float = place[3]
		# The ports near enough to matter, as east and north nm of this one: [(east, north), the way to sea (or zero), funnel nm].
		var others := []
		var squash := maxf(cos(deg_to_rad(at.y)), 0.05)
		for other: Array in places:
			if other[0] == port.id or Geo.distance_nm(at, other[1]) > SEARCH_NM + keep_off_nm + float(other[3]):
				continue
			var there: Vector2 = other[1]
			var sea_way := Vector2.ZERO if is_nan(float(other[2])) else Vector2.from_angle(deg_to_rad(90.0 - float(other[2])))
			others.append([Vector2(wrapf(there.x - at.x, -180.0, 180.0) * 60.0 * squash, (there.y - at.y) * 60.0), sea_way, float(other[3])])
		# This port's approach and its neighbours' (within reach), as east and north nm of this port.
		var ways := []
		for other: Array in places:
			if other[0] != port.id and Geo.distance_nm(at, other[1]) > SEARCH_NM * 2.0:
				continue
			var way := PackedVector2Array()
			for p: Vector2 in approaches.get(other[0], PackedVector2Array()):
				way.append(Vector2(wrapf(p.x - at.x, -180.0, 180.0) * 60.0 * squash, (p.y - at.y) * 60.0))
			if way.size() >= 2:
				ways.append(way)
		var spots := {
			all = _spots(at, bearing, swing_nm, swing_nm + MARGIN_NM, funnel_nm, others, keep_off_nm, ways),
			small = _spots(at, bearing, small_swing_nm, small_swing_nm + MARGIN_NM, funnel_nm, others, keep_off_nm, ways),
		}
		for pool: String in spots:
			spots[pool] = (spots[pool] as Array).filter(func(spot: Array) -> bool:
				for box: Array in EXCLUDE_BOXES:
					if float(spot[0]) >= float(box[0]) and float(spot[0]) <= float(box[2]) and float(spot[1]) >= float(box[1]) and float(spot[1]) <= float(box[3]):
						return false
				return true)
		out[port.id] = spots
		if spots.all.size() < 8 or spots.small.size() < 12:
			short.append("%s (%d, %d)" % [port.id, spots.all.size(), spots.small.size()])
		# How many of the old anchor points lay in the funnel (for the record).
		var was := 0
		for spot: Array in (old.get("ports", {}) as Dictionary).get(port.id, {}).get("all", []):
			if _in_funnel(at, bearing, Vector2(float(spot[0]), float(spot[1])), funnel_nm):
				was += 1
		if was > 0:
			in_funnel += was
			worst.append([was, port.id])
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		_comment = "Anchor points (lon, lat) round each port, nearest first (the sides before straight out in front) and none in the funnel in front of the harbour mouth: built by tools/build_anchorages.gd. all: each clear of land as far as the longest ship can swing about it (%.1f nm), and that far and a little more from the others; small: the same for ships up to small_length dock units long (%.1f nm)." % [swing_nm, small_swing_nm],
		small_length = SMALL_LENGTH,
		ports = out,
	}, "\t", false))
	file.close()
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("Old anchor points in the funnel in front of a mouth: %d, most at %s" % [in_funnel, ", ".join(worst.slice(0, 12).map(func(w: Array) -> String: return "%s (%d)" % [w[1], w[0]]))])
	print("Ports with under 8 anchor points for the longest ships or 12 for the rest: %s" % (", ".join(short) if not short.is_empty() else "none"))
	print("Done in %d s" % ((Time.get_ticks_msec() - started) / 1000))
	get_tree().quit()


## A port's anchor points: a hexagonal grid (spacing_nm apart, lined up with
## the way to sea) out to SEARCH_NM, keeping those whose swing circle is all
## water and that aren't in the funnel in front of the mouth, nearest the
## port first (a spot out in front counting further: see FRONT_PENALTY).
func _spots(at: Vector2, bearing: float, swing_nm: float, spacing_nm: float, funnel_nm: float, others: Array, keep_off_nm: float, ways: Array) -> Array:
	var sea_way := Vector2.ZERO
	var turn := 0.0
	if not is_nan(bearing):
		turn = deg_to_rad(90.0 - bearing)  # Compass bearing to an east-north angle.
		sea_way = Vector2.from_angle(turn)
	var found := []
	var rings := ceili(SEARCH_NM / spacing_nm)
	var row_step := spacing_nm * sqrt(3.0) / 2.0
	for row in range(-rings, rings + 1):
		for col in range(-rings, rings + 1):
			var local := Vector2((col + (row % 2) * 0.5) * spacing_nm, row * row_step).rotated(turn)
			var distance := local.length()
			if distance > SEARCH_NM or distance < spacing_nm * 0.5:
				continue
			if _local_in_funnel(local, sea_way, funnel_nm) or (sea_way != Vector2.ZERO and absf(rad_to_deg(local.angle_to(sea_way))) > BEHIND_DEG):
				continue
			if _near_another(local, others, keep_off_nm) or _on_a_way(local, ways, swing_nm + MARGIN_NM):
				continue
			var point := _offset(at, local)
			if _clear(point, swing_nm):
				var along := local.dot(sea_way) / maxf(distance, 0.001) if sea_way != Vector2.ZERO else 0.0
				found.append([distance * (1.0 + FRONT_PENALTY * maxf(along, 0.0) + BACK_PENALTY * maxf(-along, 0.0)), point])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var spots := []
	for item: Array in found.slice(0, KEEP):
		var point: Vector2 = item[1]
		spots.append([snappedf(point.x, 0.0001), snappedf(point.y, 0.0001)])
	return spots


## True if a point (east and north nm of a port) lies in the funnel in front
## of its mouth: within FUNNEL_DEG of the way to sea, out to funnel_nm.
static func _local_in_funnel(local: Vector2, sea_way: Vector2, funnel_nm: float) -> bool:
	if sea_way == Vector2.ZERO or local.length() > funnel_nm:
		return false
	return absf(rad_to_deg(local.angle_to(sea_way))) <= FUNNEL_DEG


## True if a point (east and north nm of a port) is within keep_off_nm of
## another port, or in the funnel in front of its mouth (`others`: [(east,
## north) of the other, its way to sea, its funnel nm]).
static func _near_another(local: Vector2, others: Array, keep_off_nm: float) -> bool:
	for other: Array in others:
		var off: Vector2 = local - (other[0] as Vector2)
		if off.length() < keep_off_nm or _local_in_funnel(off, other[1], float(other[2])):
			return true
	return false


## True if a point (east and north nm of a port) is within `room` nm of any
## of the ports' approaches (`ways`: each as such points).
static func _on_a_way(local: Vector2, ways: Array, room: float) -> bool:
	for way: PackedVector2Array in ways:
		for k in range(1, way.size()):
			if local.distance_to(Geometry2D.get_closest_point_to_segment(local, way[k - 1], way[k])) < room:
				return true
	return false


## The same for a (lon, lat) point round a port facing a compass bearing.
static func _in_funnel(at: Vector2, bearing: float, point: Vector2, funnel_nm: float) -> bool:
	if is_nan(bearing):
		return false
	var local := Vector2(wrapf(point.x - at.x, -180.0, 180.0) * 60.0 * maxf(cos(deg_to_rad(at.y)), 0.05), (point.y - at.y) * 60.0)
	return _local_in_funnel(local, Vector2.from_angle(deg_to_rad(90.0 - bearing)), funnel_nm)


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
