class_name Icebreaking
extends RefCounted
## Icebreakers and the ice areas they work (game_config icebreaking).
##
## An ice area is covered by circles and is in season while its seasonal
## closure or ice zone is (see Seasons). With an icebreaker stationed there it's
## open (open()): its closure no longer stops ships, but a ship reaching the
## ice edge (entry_mile()), or leaving a port in the ice, waits for the
## icebreaker, which comes and leads it, with up to convoy_size others on the
## same lane, through the ice. GameState moves the ships; this works out the
## areas, where lanes meet the ice, and which ships make up the next convoy.

## How often (seconds of play) refresh() works the open areas out again.
const REFRESH_S := 0.25

var _state: Node  # GameState
var _edges := {}  # "area/FROM-TO" -> [entry mile, exit mile] (see _edge_miles())
var _open := {}  # Area id -> open(), as of the last refresh().
var _any_open_closure := false  # Any open area with a closure (one that leads convoys).
var _season_day := -1  # in_season() results, kept for a calendar day.
var _season_cache := {}
var _refreshed_at := -INF  # play_time of the last refresh().


func _init(state: Node) -> void:
	_state = state


func _settings() -> Dictionary:
	return GameData.config.get("icebreaking", {})


func areas() -> Array:
	return _settings().get("areas", [])


func area(area_id: String) -> Dictionary:
	for item: Dictionary in areas():
		if item.id == area_id:
			return item
	return {}


func convoy_size() -> int:
	return int(_settings().get("convoy_size", 4))


func gap_nm() -> float:
	return float(_settings().get("gap_nm", 3.0))


## The share of the slower of an icebreaker and its slowest ship a convoy
## makes through the ice.
func escort_factor(icebreaker: Ship) -> float:
	return float(_settings().get("escort_speed", {}).get(str(icebreaker.model().get("icebreaker", "diesel")), 0.6))


## True while an area's ice is in season (seasonal closures active, and its
## closure or ice zone in season).
func in_season(item: Dictionary) -> bool:
	if not _state.seasonal.active():
		return false
	var now: int = _state.calendar_time()
	var day := Seasons._month_day(now)
	if day != _season_day:  # Seasons change by the day, but ships ask every step.
		_season_day = day
		_season_cache.clear()
	if _season_cache.has(item.id):
		return _season_cache[item.id]
	var found := false
	var lists := {closure = _state.seasonal.closures(), zone = _state.seasonal.ice_zones()}
	for key: String in lists:
		if item.has(key):
			for season: Dictionary in lists[key]:
				if season.id == item[key] and Seasons.in_season(season, now):
					found = true
	_season_cache[item.id] = found
	return found


## The icebreakers stationed at an area.
func stationed(area_id: String) -> Array[Ship]:
	var out: Array[Ship] = []
	for ship: Ship in _state.ships:
		if ship.is_icebreaker() and ship.station == area_id:
			out.append(ship)
	return out


## True if an area's ice is in season and an icebreaker is stationed there:
## ships then wait to be led through instead of crawling (or being shut out).
## As of the last refresh().
func open(item: Dictionary) -> bool:
	return _open.get(item.get("id", ""), false)


## Works out which areas are open, once a step (ships ask many times a step).
func refresh(now := false) -> void:
	# Stations and seasons change rarely: every REFRESH_S is plenty (or now,
	# when an icebreaker is stationed).
	if not now and _state.play_time >= _refreshed_at and _state.play_time - _refreshed_at < REFRESH_S:
		return
	_refreshed_at = _state.play_time
	_any_open_closure = false
	var stationed_at := {}
	for ship: Ship in _state.ships:
		if ship.is_icebreaker() and not ship.station.is_empty():
			stationed_at[ship.station] = true
	for item: Dictionary in areas():
		_open[item.id] = stationed_at.has(item.id) and in_season(item)
		if _open[item.id] and item.has("closure"):
			_any_open_closure = true


## The open area a seasonal closure belongs to, or {}: that closure no longer
## stops ships.
func lifting(closure: Dictionary) -> Dictionary:
	for item: Dictionary in areas():
		if item.get("closure", "") == closure.get("id", "") and open(item):
			return item
	return {}


## [speed factor, wear factor] in an ice zone whose fairways an icebreaker
## stationed there keeps open, or [] if none does.
func fairway(zone_id: String) -> Array:
	for item: Dictionary in areas():
		if item.get("zone", "") == zone_id and open(item):
			var eased: Dictionary = _settings().get("fairway", {})
			return [float(eased.get("speed", 0.8)), float(eased.get("wear", 1.1))]
	return []


## The circles ([lon, lat, radius nm]) an area covers: its own, or else its
## closure's (the Arctic routes share theirs).
func circles(item: Dictionary) -> Array:
	if item.has("circles"):
		return item.circles
	for closure: Dictionary in _state.seasonal.closures():
		if closure.id == item.get("closure", ""):
			return closure.get("circles", [])
	return []


## Why a model can't be stationed at an area, or "": the Arctic routes need a
## nuclear icebreaker, and the Great Lakes one that fits the Seaway.
func station_error(item: Dictionary, model: Dictionary) -> String:
	if item.get("needs", "") == "nuclear" and model.get("icebreaker", "") != "nuclear":
		return "Only a nuclear icebreaker can keep the %s open through the Arctic winter." % item.name
	if station_port(item, model, str(item.get("station_ports", [""])[0])).is_empty():
		return "A %s is too big for the St. Lawrence Seaway, so it can't work the Great Lakes." % model.get("name", "")
	return ""


func inside(item: Dictionary, lon_lat: Vector2) -> bool:
	for circle: Array in circles(item):
		if Geo.distance_nm(Vector2(circle[0], circle[1]), lon_lat) <= float(circle[2]):
			return true
	return false


func port_inside(item: Dictionary, port_id: String) -> bool:
	var port := GameData.get_port(port_id)
	return inside(item, Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0))))


## The open area a ship needs leading through on a leg: one its lane enters, or
## starts in. {} if none.
func area_for_leg(from_port: String, to_port: String) -> Dictionary:
	if not _any_open_closure:
		return {}  # The usual case, asked for every ship every step.
	for item: Dictionary in areas():
		# An ice zone stays open anyway: its icebreaker keeps the fairways open
		# instead of leading convoys (see fairway()).
		if item.has("closure") and open(item) and _edge_miles(item, from_port, to_port)[0] >= 0.0:
			return item
	return {}


## Where a lane first enters an area's ice (0 if it starts in it), or -1 if it
## never does.
func entry_mile(item: Dictionary, from_port: String, to_port: String) -> float:
	return _edge_miles(item, from_port, to_port)[0]


## Where a convoy on a lane is let go: its end if the lane ends in the ice,
## otherwise where it leaves the ice after entry_mile().
func escort_end(item: Dictionary, from_port: String, to_port: String) -> float:
	return _edge_miles(item, from_port, to_port)[1]


## [entry mile, release mile] of a lane in an area (see entry_mile() and
## escort_end()), sampled every couple of miles; [-1, -1] if it never enters.
func _edge_miles(item: Dictionary, from_port: String, to_port: String) -> Array:
	var key := "%s/%s-%s" % [item.id, from_port, to_port]
	if _edges.has(key):
		return _edges[key]
	var result := [-1.0, -1.0]
	var lane = GameData.lane(from_port, to_port)
	if lane != null:
		var length: float = lane.length()
		var mile := 0.0
		var step := 2.0
		while mile <= length:
			var here := inside(item, Geo.unproject(lane.sample(mile)[0]))
			if result[0] < 0.0 and here:
				result[0] = mile
			elif result[0] >= 0.0 and not here:
				result[1] = mile
				break
			mile += step
		if result[0] >= 0.0 and result[1] < 0.0:
			result[1] = length
	_edges[key] = result
	return result


## The next convoy for an icebreaker idle in its area: the ship that has waited
## longest for one, and up to convoy_size - 1 more waiting on the same lane in
## the same way (all at the ice edge, or all in the same port). [] if none.
func next_convoy(icebreaker: Ship) -> Array[Ship]:
	var waiting: Array[Ship] = []
	for ship: Ship in _state.ships:
		if ship.ice_wait == icebreaker.station and ship.escort == null and not ship.is_lost():
			waiting.append(ship)
	if waiting.is_empty():
		return []
	waiting.sort_custom(func(a: Ship, b: Ship) -> bool: return a.ice_wait_since < b.ice_wait_since)
	var first := waiting[0]
	var convoy: Array[Ship] = [first]
	for ship in waiting.slice(1):
		if convoy.size() >= convoy_size():
			break
		if ship.is_docked() == first.is_docked() and _same_leg(ship, first):
			convoy.append(ship)
	return convoy


## Where a waiting ship's leg is: [from, to] (a docked ship, the leg it's about
## to sail).
static func waiting_leg(ship: Ship) -> Array:
	return [ship.docked_at, ship.ice_to] if ship.is_docked() else [ship.from_port, ship.to_port]


static func _same_leg(a: Ship, b: Ship) -> bool:
	return waiting_leg(a) == waiting_leg(b)


## The nearest of an area's station ports a model can use, by sea from a port
## (a model too big for the Seaway can't be stationed on the Great Lakes:
## returns "").
func station_port(item: Dictionary, model: Dictionary, from_port: String) -> String:
	var best := ""
	var best_nm := INF
	for port_id: String in item.get("station_ports", []):
		if not model.get("seaway", false) and GameData.get_port(port_id).get("seaway", false):
			continue
		var nm := 0.0 if port_id == from_port else GameData.distance_nm(from_port, port_id)
		if nm < best_nm:
			best_nm = nm
			best = port_id
	return best
