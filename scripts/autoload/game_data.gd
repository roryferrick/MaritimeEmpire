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
const _NO_LANE := 1 << 30

var config: Dictionary = {}
var ports: Array[Dictionary] = []
var ship_models: Array[Dictionary] = []
## Word lists ("first", "second") combined to suggest names for new ships.
var ship_names: Dictionary = {}
var world_map: WorldMapData

var _ports_by_id: Dictionary = {}
var _port_positions: Dictionary = {}  # id -> projected Vector2
var _models_by_id: Dictionary = {}
var _lane_data: SeaLaneData
## "FROM-TO" (both directions) -> index into _lane_data; negative (-index - 1)
## when the stored lane runs the other way.
var _lane_index: Dictionary = {}
var _lane_cache: Dictionary = {}  # "FROM-TO" -> SeaLane, built on first use


## A sailing path between two ports.
class SeaLane:
	## Projected map coordinates, from the first port to the second.
	var points := PackedVector2Array()
	## Nautical miles from the start to each point.
	var miles := PackedFloat64Array()

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


## The longest sailing distance between any two ports.
func longest_lane_nm() -> float:
	var longest := 0.0
	for distance in _lane_data.distances:
		longest = maxf(longest, distance)
	return longest


## "Port A → Port B → Port C"
func route_text(route: Array[String]) -> String:
	return " → ".join(PackedStringArray(route.map(port_name)))


## Paid to a ship of this model for carrying a full load between two ports.
func leg_payment(from_port: String, to_port: String, model: Dictionary) -> int:
	return roundi(int(model.get("capacity", 0)) * distance_nm(from_port, to_port) * pay_rate(model))


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
