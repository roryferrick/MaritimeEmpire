# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Docks
extends RefCounted
## Each port's berths: a cargo ship arriving queues for one that fits it
## (first come, first served, every company's ships together), comes
## alongside, does its stop there and pulls out (see
## GameState._advance_docked()); ships waiting or idle in port lie at the
## anchorage. A port's berths go by its size band (game_config docks berths),
## or hub_berths at a port with any company's HQ or hub: each a kind (see
## berth_kinds()), so at a Large or Giant port the biggest ships share its one
## big berth while the rest use the others; when no big ship is waiting, two
## smaller ships short enough to lie end to end can share it (see shares()).


var _state: Node  # GameState
## Port id -> {berth index: Ship, or for a shared big berth [Ship or null,
## Ship or null], one per half}.
var _taken := {}
## Port id -> ships waiting for a berth there, first come first.
var _queues := {}
## Port id -> how many times its berths or queue have changed (see claim()).
var _changes := {}
## A ship that couldn't get a berth tries again at once when something changes
## at its port, and otherwise only every this long (s of play).
const CLAIM_RETRY_S := 1.0
## A ship's bow sticks out this many times its width past its map_size length
## (as drawn: MapView.BOW_LENGTH_FACTOR).
const BOW_LENGTH_FACTOR := 0.6
## Room left between two smaller ships sharing a big berth (map_size units).
const SHARE_GAP := 1.7

static var _big_length := -1.0
static var _shortest := -1.0


func _init(state: Node) -> void:
	_state = state


static func settings() -> Dictionary:
	return GameData.config.get("docks", {})


## A port's berths in order round its marina, a letter each: "s" for the
## smaller ships (those that can dock at a Small port), "m" for any ship a
## Medium port takes, "B" a big berth only for the biggest ships (see
## needs_big_berth()); at a hub port the B's are its slip's two walls.
func berth_kinds(port_id: String) -> String:
	if has_hub(port_id):
		return str(settings().get("hub_berths", "sssBBsss"))
	return str(settings().get("berths", {}).get(_state.port_sizes.band(port_id), "ss"))


## How many berths a port has now.
func berth_count(port_id: String) -> int:
	return berth_kinds(port_id).length()


## True if a model is one of the biggest ships, those that need a Medium or
## Large port (or an HQ or hub): they moor at a big berth (or a Medium port's).
static func needs_big_berth(model: Dictionary) -> bool:
	return not str(model.get("min_port", "")).is_empty()


## True if a ship of a model can moor at a berth of a kind (see berth_kinds()).
static func berth_fits(kind: String, model: Dictionary) -> bool:
	match kind:
		"B":
			return needs_big_berth(model)
		"s":
			return not needs_big_berth(model)
	return true


## A model's length bow to stern, in map_size units.
static func model_length(model: Dictionary) -> float:
	var dims: Array = model.get("map_size", [14, 6])
	return float(dims[0]) + float(dims[1]) * BOW_LENGTH_FACTOR


## How long a big berth is (map_size units): the longest ship it takes.
static func big_berth_length() -> float:
	if _big_length < 0.0:
		_big_length = 0.0
		for model: Dictionary in GameData.ship_models:
			if needs_big_berth(model):
				_big_length = maxf(_big_length, model_length(model))
	return _big_length


## True if a port's berth is a big berth two smaller ships can share: a Large
## or Giant port's (not a hub's slip).
func shares(port_id: String, berth: int) -> bool:
	var kinds := berth_kinds(port_id)
	return berth >= 0 and berth < kinds.length() and kinds[berth] == "B" and not has_hub(port_id)


## True if a cargo ship of a model could take half of a shared big berth
## beside a ship of another model (or, other_model {}, beside the shortest
## that could).
static func half_fits(model: Dictionary, other_model := {}) -> bool:
	if not _shares_at_all(model):
		return false
	var other := model_length(other_model) if not other_model.is_empty() else _shortest_sharer()
	return model_length(model) + other + SHARE_GAP <= big_berth_length()


static func _shares_at_all(model: Dictionary) -> bool:
	return not needs_big_berth(model) and model.has("cargo")


## The shortest ship that could share a big berth (map_size units).
static func _shortest_sharer() -> float:
	if _shortest < 0.0:
		_shortest = INF
		for model: Dictionary in GameData.ship_models:
			if _shares_at_all(model):
				_shortest = minf(_shortest, model_length(model))
	return _shortest


## True if any company has its HQ or a hub at a port (it's built as a hub port).
func has_hub(port_id: String) -> bool:
	for each: Company in _state.all_companies():
		if each.hub_at(port_id) != null:
			return true
	return false


## A ship arriving for a stop joins the port's queue.
func join_queue(ship: Ship) -> void:
	var queue: Array = _queues.get_or_add(ship.docked_at, [])
	if not queue.has(ship):
		queue.append(ship)


## Gives the ship a free berth that fits it, unless a ship ahead of it in its
## port's queue is waiting for that one too: true if it got one. A smaller ship
## tries the berths for its size first, then half of a shared big berth.
func claim(ship: Ship) -> bool:
	var port := ship.docked_at
	# Nothing has changed at the port since it last tried (no berth freed, no
	# ship taken in or out of the queue): no need to look again (but once in a
	# while anyway, as a port's berths change with its size and hubs).
	var stamp := int(_changes.get(port, 0))
	if ship.claim_stamp == stamp and ship.claim_port == port and _state.play_time < ship.claim_retry:
		return false
	ship.claim_stamp = stamp
	ship.claim_port = port
	ship.claim_retry = _state.play_time + CLAIM_RETRY_S
	var queue: Array = _queues.get_or_add(port, [])
	var at := queue.find(ship)
	if at < 0:
		at = queue.size()
		queue.append(ship)
	var kinds := berth_kinds(port)
	var taken: Dictionary = _taken.get_or_add(port, {})
	var model := ship.model()
	for i in kinds.length():
		var kind := kinds[i]
		if taken.has(i) or not berth_fits(kind, model) or _waited(queue, at, kind, false):
			continue
		taken[i] = ship
		_take(ship, port, i, -1)
		return true
	if not half_fits(model):
		return false
	for i in kinds.length():
		if not shares(port, i):
			continue
		var held: Variant = taken.get(i)
		if held is Ship:
			continue  # A big ship has it all.
		if held == null:
			# A free big berth: not if a ship that came before is waiting for it.
			if _waited(queue, at, kinds[i], true):
				continue
			taken[i] = [ship, null]
			_take(ship, port, i, 0)
			return true
		var pair: Array = held
		var free := pair.find(null)
		if free < 0:
			continue
		var other: Ship = pair[1 - free]
		if not half_fits(model, other.model()) or _waited(queue, at, kinds[i], true, other):
			continue
		pair[free] = ship
		_take(ship, port, i, free)
		return true
	return false


## True if a ship ahead in the queue (before at) is waiting for a berth of a
## kind: first come first served for each berth. Sharing, counting the smaller
## ships that could take half of it (beside other, if it has the other half)
## as well as those it fits.
func _waited(queue: Array, at: int, kind: String, sharing: bool, other: Ship = null) -> bool:
	for k in at:
		var model := (queue[k] as Ship).model()
		if other != null:
			if half_fits(model, other.model()):
				return true
		elif berth_fits(kind, model) or sharing and half_fits(model):
			return true
	return false


func _take(ship: Ship, port: String, berth: int, half: int) -> void:
	_changes[port] = int(_changes.get(port, 0)) + 1
	ship.berth = berth
	ship.berth_half = half
	var queue: Array = _queues.get(port, [])
	var at := queue.find(ship)
	if at >= 0:
		queue.remove_at(at)


## The ship leaves its berth (or the queue).
func release(ship: Ship) -> void:
	for port: String in _taken:
		var taken: Dictionary = _taken[port]
		if ship.berth < 0 or not taken.has(ship.berth):
			continue
		var held: Variant = taken[ship.berth]
		if held is Ship and held == ship:
			taken.erase(ship.berth)
			_changes[port] = int(_changes.get(port, 0)) + 1
		elif held is Array and (held as Array).has(ship):
			var pair: Array = held
			pair[pair.find(ship)] = null
			if pair.count(null) == 2:
				taken.erase(ship.berth)
			_changes[port] = int(_changes.get(port, 0)) + 1
	for port: String in _queues:
		var queue: Array = _queues[port]
		var at := queue.find(ship)
		if at >= 0:
			queue.remove_at(at)
			_changes[port] = int(_changes.get(port, 0)) + 1
	ship.berth = -1
	ship.berth_half = -1


## Where a ship is in its port's queue (1 for next in), or 0 if it isn't
## queuing: counting only the ships ahead of it waiting for the same berths
## (at a Large or Giant port, the biggest ships queue for its big berth apart).
func queue_position(ship: Ship) -> int:
	var queue: Array = _queues.get(ship.docked_at, [])
	var at := queue.find(ship)
	if at < 0:
		return 0
	var kinds := berth_kinds(ship.docked_at)
	var place := 1
	for other: Ship in queue.slice(0, at):
		for kind in kinds:
			if berth_fits(kind, ship.model()) and berth_fits(kind, other.model()):
				place += 1
				break
	return place


## The ship in a port's berth (the first of two sharing it), or null.
func occupant(port_id: String, berth: int) -> Ship:
	var held: Variant = _taken.get(port_id, {}).get(berth)
	if held is Array:
		for each: Variant in held:
			if each != null:
				return each
		return null
	return held


## Rebuilds who's where from the ships (after loading a game): ships keep the
## berths they had (one that's gone, or taken twice, queues again), and
## waiting ships queue in the order they arrived.
func rebuild(ships: Array[Ship]) -> void:
	_taken.clear()
	_queues.clear()
	var waiting: Array[Ship] = []
	for ship in ships:
		if ship.docked_at.is_empty():
			ship.berth = -1
			ship.berth_half = -1
			continue
		if ship.berth >= 0:
			var taken: Dictionary = _taken.get_or_add(ship.docked_at, {})
			var kinds := berth_kinds(ship.docked_at)
			if ship.berth_half < 0:
				if ship.berth < kinds.length() and berth_fits(kinds[ship.berth], ship.model()) and not taken.has(ship.berth):
					taken[ship.berth] = ship
					continue
			elif ship.berth_half <= 1 and shares(ship.docked_at, ship.berth) and half_fits(ship.model()):
				var held: Variant = taken.get(ship.berth)
				if held == null:
					var pair := [null, null]
					pair[ship.berth_half] = ship
					taken[ship.berth] = pair
					continue
				if held is Array and (held as Array)[ship.berth_half] == null:
					(held as Array)[ship.berth_half] = ship
					continue
			ship.berth = -1
			ship.berth_half = -1
			if ship.berth_phase != Ship.BERTH_OUT:
				ship.berth_phase = Ship.BERTH_WAIT
		if ship.berth_phase == Ship.BERTH_WAIT or ship.berth_phase == Ship.BERTH_IN:
			ship.berth_phase = Ship.BERTH_WAIT
			waiting.append(ship)
		elif ship.berth_phase == Ship.BERTH_OUT:
			ship.berth_phase = Ship.BERTH_NONE  # Lost its berth: it's out at the anchorage.
	waiting.sort_custom(func(a: Ship, b: Ship) -> bool: return a.berth_since < b.berth_since)
	for ship in waiting:
		join_queue(ship)
