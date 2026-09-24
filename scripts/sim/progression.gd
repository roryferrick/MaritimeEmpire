class_name Progression
## Company and ship levels, from the XP settings in game_config.json and
## ship_models.json.
##
## Company level L costs about as many minutes as the level number suggests
## (company_level_minutes) of what a full fleet at that level would earn, so
## levels don't rush by when bigger ships unlock. Ship levels cost 5% more
## each, starting from each model's xp_first_level.

## XP to go from each company level to the next, index 0 = level 1 -> 2.
static var _company_costs: Array[int] = []


static func xp_for_delivery(capacity: int, distance_nm: float) -> float:
	return capacity * distance_nm * float(GameData.config.get("xp_per_container_nm", 0.01))


## XP for a delivery that paid this much: the containers x nm that pay would
## buy at the container rate, x xp_per_container_nm.
static func xp_for_payment(payment: float) -> float:
	return xp_for_delivery(1, payment / float(GameData.config.get("pay_per_container_nm", 1.0)))


static func max_company_level() -> int:
	return int(GameData.config.get("max_company_level", 100))


## XP needed to go from this company level to the next (0 at the max level).
static func company_level_cost(level: int) -> int:
	if _company_costs.is_empty():
		_build_company_costs()
	return _company_costs[level - 1] if level < max_company_level() else 0


## Level reached with this much total XP: {level, xp (into the level), cost (of the level)}.
static func company_level(total_xp: float) -> Dictionary:
	var level := 1
	var left := total_xp
	while level < max_company_level() and left >= company_level_cost(level):
		left -= company_level_cost(level)
		level += 1
	return {level = level, xp = left, cost = company_level_cost(level)}


## How many of a model the company can own at a level: none before it
## unlocks, then ship_slots' start, one more every few levels, up to max_owned.
static func model_slots(model: Dictionary, level: int) -> int:
	var unlock := unlock_level(model)
	if level < unlock:
		return 0
	var growth := _slot_growth(model)
	return mini(int(growth[0]) + floori(float(level - unlock) / int(growth[1])), int(model.get("max_owned", 10)))


## The company level that gives this model its next slot, or -1 if it's at its max.
static func next_slot_level(model: Dictionary, level: int) -> int:
	if level < unlock_level(model):
		return unlock_level(model)
	if model_slots(model, level) >= int(model.get("max_owned", 10)):
		return -1
	var growth := _slot_growth(model)
	var every := int(growth[1])
	return level + every - (level - unlock_level(model)) % every


## [start, every] from game_config ship_slots, for cargo ships or recovery boats;
## a model's own slot_every replaces "every".
static func _slot_growth(model: Dictionary) -> Array:
	var slots: Dictionary = GameData.config.get("ship_slots", {})
	var growth: Array = slots.get("recovery" if model.get("recovery", false) else "cargo", [3, 3])
	return [growth[0], int(model.get("slot_every", growth[1]))]


static func unlock_level(model: Dictionary) -> int:
	return int(model.get("unlock_level", 1))


## What reaching this company level unlocks, e.g. ["GE 100", "+1 slot: Scooter 10"].
static func unlocks_at(level: int) -> Array[String]:
	var unlocked: Array[String] = []
	var more_slots := PackedStringArray()
	for model: Dictionary in GameData.ship_models:
		if level > 1 and unlock_level(model) == level:
			unlocked.append(String(model.get("name", model.id)))
		elif model_slots(model, level) > model_slots(model, level - 1):
			more_slots.append(String(model.get("name", model.id)))
	if not more_slots.is_empty():
		unlocked.append("+1 slot: %s" % ", ".join(more_slots))
	if hub_slots(level) > hub_slots(level - 1):
		unlocked.append("a new hub")
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


## Company level L costs (a + b x (L - 1)) minutes of a full fleet's XP at L,
## rounded to 2 significant figures.
static func _build_company_costs() -> void:
	var minutes: Array = GameData.config.get("company_level_minutes", [3, 0.45])
	for level in range(1, max_company_level()):
		var cost := (float(minutes[0]) + float(minutes[1]) * (level - 1)) * _full_fleet_xp_per_minute(level)
		_company_costs.append(_round_to_2_figures(maxf(cost, 100.0)))
	_company_costs.append(0)


## XP per minute from every unlocked cargo model with all its slots filled
## at this level, at sea at_sea_share of the time.
static func _full_fleet_xp_per_minute(level: int) -> float:
	var rate := 0.0
	for model: Dictionary in GameData.ship_models:
		if not model.get("recovery", false):
			rate += model_slots(model, level) * _xp_per_minute(model)
	return rate * float(GameData.config.get("at_sea_share", 0.75))


## Delivery XP follows pay, so a tanker earns the XP of the containers its pay would buy.
static func _xp_per_minute(model: Dictionary) -> float:
	var pay_per_minute := int(model.get("capacity", 0)) * float(model.get("speed_nm_per_s", 0)) * 60.0 * GameData.pay_rate(model)
	return xp_for_payment(pay_per_minute)


static func _round_to_2_figures(value: float) -> int:
	var magnitude := pow(10.0, floorf(log(value) / log(10.0)) - 1.0)
	return int(roundf(value / magnitude) * magnitude)


## How many HQ + hub locations the company can have at a level: the HQ, plus
## one hub every hubs.every_company_levels levels, up to hubs.max_hubs.
static func hub_slots(level: int) -> int:
	var settings: Dictionary = GameData.config.get("hubs", {})
	return 1 + mini(floori(float(level) / int(settings.get("every_company_levels", 15))), int(settings.get("max_hubs", 6)))


## XP a hub needs to go from `level` to the next, at the company's current
## level: (level_minutes[0] + level_minutes[1] x level) minutes of traffic_share
## of a full fleet's XP.
static func hub_level_cost(level: int, company_level: int) -> float:
	var settings: Dictionary = GameData.config.get("hubs", {})
	var minutes: Array = settings.get("level_minutes", [10, 1.4])
	var per_minute := _full_fleet_xp_per_minute(company_level) * float(settings.get("traffic_share", 0.25))
	return maxf((float(minutes[0]) + float(minutes[1]) * level) * per_minute, 50.0)
