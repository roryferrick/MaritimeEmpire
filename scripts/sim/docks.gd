class_name Docks
extends RefCounted
## Each port's berths: a cargo ship arriving queues for one (first come, first
## served, every company's ships together), comes alongside, does its stop
## there and pulls out (see GameState._advance_docked()); ships waiting or
## idle in port lie at the anchorage. How many berths a port has goes by its
## size band (game_config docks berths) plus one for every hub_levels_per_berth
## levels of a hub there (an HQ's count hq_multiplier times).


var _state: Node  # GameState
## Port id -> {berth index: Ship}.
var _taken := {}
## Port id -> ships waiting for a berth there, first come first.
var _queues := {}


func _init(state: Node) -> void:
	_state = state


static func settings() -> Dictionary:
	return GameData.config.get("docks", {})


## How many berths a port has now: by its size band, plus a hub's.
func berth_count(port_id: String) -> int:
	var base := int(settings().get("berths", {}).get(_state.port_sizes.band(port_id), 2))
	return base + extra_berths(port_id)


## The berths a hub (or HQ) at a port adds: the most any company's does.
func extra_berths(port_id: String) -> int:
	var per := maxi(int(settings().get("hub_levels_per_berth", 10)), 1)
	var best := 0
	for each: Company in _state.all_companies():
		var hub: Hub = each.hub_at(port_id)
		if hub != null:
			var multiplier := float(Hub.settings().get("hq_multiplier", 1.5)) if hub.is_hq else 1.0
			best = maxi(best, floori(hub.level / float(per) * multiplier))
	return best


## A ship arriving for a stop joins the port's queue.
func join_queue(ship: Ship) -> void:
	var queue: Array = _queues.get_or_add(ship.docked_at, [])
	if not queue.has(ship):
		queue.append(ship)


## Gives the ship a free berth if it's first in its port's queue: true if it got one.
func claim(ship: Ship) -> bool:
	var port := ship.docked_at
	var queue: Array = _queues.get(port, [])
	if queue.is_empty() or queue[0] != ship:
		if not queue.has(ship):
			queue.append(ship)
		return false
	var taken: Dictionary = _taken.get_or_add(port, {})
	for i in berth_count(port):
		if not taken.has(i):
			taken[i] = ship
			ship.berth = i
			queue.pop_front()
			return true
	return false


## The ship leaves its berth (or the queue).
func release(ship: Ship) -> void:
	for port: String in _taken:
		var taken: Dictionary = _taken[port]
		if ship.berth >= 0 and taken.get(ship.berth) == ship:
			taken.erase(ship.berth)
	for port: String in _queues:
		(_queues[port] as Array).erase(ship)
	ship.berth = -1


## Where a ship is in its port's queue (1 for next in), or 0 if it isn't queuing.
func queue_position(ship: Ship) -> int:
	return (_queues.get(ship.docked_at, []) as Array).find(ship) + 1


## The ship in a port's berth, or null.
func occupant(port_id: String, berth: int) -> Ship:
	return _taken.get(port_id, {}).get(berth)


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
			continue
		if ship.berth >= 0:
			var taken: Dictionary = _taken.get_or_add(ship.docked_at, {})
			if ship.berth < berth_count(ship.docked_at) and not taken.has(ship.berth):
				taken[ship.berth] = ship
				continue
			ship.berth = -1
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
