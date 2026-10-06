extends Node
## Multiplayer, CK3 style: one player hosts and their game runs the world;
## friends join it, each running their own company in the same world (the
## economy, ports, weather and calendar are shared). Only the host sets the
## game speed, and every company has its own home port.
##
## The host's game simulates as in single player. Every SYNC_S it sends each
## joined game what changed (Ship, Company and world dictionaries, as saves
## hold them, key by key), and the joined games show it, moving ships along
## smoothly in between (see GameState._client_frame()). What a joined player
## does (buy, route, upgrade...) is sent to the host as a command and done
## there for their company; what happens to their ships (sales, breakdowns,
## level-ups...) is sent back to them as GameState's own signals, so their
## activity log reads as in single player.
##
## Games are found on the local network (the host announces itself every
## ANNOUNCE_S on DISCOVERY_PORT) or joined by address. A host can set a
## password; joining needs it. Built on Godot's ENet: Steam lobbies and relay
## can be put in its place later without changing the rest.

## A joined game asked to join, was turned down, picked a company, started.
signal join_status(text: String)
signal join_failed(reason: String)
## The host accepted: pick a company. info: {companies: [{index, name, color,
## home_port, money, level, taken}], taken_ports: [port ids], storms, seasons,
## max_time_speed}.
signal join_choose(info: Dictionary)
signal joined
## The connection to the host was lost or the host left (joined games only).
signal left(reason: String)
signal players_changed
## Games found on the local network changed (see games).
signal games_changed

enum Role { OFFLINE, HOST, CLIENT }

const PORT := 24565
const DISCOVERY_PORT := 24566
## Bumped whenever games of different versions couldn't play together.
const PROTOCOL := 1
const MAX_PLAYERS := 8
## How often the host sends what changed, and announces itself.
const SYNC_S := 0.15
const ANNOUNCE_S := 1.0
## How often each ship (and the port sizes and companies' finances) is
## compared whole, at the least (changed ships go at once).
const FULL_SYNC_S := 3.0
## The ship keys sent every update for ships under way or in port stops (see
## _broadcast()), in this order.
const HOT_KEYS: Array[String] = ["traveled_nm", "fuel", "maintenance", "align_time", "dock_time", "lock_time"]
## A found game not heard from for this long is dropped from the list.
const GAME_TIMEOUT_S := 4.0
## The longest chat message.
const CHAT_MAX_LENGTH := 200
## Keys of a ship's dictionary that change every step while it moves: a change
## to only these doesn't need the screens to look at the ship again.
const QUIET_SHIP_KEYS: Array[String] = ["traveled_nm", "fuel", "maintenance", "sea_time", "align_time", "dock_time",
	"lock_time", "bill", "stop_fuel_cost", "stop_repair_cost", "canal_queue_since", "ledger", "xp", "job_nm", "carry_nm"]
## GameState signals whose first argument is a ship: sent to that ship's
## company's player. port_band_changed goes to everyone.
const SHIP_SIGNALS: Array[StringName] = [&"cargo_sold", &"cargo_loaded", &"ship_held", &"ship_departed", &"canal_entered",
	&"ship_broke_down", &"ship_lost", &"ship_recovered", &"recovery_sent", &"ship_at_risk", &"ship_sold", &"ship_leveled"]
## Commands a joined player's game sends, done by the host for their company
## (each is the GameState function of that name).
const COMMANDS: Array[StringName] = [&"buy_ship", &"sell_ship", &"assign_route", &"set_paused", &"set_auto_refuel",
	&"set_auto_repair", &"set_auto_recover", &"set_full_loads", &"set_bank_reserve", &"level_skill", &"upgrade_all",
	&"build_hub", &"upgrade_hub", &"buy_mega", &"claim_hidden_gem", &"send_recovery", &"station_icebreaker",
	&"rename_ship", &"set_prefs"]

var role := Role.OFFLINE
## The host's settings: the game's name (shown in the games list), its
## password ("" for none) and how many players it takes (the host too).
var game_name := ""
var password := ""
var max_players := 4
## Players in the game, by peer id (the host is 1): {name, company (index in
## GameState.companies, -1 while choosing)}. Joined games get the host's list.
var players := {}
## Games found on the local network: "address:port" -> {name, company,
## players, max_players, locked, address, port, seen (msec)}.
var games := {}

## Set while the host does a joined player's command: their peer id (their
## company is GameState.company meanwhile).
var acting_peer := 0
## Meanwhile, the host's own company (for saving: see GameState.world_dict()).
var acting_for: Company = null
## Why hosting couldn't start when the game opened ("" if it did, or wasn't asked to).
var host_error := ""
## Set while a joined game applies the host's update (so the game speed can change).
var syncing := false

var _peer: ENetMultiplayerPeer = null
var _announcer: PacketPeerUDP = null
var _listener: PacketPeerUDP = null
var _sync_clock := 0.0
var _announce_clock := 0.0
## Host: what was last sent ({t, speed, weather, market, ports, companies,
## ships}); joined games apply changes to theirs.
var _sent := {}
## Host: events waiting to go out after the next update, by peer.
var _events := {}
## Host: ships changed since the last update (by id), where the round of whole
## ships is up to, and time towards the next port sizes.
var _dirty := {}
var _round := 0
var _full_clock := 0.0
## Joined game: the password and name it asks to join with, and the host's
## game while choosing a company.
var _join_password := ""
var _join_name := ""
## Joined game: when the last update came (msec), for moving ships smoothly.
var _last_sync_msec := 0
## Joined game: each ship's speed along its leg as of the last updates
## (nm per real second) and where it was: ship -> [traveled, msec].
var _ship_rates := {}
var _ship_marks := {}
## Joined game: the settings last sent to the host (see set_prefs).
var _prefs_sent := {}
var _prefs_clock := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	for signal_name in SHIP_SIGNALS:
		GameState.connect(signal_name, func(...args: Array) -> void: _on_ship_signal(signal_name, args))
	GameState.port_band_changed.connect(func(...args: Array) -> void: _on_world_signal(&"port_band_changed", args))
	GameState.hub_leveled.connect(func(...args: Array) -> void: _on_hub_signal(&"hub_leveled", args))
	GameState.hub_built.connect(func(...args: Array) -> void: _on_hub_signal(&"hub_built", args))
	GameState.mega_upgraded.connect(func(...args: Array) -> void: _on_acting_signal(&"mega_upgraded", args))
	GameState.ship_changed.connect(func(ship: Ship) -> void:
		if is_host():
			_dirty[ship.id] = true)


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func is_online() -> bool:
	return role != Role.OFFLINE


func _process(delta: float) -> void:
	if is_host():
		_sync_clock += delta
		if _sync_clock >= SYNC_S and _anyone_playing():
			_sync_clock = 0.0
			_broadcast()
		_announce_clock += delta
		if _announce_clock >= ANNOUNCE_S:
			_announce_clock = 0.0
			_announce()
	elif is_client() and GameState.in_session:
		_prefs_clock += delta
		if _prefs_clock >= 1.0:
			_prefs_clock = 0.0
			_send_prefs()
	if _listener != null:
		_listen()


# --- Hosting -----------------------------------------------------------------

## Starts hosting the game that's open (GameState's session): others can join
## it. Returns why it couldn't, or "".
func host(settings := {}) -> String:
	leave()
	game_name = str(settings.get("name", GameState.company_name)).strip_edges().left(40)
	if game_name.is_empty():
		game_name = GameState.company_name
	password = str(settings.get("password", ""))
	max_players = clampi(int(settings.get("max_players", 4)), 2, MAX_PLAYERS)
	var port := int(settings.get("port", PORT))
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, max_players - 1)
	if error != OK:
		_peer = null
		return "Couldn't host on port %d (%s). Is another game already hosting?" % [port, error_string(error)]
	multiplayer.multiplayer_peer = _peer
	role = Role.HOST
	players = {1: {name = GameState.company_name, company = GameState.companies.find(GameState.company)}}
	_sent = {}
	_events = {}
	_announcer = PacketPeerUDP.new()
	_announcer.set_broadcast_enabled(true)
	_announcer.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcast()  # Sets the baseline joiners' updates build on.
	_announce()
	players_changed.emit()
	return ""


## Stops hosting or leaves the game joined (back to playing alone, or nothing).
func leave() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.OFFLINE
	players = {}
	_sent = {}
	_events = {}
	_ship_rates = {}
	_ship_marks = {}
	acting_peer = 0
	if _announcer != null:
		_announcer.close()
		_announcer = null
	players_changed.emit()


## The game announces itself on the local network for joining players' lists.
func _announce() -> void:
	if _announcer == null:
		return
	var info := {proto = PROTOCOL, name = game_name, company = GameState.company_name,
		players = players.size(), max_players = max_players, locked = not password.is_empty(),
		port = _peer.get_host().get_local_port() if _peer and _peer.get_host() else PORT}
	_announcer.put_packet(JSON.stringify(info).to_utf8_buffer())


func _on_peer_connected(_id: int) -> void:
	pass  # The joining game says hello first (see _hello()).


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not players.has(id):
		return
	var who: Dictionary = players[id]
	players.erase(id)
	_events.erase(id)
	if int(who.company) >= 0:
		ActivityLog.add("%s left the game; their company carries on." % who.name, ActivityLog.Kind.INFO)
	_send_players()


## A joining game's hello: its protocol, the password it was given and its
## player's name. Turned away if the versions differ, the password's wrong or
## the game's full; otherwise sent the companies to pick from.
@rpc("any_peer", "reliable")
func _hello(info: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if int(info.get("proto", 0)) != PROTOCOL:
		reason = "That game is running a different version of Maritime Empire."
	elif not password.is_empty() and str(info.get("password", "")) != password:
		reason = "Wrong password." if not str(info.get("password", "")).is_empty() else "This game needs a password."
	elif players.size() >= max_players:
		reason = "This game is full (%d players)." % max_players
	if not reason.is_empty():
		_rejected.rpc_id(id, reason)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if _peer != null and multiplayer.get_peers().has(id):
				_peer.disconnect_peer(id))
		return
	players[id] = {name = str(info.get("name", "Player")).strip_edges().left(GameState.MAX_COMPANY_NAME_LENGTH), company = -1}
	_welcome.rpc_id(id, _choice_info())
	_send_players()


## What a joining player picks from: the companies (and whether someone is
## playing each), the home ports already taken, and the game's settings.
func _choice_info() -> Dictionary:
	var taken := {}
	for id: int in players:
		taken[int(players[id].company)] = true
	var list := []
	for i in GameState.companies.size():
		var each: Company = GameState.companies[i]
		list.append({index = i, name = each.name, color = each.color, home_port = each.home_port,
			money = each.money, level = each.level(), taken = taken.has(i)})
	return {companies = list, taken_ports = GameState.companies.map(func(each: Company) -> String: return each.home_port),
		storms = GameState.storms, seasons = GameState.seasons, max_time_speed = GameState.max_time_speed, name = game_name}


## A joining player's pick: {company: index} to take over a company no one is
## playing, or {name, color, home_port} to found a new one (at a home port no
## company has). Starts them off with the whole game, or says why not.
@rpc("any_peer", "reliable")
func _choose(choice: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	var index := -1
	if choice.has("company"):
		index = int(choice.company)
		var free := index >= 0 and index < GameState.companies.size() and index != GameState.companies.find(GameState.company)
		for other: int in players:
			if other != id and int(players[other].company) == index:
				free = false
		if not free:
			_choose_again.rpc_id(id, "Someone is already playing that company.", _choice_info())
			return
	else:
		var error := GameState.found_company_error(str(choice.get("name", "")), str(choice.get("home_port", "")))
		if not error.is_empty():
			_choose_again.rpc_id(id, error, _choice_info())
			return
		index = GameState.found_company(str(choice.name), str(choice.get("color", "purple")), str(choice.home_port))
	players[id].company = index
	players[id].name = GameState.companies[index].name
	_broadcast()  # Everyone (and the baseline) up to date, then the newcomer gets the same state whole.
	_start.rpc_id(id, index, _pack(GameState.world_dict()))
	_send_players()
	ActivityLog.add("%s joined the game." % GameState.companies[index].name, ActivityLog.Kind.GOOD)


func _send_players() -> void:
	if not is_host():
		return
	for id: int in players:
		if id != 1:
			_players.rpc_id(id, players)
	players_changed.emit()


# --- Joining -----------------------------------------------------------------

## Joins the game at an address (the player's name and the password to give).
## Progress comes as join_status, then join_choose (pick a company, see
## choose_company()) or join_failed.
func join(address: String, port := PORT, join_password := "", player_name := "") -> String:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address.strip_edges(), port)
	if error != OK:
		_peer = null
		return "Couldn't connect to %s (%s)." % [address, error_string(error)]
	multiplayer.multiplayer_peer = _peer
	role = Role.CLIENT
	_join_password = join_password
	_join_name = player_name
	join_status.emit("Connecting to %s..." % address)
	return ""


func _on_connected() -> void:
	join_status.emit("Connected. Asking to join...")
	_hello.rpc_id(1, {proto = PROTOCOL, password = _join_password, name = _join_name})


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("Couldn't reach that game.")


func _on_server_disconnected() -> void:
	var was_playing := GameState.in_session
	leave()
	if was_playing:
		GameState.in_session = false
		left.emit("The host left the game.")
	else:
		join_failed.emit("The host closed the connection.")


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	leave()
	join_failed.emit(reason)


@rpc("authority", "reliable")
func _welcome(info: Dictionary) -> void:
	join_status.emit("Pick your company.")
	join_choose.emit(info)


@rpc("authority", "reliable")
func _choose_again(reason: String, info: Dictionary) -> void:
	join_status.emit(reason)
	join_choose.emit(info)


## Takes over a company no one is playing ({company: index}) or founds one
## ({name, color, home_port}).
func choose_company(choice: Dictionary) -> void:
	if is_client():
		join_status.emit("Joining...")
		_choose.rpc_id(1, choice)


## The host's whole game, with this player's company: play starts.
@rpc("authority", "reliable")
func _start(local_index: int, world: Array) -> void:
	var data: Dictionary = _unpack(world)
	GameState.multiplayer_save = true
	GameState.load_world(data, local_index)
	_sent = _state_of(data)
	_ship_rates = {}
	_ship_marks = {}
	_prefs_sent = _prefs()
	_last_sync_msec = Time.get_ticks_msec()
	GameState.begin_client_session()
	joined.emit()


@rpc("authority", "reliable")
func _players(list: Dictionary) -> void:
	players = list
	players_changed.emit()


# --- Keeping joined games up to date --------------------------------------------

## The parts of the game sent to joined games, as dictionaries (ships by id).
func _collect() -> Dictionary:
	var all := GameState.all_companies()
	var ships := {}
	for ship in GameState.ships:
		var data := ship.to_dict()
		data["company"] = maxi(all.find(GameState.owner_of(ship)), 0)
		ships[ship.id] = data
	return {
		t = GameState.play_time, speed = GameState.time_speed,
		weather = GameState.weather.to_dict(), market = GameState.market.to_dict(),
		ports = GameState.port_sizes.to_dict(),
		companies = all.map(func(each: Company) -> Dictionary: return each.to_dict()),
		ships = ships,
	}


## The same parts out of a world_dict() (what a joined game starts from).
func _state_of(world: Dictionary) -> Dictionary:
	var ships := {}
	for data: Dictionary in world.get("ships", []):
		ships[int(data.id)] = data
	return {
		t = float(world.get("play_time", 0.0)), speed = 1,
		weather = world.get("weather", {}), market = world.get("market", {}),
		ports = world.get("port_sizes", {}),
		companies = world.get("companies", []),
		ships = ships,
	}


## Host: sends every joined game what changed since the last time, then their
## events. Every time: the clock and speed, the weather and market if they
## changed, each company's changed keys, and each moving ship's HOT_KEYS. A
## ship's whole dictionary is compared (and its changed keys sent) when it
## changed (GameState.ship_changed) and, round the fleet, at least every
## FULL_SYNC_S; port sizes every FULL_SYNC_S too.
func _broadcast() -> void:
	if _sent.is_empty():
		_sent = _collect()
		_dirty.clear()
		return
	var update := {t = GameState.play_time, speed = GameState.time_speed}
	var weather := GameState.weather.to_dict()
	if weather != _sent.weather:
		update.weather = weather
		_sent.weather = weather
	var market := GameState.market.to_dict()
	if market != _sent.market:
		update.market = market
		_sent.market = market
	_full_clock += SYNC_S
	var full_round := _full_clock >= FULL_SYNC_S
	if full_round:
		_full_clock = 0.0
		var ports := GameState.port_sizes.to_dict()
		var changed_ports := _diff(_sent.ports, ports)
		if not changed_ports.is_empty():
			update.ports = changed_ports
			_sent.ports = ports
	# Companies: money and XP every time, the rest (finances, hubs...) each full round.
	var all := GameState.all_companies()
	var companies := {}
	for i in all.size():
		var known: bool = i < _sent.companies.size()
		if full_round or not known:
			var now: Dictionary = all[i].to_dict()
			var changed := _diff(_sent.companies[i] if known else {}, now)
			if not changed.is_empty():
				companies[i] = changed
			if known:
				_sent.companies[i] = now
			else:
				_sent.companies.append(now)
		else:
			var kept: Dictionary = _sent.companies[i]
			var changed := {}
			if kept.money != all[i].money:
				changed.money = all[i].money
			if kept.company_xp != all[i].xp:
				changed.company_xp = all[i].xp
			if not changed.is_empty():
				companies[i] = changed
				kept.merge(changed, true)
	if not companies.is_empty():
		update.companies = companies
	# Ships: whole for the changed ones and this round's share, hot keys for the rest that move.
	var fleet := GameState.ships
	var share := ceili(fleet.size() * SYNC_S / FULL_SYNC_S)
	var ships := {}
	var hot := {}
	var present := {}
	for i in fleet.size():
		var ship: Ship = fleet[i]
		present[ship.id] = true
		var in_round := posmod(i - _round, fleet.size()) < share
		if _dirty.has(ship.id) or in_round or not _sent.ships.has(ship.id):
			var data := ship.to_dict()
			data["company"] = maxi(all.find(GameState.owner_of(ship)), 0)
			var changed := _diff(_sent.ships.get(ship.id, {}), data)
			if not changed.is_empty():
				ships[ship.id] = changed
			_sent.ships[ship.id] = data
		elif not ship.is_docked() or ship.dock_time >= 0.0:
			var values := [ship.traveled_nm, ship.fuel, ship.maintenance, ship.align_time, ship.dock_time, ship.lock_time]
			hot[ship.id] = values
			var kept: Dictionary = _sent.ships[ship.id]
			for k in HOT_KEYS.size():
				kept[HOT_KEYS[k]] = values[k]
	_round = (_round + share) % maxi(fleet.size(), 1)
	_dirty.clear()
	if not ships.is_empty():
		update.ships = ships
	if not hot.is_empty():
		update.hot = hot
	var gone := []
	for id: int in _sent.ships:
		if not present.has(id):
			gone.append(id)
	for id: int in gone:
		_sent.ships.erase(id)
	if not gone.is_empty():
		update.gone = gone
	var packed := _pack(update)
	for id: int in players:
		if id == 1 or int(players[id].company) < 0:
			continue
		_sync.rpc_id(id, packed)
		if _events.has(id) and not _events[id].is_empty():
			_events_for.rpc_id(id, _events[id])
	_events = {}


static func _diff(old: Dictionary, new: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in new:
		if not old.has(key) or old[key] != new[key]:
			out[key] = new[key]
	return out


## Joined game: applies the host's update.
@rpc("authority", "reliable")
func _sync(packed: Array) -> void:
	if not is_client() or not GameState.in_session:
		return
	var update: Dictionary = _unpack(packed)
	var now_msec := Time.get_ticks_msec()
	GameState.play_time = float(update.t)
	if int(update.speed) != GameState.time_speed:
		syncing = true
		GameState.time_speed = int(update.speed)
		syncing = false
	if update.has("weather"):
		GameState.weather.from_dict(update.weather)
	if update.has("market"):
		GameState.market.from_dict(update.market)
	if update.has("ports"):
		GameState.port_sizes.apply_update(update.ports)
	if update.has("companies"):
		_apply_companies(update.companies)
	if update.has("hot"):
		_apply_hot(update.hot, now_msec)
	if update.has("ships") or update.has("gone"):
		_apply_ships(update.get("ships", {}), update.get("gone", []), now_msec)
	_last_sync_msec = now_msec


func _apply_companies(changes: Dictionary) -> void:
	var mine := GameState.company
	var money_before := mine.money
	var level_before := mine.level()
	var hubs_before := mine.hubs.size()
	for index: int in changes:
		while GameState.companies.size() <= index:
			GameState.companies.append(Company.new())
		var each: Company = GameState.companies[index]
		var hubs_changed: bool = changes[index].has("hubs")
		each.apply_update(changes[index], each == mine)
		if hubs_changed:
			GameState.hubs_changed.emit()
	if mine.money != money_before:
		GameState.money_changed.emit(mine.money)
	if mine.level() != level_before or changes.has(GameState.companies.find(mine)):
		GameState.company_xp_changed.emit(mine.xp)
	for level in range(level_before + 1, mine.level() + 1):
		GameState.company_leveled.emit(level, Progression.unlocks_at(level))
	if mine.hubs.size() != hubs_before:
		GameState.hubs_changed.emit()


func _apply_ships(changes: Dictionary, gone: Array, now_msec: int) -> void:
	var by_id := {}
	for ship in GameState.ships:
		by_id[ship.id] = ship
	var fleet_changed := false
	for id: int in gone:
		var ship: Ship = by_id.get(id)
		if ship:
			GameState.ships.erase(ship)
			_ship_rates.erase(ship)
			_ship_marks.erase(ship)
			fleet_changed = true
	var relink := false
	for id: int in changes:
		var data: Dictionary = changes[id]
		var ship: Ship = by_id.get(id)
		if ship == null:
			ship = Ship.from_dict(data)
			by_id[id] = ship
			GameState.ships.append(ship)
			fleet_changed = true
			relink = true
		else:
			var leg_before := ship.from_port + ship.to_port
			ship.apply_update(data)
			if data.has("rescuing"):
				ship.set_meta(&"rescuing", data.rescuing)
				relink = true
			# Speed along the leg, from how far it went since the last update.
			if data.has("traveled_nm") and ship.from_port + ship.to_port == leg_before and _ship_marks.has(ship):
				var mark: Array = _ship_marks[ship]
				var seconds := (now_msec - int(mark[1])) / 1000.0
				_ship_rates[ship] = maxf((ship.traveled_nm - float(mark[0])) / seconds, 0.0) if seconds > 0.0 else 0.0
			elif data.has("from_port") or data.has("to_port") or data.has("docked_at"):
				_ship_rates.erase(ship)
		if data.has("company"):
			var index := int(data.company)
			if index < GameState.companies.size():
				ship.company = GameState.companies[index]
		_ship_marks[ship] = [ship.traveled_nm, now_msec]
		var quiet := true
		for key: String in data:
			if not key in QUIET_SHIP_KEYS:
				quiet = false
				break
		if not quiet:
			GameState.ship_changed.emit(ship)
	if relink:
		_relink_rescues()
	if fleet_changed:
		GameState.ships_changed.emit()


## Joined game: reconnects recovery boats and tugs to the ships they're
## rescuing (by name, as saves keep it).
func _relink_rescues() -> void:
	var by_name := {}
	for ship in GameState.ships:
		by_name[ship.name] = ship
	for ship in GameState.ships:
		ship.rescuer = null
	for boat in GameState.ships:
		var target: String = boat.get_meta(&"rescuing", "") if boat.has_meta(&"rescuing") else (boat.rescuing.name if boat.rescuing else "")
		boat.rescuing = by_name.get(target) if not target.is_empty() else null
	for boat in GameState.ships:
		if boat.rescuing != null and (not boat.is_tug() or boat.tug_lead):
			boat.rescuing.rescuer = boat


## Joined game: how far a ship sailing a leg moves per real second, as of the
## last updates (0 if not known yet), for moving it smoothly between them.
func ship_rate(ship: Ship) -> float:
	return float(_ship_rates.get(ship, 0.0))


# --- Commands from joined players --------------------------------------------------

## Joined game: sends a command (a GameState function of that name, see
## COMMANDS) for the host to do for this player's company. Ships go by id,
## hubs by port. Returns true if sent (the caller does nothing more itself).
func command(name: StringName, args: Array = []) -> bool:
	if not is_client():
		return false
	var sent := []
	for arg: Variant in args:
		if arg is Ship:
			sent.append({ship = (arg as Ship).id})
		elif arg is Hub:
			sent.append({hub = (arg as Hub).port_id})
		else:
			sent.append(arg)
	_command.rpc_id(1, name, sent)
	return true


@rpc("any_peer", "reliable")
func _command(name: StringName, args: Array) -> void:
	if not is_host() or not name in COMMANDS:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or int(players[id].company) < 0 or int(players[id].company) >= GameState.companies.size():
		return
	var actor: Company = GameState.companies[int(players[id].company)]
	var resolved := []
	for arg: Variant in args:
		if arg is Dictionary and (arg as Dictionary).has("ship"):
			var ship := GameState.ship_by_id(int(arg.ship))
			if ship == null or GameState.owner_of(ship) != actor:
				return  # Not theirs (or gone): ignored.
			resolved.append(ship)
		elif arg is Dictionary and (arg as Dictionary).has("hub"):
			var hub := actor.hub_at(str(arg.hub))
			if hub == null:
				return
			resolved.append(hub)
		else:
			resolved.append(arg)
	if name == &"assign_route":
		var route: Array[String] = []
		route.assign(resolved[1])
		resolved[1] = route
	# Done as that player: their company is GameState.company meanwhile.
	var mine := GameState.company
	GameState.company = actor
	acting_peer = id
	acting_for = mine
	var result: Variant = GameState.callv(name, resolved)
	acting_peer = 0
	acting_for = null
	GameState.company = mine
	GameState.money_changed.emit(mine.money)
	GameState.company_xp_changed.emit(mine.xp)
	if name == &"buy_ship" and result is Ship:
		_log_to(id, "Bought %s. It's docked at %s." % [result.name, GameData.port_name(result.docked_at)],
			ActivityLog.Kind.INFO, ActivityLog.ship_color(result))


## This player's own map and log settings, as Company.PREF_KEYS.
func _prefs() -> Dictionary:
	var out := {}
	for key in Company.PREF_KEYS:
		out[key] = GameState.company.to_dict()[key]
	return out


## Joined game: sends this player's own settings when they change, so the
## host's save keeps them.
func _send_prefs() -> void:
	var now := _prefs()
	if now != _prefs_sent:
		_prefs_sent = now
		command(&"set_prefs", [now])


# --- Events for joined players -----------------------------------------------------

## Host: something happened to a ship: if it's a joined player's, it's sent to
## them (after the next update, which brings any new ship first).
func _on_ship_signal(signal_name: StringName, args: Array) -> void:
	if is_host() and not args.is_empty() and args[0] is Ship:
		_queue_for(GameState.owner_of(args[0]), signal_name, args)


## Host: a hub leveled or was founded: sent to its company's player.
func _on_hub_signal(signal_name: StringName, args: Array) -> void:
	if not is_host():
		return
	for each in GameState.companies:
		if each.hubs.has(args[0]):
			_queue_for(each, signal_name, args)


## Host: something a joined player's own command did (a mega upgrade).
func _on_acting_signal(signal_name: StringName, args: Array) -> void:
	if is_host() and acting_peer != 0:
		_queue_peer(acting_peer, signal_name, args)


## Host: something that happened to the world (a port grew): sent to everyone.
func _on_world_signal(signal_name: StringName, args: Array) -> void:
	if not is_host():
		return
	for id: int in players:
		if id != 1 and int(players[id].company) >= 0:
			_queue_peer(id, signal_name, args)


func _queue_for(owner_company: Company, signal_name: StringName, args: Array) -> void:
	var index := GameState.companies.find(owner_company)
	for id: int in players:
		if id != 1 and int(players[id].company) == index:
			_queue_peer(id, signal_name, args)


## Ships go by id (with their name and model, in case they're gone by the time
## it arrives), hubs by port, canals by id.
func _queue_peer(id: int, signal_name: StringName, args: Array) -> void:
	var sent := []
	for i in args.size():
		var arg: Variant = args[i]
		if arg is Ship:
			sent.append({ship = (arg as Ship).id, name = (arg as Ship).name, model = (arg as Ship).model_id})
		elif arg is Hub:
			sent.append({hub = (arg as Hub).port_id})
		elif signal_name == &"canal_entered" and i == 1:
			sent.append({canal = str((arg as Dictionary).get("id", ""))})
		else:
			sent.append(arg)
	(_events.get_or_add(id, []) as Array).append([signal_name, sent])


## Joined game: the host's events for this player's company, played out as
## GameState's own signals (so the activity log reads as in single player).
@rpc("authority", "reliable")
func _events_for(list: Array) -> void:
	if not is_client():
		return
	var by_id := {}
	for ship in GameState.ships:
		by_id[ship.id] = ship
	for event: Array in list:
		var args := []
		for arg: Variant in event[1]:
			if arg is Dictionary and (arg as Dictionary).has("ship"):
				var ship: Ship = by_id.get(int(arg.ship))
				if ship == null:  # Gone already (sold): a stand-in with its name.
					ship = Ship.new(str(arg.name), str(arg.model))
				args.append(ship)
			elif arg is Dictionary and (arg as Dictionary).has("hub"):
				var hub := GameState.company.hub_at(str(arg.hub))
				args.append(hub if hub != null else Hub.new(str(arg.hub)))
			elif arg is Dictionary and (arg as Dictionary).has("canal"):
				args.append(GameData.get_canal(str(arg.canal)))
			else:
				args.append(arg)
		_emit(event[0], args)


func _emit(signal_name: StringName, args: Array) -> void:
	match args.size():
		0: GameState.emit_signal(signal_name)
		1: GameState.emit_signal(signal_name, args[0])
		2: GameState.emit_signal(signal_name, args[0], args[1])
		3: GameState.emit_signal(signal_name, args[0], args[1], args[2])
		4: GameState.emit_signal(signal_name, args[0], args[1], args[2], args[3])
		5: GameState.emit_signal(signal_name, args[0], args[1], args[2], args[3], args[4])
		6: GameState.emit_signal(signal_name, args[0], args[1], args[2], args[3], args[4], args[5])
		_: GameState.emit_signal(signal_name, args[0], args[1], args[2], args[3], args[4], args[5], args[6])


## Host: an activity log message for a joined player (from their command).
func _log_to(id: int, text: String, kind: int, color := Color.TRANSPARENT) -> void:
	if is_host() and players.has(id):
		_log.rpc_id(id, text, kind, color)


## While the host does a joined player's command, its activity log messages go
## to that player instead. True if this one was sent on.
func redirect_log(text: String, kind: int, color: Color) -> bool:
	if not is_host() or acting_peer == 0:
		return false
	_log_to(acting_peer, text, kind, color)
	return true


@rpc("authority", "reliable")
func _log(text: String, kind: int, color: Color) -> void:
	ActivityLog.add(text, kind, color)


# --- Finding games on the local network ------------------------------------------

## Starts listening for games announced on the local network (see games).
func start_browsing() -> void:
	stop_browsing()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null
	games = {}
	games_changed.emit()


func stop_browsing() -> void:
	if _listener != null:
		_listener.close()
	_listener = null


func _listen() -> void:
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var packet := _listener.get_packet()
		var address := _listener.get_packet_ip()
		var info: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(info) != TYPE_DICTIONARY or int(info.get("proto", 0)) != PROTOCOL:
			continue
		var port := int(info.get("port", PORT))
		info.address = address
		info.port = port
		info.seen = Time.get_ticks_msec()
		games["%s:%d" % [address, port]] = info
		changed = true
	for key: String in games.keys():
		if Time.get_ticks_msec() - int(games[key].seen) > GAME_TIMEOUT_S * 1000.0:
			games.erase(key)
			changed = true
	if changed:
		games_changed.emit()


# --- Packing -----------------------------------------------------------------------

## A dictionary as [its size, its bytes compressed] for sending.
static func _pack(data: Dictionary) -> Array:
	var bytes := var_to_bytes(data)
	return [bytes.size(), bytes.compress(FileAccess.COMPRESSION_ZSTD)]


static func _unpack(packed: Array) -> Dictionary:
	var bytes: PackedByteArray = (packed[1] as PackedByteArray).decompress(int(packed[0]), FileAccess.COMPRESSION_ZSTD)
	var data: Variant = bytes_to_var(bytes)
	return data if data is Dictionary else {}


## Host: whether anyone has joined and is playing (no updates to send if not;
## a newcomer's start brings the baseline up to date, see _choose()).
func _anyone_playing() -> bool:
	for id: int in players:
		if id != 1 and int(players[id].company) >= 0:
			return true
	return false


## Joined game: the moving ships' HOT_KEYS from the host's update, and their
## speeds along their legs for moving them smoothly until the next.
func _apply_hot(hot: Dictionary, now_msec: int) -> void:
	var by_id := {}
	for ship in GameState.ships:
		by_id[ship.id] = ship
	for id: int in hot:
		var ship: Ship = by_id.get(id)
		if ship == null:
			continue
		var values: Array = hot[id]
		if _ship_marks.has(ship):
			var mark: Array = _ship_marks[ship]
			var seconds := (now_msec - int(mark[1])) / 1000.0
			if seconds > 0.0:
				_ship_rates[ship] = maxf((float(values[0]) - float(mark[0])) / seconds, 0.0)
		ship.traveled_nm = values[0]
		ship.fuel = values[1]
		ship.maintenance = values[2]
		ship.align_time = values[3]
		ship.dock_time = values[4]
		ship.lock_time = values[5]
		_ship_marks[ship] = [ship.traveled_nm, now_msec]


# --- Chat --------------------------------------------------------------------------

## Says something to everyone in the game: it shows in every player's activity
## log, "Name: text", in the speaker's company color.
func say(text: String) -> void:
	text = text.strip_edges().left(CHAT_MAX_LENGTH)
	if text.is_empty():
		return
	if is_host():
		_chat_all(1, text)
	elif is_client():
		_chat.rpc_id(1, text)


@rpc("any_peer", "reliable")
func _chat(text: String) -> void:
	if is_host():
		_chat_all(multiplayer.get_remote_sender_id(), str(text).left(CHAT_MAX_LENGTH))


func _chat_all(from: int, text: String) -> void:
	if not players.has(from):
		return
	var index := int(players[from].company)
	var speaker: String = players[from].name
	var color := "purple"
	if index >= 0 and index < GameState.companies.size():
		speaker = GameState.companies[index].name
		color = GameState.companies[index].color
	for id: int in players:
		if id != 1 and int(players[id].company) >= 0:
			_chat_line.rpc_id(id, speaker, color, text)
	_chat_line(speaker, color, text)


@rpc("authority", "reliable")
func _chat_line(speaker: String, color: String, text: String) -> void:
	ActivityLog.add("%s: %s" % [speaker, text], ActivityLog.Kind.INFO, GameState.company_color_value(color))
