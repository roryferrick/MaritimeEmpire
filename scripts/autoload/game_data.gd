extends Node
## Static game data (tuning, ports, ship models) loaded from JSON in res://data.

const CONFIG_PATH := "res://data/game_config.json"
const PORTS_PATH := "res://data/ports.json"
const SHIP_MODELS_PATH := "res://data/ship_models.json"
const SHIP_NAMES_PATH := "res://data/ship_names.json"

var config: Dictionary = {}
var ports: Array[Dictionary] = []
var ship_models: Array[Dictionary] = []
## Word lists ("first", "second") combined to suggest names for new ships.
var ship_names: Dictionary = {}

var _ports_by_id: Dictionary = {}
var _models_by_id: Dictionary = {}


func _ready() -> void:
	config = _load_json(CONFIG_PATH)
	for port: Dictionary in _load_json(PORTS_PATH).get("ports", []):
		ports.append(port)
		_ports_by_id[port.id] = port
	for model: Dictionary in _load_json(SHIP_MODELS_PATH).get("models", []):
		ship_models.append(model)
		_models_by_id[model.id] = model
	ship_names = _load_json(SHIP_NAMES_PATH)


func get_port(id: String) -> Dictionary:
	return _ports_by_id.get(id, {})


func port_name(id: String) -> String:
	return get_port(id).get("name", id)


## "Port A → Port B → Port C"
func route_text(route: Array[String]) -> String:
	return " → ".join(PackedStringArray(route.map(port_name)))


## Paid per container on arriving at the end of a leg: the higher
## pay_per_container of its two ports.
func pay_per_container(from_port: String, to_port: String) -> int:
	return int(maxf(get_port(from_port).get("pay_per_container", 0),
			get_port(to_port).get("pay_per_container", 0)))


## Port position in world nautical miles (x east, y north).
func port_position(id: String) -> Vector2:
	var port := get_port(id)
	return Vector2(port.get("x", 0.0), port.get("y", 0.0))


func distance_nm(from_port: String, to_port: String) -> float:
	return port_position(from_port).distance_to(port_position(to_port))


func get_ship_model(id: String) -> Dictionary:
	return _models_by_id.get(id, {})


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
