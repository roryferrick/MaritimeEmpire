# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name AmbientTraffic
extends RefCounted
## The other shipping firms' ships on the map (DESIGN_LIVING_WORLD.md M1): the
## paper firms' voyages (ShippingFirms.voyages) and their homeward legs
## (ShippingFirms.returning()) drawn as ships where the player looks. Each is a
## Ship (ghost = true, owned by a Company standing for its firm, in the firm's
## colour) that isn't in GameState.ships: the map draws it like another
## player's ship (faded, its firm's flag at the stern) and the sim never steps
## it. Where a voyage is follows from its times alone: as far along the lane
## between its ports as the play time is between its start and its arrival.
## The scan (a slice of the records a frame, round and round) makes a ghost
## for each record in view, up to the cap Settings.traffic sets (CAPS), and
## drops the ghosts that sail out of view (UNSEEN_S) or finish. A voyage's
## record runs between its zones' main ports; its ghost sails between ports
## of those zones picked by the record (the main port likeliest), so a zone's
## traffic spreads over its coast. A ghost arriving at a port berths briefly
## (DWELL_HOURS) if the port has a berth to spare (SPARE_BERTHS are kept for
## the players' ships, and one of theirs waiting sends it out at once), else
## lies at anchor, then sails for home. Nothing here is saved: the ghosts are
## made again from the records when a game loads.

## How many ghosts at once, by Settings.traffic.
const CAPS := {off = 0, light = 50, busy = 150, heavy = 400}
## Calendar hours a ghost stays in port before sailing home.
const DWELL_HOURS := 8.0
## Berths a port keeps free of ghosts, for the players' ships.
const SPARE_BERTHS := 1
## A ghost out of view this long (real seconds) is dropped.
const UNSEEN_S := 2.0
## The firms' colours (game_config company_colors ids), round and round by firm.
const COLORS := ["red", "orange", "yellow", "lime", "green", "teal", "cyan", "blue", "navy", "purple", "magenta", "pink", "maroon", "brown", "tan", "gray", "white"]

## A ghost was made or dropped, or changed what it's doing (the map's drawing order and spots follow).
signal changed
## A ghost is gone (the map forgets what it kept about it).
signal ghost_gone(ship: Ship)

var _state: Node  # GameState
## The ghosts on the map now.
var ghosts: Array[Ship] = []
## Whether a projected map point is near the view (set by the map: MapView._projected_in_view()).
var view_test := Callable()
var _companies := {}  # firm index -> Company
var _keys := {}  # record key -> ghost (a record has one ghost at most)
var _scan_out := 0
var _scan_home := 0
var _next_id := -1


func _init(state: Node) -> void:
	_state = state


## How many ghosts the setting allows.
func cap() -> int:
	return int(CAPS.get(Settings.traffic, 150))


## Drops every ghost (a game ending or loading, the firms made again).
func clear() -> void:
	for ship in ghosts.duplicate():
		_drop(ship)
	_keys.clear()
	_companies.clear()
	_scan_out = 0
	_scan_home = 0
	_cells.clear()


# --- Each frame -------------------------------------------------------------------------

## Keeps the ghosts to those in view and makes new ones for the records in
## view. Called every frame, paused or not (the player pans meanwhile). The
## records are binned by where they are into CELL-degree cells of the
## projected map (a slice of them a frame, round and round: _index_slice()),
## and only the cells under the view are looked at closely (_scan_view()), so
## a view of a harbour costs a few hundred records a frame, not all 20,000.
func scan() -> void:
	var firms: ShippingFirms = _state.firms
	var limit := cap()
	if limit <= 0 or not view_test.is_valid() or not view_bounds.is_valid() or firms.voyages.is_empty() and firms.returning().is_empty():
		if not ghosts.is_empty():
			clear()
		return
	var now := Time.get_ticks_msec()
	for ship in ghosts.duplicate():
		var about: Dictionary = ship.get_meta(&"traffic")
		var at: Vector2 = GameData.port_position(ship.docked_at) if ship.is_docked() else (about.lane as GameData.SeaLane).point_at(ship.traveled_nm)
		if view_test.call(at):
			about.unseen = -1
		elif int(about.unseen) < 0:
			about.unseen = now
		elif now - int(about.unseen) > UNSEEN_S * 1000.0:
			_drop(ship)
	while ghosts.size() > limit:
		_drop(ghosts[-1])
	var t_i := Time.get_ticks_usec()
	_index_slice(firms)
	MapView._prof("traffic.index", t_i)
	t_i = Time.get_ticks_usec()
	_prune_cell()
	MapView._prof("traffic.prune", t_i)
	var bounds: Rect2 = view_bounds.call()
	if bounds.position.distance_to(_last_bounds.position) > _last_bounds.size.length() * MOVED_SHARE or absf(bounds.size.length() - _last_bounds.size.length()) > _last_bounds.size.length() * MOVED_SHARE:
		_last_bounds = bounds
		_round_due = true
		_view_cell = 0
		_view_index = 0
	if ghosts.size() < limit and (_round_due or now - _round_done >= RESCAN_S * 1000.0):
		var t_v := Time.get_ticks_usec()
		if _scan_view(limit, bounds):
			_round_due = false
			_round_done = now
		MapView._prof("traffic.view", t_v)


## The map's cells: CELL degrees of the projected map a side, COLS across and
## down (the projection runs about -180 to 180 both ways).
const CELL := 15.0
const COLS := 24
## Records binned a frame (both lists, round and round: every record is seen
## again within about six seconds, so a ship is never more than MARGIN_CELLS
## from where it's binned even at 8x; about 4 us a record once binned, 25 us
## the first time, mostly a new pair of ports' lane) and looked at closely
## under the view a frame.
const INDEX_PER_FRAME := 60
const VIEW_PER_FRAME := 400

## cell -> the records in it (by where they were when last binned: record.ghost_cell).
var _cells := {}
var _prune_at := 0
## The projected bounds of the view (set by the map: MapView._view_bounds()).
var view_bounds := Callable()


static func _cell_of(at: Vector2) -> int:
	return clampi(floori((at.y + 180.0) / CELL), 0, COLS - 1) * COLS + clampi(floori((at.x + 180.0) / CELL), 0, COLS - 1)


## A record's time window on its leg: [start, end] of play time (an outbound
## voyage from its start to its arrival, a homeward leg from the arrival to
## coming free).
static func _window(record: Dictionary, home: bool) -> Array:
	return [float(record.arrive), float(record.free)] if home else [float(record.start), float(record.arrive)]


## Bins a slice of the records by where they are now (the budget shared by the
## lists' sizes), dropping finished ones from their cells.
func _index_slice(firms: ShippingFirms) -> void:
	var out_n := firms.voyages.size()
	var home_n := firms.returning().size()
	var budget := INDEX_PER_FRAME
	var out_budget := roundi(budget * float(out_n) / maxf(out_n + home_n, 1.0))
	_scan_out = _index_list(firms.voyages, false, out_budget, _scan_out)
	_scan_home = _index_list(firms.returning(), true, budget - out_budget, _scan_home)


func _index_list(list: Array, home: bool, budget: int, cursor: int) -> int:
	var n := list.size()
	var most := mini(budget, n)
	var now: float = _state.play_time
	for k in most:
		if cursor >= n:
			cursor = 0
		var record: Dictionary = list[cursor]
		cursor += 1
		# (The hot loop: _window() and _cell_of() written out, no arrays made.)
		var start: float = record.arrive if home else record.start
		var end: float = record.free if home else record.arrive
		if now < start or now > end or end <= start:
			if int(record.get("ghost_cell", -1)) >= 0:
				_unbin(record)
			continue
		var key: String = record.get("ghost_key", "")
		if key.is_empty():
			key = _key(record, home)
			record.ghost_key = key
			record.ghost_home = home
		var ports := _ports(record, key)
		if ports.is_empty():
			continue
		var lane: GameData.SeaLane = ports[2]
		var at := lane.point_at((now - start) / (end - start) * float(ports[3]))
		var cell := clampi(floori((at.y + 180.0) / CELL), 0, COLS - 1) * COLS + clampi(floori((at.x + 180.0) / CELL), 0, COLS - 1)
		if int(record.get("ghost_cell", -1)) != cell:
			_unbin(record)
			record.ghost_cell = cell
			_cells.get_or_add(cell, []).append(record)
	return cursor


func _unbin(record: Dictionary) -> void:
	var cell := int(record.get("ghost_cell", -1))
	if cell >= 0:
		(_cells.get(cell, []) as Array).erase(record)
		record.ghost_cell = -1


## Takes the finished records out of one cell a frame (those no longer in the
## firms' lists aren't binned again, so they'd linger).
func _prune_cell() -> void:
	_prune_at = (_prune_at + 1) % (COLS * COLS)
	var records: Array = _cells.get(_prune_at, [])
	if records.is_empty():
		return
	var now: float = _state.play_time
	for i in range(records.size() - 1, -1, -1):
		var record: Dictionary = records[i]
		var window := _window(record, bool(record.get("ghost_home", false)))
		if now > window[1]:
			records.remove_at(i)
			record.ghost_cell = -1


## Looks closely at the records binned under the view (and MARGIN_CELLS round
## it): a round over them all, up to VIEW_PER_FRAME a frame, making a ghost
## for each in view till the cap. A round is started again when the view has
## moved by much (MOVED_SHARE of itself) and otherwise RESCAN_S after the last
## finished (ships drift into view slowly), so a still view costs little. True
## when a round finished this call.
func _scan_view(limit: int, bounds: Rect2) -> bool:
	var x0 := clampi(floori((bounds.position.x + 180.0) / CELL) - MARGIN_CELLS, 0, COLS - 1)
	var x1 := clampi(floori((bounds.end.x + 180.0) / CELL) + MARGIN_CELLS, 0, COLS - 1)
	var y0 := clampi(floori((bounds.position.y + 180.0) / CELL) - MARGIN_CELLS, 0, COLS - 1)
	var y1 := clampi(floori((bounds.end.y + 180.0) / CELL) + MARGIN_CELLS, 0, COLS - 1)
	var cells := []
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			cells.append(cy * COLS + cx)
	var now: float = _state.play_time
	var looked := 0
	while _view_cell < cells.size():
		var records: Array = _cells.get(cells[_view_cell], [])
		while _view_index < records.size():
			if looked >= VIEW_PER_FRAME or ghosts.size() >= limit:
				return false
			looked += 1
			var record: Dictionary = records[_view_index]
			var home := bool(record.get("ghost_home", false))
			var window := _window(record, home)
			if now < float(window[0]) or now > float(window[1]):
				records.remove_at(_view_index)  # (Finished: out of its cell.)
				record.ghost_cell = -1
				continue
			_view_index += 1
			var key: String = record.ghost_key
			if _keys.has(key):
				continue
			var ports := _ports(record, key)
			if ports.is_empty():
				continue
			var lane: GameData.SeaLane = ports[2]
			var mile: float = (now - float(window[0])) / (float(window[1]) - float(window[0])) * float(ports[3])
			if not view_test.call(lane.point_at(mile)):
				continue
			_make(record, key, home, ports, float(window[0]), float(window[1]), mile)
		_view_cell += 1
		_view_index = 0
	_view_cell = 0
	_view_index = 0
	return true
## Where the round over the view's cells is (the cell, and the record in it).
var _view_cell := 0
var _view_index := 0
var _last_bounds := Rect2()
var _round_due := true
var _round_done := -INF
const MARGIN_CELLS := 2
const RESCAN_S := 1.0
const MOVED_SHARE := 0.1


## A record's key: an outbound voyage's by its firm, start, ports and model;
## a homeward leg's by its firm, arrival, ports and model (ShippingFirms
## makes the homeward record from the outbound one, so _home_key() finds it).
static func _key(record: Dictionary, home: bool) -> String:
	return "%s|%d|%d|%s|%s|%s" % ["h" if home else "o", int(record.firm), roundi(float(record.arrive if home else record.start)), record.from, record.to, record.model]


## The key of the homeward record an outbound record will have.
static func _home_key(record: Dictionary) -> String:
	return "h|%d|%d|%s|%s|%s" % [int(record.firm), roundi(float(record.arrive)), record.to, record.from, record.model]


## The ports a record's ghost sails between, their lane and its length, [from,
## to, lane, nm], picked once per record (kept on it as ghost_ports; nothing of
## a record but its own keys is saved): a port of each zone, the main port
## likeliest; the main ports if no lane joins the picks. [] if there's no lane at all.
func _ports(record: Dictionary, key: String) -> Array:
	var kept: Array = record.get("ghost_ports", [])
	if kept.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		var a := _port_of_zone(str(record.from), rng)
		var b := _port_of_zone(str(record.to), rng)
		if a == b or GameData.lane(a, b) == null:
			a = str(record.from)
			b = str(record.to)
		var lane := GameData.lane(a, b) if a != b else null
		kept = [a, b, lane, lane.length()] if lane != null else [""]
		record.ghost_ports = kept
	return kept if kept.size() == 4 else []


## A port of a zone (named by its main port): the main port with weight 3,
## every other with 1.
func _port_of_zone(main: String, rng: RandomNumberGenerator) -> String:
	var world: WorldEconomy = _state.world
	var z := world.zone_of_port(main)
	if z < 0:
		return main
	var ports: Array = world.zones[z].ports
	var i := rng.randi() % (ports.size() + 2)
	return str(ports[0]) if i >= ports.size() else str(ports[i])


func _make(record: Dictionary, key: String, home: bool, ports: Array, start: float, end: float, mile: float) -> void:
	var firms: ShippingFirms = _state.firms
	var firm: Dictionary = firms.firms[int(record.firm)]
	var model := GameData.get_ship_model(str(record.model))
	var ship := Ship.new("%s %s" % [firm.name, str(model.get("name", record.model))], str(record.model), str(ports[0]))
	ship.id = _next_id
	_next_id -= 1
	ship.ghost = true
	ship.company = _company(int(record.firm))
	ship.docked_at = ""
	ship.from_port = str(ports[0])
	ship.to_port = str(ports[1])
	ship.traveled_nm = mile
	var lane: GameData.SeaLane = ports[2]
	ship.set_meta(&"traffic", {keys = [key], record = record, home = home, ports = [ports[0], ports[1]], lane = lane, length = lane.length(),
		start = start, end = end, unseen = -1, dwell = 0.0})
	ghosts.append(ship)
	_keys[key] = ship
	changed.emit()


## The Company standing for a firm (its name, colour and home port).
func _company(firm_index: int) -> Company:
	if not _companies.has(firm_index):
		var firm: Dictionary = (_state.firms as ShippingFirms).firms[firm_index]
		_companies[firm_index] = Company.new(str(firm.name), COLORS[firm_index % COLORS.size()], str(firm.home))
	return _companies[firm_index]


func _drop(ship: Ship) -> void:
	(_state.docks as Docks).release(ship)
	if ship.has_meta(&"traffic"):
		for key: String in ship.get_meta(&"traffic").keys:
			if _keys.get(key) == ship:
				_keys.erase(key)
	ghosts.erase(ship)
	ghost_gone.emit(ship)
	changed.emit()


# --- Each sim step -----------------------------------------------------------------------

## Moves the ghosts along by the clock, and those in port through their
## berthing and out again (play time: with the sim, so they stop when it does).
func step(delta: float) -> void:
	if ghosts.is_empty():
		return
	var now: float = _state.play_time
	for ship in ghosts.duplicate():
		var about: Dictionary = ship.get_meta(&"traffic")
		if ship.is_docked():
			_step_in_port(ship, about, delta, now)
			continue
		var span := float(about.end) - float(about.start)
		var share := clampf((now - float(about.start)) / maxf(span, 0.001), 0.0, 1.0)
		ship.traveled_nm = share * float(about.length)
		if share >= 1.0:
			if bool(about.home):
				_drop(ship)  # Home again.
			else:
				_arrive(ship, about, now)


## A ghost reaching the port it's bound for: alongside if there's a berth to
## spare, else lying at anchor (the map gives it a mooring or an anchor spot).
## Its homeward record's key is taken now, so the scan doesn't make a second
## ghost for the leg home.
func _arrive(ship: Ship, about: Dictionary, now: float) -> void:
	var port := ship.to_port
	var home_key := _home_key(about.record)
	_keys[home_key] = ship
	(about.keys as Array).append(home_key)
	ship.docked_at = port
	ship.from_port = ""
	ship.to_port = ""
	ship.traveled_nm = 0.0
	about.home = true
	about.dwell = now + DWELL_HOURS * 3600.0 / _state.calendar_seconds_per_second()
	var docks: Docks = _state.docks
	if docks.free_berths(port) > SPARE_BERTHS and docks.claim(ship):
		ship.berth_phase = Ship.BERTH_IN
		ship.berth_time = 0.0
		ship.berth_duration = _state._berth_seconds(ship, true)
	else:
		docks.release(ship)  # (Not left in the queue, ahead of a player's ship.)
	changed.emit()


func _step_in_port(ship: Ship, about: Dictionary, delta: float, now: float) -> void:
	var docks: Docks = _state.docks
	match ship.berth_phase:
		Ship.BERTH_IN:
			ship.berth_time += delta
			if ship.berth_time >= ship.berth_duration:
				ship.berth_phase = Ship.BERTH_NONE
				changed.emit()
		Ship.BERTH_OUT:
			ship.berth_time += delta
			if ship.berth_time >= ship.berth_duration:
				docks.release(ship)
				ship.berth_phase = Ship.BERTH_NONE
				_sail_home(ship, about, now)
		_:
			if now >= float(about.dwell) or ship.berth >= 0 and docks.waiting(ship.docked_at) > 0:
				if ship.berth >= 0:
					ship.berth_phase = Ship.BERTH_OUT
					ship.berth_time = 0.0
					ship.depart_to = str(about.ports[0])
					ship.berth_duration = _state._berth_seconds(ship, false)
					changed.emit()
				else:
					_sail_home(ship, about, now)


## Off home at the model's speed (the record's own timing is the firm's books;
## what's drawn sails the lane between the ghost's ports).
func _sail_home(ship: Ship, about: Dictionary, now: float) -> void:
	var port := ship.docked_at
	var home := str(about.ports[0])
	var lane := GameData.lane(port, home)
	if lane == null:
		_drop(ship)
		return
	ship.docked_at = ""
	ship.depart_to = ""
	ship.berth = -1
	ship.berth_half = -1
	ship.from_port = port
	ship.to_port = home
	ship.traveled_nm = 0.0
	about.lane = lane
	about.length = lane.length()
	about.start = now
	about.end = now + lane.length() / maxf(float(ship.model().get("speed_nm_per_s", 5.0)), 0.1)
	changed.emit()


# --- Telling about one ------------------------------------------------------------------

## What a ghost is up to, for its card (TrafficPopup): {firm, country, model,
## ships, goods (good -> units, outbound), home (bool), from, to, port (docked
## at), arrives (calendar time), status}.
func describe(ship: Ship) -> Dictionary:
	if not ship.has_meta(&"traffic"):
		return {}
	var about: Dictionary = ship.get_meta(&"traffic")
	var record: Dictionary = about.record
	var firm: Dictionary = (_state.firms as ShippingFirms).firms[int(record.firm)]
	var out := {firm = str(firm.name), country = str(firm.country), model = str(GameData.get_ship_model(str(record.model)).get("name", record.model)),
		ships = int(record.ships), goods = record.get("goods", {}) if not bool(about.home) else {}, home = bool(about.home),
		from = str(about.ports[0]), to = str(about.ports[1]), port = ship.docked_at, arrives = _state.calendar_time_at(float(about.end))}
	if ship.is_docked():
		if ship.berth_phase == Ship.BERTH_IN:
			out.status = "Coming alongside at %s" % GameData.port_name(ship.docked_at)
		elif ship.berth_phase == Ship.BERTH_OUT:
			out.status = "Leaving %s for home" % GameData.port_name(ship.docked_at)
		elif ship.berth >= 0:
			out.status = "Alongside at %s, unloading" % GameData.port_name(ship.docked_at)
		else:
			out.status = "At anchor off %s" % GameData.port_name(ship.docked_at)
	elif bool(about.home):
		out.status = "In ballast, home to %s" % GameData.port_name(ship.to_port)
	else:
		out.status = "Bound for %s" % GameData.port_name(ship.to_port)
	return out
