extends SceneTree
## Builds the game's map data from Natural Earth downloads:
##   data/world_map.res  land, coastline, borders and country labels, for drawing
##   data/sea_lanes.res  a sea route and its distance between every pair of ports
##
## Rerun after changing data/ports.json (takes several minutes; add
## "-- --lanes-only" to skip rebuilding the map art):
##   Godot --headless --path . -s tools/build_map_data.gd
##
## Source files (public domain, https://www.naturalearthdata.com), in tools/source_data/:
##   ne_10m_land.geojson, ne_50m_admin_0_countries.geojson
## from https://github.com/nvkelso/natural-earth-vector/tree/master/geojson

const LAND_PATH := "res://tools/source_data/ne_10m_land.geojson"
const COUNTRIES_PATH := "res://tools/source_data/ne_50m_admin_0_countries.geojson"
const PORTS_PATH := "res://data/ports.json"
const MAP_OUT := "res://data/world_map.res"
const LANES_OUT := "res://data/sea_lanes.res"

## Coastline simplification, in projected degrees (~0.7 nm at the equator).
const SIMPLIFY_TOLERANCE := 0.012
## Land is cut into tiles this size before triangulating, to keep polygons small.
const TILE_SIZE := 5.0

## Pathfinding grid in projected coordinates. It runs past 180 degrees east so
## routes across the Pacific have no seam: the Americas appear twice, once at
## their real longitude and once 360 degrees further east.
const GRID_WEST := -180.0
const GRID_EAST := 320.0
const GRID_SOUTH_LAT := -58.0
const GRID_NORTH_LAT := 66.0
const GRID_CELL := 0.1
## Routes whose ends are further apart than this (in longitude) are not tried
## with that pairing of the two copies of the Americas.
const MAX_ROUTE_SPAN := 270.0
## Ports closer than this in longitude are only routed at their real
## longitudes; further apart, the way across the Pacific is tried too.
const MIN_WRAP_SPAN := 150.0
## Coarse search grid: this many fine cells per side.
const COARSE := 5
## Extra cost for coarse cells that touch land, so lanes keep off the coast.
const COAST_PENALTY := 1.3
## How far (in cells) a port may be from the water cell its lanes start from.
const SNAP_RADIUS := 30
## Great-circle legs are split into pieces about this long (nm) where open water allows.
const GREAT_CIRCLE_STEP_NM := 100.0
## Canals, rivers and straits too narrow for the grid to see. Carved as water.
## Each is a list of [lon, lat] points.
const CHANNELS := {
	"Strait of Gibraltar": [[-6.2, 35.95], [-5.6, 35.97], [-5.2, 36.0]],
	"Dardanelles": [[26.15, 40.00], [26.27, 40.07], [26.40, 40.15], [26.45, 40.22], [26.55, 40.30], [26.68, 40.41], [26.80, 40.48]],
	"Strait of Messina": [[15.68, 38.31], [15.66, 38.25], [15.62, 38.18], [15.60, 38.10], [15.57, 38.00]],
	"Strait of Bonifacio": [[9.0, 41.33], [9.25, 41.32], [9.5, 41.30]],
	"Suez Canal": [[32.31, 31.30], [32.32, 31.00], [32.33, 30.70], [32.35, 30.45], [32.42, 30.20], [32.57, 29.95], [32.57, 29.80]],
	"Panama Canal": [[-79.92, 9.40], [-79.90, 9.30], [-79.85, 9.20], [-79.75, 9.12], [-79.68, 9.05], [-79.62, 9.00], [-79.55, 8.90], [-79.52, 8.80]],
	"Singapore Strait": [[103.5, 1.20], [103.8, 1.20], [104.1, 1.25], [104.4, 1.30]],
	"Great Belt": [[11.0, 56.10], [10.95, 55.70], [11.0, 55.35], [11.05, 55.05], [11.2, 54.70], [11.5, 54.55]],
	"Elbe (Hamburg)": [[8.3, 53.95], [8.7, 53.88], [9.0, 53.85], [9.35, 53.72], [9.55, 53.60], [9.8, 53.54], [9.95, 53.54]],
	"Western Scheldt (Antwerp)": [[3.3, 51.45], [3.6, 51.42], [3.9, 51.40], [4.1, 51.38], [4.25, 51.33], [4.33, 51.28]],
	"The Narrows (New York)": [[-74.05, 40.66], [-74.045, 40.63], [-74.04, 40.605], [-74.03, 40.58], [-74.00, 40.53]],
	"Savannah River": [[-80.80, 32.02], [-80.95, 32.05], [-81.10, 32.08]],
	"Galveston Bay (Houston)": [[-94.65, 29.30], [-94.75, 29.36], [-94.85, 29.45], [-94.95, 29.55], [-94.98, 29.60]],
	"Golden Gate (Oakland)": [[-122.65, 37.78], [-122.50, 37.81], [-122.40, 37.81], [-122.32, 37.80]],
	"Admiralty Inlet (Seattle)": [[-122.75, 48.20], [-122.65, 48.05], [-122.50, 47.85], [-122.40, 47.65], [-122.35, 47.60]],
	"Port Phillip Heads (Melbourne)": [[144.60, -38.32], [144.64, -38.28], [144.75, -38.15], [144.90, -37.90]],
	"Santos channel": [[-46.30, -24.05], [-46.30, -23.98]],
	"Paranagua Bay": [[-48.30, -25.57], [-48.40, -25.52], [-48.52, -25.50]],
	"Lagos harbor": [[3.40, 6.35], [3.39, 6.44]],
	"Vridi Canal (Abidjan)": [[-4.02, 5.20], [-4.00, 5.25]],
	"Kilindini (Mombasa)": [[39.70, -4.10], [39.67, -4.05]],
	"Durban harbor": [[31.10, -29.88], [31.03, -29.87]],
}

var _cols := 0
var _rows := 0
var _grid_origin := Vector2.ZERO  # Projected coords of cell (0, 0)'s corner.
var _land := PackedByteArray()  # 1 = land
var _near_land := PackedByteArray()  # 1 = land or next to land
## 1 = water connected to the open ocean. Ports snap to these cells, so every
## pair of ports has a route (and no search is wasted on an enclosed pocket).
var _ocean := PackedByteArray()
var _coarse_cols := 0
## For each coarse cell, the index of the fine ocean cell a route passes through (-1 if none).
var _coarse_rep := PackedInt32Array()


func _init() -> void:
	var started := Time.get_ticks_msec()
	var land_rings := _read_land_rings()
	print("Land: %d rings" % land_rings.size())
	if not "--lanes-only" in OS.get_cmdline_user_args():
		_build_map(land_rings)
	_build_grid(land_rings)
	land_rings.clear()
	_build_lanes()
	print("Done in %.1f min" % ((Time.get_ticks_msec() - started) / 60000.0))
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

	# Scanline-fill every land polygon (outline and holes, even-odd) into the
	# grid, plus a second copy 360 degrees east for the part past 180.
	for polygon: Dictionary in land_polygons:
		var rings := [_project_all(polygon.outline)]
		for hole: PackedVector2Array in polygon.holes:
			rings.append(_project_all(hole))
		_fill_rings(rings, 0.0)
		_fill_rings(rings, Geo.WORLD_WIDTH)

	for channel_name: String in CHANNELS:
		var channel: Array = CHANNELS[channel_name]
		for i in range(1, channel.size()):
			var a := Geo.project(Vector2(channel[i - 1][0], channel[i - 1][1]))
			var b := Geo.project(Vector2(channel[i][0], channel[i][1]))
			_carve(a, b)
			_carve(a + Vector2(Geo.WORLD_WIDTH, 0), b + Vector2(Geo.WORLD_WIDTH, 0))

	_near_land = _land.duplicate()
	for row in _rows:
		var base := row * _cols
		for col in _cols:
			if not _land[base + col]:
				continue
			for dy in range(-1, 2):
				var r := row + dy
				if r < 0 or r >= _rows:
					continue
				var rbase := r * _cols
				for dx in range(-1, 2):
					var c := col + dx
					if c >= 0 and c < _cols:
						_near_land[rbase + c] = 1
	_mark_ocean()
	print("Grid: %d x %d cells" % [_cols, _rows])


## Flood-fills the water reachable from the middle of the Pacific. Moves are
## 4-way, matching the pathfinder (it only cuts corners when both sides are water).
func _mark_ocean() -> void:
	_ocean.resize(_land.size())
	var start := _cell_of(Geo.project(Vector2(-150.0, 0.0)))
	var queue := PackedInt32Array([start.y * _cols + start.x])
	_ocean[queue[0]] = 1
	var total := _land.size()
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var col := index % _cols
		if col > 0 and not _land[index - 1] and not _ocean[index - 1]:
			_ocean[index - 1] = 1
			queue.append(index - 1)
		if col < _cols - 1 and not _land[index + 1] and not _ocean[index + 1]:
			_ocean[index + 1] = 1
			queue.append(index + 1)
		if index >= _cols and not _land[index - _cols] and not _ocean[index - _cols]:
			_ocean[index - _cols] = 1
			queue.append(index - _cols)
		if index + _cols < total and not _land[index + _cols] and not _ocean[index + _cols]:
			_ocean[index + _cols] = 1
			queue.append(index + _cols)
	print("Ocean: %d connected water cells" % queue.size())


func _fill_rings(rings: Array, x_offset: float) -> void:
	var crossings := {}  # row -> x positions where an edge crosses the row's center line
	var origin := _grid_origin - Vector2(x_offset, 0)
	for ring: PackedVector2Array in rings:
		for i in ring.size():
			var a := (ring[i] - origin) / GRID_CELL
			var b := (ring[(i + 1) % ring.size()] - origin) / GRID_CELL
			if a.y == b.y:
				continue
			var lo := minf(a.y, b.y)
			var hi := maxf(a.y, b.y)
			var first_row := maxi(0, ceili(lo - 0.5))
			var last_row := mini(_rows - 1, ceili(hi - 0.5) - 1)
			for row in range(first_row, last_row + 1):
				var t := (row + 0.5 - a.y) / (b.y - a.y)
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
	var steps := maxi(1, ceili(a.distance_to(b) / (GRID_CELL * 0.25)))
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


## Like _is_near_land for a (lon, lat) point, trying both copies of the Americas.
func _lon_lat_near_land(lon_lat: Vector2) -> bool:
	var p := Geo.project(Vector2(wrapf(lon_lat.x, -180.0, 180.0), lon_lat.y))
	if not _is_near_land(_cell_of(p)):
		return false
	var east := _cell_of(p + Vector2(Geo.WORLD_WIDTH, 0))
	return not _in_grid(east) or _is_near_land(east)


# --- Sea lanes -----------------------------------------------------------

func _build_lanes() -> void:
	# Routes are found on a coarse grid (fast, and weighted so they follow real
	# distances and keep off the coast), then fitted to the fine grid; the fine
	# grid is only searched for short hops the coarse route can't see across.
	var coarse := _build_coarse_grid()
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, _cols, _rows)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.jumping_enabled = true
	astar.update()
	for row in _rows:
		var col := 0
		while col < _cols:
			if not _land[row * _cols + col]:
				col += 1
				continue
			var run_start := col
			while col < _cols and _land[row * _cols + col]:
				col += 1
			astar.fill_solid_region(Rect2i(run_start, row, col - run_start, 1))
	print("Pathfinding grid ready")

	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string(PORTS_PATH)).ports
	ports.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	# Each port's starting water cell, at its real longitude and (if it fits in
	# the grid) 360 degrees east: [[lon offset, cell], ...]
	var starts := {}
	for port: Dictionary in ports:
		var options := []
		for offset in [0.0, Geo.WORLD_WIDTH]:
			var p := Geo.project(Vector2(port.lon + offset, port.lat))
			if p.x < GRID_EAST - 1.0:
				var cell := _nearest_water(_cell_of(p))
				if cell.x >= 0:
					options.append([offset, cell])
					var snap := Vector2(cell - _cell_of(p)).length()
					if snap > 12 and offset == 0.0:
						print("  note: %s is %.0f cells from open water" % [port.id, snap])
		if options.is_empty():
			push_error("%s is not near any water" % port.id)
		starts[port.id] = options

	var data := SeaLaneData.new()
	var started := Time.get_ticks_msec()
	@warning_ignore("integer_division")
	var pairs := ports.size() * (ports.size() - 1) / 2
	var done := 0
	var search_usec := 0
	var shape_usec := 0
	var args := OS.get_cmdline_user_args()
	var limit := int(args[args.find("--limit") + 1]) if "--limit" in args else pairs
	for i in ports.size():
		if done >= limit:
			break
		for j in range(i + 1, ports.size()):
			if done >= limit:
				break
			var a: Dictionary = ports[i]
			var b: Dictionary = ports[j]
			var best := PackedVector2Array()
			var best_distance := INF
			var span: float = absf(a.lon - b.lon)
			for option_a: Array in starts[a.id]:
				for option_b: Array in starts[b.id]:
					if option_a[0] > 0.0 and option_b[0] > 0.0:
						continue  # Same as both at their real longitude.
					var shifted: bool = option_a[0] > 0.0 or option_b[0] > 0.0
					if shifted and span <= MIN_WRAP_SPAN:
						continue  # Close enough that the short way can't cross the Pacific seam.
					var lon_a: float = a.lon + option_a[0]
					var lon_b: float = b.lon + option_b[0]
					if absf(lon_a - lon_b) > MAX_ROUTE_SPAN:
						continue
					var t0 := Time.get_ticks_usec()
					var cells := _route(coarse, astar, option_a[1], option_b[1])
					var t1 := Time.get_ticks_usec()
					search_usec += t1 - t0
					if cells.is_empty():
						continue
					var points := _lane_points(Vector2(lon_a, a.lat), cells, Vector2(lon_b, b.lat))
					shape_usec += Time.get_ticks_usec() - t1
					var distance := _length_nm(points)
					if distance < best_distance:
						best_distance = distance
						best = points
			if best.is_empty():
				push_error("No sea route from %s to %s" % [a.id, b.id])
			else:
				# Shift the lane so it starts at the first port's real longitude.
				var shift: float = a.lon - best[0].x
				data.keys.append("%s-%s" % [a.id, b.id])
				data.starts.append(data.points.size())
				for p in best:
					data.points.append(Vector2(snappedf(p.x + shift, 0.0001), snappedf(p.y, 0.0001)))
				data.distances.append(best_distance)
			done += 1
			if done % 50 == 0:
				var elapsed := (Time.get_ticks_msec() - started) / 1000.0
				print("  %d / %d lanes (%.0f s, ~%.0f s left; search %.0f s, shaping %.0f s)" % [done, pairs, elapsed, elapsed / done * (pairs - done), search_usec / 1e6, shape_usec / 1e6])
	data.starts.append(data.points.size())

	var err := ResourceSaver.save(data, LANES_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % LANES_OUT)
	print("Lanes: %d, %d points" % [data.keys.size(), data.points.size()])
	_print_stats(data)


## Coarse grid over the fine one. A coarse cell is water if any of its fine
## cells is open ocean (so narrow straits stay open), and remembers the ocean
## cell nearest its center, preferring cells off the coast.
func _build_coarse_grid() -> AStarGrid2D:
	var coarse_cols := ceili(float(_cols) / COARSE)
	var coarse_rows := ceili(float(_rows) / COARSE)
	var coarse := AStarGrid2D.new()
	coarse.region = Rect2i(0, 0, coarse_cols, coarse_rows)
	coarse.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	coarse.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	coarse.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	coarse.update()
	# On a Mercator grid a cell spans cos(latitude) as much real distance at
	# every latitude. Weights are normalized to >= 1 so the heuristic stays admissible.
	var min_scale := cos(deg_to_rad(maxf(absf(GRID_NORTH_LAT), absf(GRID_SOUTH_LAT))))
	_coarse_rep.resize(coarse_cols * coarse_rows)
	for cy in coarse_rows:
		var lat := Geo.unproject(_cell_center(Vector2i(0, mini(cy * COARSE + COARSE / 2, _rows - 1)))).y
		var weight := cos(deg_to_rad(lat)) / min_scale
		for cx in coarse_cols:
			var center := Vector2((cx + 0.5) * COARSE, (cy + 0.5) * COARSE)
			var best := -1
			var best_score := INF
			var touches_land := false
			for fy in range(cy * COARSE, mini((cy + 1) * COARSE, _rows)):
				for fx in range(cx * COARSE, mini((cx + 1) * COARSE, _cols)):
					var index := fy * _cols + fx
					if not _ocean[index]:
						touches_land = touches_land or _land[index] == 1
						continue
					var score := center.distance_to(Vector2(fx + 0.5, fy + 0.5)) + (100.0 if _near_land[index] else 0.0)
					if score < best_score:
						best_score = score
						best = index
			_coarse_rep[cy * coarse_cols + cx] = best
			if best < 0:
				coarse.set_point_solid(Vector2i(cx, cy))
			else:
				coarse.set_point_weight_scale(Vector2i(cx, cy), weight * (COAST_PENALTY if touches_land else 1.0))
	_coarse_cols = coarse_cols
	print("Coarse grid: %d x %d cells" % [coarse_cols, coarse_rows])
	return coarse


## A fine-grid path between two ocean cells: the coarse route's cells, with
## any hop that would cross land replaced by a short fine-grid search.
func _route(coarse: AStarGrid2D, fine: AStarGrid2D, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var coarse_path := coarse.get_id_path(from / COARSE, to / COARSE)
	var result: Array[Vector2i] = []
	if coarse_path.is_empty():
		return result
	var waypoints: Array[Vector2i] = [from]
	for k in range(1, coarse_path.size() - 1):
		var rep := _coarse_rep[coarse_path[k].y * _coarse_cols + coarse_path[k].x]
		waypoints.append(Vector2i(rep % _cols, rep / _cols))
	waypoints.append(to)

	result.append(from)
	for k in range(1, waypoints.size()):
		var a := waypoints[k - 1]
		var b := waypoints[k]
		if _clear_of_land(a, b):
			result.append(b)
			continue
		var hop := fine.get_id_path(a, b)
		if hop.is_empty():
			result.clear()
			return result
		for h in range(1, hop.size()):
			result.append(hop[h])
	return result


## True if the straight line between two cells crosses no land at all.
func _clear_of_land(a: Vector2i, b: Vector2i) -> bool:
	var pa := Vector2(a) + Vector2(0.5, 0.5)
	var pb := Vector2(b) + Vector2(0.5, 0.5)
	var steps := ceili(pa.distance_to(pb) * 2.0)
	for s in range(1, steps):
		var p := pa.lerp(pb, float(s) / steps)
		if _land[floori(p.y) * _cols + floori(p.x)]:
			return false
	return true


func _nearest_water(cell: Vector2i) -> Vector2i:
	for radius in SNAP_RADIUS + 1:
		var best := Vector2i(-1, -1)
		var best_dist := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := cell + Vector2i(dx, dy)
				if _in_grid(c) and _ocean[c.y * _cols + c.x] and Vector2(dx, dy).length() < best_dist:
					best_dist = Vector2(dx, dy).length()
					best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Turns a grid path into a short list of (lon, lat) points: straightens it
## wherever there's clear water, then follows great circles on long open legs.
## Longitudes stay continuous (they may run past 180).
func _lane_points(start: Vector2, cells: Array[Vector2i], end: Vector2) -> PackedVector2Array:
	# The route is a list of turning points; fill in every cell along each hop.
	var path: Array[Vector2i] = [cells[0]]
	for k in range(1, cells.size()):
		var a := Vector2(cells[k - 1])
		var delta := Vector2(cells[k] - cells[k - 1])
		var steps := maxi(absi(cells[k].x - cells[k - 1].x), absi(cells[k].y - cells[k - 1].y))
		for s in range(1, steps + 1):
			path.append(Vector2i((a + delta * (float(s) / steps)).round()))

	# Straighten: keep a span as one line if it's clear, otherwise split it in
	# half and try again. Then drop any kept cell the line can skip over.
	var marks := PackedByteArray()
	marks.resize(path.size())
	marks[0] = 1
	marks[-1] = 1
	var spans := [Vector2i(0, path.size() - 1)]
	while not spans.is_empty():
		var span: Vector2i = spans.pop_back()
		if span.y - span.x < 2 or _clear_line(path[span.x], path[span.y]):
			continue
		@warning_ignore("integer_division")
		var mid := (span.x + span.y) / 2
		marks[mid] = 1
		spans.append(Vector2i(span.x, mid))
		spans.append(Vector2i(mid, span.y))
	var candidates: Array[Vector2i] = []
	for k in path.size():
		if marks[k]:
			candidates.append(path[k])
	var kept: Array[Vector2i] = [candidates[0]]
	var i := 0
	while i < candidates.size() - 1:
		var j := i + 1
		while j + 1 < candidates.size() and _clear_line(candidates[i], candidates[j + 1]):
			j += 1
		kept.append(candidates[j])
		i = j

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
		var previous_lon := a.x
		for s in range(1, pieces):
			var p := Geo.great_circle_lerp(a, b, float(s) / pieces)
			p.x += roundf((previous_lon - p.x) / Geo.WORLD_WIDTH) * Geo.WORLD_WIDTH
			previous_lon = p.x
			if _lon_lat_near_land(p):
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


func _length_nm(points: PackedVector2Array) -> float:
	var distance := 0.0
	for k in range(1, points.size()):
		distance += Geo.distance_nm(points[k - 1], points[k])
	return distance


func _print_stats(data: SeaLaneData) -> void:
	var by_key := {}
	for i in data.keys.size():
		by_key[data.keys[i]] = data.distances[i]
	var longest := 0.0
	var longest_key := ""
	var longest_med_us := 0.0
	var med := ["ALG", "ALY", "ASH", "BCN", "BIA", "CAG", "GIT", "GOA", "HFA", "IST", "IZM", "KOP", "LMS", "MER", "MLA", "MRS", "PIR", "PMI", "PMO", "PSD", "ROM", "SPE", "TNG", "TUN", "VLC"]
	var us_east := ["BOS", "NYC", "MIA"]
	for key: String in by_key:
		var ids := key.split("-")
		if by_key[key] > longest:
			longest = by_key[key]
			longest_key = key
		if ((ids[0] in med) and (ids[1] in us_east)) or ((ids[1] in med) and (ids[0] in us_east)):
			longest_med_us = maxf(longest_med_us, by_key[key])
	print("Rome-Tunis: %.1f nm" % by_key.get("ROM-TUN", -1.0))
	print("Longest Med-US East leg: %.1f nm" % longest_med_us)
	print("Longest leg overall: %s %.1f nm" % [longest_key, longest])
	for key: String in ["ALG-TNG", "ALG-NYC", "GIT-MLA", "IST-PIR", "BCN-VLC", "RTM-SHA", "LAX-SHA", "NYC-RTM", "HAM-SIN", "ANC-SEA", "BLB-CLN", "LAX-NYC", "PMO-TUN", "BIA-GOA"]:
		print("  %s: %.1f nm" % [key, by_key.get(key, -1.0)])
