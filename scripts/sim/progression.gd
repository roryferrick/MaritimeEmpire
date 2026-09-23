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


## Cargo ship slots at a company level.
static func fleet_slots(level: int) -> int:
	var slots := 0
	for step: Array in GameData.config.get("fleet_slots", []):
		if level >= int(step[0]):
			slots = int(step[1])
	return slots


## The next benchmark after this level that adds slots: [level, slots], or [] if none.
static func next_slots(level: int) -> Array:
	for step: Array in GameData.config.get("fleet_slots", []):
		if int(step[0]) > level:
			return [int(step[0]), int(step[1])]
	return []


static func unlock_level(model: Dictionary) -> int:
	return int(model.get("unlock_level", 1))


## What reaching this company level unlocks, e.g. ["GE 100", "5 fleet slots"].
static func unlocks_at(level: int) -> Array[String]:
	var unlocked: Array[String] = []
	for model: Dictionary in GameData.ship_models:
		if unlock_level(model) == level and level > 1:
			unlocked.append(String(model.get("name", model.id)))
	if fleet_slots(level) > fleet_slots(level - 1):
		unlocked.append("%d fleet slots" % fleet_slots(level))
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


## XP per minute from the best unlocked cargo models (max_owned of each)
## filling this level's slots, at sea at_sea_share of the time.
static func _full_fleet_xp_per_minute(level: int) -> float:
	var cargo := GameData.ship_models.filter(func(model: Dictionary) -> bool:
		return not model.get("recovery", false) and unlock_level(model) <= level)
	cargo.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _xp_per_minute(a) > _xp_per_minute(b))
	var left := fleet_slots(level)
	var rate := 0.0
	for model: Dictionary in cargo:
		var count := mini(int(model.get("max_owned", 10)), left)
		rate += count * _xp_per_minute(model)
		left -= count
	return rate * float(GameData.config.get("at_sea_share", 0.75))


static func _xp_per_minute(model: Dictionary) -> float:
	return xp_for_delivery(int(model.get("capacity", 0)), float(model.get("speed_nm_per_s", 0)) * 60.0)


static func _round_to_2_figures(value: float) -> int:
	var magnitude := pow(10.0, floorf(log(value) / log(10.0)) - 1.0)
	return int(roundf(value / magnitude) * magnitude)
