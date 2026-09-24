class_name CanalTraffic
extends RefCounted
## Moves ships through canals (data/canals.json, see GameData.canal_crossings()):
## tolls, lock chambers and their lines, and convoys. GameState owns one and
## asks it, every frame, whether each sailing ship is held (hold()) and how far
## it may go (limit()).
##
## Locks: each lock chamber a lane passes is a stop. A chamber has slots (see
## GameData.chamber_slots()): a lane each way ("each_way", like Panama), or one
## or more shared chambers used by one ship at a time in either direction. A
## ship reserves a slot as it comes up to the chamber (or joins the line for
## it, stopping queue_spacing_nm behind the ship ahead), sails in, and sits
## there step_seconds while the water rises or falls. A shared chamber is left
## at the other level, so the next ship the other way can go straight in; a
## ship the same way has to wait step_seconds while it's turned around. With
## ships waiting on both sides, shared chambers alternate direction. A ship
## that finishes an each_way chamber stays in it until it has the next one if
## that one is each_way too and at most hold_chamber_nm on.
##
## Convoys: ships wait at an anchorage at the canal's entrance (engines off)
## until the next convoy leaves (every convoy_interval_s, both ways at once),
## paying the toll as it does; late ships can still join within
## convoy_grace_s. Convoy ships enter one after another, fastest first, at
## speed_factor of their speed, keeping convoy_spacing_nm behind the ship
## ahead in the single-lane stretches (they can pass in the doubled ones). A
## ship won't enter a single-lane stretch while a ship the other way is in it.
##
## Tolls: cargo ships pay each canal's toll as they enter it (with a convoy,
## as it leaves), and wait for the money if they can't; recovery boats go free.

const RESERVED := "reserved"
const QUEUED := "queued"
const TOLL := "toll"
const ANCHORED := "anchored"
const CONVOY := "convoy"

var _state: Node  # GameState
## Slot key -> the ship in it or heading into it.
var _slot_ships := {}
## Shared slot key -> true if its water is at the level for a forward ship.
var _slot_sides := {}
## Shared slot key -> seconds left turning it around (filling or emptying it empty).
var _slot_turns := {}
## Line key -> ships waiting for that chamber that way, first in line first.
var _lines := {}
## "canal/chamber" -> the way (true = forward) the chamber was last given to.
var _last_ways := {}
## Convoy key ("canal/f" or "canal/b") -> ships at anchor, in arrival order.
var _anchored := {}
## Convoy key -> ships of the convoy that has left, waiting their turn to enter.
var _released := {}
## Convoy key -> play_time the last convoy left.
var _departures := {}


func _init(state: Node) -> void:
	_state = state


func clear() -> void:
	_slot_ships.clear()
	_slot_sides.clear()
	_slot_turns.clear()
	_lines.clear()
	_last_ways.clear()
	_anchored.clear()
	_released.clear()
	_departures.clear()


# --- Every frame -------------------------------------------------------------

## Turns chambers around and sends convoys off.
func step(delta: float) -> void:
	for key: String in _slot_turns.keys():
		_slot_turns[key] = float(_slot_turns[key]) - delta
		if _slot_turns[key] <= 0.0:
			_slot_turns.erase(key)
	for canal in GameData.canals:
		if canal.get("type", "") != "convoy":
			continue
		var interval := float(canal.get("convoy_interval_s", 90))
		var now: float = _state.play_time
		if floori(now / interval) > floori((now - delta) / interval):
			for forward: bool in [true, false]:
				_depart(canal, forward)
		for forward: bool in [true, false]:
			_enter_next(canal, forward)


## True while a ship is held where it is this frame: in a lock chamber, in line
## at its stop, waiting for toll money, or at anchor for a convoy.
func hold(ship: Ship, delta: float) -> bool:
	if ship.lock_time >= 0.0:
		return _hold_in_chamber(ship, delta)
	match ship.canal_state:
		TOLL:
			var crossing := GameData.crossing_ahead(ship.from_port, ship.to_port, ship.traveled_nm)
			if crossing.is_empty() or crossing.canal.get("type", "") == "convoy":
				return true  # Tries again when the next convoy leaves.
			return not _pay_toll(ship, crossing.canal)
		QUEUED:
			if _take(ship, ship.canal_step):
				return false
			return ship.traveled_nm >= _line_stop(ship) - 0.001
		ANCHORED, CONVOY:
			return true
	return false


## How far a ship sailing toward `target` (nm along its lane) may go.
func limit(ship: Ship, target: float) -> float:
	if not ship.leg_has_canal():  # Most legs: nothing to check.
		return target
	var from := ship.traveled_nm
	var crossing := GameData.crossing_ahead(ship.from_port, ship.to_port, from)
	if crossing.is_empty():
		return target
	var canal: Dictionary = crossing.canal
	# The entrance: pay the toll, or drop anchor for a convoy.
	if not ship.canals_entered.has(canal.id) and from <= crossing.start_nm + 0.001 and target >= crossing.start_nm:
		if canal.get("type", "") == "convoy":
			_arrive_at_anchorage(ship, crossing)
			return crossing.start_nm
		if not _pay_toll(ship, canal):
			ship.canal_state = TOLL
			_state.ship_changed.emit(ship)
			return crossing.start_nm
	if canal.get("type", "") == "convoy":
		return _limit_in_convoy(ship, crossing, target)
	return _limit_at_locks(ship, target)


## Frees any chamber a ship holds and takes it out of every line, anchorage and convoy.
func leave(ship: Ship) -> void:
	for key: String in _slot_ships.keys():
		if _slot_ships[key] == ship:
			_slot_ships.erase(key)
	for list: Dictionary in [_lines, _anchored, _released]:
		for ships: Array in list.values():
			ships.erase(ship)
	ship.lock_time = -1.0
	ship.canal_state = ""
	ship.lock_slot = ""


## Sets up a ship's canal state for the leg or job segment it's starting (which
## may start partway along its lane, past some chambers and entrances).
func start_leg(ship: Ship) -> void:
	leave(ship)
	ship.canal_step = 0
	ship.canals_entered.clear()
	for chamber: Dictionary in GameData.lane_chambers(ship.from_port, ship.to_port):
		if chamber.mile < ship.traveled_nm - 0.001:
			ship.canal_step += 1
	for crossing: Dictionary in GameData.canal_crossings(ship.from_port, ship.to_port):
		if ship.traveled_nm > crossing.start_nm + 0.001:
			ship.canals_entered.append(crossing.canal.id)


## True while a ship is between a canal's entrance and exit, or held up at one
## (no breakdowns there).
func in_canal(ship: Ship) -> bool:
	if ship.is_docked() or ship.from_port.is_empty():
		return false
	if not ship.canal_state.is_empty() or ship.lock_time >= 0.0:
		return true
	return not GameData.crossing_at(ship.from_port, ship.to_port, ship.traveled_nm).is_empty()


# --- Locks ---------------------------------------------------------------------

func _hold_in_chamber(ship: Ship, delta: float) -> bool:
	var chambers := GameData.lane_chambers(ship.from_port, ship.to_port)
	var here: Dictionary = chambers[ship.canal_step - 1]
	ship.lock_time += delta
	if ship.lock_time < float(here.canal.get("step_seconds", 3)):
		return true
	if _stay_for_next(ship) and not _take(ship, ship.canal_step):
		return true
	_free_slot(ship, here)
	ship.lock_time = -1.0
	_state.ship_changed.emit(ship)
	return false


## Sails a ship up to its next chamber: into it if it has it reserved (and it's
## ready), otherwise up to its place in line.
func _limit_at_locks(ship: Ship, target: float) -> float:
	var from := ship.traveled_nm
	var chambers := GameData.lane_chambers(ship.from_port, ship.to_port)
	var step := ship.canal_step
	if not _chamber_ahead(ship, step):
		return target
	var chamber: Dictionary = chambers[step]
	if ship.canal_state.is_empty():
		var in_line := _sailing_in_line(_lines.get(_line_key(chamber), []), null)
		if target < chamber.mile - _spacing(chamber.canal) * (in_line + 1):
			return target
		_take(ship, step)
	if ship.canal_state == QUEUED:
		return maxf(from, minf(target, _line_stop(ship)))
	if _slot_turns.has(_slot_key(ship, chamber)):
		return maxf(from, minf(target, chamber.mile - _spacing(chamber.canal)))
	if target < chamber.mile:
		return target
	ship.canal_step += 1
	ship.lock_time = 0.0
	ship.canal_state = ""
	_state.ship_changed.emit(ship)
	return chamber.mile


## Reserves the chamber at `step` for a ship if it's first in line, it's its
## way's turn, and a slot is free (turning a shared one around if it's at the
## wrong level); otherwise puts it in line. Returns true if reserved.
func _take(ship: Ship, step: int) -> bool:
	var chambers := GameData.lane_chambers(ship.from_port, ship.to_port)
	var chamber: Dictionary = chambers[step]
	var canal: Dictionary = chamber.canal
	var forward: bool = chamber.forward
	var line: Array = _lines.get_or_add(_line_key(chamber), [])
	if not line.has(ship):
		line.append(ship)
		ship.canal_state = QUEUED
		ship.canal_queue_since = _state.play_time
		_state.ship_changed.emit(ship)
	if line[0] != ship:
		return false
	var shared := _is_shared(chamber)
	var way_key := "%s/%d" % [canal.id, chamber.index]
	if shared and _last_ways.get(way_key, not forward) == forward \
			and not _lines.get(GameData.line_key(canal.id, chamber.index, not forward), []).is_empty():
		return false  # Ships are waiting the other way: it's their turn.
	var slot := ""
	if not shared:
		slot = "f" if forward else "b"
		if _slot_ships.has(GameData.slot_key(canal.id, chamber.index, slot)):
			return false
	else:
		var turn_slot := ""
		for candidate in GameData.chamber_slots(canal, chamber):
			var key := GameData.slot_key(canal.id, chamber.index, candidate)
			if _slot_ships.has(key) or _slot_turns.has(key):
				continue
			if _slot_sides.get(key, true) == forward:
				slot = candidate
				break
			if turn_slot.is_empty():
				turn_slot = candidate
		if slot.is_empty() and not turn_slot.is_empty():
			slot = turn_slot
			var key := GameData.slot_key(canal.id, chamber.index, slot)
			_slot_turns[key] = float(canal.get("step_seconds", 3))
			_slot_sides[key] = forward
		if slot.is_empty():
			return false
	line.erase(ship)
	_slot_ships[GameData.slot_key(canal.id, chamber.index, slot)] = ship
	_last_ways[way_key] = forward
	ship.lock_slot = slot
	ship.canal_state = RESERVED
	_state.ship_changed.emit(ship)
	return true


## Frees the slot a ship is leaving; a shared chamber is left at the level for
## the other way.
func _free_slot(ship: Ship, chamber: Dictionary) -> void:
	var key := _slot_key(ship, chamber)
	if _slot_ships.get(key) == ship:
		_slot_ships.erase(key)
		if _is_shared(chamber):
			_slot_sides[key] = not chamber.forward


## True if the ship stays in its (each-way) chamber until it has the next one:
## that one is each-way too, in the same canal, and close by.
func _stay_for_next(ship: Ship) -> bool:
	var step := ship.canal_step
	if not _chamber_ahead(ship, step):
		return false
	var chambers := GameData.lane_chambers(ship.from_port, ship.to_port)
	var here: Dictionary = chambers[step - 1]
	var next: Dictionary = chambers[step]
	if _is_shared(here) or _is_shared(next) or next.canal != here.canal:
		return false
	return next.mile - here.mile <= float(here.canal.get("hold_chamber_nm", 3.0))


## True if the lane has a chamber at this step before the ship's stretch ends
## (a recovery boat's job segment can end partway along a lane).
func _chamber_ahead(ship: Ship, step: int) -> bool:
	var chambers := GameData.lane_chambers(ship.from_port, ship.to_port)
	var end := ship.segment_end if ship.is_on_job() else ship.leg_length()
	return step < chambers.size() and chambers[step].mile < end


## Where a ship in line stops: queue_spacing_nm behind each ship ahead of it
## that's still sailing (ships waiting in the chamber before don't count).
func _line_stop(ship: Ship) -> float:
	var chamber: Dictionary = GameData.lane_chambers(ship.from_port, ship.to_port)[ship.canal_step]
	var ahead := _sailing_in_line(_lines.get(_line_key(chamber), []), ship)
	return chamber.mile - _spacing(chamber.canal) * (ahead + 1)


static func _sailing_in_line(line: Array, before: Ship) -> int:
	var count := 0
	for other: Ship in line:
		if other == before:
			break
		if other.lock_time < 0.0:
			count += 1
	return count


static func _is_shared(chamber: Dictionary) -> bool:
	return chamber.canal.locks[chamber.lock].get("lanes", "each_way") == "shared"


static func _line_key(chamber: Dictionary) -> String:
	return GameData.line_key(chamber.canal.id, chamber.index, chamber.forward)


## The slot a ship uses in a chamber: its way's lane, or the shared chamber it reserved.
static func _slot_key(ship: Ship, chamber: Dictionary) -> String:
	var slot := ship.lock_slot
	if not _is_shared(chamber):
		slot = "f" if chamber.forward else "b"
	return GameData.slot_key(chamber.canal.id, chamber.index, slot)


static func _spacing(canal: Dictionary) -> float:
	return float(canal.get("queue_spacing_nm", canal.get("convoy_spacing_nm", 1.6)))


# --- Convoys -------------------------------------------------------------------

static func _convoy_key(canal: Dictionary, forward: bool) -> String:
	return "%s/%s" % [canal.id, "f" if forward else "b"]


## A ship reaching the canal entrance drops anchor, or joins the convoy that
## has just left if it's within the grace time.
func _arrive_at_anchorage(ship: Ship, crossing: Dictionary) -> void:
	var canal: Dictionary = crossing.canal
	var key := _convoy_key(canal, crossing.forward)
	var since_departure: float = _state.play_time - float(_departures.get(key, -INF))
	ship.canal_queue_since = _state.play_time
	if since_departure <= float(canal.get("convoy_grace_s", 10)) and _pay_toll(ship, canal):
		ship.canal_state = CONVOY
		_released.get_or_add(key, []).append(ship)
	else:
		ship.canal_state = ANCHORED
		_anchored.get_or_add(key, []).append(ship)
	_state.ship_changed.emit(ship)


## A convoy leaves: every ship at anchor that can pay its toll joins it,
## fastest first; the rest wait at anchor for the next one.
func _depart(canal: Dictionary, forward: bool) -> void:
	var key := _convoy_key(canal, forward)
	_departures[key] = _state.play_time
	var waiting: Array = _anchored.get(key, []).duplicate()
	waiting.sort_custom(func(a: Ship, b: Ship) -> bool: return a.speed() > b.speed())
	var still_waiting := []
	var released: Array = _released.get_or_add(key, [])
	for ship: Ship in waiting:
		if _pay_toll(ship, canal):
			ship.canal_state = CONVOY
			ship.canal_queue_since = _state.play_time + released.size() * 0.001
			released.append(ship)
		else:
			ship.canal_state = TOLL
			still_waiting.append(ship)
		_state.ship_changed.emit(ship)
	_anchored[key] = still_waiting


## The next convoy ship enters once the ship before it is convoy_spacing_nm in.
func _enter_next(canal: Dictionary, forward: bool) -> void:
	var released: Array = _released.get(_convoy_key(canal, forward), [])
	if released.is_empty():
		return
	var ship: Ship = released[0]
	var crossing := GameData.crossing_ahead(ship.from_port, ship.to_port, ship.traveled_nm)
	if crossing.is_empty():
		released.pop_front()
		return
	var entrance := _progress(crossing, GameData.canal_s(crossing, crossing.start_nm))
	for other: Ship in _moving_in(canal, forward):
		var progress := _progress_of(other)
		if progress >= entrance - 0.001 and progress < entrance + _spacing(canal):
			return
	released.pop_front()
	ship.canal_state = ""
	_state.ship_changed.emit(ship)


## Moves a convoy ship along: behind the ship ahead in single-lane stretches,
## and not into a single-lane stretch with a ship coming the other way.
func _limit_in_convoy(ship: Ship, crossing: Dictionary, target: float) -> float:
	var canal: Dictionary = crossing.canal
	if target > crossing.end_nm:
		target = maxf(ship.traveled_nm, target)
	var s0 := GameData.canal_s(crossing, ship.traveled_nm)
	var s1 := GameData.canal_s(crossing, minf(target, crossing.end_nm))
	var stretch := GameData.single_stretch_entered(canal, s0, s1)
	if not stretch.is_empty() and _oncoming_in(canal, crossing.forward, stretch):
		var boundary: float = stretch[0] if crossing.forward else stretch[1]
		return maxf(ship.traveled_nm, GameData.lane_mile(crossing, boundary) - 0.001)
	var leader := convoy_leader(ship)
	if leader != null:
		var gap := _spacing(canal)
		var leader_s := GameData.canal_s(GameData.crossing_ahead(leader.from_port, leader.to_port, leader.traveled_nm), leader.traveled_nm)
		if GameData.in_single_stretch(canal, s1) or GameData.in_single_stretch(canal, leader_s):
			var max_progress := _progress(crossing, leader_s) - gap
			var max_s := max_progress if crossing.forward else float(canal.path_nm[-1]) - max_progress
			target = minf(target, maxf(ship.traveled_nm, GameData.lane_mile(crossing, max_s)))
	return target


## The nearest ship ahead of a convoy ship in the canal, going the same way, or null.
func convoy_leader(ship: Ship) -> Ship:
	var crossing := GameData.crossing_at(ship.from_port, ship.to_port, ship.traveled_nm)
	if crossing.is_empty() or crossing.canal.get("type", "") != "convoy":
		return null
	var mine := _progress_of(ship)
	var best: Ship = null
	var best_progress := INF
	for other: Ship in _moving_in(crossing.canal, crossing.forward):
		if other == ship:
			continue
		var progress := _progress_of(other)
		if progress > mine and progress < best_progress:
			best = other
			best_progress = progress
	return best


## True if a ship coming the other way is in a single-lane stretch.
func _oncoming_in(canal: Dictionary, forward: bool, stretch: Array) -> bool:
	for other: Ship in _moving_in(canal, not forward):
		var crossing := GameData.crossing_at(other.from_port, other.to_port, other.traveled_nm)
		var s := GameData.canal_s(crossing, other.traveled_nm)
		if s >= stretch[0] and s <= stretch[1]:
			return true
	return false


## The single-lane stretch a convoy ship is waiting to enter because of oncoming
## ships, or [].
func blocked_stretch(ship: Ship) -> Array:
	var crossing := GameData.crossing_at(ship.from_port, ship.to_port, ship.traveled_nm)
	if crossing.is_empty() or crossing.canal.get("type", "") != "convoy" or not ship.canal_state.is_empty():
		return []
	var s0 := GameData.canal_s(crossing, ship.traveled_nm)
	var s1 := s0 + (0.01 if crossing.forward else -0.01)
	var stretch := GameData.single_stretch_entered(crossing.canal, s0, s1)
	if not stretch.is_empty() and _oncoming_in(crossing.canal, crossing.forward, stretch):
		return stretch
	return []


## Ships sailing in a convoy canal one way (entered, not at anchor or waiting to enter).
func _moving_in(canal: Dictionary, forward: bool) -> Array[Ship]:
	var ships: Array[Ship] = []
	for ship: Ship in _state.ships:
		if ship.is_docked() or ship.is_lost() or not ship.canal_state.is_empty() or ship.is_carried():
			continue
		var crossing := GameData.crossing_at(ship.from_port, ship.to_port, ship.traveled_nm)
		if not crossing.is_empty() and crossing.canal == canal and crossing.forward == forward \
				and ship.canals_entered.has(canal.id):
			ships.append(ship)
	return ships


## How far along the canal a ship has come, measured its own way (nm).
static func _progress(crossing: Dictionary, s: float) -> float:
	return s if crossing.forward else float(crossing.canal.path_nm[-1]) - s


func _progress_of(ship: Ship) -> float:
	var crossing := GameData.crossing_at(ship.from_port, ship.to_port, ship.traveled_nm)
	return _progress(crossing, GameData.canal_s(crossing, ship.traveled_nm))


## Seconds until the next convoy leaves (the same moment both ways).
func next_convoy_in(canal: Dictionary) -> float:
	var interval := float(canal.get("convoy_interval_s", 90))
	return interval - fmod(_state.play_time, interval)


func anchored_ships(canal: Dictionary, forward: bool) -> Array:
	return _anchored.get(_convoy_key(canal, forward), [])


## Ships of the convoy that has left, still waiting their turn to enter.
func released_ships(canal: Dictionary, forward: bool) -> Array:
	return _released.get(_convoy_key(canal, forward), [])


## Ships sailing through a convoy canal one way, furthest along first.
func convoy_ships(canal: Dictionary, forward: bool) -> Array[Ship]:
	var ships := _moving_in(canal, forward)
	ships.sort_custom(func(a: Ship, b: Ship) -> bool: return _progress_of(a) > _progress_of(b))
	return ships


# --- Tolls ---------------------------------------------------------------------

## Charges a cargo ship a canal's toll. Returns false if it can't afford it
## yet. Recovery boats go free.
func _pay_toll(ship: Ship, canal: Dictionary) -> bool:
	if not ship.is_recovery():
		var toll: int = _state.cargo_toll(ship, canal)
		if _state.money < toll:
			return false
		_state.money -= toll
		_state.record_toll(ship, canal, toll)
		ship.leg_toll += toll
		_state.canal_entered.emit(ship, canal, toll)
	if not ship.canals_entered.has(canal.id):
		ship.canals_entered.append(canal.id)
	if ship.canal_state == TOLL:
		ship.canal_state = ""
	_state.ship_changed.emit(ship)
	return true


# --- Loading -------------------------------------------------------------------

## Rebuilds who holds and waits for each chamber, anchorage and convoy from the
## ships' own state, after loading. Saves from before canals work out each
## ship's progress from where it is.
func rebuild(ships: Array[Ship]) -> void:
	clear()
	var waiting: Array[Ship] = []
	for ship in ships:
		if ship.is_docked() or ship.is_lost() or ship.from_port.is_empty():
			ship.canal_step = 0
			ship.lock_time = -1.0
			ship.canal_state = ""
			continue
		var chambers := GameData.lane_chambers(ship.from_port, ship.to_port)
		if ship.canal_step < 0 or ship.canal_step > chambers.size():
			start_leg(ship)
			continue
		if ship.lock_time >= 0.0 and ship.canal_step > 0:
			_slot_ships[_slot_key(ship, chambers[ship.canal_step - 1])] = ship
		if ship.canal_state == RESERVED and ship.canal_step < chambers.size():
			_slot_ships[_slot_key(ship, chambers[ship.canal_step])] = ship
		elif ship.canal_state in [QUEUED, ANCHORED, CONVOY, TOLL]:
			waiting.append(ship)
	waiting.sort_custom(func(a: Ship, b: Ship) -> bool: return a.canal_queue_since < b.canal_queue_since)
	for ship in waiting:
		if ship.canal_state == QUEUED:
			var chambers := GameData.lane_chambers(ship.from_port, ship.to_port)
			if ship.canal_step < chambers.size():
				_lines.get_or_add(_line_key(chambers[ship.canal_step]), []).append(ship)
			continue
		var crossing := GameData.crossing_ahead(ship.from_port, ship.to_port, ship.traveled_nm)
		if crossing.is_empty():
			ship.canal_state = ""
		elif crossing.canal.get("type", "") == "convoy":
			var key := _convoy_key(crossing.canal, crossing.forward)
			(_released if ship.canal_state == CONVOY else _anchored).get_or_add(key, []).append(ship)


# --- For the map and popups ------------------------------------------------------

## The ship in (or heading into) a chamber slot, or null.
func slot_ship(canal_id: String, chamber_index: int, slot: String) -> Ship:
	return _slot_ships.get(GameData.slot_key(canal_id, chamber_index, slot))


## Ships waiting for a chamber one way, first in line first.
func line(canal_id: String, chamber_index: int, forward: bool) -> Array:
	return _lines.get(GameData.line_key(canal_id, chamber_index, forward), [])


## A ship's place (1 = first) in line for its next chamber, or 0.
func line_position(ship: Ship) -> int:
	if ship.canal_state != QUEUED:
		return 0
	var chambers := GameData.lane_chambers(ship.from_port, ship.to_port)
	if ship.canal_step >= chambers.size():
		return 0
	return _lines.get(_line_key(chambers[ship.canal_step]), []).find(ship) + 1


## A slot's water level, 0 (low) to 1 (high), for drawing: rising or falling
## with a ship in it or while it's turned around, otherwise at rest.
func slot_level(canal: Dictionary, chamber: Dictionary, slot: String) -> float:
	var key := GameData.slot_key(canal.id, chamber.index, slot)
	var rises_forward: bool = canal.locks[chamber.lock].rises_forward
	var step := float(canal.get("step_seconds", 3))
	var ship: Ship = _slot_ships.get(key)
	if ship != null and ship.lock_chamber().get("index", -1) == chamber.index and ship.lock_chamber().canal == canal:
		var forward: bool = ship.lock_chamber().forward
		var t := clampf(ship.lock_time / step, 0.0, 1.0)
		return t if rises_forward == forward else 1.0 - t
	var forward_ready: bool = _slot_sides.get(key, true) if slot not in ["f", "b"] else slot == "f"
	# Ready for a forward ship means at the level it enters at.
	var level := 0.0 if rises_forward == forward_ready else 1.0
	if _slot_turns.has(key):
		var t := 1.0 - clampf(float(_slot_turns[key]) / step, 0.0, 1.0)
		return lerpf(1.0 - level, level, t)
	return level if slot not in ["f", "b"] else 0.5


## Seconds left turning a shared slot around, or 0.
func slot_turn(canal_id: String, chamber_index: int, slot: String) -> float:
	return float(_slot_turns.get(GameData.slot_key(canal_id, chamber_index, slot), 0.0))
