# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Birds
extends RefCounted
## Birds (data/birds.json), just for looking at: they never affect ships.
## Two systems, both worked out from the calendar and who's where alone, so
## every player sees the same birds and nothing is saved.
##
## Gulls: every port has a flock circling it; grain and livestock carriers
## always have one over them; other ships, and pods of sea animals, now and
## then (in stretches of gull_follow_hours). A flock is 3 to 25 birds: busiest
## at dawn and dusk and quietest at night (by the sun where it is), bigger in
## its hemisphere's breeding season, and around ships loading or unloading.
## Its birds are one to three of the species whose range covers it that month.
##
## Seabirds (condors, albatrosses, terns, pelicans, shearwaters): when a ship
## at sea is where a species is that month, now and then some take up
## following it for a stretch of seabird_follow_hours.
##
## Raptors (eagles, hawks, the osprey) never follow ships: they live along
## the shore, and a port in a species' range that month has some about it by
## day, in some stretches of raptor_hours: perched, fishing, soaring.

const DATA_PATH := "res://data/birds.json"
const MONTH_SECONDS := 86400.0
## Flock sizes: the most a flock has (at its busiest), and the fewest.
const MOST := 25
const FEWEST := 3
## A port's flock at its busiest, by its size band (and more at a hub).
const PORT_FLOCK := {small = 9, medium = 13, large = 17, giant = 21}
const HUB_EXTRA := 4
## A grain or livestock carrier's flock, and another ship's when it has one.
const FEEDING_FLOCK := 14
const SHIP_FLOCK := 7
const POD_FLOCK := 10
## Chances another ship (near port, or out at sea) or a pod has gulls round it
## in a stretch.
const SHIP_CHANCE_NEAR := 0.6
const SHIP_CHANCE_SEA := 0.3
const NEAR_PORT_NM := 40.0
const POD_CHANCE := 0.4
## Cargo carried that brings gulls (model categories).
const GULL_CARGO := ["grain", "livestock"]
## Raptors are out between these local hours (by the sun).
const RAPTOR_DAY := Vector2(6.0, 19.0)

static var _shared: Birds

var gulls := {}
var seabirds := {}
var raptors := {}
var land_animals := {}
var gull_hours := 3.0
var seabird_hours := 6.0
var raptor_hours := 4.0

## Ships loading or unloading at each port, as of _busy_time (see _busy()).
var _busy_ports := {}
var _busy_time := -1


static func shared() -> Birds:
	if _shared == null:
		_shared = Birds.new()
	return _shared


func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	if data is Dictionary:
		gulls = data.get("gulls", {})
		seabirds = data.get("seabirds", {})
		raptors = data.get("raptors", {})
		land_animals = data.get("land_animals", {})
		gull_hours = float(data.get("gull_follow_hours", 3.0))
		seabird_hours = float(data.get("seabird_follow_hours", 6.0))
		raptor_hours = float(data.get("raptor_hours", 4.0))


## A species' data (gull, seabird or raptor), or {}.
func species(id: String) -> Dictionary:
	return gulls.get(id, seabirds.get(id, raptors.get(id, {})))


# --- Where and when -------------------------------------------------------------

## The month (1 to 12) at a calendar time.
static func month_of(unix: float) -> int:
	return int(Time.get_datetime_dict_from_unix_time(int(unix)).month)


## True if a species is at a place (lon, lat) in a month.
static func is_at(info: Dictionary, lon_lat: Vector2, month: int) -> bool:
	for season: Dictionary in info.get("seasons", []):
		var months: Array = season.get("months", [])
		if not months.is_empty() and not months.has(month):
			continue
		for box: Array in season.get("ranges", []):
			if lon_lat.x >= float(box[0]) and lon_lat.x <= float(box[1]) and lon_lat.y >= float(box[2]) and lon_lat.y <= float(box[3]):
				return true
	return false


## How far (degrees, roughly) a place is from a species' nearest range that month.
static func _distance_to(info: Dictionary, lon_lat: Vector2, month: int) -> float:
	var best := INF
	for season: Dictionary in info.get("seasons", []):
		var months: Array = season.get("months", [])
		if not months.is_empty() and not months.has(month):
			continue
		for box: Array in season.get("ranges", []):
			var near := Vector2(clampf(lon_lat.x, float(box[0]), float(box[1])), clampf(lon_lat.y, float(box[2]), float(box[3])))
			best = minf(best, near.distance_to(lon_lat))
	return best


## The gull species at a place that month: those whose range covers it, or
## else the nearest one (every port has its gulls).
func gull_species_at(lon_lat: Vector2, month: int) -> Array[String]:
	var found: Array[String] = []
	for id: String in gulls:
		if is_at(gulls[id], lon_lat, month):
			found.append(id)
	if found.is_empty():
		var nearest := ""
		var best := INF
		for id: String in gulls:
			var distance := _distance_to(gulls[id], lon_lat, month)
			if distance < best:
				best = distance
				nearest = id
		if not nearest.is_empty():
			found.append(nearest)
	return found


## How busy birds are at an hour of the local day (0 to 24): most at dawn and
## dusk, a fair few by day, few at night (0.15 to 1).
static func daylight(hour: float) -> float:
	var dawn := exp(-pow((hour - 6.5) / 1.5, 2.0))
	var dusk := exp(-pow((hour - 18.5) / 1.5, 2.0))
	var day := smoothstep(5.0, 8.0, hour) * (1.0 - smoothstep(17.0, 20.0, hour)) * 0.55
	return 0.15 + 0.85 * maxf(maxf(dawn, dusk), day)


## The local hour (by the sun) at a longitude and calendar time.
static func local_hour(lon: float, unix: float) -> float:
	return fposmod(fposmod(unix, 86400.0) / 3600.0 + lon / 15.0, 24.0)


## More in a hemisphere's breeding season (its spring and summer), fewer in its winter.
static func breeding(lat: float, month: int) -> float:
	var summer := [4, 5, 6, 7] if lat >= 0.0 else [10, 11, 12, 1]
	var winter := [11, 12, 1, 2] if lat >= 0.0 else [5, 6, 7, 8]
	return 1.15 if summer.has(month) else (0.85 if winter.has(month) else 1.0)


## A steady number from 0 to 1 for the parts given (the same every time).
static func chance(parts: Array) -> float:
	# A string's hash barely changes in its high bits between near-alike
	# strings ("bird 1", "bird 2"): mix it well first.
	var h := str(parts).hash() & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h ^= h >> 16
	return float(h & 0x7fffffff) / float(0x7fffffff)


## "a few", "a flock" or "lots".
static func how_many(count: int) -> String:
	if count >= 13:
		return "lots"
	if count >= 6:
		return "a flock"
	return "a few"


# --- Gull flocks ----------------------------------------------------------------

## A flock of gulls: {count, species (ids, one to three), key (steady for
## drawing it)}, or {} for none.
func _flock(key: String, lon_lat: Vector2, unix: float, busiest: float, fewest: int) -> Dictionary:
	var month := month_of(unix)
	var count := roundi(busiest * daylight(local_hour(lon_lat.x, unix)) * breeding(lon_lat.y, month))
	count = clampi(count, fewest, MOST)
	var here := gull_species_at(lon_lat, month)
	var day := floori(unix / 86400.0)
	here.sort_custom(func(a: String, b: String) -> bool: return chance([key, a, day]) < chance([key, b, day]))
	var kinds := clampi(1 + floori(chance([key, day, "kinds"]) * 3.0), 1, mini(3, here.size()))
	return {count = count, species = here.slice(0, kinds), key = key}


## The gulls circling a port now (always some).
func port_flock(port_id: String) -> Dictionary:
	var unix := float(GameState.calendar_time())
	var port := GameData.get_port(port_id)
	var lon_lat := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
	var busiest := float(PORT_FLOCK.get(GameState.port_sizes.band(port_id), 9))
	if GameState.docks.has_hub(port_id):
		busiest += HUB_EXTRA
	busiest *= 1.0 + minf(0.1 * _busy(port_id), 0.4)  # Ships loading and unloading draw more.
	return _flock("port/" + port_id, lon_lat, unix, busiest, FEWEST)


## The gulls round a ship now: always over a grain or livestock carrier,
## sometimes over others (more often near port), or {}.
func ship_flock(ship: Ship) -> Dictionary:
	if ship.is_carried():
		return {}
	var unix := float(GameState.calendar_time())
	var lon_lat := Geo.unproject(GameData.port_position(ship.docked_at) if ship.is_docked() else ship.world_position())
	var feeding := GULL_CARGO.has(str(ship.model().get("category", "")))
	var busiest := float(FEEDING_FLOCK if feeding else SHIP_FLOCK)
	if not feeding:
		var near := ship.is_docked() or ship.traveled_nm < NEAR_PORT_NM or ship.leg_length() - ship.traveled_nm < NEAR_PORT_NM
		var stretch := floori(unix / (gull_hours * 3600.0))
		if chance(["ship", ship.id, stretch]) >= (SHIP_CHANCE_NEAR if near else SHIP_CHANCE_SEA):
			return {}
	if ship.is_docking():
		busiest *= 1.4  # Loading or unloading.
	elif ship.is_docked():
		busiest *= 0.7  # Idle at anchor.
	return _flock("ship/%d" % ship.id, lon_lat, unix, busiest, FEWEST if feeding else 2)


## The gulls round a pod of sea animals now, or {}.
func pod_flock(pod_index: int, lon_lat: Vector2) -> Dictionary:
	var unix := float(GameState.calendar_time())
	if chance(["pod", pod_index, floori(unix / (gull_hours * 3600.0))]) >= POD_CHANCE:
		return {}
	return _flock("pod/%d" % pod_index, lon_lat, unix, POD_FLOCK, 2)


## How many ships are loading or unloading at a port (counted once a second of play).
func _busy(port_id: String) -> int:
	var now := int(GameState.play_time)
	if now != _busy_time:
		_busy_time = now
		_busy_ports.clear()
		for ship in GameState.ships:
			if ship.is_docking():
				_busy_ports[ship.docked_at] = int(_busy_ports.get(ship.docked_at, 0)) + 1
	return int(_busy_ports.get(port_id, 0))


# --- Seabirds following ships ---------------------------------------------------

## The seabirds following a ship at sea now: [{id, count}], most first.
func followers(ship: Ship) -> Array:
	var out := []
	if ship.is_docked() or ship.is_lost():
		return out
	var unix := float(GameState.calendar_time())
	var lon_lat := Geo.unproject(ship.world_position())
	var month := month_of(unix)
	var stretch_s := seabird_hours * 3600.0
	for id: String in seabirds:
		var info := species(id)
		if not is_at(info, lon_lat, month):
			continue
		# Each species keeps its own stretches, so they come and go at different times.
		var offset := chance([id, "offset"]) * stretch_s
		var stretch := floori((unix + offset) / stretch_s)
		var follow: Array = info.get("follow", [0.3, 1, 2])
		if chance(["follow", ship.id, id, stretch]) >= float(follow[0]):
			continue
		var fewest := int(follow[1])
		var most := int(follow[2])
		out.append({id = id, count = fewest + floori(chance(["count", ship.id, id, stretch]) * (most - fewest + 1))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.count) > int(b.count))
	return out


# --- Raptors along the shore ----------------------------------------------------

## The raptors about a port's shore now: [{id, count}], most first. Each
## species whose range covers the port that month is there in some stretches
## of raptor_hours (its visit chance), only by day (raptors hunt by sight).
func port_raptors(port_id: String) -> Array:
	var out := []
	var unix := float(GameState.calendar_time())
	var port := GameData.get_port(port_id)
	var lon_lat := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
	var hour := local_hour(lon_lat.x, unix)
	if hour < RAPTOR_DAY.x or hour > RAPTOR_DAY.y:
		return out
	var month := month_of(unix)
	var stretch_s := raptor_hours * 3600.0
	for id: String in raptors:
		var info: Dictionary = raptors[id]
		if not is_at(info, lon_lat, month):
			continue
		var offset := chance([id, "offset"]) * stretch_s
		var stretch := floori((unix + offset) / stretch_s)
		var visit: Array = info.get("visit", [0.3, 1, 2])
		if chance(["raptor", port_id, id, stretch]) >= float(visit[0]):
			continue
		var fewest := int(visit[1])
		var most := int(visit[2])
		out.append({id = id, count = fewest + floori(chance(["count", port_id, id, stretch]) * (most - fewest + 1))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.count) > int(b.count))
	return out


# --- Words for popups -----------------------------------------------------------

## "Herring Gull, Great Black-backed Gull (lots)", or "".
func flock_text(flock: Dictionary) -> String:
	if flock.is_empty():
		return ""
	var names := PackedStringArray()
	for id: String in flock.species:
		names.append(str(species(id).get("name", id)))
	return "%s (%s)" % [", ".join(names), how_many(int(flock.count))]


## "Wandering Albatross (2), Sooty Shearwaters (8)", or "".
func followers_text(following: Array) -> String:
	var names := PackedStringArray()
	for entry: Dictionary in following:
		names.append("%s (%d)" % [species(entry.id).get("name", entry.id), int(entry.count)])
	return ", ".join(names)
