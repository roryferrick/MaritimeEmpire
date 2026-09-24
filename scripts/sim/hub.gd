class_name Hub
extends RefCounted
## The company's headquarters (at its home port, from the start) or a hub (one
## more every hubs.every_company_levels company levels, placed at any port for
## good). Levels 0 to hubs.max_level from the XP of deliveries unloaded at its
## port; each level is an upgrade point for its tree, which boosts every ship
## docking there, and costs money (see upgrade_cost()). The HQ's bonuses are
## hubs.hq_multiplier times a hub's.

## Upgrade paths: [key, name, what each point does ("%d" is the total percent)].
const PATHS := [
	["xp", "Ship XP", "+%d%% XP"],
	["costs", "Fuel & repairs", "-%d%% price"],
	["speed", "Port stops", "-%d%% time"],
	["pay", "Sale prices", "+%d%% sale price"],
]

var port_id := ""
var is_hq := false
## Level and XP into it (levels are bought as XP comes in, see GameState).
var level := 0
var xp := 0.0
var upgrades := {"xp": 0, "costs": 0, "speed": 0, "pay": 0}
## Traffic: deliveries unloaded here and the pay they brought in.
var deliveries := 0
var income := 0.0


func _init(port := "", headquarters := false) -> void:
	port_id = port
	is_hq = headquarters


func title() -> String:
	return "%s %s" % [GameData.port_name(port_id), "HQ" if is_hq else "hub"]


func upgrade_points() -> int:
	var spent := 0
	for path: String in upgrades:
		spent += int(upgrades[path])
	return level - spent


func can_upgrade(path: String) -> bool:
	return upgrade_points() > 0 and int(upgrades.get(path, 0)) < Hub.max_path_level()


## Extra company XP for deliveries unloaded here (e.g. 0.3 for +30%): hubs.
## company_xp_base, plus company_xp_per_10_levels for every 10 levels, times
## the HQ multiplier. Free: it comes with the hub's level, not an upgrade.
func company_xp_bonus() -> float:
	var settings := Hub.settings()
	var bonus := float(settings.get("company_xp_base", 0.1)) + float(settings.get("company_xp_per_10_levels", 0.1)) * floori(level / 10.0)
	return bonus * (float(settings.get("hq_multiplier", 1.5)) if is_hq else 1.0)


## Money for the next point in a path: upgrade_cost, plus upgrade_cost_step for
## each point it already has.
func upgrade_cost(path: String) -> int:
	var settings := Hub.settings()
	return int(settings.get("upgrade_cost", 2000000)) + int(settings.get("upgrade_cost_step", 500000)) * int(upgrades.get(path, 0))


## The bonus from a path (e.g. 0.15 for +15%), counting the HQ multiplier.
func bonus(path: String) -> float:
	var settings := Hub.settings()
	var step := float(settings.get("per_point", {}).get(path, 0.0))
	var multiplier := float(settings.get("hq_multiplier", 1.5)) if is_hq else 1.0
	return int(upgrades.get(path, 0)) * step * multiplier


func to_dict() -> Dictionary:
	return {"port_id": port_id, "is_hq": is_hq, "level": level, "xp": xp, "upgrades": upgrades,
		"deliveries": deliveries, "income": income}


static func from_dict(data: Dictionary) -> Hub:
	var hub := Hub.new(data.get("port_id", ""), bool(data.get("is_hq", false)))
	hub.level = int(data.get("level", 0))
	hub.xp = float(data.get("xp", 0.0))
	hub.deliveries = int(data.get("deliveries", 0))
	hub.income = float(data.get("income", 0.0))
	var saved: Dictionary = data.get("upgrades", {})
	for path: String in hub.upgrades:
		hub.upgrades[path] = int(saved.get(path, 0))
	return hub


static func settings() -> Dictionary:
	return GameData.config.get("hubs", {})


static func max_level() -> int:
	return int(settings().get("max_level", 40))


static func max_path_level() -> int:
	return int(settings().get("max_path_level", 10))


## "Company XP +30% on deliveries here (+40% at level 30)"
func company_xp_text() -> String:
	var text := "Company XP +%d%% on deliveries here" % roundi(company_xp_bonus() * 100.0)
	var next_level := (floori(level / 10.0) + 1) * 10
	if next_level <= Hub.max_level():
		var step := float(Hub.settings().get("company_xp_per_10_levels", 0.1)) * (float(Hub.settings().get("hq_multiplier", 1.5)) if is_hq else 1.0)
		text += " (+%d%% at level %d)" % [roundi((company_xp_bonus() + step) * 100.0), next_level]
	return text
