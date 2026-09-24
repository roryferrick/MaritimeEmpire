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
## How close (in projected degrees) a lane must pass a lock chamber to go through it.
const CHAMBER_ON_LANE := 0.002
const _NO_LANE := 1 << 30

var config: Dictionary = {}
var ports: Array[Dictionary] = []
var ship_models: Array[Dictionary] = []
## Word lists ("first", "second") combined to suggest names for new ships.
var ship_names: Dictionary = {}
var world_map: WorldMapData
## Canals from data/canals.json (with locks, or convoys), each with its path
## projected (projected_path) and in nm from its start (path_nm), convoy
## canals' single-lane stretches (single_nm: [[start, end] nm]), and lock
## chambers in path order (chambers: {index, lock, position, path_index}).
var canals: Array[Dictionary] = []

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
var _zones_cache: Dictionary = {}  # "FROM-TO" -> lane_zones()


## A sailing path between two ports.
class SeaLane:
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

	## Position and travel direction (both projected) after sailing some distance.
	func sample(distance: float) -> Array[Vector2]:
		distance = clampf(distance, 0.0, length())
		var i := miles.bsearch(distance)
		i = clampi(i, 1, points.size() - 1)
		var span := miles[i] - miles[i - 1]
		var t := (distance - miles[i - 1]) / span if span > 0.0 else 1.0
		return [points[i - 1].lerp(points[i], t), points[i] - points[i - 1]]


func _ready() -> void:
	config = _load_json(CONFIG_PATH)
	for port: Dictionary in _load_json(PORTS_PATH).get("ports", []):
		ports.append(port)
		_ports_by_id[port.id] = port
		_port_positions[port.id] = Geo.project(Vector2(port.lon, port.lat))
	for model: Dictionary in _load_json(SHIP_MODELS_PATH).get("models", []):
		ship_models.append(model)
		_models_by_id[model.id] = model
	ship_names = _load_json(SHIP_NAMES_PATH)
	world_map = load(WORLD_MAP_PATH)
	_load_lanes()
	_load_canals()


func get_port(id: String) -> Dictionary:
	return _ports_by_id.get(id, {})


func port_name(id: String) -> String:
	return get_port(id).get("name", id)


## Ports sorted by name, for pickers.
func ports_by_name() -> Array[Dictionary]:
	var sorted: Array[Dictionary] = ports.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return sorted


## Port position in projected map coordinates.
func port_position(id: String) -> Vector2:
	return _port_positions.get(id, Vector2.ZERO)


## The sea lane from one port to another, or null if there isn't one.
func lane(from_port: String, to_port: String) -> SeaLane:
	var key := "%s-%s" % [from_port, to_port]
	if _lane_cache.has(key):
		return _lane_cache[key]
	if not _lane_index.has(key):
		return null
	var index: int = _lane_index[key]
	var stored := index if index >= 0 else -index - 1
	var sea_lane := SeaLane.new()
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


## Sailing distance in nautical miles; INF if there's no sea route.
func distance_nm(from_port: String, to_port: String) -> float:
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
			var crossing := _crossing(sea_lane, canal)
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


## The toll for one canal on a leg: its toll_share of the leg's base pay.
func canal_toll(from_port: String, to_port: String, model: Dictionary, canal: Dictionary) -> int:
	return roundi(leg_payment(from_port, to_port, model) * float(canal.get("toll_share", 0.0)))


## All the canal tolls on a leg.
func leg_tolls(from_port: String, to_port: String, model: Dictionary) -> int:
	var total := 0
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		total += canal_toll(from_port, to_port, model, crossing.canal)
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
func lane_zones(from_port: String, to_port: String) -> Array:
	var key := "%s-%s" % [from_port, to_port]
	if _zones_cache.has(key):
		return _zones_cache[key]
	var sea_lane := lane(from_port, to_port)
	var zones := []
	if sea_lane == null:
		_zones_cache[key] = zones
		return zones
	var rough: Dictionary = config.get("rough_seas", {})
	var rough_lat := float(rough.get("lat", -90.0))
	var rough_wear := float(rough.get("wear_factor", 1.0))
	var breaks := PackedFloat64Array([sea_lane.length()])
	for i in range(1, sea_lane.points.size()):
		var a := Geo.unproject(sea_lane.points[i - 1]).y < rough_lat
		var b := Geo.unproject(sea_lane.points[i]).y < rough_lat
		if a != b:
			breaks.append(lerpf(sea_lane.miles[i - 1], sea_lane.miles[i], 0.5))
	var slow := []
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		var factor := float(crossing.canal.get("speed_factor", 1.0))
		if factor != 1.0:
			slow.append([crossing.start_nm, crossing.end_nm, factor])
			breaks.append(crossing.start_nm)
			breaks.append(crossing.end_nm)
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
	_zones_cache[key] = zones
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


## Paid to a ship of this model for carrying a load between two ports (before
## any hub bonus): capacity x distance x pay rate, plus rough_seas.pay_bonus
## to or from a port in the rough seas, plus upper_lakes_bonus between two
## upper Great Lakes ports, less what a canal makes it unload to pass
## (a canal's "lighten" for the model, e.g. a Supertanker at Suez).
func leg_payment(from_port: String, to_port: String, model: Dictionary) -> int:
	var pay := int(model.get("capacity", 0)) * distance_nm(from_port, to_port) * pay_rate(model)
	if is_rough_port(from_port) or is_rough_port(to_port):
		pay *= 1.0 + float(config.get("rough_seas", {}).get("pay_bonus", 0.0))
	if is_upper_lakes_port(from_port) and is_upper_lakes_port(to_port):
		pay *= 1.0 + float(config.get("upper_lakes_bonus", 0.0))
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		pay *= 1.0 - float(crossing.canal.get("lighten", {}).get(model.get("id", ""), 0.0))
	return roundi(pay)


## True for Great Lakes ports on Lakes Superior, Michigan or Huron.
func is_upper_lakes_port(port_id: String) -> bool:
	return get_port(port_id).get("lake", "") in ["superior", "michigan", "huron"]


## How much of this model's cargo it must unload to pass the leg's canals (0..1).
func leg_lightening(from_port: String, to_port: String, model: Dictionary) -> float:
	var kept := 1.0
	for crossing: Dictionary in canal_crossings(from_port, to_port):
		kept *= 1.0 - float(crossing.canal.get("lighten", {}).get(model.get("id", ""), 0.0))
	return 1.0 - kept


## Dollars per unit of cargo per nm: the model's own pay_per_unit_nm (gas
## tankers), or game_config pay_per_container_nm.
func pay_rate(model: Dictionary) -> float:
	return float(model.get("pay_per_unit_nm", config.get("pay_per_container_nm", 0.0)))


## "10,000 containers" or "5,000 tons of fuel".
func cargo_text(model: Dictionary) -> String:
	var unit := "tons of fuel" if model.get("category", "") == "tanker" else "containers"
	return "%s %s" % [Fmt.thousands(int(model.get("capacity", 0))), unit]


func get_ship_model(id: String) -> Dictionary:
	return _models_by_id.get(id, {})


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
## can carry, e.g. "Up to Greenline 200 / Coastal size".
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
