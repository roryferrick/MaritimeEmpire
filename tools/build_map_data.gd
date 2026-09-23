extends SceneTree
## Builds the game's map data from Natural Earth downloads:
##   data/world_map.res   land, coastline, borders and country labels, for drawing
##   data/sea_lanes.json  a sea route and its distance between every pair of ports
##
## Rerun after changing data/ports.json:
##   Godot --headless --path . -s tools/build_map_data.gd
##
## Source files (public domain, https://www.naturalearthdata.com), in tools/source_data/:
##   ne_10m_land.geojson, ne_50m_admin_0_countries.geojson
## from https://github.com/nvkelso/natural-earth-vector/tree/master/geojson

const LAND_PATH := "res://tools/source_data/ne_10m_land.geojson"
const COUNTRIES_PATH := "res://tools/source_data/ne_50m_admin_0_countries.geojson"
const PORTS_PATH := "res://data/ports.json"
const MAP_OUT := "res://data/world_map.res"
const LANES_OUT := "res://data/sea_lanes.json"

## Coastline simplification, in projected degrees (~0.7 nm at the equator).
const SIMPLIFY_TOLERANCE := 0.012
## Land is cut into tiles this size before triangulating, to keep polygons small.
const TILE_SIZE := 5.0

## Pathfinding grid in projected coordinates. Covers the Mediterranean and the
## North Atlantic out to the US East Coast.
const GRID_WEST := -84.0
const GRID_EAST := 40.0
const GRID_SOUTH_LAT := 15.0
const GRID_NORTH_LAT := 50.0
const GRID_CELL := 0.05
## Extra cost for sailing right next to the coast, so lanes keep off the beach.
const COAST_PENALTY := 1.5
## Great-circle legs are split into pieces about this long (nm) where open water allows.
const GREAT_CIRCLE_STEP_NM := 60.0
## Straits too narrow for the grid to see. Carved as water.
const CHANNELS := [
	# Dardanelles (Aegean to the Sea of Marmara, for Istanbul).
	[[26.15, 40.00], [26.27, 40.07], [26.40, 40.15], [26.45, 40.22], [26.55, 40.30], [26.68, 40.41], [26.80, 40.48]],
	# Strait of Messina.
	[[15.68, 38.31], [15.66, 38.25], [15.62, 38.18], [15.60, 38.10], [15.57, 38.00]],
	# The Narrows, New York (Upper Bay to Lower Bay).
	[[-74.05, 40.66], [-74.045, 40.63], [-74.04, 40.605], [-74.03, 40.58], [-74.00, 40.53]],
]

var _cols := 0
var _rows := 0
var _grid_origin := Vector2.ZERO  # Projected coords of cell (0, 0)'s corner.
var _land := PackedByteArray()  # 1 = land
var _near_land := PackedByteArray()  # 1 = land or next to land


func _init() -> void:
	var started := Time.get_ticks_msec()
	var land_rings := _read_land_rings()
	print("Land: %d rings" % land_rings.size())
	_build_map(land_rings)
	_build_grid(land_rings)
	_build_lanes()
	print("Done in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit()


# --- Source data ---------------------------------------------------------

func _read_geojson(path: String) -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(typeof(data) == TYPE_DICTIONARY, "Can't read %s" % path)
	return data.features


## Each feature's polygons as arrays of rings; ring 0 is the outline, the rest are holes.
func _feature_polygons(feature: Dictionary) -> Array:
	var geometry: Dictionary = feature.geometry
	if geometry.type == "Polygon":
		return [geometry.coordinates]
	return geometry.coordinates


## Land polygons as {outline, holes} in lon/lat.
func _read_land_rings() -> Array:
	var polygons := []
	for feature: Dictionary in _read_geojson(LAND_PATH):
		if feature.properties.get("featurecla", "") != "Land":
			continue
		for polygon: Array in _feature_polygons(feature):
			var holes := []
			for i in range(1, polygon.size()):
				holes.append(_to_points(polygon[i]))
			polygons.append({"outline": _to_points(polygon[0]), "holes": holes})
	return polygons


func _to_points(ring: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for coord: Array in ring:
		points.append(Vector2(coord[0], coord[1]))
	if points.size() > 1 and points[0] == points[-1]:
		points.remove_at(points.size() - 1)
	return points


func _project_all(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = Geo.project(points[i])
	return out


# --- Map art -------------------------------------------------------------

func _build_map(land_polygons: Array) -> void:
	var map := WorldMapData.new()
	for polygon: Dictionary in land_polygons:
		var outline := _simplify(_project_all(polygon.outline))
		if outline.size() < 3:
			continue
		_add_coast(map, outline)
		_triangulate_tiled(outline, map.land_triangles, map.water_triangles)
		for hole: PackedVector2Array in polygon.holes:
			var hole_points := _simplify(_project_all(hole))
			if hole_points.size() >= 3:
				_add_coast(map, hole_points)
				_triangulate_tiled(hole_points, map.water_triangles, map.land_triangles)
	print("Map: %d land triangles, %d coast segments" % [map.land_triangles.size() / 3, map.coast_segments.size() / 2])

	_add_countries(map)
	var err := ResourceSaver.save(map, MAP_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % MAP_OUT)


## Douglas-Peucker simplification of a closed ring.
func _simplify(points: PackedVector2Array) -> PackedVector2Array:
	var n := points.size()
	if n < 4:
		return points
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack := [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var a := points[span.x]
		var b := points[span.y]
		var worst := -1
		var worst_dist := SIMPLIFY_TOLERANCE
		for i in range(span.x + 1, span.y):
			var d := Geometry2D.get_closest_point_to_segment(points[i], a, b).distance_to(points[i])
			if d > worst_dist:
				worst_dist = d
				worst = i
		if worst >= 0:
			keep[worst] = 1
			stack.append(Vector2i(span.x, worst))
			stack.append(Vector2i(worst, span.y))
	var out := PackedVector2Array()
	for i in n:
		if keep[i]:
			out.append(points[i])
	return out


## Coastline segments, skipping the artificial edges Natural Earth adds along
## the antimeridian and the bottom of Antarctica.
func _add_coast(map: WorldMapData, ring: PackedVector2Array) -> void:
	var bottom := Geo.project(Vector2(0, -Geo.MAX_LAT)).y + 0.01
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if absf(a.x) > 179.99 and absf(b.x) > 179.99:
			continue
		if a.y < bottom and b.y < bottom:
			continue
		map.coast_segments.append(a)
		map.coast_segments.append(b)


## Cuts a polygon into tiles and triangulates each piece. Pieces that come out
## as holes (from self-intersections after simplifying) go to hole_out.
func _triangulate_tiled(polygon: PackedVector2Array, out: PackedVector2Array, hole_out: PackedVector2Array) -> void:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	var x0 := floorf(bounds.position.x / TILE_SIZE) * TILE_SIZE
	var y0 := floorf(bounds.position.y / TILE_SIZE) * TILE_SIZE
	var x := x0
	while x < bounds.end.x:
		var y := y0
		while y < bounds.end.y:
			var tile := PackedVector2Array([Vector2(x, y), Vector2(x + TILE_SIZE, y),
					Vector2(x + TILE_SIZE, y + TILE_SIZE), Vector2(x, y + TILE_SIZE)])
			var pieces := Geometry2D.intersect_polygons(polygon, tile)
			var outer_clockwise := _largest_is_clockwise(pieces)
			for piece: PackedVector2Array in pieces:
				var target := out if Geometry2D.is_polygon_clockwise(piece) == outer_clockwise else hole_out
				_triangulate(piece, target)
			y += TILE_SIZE
		x += TILE_SIZE


func _largest_is_clockwise(pieces: Array) -> bool:
	var best := 0.0
	var clockwise := false
	for piece: PackedVector2Array in pieces:
		var area := absf(_signed_area(piece))
		if area > best:
			best = area
			clockwise = Geometry2D.is_polygon_clockwise(piece)
	return clockwise


func _signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in points.size():
		area += points[i].cross(points[(i + 1) % points.size()])
	return area / 2.0


func _triangulate(piece: PackedVector2Array, out: PackedVector2Array) -> void:
	var indices := Geometry2D.triangulate_polygon(piece)
	if indices.is_empty():
		# Ear clipping fails on some degenerate pieces; fall back to Delaunay,
		# keeping the triangles whose centers are inside the piece.
		var all := Geometry2D.triangulate_delaunay(piece)
		for i in range(0, all.size(), 3):
			var center := (piece[all[i]] + piece[all[i + 1]] + piece[all[i + 2]]) / 3.0
			if Geometry2D.is_point_in_polygon(center, piece):
				indices.append_array([all[i], all[i + 1], all[i + 2]])
	for i in indices:
		out.append(piece[i])


## Borders are the country outline edges shared by two countries; edges only
## one country has are coastline, which the land data already draws.
func _add_countries(map: WorldMapData) -> void:
	var edge_counts := {}
	for feature: Dictionary in _read_geojson(COUNTRIES_PATH):
		var props: Dictionary = feature.properties
		map.label_names.append(props.get("NAME", ""))
		map.label_positions.append(Geo.project(Vector2(props.get("LABEL_X", 0.0), props.get("LABEL_Y", 0.0))))
		map.label_min_zoom.append(float(props.get("MIN_LABEL", 10.0)))
		for polygon: Array in _feature_polygons(feature):
			for ring: Array in polygon:
				var points := _to_points(ring)
				for i in points.size():
					var key := _edge_key(points[i], points[(i + 1) % points.size()])
					edge_counts[key] = edge_counts.get(key, 0) + 1
	for key: Array in edge_counts:
		if edge_counts[key] >= 2:
			map.border_segments.append(Geo.project(key[0]))
			map.border_segments.append(Geo.project(key[1]))
	print("Countries: %d labels, %d border segments" % [map.label_names.size(), map.border_segments.size() / 2])


func _edge_key(a: Vector2, b: Vector2) -> Array:
	a = a.snappedf(0.0001)
	b = b.snappedf(0.0001)
	return [a, b] if (a.x < b.x or (a.x == b.x and a.y < b.y)) else [b, a]


# --- Pathfinding grid ----------------------------------------------------

func _build_grid(land_polygons: Array) -> void:
	var south := Geo.project(Vector2(0, GRID_SOUTH_LAT)).y
	var north := Geo.project(Vector2(0, GRID_NORTH_LAT)).y
	_grid_origin = Vector2(GRID_WEST, south)
	_cols = ceili((GRID_EAST - GRID_WEST) / GRID_CELL)
	_rows = ceili((north - south) / GRID_CELL)
	_land.resize(_cols * _rows)

	# Scanline-fill every land polygon (outline and holes, even-odd) into the grid.
	for polygon: Dictionary in land_polygons:
		var rings := [_project_all(polygon.outline)]
		for hole: PackedVector2Array in polygon.holes:
			rings.append(_project_all(hole))
		_fill_rings(rings)

	for channel: Array in CHANNELS:
		for i in range(1, channel.size()):
			_carve(Geo.project(Vector2(channel[i - 1][0], channel[i - 1][1])),
					Geo.project(Vector2(channel[i][0], channel[i][1])))

	_near_land.resize(_land.size())
	for row in _rows:
		for col in _cols:
			if _land[row * _cols + col]:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var c := col + dx
						var r := row + dy
						if c >= 0 and c < _cols and r >= 0 and r < _rows:
							_near_land[r * _cols + c] = 1
	print("Grid: %d x %d cells" % [_cols, _rows])


func _fill_rings(rings: Array) -> void:
	var crossings := {}  # row -> x positions where an edge crosses the row's center line
	for ring: PackedVector2Array in rings:
		for i in ring.size():
			var a := (ring[i] - _grid_origin) / GRID_CELL
			var b := (ring[(i + 1) % ring.size()] - _grid_origin) / GRID_CELL
			if a.y == b.y:
				continue
			var lo := minf(a.y, b.y)
			var hi := maxf(a.y, b.y)
			var first_row := maxi(0, ceili(lo - 0.5))
			var last_row := mini(_rows - 1, ceili(hi - 0.5) - 1)
			for row in range(first_row, last_row + 1):
				var cy := row + 0.5
				var t := (cy - a.y) / (b.y - a.y)
				if not crossings.has(row):
					crossings[row] = PackedFloat32Array()
				crossings[row].append(a.x + t * (b.x - a.x))
	for row: int in crossings:
		var xs: PackedFloat32Array = crossings[row]
		xs.sort()
		for i in range(0, xs.size() - 1, 2):
			var c0 := maxi(0, ceili(xs[i] - 0.5))
			var c1 := mini(_cols - 1, ceili(xs[i + 1] - 0.5) - 1)
			for col in range(c0, c1 + 1):
				_land[row * _cols + col] ^= 1


func _carve(a: Vector2, b: Vector2) -> void:
	var steps := ceili(a.distance_to(b) / (GRID_CELL * 0.25))
	for s in steps + 1:
		var cell := _cell_of(a.lerp(b, float(s) / steps))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := cell + Vector2i(dx, dy)
				if _in_grid(c):
					_land[c.y * _cols + c.x] = 0


func _cell_of(point: Vector2) -> Vector2i:
	var p := (point - _grid_origin) / GRID_CELL
	return Vector2i(floori(p.x), floori(p.y))


func _cell_center(cell: Vector2i) -> Vector2:
	return _grid_origin + (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_CELL


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _cols and cell.y >= 0 and cell.y < _rows


func _is_land(cell: Vector2i) -> bool:
	return not _in_grid(cell) or _land[cell.y * _cols + cell.x] == 1


func _is_near_land(cell: Vector2i) -> bool:
	return not _in_grid(cell) or _near_land[cell.y * _cols + cell.x] == 1


# --- Sea lanes -----------------------------------------------------------

func _build_lanes() -> void:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, _cols, _rows)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()
	# On a Mercator grid, one cell spans cos(latitude) as much real distance at
	# every latitude. Weights are normalized to >= 1 so the heuristic stays admissible.
	var min_scale := cos(deg_to_rad(GRID_NORTH_LAT))
	for row in _rows:
		var lat := Geo.unproject(_cell_center(Vector2i(0, row))).y
		var weight := cos(deg_to_rad(lat)) / min_scale
		for col in _cols:
			var cell := Vector2i(col, row)
			if _land[row * _cols + col]:
				astar.set_point_solid(cell)
			else:
				astar.set_point_weight_scale(cell, weight * (COAST_PENALTY if _near_land[row * _cols + col] else 1.0))

	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string(PORTS_PATH)).ports
	var water_cells := {}
	for port: Dictionary in ports:
		water_cells[port.id] = _nearest_water(_cell_of(Geo.project(Vector2(port.lon, port.lat))))

	var lanes := {}
	var stats := {}
	for i in ports.size():
		for j in range(i + 1, ports.size()):
			# Keys and point order run from the alphabetically first port id.
			var a: Dictionary = ports[i] if ports[i].id < ports[j].id else ports[j]
			var b: Dictionary = ports[j] if a == ports[i] else ports[i]
			var cells := astar.get_id_path(water_cells[a.id], water_cells[b.id])
			if cells.is_empty():
				push_error("No sea route from %s to %s" % [a.id, b.id])
				continue
			var points := _lane_points(Vector2(a.lon, a.lat), cells, Vector2(b.lon, b.lat))
			var distance := 0.0
			for k in range(1, points.size()):
				distance += Geo.distance_nm(points[k - 1], points[k])
			var coords := []
			for p in points:
				coords.append([snappedf(p.x, 0.0001), snappedf(p.y, 0.0001)])
			var key := "%s-%s" % [a.id, b.id]
			lanes[key] = {"distance_nm": snappedf(distance, 0.1), "points": coords}
			stats[key] = distance

	var file := FileAccess.open(LANES_OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"_comment": "Generated by tools/build_map_data.gd. Sea route between each pair of ports, as [lon, lat] points from the first port to the second.",
		"lanes": lanes,
	}, "\t"))
	file.close()
	print("Lanes: %d" % lanes.size())
	_print_stats(ports, stats)


func _nearest_water(cell: Vector2i) -> Vector2i:
	for radius in 60:
		var best := Vector2i(-1, -1)
		var best_dist := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := cell + Vector2i(dx, dy)
				if _in_grid(c) and not _is_land(c) and Vector2(dx, dy).length() < best_dist:
					best_dist = Vector2(dx, dy).length()
					best = c
		if best.x >= 0:
			return best
	push_error("No water near cell %s" % cell)
	return cell


## Turns a grid path into a short list of (lon, lat) points: straightens it
## wherever there's clear water, then follows great circles on long open legs.
func _lane_points(start: Vector2, cells: Array[Vector2i], end: Vector2) -> PackedVector2Array:
	# From each kept cell, jump to the farthest later cell with a clear line:
	# double the jump while clear, then binary-search the edge.
	var kept: Array[Vector2i] = [cells[0]]
	var last := cells.size() - 1
	var i := 0
	while i < last:
		var good := i + 1
		var step := 1
		while good < last and _clear_line(cells[i], cells[mini(good + step, last)]):
			good = mini(good + step, last)
			step *= 2
		var bad := mini(good + step, last + 1)
		while bad - good > 1:
			var mid := (good + bad) / 2
			if _clear_line(cells[i], cells[mid]):
				good = mid
			else:
				bad = mid
		kept.append(cells[good])
		i = good

	var points := PackedVector2Array([start])
	for cell in kept:
		points.append(Geo.unproject(_cell_center(cell)))
	points.append(end)

	var out := PackedVector2Array([points[0]])
	for k in range(1, points.size()):
		var a := points[k - 1]
		var b := points[k]
		var pieces := floori(Geo.distance_nm(a, b) / GREAT_CIRCLE_STEP_NM)
		var arc := PackedVector2Array()
		var arc_ok := pieces >= 2
		for s in range(1, pieces):
			var p := Geo.great_circle_lerp(a, b, float(s) / pieces)
			if _is_near_land(_cell_of(Geo.project(p))):
				arc_ok = false
				break
			arc.append(p)
		if arc_ok:
			out.append_array(arc)
		out.append(b)
	return out


## True if the straight (projected) line between two cells stays off the
## coast, apart from right next to either end.
func _clear_line(a: Vector2i, b: Vector2i) -> bool:
	var pa := Vector2(a) + Vector2(0.5, 0.5)
	var pb := Vector2(b) + Vector2(0.5, 0.5)
	var steps := ceili(pa.distance_to(pb) * 2.0)
	for s in range(1, steps):
		var p := pa.lerp(pb, float(s) / steps)
		var cell := Vector2i(floori(p.x), floori(p.y))
		var near_end := p.distance_to(pa) < 2.5 or p.distance_to(pb) < 2.5
		if _is_land(cell) or (_is_near_land(cell) and not near_end):
			return false
	return true


func _print_stats(ports: Array, stats: Dictionary) -> void:
	print("Rome-Tunis: %.1f nm" % stats.get("ROM-TUN", stats.get("TUN-ROM", -1.0)))
	var us := ["BOS", "NYC", "MIA"]
	var longest := 0.0
	var longest_key := ""
	for key: String in stats:
		var ids := key.split("-")
		if (ids[0] in us) != (ids[1] in us) and stats[key] > longest:
			longest = stats[key]
			longest_key = key
	print("Longest Med-US leg: %s %.1f nm" % [longest_key, longest])
	for key: String in ["ALG-TNG", "ALG-NYC", "GIT-MLA", "IST-PIR", "MIA-PSD", "NYC-TNG", "BCN-VLC", "GOA-ROM"]:
		print("  %s: %.1f nm" % [key, stats.get(key, -1.0)])
