class_name Weather
extends RefCounted
## Storms (game_config weather): systems that form in their real basins and
## seasons (by the in-game calendar), drift, build up and fade. Only in saves
## founded with storms (GameState.storms). Each storm is
## {name, kind, basin, lon, lat, age, life, radius_nm, speed_nm, recurve_lat,
## veer}: age and life in seconds of play, veer a fixed turn of its track.
##
## From company level min_company_level (see active()) they act on ships: at a
## point, a storm's strength is its intensity (rising then falling over its
## life) times how near the core it is, and that slows ships (factors()),
## wears them, and over a port, closes it if it's a tropical storm strong
## enough (closed_by()). Until then they're only drawn.

const LEVELS: Array[String] = ["none", "moderate", "harsh"]
const LEVEL_NAMES := {none = "No storms", moderate = "Moderate storms", harsh = "Harsh storms"}
const TROPICAL: Array[String] = ["hurricane", "typhoon", "cyclone"]
const KIND_NAMES := {hurricane = "Hurricane", typhoon = "Typhoon", cyclone = "Cyclone", gale = "Storm"}
## Within this share of its radius a storm is at full strength; it fades to
## nothing at the radius.
const CORE := 0.35
## Calendar days in a month, for turning a basin's storms a year into a rate.
const DAYS_PER_MONTH := 30.44

var storms: Array[Dictionary] = []
var _state: Node  # GameState
var _next_name := {}  # Basin id -> index of its next name.
var _closed := {}  # Port id -> closed_by(), worked out once a step (every ship asks).
var _can_close := false  # Any storm strong enough to close a port this step.



func _init(state: Node) -> void:
	_state = state


func clear() -> void:
	storms.clear()
	_next_name.clear()


func _settings() -> Dictionary:
	return GameData.config.get("weather", {})


func _level() -> Dictionary:
	return _settings().get("levels", {}).get(_state.storms, {})


## True once storms act on ships: a save with storms, from min_company_level.
func active() -> bool:
	return _state.storms != "none" and _state.world_level() >= int(_settings().get("min_company_level", 1))


## Forms, moves, builds up and fades the storms (in saves with storms).
func step(delta: float) -> void:
	_closed.clear()
	if _state.storms == "none":
		if not storms.is_empty():
			storms.clear()
		return
	for storm in storms:
		_move(storm, delta)
		storm.age += delta
	storms = storms.filter(func(storm: Dictionary) -> bool: return storm.age < storm.life)
	# Whether any storm is strong enough to close a port at all (at its core),
	# so ships needn't ask about their ports when none is.
	var close_at := float(_level().get("close_at", 2.0))
	_can_close = storms.any(func(storm: Dictionary) -> bool: return TROPICAL.has(storm.kind) and intensity(storm) >= close_at)
	var month := _month()
	var day_s := 86400.0 / float(_state.calendar_seconds_per_second())
	var rate_factor := float(_level().get("rate", 1.0))
	for basin: Dictionary in _settings().get("basins", []):
		var per_second := _monthly_share(basin, month) * float(basin.per_year) / (DAYS_PER_MONTH * day_s) * rate_factor
		if per_second > 0.0 and randf() < per_second * delta:
			_form(basin, day_s)


## The share of a basin's storms a year that form in a month: peak months count
## twice, other months in its season once, and the rest none.
static func _monthly_share(basin: Dictionary, month: int) -> float:
	# JSON numbers are floats, which never equal an int month: compare as ints.
	var months: Array = basin.get("months", []).map(func(m: float) -> int: return int(m))
	var peak: Array = basin.get("peak", []).map(func(m: float) -> int: return int(m))
	if not months.has(month):
		return 0.0
	var total := 0.0
	for m: int in months:
		total += 2.0 if peak.has(m) else 1.0
	return (2.0 if peak.has(month) else 1.0) / total


func _month() -> int:
	return int(Time.get_datetime_dict_from_unix_time(_state.calendar_time()).month)


func _form(basin: Dictionary, day_s: float) -> void:
	var spawn: Array = basin.spawn
	var names: Array = basin.get("names", ["Storm"])
	var index := int(_next_name.get(basin.id, randi() % names.size()))
	_next_name[basin.id] = (index + 1) % names.size()
	var life_days: Array = basin.get("life_days", [4, 8])
	storms.append({
		name = str(names[index]),
		kind = str(basin.kind),
		basin = str(basin.id),
		lon = wrapf(randf_range(spawn[0][0], spawn[0][1]), -180.0, 180.0),
		lat = randf_range(spawn[1][0], spawn[1][1]),
		age = 0.0,
		life = randf_range(life_days[0], life_days[1]) * day_s,
		radius_nm = float(basin.get("radius_nm", 250)) * randf_range(0.85, 1.15),
		speed_nm = float(basin.get("speed_nm", 12)),
		recurve_lat = float(basin.get("recurve_lat", 28)),
		veer = randf_range(-0.25, 0.25),
	})


## Tropical storms drift west and poleward, turning away east as they pass
## their recurve latitude (speeding up); gales run east, a little poleward.
func _move(storm: Dictionary, delta: float) -> void:
	var hemisphere := signf(storm.lat) if storm.lat != 0.0 else 1.0
	var heading: Vector2
	var speed: float = storm.speed_nm
	if TROPICAL.has(storm.kind):
		var turn := smoothstep(storm.recurve_lat - 8.0, storm.recurve_lat + 6.0, absf(storm.lat))
		heading = Vector2(lerpf(-1.0, 0.9, turn), hemisphere * lerpf(0.35, 0.6, turn))
		speed *= lerpf(1.0, 1.8, turn)
	else:
		heading = Vector2(1.0, hemisphere * 0.15)
	heading = heading.normalized().rotated(storm.veer)
	# speed_nm is calendar nm an hour; this many pass per second of play.
	var nm := speed * float(_state.calendar_seconds_per_second()) / 3600.0 * delta
	storm.lat = clampf(storm.lat + heading.y * nm / 60.0, -80.0, 80.0)
	storm.lon = wrapf(storm.lon + heading.x * nm / (60.0 * maxf(cos(deg_to_rad(storm.lat)), 0.1)), -180.0, 180.0)


## How strong a storm is now (0..1): building up over the first part of its
## life and fading over the rest.
static func intensity(storm: Dictionary) -> float:
	return pow(sin(PI * clampf(storm.age / storm.life, 0.0, 1.0)), 0.6)


## A storm's strength at a (lon, lat) point (0..1).
static func strength_at(storm: Dictionary, lon_lat: Vector2) -> float:
	if absf(float(storm.lat) - lon_lat.y) * 60.0 >= float(storm.radius_nm):
		return 0.0  # Too far north or south to reach (a degree of latitude is 60 nm): quick to rule out.
	var reach := Geo.distance_nm(Vector2(storm.lon, storm.lat), lon_lat) / float(storm.radius_nm)
	if reach >= 1.0:
		return 0.0
	return intensity(storm) * (1.0 - smoothstep(CORE, 1.0, reach))


## The strongest storm at a (lon, lat) point and its strength: [storm, 0..1],
## or [{}, 0.0] if none reaches it.
func strongest_at(lon_lat: Vector2) -> Array:
	var best := {}
	var best_strength := 0.0
	for storm in storms:
		var strength := strength_at(storm, lon_lat)
		if strength > best_strength:
			best = storm
			best_strength = strength
	return [best, best_strength]


## [speed factor, wear factor] at a (lon, lat) point: what the strongest storm
## there does to a ship (1, 1 when storms aren't active or none reach it).
func factors(lon_lat: Vector2) -> Array:
	if not active() or storms.is_empty():
		return [1.0, 1.0]
	var strength: float = strongest_at(lon_lat)[1]
	var level := _level()
	return [1.0 - float(level.get("slow", 0.0)) * strength, 1.0 + (float(level.get("wear", 1.0)) - 1.0) * strength]


## The tropical storm closing a port (strong enough over it: the level's
## close_at), or {} if it's open.
func closed_by(port_id: String) -> Dictionary:
	if not active() or storms.is_empty():
		return {}
	if not _can_close:
		return {}
	if _closed.has(port_id):
		return _closed[port_id]
	var close_at := float(_level().get("close_at", 2.0))
	var port := GameData.get_port(port_id)
	var at := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
	var found := {}
	for storm in storms:
		if TROPICAL.has(storm.kind) and strength_at(storm, at) >= close_at:
			found = storm
			break
	_closed[port_id] = found
	return found


## "Hurricane Ana".
static func title(storm: Dictionary) -> String:
	return "%s %s" % [KIND_NAMES.get(storm.kind, "Storm"), storm.name]


## Where a storm will be after some seconds of play, if it keeps going as now
## (for warnings), as (lon, lat).
func position_after(storm: Dictionary, seconds: float) -> Vector2:
	var ghost := storm.duplicate()
	var steps := 8
	for i in steps:
		_move(ghost, seconds / steps)
	return Vector2(ghost.lon, ghost.lat)


func to_dict() -> Dictionary:
	return {storms = storms, next_name = _next_name}


func from_dict(data: Dictionary) -> void:
	clear()
	for storm: Dictionary in data.get("storms", []):
		storms.append(storm)
	_next_name = data.get("next_name", {})
