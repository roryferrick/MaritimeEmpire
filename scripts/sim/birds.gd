# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Birds
extends RefCounted
## Birds (data/birds.json), just for looking at: they never affect ships. The
## species and where and when they're about; every bird itself is one of the
## wildlife's colonies (Wildlife), and lives its days as a permanent map
## object (BirdLife).

const DATA_PATH := "res://data/birds.json"
const MONTH_SECONDS := 86400.0

static var _shared: Birds

var gulls := {}
var seabirds := {}
var raptors := {}
var sea_ducks := {}
var cormorants := {}
var waders := {}
var land_animals := {}


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
		sea_ducks = data.get("sea_ducks", {})
		cormorants = data.get("cormorants", {})
		waders = data.get("waders", {})
		land_animals = data.get("land_animals", {})


## A species' data (gull, seabird, raptor, sea duck, cormorant or wader), or {}.
func species(id: String) -> Dictionary:
	return gulls.get(id, seabirds.get(id, raptors.get(id, sea_ducks.get(id, cormorants.get(id, waders.get(id, {}))))))


# --- Where and when -------------------------------------------------------------

## The month (1 to 12) at a calendar time.
static func month_of(unix: float) -> int:
	return int(Time.get_datetime_dict_from_unix_time(int(unix)).month)


## True if a species is at a place (lon, lat) in a month.
static func is_at(info: Dictionary, lon_lat: Vector2, month: int) -> bool:
	for season: Dictionary in info.get("seasons", []):
		var months: Array = season.get("months", [])
		if not _in_months(months, month):
			continue
		for box: Array in season.get("ranges", []):
			if lon_lat.x >= float(box[0]) and lon_lat.x <= float(box[1]) and lon_lat.y >= float(box[2]) and lon_lat.y <= float(box[3]):
				return true
	return false


## True if a season's months (none: all year) have this month in them (the
## data's months read in as floats).
static func _in_months(months: Array, month: int) -> bool:
	return months.is_empty() or months.has(month) or months.has(float(month))


## How far (degrees, roughly) a place is from a species' nearest range that month.
static func _distance_to(info: Dictionary, lon_lat: Vector2, month: int) -> float:
	var best := INF
	for season: Dictionary in info.get("seasons", []):
		var months: Array = season.get("months", [])
		if not _in_months(months, month):
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


# --- Words for popups -----------------------------------------------------------

## "Wandering Albatross (2), Sooty Shearwaters (8)" from [{id, count}], or "".
func counts_text(entries: Array) -> String:
	var names := PackedStringArray()
	for entry: Dictionary in entries:
		names.append("%s (%d)" % [species(entry.id).get("name", entry.id), int(entry.count)])
	return ", ".join(names)
