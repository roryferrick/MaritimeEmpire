# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Wildlife
extends RefCounted
## The wildlife as individuals that live on the map for good (data/wildlife.json;
## the species' names, looks and facts are data/birds.json's), just for
## looking at: they never affect ships. Worked out from the data and the
## clocks alone, so every player sees much the same and nothing is saved.
##
## Land animals live in groups (a herd, a pride, a mother and cubs), several
## round each of the map's spots for the species (its drawing's spot), each
## group with its home if it has one (a den, a cave, a burrow, a nest in a
## tree, a rookery, a waterhole...). By day (or night, or dusk and dawn: when
## its species is up) the group roams its range round its home, from spot to
## spot at its walking pace, grazing and resting between; the rest of the
## time it's at its home, or bedded down where it is. Bears sleep the winter
## in their dens; reindeer and zebras migrate with the seasons.
##
## Birds live in colonies: each port has its gulls, and the raptors,
## cormorants, waders and sea ducks whose ranges cover it (if they live there:
## birds.json's chance for each), each colony with its home on the shore near
## the port (a gull colony, an eyrie, a heronry...). A colony whose species is
## only there some months spends the rest at the nearest port its range covers
## then, flying between the two over migrate_days. Birds (see Birds) draws
## each port's birds from the colonies there now, and the gulls round ships
## and sea animals from the nearest. Seabirds (albatrosses, shearwaters,
## terns, pelicans, condors) nest in colonies at some of the ports in their
## range and forage out to sea round them, following ships that pass.
##
## Movement goes by the life clock (step()): calendar seconds at the game's
## speed, but never slower than 1x, so the wildlife carries on while the game's
## paused. When things happen (day and night, the seasons) goes by the calendar.

const DATA_PATH := "res://data/wildlife.json"
## Life seconds a real second at 1x (the calendar's 20 minutes a second).
const LIFE_RATE := 1200.0
const KM_PER_DEGREE := 111.32
## Where a colony that never leaves is (see colony_where()).
const ALL_YEAR := ["home", 0.0]
## A land group moves for this share of each leg between spots, then grazes or rests.
const MOVE_SHARE := 0.55
## Groups round each spot: wildlife.json groups times this.
const LAND_GROUPS := 2
## How big a young animal is, for its kind.
const YOUNG_SIZE := 0.55
## The most species of each class of bird living at one port.
const SPECIES_A_PORT := {raptors = 2, cormorants = 2, waders = 3, sea_ducks = 1}
## The most birds of one species in a colony, by class (rafts and cormorant groups can be big).
const COLONY_MOST := {cormorants = 8, sea_ducks = 16, waders = 3, raptors = 2}
## The share of each colony's birds that live (a fixed roll per colony
## settling the odd bird, so some colonies of one have none); these species
## all of them.
const BIRD_SHARE := 2.0 / 3.0
const FULL_NUMBERS := ["red_tailed_hawk"]
## Land groups and seabird colonies are found by cells this many degrees across.
const CELL_DEG := 5.0

static var _shared: Wildlife

var land := {}  # species id -> its wildlife.json land data merged with birds.json's
var birds_data := {}
var migrate_days := 10.0
## Land groups: {key, species, home (lon, lat), away (lon, lat; or home), members,
## young (how many of the members are young), home_kind}.
var groups: Array[Dictionary] = []
## Bird colonies: {key, cls, species, port, count, home_kind, home_months
## (months it's at port; all twelve for one that stays), away_port ("" for
## none), away_spot (lon, lat)}.
var colonies: Array[Dictionary] = []
var _colonies_at := {}  # port -> [colony indices living there]
var _visiting := {}  # port -> [colony indices spending their away months there]
var _group_cells := {}  # Vector2i -> [group indices]
var _seabird_cells := {}  # Vector2i -> [colony indices of seabirds]
var _built := false
var _task := -1
## The colonies on the wing (see migrating()), and the calendar hour they were worked out for.
var _migrating := []
var _migrating_hour := -1
var life_time := 0.0
## The birds' own clock (real seconds: see BirdLife).
var bird_time := 0.0
## How many times any colony has set off, arrived or gone away (see
## colony_where()): what's kept about birds' whereabouts holds till it changes.
var where_changes := 0
## Colonies' whereabouts this hour by the months they're home (see colony_where()).
var _seasons := {}
var _season_hour := -1
var _colony_cells := {}  # Vector2i -> [colony indices with their home or away spot there]
var _month_hour := -1
var _month_now := 1


static func shared() -> Wildlife:
	if _shared == null:
		_shared = Wildlife.new()
	return _shared


func _init() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text()) if file != null else {}
	migrate_days = float(data.get("migrate_days", 10.0))
	birds_data = data.get("birds", {})
	var names := Birds.shared().land_animals
	for id: String in data.get("land", {}):
		var info: Dictionary = (names.get(id, {}) as Dictionary).duplicate()
		info.merge(data.land[id], true)
		land[id] = info


## Moves the life clock on (see the top): the map calls this every frame.
func step(delta: float) -> void:
	life_time += delta * LIFE_RATE * maxf(float(GameState.time_speed), 1.0)
	bird_time += delta


## True once the groups and colonies are built; the first ask starts building
## them off the main thread (it takes a few seconds: homes keep to the land,
## so it waits for the map's land), and till then there's no wildlife.
func ensure_built() -> bool:
	if _built:
		return true
	if _task < 0:
		_task = WorkerThreadPool.add_task(_build, false, "Wildlife")
		return false
	if not WorkerThreadPool.is_task_completed(_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_built = true
	return true


## Builds them now, waiting (for tests and tools).
func build_now() -> void:
	ensure_built()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_built = true


func _build() -> void:
	MapView._land_ready()
	_build_land()
	_build_birds()


# --- Land animals ---------------------------------------------------------------

func _build_land() -> void:
	var data := GameData.world_map
	for i in data.decor_positions.size():
		var species := data.decor_kind_names[data.decor_kinds[i]]
		if not land.has(species):
			continue
		var info: Dictionary = land[species]
		var base := Geo.unproject(data.decor_positions[i])
		for g in int(info.get("groups", 3)) * LAND_GROUPS:
			var key := "%s/%d/%d" % [species, i, g]
			var home := base
			# The first group at the spot itself; the rest round it, on land with
			# all the range they roam on land too (so none wanders into the sea).
			var reach := float(info.get("roam_km", 30.0)) + float(info.get("km", 6.0)) * 3.0
			for attempt in 24:
				if g == 0:
					break
				var spot := _offset(base, _disc([key, "home", attempt]) * float(info.get("spread_km", 300.0)))
				if _range_on_land(spot, reach):
					home = spot
					break
			var away := home
			if info.has("migrate"):
				var to: Array = info.migrate.to
				away = home + Vector2(float(to[0]), float(to[1]))
			# How many: a steady number in its species' range; some young (not the first, their mother).
			var counts: Array = info.get("group", [1, 1])
			var fewest := int(counts[0])
			var most := maxi(int(counts[1]), fewest)
			var size := fewest + mini(floori(Birds.chance([key, "count"]) * (most - fewest + 1)), most - fewest)
			var young := 0
			for m in range(1, size):
				if Birds.chance([key, m, "young"]) < float(info.get("young", 0.0)):
					young += 1
			var index := groups.size()
			groups.append({key = key, seed = key.hash(), species = species, home = home, away = away, members = size, young = young, home_kind = str(info.get("home", "none"))})
			for spot: Vector2 in [home, away]:
				var cell := _cell(spot)
				var list: Array = _group_cells.get_or_add(cell, [])
				if not list.has(index):
					list.append(index)


## The land groups whose range may reach into a box of (lon, lat).
func groups_in(box: Rect2) -> Array:
	if not ensure_built():
		return []
	return _in_cells(_group_cells, box)


## A land animal now: {pos (lon, lat), heading (radians, 0 east, counterclockwise
## towards north), mode ("walk", "graze", "rest", "sleep", "den": out of sight
## in its den), young, size (km)}.
func land_state(group: Dictionary, member: int, cal: float) -> Dictionary:
	var info: Dictionary = land[group.species]
	var seed: int = group.seed
	var young := member > 0 and member >= int(group.members) - int(group.young)
	var size := float(info.get("km", 6.0)) * (YOUNG_SIZE if young else 1.0)
	var month := _month(cal)
	var hibernating: bool = (info.get("hibernate", []) as Array).has(month) or (info.get("hibernate", []) as Array).has(float(month))
	if hibernating and (not info.get("den_young", false) or int(group.young) > 0):
		return {pos = group.home, heading = 0.0, mode = "den", young = young, size = size}
	var base := _migration_base(group, info, cal)
	var hour := Birds.local_hour(float(base.x), cal)
	var up := _activity(hour, str(info.get("active", "day")))
	var roam := float(info.get("roam_km", 30.0))
	var kmh := maxf(float(info.get("kmh", 3.0)), 0.3)
	# The group's legs between spots in its range: a leg takes long enough to
	# walk its way at its pace, then it stays a while.
	var leg_s := roam / kmh * 3600.0 * 1.4 / MOVE_SHARE
	var t := life_time / leg_s + _mix(seed) * 7.0
	var leg := floori(t)
	var u := t - leg
	var from := _offset(base, _disc_n(seed + leg * 7919) * roam)
	var to := _offset(base, _disc_n(seed + (leg + 1) * 7919) * roam)
	var going := smoothstep(0.0, MOVE_SHARE, u)
	var middle := from.lerp(to, going)
	var moving := u < MOVE_SHARE
	# Each member round the middle (the young close by their mother).
	var spread := float(info.get("km", 6.0)) * (1.2 + 0.4 * int(group.members))
	var mseed := seed * 31 + member * 1009
	var mine := _disc_n(mseed) * spread * (0.35 if young else 1.0)
	var active := _offset(middle, mine)
	var rest_at: Vector2 = group.home if group.home_kind != "none" else from
	var resting := _offset(rest_at, mine * 0.35)
	var pos := resting.lerp(active, up)
	var heading := _mix(mseed + 7) * TAU
	var mode := "sleep"
	if up > 0.5:
		if moving:
			heading = atan2(to.y - from.y, (to.x - from.x) * cos(deg_to_rad(base.y)))
			mode = "walk"
		else:
			mode = "graze" if _mix(mseed + leg * 13) < 0.6 else "rest"
	elif up > 0.05:
		mode = "walk"
		var way := (active - resting) if hour < 12.0 else (resting - active)
		if way.length() > 0.0001:
			heading = atan2(way.y, way.x * cos(deg_to_rad(base.y)))
	return {pos = pos, heading = heading, mode = mode, young = young, size = size}


## Where a group's range is centered now: its home, or out along its
## migration (there by its away months, back after), walking over migrate_days.
func _migration_base(group: Dictionary, info: Dictionary, cal: float) -> Vector2:
	if not info.has("migrate"):
		return group.home
	var hour := floori(cal / 3600.0)
	if int(group.get("season_hour", -1)) != hour:
		group.season_hour = hour
		group.season = _season(info.migrate.months, cal, true)
	var where: Array = group.season
	match where[0]:
		"away":
			return group.away
		"to_away":
			return (group.home as Vector2).lerp(group.away, where[1])
		"to_home":
			return (group.away as Vector2).lerp(group.home, where[1])
	return group.home


## How much an animal's up and about at a local hour (0 to 1), by when its
## species is active: by day, by night, or at dusk and dawn.
static func _activity(hour: float, active: String) -> float:
	var day := smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(18.5, 20.5, hour))
	match active:
		"night":
			return 1.0 - day
		"dusk":
			return maxf(exp(-pow((hour - 6.5) / 2.0, 2.0)), exp(-pow((hour - 19.0) / 2.0, 2.0)))
	return day


## What a group's doing, for its popup: "Grazing", "Asleep in their den" ...
func group_doing(group: Dictionary, cal: float) -> String:
	var counts := {}
	var order: Array[String] = []
	var home_word := home_name(group.home_kind)
	for m in int(group.members):
		var state := land_state(group, m, cal)
		var doing: String = {walk = "on the move", graze = "grazing", rest = "resting", sleep = "asleep", den = "hibernating in the den"}.get(state.mode, "resting")
		if state.mode == "sleep" and group.home_kind != "none":
			doing = "asleep at the %s" % home_word
		if not counts.has(doing):
			order.append(doing)
		counts[doing] = int(counts.get(doing, 0)) + 1
	if order.size() == 1:
		return order[0].left(1).to_upper() + order[0].substr(1)
	var parts := PackedStringArray()
	for doing in order:
		parts.append("%d %s" % [counts[doing], doing])
	return ", ".join(parts)


## A home's name in words ("den", "gull colony" ...).
static func home_name(kind: String) -> String:
	return {rookery = "rookery", snow_den = "snow den", cave = "cave", den = "den", burrow = "burrow", tree = "tree",
		tree_nest = "nest hole", leaf_nest = "nest", waterhole = "waterhole", wallow = "wallow", pride_rock = "rocks",
		gull_colony = "colony", eyrie = "eyrie", cormorant_colony = "colony", heronry = "heronry",
		reed_nest = "nest in the reeds", ground_nest = "nest", duck_nest = "nest", seabird_colony = "colony"}.get(kind, kind.replace("_", " "))


# --- Birds ----------------------------------------------------------------------

func _build_birds() -> void:
	var birds := Birds.shared()
	var homes: Dictionary = birds_data.get("homes", {})
	var species_homes: Dictionary = birds_data.get("species_homes", {})
	var classes := {gulls = birds.gulls, raptors = birds.raptors, cormorants = birds.cormorants, waders = birds.waders, sea_ducks = birds.sea_ducks}
	for port: Dictionary in GameData.ports:
		var spot := Vector2(float(port.lon), float(port.lat))
		for cls: String in classes:
			var all: Dictionary = classes[cls]
			var here: Array = []
			for id: String in all:
				var months := _months_at(all[id], spot)
				if not months.is_empty():
					here.append([id, months])
			if cls == "gulls":
				_add_gulls(port, spot, here)
				continue
			# Up to SPECIES_A_PORT of the class's species live at a port (a steady pick).
			here.sort_custom(func(a: Array, b: Array) -> bool: return Birds.chance([port.id, a[0], "pick"]) < Birds.chance([port.id, b[0], "pick"]))
			var kept := 0
			for entry: Array in here:
				if kept >= int(SPECIES_A_PORT.get(cls, 2)):
					break
				var id: String = entry[0]
				var info: Dictionary = all[id]
				var odds: Array = info.get({raptors = "visit", sea_ducks = "raft"}.get(cls, "group"), [0.5, 1, 3])
				if Birds.chance([port.id, id, "lives"]) >= float(odds[0]):
					continue
				var count := mini(int(odds[1]) + floori(Birds.chance([port.id, id, "count"]) * (int(odds[2]) - int(odds[1]) + 1)), int(COLONY_MOST.get(cls, 99)))
				_add_colony(cls, id, port.id, spot, maxi(count, 1), str(species_homes.get(id, homes.get(cls, "nest"))), entry[1])
				kept += 1
		# Seabirds nest at some of the ports in their ranges.
		for id: String in birds.seabirds:
			var info: Dictionary = birds.seabirds[id]
			var months := _months_at(info, spot)
			if months.is_empty() or Birds.chance([port.id, id, "colony"]) >= float(birds_data.get("seabird_colony_chance", 0.3)):
				continue
			var follow: Array = info.get("follow", [0.3, 1, 2])
			var count := int(follow[2]) * int(birds_data.get("seabird_colony_size", 3))
			var index := _add_colony("seabirds", id, port.id, spot, count, str(species_homes.get(id, homes.get("seabirds", "seabird_colony"))), months)
			if index < 0:
				continue
			colonies[index].range_km = seabird_range_km(id)
			(_seabird_cells.get_or_add(_cell(spot), []) as Array).append(index)


## The gulls of a port: the species whose ranges cover it (or the nearest
## one), its numbers (by the port's size band, more at a hub) shared out
## between up to three of them.
func _add_gulls(port: Dictionary, spot: Vector2, here: Array) -> void:
	var birds := Birds.shared()
	if here.is_empty():
		var nearest := birds.gull_species_at(spot, 6)
		if nearest.is_empty():
			return
		here = [[nearest[0], range(1, 13)]]
	here.sort_custom(func(a: Array, b: Array) -> bool: return Birds.chance([port.id, a[0]]) < Birds.chance([port.id, b[0]]))
	here = here.slice(0, 3)
	var total := int((birds_data.get("gull_numbers", {}) as Dictionary).get(GameState.port_sizes.band(port.id), 12))
	if GameState.docks.has_hub(port.id):
		total += int(birds_data.get("hub_gulls", 5))
	for k in here.size():
		var share := total / here.size() + (1 if k < total % here.size() else 0)
		_add_colony("gulls", here[k][0], port.id, spot, share, str((birds_data.get("homes", {}) as Dictionary).get("gulls", "gull_colony")), here[k][1])


## A colony: living at a port in its home months, and (if those aren't all
## of them) at the nearest port its species' range covers in the rest. Its
## BIRD_SHARE of `count` live; its index, or -1 if that leaves none.
func _add_colony(cls: String, id: String, port_id: String, spot: Vector2, count: int, home_kind: String, months: Array) -> int:
	if not FULL_NUMBERS.has(id):
		var share := count * BIRD_SHARE
		count = floori(share) + (1 if Birds.chance([cls, id, port_id, "share"]) < share - floorf(share) else 0)
		if count <= 0:
			return -1
	var info := Birds.shared().species(id)
	var away_port := ""
	var away_spot := spot
	if months.size() < 12:
		var away_month := 1
		for m in range(1, 13):
			if not months.has(m):
				away_month = m
				break
		var best := INF
		for other: Dictionary in GameData.ports:
			var there := Vector2(float(other.lon), float(other.lat))
			if not Birds.is_at(info, there, away_month):
				continue
			var gap := Geo.distance_nm(spot, there)
			if gap < best:
				best = gap
				away_port = other.id
				away_spot = there
		if away_port.is_empty():
			away_spot = _range_middle(info, away_month, spot)
	var index := colonies.size()
	var key := "%s/%s/%s" % [cls, id, port_id]
	colonies.append({key = key, seed = key.hash(), cls = cls, species = id, port = port_id, count = count,
		home_kind = home_kind, home_months = months, away_port = away_port, away_spot = away_spot, spot = spot})
	(_colonies_at.get_or_add(port_id, []) as Array).append(index)
	for place: Vector2 in [spot, away_spot]:
		var cell_list: Array = _colony_cells.get_or_add(_cell(place), [])
		if not cell_list.has(index):
			cell_list.append(index)
	if not away_port.is_empty():
		(_visiting.get_or_add(away_port, []) as Array).append(index)
	return index


## The months (1 to 12) a species' range covers a place, or [].
static func _months_at(info: Dictionary, spot: Vector2) -> Array:
	var out := []
	for m in range(1, 13):
		if Birds.is_at(info, spot, m):
			out.append(m)
	return out


## The middle of the range box nearest a place that a species is in in a month.
static func _range_middle(info: Dictionary, month: int, near: Vector2) -> Vector2:
	var best := near
	var best_gap := INF
	for season: Dictionary in info.get("seasons", []):
		if not Birds._in_months(season.get("months", []), month):
			continue
		for box: Array in season.get("ranges", []):
			var middle := Vector2((float(box[0]) + float(box[1])) / 2.0, (float(box[2]) + float(box[3])) / 2.0)
			if middle.distance_to(near) < best_gap:
				best_gap = middle.distance_to(near)
				best = middle
	return best


## Where a colony is now: ["home"], ["away"], or on its way ["to_home" or
## "to_away", how far (0 to 1)].
func colony_where(colony: Dictionary, cal: float) -> Array:
	if (colony.home_months as Array).size() >= 12:
		return ALL_YEAR
	var hour := floori(cal / 3600.0)  # (Worked out once an hour of the calendar: it's asked for a lot.)
	if int(colony.get("where_hour", -1)) != hour:
		# (Colonies away the same months share the working out: it's dates.)
		var months_key: String = colony.get("months_key", "")
		if months_key.is_empty():
			months_key = str(colony.home_months)
			colony.months_key = months_key
		if _season_hour != hour:
			_season_hour = hour
			_seasons.clear()
		if not _seasons.has(months_key):
			var away_months := []
			for m in range(1, 13):
				if not (colony.home_months as Array).has(m):
					away_months.append(m)
			_seasons[months_key] = _season(away_months, cal, false)
		colony.where_hour = hour
		var was: Array = colony.get("where", [])
		colony.where = _seasons[months_key]
		if not was.is_empty() and was[0] != colony.where[0]:
			where_changes += 1
			colony.changes = int(colony.get("changes", 0)) + 1  # (Its own birds are worked out again: see BirdLife.)
	return colony.where


## Where something is that's away in some months: ["home"], ["away"], or
## ["to_away" / "to_home", progress] over the first migrate_days of each.
func _season(away_months: Array, cal: float, _land: bool) -> Array:
	var month := Birds.month_of(cal)
	var away := away_months.has(month) or away_months.has(float(month))
	# The day of the year the stay it's in began: back through the months while they're the same.
	var date := Time.get_datetime_dict_from_unix_time(int(cal))
	var start_month := month
	for step in 11:
		var before := (start_month + 10) % 12 + 1
		if (away_months.has(before) or away_months.has(float(before))) != away:
			break
		start_month = before
	var start := Time.get_unix_time_from_datetime_dict({year = date.year if start_month <= month else date.year - 1, month = start_month, day = 1, hour = 0, minute = 0, second = 0})
	var days := (cal - start) / 86400.0
	if days < migrate_days:
		return ["to_away" if away else "to_home", clampf(days / migrate_days, 0.0, 1.0)]
	return ["away" if away else "home", 0.0]


## The birds of a class at a port now: [{id, count, colony (index)}], those
## living there in their home months and those spending their away months
## there (not those on their way).
func birds_at(port_id: String, cls: String, cal: float) -> Array:
	if not ensure_built():
		return []
	var out := []
	for index: int in _colonies_at.get(port_id, []):
		var colony: Dictionary = colonies[index]
		if colony.cls == cls and colony_where(colony, cal)[0] == "home":
			out.append({id = colony.species, count = int(colony.count), colony = index})
	for index: int in _visiting.get(port_id, []):
		var colony: Dictionary = colonies[index]
		if colony.cls == cls and colony_where(colony, cal)[0] == "away":
			out.append({id = colony.species, count = int(colony.count), colony = index})
	return out


## The colonies with their home at a port (whether they're there now or not).
func colonies_at(port_id: String) -> Array:
	if not ensure_built():
		return []
	return _colonies_at.get(port_id, [])


## The colonies flying between their homes now, with where they are: [[colony
## index, from (lon, lat), to (lon, lat), progress]].
func migrating(cal: float) -> Array:
	if not ensure_built():
		return []
	# Which are on the wing, once a calendar hour; where they've got to, now.
	var hour := floori(cal / 3600.0)
	if hour != _migrating_hour:
		_migrating_hour = hour
		_migrating.clear()
		for index in colonies.size():
			var colony: Dictionary = colonies[index]
			if (colony.home_months as Array).size() < 12 and str(colony_where(colony, cal)[0]).begins_with("to_"):
				_migrating.append(index)
	var out := []
	for index: int in _migrating:
		var colony: Dictionary = colonies[index]
		var away_months := []
		for m in range(1, 13):
			if not (colony.home_months as Array).has(m):
				away_months.append(m)
		var where := _season(away_months, cal, false)
		if where[0] == "to_home":
			out.append([index, colony.away_spot, colony.spot, where[1]])
		elif where[0] == "to_away":
			out.append([index, colony.spot, colony.away_spot, where[1]])
	return out


## The seabird colonies whose foraging range may reach a box of (lon, lat).
func seabird_colonies_in(box: Rect2) -> Array:
	if not ensure_built():
		return []
	var reach := 2600.0 / KM_PER_DEGREE
	return _in_cells(_seabird_cells, box.grow(reach))


## How far (km) a seabird species forages from its colony.
func seabird_range_km(id: String) -> float:
	var kind := str(Birds.shared().species(id).get("kind", ""))
	return float((birds_data.get("seabird_range_km", {}) as Dictionary).get(kind, 500.0))


## A colony's young in its breeding season ("eggs", "chicks" or ""): its
## hemisphere's spring for eggs, early summer for chicks, while it's home.
func young_now(colony: Dictionary, cal: float) -> String:
	if colony_where(colony, cal)[0] != "home":
		return ""
	var month := Birds.month_of(cal)
	var north: bool = (colony.spot as Vector2).y >= 0.0
	if month in ([4, 5] if north else [10, 11]):
		return "eggs"
	if month in ([6, 7] if north else [12, 1]):
		return "chicks"
	return ""


# --- Helpers ----------------------------------------------------------------------

## A spot `km` (Vector2 km east and north) from a (lon, lat).
static func _offset(spot: Vector2, km: Vector2) -> Vector2:
	return spot + Vector2(km.x / (KM_PER_DEGREE * maxf(cos(deg_to_rad(spot.y)), 0.1)), km.y / KM_PER_DEGREE)


## True if a spot and the ring round it `km` out (and halfway) are all on land.
static func _range_on_land(spot: Vector2, km: float) -> bool:
	if not MapView._on_land(spot):
		return false
	for k in 12:
		var way := Vector2.from_angle(TAU * k / 12.0)
		if not MapView._on_land(_offset(spot, way * km)) or not MapView._on_land(_offset(spot, way * km * 0.5)):
			return false
	return true


## A steady point in the unit disc for the parts given.
static func _disc(parts: Array) -> Vector2:
	var angle := Birds.chance(parts + ["a"]) * TAU
	return Vector2.from_angle(angle) * sqrt(Birds.chance(parts + ["r"]))


static func _cell(spot: Vector2) -> Vector2i:
	return Vector2i(floori(spot.x / CELL_DEG), floori(spot.y / CELL_DEG))


## The indices filed in the cells a box of (lon, lat) covers (each once).
static func _in_cells(cells: Dictionary, box: Rect2) -> Array:
	var seen := {}
	var out := []
	for x in range(floori(box.position.x / CELL_DEG) - 1, floori(box.end.x / CELL_DEG) + 2):
		for y in range(floori(box.position.y / CELL_DEG) - 1, floori(box.end.y / CELL_DEG) + 2):
			for index: int in cells.get(Vector2i(x, y), []):
				if not seen.has(index):
					seen[index] = true
					out.append(index)
	return out


## A steady number from 0 to 1 for an integer (a quick mix: the wildlife asks
## for many every frame; Birds.chance() is for words).
static func _mix(n: int) -> float:
	var h := n & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h ^= h >> 16
	return float(h & 0x7fffffff) / float(0x7fffffff)


## A steady point in the unit disc for an integer.
static func _disc_n(n: int) -> Vector2:
	return Vector2.from_angle(_mix(n) * TAU) * sqrt(_mix(n ^ 0x5bd1e995))


## The month (1 to 12) at a calendar time, worked out once an hour of it.
func _month(cal: float) -> int:
	var hour := floori(cal / 3600.0)
	if hour != _month_hour:
		_month_hour = hour
		_month_now = Birds.month_of(cal)
	return _month_now


## The colonies with their home or away spot in or near a box of (lon, lat).
func colonies_near(box: Rect2) -> Array:
	if not ensure_built():
		return []
	return _in_cells(_colony_cells, box)
