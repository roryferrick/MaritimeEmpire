extends Node
## State of the running game session: money, ships and their movement, plus
## saving and loading.
##
## The world only advances while a session is open. The game saves on quit
## and on a timer; nothing happens while the game is closed.

signal money_changed(money: int)
signal containers_changed(total: int)
## A ship was bought.
signal ships_changed
## A ship docked, departed, was paused/resumed, or got a new route.
signal ship_changed(ship: Ship)
signal ship_arrived(ship: Ship, port_id: String, payment: int)

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 2
const MAX_NAME_LENGTH := 24
const MAX_COMPANY_NAME_LENGTH := 32

var money: int = 0:
	set(value):
		money = value
		money_changed.emit(money)

var containers_delivered: int = 0:
	set(value):
		containers_delivered = value
		containers_changed.emit(containers_delivered)

var company_name := ""
## New ships are delivered here.
var home_port := ""
var ships: Array[Ship] = []
var in_session := false

var _autosave_timer := Timer.new()


func _ready() -> void:
	_autosave_timer.wait_time = float(GameData.config.get("autosave_seconds", 30))
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _process(delta: float) -> void:
	if not in_session:
		return
	for ship in ships:
		_advance(ship, delta)


# --- Ships ---------------------------------------------------------------

func buy_ship(model_id: String, ship_name: String) -> Ship:
	ship_name = ship_name.strip_edges()
	if not buy_error(model_id).is_empty() or not ship_name_error(ship_name).is_empty():
		return null
	money -= int(GameData.get_ship_model(model_id).get("price", 0))
	var ship := Ship.new(ship_name, model_id, home_port)
	ships.append(ship)
	ships_changed.emit()
	save_game()
	return ship


func owned_count(model_id: String) -> int:
	return ships.filter(func(ship: Ship) -> bool: return ship.model_id == model_id).size()


## Why the player can't buy another of this model, or "" if they can.
func buy_error(model_id: String) -> String:
	var model := GameData.get_ship_model(model_id)
	var limit := int(model.get("max_owned", 0))
	if limit > 0 and owned_count(model_id) >= limit:
		return "You already own the maximum of %d %s ships." % [limit, model.get("name", model_id)]
	if money < int(model.get("price", 0)):
		return "You can't afford this ship."
	return ""


func company_name_error(new_company_name: String) -> String:
	return "Enter a company name." if new_company_name.strip_edges().is_empty() else ""


## Why a ship name can't be used, or "" if it's fine.
func ship_name_error(ship_name: String) -> String:
	ship_name = ship_name.strip_edges()
	if ship_name.is_empty():
		return "Enter a name."
	for ship in ships:
		if ship.name.nocasecmp_to(ship_name) == 0:
			return "You already have a ship called %s." % ship.name
	return ""


func suggest_ship_name() -> String:
	var first: Array = GameData.ship_names.get("first", [])
	var second: Array = GameData.ship_names.get("second", [])
	if not first.is_empty() and not second.is_empty():
		for attempt in 100:
			var candidate := "%s %s" % [first.pick_random(), second.pick_random()]
			if ship_name_error(candidate).is_empty():
				return candidate
	var n := ships.size() + 1
	while not ship_name_error("Ship %d" % n).is_empty():
		n += 1
	return "Ship %d" % n


## Why a route can't be given to a ship, or "" if it's valid. Routes loop, so
## the last stop also can't be the same as the first, and every leg (including
## the one back to the start, and the trip from where the ship is now to the
## route's first port) must be within the ship's range.
func route_error(route: Array[String], ship: Ship) -> String:
	if route.size() < 2:
		return "A route needs at least 2 ports."
	for i in range(1, route.size()):
		if route[i] == route[i - 1]:
			return "A ship can't visit the same port twice in a row."
	if route[-1] == route[0]:
		return "The route loops back to %s, so it can't also end there." % GameData.port_name(route[0])
	for i in route.size():
		var from := route[i]
		var to := route[(i + 1) % route.size()]
		if not ship.can_sail(from, to):
			return _range_error(ship, from, to)
	var start := ship.reference_port()
	if not route.has(start) and not ship.can_sail(start, route[0]):
		return _range_error(ship, start, route[0])
	return ""


func _range_error(ship: Ship, from: String, to: String) -> String:
	return "%s to %s is %s nm, beyond this ship's %s nm range." % [
		GameData.port_name(from), GameData.port_name(to),
		Fmt.thousands(roundi(GameData.distance_nm(from, to))), Fmt.thousands(roundi(ship.range_nm()))]


## Gives a ship a new route and sets it running. A ship at sea finishes its
## current leg first.
func assign_route(ship: Ship, route: Array[String]) -> void:
	if not route_error(route, ship).is_empty():
		return
	ship.paused = false
	if ship.is_docked():
		ship.route = route.duplicate()
		ship.pending_route.clear()
		ship.route_index = ship.route.find(ship.docked_at)
		_depart(ship)
	else:
		ship.pending_route = route.duplicate()
	ship_changed.emit(ship)


## A ship paused at sea carries on to its next port and waits there.
func set_paused(ship: Ship, paused: bool) -> void:
	if not ship.has_route():
		return
	ship.paused = paused
	if not paused and ship.is_docked():
		_depart(ship)
	ship_changed.emit(ship)


func _advance(ship: Ship, delta: float) -> void:
	var budget := ship.speed() * delta
	while budget > 0.0 and not ship.is_docked():
		var remaining := ship.leg_length() - ship.traveled_nm
		if budget < remaining:
			ship.traveled_nm += budget
			return
		budget -= remaining
		_arrive(ship)


func _arrive(ship: Ship) -> void:
	var port := ship.to_port
	var payment := GameData.leg_payment(ship.from_port, port, ship.capacity())
	ship.docked_at = port
	ship.from_port = ""
	ship.to_port = ""
	ship.traveled_nm = 0.0
	if not ship.pending_route.is_empty():
		ship.route = ship.pending_route.duplicate()
		ship.pending_route.clear()
		ship.route_index = ship.route.find(port)

	money += payment
	containers_delivered += ship.capacity()
	ship_arrived.emit(ship, port, payment)
	if ship.is_running():
		_depart(ship)
	ship_changed.emit(ship)


func _depart(ship: Ship) -> void:
	var next := ship.next_route_index()
	ship.route_index = next
	ship.from_port = ship.docked_at
	ship.to_port = ship.route[next]
	ship.traveled_nm = 0.0
	ship.docked_at = ""


# --- Saving --------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func new_game(new_company_name: String, new_home_port: String) -> void:
	company_name = new_company_name.strip_edges()
	home_port = new_home_port
	money = int(GameData.config.get("starting_money", 10000))
	containers_delivered = 0
	ships.clear()
	_begin_session()
	save_game()


## Loads the save file and starts a session. Returns why it couldn't, or "".
func continue_game() -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GameState: save file %s is missing or corrupt" % SAVE_PATH)
		return "The saved game could not be read."
	if int(data.get("version", 0)) != SAVE_VERSION:
		return "This save is from an older version of the game and can't be loaded. Start a new game."
	company_name = data.get("company_name", "")
	home_port = data.get("home_port", "")
	money = int(data.get("money", 0))
	containers_delivered = int(data.get("containers_delivered", 0))
	ships.clear()
	for ship_data: Dictionary in data.get("ships", []):
		ships.append(Ship.from_dict(ship_data))
	_begin_session()
	return ""


func save_game() -> void:
	if not in_session:
		return
	var data := {
		"version": SAVE_VERSION,
		"company_name": company_name,
		"home_port": home_port,
		"money": money,
		"containers_delivered": containers_delivered,
		"ships": ships.map(func(ship: Ship) -> Dictionary: return ship.to_dict()),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameState: could not write save (%s)" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))


func _begin_session() -> void:
	in_session = true
	_autosave_timer.start()
