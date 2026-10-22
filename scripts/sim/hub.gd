# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Hub
extends RefCounted
## The company's headquarters (at its home port, from the start) or a hub
## (bought at any port, for good: GameState.hub_price()). Each pays a monthly
## upkeep by its port's size (GameState._pay_hub_upkeep()) and has plots for
## its warehouses. Facilities to buy come later (DESIGN_LIVING_WORLD.md).

var port_id := ""
var is_hq := false
## Traffic: deliveries unloaded here and the pay they brought in.
var deliveries := 0
var income := 0.0
## Its warehouses: one on each plot beside the marina (a commodity id, or ""
## for an empty plot), INDUSTRY_SLOTS of them, all open.
var industries := ["", "", ""]
## The facilities built here (facility ids: see Hub.facility()).
var facilities: Array[String] = []

const INDUSTRY_SLOTS := 3


func _init(port := "", headquarters := false) -> void:
	port_id = port
	is_hq = headquarters


func title() -> String:
	return "%s %s" % [GameData.port_name(port_id), "HQ" if is_hq else "hub"]


## The industry settings (game_config hubs.industry).
static func industry_settings() -> Dictionary:
	return settings().get("industry", {})


## True if it has a building for a commodity.
func has_industry(commodity_id: String) -> bool:
	return not commodity_id.is_empty() and industries.has(commodity_id)


## What its building for a commodity gives (0 without one): "buy" (its buy
## price here that much cheaper, e.g. 0.2) or "sell" (its sell price here that
## much more expensive), the HQ's hq_multiplier times a hub's.
func industry_bonus(commodity_id: String, kind: String) -> float:
	if not has_industry(commodity_id):
		return 0.0
	var key: String = {buy = "buy_discount", sell = "sell_bonus"}.get(kind, "")
	var value := float(Hub.industry_settings().get(key, 0.0))
	return value * (float(Hub.settings().get("hq_multiplier", 1.5)) if is_hq else 1.0)


## Its monthly upkeep: game_config hubs.upkeep_month for its port's size band
## (none for the HQ), plus its facilities'.
func upkeep() -> int:
	var total := 0
	for id in facilities:
		total += int(Hub.facility(id).get("upkeep_month", 0))
	if is_hq:
		return total
	return total + int(Hub.settings().get("upkeep_month", {}).get(GameState.port_sizes.band(port_id), 0))


## The facilities there are (game_config hubs.facilities), and one by id.
static func facility_list() -> Array:
	return settings().get("facilities", [])


static func facility(id: String) -> Dictionary:
	for each: Dictionary in facility_list():
		if each.id == id:
			return each
	return {}


func has_facility(id: String) -> bool:
	return facilities.has(id)


## What a facility here gives: its value (x hq_multiplier at the HQ), 0 without it.
func facility_effect(id: String) -> float:
	if not has_facility(id):
		return 0.0
	return float(facility(id).get("value", 0.0)) * (float(settings().get("hq_multiplier", 1.5)) if is_hq else 1.0)


## The summed effect of its facilities of a kind ("dock" for a ship category, "fuel", "repairs", "price" for a family...).
func effect_of(kind: String, about := "") -> float:
	var total := 0.0
	for id in facilities:
		var info := facility(id)
		if str(info.get("effect", "")) != kind:
			continue
		if kind == "dock" and not about in info.get("categories", []):
			continue
		if kind == "price" and str(info.get("family", "")) != about:
			continue
		total += facility_effect(id)
	return total


func to_dict() -> Dictionary:
	return {"port_id": port_id, "is_hq": is_hq, "deliveries": deliveries, "income": income, "industries": industries, "facilities": facilities}


static func from_dict(data: Dictionary) -> Hub:
	var hub := Hub.new(data.get("port_id", ""), bool(data.get("is_hq", false)))
	hub.deliveries = int(data.get("deliveries", 0))
	hub.income = float(data.get("income", 0.0))
	var built: Array = data.get("industries", [])
	for slot in INDUSTRY_SLOTS:
		hub.industries[slot] = str(built[slot]) if slot < built.size() else ""
	hub.facilities.assign(data.get("facilities", []))
	return hub


static func settings() -> Dictionary:
	return GameData.config.get("hubs", {})


## How many warehouses its marina shows (MapView): 2, one more for every
## WAREHOUSE_DELIVERIES deliveries unloaded here, up to 4.
static func warehouse_count(hub: Hub) -> int:
	return clampi(2 + hub.deliveries / WAREHOUSE_DELIVERIES, 2, 4)
const WAREHOUSE_DELIVERIES := 300
