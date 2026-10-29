# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Seasons
extends RefCounted
## Seasonal closures (game_config seasons), for saves founded with them
## (GameState.seasons), from the start (see active()).
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
var _bounds := {}  # Closure id -> _circles_bounds().
## zones_now(), and the month x 100 + day it was worked out for.
var _zones_cache := []
var _zones_day := -1


func _init(state: Node) -> void:
	_state = state


func _settings() -> Dictionary:
	return GameData.config.get("seasons", {})


func closures() -> Array:
	var out: Array = _settings().get("closures", []).duplicate()
	out.append_array(_state.events.closures())  # (Canals and ports shut by events: see Events.)
	return out


func ice_zones() -> Array:
	return _settings().get("ice_zones", [])


## True when closures apply: a save with them, or an event shutting something.
func active() -> bool:
	return _state.seasons or not _state.events.active.is_empty()


## True if a closure or ice zone ({from, to}: [month, day]) is in season at a
## calendar (Unix) time.
static func in_season(item: Dictionary, unix_time: int) -> bool:
	if item.has("unix_from"):  # (An event's closure: a window of calendar time.)
		return unix_time >= int(item.unix_from) and unix_time < int(item.unix_to)
	var today := _month_day(unix_time)
	if item.get("not_first_year", false) and _md_year == _first_year():
		return false  # Spared in the game's first calendar year (the Great Lakes ice).
	var from := int(item.from[0]) * 100 + int(item.from[1])
	var to := int(item.to[0]) * 100 + int(item.to[1])
	return today >= from and today <= to if from <= to else today >= from or today <= to


## A calendar time's month x 100 + day, remembered for the last time asked
## (every ship asks about the same time each step).
static var _md_time := -1
static var _md := 0
static var _md_year := 0
static var _start_year := -1

static func _month_day(unix_time: int) -> int:
	if unix_time != _md_time:
		var date := Time.get_datetime_dict_from_unix_time(unix_time)
		_md_time = unix_time
		_md = int(date.month) * 100 + int(date.day)
		_md_year = int(date.year)
	return _md


## The calendar year every game starts in (game_config calendar start).
static func _first_year() -> int:
	if _start_year < 0:
		_start_year = int(str(GameData.config.get("calendar", {}).get("start", "2000-01-01")).left(4))
	return _start_year


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
	var war: Dictionary = _state.events.war_blocks(_state.company, from_port, to_port)  # (A war between the two ports' countries: see Events.)
	if not war.is_empty():
		return war
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
		# Most lanes go nowhere near: ruled out at once by the boxes round them.
		if lane != null and lane.bounds().intersects(_circles_bounds(closure)):
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


## A box (projected) round a closure's circles, a little generous; worked out once.
func _circles_bounds(closure: Dictionary) -> Rect2:
	if not _bounds.has(closure.id):
		var box := Rect2()
		for i in closure.circles.size():
			var circle: Array = closure.circles[i]
			var center := Geo.project(Vector2(circle[0], circle[1]))
			var radius := float(circle[2]) / (60.0 * maxf(cos(deg_to_rad(float(circle[1]))), 0.1)) * 1.5
			var one := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
			box = one if i == 0 else box.merge(one)
		_bounds[closure.id] = box
	return _bounds[closure.id]


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
	for zone: Dictionary in zones_now():
		if Geo.distance_nm(Vector2(zone.center[0], zone.center[1]), lon_lat) <= float(zone.radius_nm):
			var fairway: Array = _state.icebreaking.fairway(zone.id)
			return fairway if not fairway.is_empty() else [float(zone.speed), float(zone.wear)]
	return [1.0, 1.0]


## The ice zones in season now (all of them, whether or not closures are
## active), worked out again when the calendar day changes.
func zones_now() -> Array:
	var today := _month_day(_state.calendar_time())
	if today != _zones_day:
		_zones_day = today
		var now: int = _state.calendar_time()
		_zones_cache = ice_zones().filter(func(zone: Dictionary) -> bool: return in_season(zone, now))
	return _zones_cache


## Where the sea is frozen now, for the map: [lon, lat, radius nm] circles of
## every closure in season (its ice circles, its own stretch of sea, or its
## icebreaker area's) and every ice zone in season. [] when closures aren't active.
func ice_circles() -> Array:
	if not active():
		return []
	var now: int = _state.calendar_time()
	var out := []
	for closure: Dictionary in closures():
		if not in_season(closure, now):
			continue
		if closure.has("ice"):
			out.append_array(closure.ice)
		elif closure.has("circles"):
			out.append_array(closure.circles)
		else:
			for item: Dictionary in _state.icebreaking.areas():
				if item.get("closure", "") == closure.id:
					out.append_array(_state.icebreaking.circles(item))
	for zone: Dictionary in ice_zones():
		if in_season(zone, now):
			out.append([zone.center[0], zone.center[1], zone.radius_nm])
	return out


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
