# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Energy
extends RefCounted
## Oil and gas (data/energy.json), for Tankers companies: the offshore fields
## and their slots (oil rigs on oil fields, gas platforms on gas fields: who
## owns each, its upgrades, its storm damage, its pipeline), each company's
## storage at the fields and its stores at ports, and the buildings it puts up
## at ports (refineries and the hydrogen & ammonia plant) that turn one good
## into another. GameState owns one (its energy) and runs it a day at a time;
## its actions are GameState's (with their Net commands), which call the ones
## here for a company.
##
## Slots are keyed "FIELD#n" (n from 0). A field's end of its sea lanes is a
## port-like place "@rig_FIELD" (GameData.get_port()), reached like a fishing
## ground's: ships on rig runs (GameState) sail out to it, load what the
## company's rigs there have stored, and bring it to their delivery port.

const PATH := "res://data/energy.json"
const DAY_S := 86400.0
## A field's end of its lanes, as a port id: "@rig_brent".
const END_PREFIX := "@rig_"
## How the production tallies fade (a day): the rating looks at about the last few months.
const TALLY_FADE := 0.985

static var _data := {}
static var _fields := {}
static var _buildings := {}

## Slot key -> {owner (company index in GameState.all_companies()), kind ("rig"
## or "platform"), upgrades [ids], damage (0 sound, 1 damaged: half, 2
## stopped), shut (a storm over it today), listing (asking price, 0 if not
## listed), paid, pipe (the port its pipeline runs to, "" for none), tug (the
## id of the tug sent to repair it, 0 for none)}. Only slots ever bought are here.
var slots := {}
## The calendar day last run (-1 until the first step).
var day := -1
## Counts every change (the map redraws when it moves on).
var version := 0
var _state: Node


func _init(state: Node) -> void:
	_state = state


func _changed() -> void:
	version += 1
	_state.energy_changed.emit()


# --- The data ---------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {}
		for field: Dictionary in _data.get("fields", []):
			_fields[field.id] = field
		for building: Dictionary in _data.get("buildings", []):
			_buildings[building.id] = building
	return _data


static func settings() -> Dictionary:
	return data().get("settings", {})


static func setting(key: String, default: Variant = 0.0) -> Variant:
	return settings().get(key, default)


## The fields' ids, in the data's order.
static func field_ids() -> Array[String]:
	data()
	var out: Array[String] = []
	out.assign(_fields.keys())
	return out


## A field: {id, name, kind ("oil" or "gas"), lon, lat, richness, slots, known}, or {}.
static func field(field_id: String) -> Dictionary:
	data()
	return _fields.get(field_id, {})


static func field_name(field_id: String) -> String:
	return str(field(field_id).get("name", field_id))


## What a slot on a field holds: "rig" on an oil field, "platform" on a gas field.
static func kind_on(field_id: String) -> String:
	return "rig" if str(field(field_id).get("kind", "oil")) == "oil" else "platform"


## A rig kind's data: {name, field, cost, output_t, gas_share, storage, wages}.
static func rig_info(kind: String) -> Dictionary:
	return data().get("rigs", {}).get(kind, {})


static func rig_upgrade(upgrade_id: String) -> Dictionary:
	for each: Dictionary in data().get("rig_upgrades", []):
		if each.id == upgrade_id:
			return each
	return {}


## A building: {id, name, input, outputs {commodity: tons a ton}, rate, cost, wages, tank_days, tier, text}, or {}.
static func building(building_id: String) -> Dictionary:
	data()
	return _buildings.get(building_id, {})


static func building_ids() -> Array[String]:
	data()
	var out: Array[String] = []
	out.assign(_buildings.keys())
	return out


static func building_upgrade(upgrade_id: String) -> Dictionary:
	for each: Dictionary in data().get("building_upgrades", []):
		if each.id == upgrade_id:
			return each
	return {}


## A field's end of its lanes ("@rig_brent"), and back.
static func end_of(field_id: String) -> String:
	return END_PREFIX + field_id


static func is_field_end(port_id: String) -> bool:
	return port_id.begins_with(END_PREFIX)


static func field_of_end(port_id: String) -> String:
	return port_id.substr(END_PREFIX.length())


static func key_of(field_id: String, index: int) -> String:
	return "%s#%d" % [field_id, index]


static func field_of(key: String) -> String:
	return key.get_slice("#", 0)


static func index_of(key: String) -> int:
	return int(key.get_slice("#", 1))


## A field's slot keys.
static func keys_at(field_id: String) -> Array[String]:
	var out: Array[String] = []
	for i in int(field(field_id).get("slots", 0)):
		out.append(key_of(field_id, i))
	return out


## The most of a field's slots one company may own (max_share of them).
static func most_at(field_id: String) -> int:
	return maxi(floori(int(field(field_id).get("slots", 0)) * float(setting("max_share", 0.5))), 1)


## The goods a field gives: crude oil (and some gas) on an oil field, gas on a gas field.
static func products_of(field_id: String) -> Array[String]:
	if kind_on(field_id) == "rig":
		return ["oil", "gas", "lpg"]
	return ["gas", "lpg"]


## True if a company works in oil and gas: a Tankers company (or one from before types).
static func can_drill(who: Company) -> bool:
	return who != null and who.has_type("tankers")


## The company level a Tankers tier unlocks at for a company (its tanker of that tier's).
static func tier_level(tier: int, who: Company) -> int:
	for model: Dictionary in GameData.ship_models:
		if str(model.get("category", "")) == "tanker" and int(model.get("tier", 0)) == tier:
			return Progression.unlock_level(model, who)
	return Progression.LOCKED


## The company level a thing unlocks at: a building's id, "rig", "platform" or "pipeline".
static func unlock_level(what: String, who: Company) -> int:
	var tier := int(building(what).get("tier", 0))
	if tier <= 0:
		tier = int(setting(what + "_tier", 3))
	return tier_level(tier, who)


static func unlocked(what: String, who: Company) -> bool:
	return can_drill(who) and who.level() >= unlock_level(what, who)


## The ports a field's lanes run from (the lane tool's, nearest first).
static func lane_ports(field_id: String) -> Array:
	if _lane_ports.is_empty():
		_lane_ports = GameData.fishing_lanes()
	return _lane_ports.get(end_of(field_id), [])
static var _lane_ports := {}


## The port a ship from `base` sets out to a field by (one of the ports its
## lanes run from, the one making the trip shortest, or `base` itself when
## its own lane straight out is about as short), and the miles one way:
## [port, miles], or ["", INF] if there's no way.
static func way_to(base: String, field_id: String) -> Array:
	var key := base + ">" + field_id
	if _ways.has(key):
		return _ways[key]
	var best := ""
	var best_nm := INF
	var end := end_of(field_id)
	for port: String in lane_ports(field_id):
		if port == base:
			continue
		var nm := GameData.distance_nm(base, port, -1) + GameData.distance_nm(port, end, -1)
		if nm < best_nm:
			best_nm = nm
			best = port
	var straight := GameData.distance_nm(base, end, -1)
	var way := [base, straight] if straight < INF and straight <= best_nm * 1.3 else [best, best_nm]
	_ways[key] = way
	return way
static var _ways := {}


## The sea miles from a port to a field, INF if there's no way.
static func miles_to(base: String, field_id: String) -> float:
	return float(way_to(base, field_id)[1])


## A trip's legs out to a field from `base` and back: [out, home], each a list
## of [from, to, start_nm, end_nm] segments.
static func legs(base: String, field_id: String) -> Array:
	var port: String = way_to(base, field_id)[0]
	var end := end_of(field_id)
	var out := []
	var home := []
	if base != port:
		out.append([base, port, 0.0, GameData.distance_nm(base, port, -1)])
	out.append([port, end, 0.0, GameData.distance_nm(port, end, -1)])
	home.append([end, port, 0.0, GameData.distance_nm(end, port, -1)])
	if base != port:
		home.append([port, base, 0.0, GameData.distance_nm(port, base, -1)])
	return [out, home]


# --- State ---------------------------------------------------------------------------

func reset() -> void:
	slots.clear()
	day = -1


func to_dict() -> Dictionary:
	return {slots = slots, day = day}


func from_dict(saved: Dictionary) -> void:
	slots = saved.get("slots", {}) if saved.get("slots") is Dictionary else {}
	day = int(saved.get("day", -1))
	version += 1
	for key: String in slots:
		var entry: Dictionary = slots[key]
		entry.owner = int(entry.get("owner", -1))
		entry.damage = int(entry.get("damage", 0))
		entry.tug = int(entry.get("tug", 0))


func slot(key: String) -> Dictionary:
	return slots.get(key, {})


## The company owning a slot, or null for a free one.
func owner_of(key: String) -> Company:
	var index := int(slot(key).get("owner", -1))
	var all: Array[Company] = _state.all_companies()
	return all[index] if index >= 0 and index < all.size() else null


func _index_of(who: Company) -> int:
	return _state.all_companies().find(who)


## A company's slots (keys), by field.
func owned_by(who: Company, field_id := "") -> Array[String]:
	var index := _index_of(who)
	var out: Array[String] = []
	for key: String in slots:
		if int(slots[key].get("owner", -1)) == index and (field_id.is_empty() or field_of(key) == field_id):
			out.append(key)
	out.sort_custom(func(a: String, b: String) -> bool: return a < b if field_of(a) != field_of(b) else index_of(a) < index_of(b))
	return out


## The fields a company has slots on.
func fields_of(who: Company) -> Array[String]:
	var out: Array[String] = []
	for key in owned_by(who):
		if not out.has(field_of(key)):
			out.append(field_of(key))
	return out


func taken_at(field_id: String) -> int:
	var count := 0
	for key in keys_at(field_id):
		if owner_of(key) != null:
			count += 1
	return count


func _has(key: String, upgrade_id: String) -> bool:
	return (slot(key).get("upgrades", []) as Array).has(upgrade_id)


## A slot's output a year (tons, all its goods), as it is now (its damage in).
func output_a_year(key: String, with_damage := true) -> float:
	var entry := slot(key)
	var info := rig_info(str(entry.get("kind", kind_on(field_of(key)))))
	var amount := float(info.get("output_t", 0.0)) * float(field(field_of(key)).get("richness", 1.0)) * (1.0 + float(info.get("gas_share", 0.0)))
	if _has(key, "wells"):
		amount *= float(rig_upgrade("wells").get("output", 1.3))
	if with_damage:
		amount *= [1.0, 0.5, 0.0][clampi(int(entry.get("damage", 0)), 0, 2)]
	return amount


## What a slot makes in a day, by good: {commodity: tons}.
func day_output(key: String) -> Dictionary:
	var entry := slot(key)
	var kind := str(entry.get("kind", kind_on(field_of(key))))
	var info := rig_info(kind)
	var total := output_a_year(key) / 365.0
	if bool(entry.get("shut", false)) or total <= 0.0:
		return {}
	var lng := float(setting("lng_share", 0.75))
	if kind == "rig":
		var gas := total * float(info.get("gas_share", 0.0)) / (1.0 + float(info.get("gas_share", 0.0)))
		return {oil = total - gas, gas = gas * lng, lpg = gas * (1.0 - lng)}
	return {gas = total * lng, lpg = total * (1.0 - lng)}


## How much a slot holds at sea (its Bigger storage more).
func storage_of(key: String) -> float:
	if _has(key, "storage"):
		return float(rig_upgrade("storage").get("storage", 60000))
	return float(rig_info(str(slot(key).get("kind", kind_on(field_of(key))))).get("storage", 20000))


## A company's storage at a field: {commodity: tons}.
func sea_items(who: Company, field_id: String) -> Dictionary:
	return who.energy_sea.get(field_id, {})


func sea_total(who: Company, field_id: String) -> float:
	var total := 0.0
	var items := sea_items(who, field_id)
	for item: String in items:
		total += float(items[item])
	return total


## What a company's rigs at a field can hold (those without a pipeline).
func sea_room(who: Company, field_id: String) -> float:
	var room := 0.0
	for key in owned_by(who, field_id):
		if str(slot(key).get("pipe", "")).is_empty():
			room += storage_of(key)
	return room


## A good's share of what a field's rigs make (a rig's crude most of it).
func product_share(field_id: String, commodity: String) -> float:
	var info := rig_info(kind_on(field_id))
	var gas := float(info.get("gas_share", 0.0)) / (1.0 + float(info.get("gas_share", 0.0))) if kind_on(field_id) == "rig" else 1.0
	var lng := float(setting("lng_share", 0.75))
	match commodity:
		"oil":
			return 1.0 - gas if kind_on(field_id) == "rig" else 0.0
		"gas":
			return gas * lng
		"lpg":
			return gas * (1.0 - lng)
	return 0.0


## The room a company's storage at a field has left for a good: its share of the whole.
func sea_room_for(who: Company, field_id: String, commodity: String) -> float:
	return maxf(sea_room(who, field_id) * product_share(field_id, commodity) - float(sea_items(who, field_id).get(commodity, 0.0)), 0.0)


## A good's name in a sentence: "crude oil", "diesel", but "LNG" and "LPG" as they are.
static func good_word(commodity: String) -> String:
	var name := str(GameData.commodity(commodity).get("name", commodity))
	return name if name == name.to_upper() else name.to_lower()


## The calendar day now (since the calendar's start).
func today() -> int:
	return floori((_state.calendar_time() - _state.calendar_time_at(0.0)) / DAY_S)


# --- Buildings and the port stores ----------------------------------------------------------

## A company's buildings at a port: {building id: {upgrades, mode}}.
func plants_at(who: Company, port_id: String) -> Dictionary:
	return who.plants.get(port_id, {})


## Every port where a company has buildings.
func plant_ports(who: Company) -> Array[String]:
	var out: Array[String] = []
	for port_id: String in who.plants:
		if not (who.plants[port_id] as Dictionary).is_empty():
			out.append(port_id)
	out.sort()
	return out


func _plant_has(who: Company, port_id: String, building_id: String, upgrade_id: String) -> bool:
	return (plants_at(who, port_id).get(building_id, {}).get("upgrades", []) as Array).has(upgrade_id)


## A building's input a day (tons), its upgrades in.
func rate_of(who: Company, port_id: String, building_id: String) -> float:
	return float(building(building_id).get("rate", 0.0)) * (1.25 if _plant_has(who, port_id, building_id, "throughput") else 1.0)


## A building's tank (tons), its upgrades in.
func tank_of(who: Company, port_id: String, building_id: String) -> float:
	var info := building(building_id)
	return float(info.get("rate", 0.0)) * float(info.get("tank_days", 20)) * (2.0 if _plant_has(who, port_id, building_id, "tanks") else 1.0)


## What a building makes now: its output (the plant's mode for one with a choice).
func output_of(who: Company, port_id: String, building_id: String) -> String:
	var outputs: Dictionary = building(building_id).get("outputs", {})
	var mode := str(plants_at(who, port_id).get(building_id, {}).get("mode", ""))
	if outputs.has(mode):
		return mode
	return str(outputs.keys()[0]) if not outputs.is_empty() else ""


## The goods a company's buildings at a port take in.
func inputs_at(who: Company, port_id: String) -> Array[String]:
	var out: Array[String] = []
	for building_id: String in plants_at(who, port_id):
		var input := str(building(building_id).get("input", ""))
		if not out.has(input):
			out.append(input)
	return out


## A company's store at a port: {commodity: tons}.
func store_items(who: Company, port_id: String) -> Dictionary:
	return who.energy_stores.get(port_id, {})


## How much of a good a company's store at a port can hold: the tanks of its
## buildings there that take it in or make it, and its pipelines' there.
func store_cap(who: Company, port_id: String, commodity: String) -> float:
	var cap := 0.0
	for building_id: String in plants_at(who, port_id):
		var info := building(building_id)
		if str(info.get("input", "")) == commodity or output_of(who, port_id, building_id) == commodity:
			cap += tank_of(who, port_id, building_id)
	for key in owned_by(who):
		if str(slot(key).get("pipe", "")) == port_id and products_of(field_of(key)).has(commodity):
			cap += float(setting("pipe_storage", 60000))
	return cap


func store_room(who: Company, port_id: String, commodity: String) -> float:
	return maxf(store_cap(who, port_id, commodity) - float(store_items(who, port_id).get(commodity, 0.0)), 0.0)


func _add_store(who: Company, port_id: String, commodity: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var items: Dictionary = who.energy_stores.get_or_add(port_id, {})
	items[commodity] = float(items.get(commodity, 0.0)) + amount


func _take_store(who: Company, port_id: String, commodity: String, amount: float) -> void:
	var items: Dictionary = who.energy_stores.get(port_id, {})
	if not items.has(commodity):
		return
	items[commodity] = float(items[commodity]) - amount
	if float(items[commodity]) < 0.5:
		items.erase(commodity)
	if items.is_empty():
		who.energy_stores.erase(port_id)


## What a company's store at a port is worth there.
func store_value(who: Company, port_id: String) -> int:
	var total := 0.0
	var items := store_items(who, port_id)
	for item: String in items:
		total += float(items[item]) * float(_state.company_sell_price(port_id, item, who))
	return roundi(total)


# --- The days ---------------------------------------------------------------------------

func step(_delta: float) -> void:
	var now := today()
	if day < 0:
		day = now
		return
	var ran := 0
	while day < now and ran < 4:  # (Fast forward: a few days a step at most, the rest the next steps.)
		day += 1
		ran += 1
		_run_day()
	if ran > 0:
		_changed()


func _run_day() -> void:
	var all: Array[Company] = _state.all_companies()
	for who in all:
		for tally: String in ["made", "lost", "processed", "idle"]:
			who.energy_tally[tally] = float(who.energy_tally.get(tally, 0.0)) * TALLY_FADE
	var storms := {}  # Field -> strength today.
	for key: String in slots.keys():
		var entry: Dictionary = slots[key]
		var index := int(entry.get("owner", -1))
		if index < 0 or index >= all.size():
			continue
		var field_id := field_of(key)
		if not storms.has(field_id):
			storms[field_id] = _storm_at(field_id)
		_weather(all[index], key, entry, float(storms[field_id]))
		_produce(all[index], key, entry)
	for who in all:
		for port_id in plant_ports(who):
			_run_plants(who, port_id)


## The strongest storm's strength over a field now (0 if storms are off).
func _storm_at(field_id: String) -> float:
	if not _state.weather.active():
		return 0.0
	var info := field(field_id)
	return float(_state.weather.strongest_at(Vector2(float(info.get("lon", 0.0)), float(info.get("lat", 0.0))))[1])


## A storm over a slot shuts it for the day; a strong one may damage it.
func _weather(who: Company, key: String, entry: Dictionary, strength: float) -> void:
	entry.shut = strength > float(setting("shut_at", 0.3))
	if strength <= float(setting("damage_at", 0.6)) or int(entry.get("damage", 0)) >= 2:
		return
	var odds := float(setting("damage_odds", 0.35)) * (float(setting("hardened_odds", 0.5)) if _has(key, "hardening") else 1.0)
	if randf() >= odds:
		return
	entry.damage = int(entry.get("damage", 0)) + 1
	if who == _state.company:
		var what := rig_info(str(entry.kind)).get("name", "rig") as String
		var how := "making half its output" if int(entry.damage) == 1 else "stopped"
		ActivityLog.add("A storm damaged your %s at %s: %s till a tug repairs it (the Energy tab)." % [what.to_lower(), field_name(field_of(key)), how], ActivityLog.Kind.BAD)


## A day of a slot's output: into its pipeline's store, or its storage at sea
## (each good its share of the room, so gas no ship collects never stops the
## crude); what has no room is lost (the rig throttles back).
func _produce(who: Company, key: String, entry: Dictionary) -> void:
	var made := day_output(key)
	if made.is_empty():
		return
	var field_id := field_of(key)
	var pipe := str(entry.get("pipe", ""))
	for commodity: String in made:
		var room := sea_room_for(who, field_id, commodity)
		var amount := float(made[commodity])
		var value := float(GameData.commodity(commodity).get("base", 0.0))
		if not pipe.is_empty():
			var piped := minf(amount, store_room(who, pipe, commodity))
			_add_store(who, pipe, commodity, piped)
			amount -= piped
			who.energy_tally.made = float(who.energy_tally.get("made", 0.0)) + piped * value
		var kept := minf(amount, maxf(room, 0.0))
		if kept > 0.0:
			var items: Dictionary = who.energy_sea.get_or_add(field_id, {})
			items[commodity] = float(items.get(commodity, 0.0)) + kept
			amount -= kept
			who.energy_tally.made = float(who.energy_tally.get("made", 0.0)) + kept * value
		if amount > 0.0:
			who.energy_tally.lost = float(who.energy_tally.get("lost", 0.0)) + amount * value


## A day of a company's buildings at a port, each taking its input from the
## store and putting its output back, as far as both tanks allow.
func _run_plants(who: Company, port_id: String) -> void:
	var plants := plants_at(who, port_id)
	# In the order of the chain (crude to diesel before diesel to gasoline...).
	for building_id in building_ids():
		if not plants.has(building_id):
			continue
		var info := building(building_id)
		var input := str(info.get("input", ""))
		var output := output_of(who, port_id, building_id)
		var yield_t := float((info.get("outputs", {}) as Dictionary).get(output, 1.0))
		var rate := rate_of(who, port_id, building_id)
		var held := float(store_items(who, port_id).get(input, 0.0))
		var take := minf(rate, held)
		if yield_t > 0.0:
			take = minf(take, store_room(who, port_id, output) / yield_t)
		var value := rate * float(GameData.commodity(input).get("base", 0.0))
		if take <= 0.0:
			who.energy_tally.idle = float(who.energy_tally.get("idle", 0.0)) + value
			continue
		_take_store(who, port_id, input, take)
		_add_store(who, port_id, output, take * yield_t)
		who.energy_tally.processed = float(who.energy_tally.get("processed", 0.0)) + take * float(GameData.commodity(input).get("base", 0.0))
		who.energy_tally.idle = float(who.energy_tally.get("idle", 0.0)) + value * (1.0 - take / rate)


## Wages for a pay period: each rig's and platform's crew, and each building's
## workers (half with Automation). Called with the crews' wages.
func pay_wages() -> void:
	var all: Array[Company] = _state.all_companies()
	var paid := {}
	for key: String in slots:
		var entry: Dictionary = slots[key]
		var index := int(entry.get("owner", -1))
		if index < 0 or index >= all.size():
			continue
		paid[all[index]] = float(paid.get(all[index], 0.0)) + float(rig_info(str(entry.get("kind", "rig"))).get("wages", 0.0))
	for who in all:
		for port_id in plant_ports(who):
			for building_id: String in plants_at(who, port_id):
				var wages := float(building(building_id).get("wages", 0.0)) * (0.5 if _plant_has(who, port_id, building_id, "automation") else 1.0)
				paid[who] = float(paid.get(who, 0.0)) + wages
	for who: Company in paid:
		var total := roundi(paid[who])
		_state._add_money(who, -total)
		_state._record(null, "energy", total, who)


# --- Actions (a company's, through GameState) ---------------------------------------------------

func _money_error(who: Company, cost: int) -> String:
	return "Not enough money" if _state.in_debt(who) or who.money < cost else ""


## Why a company can't buy a free slot ("" if it can).
func buy_error(who: Company, key: String) -> String:
	var field_id := field_of(key)
	if not can_drill(who):
		return "Only Tankers companies drill"
	if field(field_id).is_empty() or index_of(key) >= int(field(field_id).get("slots", 0)):
		return "No such slot"
	var kind := kind_on(field_id)
	if not unlocked(kind, who):
		return "Unlocks at level %d" % unlock_level(kind, who)
	if owner_of(key) != null:
		return "Owned by %s" % owner_of(key).name
	if owned_by(who, field_id).size() >= most_at(field_id):
		return "You can own at most %d of the %d slots here" % [most_at(field_id), int(field(field_id).get("slots", 0))]
	if lane_ports(field_id).is_empty():
		return "No way out to it"
	return _money_error(who, int(rig_info(kind).get("cost", 0)))


func buy(who: Company, key: String) -> void:
	if not buy_error(who, key).is_empty():
		return
	var kind := kind_on(field_of(key))
	var cost := int(rig_info(kind).get("cost", 0))
	_state._add_money(who, -cost)
	_state._record(null, "energy_built", cost, who)
	slots[key] = {owner = _index_of(who), kind = kind, upgrades = [], damage = 0, shut = false, listing = 0, paid = cost, pipe = "", tug = 0}
	_changed()


func sell_error(who: Company, key: String) -> String:
	return "" if owner_of(key) == who and who != null else "Not yours"


## What selling a slot back pays: sale_share of its rig's cost.
func sale_price(key: String) -> int:
	return roundi(float(rig_info(str(slot(key).get("kind", kind_on(field_of(key))))).get("cost", 0)) * float(setting("sale_share", 0.5)) / 10000.0) * 10000


## Sells a slot back (its upgrades and pipeline with it; what's stored at sea stays while other rigs there hold it).
func sell_back(who: Company, key: String) -> int:
	if not sell_error(who, key).is_empty():
		return 0
	var price := sale_price(key)
	slots.erase(key)
	_trim_sea(who, field_of(key))
	_state._add_money(who, price)
	_state._record(null, "energy_sold", price, who)
	_changed()
	return price


## Throws away what a company's storage at a field can no longer hold.
func _trim_sea(who: Company, field_id: String) -> void:
	var room := sea_room(who, field_id)
	var total := sea_total(who, field_id)
	if total <= room:
		return
	var items := sea_items(who, field_id)
	var keep := room / total if total > 0.0 else 0.0
	for item: String in items.keys():
		items[item] = float(items[item]) * keep
		if float(items[item]) < 0.5:
			items.erase(item)
	if items.is_empty():
		who.energy_sea.erase(field_id)


func list(who: Company, key: String, price: int) -> void:
	if owner_of(key) != who or who == null:
		return
	slots[key].listing = maxi(price, 0)
	_changed()


func listing_error(who: Company, key: String) -> String:
	var entry := slot(key)
	var seller := owner_of(key)
	if seller == null or int(entry.get("listing", 0)) <= 0:
		return "Not for sale"
	if seller == who:
		return "Your own"
	if not can_drill(who):
		return "Only Tankers companies drill"
	if owned_by(who, field_of(key)).size() >= most_at(field_of(key)):
		return "You can own at most %d of the slots here" % most_at(field_of(key))
	return _money_error(who, int(entry.listing))


## Buys a listed slot with its rig, upgrades and pipeline (a pipeline to a port
## where the buyer has no HQ or hub is taken up).
func buy_listing(who: Company, key: String) -> void:
	if not listing_error(who, key).is_empty():
		return
	var entry: Dictionary = slots[key]
	var seller := owner_of(key)
	var price := int(entry.listing)
	_state._add_money(who, -price)
	_state._record(null, "energy_built", price, who)
	_state._add_money(seller, price)
	_state._record(null, "energy_sold", price, seller)
	entry.owner = _index_of(who)
	entry.listing = 0
	entry.paid = price
	if not str(entry.get("pipe", "")).is_empty() and who.hub_at(str(entry.pipe)) == null:
		entry.pipe = ""
	_trim_sea(seller, field_of(key))
	if seller == _state.company:
		ActivityLog.add("%s bought your %s at %s for %s." % [who.name, str(rig_info(str(entry.kind)).get("name", "rig")).to_lower(), field_name(field_of(key)), Fmt.money(price)], ActivityLog.Kind.GOOD)
	_changed()


func upgrade_error(who: Company, key: String, upgrade_id: String) -> String:
	var info := rig_upgrade(upgrade_id)
	if owner_of(key) != who or who == null:
		return "Not yours"
	if info.is_empty():
		return "No such upgrade"
	if _has(key, upgrade_id):
		return "Built"
	return _money_error(who, int(info.cost))


func add_upgrade(who: Company, key: String, upgrade_id: String) -> void:
	if not upgrade_error(who, key, upgrade_id).is_empty():
		return
	var cost := int(rig_upgrade(upgrade_id).cost)
	_state._add_money(who, -cost)
	_state._record(null, "energy_built", cost, who)
	(slots[key].upgrades as Array).append(upgrade_id)
	_changed()


## The nearest of a company's HQ and hubs a pipeline from a field can reach:
## [port, miles], or ["", INF].
func pipe_target(who: Company, field_id: String) -> Array:
	var best := ""
	var best_nm := INF
	for hub: Hub in who.hubs:
		var nm := GameData.distance_nm(hub.port_id, end_of(field_id), -1)
		if nm < best_nm:
			best_nm = nm
			best = hub.port_id
	if best_nm > float(setting("pipeline_nm", 300)):
		return ["", INF]
	return [best, best_nm]


func pipe_cost(miles: float) -> int:
	return roundi((float(setting("pipeline_cost", 40000000)) + float(setting("pipeline_per_nm", 100000)) * miles) / 100000.0) * 100000


func pipe_error(who: Company, key: String) -> String:
	if owner_of(key) != who or who == null:
		return "Not yours"
	if not str(slot(key).get("pipe", "")).is_empty():
		return "Piped to %s" % GameData.port_name(str(slot(key).pipe))
	if not unlocked("pipeline", who):
		return "Unlocks at level %d" % unlock_level("pipeline", who)
	var target := pipe_target(who, field_of(key))
	if str(target[0]).is_empty():
		return "No HQ or hub of yours within %d nm" % int(setting("pipeline_nm", 300))
	return _money_error(who, pipe_cost(float(target[1])))


## Lays a pipeline from a slot to the company's nearest HQ or hub in reach.
func lay_pipe(who: Company, key: String) -> void:
	if not pipe_error(who, key).is_empty():
		return
	var target := pipe_target(who, field_of(key))
	var cost := pipe_cost(float(target[1]))
	_state._add_money(who, -cost)
	_state._record(null, "energy_built", cost, who)
	slots[key].pipe = str(target[0])
	_trim_sea(who, field_of(key))
	_changed()


## Why a company can't put up a building at a port ("" if it can).
func build_error(who: Company, building_id: String, port_id: String) -> String:
	var info := building(building_id)
	if info.is_empty():
		return "No such building"
	if not can_drill(who):
		return "Only Tankers companies build these"
	if not unlocked(building_id, who):
		return "Unlocks at level %d" % unlock_level(building_id, who)
	if GameData.get_port(port_id).is_empty() or is_field_end(port_id) or port_id.begins_with("@"):
		return "Not a port"
	if not _state.port_open_to(who, port_id):
		return "Unlock %s first" % GameData.port_region(port_id).get("name", "its region")
	if plants_at(who, port_id).has(building_id):
		return "Built here"
	return _money_error(who, int(info.cost))


func build(who: Company, building_id: String, port_id: String) -> void:
	if not build_error(who, building_id, port_id).is_empty():
		return
	var info := building(building_id)
	_state._add_money(who, -int(info.cost))
	_state._record(null, "energy_built", int(info.cost), who)
	var plants: Dictionary = who.plants.get_or_add(port_id, {})
	plants[building_id] = {upgrades = [], mode = str((info.get("outputs", {}) as Dictionary).keys()[0])}
	_changed()


## Pulls a building down for sale_share of its cost (what its tanks held stays in the store to load).
func demolish(who: Company, building_id: String, port_id: String) -> int:
	if not plants_at(who, port_id).has(building_id):
		return 0
	var refund := roundi(int(building(building_id).cost) * float(setting("sale_share", 0.5)))
	(who.plants[port_id] as Dictionary).erase(building_id)
	if (who.plants[port_id] as Dictionary).is_empty():
		who.plants.erase(port_id)
	_state._add_money(who, refund)
	_state._record(null, "energy_sold", refund, who)
	_changed()
	return refund


func building_upgrade_cost(building_id: String, upgrade_id: String) -> int:
	return roundi(int(building(building_id).get("cost", 0)) * float(building_upgrade(upgrade_id).get("share", 0.0)) / 100000.0) * 100000


func plant_upgrade_error(who: Company, building_id: String, port_id: String, upgrade_id: String) -> String:
	if not plants_at(who, port_id).has(building_id):
		return "Not built"
	if building_upgrade(upgrade_id).is_empty():
		return "No such upgrade"
	if _plant_has(who, port_id, building_id, upgrade_id):
		return "Built"
	return _money_error(who, building_upgrade_cost(building_id, upgrade_id))


func upgrade_plant(who: Company, building_id: String, port_id: String, upgrade_id: String) -> void:
	if not plant_upgrade_error(who, building_id, port_id, upgrade_id).is_empty():
		return
	var cost := building_upgrade_cost(building_id, upgrade_id)
	_state._add_money(who, -cost)
	_state._record(null, "energy_built", cost, who)
	(plants_at(who, port_id)[building_id].upgrades as Array).append(upgrade_id)
	_changed()


## Sets what a plant with a choice makes (the hydrogen & ammonia plant).
func set_mode(who: Company, building_id: String, port_id: String, mode: String) -> void:
	if not plants_at(who, port_id).has(building_id) or not (building(building_id).get("outputs", {}) as Dictionary).has(mode):
		return
	plants_at(who, port_id)[building_id].mode = mode
	_changed()


## Sells what a company's store at a port holds of a good, at the port's price.
func sell_item(who: Company, port_id: String, commodity: String) -> int:
	var units := floori(float(store_items(who, port_id).get(commodity, 0.0)))
	if units <= 0:
		return 0
	var value := roundi(units * float(_state.company_sell_price(port_id, commodity, who)))
	_take_store(who, port_id, commodity, units)
	_state._add_money(who, value)
	_state._record(null, "energy_sales", value, who)
	_state._tally_port_trade(who, port_id, commodity, units, value, true)
	_state.market.trade(port_id, commodity, value, false)
	_changed()
	return value


# --- Repairs ------------------------------------------------------------------------------------

## What repairing a slot costs (repair_fee a step of its damage).
func repair_fee(key: String) -> int:
	return int(setting("repair_fee", 1500000)) * int(slot(key).get("damage", 0))


## The nearest of a company's tugs free to sail out to a slot and back:
## [tug, miles one way], or [null, INF].
func repair_tug(who: Company, key: String) -> Array:
	var best: Ship = null
	var best_nm := INF
	for tug: Ship in _state.fleet(who):
		if not tug.is_tug() or tug.is_on_job() or not tug.is_docked() or tug.is_lost() or tug.rescuing != null:
			continue
		var nm := miles_to(tug.docked_at, field_of(key))
		# (Its fuel there and back is the limit, not its towing reach: it sails out on its own.)
		if nm < best_nm and tug.fuel_per_s() * (2.0 * nm / maxf(tug.speed(), 0.01) + GameState.DEPARTURE_MARGIN_S) <= tug.fuel:
			best_nm = nm
			best = tug
	return [best, best_nm]


func repair_error(who: Company, key: String) -> String:
	if owner_of(key) != who or who == null:
		return "Not yours"
	if int(slot(key).get("damage", 0)) <= 0:
		return "Not damaged"
	if int(slot(key).get("tug", 0)) != 0:
		return "A tug is on its way"
	if repair_tug(who, key)[0] == null:
		return "No free tug of yours has the fuel to reach it and come back (tugs come with the ports on your routes)"
	return _money_error(who, repair_fee(key))


## A tug finished its repair: the slot is sound again.
func repaired(key: String) -> void:
	if not slots.has(key):
		return
	slots[key].damage = 0
	slots[key].tug = 0
	var who := owner_of(key)
	if who == _state.company:
		ActivityLog.add("Your %s at %s is repaired and back at work." % [str(rig_info(str(slots[key].kind)).get("name", "rig")).to_lower(), field_name(field_of(key))], ActivityLog.Kind.GOOD)
	_changed()


# --- The ships ---------------------------------------------------------------------------------

## The goods a ship can collect from a field.
static func carries_from(model: Dictionary, field_id: String) -> Array[String]:
	var out: Array[String] = []
	for commodity in products_of(field_id):
		if (model.get("cargo", []) as Array).has(commodity):
			out.append(commodity)
	return out


## Why a ship can't run between a field and a port ("" if it can).
func run_error(who: Company, ship: Ship, field_id: String, port_id: String) -> String:
	if ship == null or ship.is_service() or ship.is_cruise():
		return "Not a cargo ship"
	if carries_from(ship.model(), field_id).is_empty():
		return "It can't carry what the field gives"
	if owned_by(who, field_id).is_empty():
		return "You have no rigs at %s" % field_name(field_id)
	if not ship.fits_port(port_id):
		return "%s is too small for it" % GameData.port_name(port_id)
	if not _state.port_open_to(who, port_id):
		return "Unlock %s first" % GameData.port_region(port_id).get("name", "its region")
	var miles := miles_to(port_id, field_id)
	if miles == INF:
		return "No way from %s to the field" % GameData.port_name(port_id)
	if miles * 2.0 > ship.range_nm():
		return "%s is %s nm out, too far there and back on one tank (%s nm)" % [field_name(field_id), Fmt.thousands(roundi(miles)), Fmt.thousands(roundi(ship.range_nm()))]
	return ""


## A ship at a field loads what its company's storage there holds that it
## carries: the good worth most at its delivery port (topping up the one it
## has aboard). Returns the tons it took.
func load_at_field(ship: Ship) -> int:
	var who: Company = _state.owner_of(ship)
	var field_id := ship.rig_field
	var items := sea_items(who, field_id)
	var pick := ship.cargo_id
	if pick.is_empty():
		var best := 0.0
		for commodity in carries_from(ship.model(), field_id):
			var held := float(items.get(commodity, 0.0))
			var gain := minf(held, ship.capacity()) * float(_state.company_sell_price(ship.rig_port, commodity, who))
			if held >= 1.0 and gain > best:
				best = gain
				pick = commodity
	if pick.is_empty():
		return 0
	var room := floori(ship.capacity() / GameData.hold_of(pick)) - ship.cargo_qty
	var take := mini(room, floori(float(items.get(pick, 0.0))))
	if take <= 0:
		return 0
	items[pick] = float(items[pick]) - take
	if float(items[pick]) < 0.5:
		items.erase(pick)
	if items.is_empty():
		who.energy_sea.erase(field_id)
	var cost := roundi(take * float(_state.company_sell_price(ship.rig_port, pick, who)) * 0.5)
	_state._record(ship, "cargo", cost)
	if ship.cargo_id.is_empty():
		ship.cargo_id = pick
		ship.cargo_from = end_of(field_id)
		ship.cargo_cost = 0
	ship.cargo_qty += take
	ship.cargo_cost += cost
	who.energy_tally.collected = float(who.energy_tally.get("collected", 0.0)) + take * float(GameData.commodity(pick).get("base", 0.0))
	return take


## A ship unloading at a port where its company's buildings take in its cargo:
## as much as the tanks have room for goes into the store. Returns the tons.
func take_delivery(who: Company, port_id: String, commodity: String, quantity: int) -> int:
	if not inputs_at(who, port_id).has(commodity):
		return 0
	var taken := mini(quantity, floori(store_room(who, port_id, commodity)))
	if taken <= 0:
		return 0
	_add_store(who, port_id, commodity, taken)
	_changed()
	return taken


## The input a ship should buy here for its company's buildings at its next
## port: one it carries that a building there takes in, with room in its tank
## for at least half its hold (the most room first). "" for none.
func feed_for(ship: Ship, to: String) -> String:
	var who: Company = _state.owner_of(ship)
	if who.plants.is_empty() or not who.plants.has(to):
		return ""
	var best := ""
	var best_room := 0.0
	var carries: Array = ship.model().get("cargo", [])
	for input in inputs_at(who, to):
		if not carries.has(input):
			continue
		var room := store_room(who, to, input)
		if room >= ship.capacity() * 0.5 and room > best_room:
			best_room = room
			best = input
	return best


## A ship loading at a port where its company's store holds goods it carries
## that no building there takes in: the one worth most where it's going, free
## (its worth here as the cargo's cost), up to its room. [commodity, tons] or [].
func load_ship(ship: Ship, to: String) -> Array:
	var who: Company = _state.owner_of(ship)
	var here := ship.docked_at
	var items := store_items(who, here)
	if items.is_empty():
		return []
	var inputs := inputs_at(who, here)
	var carries: Array = ship.model().get("cargo", [])
	var best := ""
	var best_gain := 0.0
	for commodity: String in items:
		if not carries.has(commodity) or inputs.has(commodity) or float(items[commodity]) < 1.0:
			continue
		var gain := minf(float(items[commodity]), ship.capacity()) * float(_state.company_sell_price(to, commodity, who))
		if gain > best_gain:
			best_gain = gain
			best = commodity
	if best.is_empty():
		return []
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(here, to, ship.model())) / GameData.hold_of(best))
	var quantity := mini(room, floori(float(items[best])))
	if quantity <= 0:
		return []
	_take_store(who, here, best, quantity)
	var cost := roundi(quantity * float(_state.company_sell_price(here, best, who)))
	_state._record(ship, "cargo", cost)
	ship.cargo_id = best
	ship.cargo_from = here
	ship.cargo_qty = quantity
	ship.cargo_cost = cost
	_state.cargo_loaded.emit(ship, here, best, quantity, cost, to)
	_state.ship_changed.emit(ship)
	_changed()
	return [best, quantity]


## Free bunkering: of `units` of fuel a ship takes at a port, how many its
## company's Diesel there pays for (at the port's fuel price against the
## Diesel's), taking that Diesel from the store.
func bunker(ship: Ship, units: float, fuel_price: float) -> float:
	var who: Company = _state.owner_of(ship)
	var here := ship.docked_at
	var held := float(store_items(who, here).get("diesel", 0.0))
	if held < 1.0 or units <= 0.0:
		return 0.0
	var diesel_price := maxf(float(_state.company_sell_price(here, "diesel", who)), 1.0)
	var tons := minf(units * fuel_price / diesel_price, held)
	_take_store(who, here, "diesel", tons)
	return tons * diesel_price / maxf(fuel_price, 0.0001)


# --- The rating's Production part -----------------------------------------------------------

## The Production part of a company's Tankers rating (0 to 5) and its figures:
## rigs and platforms owned against what its level expects (1 + level / 12, up
## to 8), the share of them working (not damaged or stopped), its buildings'
## use (the share of their capacity run lately) and the share of what its rigs
## made that was kept (not lost for want of room).
func rating_part(who: Company) -> Dictionary:
	var keys := owned_by(who)
	var working := 0
	for key in keys:
		if int(slot(key).get("damage", 0)) == 0:
			working += 1
	var expected := minf(1.0 + who.level() / 12.0, 8.0)
	var sound := float(working) / keys.size() if not keys.is_empty() else 0.0
	var processed := float(who.energy_tally.get("processed", 0.0))
	var idle := float(who.energy_tally.get("idle", 0.0))
	var used := processed / (processed + idle) if processed + idle > 0.0 else -1.0
	var made := float(who.energy_tally.get("made", 0.0))
	var lost := float(who.energy_tally.get("lost", 0.0))
	var kept := made / (made + lost) if made + lost > 0.0 else 1.0
	var built := plant_ports(who).size()
	if keys.is_empty() and built == 0:
		return {stars = 0.0, rigs = 0, expected = expected, sound = 0.0, used = 0.0, kept = 0.0, plants = 0}
	var scale := minf((keys.size() + built) / expected, 1.0)
	var stars := 5.0 * (0.35 * scale + 0.25 * sound + 0.2 * (used if used >= 0.0 else 0.5) + 0.2 * kept)
	return {stars = clampf(stars, 0.0, 5.0), rigs = keys.size(), expected = expected, sound = sound, used = maxf(used, 0.0), kept = kept, plants = built}


# --- The map ---------------------------------------------------------------------------------

## Where a field's rigs stand on the map, as (lon, lat): its lanes' end, then
## the rest spread round it in a ring.
func slot_position(key: String) -> Vector2:
	var place := GameData.get_port(end_of(field_of(key)))
	var center := Vector2(float(place.get("lon", field(field_of(key)).get("lon", 0.0))), float(place.get("lat", field(field_of(key)).get("lat", 0.0))))
	var count := maxi(int(field(field_of(key)).get("slots", 1)), 1)
	var angle := TAU * index_of(key) / count + 0.4
	var radius := 0.08  # Degrees (about 5 nm).
	return center + Vector2(cos(angle) * radius / maxf(cos(deg_to_rad(center.y)), 0.2), sin(angle) * radius)


# --- AI rivals ---------------------------------------------------------------------------------------

## A rival in oil and gas, simply (RivalAI, now and then): with money to
## spare, a slot on the field nearest its HQ that its ships can collect from
## (or a listed one), a refinery where its tankers call, a tug sent to a
## damaged rig. Returns news ("put up an oil rig at Brent").
func run_rival(rival: Company, spare: int) -> Array:
	var news := []
	if not can_drill(rival):
		return news
	var ships: Array[Ship] = _state.fleet(rival)
	var carries := {}
	for ship in ships:
		for commodity: String in ship.model().get("cargo", []):
			carries[commodity] = true
	if carries.is_empty():
		return news
	# Damaged rigs: a tug if one can go.
	for key in owned_by(rival):
		if repair_error(rival, key).is_empty():
			_state._send_rig_tug(rival, key)
		elif int(slot(key).get("damage", 0)) > 0 and int(slot(key).get("tug", 0)) == 0 and randf() < 0.05 and rival.money > repair_fee(key):
			# (No tug in reach: a contractor's, at twice the fee.)
			_state._add_money(rival, -repair_fee(key) * 2)
			_state._record(null, "energy", repair_fee(key) * 2, rival)
			slots[key].damage = 0
			_changed()
	# Its ships on rig runs to the fields it has.
	for field_id in fields_of(rival):
		var running := ships.filter(func(ship: Ship) -> bool: return ship.rig_field == field_id)
		if running.is_empty():
			for ship in ships:
				if not ship.rig_field.is_empty() or ship.is_service() or carries_from(ship.model(), field_id).is_empty() or not ship.is_docked():
					continue
				var port: String = way_to(ship.docked_at, field_id)[0]
				var hq := rival.hubs[0].port_id if not rival.hubs.is_empty() else ""
				for choice: String in [hq, ship.docked_at, port]:
					if not choice.is_empty() and run_error(rival, ship, field_id, choice).is_empty():
						_state._set_rig_run(ship, field_id, choice)
						break
				if not ship.rig_field.is_empty():
					break
	if rival.level() < 5:
		return news
	# A refinery at its HQ when it has crude coming in.
	if not rival.hubs.is_empty() and spare > int(building("oil_refinery").get("cost", 0)) * 2:
		var hq := rival.hubs[0].port_id
		if build_error(rival, "oil_refinery", hq).is_empty() and not fields_of(rival).is_empty():
			build(rival, "oil_refinery", hq)
			news.append("built an oil refinery at %s" % GameData.port_name(hq))
			return news
	var most := mini(1 + rival.level() / 10, 6)
	if owned_by(rival).size() >= most:
		return news
	for key: String in slots:
		if int(slots[key].get("listing", 0)) > 0 and listing_error(rival, key).is_empty() and int(slots[key].listing) <= mini(spare, sale_price(key) * 3):
			buy_listing(rival, key)
			news.append("bought a %s at %s" % [str(rig_info(str(slots[key].kind)).get("name", "rig")).to_lower(), field_name(field_of(key))])
			return news
	var home := rival.hubs[0].port_id if not rival.hubs.is_empty() else ""
	if home.is_empty():
		return news
	var best_key := ""
	var best_nm := INF
	for field_id in field_ids():
		if not carries.has(products_of(field_id)[0]):
			continue
		var nm := miles_to(home, field_id)
		if nm >= best_nm:
			continue
		for key in keys_at(field_id):
			if buy_error(rival, key).is_empty() and int(rig_info(kind_on(field_id)).get("cost", 0)) <= spare:
				best_key = key
				best_nm = nm
				break
	if best_key.is_empty():
		return news
	buy(rival, best_key)
	news.append("put up a %s at %s" % [str(rig_info(kind_on(field_of(best_key))).get("name", "rig")).to_lower(), field_name(field_of(best_key))])
	return news
