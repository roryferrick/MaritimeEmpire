# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Progression
## Company and ship levels, from the XP settings in game_config.json and
## ship_models.json.
##
## Company level L costs about as many minutes as the level number suggests
## (company_level_minutes) of what a full fleet at that level would earn, so
## levels don't rush by when bigger ships unlock. Ship levels cost 5% more
## each, starting from each model's xp_first_level.

## XP to go from each company level to the next, index 0 = level 1 -> 2, per
## kind of company (_cost_key()): companies with the same types share a table.
static var _company_costs := {}


static func xp_for_delivery(capacity: int, distance_nm: float) -> float:
	return capacity * distance_nm * float(GameData.config.get("xp_per_container_nm", 0.01))


## XP for delivering cargo: units x distance x xp_per_container_nm, weighted by
## the commodity's base price against data/markets.json xp_ref_price (so a ton
## of oil counts for less than a container of toys). Steady whatever the
## market pays, so a trade at a loss still earns XP.
static func xp_for_cargo(quantity: int, commodity_id: String, distance_nm: float) -> float:
	return xp_for_delivery(quantity, distance_nm) * _value_weight(commodity_id)


static func _value_weight(commodity_id: String) -> float:
	return float(GameData.commodity(commodity_id).get("base", 0.0)) / float(GameData.markets.get("xp_ref_price", 4000))


static func max_company_level() -> int:
	return int(GameData.config.get("max_company_level", 140))


## XP needed to go from this company level to the next (0 at the max level),
## for a company (this player's if null): its own table, from the lines its
## company types give it (see _build_company_costs()).
static func company_level_cost(level: int, company: Company = null) -> int:
	if level >= max_company_level():
		return 0
	var key := _cost_key(_company_or_mine(company))
	if not _company_costs.has(key):
		_company_costs[key] = _build_company_costs(_company_or_mine(company))
	return int(_company_costs[key][level - 1])


## Level reached with this much total XP: {level, xp (into the level), cost (of the level)}.
static func company_level(total_xp: float, company: Company = null) -> Dictionary:
	var level := 1
	var left := total_xp
	while level < max_company_level() and left >= company_level_cost(level, company):
		left -= company_level_cost(level, company)
		level += 1
	return {level = level, xp = left, cost = company_level_cost(level, company)}


# --- Company types -------------------------------------------------------------

## (Not the coming_soon ones: see upcoming_types().)
## The company types (game_config company_types types): {id, name, tab, categories, color, blurb}.
static func company_types() -> Array:
	return GameData.config.get("company_types", {}).get("types", []).filter(func(each: Dictionary) -> bool: return not each.get("coming_soon", false))


## The types a company can be founded as: not the pick_only ones (Research: taken only at a pick).
static func start_types() -> Array:
	return company_types().filter(func(each: Dictionary) -> bool: return not each.get("pick_only", false))


## The company types not playable yet (game_config company_types coming_soon: Cruises).
static func upcoming_types() -> Array:
	return GameData.config.get("company_types", {}).get("types", []).filter(func(each: Dictionary) -> bool: return each.get("coming_soon", false))


static func company_type(type_id: String) -> Dictionary:
	for each: Dictionary in GameData.config.get("company_types", {}).get("types", []):  # (Coming-soon ones too.)
		if each.id == type_id:
			return each
	return {}


## A type's name ("All" for a company from before types, "" for an unknown type).
static func type_name(type_id: String) -> String:
	return "All" if type_id.is_empty() else str(company_type(type_id).get("name", ""))


## The company type a ship category belongs to ("" for recovery boats, tugs and icebreakers).
static func type_of_category(category: String) -> String:
	if _category_types.is_empty():
		for each: Dictionary in company_types():
			for each_category: String in each.categories:
				_category_types[each_category] = each.id
		_category_types[""] = ""
	return str(_category_types.get(category, ""))
static var _category_types := {}


static func type_of_model(model: Dictionary) -> String:
	return type_of_category(str(model.get("category", "")))


## The company type whose ships carry a commodity ("" if none): by the models
## that carry it (a seafood family by the seafood carriers, so a catch counts as Seafood).
static func type_of_commodity(commodity_id: String) -> String:
	if _commodity_types.is_empty():
		for model: Dictionary in GameData.ship_models:
			for each: String in model.get("cargo", []):
				if not _commodity_types.has(each):
					_commodity_types[each] = type_of_model(model)
		_commodity_types[""] = ""
	return str(_commodity_types.get(commodity_id, ""))
static var _commodity_types := {}


## Levels between taking a type and its tiers unlocking (tier 1 first).
static func tier_offset(model: Dictionary) -> int:
	var offsets: Array = GameData.config.get("company_types", {}).get("tier_levels", [0, 3, 8, 15, 24])
	return int(offsets[clampi(int(model.get("tier", 1)), 1, offsets.size()) - 1])


## How often (in company levels) a company picks another type.
static func type_pick_every() -> int:
	return int(GameData.config.get("company_types", {}).get("pick_every", 15))


## How many types a company may have at a level: its first, plus one every
## type_pick_every() levels, up to all of them.
static func type_slots(level: int) -> int:
	return mini(1 + floori(float(level) / type_pick_every()), company_types().size())


## The company level of the next type pick after this level (-1 once all are taken).
static func next_type_level(level: int) -> int:
	if type_slots(level) >= company_types().size():
		return -1
	return (floori(float(level) / type_pick_every()) + 1) * type_pick_every()


## The level a model unlocks at for a company (this player's if null): its
## company type's level plus its tier's offset, or LOCKED if the company
## doesn't have that type. Models outside the types, and every model for a
## company from before types, unlock at their ship_models.json unlock_level.
static func unlock_level(model: Dictionary, company: Company = null) -> int:
	var type_id := type_of_model(model)
	company = _company_or_mine(company)
	if type_id.is_empty() or company == null or company.all_types():
		return int(model.get("unlock_level", 1))
	if not company.company_types.has(type_id):
		return LOCKED
	return company.type_level(type_id) + tier_offset(model)
const LOCKED := 1000000


static func _company_or_mine(company: Company) -> Company:
	return company if company != null else GameState.company


## How many of a model the company can own at a level: none before it
## unlocks, then ship_slots' start, one more every few levels, up to max_owned.
static func model_slots(model: Dictionary, level: int, company: Company = null) -> int:
	if model.get("tug", false):
		return 0  # Tugs come with the ports on the routes instead (GameState.tug_slots()).
	return _slots_from(model, unlock_level(model, company), level)


static func _slots_from(model: Dictionary, unlock: int, level: int) -> int:
	if level < unlock:
		return 0
	var growth := _slot_growth(model)
	return mini(int(growth[0]) + floori(float(level - unlock) / int(growth[1])), int(model.get("max_owned", 10)))


## The company level that gives this model its next slot (LOCKED while the
## company lacks its type), or -1 if it's at its max.
static func next_slot_level(model: Dictionary, level: int, company: Company = null) -> int:
	var unlock := unlock_level(model, company)
	if level < unlock:
		return unlock
	if model.get("tug", false) or model_slots(model, level, company) >= int(model.get("max_owned", 10)):
		return -1
	var growth := _slot_growth(model)
	var every := int(growth[1])
	return level + every - (level - unlock) % every


## [start, every] from game_config ship_slots, for cargo ships or service ships
## (recovery boats and icebreakers); a model's own slot_every replaces "every".
static func _slot_growth(model: Dictionary) -> Array:
	var slots: Dictionary = GameData.config.get("ship_slots", {})
	var service: bool = model.get("recovery", false) or not str(model.get("icebreaker", "")).is_empty()
	var growth: Array = slots.get("recovery" if service else "cargo", [3, 3])
	return [growth[0], int(model.get("slot_every", growth[1]))]


## What reaching this company level unlocks for a company (this player's if
## null), e.g. ["Feeder 100", "+1 slot: Scooter 20", "a new company type to choose"].
static func unlocks_at(level: int, company: Company = null) -> Array[String]:
	company = _company_or_mine(company)
	var unlocked: Array[String] = []
	var more_slots := PackedStringArray()
	for model: Dictionary in GameData.ship_models:
		if level > 1 and unlock_level(model, company) == level:
			unlocked.append(String(model.get("name", model.id)))
		elif model_slots(model, level, company) > model_slots(model, level - 1, company):
			more_slots.append(String(model.get("name", model.id)))
	if not more_slots.is_empty():
		unlocked.append("+1 slot: %s" % ", ".join(more_slots))
	if level > 1 and Energy.can_drill(company):  # (Rigs, refineries and pipelines by the Tankers tiers: see Energy.)
		for what: String in Energy.building_ids() + ["rig", "platform", "pipeline"]:
			if Energy.unlock_level(what, company) == level:
				var title := str(Energy.building(what).get("name", Energy.rig_info(what).get("name", "Pipelines")))
				unlocked.append("%s (the Energy page)" % title)
	if company != null and not company.all_types() and type_slots(level) > type_slots(level - 1):
		unlocked.append("a new company type to choose")
	if hub_slots(level) > hub_slots(level - 1):
		unlocked.append("a new hub")
	if region_slots(level) > region_slots(level - 1) and region_slots(level) <= GameData.markets.get("regions", []).size():
		unlocked.append("a new region to unlock")
	return unlocked


static func ship_max_level() -> int:
	return int(GameData.config.get("ship_max_level", 30))


## XP a ship of this model needs to go from `level` to the next.
static func ship_level_cost(model: Dictionary, level: int) -> float:
	var growth := float(GameData.config.get("ship_level_growth", 1.05))
	return float(model.get("xp_first_level", 0)) * pow(growth, level)


## A ship's level from its total XP: {level, xp (into the level), cost (of the level)}.
static func ship_level(model: Dictionary, total_xp: float) -> Dictionary:
	var level := 0
	var left := total_xp
	if float(model.get("xp_first_level", 0)) <= 0.0:
		return {level = 0, xp = 0.0, cost = 0.0}
	while level < ship_max_level() and left >= ship_level_cost(model, level):
		left -= ship_level_cost(model, level)
		level += 1
	var cost := ship_level_cost(model, level) if level < ship_max_level() else 0.0
	return {level = level, xp = left, cost = cost}


static func skill_max_level() -> int:
	return int(GameData.config.get("skill_max_level", 10))


## Bonus per skill level for "speed", "durability" or "efficiency".
static func skill_step(skill: String) -> float:
	return float(GameData.config.get("skills", {}).get(skill, 0.0))


## Which table of level costs a company uses: "all" for a company from before
## types (or none), else its types and the levels it took them at.
static func _cost_key(company: Company) -> String:
	if company == null or company.all_types():
		return "all"
	var parts := PackedStringArray()
	for type_id: String in company.company_types:
		parts.append("%s@%d" % [type_id, company.type_level(type_id)])
	return ",".join(parts)


## Company level L costs (a + b x (L - 1)) minutes of a full fleet's XP at L,
## rounded to 2 significant figures: the fleet the company's types give it.
static func _build_company_costs(company: Company) -> Array[int]:
	var costs: Array[int] = []
	var minutes: Array = GameData.config.get("company_level_minutes", [3, 0.45])
	for level in range(1, max_company_level()):
		var cost := (float(minutes[0]) + float(minutes[1]) * (level - 1)) * _full_fleet_xp_per_minute(level, company)
		costs.append(_round_to_2_figures(maxf(cost, 100.0)))
	costs.append(0)
	return costs


## XP per minute from every unlocked cargo model with all its slots filled
## at this level, at sea at_sea_share of the time. A company from before types
## counts every model but the new_tier ones (so its levels stay as they were),
## and no company counts the farm_line, boat_line or gas_line ones (the Fresh
## produce carriers, the boat carriers and the gas carriers).
## One with types counts its types' models; for each type pick it has reached
## but not made yet, the average of the types it could still take (taken at
## that pick's level).
static func _full_fleet_xp_per_minute(level: int, company: Company = null) -> float:
	company = _company_or_mine(company)
	var rate := 0.0
	if company == null or company.all_types():
		for model: Dictionary in GameData.ship_models:
			if not model.get("recovery", false) and not model.get("new_tier", false) and not model.get("farm_line", false) and not model.get("boat_line", false) and not model.get("extra_line", false) and not model.get("gas_line", false) and not model.get("research_line", false):
				rate += _slots_from(model, int(model.get("unlock_level", 1)), level) * _xp_per_minute(model)
		return rate * float(GameData.config.get("at_sea_share", 0.75))
	for type_id: String in company.company_types:
		rate += _type_rate(type_id, company.type_level(type_id), level)
	var untaken := start_types().filter(func(each: Dictionary) -> bool: return not company.company_types.has(each.id))  # (Not Research: its ships earn no cargo XP, so it would make every level cheaper.)
	for pick in range(company.company_types.size(), type_slots(level)):
		var at := pick * type_pick_every()
		var sum := 0.0
		for each: Dictionary in untaken:
			sum += _type_rate(each.id, at, level)
		rate += sum / maxf(untaken.size(), 1.0)
	return rate * float(GameData.config.get("at_sea_share", 0.75))


## XP per minute of a company type's full fleet at a level, the type taken at taken_at.
static func _type_rate(type_id: String, taken_at: int, level: int) -> float:
	var categories: Array = company_type(type_id).get("categories", [])
	var rate := 0.0
	for model: Dictionary in GameData.ship_models:
		if categories.has(model.get("category", "")) and not model.get("farm_line", false) and not model.get("boat_line", false) and not model.get("extra_line", false) and not model.get("gas_line", false):  # (Not the Fresh produce carriers, the boat carriers or the gas carriers: added with the farms, the makers and the rigs, so companies keep their levels.)
			rate += _slots_from(model, taken_at + tier_offset(model), level) * _xp_per_minute(model)
	return rate


## A model's XP per minute at sea with a full hold of its average cargo. A
## fishing or crabbing boat's is a typical trip's: its catch (a full hold, or
## its rate for the working share of its days), landed from grounds a quarter
## of its range away, over the trip.
static func _xp_per_minute(model: Dictionary) -> float:
	if model.has("fishing"):
		return _fishing_xp_per_minute(model)
	if model.has("research"):  # A research ship's expeditions: its tier's cargo rate (Research.xp_rate()) for the 60% of the time it's out.
		return Research.xp_rate(model) * 60.0 * 0.6
	if model.has("cruise"):  # Its guests (a cruise about 85% full) over the miles it sails, at sea about 60% of the time (the rest in port booking).
		var guests := roundi(float(model.cruise.get("guests", 0)) * 0.85)
		return xp_for_delivery(guests, float(model.get("speed_nm_per_s", 0)) * 60.0) * float(GameData.config.get("cruises", {}).get("xp_factor", 0.4)) * 0.6
	var cargo: Array = model.get("cargo", [])
	if cargo.is_empty():
		return 0.0
	var weight := 0.0
	for commodity_id: String in cargo:
		weight += _value_weight(commodity_id) / GameData.hold_of(commodity_id)  # (A unit of hold's worth: capacity is in units of hold.)
	weight /= cargo.size()
	return xp_for_delivery(int(model.get("capacity", 0)), float(model.get("speed_nm_per_s", 0)) * 60.0) * weight


static func _fishing_xp_per_minute(model: Dictionary) -> float:
	var fishing: Dictionary = model.fishing
	var days: Array = fishing.get("trip_days", [3, 7])
	var mean_days := (float(days[0]) + float(days[1])) / 2.0
	var day_minutes := 86400.0 / (float(GameData.config.get("calendar", {}).get("minutes_per_second", 20)) * 60.0) / 60.0
	var crates := minf(float(model.get("capacity", 0)), float(fishing.get("rate", 0)) * mean_days * 0.6)
	var crabs: bool = (fishing.get("gear", []) as Array).has("trap")
	var weight := 0.0
	var count := 0
	for commodity_id: String in _seafood_commodities():
		if (commodity_id.contains("crab") or commodity_id == "crayfish") == crabs:
			weight += _value_weight(commodity_id)
			count += 1
	weight /= maxf(count, 1.0)
	var miles := 2.0 * float(model.get("range_nm", 0)) * 0.25
	return xp_for_delivery(roundi(crates), miles) * weight / maxf(mean_days * day_minutes, 0.1)


## What the seafood carriers carry (the catch's commodities).
static func _seafood_commodities() -> Array:
	for model: Dictionary in GameData.ship_models:
		if model.get("category", "") == "seafood":
			return model.get("cargo", [])
	return []


static func _round_to_2_figures(value: float) -> int:
	var magnitude := pow(10.0, floorf(log(value) / log(10.0)) - 1.0)
	return int(roundf(value / magnitude) * magnitude)


## How many HQ + hub locations the company can have at a level: the HQ, plus
## one hub every hubs.every_company_levels levels, up to hubs.max_hubs.
static func hub_slots(level: int) -> int:
	var settings: Dictionary = GameData.config.get("hubs", {})
	return 1 + mini(floori(float(level) / int(settings.get("every_company_levels", 15))), int(settings.get("max_hubs", 6)))


## How many market regions the company can have unlocked at a level: its home
## port's, plus one every regions.every_company_levels levels.
static func region_slots(level: int) -> int:
	return 1 + floori(float(level) / int(GameData.config.get("regions", {}).get("every_company_levels", 5)))


## XP a hub needs to go from `level` to the next, at the company's current
## level: (level_minutes[0] + level_minutes[1] x level) minutes of traffic_share
## of a full fleet's XP.
static func hub_level_cost(level: int, company_level: int, company: Company = null) -> float:
	var settings: Dictionary = GameData.config.get("hubs", {})
	var minutes: Array = settings.get("level_minutes", [10, 1.4])
	var per_minute := _full_fleet_xp_per_minute(company_level, company) * float(settings.get("traffic_share", 0.25))
	return maxf((float(minutes[0]) + float(minutes[1]) * level) * per_minute, 50.0)
