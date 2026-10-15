# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Static game data (tuning, ports, sea lanes, ship models, map art) loaded
## from res://data.
##
## Positions are projected map coordinates (see Geo); distances are real
## nautical miles along the sea lanes.

const CONFIG_PATH := "res://data/game_config.json"
const PORTS_PATH := "res://data/ports.json"
const LANES_PATH := "res://data/sea_lanes.res"
const SHIP_MODELS_PATH := "res://data/ship_models.json"
const SHIP_NAMES_PATH := "res://data/ship_names.json"
const WORLD_MAP_PATH := "res://data/world_map.res"
const CANALS_PATH := "res://data/canals.json"
const MARKETS_PATH := "res://data/markets.json"
const STARTS_PATH := "res://data/starts.json"
const TYPE_STARTS_PATH := "res://data/type_starts.json"
const WONDERS_PATH := "res://data/wonders.json"
const TRENCHES_PATH := "res://data/trenches.json"
## MapView.FeatureKind.TRENCH (the map's feature labels are written by the map tool; trenches are added at load).
const TRENCH_KIND := 7
## How close (in projected degrees) a lane must pass a lock chamber to go through it.
const CHAMBER_ON_LANE := 0.002
const _NO_LANE := 1 << 30

var config: Dictionary = {}
var ports: Array[Dictionary] = []
var ship_models: Array[Dictionary] = []
## Models not in play yet (ship_models.json coming_soon: the cruise ships), shown
## on the Shop's coming-soon tab only.
var upcoming_models: Array[Dictionary] = []
## Word lists ("first", "second") combined to suggest names for new ships.
var ship_names: Dictionary = {}
var world_map: WorldMapData
## Canals from data/canals.json (with locks, or convoys), each with its path
## projected (projected_path) and in nm from its start (path_nm), convoy
## canals' single-lane stretches (single_nm: [[start, end] nm]), and lock
## chambers in path order (chambers: {index, lock, position, path_index}).
var canals: Array[Dictionary] = []
## Commodities, regions and prices from data/markets.json.
var markets: Dictionary = {}
var commodities: Array[Dictionary] = []
## Recommended HQ ports from data/starts.json: {excellent: [{port, note}],
## great, fair, hard: [...], great_lakes: {note, ports}}.
var starts: Dictionary = {}
## The other company types' recommended HQ ports (data/type_starts.json):
## {type id: {excellent, great, fair, hard}}; Cargo & Ore's are starts'.
var type_starts: Dictionary = {}
## The wonders of the world on the map (data/wonders.json): {id, name, kind
## (natural, man_made or ancient), country, lon, lat, tier, when, fact}.
var wonders: Array[Dictionary] = []
var _wonders_by_id := {}
## The kinds of recommended start in data/starts.json, best first.
const START_KINDS := ["excellent", "great", "fair", "hard"]

var _ports_by_id: Dictionary = {}
var _port_positions: Dictionary = {}  # id -> projected Vector2
var _models_by_id: Dictionary = {}
var _lane_data: SeaLaneData
## "FROM-TO" (both directions) -> index into _lane_data; negative (-index - 1)
## when the stored lane runs the other way.
var _lane_index: Dictionary = {}
var _lane_cache: Dictionary = {}  # "FROM-TO" -> SeaLane, built on first use
var _crossing_cache: Dictionary = {}  # "FROM-TO" -> canal_crossings()
var _chambers_cache: Dictionary = {}  # "FROM-TO" -> lane_chambers()
var _zones_cache: Dictionary = {}  # "FROM-TO#way@month" -> lane_zones()
## The lanes whose zones were asked for ("FROM>TO" -> [from, to]), whose next
## month's zones warm_next_month() works out ahead, a few a frame, so the
## month's turn doesn't work them all out at once (a 200 ms hitch at 8x).
var _zones_lanes: Dictionary = {}
var _zones_warm_keys: Array = []
var _zones_warm_at := 0
## The currents' second ways round (SeaLaneData variant_*: one way, riding a
## current, in the months it's quicker): "FROM>TO" -> its index there.
var _variant_index: Dictionary = {}
## The month the routes and currents go by (0-11; 12, Currents.MEAN, the
## year's average until GameState sets it: see set_month()), and each one-way
## leg's way this month (see way_now()).
var month := Currents.MEAN
var _ways_now: Dictionary = {}
## How strongly the currents push ships (game_config currents), read once.
var _current_settings: Dictionary = {}
## Lanes, their zones and canal crossings worked out natively (LaneMath: the
## same numbers, to the last bit) when the native library's there.
var native_lanes := ClassDB.class_exists(&"LaneMath")
var _commodities_by_id: Dictionary = {}
var _port_regions: Dictionary = {}  # port id -> region
var _base_prices: Dictionary = {}  # "PORT/commodity" -> base_price()
var _world_prices: Dictionary = {}  # commodity -> world_price()


## A sailing path between two ports.
class SeaLane:
	## How far (projected degrees) either side of a turning point a ship's
	## heading eases round it (see sample()).
	const HEADING_BLEND := 0.3

	## Projected map coordinates, from the first port to the second.
	var points := PackedVector2Array()
	## Nautical miles from the start to each point.
	var miles := PackedFloat64Array()

	## Bounding box of its points (projected), worked out on first use.
	var _bounds := Rect2()
	var _has_bounds := false

	func bounds() -> Rect2:
		if not _has_bounds:
			_bounds = Rect2(points[0], Vector2.ZERO)
			for point in points:
				_bounds = _bounds.expand(point)
			_has_bounds = true
		return _bounds

	func length() -> float:
		return miles[-1]

	func reversed() -> SeaLane:
		var lane := SeaLane.new()
		var total := length()
		for i in range(points.size() - 1, -1, -1):
			lane.points.append(points[i])
			lane.miles.append(total - miles[i])
		return lane

	## Position and travel direction (both projected; the direction normalized)
	## after sailing some distance. The direction eases round each turning
	## point: within HEADING_BLEND of one it's turned part way towards the
	## direction of the leg on the other side, so ships swing round rather
	## than snapping to a new heading.
	func sample(distance: float) -> Array[Vector2]:
		distance = clampf(distance, 0.0, length())
		var i := miles.bsearch(distance)
		i = clampi(i, 1, points.size() - 1)
		var span := miles[i] - miles[i - 1]
		var t := (distance - miles[i - 1]) / span if span > 0.0 else 1.0
		var leg := points[i] - points[i - 1]
		var direction := leg.normalized()
		var blend := minf(leg.length() / 2.0, HEADING_BLEND)
		if blend > 0.0:
			var from_start := leg.length() * t
			var to_end := leg.length() - from_start
			if from_start < blend and i >= 2:
				direction = _corner_direction(i - 1).slerp(direction, from_start / blend)
			elif to_end < blend and i <= points.size() - 2:
				direction = _corner_direction(i).slerp(direction, to_end / blend)
		return [points[i - 1].lerp(points[i], t), direction]

	## The direction halfway between the legs into and out of point k.
	func _corner_direction(k: int) -> Vector2:
		var leg_in := (points[k] - points[k - 1]).normalized()
		var leg_out := (points[k + 1] - points[k]).normalized()
		var middle := leg_in + leg_out
		return middle.normalized() if middle.length() > 0.01 else leg_out


func _ready() -> void:
	config = _load_json(CONFIG_PATH)
	for port: Dictionary in _load_json(PORTS_PATH).get("ports", []):
		ports.append(port)
		_ports_by_id[port.id] = port
		_port_positions[port.id] = Geo.project(Vector2(port.lon, port.lat))
	for model: Dictionary in _load_json(SHIP_MODELS_PATH).get("models", []):
		if model.get("coming_soon", false):
			upcoming_models.append(model)  # (Shown in the Shop, not in play yet.)
			continue
		ship_models.append(model)
		_models_by_id[model.id] = model
	ship_names = _load_json(SHIP_NAMES_PATH)
	world_map = load(WORLD_MAP_PATH)
	_add_trench_labels()
	_load_lanes()
	_load_canals()
	_load_markets()
	starts = _load_json(STARTS_PATH)
	type_starts = _load_json(TYPE_STARTS_PATH) if FileAccess.file_exists(TYPE_STARTS_PATH) else {}
	for item: Dictionary in _load_json(WONDERS_PATH).get("wonders", []):
		wonders.append(item)
		_wonders_by_id[item.id] = item
	# The map's land colors take a while to decode: start on them now, so
	# they're ready by the time a map shows (see MapView.land_colors()).
	ResourceLoader.load_threaded_request("res://data/land_colors.webp")


func get_port(id: String) -> Dictionary:
	var port: Dictionary = _ports_by_id.get(id, {})
	if port.is_empty() and id.begins_with("@"):
		return _ground_port(id)
	return port


## A fishing ground's end of its lanes ("@bristol_bay": see Fisheries) as a
## port-like place: {id, name, lon, lat, ground}, made once.
func _ground_port(id: String) -> Dictionary:
	if not _ground_ports.has(id):
		var ground: Dictionary = Fisheries.shared().grounds.get(id.substr(1), {})
		var place := {}
		if not ground.is_empty():
			var title := str(ground.name).trim_prefix("the ")
			place = {id = id, name = title.left(1).to_upper() + title.substr(1), lon = ground.lon, lat = ground.lat, ground = ground.id}
			# Where its lanes end (its middle, on the water).
			var ports: Array = ground.get("ports", [])
			if not ports.is_empty():
				var sea_lane := lane(str(ports[0]), id, -1)
				if sea_lane != null and not sea_lane.points.is_empty():
					var end := Geo.unproject(sea_lane.points[sea_lane.points.size() - 1])
					place.lon = wrapf(end.x, -180.0, 180.0)
					place.lat = end.y
			_port_positions[id] = Geo.project(Vector2(place.lon, place.lat))
		_ground_ports[id] = place
	return _ground_ports[id]
var _ground_ports := {}


## The fishing grounds' lanes (see Fisheries): "@ground" -> the ports they run from.
func fishing_lanes() -> Dictionary:
	var out := {}
	for key: String in _lane_data.keys:
		if not key.contains("@"):
			continue
		var ids := key.split("-")
		var port := ids[0] if not ids[0].begins_with("@") else ids[1]
		var end := ids[1] if ids[1].begins_with("@") else ids[0]
		out.get_or_add(end, []).append(port)
	return out


func port_name(id: String) -> String:
	return get_port(id).get("name", id)


## Ports sorted by name, for pickers.
func ports_by_name() -> Array[Dictionary]:
	var sorted: Array[Dictionary] = ports.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return sorted


## A kind of recommended start's ports for a company type: [{port, note}]
## (type_starts' for the types it ranks, starts' for Cargo & Ore).
func start_list(kind: String, type_id := "cargo") -> Array:
	if type_starts.has(type_id):
		return type_starts[type_id].get(kind, [])
	return starts.get(kind, [])


## A port's place among a company type's starts: {kind (one of START_KINDS or
## "great_lakes"), note}, or {} if it isn't a recommended or lake HQ.
func start_info(port_id: String, type_id := "cargo") -> Dictionary:
	for kind: String in START_KINDS:
		for entry: Dictionary in start_list(kind, type_id):
			if entry.port == port_id:
				return {kind = kind, note = entry.get("note", "")}
	var lakes: Dictionary = starts.get("great_lakes", {})
	if lakes.get("ports", []).has(port_id):
		return {kind = "great_lakes", note = lakes.get("note", "")}
	return {}


## A ship line's color (e.g. "container"): the map color of its middle-sized
## model, brightened to at least min_luminance so it reads on dark panels.
func category_color(category: String, min_luminance := 0.5) -> Color:
	var line := (ship_models + upcoming_models).filter(func(model: Dictionary) -> bool: return model.get("category", "") == category)
	if line.is_empty():
		return Color.WHITE
	var color := Color.from_string(line[line.size() / 2].get("map_color", "#ffffff"), Color.WHITE)
	var luminance := color.get_luminance()
	if luminance < min_luminance:
		color = color.lerp(Color.WHITE, (min_luminance - luminance) / (1.0 - luminance))
	return color


## Port position in projected map coordinates.
func port_position(id: String) -> Vector2:
	if not _port_positions.has(id) and id.begins_with("@"):
		_ground_port(id)
	return _port_positions.get(id, Vector2.ZERO)


## The sea lane from one port to another, or null if there isn't one.
func lane(from_port: String, to_port: String, way := -2) -> SeaLane:
	if way == -2:
		way = way_now(from_port, to_port)
	if way >= 0:
		return _variant_lane(way)
	var key := "%s-%s" % [from_port, to_port]
	if _lane_cache.has(key):
		return _lane_cache[key]
	if not _lane_index.has(key):
		return null
	var index: int = _lane_index[key]
	var stored := index if index >= 0 else -index - 1
	var sea_lane := SeaLane.new()
	if native_lanes:
		var made: Array = ClassDB.class_call_static(&"LaneMath", &"lane_points", _lane_data.points.slice(_lane_data.starts[stored], _lane_data.starts[stored + 1]))
		sea_lane.points = made[0]
		sea_lane.miles = made[1]
		if index < 0:
			sea_lane = sea_lane.reversed()
		sea_lane._bounds = ClassDB.class_call_static(&"LaneMath", &"lane_bounds", sea_lane.points)
		sea_lane._has_bounds = true
		_lane_cache[key] = sea_lane
		return sea_lane
	var previous := Vector2.ZERO
	var miles := 0.0
	for i in range(_lane_data.starts[stored], _lane_data.starts[stored + 1]):
		var lon_lat := _lane_data.points[i]
		if not sea_lane.points.is_empty():
			miles += Geo.distance_nm(previous, lon_lat)
		sea_lane.points.append(Geo.project(lon_lat))
		sea_lane.miles.append(miles)
		previous = lon_lat
	if index < 0:
		sea_lane = sea_lane.reversed()
	_lane_cache[key] = sea_lane
	return sea_lane


## A second way round as a lane (see _variant_index), made once.
func _variant_lane(way: int) -> SeaLane:
	var key := "#%d" % way
	if _lane_cache.has(key):
		return _lane_cache[key]
	var sea_lane := SeaLane.new()
	var made: Array = ClassDB.class_call_static(&"LaneMath", &"lane_points", _lane_data.variant_points.slice(_lane_data.variant_starts[way], _lane_data.variant_starts[way + 1])) if native_lanes else []
	if not made.is_empty():
		sea_lane.points = made[0]
		sea_lane.miles = made[1]
	else:
		var previous := Vector2.ZERO
		var miles := 0.0
		for i in range(_lane_data.variant_starts[way], _lane_data.variant_starts[way + 1]):
			var lon_lat := _lane_data.variant_points[i]
			if not sea_lane.points.is_empty():
				miles += Geo.distance_nm(previous, lon_lat)
			sea_lane.points.append(Geo.project(lon_lat))
			sea_lane.miles.append(miles)
			previous = lon_lat
	_lane_cache[key] = sea_lane
	return sea_lane


## Which way a ship setting off from one port to another this month sails:
## the second way round on a current (its index) if there's one quicker this
## month, else -1 (the lane).
func way_now(from_port: String, to_port: String) -> int:
	if _variant_index.is_empty():
		return -1
	var key := "%s>%s" % [from_port, to_port]
	if _ways_now.has(key):
		return _ways_now[key]
	var way := -1
	var index: int = _variant_index.get(key, -1)
	if index >= 0 and _lane_data.variant_months[index] & (1 << month):
		way = index
	_ways_now[key] = way
	return way


## The second way round on a current for a one-way leg (its index), whatever
## the month, or -1 if it has none.
func variant_of(from_port: String, to_port: String) -> int:
	return _variant_index.get("%s>%s" % [from_port, to_port], -1)


## Sets the month the routes and currents go by (GameState, as the calendar
## turns): this month's ways and the zones are worked out afresh.
func set_month(new_month: int) -> void:
	if new_month == month:
		return
	month = new_month
	_ways_now.clear()  # (The zones are kept by month: the next one's are worked out ahead.)
	_zones_warm_keys = _zones_lanes.keys()
	_zones_warm_at = 0


## The current at a way's name (a chain like "gulf_stream+north_atlantic": its
## first), for saying which current a ship rides.
func way_current(way: int) -> String:
	if way < 0 or way >= _lane_data.variant_currents.size():
		return ""
	var id := _lane_data.variant_currents[way].get_slice("+", 0)
	for item: Dictionary in Currents.shared().list:
		if item.id == id:
			return str(item.name)
	return ""


## Sailing distance in nautical miles; INF if there's no sea route. A way as for lane().
func distance_nm(from_port: String, to_port: String, way := -2) -> float:
	if way == -2:
		way = way_now(from_port, to_port)
	if way >= 0:
		return _lane_data.variant_distances[way]
	var index: int = _lane_index.get("%s-%s" % [from_port, to_port], _NO_LANE)
	if index == _NO_LANE:
		return INF
	return _lane_data.distances[index if index >= 0 else -index - 1]


## Every canal a lane goes through, in the order it reaches them. Each is
## {canal, forward (true if the lane runs the way the canal's path does),
## start_nm and end_nm (where it enters and leaves the canal), join_s (how far
## along the canal, in nm from its path's start, the lane is at start_nm), and
## for canals with locks, chambers (in the order the lane reaches them:
## {index, lock, mile})}.
func canal_crossings(from_port: String, to_port: String) -> Array:
	var key := "%s-%s" % [from_port, to_port]
	if _crossing_cache.has(key):
		return _crossing_cache[key]
	var crossings := []
	var sea_lane := lane(from_port, to_port)
	if sea_lane != null:
		for canal in canals:
			var crossing: Dictionary = ClassDB.class_call_static(&"LaneMath", &"crossing", sea_lane.points, sea_lane.miles, sea_lane.bounds(), canal, CHAMBER_ON_LANE) if native_lanes else _crossing(sea_lane, canal)
			if not crossing.is_empty():
				crossings.append(crossing)
		crossings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.start_nm < b.start_nm)
	_crossing_cache[key] = crossings
	return crossings


## The crossing a ship `mile` nm along the lane is in or coming up to next, or
## {} once it's past them all.
func crossing_ahead(from_port: String, to_port: String, mile: float) -> Dictionary:
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		if mile <= crossing.end_nm + 0.001:
			return crossing
	return {}


## The crossing that contains `mile` (between its entrance and exit), or {}.
func crossing_at(from_port: String, to_port: String, mile: float) -> Dictionary:
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		if mile >= crossing.start_nm - 0.001 and mile <= crossing.end_nm + 0.001:
			return crossing
	return {}


## A lane goes through a canal with locks if it passes all its chambers, and
## through a convoy canal if it passes the path points a quarter and three
## quarters of the way along (ports at either end are within that).
func _crossing(sea_lane: SeaLane, canal: Dictionary) -> Dictionary:
	var path: PackedVector2Array = canal.projected_path
	if not _near(sea_lane, canal.bounds):
		return {}
	var stops := []
	for chamber: Dictionary in canal.chambers:
		var mile := _mile_on_lane(sea_lane, chamber.position)
		if mile < 0.0:
			return {}
		stops.append({index = chamber.index, lock = chamber.lock, mile = mile})
	if stops.is_empty():
		for i: int in [floori(path.size() * 0.25), floori(path.size() * 0.75)]:
			if _mile_on_lane(sea_lane, path[i]) < 0.0:
				return {}
	var first_mile := INF
	var first_vertex := -1
	var last_mile := -INF
	var last_vertex := -1
	for i in path.size():
		var mile := _mile_on_lane(sea_lane, path[i])
		if mile < 0.0:
			continue
		if mile < first_mile:
			first_mile = mile
			first_vertex = i
		if mile > last_mile:
			last_mile = mile
			last_vertex = i
	var forward := first_vertex < last_vertex
	var start_nm := first_mile
	var end_nm := last_mile
	if not stops.is_empty():
		stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.mile < b.mile)
		start_nm = minf(start_nm, stops[0].mile)
		end_nm = maxf(end_nm, stops[-1].mile)
	var path_nm: PackedFloat64Array = canal.path_nm
	return {canal = canal, forward = forward, start_nm = start_nm, end_nm = end_nm, chambers = stops,
		join_s = path_nm[first_vertex] + (first_mile - start_nm) * (-1.0 if forward else 1.0)}


## How far along a canal (nm from its path's start) a ship `mile` nm along its lane is.
static func canal_s(crossing: Dictionary, mile: float) -> float:
	return crossing.join_s + (mile - crossing.start_nm) * (1.0 if crossing.forward else -1.0)


## The lane mile for a point `s` nm along the canal.
static func lane_mile(crossing: Dictionary, s: float) -> float:
	return crossing.start_nm + (s - crossing.join_s) * (1.0 if crossing.forward else -1.0)


## True if a point `s` nm along a convoy canal is in a single-lane stretch.
static func in_single_stretch(canal: Dictionary, s: float) -> bool:
	for stretch: Array in canal.get("single_nm", []):
		if s > stretch[0] and s < stretch[1]:
			return true
	return false


## The single-lane stretch a ship moving from s0 to s1 (nm along the canal)
## would enter, as [start, end], or [] if none.
static func single_stretch_entered(canal: Dictionary, s0: float, s1: float) -> Array:
	for stretch: Array in canal.get("single_nm", []):
		var boundary: float = stretch[0] if s1 > s0 else stretch[1]
		if (s0 <= boundary and s1 > boundary) or (s0 >= boundary and s1 < boundary):
			return stretch
	return []


## Every lock chamber a lane passes, across all its canals, in order:
## {index, lock, mile, canal, forward}.
func lane_chambers(from_port: String, to_port: String) -> Array:
	var key := "%s-%s" % [from_port, to_port]
	if _chambers_cache.has(key):
		return _chambers_cache[key]
	var all := []
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		for chamber: Dictionary in crossing.chambers:
			all.append({index = chamber.index, lock = chamber.lock, mile = chamber.mile, canal = crossing.canal,
				forward = crossing.forward})
	_chambers_cache[key] = all
	return all


## True if a lane's bounding box overlaps a rect (at any east-west copy of the world).
func _near(sea_lane: SeaLane, rect: Rect2) -> bool:
	var lane_bounds := sea_lane.bounds()
	for shift: float in [-Geo.WORLD_WIDTH, 0.0, Geo.WORLD_WIDTH]:
		if lane_bounds.intersects(Rect2(rect.position + Vector2(shift, 0.0), rect.size)):
			return true
	return false


## Miles along a lane to where it passes a point, or -1 if it doesn't.
func _mile_on_lane(sea_lane: SeaLane, point: Vector2) -> float:
	for i in range(1, sea_lane.points.size()):
		var a := sea_lane.points[i - 1]
		var b := sea_lane.points[i]
		var p := Vector2(point.x + roundf((a.x - point.x) / Geo.WORLD_WIDTH) * Geo.WORLD_WIDTH, point.y)
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		if q.distance_to(p) <= CHAMBER_ON_LANE:
			var t := a.distance_to(q) / a.distance_to(b) if a != b else 0.0
			return lerpf(sea_lane.miles[i - 1], sea_lane.miles[i], t)
	return -1.0


func get_canal(id: String) -> Dictionary:
	for canal in canals:
		if canal.id == id:
			return canal
	return {}


## Identifies the line (forward or back) waiting for one lock chamber.
static func line_key(canal_id: String, chamber_index: int, forward: bool) -> String:
	return "%s/%d/%s" % [canal_id, chamber_index, "f" if forward else "b"]


## Identifies one chamber slot: a chamber's lane each way ("f" or "b") for
## locks with lanes each way, or one of its parallel chambers ("0", "1"...)
## for shared ones.
static func slot_key(canal_id: String, chamber_index: int, slot: String) -> String:
	return "%s/%d/%s" % [canal_id, chamber_index, slot]


## The slots of a chamber: ["f", "b"] with a lane each way, or "0" to "N-1"
## for N parallel shared chambers.
static func chamber_slots(canal: Dictionary, chamber: Dictionary) -> Array[String]:
	var lock: Dictionary = canal.locks[chamber.lock]
	var slots: Array[String] = []
	if lock.get("lanes", "each_way") == "each_way":
		slots.assign(["f", "b"])
	else:
		for i in int(lock.get("parallel", 1)):
			slots.append(str(i))
	return slots


## The share of a cargo's sale value all the canals on a leg charge as tolls.
func leg_toll_share(from_port: String, to_port: String) -> float:
	var total := 0.0
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		total += float(crossing.canal.get("toll_share", 0.0))
	return total


## The XP bonus a leg earns from its canals, added up (e.g. 0.5 for Panama).
func leg_canal_xp_bonus(from_port: String, to_port: String) -> float:
	var total := 0.0
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		total += float(crossing.canal.get("xp_bonus", 0.0))
	return total


## Seconds a leg spends in lock chambers (not counting any wait for a free one).
func canal_lock_seconds(from_port: String, to_port: String) -> float:
	var total := 0.0
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		total += crossing.chambers.size() * float(crossing.canal.get("step_seconds", 3))
	return total


## Longest possible wait for a convoy on a leg (one interval per convoy canal).
func convoy_wait_seconds(from_port: String, to_port: String) -> float:
	var total := 0.0
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		if crossing.canal.get("type", "") == "convoy":
			total += float(crossing.canal.get("convoy_interval_s", 90))
	return total


## How a lane slows ships (convoy canals: speed_factor) and wears them (rough
## seas past rough_seas.lat: wear_factor), as pieces from its start:
## [[end mile, speed factor, wear factor], ...] covering the whole lane.
func lane_zones(from_port: String, to_port: String, way := -2, in_month := -1) -> Array:
	if way == -2:
		way = way_now(from_port, to_port)
	if in_month < 0:
		in_month = month
	var key := "%s-%s#%d@%d" % [from_port, to_port, way, in_month]
	if _zones_cache.has(key):
		return _zones_cache[key]
	if in_month == month and month != Currents.MEAN:
		var lane_key := "%s>%s" % [from_port, to_port]
		if not _zones_lanes.has(lane_key):
			_zones_lanes[lane_key] = [from_port, to_port]
			_zones_warm_keys.append(lane_key)
	var zones := _lane_zones_plain(from_port, to_port, way)
	if not zones.is_empty():
		zones = _with_currents(zones, lane(from_port, to_port, way), in_month)
	_zones_cache[key] = zones
	return zones


## Works out next month's zones for the lanes asked about this month (see
## _zones_lanes) for up to `budget_ms`; GameState calls it every frame.
func warm_next_month(budget_ms: float) -> void:
	if month == Currents.MEAN or _zones_warm_at >= _zones_warm_keys.size():
		return
	var start := Time.get_ticks_usec()
	var next := (month + 1) % 12
	while _zones_warm_at < _zones_warm_keys.size():
		var pair: Array = _zones_lanes[_zones_warm_keys[_zones_warm_at]]
		_zones_warm_at += 1
		var index: int = _variant_index.get("%s>%s" % [pair[0], pair[1]], -1)
		lane_zones(pair[0], pair[1], index if index >= 0 and _lane_data.variant_months[index] & (1 << next) else -1, next)
		if Time.get_ticks_usec() - start >= budget_ms * 1000.0:
			return


## A lane's zones with the currents (Currents.lane_factors()) laid over:
## each zone split where the currents' push changes, its speed times theirs.
func _with_currents(zones: Array, sea_lane: SeaLane, in_month: int) -> Array:
	if _current_settings.is_empty():
		_current_settings = config.get("currents", {ref_speed_kn = 15.0, limit = 0.35})
	var currents := Currents.lane_factors_of(sea_lane.points, sea_lane.miles, in_month, float(_current_settings.ref_speed_kn), float(_current_settings.limit))
	if currents.is_empty():
		return zones
	var out := []
	var i := 0
	var j := 0
	var at := 0.0
	while i < zones.size() and j < currents.size():
		var end := minf(float(zones[i][0]), float(currents[j][0]))
		if end > at + 0.0001:
			out.append([end, float(zones[i][1]) * float(currents[j][1]), zones[i][2]])
			at = end
		if float(zones[i][0]) <= end + 0.0001:
			i += 1
		if float(currents[j][0]) <= end + 0.0001:
			j += 1
	while i < zones.size():
		if float(zones[i][0]) > at + 0.0001:
			out.append(zones[i])
		i += 1
	return out


## A lane's zones from its canals and rough seas only (see lane_zones()).
func _lane_zones_plain(from_port: String, to_port: String, way: int) -> Array:
	var sea_lane := lane(from_port, to_port, way)
	var zones := []
	if sea_lane == null:
		return zones
	var rough: Dictionary = config.get("rough_seas", {})
	var rough_lat := float(rough.get("lat", -90.0))
	var rough_wear := float(rough.get("wear_factor", 1.0))
	var slow := []
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		var factor := float(crossing.canal.get("speed_factor", 1.0))
		if factor != 1.0:
			slow.append([crossing.start_nm, crossing.end_nm, factor])
	if native_lanes:
		return ClassDB.class_call_static(&"LaneMath", &"zones", sea_lane.points, sea_lane.miles, slow, rough_lat, rough_wear)
	var breaks := PackedFloat64Array([sea_lane.length()])
	for i in range(1, sea_lane.points.size()):
		var a := Geo.unproject(sea_lane.points[i - 1]).y < rough_lat
		var b := Geo.unproject(sea_lane.points[i]).y < rough_lat
		if a != b:
			breaks.append(lerpf(sea_lane.miles[i - 1], sea_lane.miles[i], 0.5))
	for stretch: Array in slow:
		breaks.append(stretch[0])
		breaks.append(stretch[1])
	breaks.sort()
	var previous := 0.0
	for mile in breaks:
		if mile <= previous + 0.0001:
			continue
		var middle := (previous + mile) / 2.0
		var speed := 1.0
		for stretch: Array in slow:
			if middle > stretch[0] and middle < stretch[1]:
				speed = stretch[2]
		var wear := rough_wear if Geo.unproject(sea_lane.sample(middle)[0]).y < rough_lat else 1.0
		zones.append([mile, speed, wear])
		previous = mile
	return zones


## [speed factor, wear factor] for a ship `mile` nm along a lane.
func zone_factors(from_port: String, to_port: String, mile: float) -> Array:
	for zone: Array in lane_zones(from_port, to_port):
		if mile < zone[0]:
			return [zone[1], zone[2]]
	return [1.0, 1.0]


## True if a lane needs the St. Lawrence Seaway (either end is a Great Lakes port).
func needs_seaway(from_port: String, to_port: String) -> bool:
	return bool(get_port(from_port).get("seaway", false)) or bool(get_port(to_port).get("seaway", false))


## True for ports in the rough seas far south (see game_config rough_seas).
func is_rough_port(port_id: String) -> bool:
	var rough: Dictionary = config.get("rough_seas", {})
	return float(get_port(port_id).get("lat", 0.0)) < float(rough.get("lat", -90.0))


## The longest sailing distance between any two ports.
func longest_lane_nm() -> float:
	var longest := 0.0
	for distance in _lane_data.distances:
		longest = maxf(longest, distance)
	return longest


## "Port A → Port B → Port C"
func route_text(route: Array[String]) -> String:
	return " → ".join(PackedStringArray(route.map(port_name)))


## How much more a cargo sells for on a leg: rough_seas.pay_bonus to or from a
## port in the rough seas, and upper_lakes_bonus between two upper Great Lakes
## ports (x1 otherwise).
func sale_factor(from_port: String, to_port: String) -> float:
	var factor := 1.0
	if is_rough_port(from_port) or is_rough_port(to_port):
		factor *= 1.0 + float(config.get("rough_seas", {}).get("pay_bonus", 0.0))
	if is_upper_lakes_port(from_port) and is_upper_lakes_port(to_port):
		factor *= 1.0 + float(config.get("upper_lakes_bonus", 0.0))
	return factor


## True for Great Lakes ports on Lakes Superior, Michigan or Huron.
func is_upper_lakes_port(port_id: String) -> bool:
	return get_port(port_id).get("lake", "") in ["superior", "michigan", "huron"]


## How much of this model's cargo it must unload to pass the leg's canals (0..1).
func leg_lightening(from_port: String, to_port: String, model: Dictionary) -> float:
	var kept := 1.0
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		kept *= 1.0 - float(crossing.canal.get("lighten", {}).get(model.get("id", ""), 0.0))
	return 1.0 - kept


## "800 tons" or "10 containers": a model's hold in its cargo's unit.
func cargo_text(model: Dictionary) -> String:
	var cargo: Array = model.get("cargo", [])
	var units: String = commodity(cargo[0]).get("units", "units") if not cargo.is_empty() else "units"
	return "%s %s" % [Fmt.thousands(int(model.get("capacity", 0))), units]


## "Toys, Clothing, Furniture, Coffee": what a model can carry.
func cargo_names(model: Dictionary) -> String:
	return ", ".join(PackedStringArray(model.get("cargo", []).map(func(id: String) -> String: return commodity(id).get("name", id))))


# --- Markets -----------------------------------------------------------------

## A commodity id as it is now: saves from before grain, livestock and
## vehicles were split up keep them as wheat, cattle and cars.
static func current_commodity(id: String) -> String:
	return {"grain": "wheat", "livestock": "cows", "vehicles": "cars"}.get(id, id)


func commodity(id: String) -> Dictionary:
	return _commodities_by_id.get(id, {})


## The region a port is in: {id, name, ports}.
func port_region(port_id: String) -> Dictionary:
	return _port_regions.get(port_id, {})


## A commodity's steady price at a port, before drift and market impact (see
## data/markets.json and _build_prices()).
func base_price(port_id: String, commodity_id: String) -> float:
	if _base_prices.is_empty():
		_build_prices()
	return float(_base_prices.get("%s/%s" % [port_id, commodity_id], 0.0))


## Steady prices for every port and commodity. Each port starts from base x its
## region's multiplier (or its own, if it's a source); then, as competing
## traders would, prices are evened out with nearby ports (a weighted average,
## the weight falling off with sea distance over smoothing_nm), so neighbours
## price alike and differences build up with distance. Last, a gentle local
## variation (spread over local_variation, varying smoothly across the map
## rather than port by port), a coastal variation (typically coastal_variation,
## varying over a few sailing days) and any island_markets multipliers are applied.
func _build_prices() -> void:
	var sigma := float(markets.get("smoothing_nm", 700.0))
	var weights := []  # Per port: [[other index, weight], ...]
	for i in ports.size():
		var row := []
		for j in ports.size():
			var d := 0.0 if i == j else distance_nm(ports[i].id, ports[j].id)
			if d < 3.0 * sigma:
				row.append([j, exp(-(d * d) / (sigma * sigma))])
		weights.append(row)
	var variation := float(markets.get("local_variation", 0.0))
	var coastal := float(markets.get("coastal_variation", 0.0))
	var islands := {}  # Port id -> {commodity id: multiplier}, from island_markets.
	for group: Dictionary in markets.get("island_markets", []):
		islands.merge(group.prices)
	for item: Dictionary in commodities:
		var raw := PackedFloat64Array()
		for port in ports:
			var region_id: String = port_region(port.id).get("id", "")
			var multiplier := float(markets.region_prices.get(region_id, {}).get(item.id, 1.0))
			raw.append(float(item.base) * float(markets.sources.get(item.id, {}).get(port.id, multiplier)))
		for i in ports.size():
			var total := 0.0
			var weight := 0.0
			for pair: Array in weights[i]:
				total += raw[pair[0]] * pair[1]
				weight += pair[1]
			var local := 1.0 + variation * 0.5 * _smooth_noise(ports[i], item.id)
			local *= 1.0 + coastal * _coastal_noise(ports[i], item.id)
			local *= float(islands.get(ports[i].id, {}).get(item.id, 1.0))
			_base_prices["%s/%s" % [ports[i].id, item.id]] = total / weight * local
	_world_prices.clear()


## A value in [-1, 1] that varies slowly across the map (over thousands of nm),
## differently for each commodity.
func _smooth_noise(port: Dictionary, commodity_id: String) -> float:
	var a := _hash01(commodity_id + "/x") * TAU
	var b := _hash01(commodity_id + "/y") * TAU
	var lon := deg_to_rad(float(port.lon))
	var lat := deg_to_rad(float(port.lat))
	return 0.5 * sin(lon * 3.0 + a) * cos(lat * 2.0 + b) + 0.5 * sin(lon * 5.0 + lat * 4.0 + a + b)


## A value that varies over coastal_wavelength_nm (a few sailing days),
## differently for each commodity, typically within [-1, 1]: a sum of
## coastal_waves waves across the globe in random directions. It gives
## neighbouring coasts small price differences that grow with distance, so
## short runs can pay without very short hops paying more a minute.
func _coastal_noise(port: Dictionary, commodity_id: String) -> float:
	var wavelength := float(markets.get("coastal_wavelength_nm", 1600.0))
	var waves := int(markets.get("coastal_waves", 6))
	var lon := deg_to_rad(float(port.lon))
	var lat := deg_to_rad(float(port.lat))
	var point := Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat)) * Geo.EARTH_RADIUS_NM
	var total := 0.0
	for i in waves:
		var key := "%s/wave%d" % [commodity_id, i]
		var z := _hash01(key + "z") * 2.0 - 1.0
		var angle := _hash01(key + "a") * TAU
		var r := sqrt(1.0 - z * z)
		var direction := Vector3(r * cos(angle), r * sin(angle), z)
		total += sin(point.dot(direction) * TAU / wavelength + _hash01(key + "p") * TAU)
	return total / sqrt(waves / 2.0)


## A commodity's average steady price across all ports.
func world_price(commodity_id: String) -> float:
	if _world_prices.has(commodity_id):
		return _world_prices[commodity_id]
	var total := 0.0
	for port in ports:
		total += base_price(port.id, commodity_id)
	_world_prices[commodity_id] = total / maxi(ports.size(), 1)
	return _world_prices[commodity_id]


## A repeatable number in [0, 1) for a string, for fixed per-port variation.
static func _hash01(text: String) -> float:
	return float(text.hash() & 0xFFFFFF) / float(0x1000000)


func get_ship_model(id: String) -> Dictionary:
	return _models_by_id.get(id, {})


## Ports taken out of the game, and the nearby port that took the place of each
## in older saves (see GameState._without_retired_ports()).
const RETIRED_PORTS := {"LAX": "LGB", "IHB": "GRY", "BUH": "GRY", "ALG": "TNG", "ETH": "AQJ", "PDX": "SEA"}


func _load_lanes() -> void:
	_lane_data = load(LANES_PATH)
	if _lane_data == null:
		push_error("GameData: could not read %s" % LANES_PATH)
		_lane_data = SeaLaneData.new()
		return
	for i in _lane_data.keys.size():
		var ids := _lane_data.keys[i].split("-")
		_lane_index["%s-%s" % [ids[0], ids[1]]] = i
		_lane_index["%s-%s" % [ids[1], ids[0]]] = -i - 1
	for i in _lane_data.variant_keys.size():
		_variant_index[_lane_data.variant_keys[i]] = i


## The ocean trenches' labels (data/trenches.json) added to the map's feature
## labels, once (the map resource is shared).
func _add_trench_labels() -> void:
	if world_map.feature_label_kinds.has(TRENCH_KIND):
		return
	for trench: Dictionary in _load_json(TRENCHES_PATH).get("trenches", []):
		world_map.feature_label_names.append(str(trench.name))
		world_map.feature_label_positions.append(Geo.project(Vector2(float(trench.lon), float(trench.lat))))
		world_map.feature_label_kinds.append(TRENCH_KIND)
		world_map.feature_label_min_zoom.append(float(trench.get("min_zoom", 3.0)))


func _load_canals() -> void:
	for canal: Dictionary in _load_json(CANALS_PATH).get("canals", []):
		var path := PackedVector2Array()
		var path_nm := PackedFloat64Array()
		for point: Array in canal.path:
			var lon_lat := Vector2(point[0], point[1])
			path_nm.append(0.0 if path.is_empty() else path_nm[-1] + Geo.distance_nm(Geo.unproject(path[-1]), lon_lat))
			path.append(Geo.project(lon_lat))
		canal.projected_path = path
		var bounds := Rect2(path[0], Vector2.ZERO)
		for point in path:
			bounds = bounds.expand(point)
		canal.bounds = bounds.grow(0.05)
		canal.path_nm = path_nm
		# Convoy canals: the single-lane stretches between the doubled ones, in nm.
		var single := []
		var from := 0.0
		for pair: Array in canal.get("double", []):
			if path_nm[int(pair[0])] > from:
				single.append([from, path_nm[int(pair[0])]])
			from = path_nm[int(pair[1])]
		if from < path_nm[-1] and not canal.get("double", []).is_empty():
			single.append([from, path_nm[-1]])
		canal.single_nm = single
		var chambers := []
		var locks: Array = canal.get("locks", [])
		for lock_index in locks.size():
			for point: Array in locks[lock_index].chambers:
				var position := Geo.project(Vector2(point[0], point[1]))
				var path_index := 0
				for i in path.size():
					if path[i].distance_to(position) < path[path_index].distance_to(position):
						path_index = i
				chambers.append({index = chambers.size(), lock = lock_index, position = position, path_index = path_index})
		canal.chambers = chambers
		canals.append(canal)


func _load_markets() -> void:
	markets = _load_json(MARKETS_PATH)
	for item: Dictionary in markets.get("commodities", []):
		commodities.append(item)
		_commodities_by_id[item.id] = item
	for region: Dictionary in markets.get("regions", []):
		for port_id: String in region.ports:
			_port_regions[port_id] = region


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("GameData: could not read %s" % path)
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GameData: %s is not a JSON object" % path)
		return {}
	return data


## What a recovery boat can carry: "Any 1 lost ship", or the biggest models it
## can carry, e.g. "Up to Feedermax 200 / Coastal size".
func carries_text(model: Dictionary) -> String:
	var carries: Array = model.get("carries", [])
	if carries.is_empty():
		return "Any 1 lost ship"
	var longest := 0.0
	for id: String in carries:
		longest = maxf(longest, float(get_ship_model(id).get("map_size", [0])[0]))
	var names := PackedStringArray()
	for id: String in carries:
		if float(get_ship_model(id).get("map_size", [0])[0]) == longest:
			names.append(get_ship_model(id).get("name", id))
	return "Up to %s size" % " / ".join(names)


## A wonder of the world by id (see wonders), or {}.
func wonder(id: String) -> Dictionary:
	return _wonders_by_id.get(id, {})
