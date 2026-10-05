class_name Seasons
extends RefCounted
## Seasonal closures (game_config seasons), for saves founded with them
## (GameState.seasons), from company level min_company_level (see active()).
##
## A closure shuts a canal's locks or some ports between two dates of every
## year (wrapping past the new year when it starts later in the year than it
## ends). A ship won't start a leg it can't finish before one shuts
## (leg_blocker()); ships already at sea finish. Ice zones stay open but slow
## ships in their season (factors()). Nothing here is saved: it all follows
## the calendar.

const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## How often (seconds of play) a leg is checked against the closures between
## leaving and arriving: about a calendar day.
const LEG_CHECK_S := 72.0

var _state: Node  # GameState
var _enters := {}  # "closure/FROM-TO" -> lane_enters()


func _init(state: Node) -> void:
	_state = state


func _settings() -> Dictionary:
	return GameData.config.get("seasons", {})


func closures() -> Array:
	return _settings().get("closures", [])


func ice_zones() -> Array:
	return _settings().get("ice_zones", [])


## True once closures apply: a save with them, from min_company_level.
func active() -> bool:
	return _state.seasons and _state.company_level() >= int(_settings().get("min_company_level", 1))


## True if a closure or ice zone ({from, to}: [month, day]) is in season at a
## calendar (Unix) time.
static func in_season(item: Dictionary, unix_time: int) -> bool:
	var date := Time.get_datetime_dict_from_unix_time(unix_time)
	var today := int(date.month) * 100 + int(date.day)
	var from := int(item.from[0]) * 100 + int(item.from[1])
	var to := int(item.to[0]) * 100 + int(item.to[1])
	return today >= from and today <= to if from <= to else today >= from or today <= to


## "22 Mar" for a [month, day].
static func date_text(month_day: Array) -> String:
	return "%d %s" % [int(month_day[1]), MONTHS[int(month_day[0]) - 1]]


## The closure shutting a canal at a calendar time, or {}.
func canal_closure(canal_id: String, unix_time: int) -> Dictionary:
	if not active():
		return {}
	for closure: Dictionary in closures():
		if closure.get("canal", "") == canal_id and in_season(closure, unix_time):
			return closure
	return {}


## The closure shutting a port at a calendar time, or {}.
func port_closure(port_id: String, unix_time: int) -> Dictionary:
	if not active():
		return {}
	for closure: Dictionary in closures():
		if closure.get("ports", []).has(port_id) and in_season(closure, unix_time):
			return closure
	return {}


## The closure that would stop a leg leaving now and taking `seconds` of play:
## its destination shut when it would arrive, or a canal it goes through shut
## at any time on the way (checked about daily). {} if it can go.
func leg_blocker(from_port: String, to_port: String, seconds: float) -> Dictionary:
	if not active():
		return {}
	var now: int = _state.calendar_time()
	var per_second: float = _state.calendar_seconds_per_second()
	if seconds == INF:
		seconds = 0.0  # Can't make it anyway: the fuel and range checks say so.
	var arrive := now + int(seconds * per_second)
	var closure := port_closure(to_port, arrive)
	# An icebreaker stationed in its ice area lifts it (the ships wait to be led in).
	if not closure.is_empty() and _state.icebreaking.lifting(closure).is_empty():
		return closure
	for crossing: Dictionary in GameData.canal_crossings(from_port, to_port):
		var t := 0.0
		while true:
			closure = canal_closure(crossing.canal.id, now + int(minf(t, seconds) * per_second))
			if not closure.is_empty() or t >= seconds:
				break
			t += LEG_CHECK_S
		if not closure.is_empty():
			return closure
	# A stretch of sea shut by ice (the Arctic routes) anywhere on the way,
	# unless an icebreaker keeps it open.
	for item: Dictionary in closures():
		if not item.has("circles") or not lane_enters(item, from_port, to_port) or not _state.icebreaking.lifting(item).is_empty():
			continue
		var t := 0.0
		while true:
			if in_season(item, now + int(minf(t, seconds) * per_second)):
				return item
			if t >= seconds:
				break
			t += LEG_CHECK_S
	return {}


## True if a lane passes through a closure's stretch of sea (its circles).
func lane_enters(closure: Dictionary, from_port: String, to_port: String) -> bool:
	var key := "%s/%s-%s" % [closure.id, from_port, to_port]
	if not _enters.has(key):
		var found := false
		var lane = GameData.lane(from_port, to_port)
		if lane != null:
			var mile := 0.0
			while mile <= lane.length() and not found:
				var at := Geo.unproject(lane.sample(mile)[0])
				for circle: Array in closure.circles:
					if Geo.distance_nm(Vector2(circle[0], circle[1]), at) <= float(circle[2]):
						found = true
						break
				mile += 5.0
		_enters[key] = found
	return _enters[key]


## Every closure (whether in season or not) that a leg is subject to: its
## destination's, its canals', and any stretch of sea it passes through. For
## the route screen.
func leg_closures(from_port: String, to_port: String) -> Array:
	var out := []
	var canal_ids := GameData.canal_crossings(from_port, to_port).map(func(crossing: Dictionary) -> String: return crossing.canal.id)
	for closure: Dictionary in closures():
		if closure.get("ports", []).has(to_port) or canal_ids.has(closure.get("canal", "")) or (closure.has("circles") and lane_enters(closure, from_port, to_port)):
			out.append(closure)
	return out


## [speed factor, wear factor] at a (lon, lat) point from the ice zones in
## season there, eased where an icebreaker keeps the fairways open (see
## Icebreaking.fairway()); [1, 1] when closures aren't active.
func factors(lon_lat: Vector2) -> Array:
	if not active():
		return [1.0, 1.0]
	var now: int = _state.calendar_time()
	for zone: Dictionary in ice_zones():
		if in_season(zone, now) and Geo.distance_nm(Vector2(zone.center[0], zone.center[1]), lon_lat) <= float(zone.radius_nm):
			var fairway: Array = _state.icebreaking.fairway(zone.id)
			return fairway if not fairway.is_empty() else [float(zone.speed), float(zone.wear)]
	return [1.0, 1.0]


## A closure's name to start a sentence: "The St. Lawrence Seaway".
static func subject(closure: Dictionary) -> String:
	var text: String = closure.name
	return text[0].to_upper() + text.substr(1)


## The singular or plural verb for a closure: several ports take the plural.
static func verb(closure: Dictionary, singular: String, plural: String) -> String:
	return plural if closure.get("ports", []).size() > 1 else singular


## "Waiting for the St. Lawrence Seaway to reopen on 22 Mar (its winter
## shutdown)".
static func wait_text(closure: Dictionary) -> String:
	return "waiting for %s to reopen on %s (%s)" % [closure.name, date_text(closure.to), closure.why]
