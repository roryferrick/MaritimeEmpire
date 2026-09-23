extends Node
## Static game data (tuning, ports, sea lanes, ship models, map art) loaded
## from res://data.
##
## Positions are projected map coordinates (see Geo); distances are real
## nautical miles along the sea lanes.

const CONFIG_PATH := "res://data/game_config.json"
const PORTS_PATH := "res://data/ports.json"
const LANES_PATH := "res://data/sea_lanes.json"
const SHIP_MODELS_PATH := "res://data/ship_models.json"
const SHIP_NAMES_PATH := "res://data/ship_names.json"
const WORLD_MAP_PATH := "res://data/world_map.res"

var config: Dictionary = {}
var ports: Array[Dictionary] = []
var ship_models: Array[Dictionary] = []
## Word lists ("first", "second") combined to suggest names for new ships.
var ship_names: Dictionary = {}
var world_map: WorldMapData

var _ports_by_id: Dictionary = {}
var _port_positions: Dictionary = {}  # id -> projected Vector2
var _models_by_id: Dictionary = {}
var _lanes: Dictionary = {}  # "FROM-TO" (both directions) -> SeaLane


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
	return _lanes.get("%s-%s" % [from_port, to_port])


## Sailing distance in nautical miles; INF if there's no sea route.
func distance_nm(from_port: String, to_port: String) -> float:
	var sea_lane := lane(from_port, to_port)
	return sea_lane.length() if sea_lane else INF


## "Port A → Port B → Port C"
func route_text(route: Array[String]) -> String:
	return " → ".join(PackedStringArray(route.map(port_name)))


## Paid to a ship arriving at the end of a leg.
func leg_payment(from_port: String, to_port: String, containers: int) -> int:
	var rate := float(config.get("pay_per_container_nm", 0.0))
	return roundi(containers * distance_nm(from_port, to_port) * rate)


func get_ship_model(id: String) -> Dictionary:
	return _models_by_id.get(id, {})


func _load_lanes() -> void:
	var lanes: Dictionary = _load_json(LANES_PATH).get("lanes", {})
	for key: String in lanes:
		var ids := key.split("-")
		var sea_lane := SeaLane.new()
		var previous := Vector2.ZERO
		var miles := 0.0
		for coord: Array in lanes[key].points:
			var lon_lat := Vector2(coord[0], coord[1])
			if not sea_lane.points.is_empty():
				miles += Geo.distance_nm(previous, lon_lat)
			sea_lane.points.append(Geo.project(lon_lat))
			sea_lane.miles.append(miles)
			previous = lon_lat
		if sea_lane.points.size() < 2:
			continue
		_lanes["%s-%s" % [ids[0], ids[1]]] = sea_lane
		_lanes["%s-%s" % [ids[1], ids[0]]] = sea_lane.reversed()


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
