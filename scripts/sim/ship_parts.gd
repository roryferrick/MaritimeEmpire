# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name ShipParts
extends RefCounted
## A ship's parts (data/ship_parts.json; DESIGN_LIVING_WORLD.md M4): each model
## has a parts list by its tier and category (5 on a Scooter to about 50 on
## the giants), each with a condition on the ship (Ship.parts, 0 to 1). The
## ship's maintenance is the weighted mean of them: wear spreads over the parts
## by rate x weight (flush()), repairs at ordinary port stops put right the
## minor parts, and the major ones (engine, propeller, shaft, plating) only in
## drydock at a shipyard port (SHIPYARD_PORTS) or a hub with the Drydock
## facility. The parts move the ship: a fouled hull burns more fuel, worn
## propulsion costs speed, a tired engine and electrics break down more, worn
## deck gear slows port stops (factor()). One upgrade per part, bought in
## drydock (upgrade_cost()). GameState runs the drydock (order_drydock()).

const PATH := "res://data/ship_parts.json"
const MAJOR_RATE := 0.5
const MAJOR_WEIGHT := 0.5

static var _data := {}
static var _by_model := {}  # model id -> Array of part dictionaries
static var _by_id := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		_data = JSON.parse_string(file.get_as_text()) if file != null else {parts = []}
		for part: Dictionary in _data.get("parts", []):
			if bool(part.get("major", false)):  # (The big parts wear slowly and weigh less in the maintenance figure: a year at sea leaves them a quarter worn, not half; the parts' own factors carry their effect.)
				part.rate = float(part.rate) * MAJOR_RATE
				part.weight = float(part.weight) * MAJOR_WEIGHT
			_by_id[part.id] = part
	return _data


static func part(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func group_name(group: String) -> String:
	return str((data().get("groups", {}) as Dictionary).get(group, group.capitalize()))


## The parts of a model: every catalogue part at or under its tier and for its category.
static func for_model(model: Dictionary) -> Array:
	var id := str(model.get("id", ""))
	if _by_model.has(id):
		return _by_model[id]
	var tier := int(model.get("tier", 1))
	var category := str(model.get("category", ""))
	var out := []
	for each: Dictionary in data().get("parts", []):
		if int(each.from_tier) > tier:
			continue
		var categories: Array = each.get("categories", [])
		if not categories.is_empty() and not category in categories:
			continue
		out.append(each)
	_by_model[id] = out
	return out


## Fresh conditions for a model, all at `condition`.
static func new_conditions(model: Dictionary, condition := 1.0) -> Dictionary:
	var out := {}
	for each: Dictionary in for_model(model):
		out[each.id] = condition
	return out


## Makes sure a ship has its parts (an old save, or a new ship): at its maintenance.
static func ensure(ship: Ship) -> void:
	if ship.parts.is_empty() and not ship.is_ghost():
		ship.parts = new_conditions(ship.model(), clampf(ship.maintenance - ship.part_debt, 0.0, 1.0))  # (At the maintenance before any change still to spread.)


## Spreads the ship's pending maintenance change over its parts: wear by rate x
## weight; repair into the minor parts (and the major ones when it's in
## drydock). Afterwards the ship's maintenance is the parts' weighted mean.
static func flush(ship: Ship) -> void:
	var debt := ship.part_debt
	if absf(debt) < 0.000001:
		return
	ensure(ship)
	ship.part_debt = 0.0
	var list := for_model(ship.model())
	if list.is_empty() or ship.parts.is_empty():
		return
	var total_weight := 0.0
	for each: Dictionary in list:
		total_weight += float(each.weight)
	if debt < 0.0:
		var pull := 0.0
		for each: Dictionary in list:
			pull += float(each.weight) * float(each.rate) * (1.0 if float(ship.parts.get(each.id, 1.0)) > 0.0 else 0.0)
		if pull > 0.0:
			for each: Dictionary in list:
				var c := float(ship.parts.get(each.id, 1.0))
				if c <= 0.0:
					continue
				ship.parts[each.id] = maxf(c + debt * total_weight * float(each.rate) / pull, 0.0)
	else:
		var drydock := not ship.drydock.is_empty()
		var room := 0.0
		for each: Dictionary in list:
			if drydock or not bool(each.get("major", false)):
				room += float(each.weight) * (1.0 - float(ship.parts.get(each.id, 1.0)))
		if room > 0.0:
			var share := minf(debt * total_weight / room, 1.0)  # (The fraction of each repairable part's deficit put right.)
			for each: Dictionary in list:
				if drydock or not bool(each.get("major", false)):
					var c := float(ship.parts.get(each.id, 1.0))
					ship.parts[each.id] = minf(c + (1.0 - c) * share, 1.0)
	ship.sync_maintenance(mean(ship))
	ship.invalidate_stats()


## A breakdown's hit (GameState): it falls on the minor parts (a pump, a turbo, the wiring: what a
## port stop puts right) and only a tenth on the major ones, so one breakdown doesn't wreck the
## engine and start a spiral of breakdowns no port can mend.
static func hit(ship: Ship, amount: float) -> void:
	flush(ship)
	var list := for_model(ship.model())
	if list.is_empty() or ship.parts.is_empty():
		ship.maintenance = maxf(ship.maintenance - amount, 0.0)
		flush(ship)
		return
	var total_weight := 0.0
	var minor_weight := 0.0
	var major_weight := 0.0
	for each: Dictionary in list:
		total_weight += float(each.weight)
		if bool(each.get("major", false)):
			major_weight += float(each.weight)
		else:
			minor_weight += float(each.weight)
	var to_minor := amount * total_weight * (0.9 if major_weight > 0.0 else 1.0)
	var to_major := amount * total_weight - to_minor
	for each: Dictionary in list:
		var c := float(ship.parts.get(each.id, 1.0))
		var share := (to_major / maxf(major_weight, 0.0001)) if bool(each.get("major", false)) else (to_minor / maxf(minor_weight, 0.0001))
		ship.parts[each.id] = clampf(c - share, 0.0, 1.0)
	ship.sync_maintenance(mean(ship))
	ship.invalidate_stats()

## The weighted mean condition of a ship's parts.
static func mean(ship: Ship) -> float:
	var list := for_model(ship.model())
	var total := 0.0
	var sum := 0.0
	for each: Dictionary in list:
		total += float(each.weight)
		sum += float(each.weight) * float(ship.parts.get(each.id, 1.0))
	return sum / total if total > 0.0 else ship.maintenance


## How much maintenance an ordinary port stop can put back (the minor parts' deficits), or everything in drydock.
static func repairable(ship: Ship) -> float:
	flush(ship)
	var list := for_model(ship.model())
	if list.is_empty():
		return 1.0 - ship.maintenance
	var drydock := not ship.drydock.is_empty()
	var total := 0.0
	var room := 0.0
	for each: Dictionary in list:
		total += float(each.weight)
		if drydock or not bool(each.get("major", false)):
			room += float(each.weight) * (1.0 - float(ship.parts.get(each.id, 1.0)))
	return room / total if total > 0.0 else 0.0


## The major parts' deficit as a share of maintenance: what only drydock puts right.
static func major_deficit(ship: Ship) -> float:
	flush(ship)
	var list := for_model(ship.model())
	var total := 0.0
	var room := 0.0
	for each: Dictionary in list:
		total += float(each.weight)
		if bool(each.get("major", false)):
			room += float(each.weight) * (1.0 - float(ship.parts.get(each.id, 1.0)))
	return room / total if total > 0.0 else 0.0


## The mean deficit of a group's parts (0 sound, 1 wrecked).
static func group_deficit(ship: Ship, group: String) -> float:
	var total := 0.0
	var sum := 0.0
	for each: Dictionary in for_model(ship.model()):
		if str(each.group) != group:
			continue
		total += float(each.weight)
		sum += float(each.weight) * (1.0 - float(ship.parts.get(each.id, 1.0)))
	return sum / total if total > 0.0 else 0.0


## The parts' factor on a stat ("fuel", "speed", "breakdowns", "dock"): the
## group's deficit times the effect's size (data effects), and the upgrades' effects.
static func factor(ship: Ship, key: String) -> float:
	flush(ship)
	var size := float((data().get("effects", {}) as Dictionary).get(key, 0.0))
	var out := 1.0
	if ship.parts.is_empty():  # (Never worn: nothing to deduct, but its upgrades count.)
		size = 0.0
	match key:
		"fuel":
			out = 1.0 + size * group_deficit(ship, "hull")
		"speed":
			out = 1.0 - size * group_deficit(ship, "propulsion")
		"breakdowns":
			out = 1.0 + size * maxf(group_deficit(ship, "engine"), group_deficit(ship, "electrics"))
		"dock":
			out = 1.0 + size * group_deficit(ship, "deck")
	for part_id: String in ship.upgrades:
		var upgrade := upgrade_info(str(ship.upgrades[part_id]))
		if str(upgrade.get("part", "")) == part_id:
			out *= float((upgrade.get("effects", {}) as Dictionary).get(key, 1.0))
	return out


# --- Drydock ------------------------------------------------------------------------------------

static func shipyard_ports() -> Array:
	return data().get("shipyard_ports", [])


## Whether a port can drydock a company's ship: a shipyard port, or the company's hub with the Drydock facility.
static func is_yard(port_id: String, company: Company) -> bool:
	if port_id in shipyard_ports():
		return true
	var hub: Hub = company.hub_at(port_id) if company != null else null
	return hub != null and hub.effect_of("repairs") > 0.0


static func own_dock(port_id: String, company: Company) -> bool:
	var hub: Hub = company.hub_at(port_id) if company != null else null
	return hub != null and hub.effect_of("repairs") > 0.0


## Days out of service for a drydock: by tier, less at the company's own dock.
static func drydock_days(ship: Ship, port_id: String) -> float:
	var days: Array = data().get("drydock_days", [3, 5, 8, 14, 21])
	var tier := clampi(int(ship.model().get("tier", 1)), 1, days.size())
	return float(days[tier - 1]) * (float(data().get("own_dock_factor", 0.7)) if own_dock(port_id, GameState.owner_of(ship)) else 1.0)


## What a drydock costs: the repairs (every part put right, at the ship's repair
## cost a point, a quarter less at the company's dock) plus the yard's fee
## (a share of the ship's price; none at its own dock) plus the upgrades.
static func drydock_cost(ship: Ship, port_id: String, upgrade_ids: Array) -> int:
	flush(ship)
	var own := own_dock(port_id, GameState.owner_of(ship))
	var repairs := (1.0 - ship.maintenance) * ship.full_repair_cost() * (0.75 if own else 1.0)
	var fee := 0.0 if own else float(data().get("yard_fee", 0.02)) * float(ship.model().get("price", 0))
	var upgrades := 0.0
	for part_id: String in upgrade_ids:
		upgrades += upgrade_cost(ship, part_id)
	return roundi(repairs + fee + upgrades)


## An upgrade by its id: the catalogue's stock one for a part, or a technology's (Technology): {id, part, name, cost, effects, tech}.
static func upgrade_info(upgrade_id: String) -> Dictionary:
	for each: Dictionary in data().get("parts", []):
		var upgrade: Dictionary = each.get("upgrade", {})
		if not upgrade.is_empty() and str(upgrade.get("id", "")) == upgrade_id:
			return {id = upgrade_id, part = str(each.id), name = str(upgrade.name), cost = float(upgrade.get("cost", 0.0)), effects = upgrade.get("effects", {}), tech = ""}
	return Technology.upgrade_by_id(upgrade_id)


static func upgrade_cost(ship: Ship, upgrade_id: String) -> int:
	return roundi(float(upgrade_info(upgrade_id).get("cost", 0.0)) * float(ship.model().get("price", 0)))


## The upgrades a ship could still take: the stock one of each part without one, and the technology
## upgrades its company holds for its parts not fitted yet: [{id, part, part_name, name, cost, effects, tech}].
static func upgrades_open(ship: Ship) -> Array:
	var out := []
	var company: Company = GameState.owner_of(ship)
	for each: Dictionary in for_model(ship.model()):
		var fitted := str(ship.upgrades.get(each.id, ""))
		var stock: Dictionary = each.get("upgrade", {})
		if not stock.is_empty() and fitted.is_empty():
			out.append({id = str(stock.id), part = str(each.id), part_name = str(each.name), name = str(stock.name), cost = float(stock.get("cost", 0.0)), effects = stock.get("effects", {}), tech = ""})
		for tech_upgrade: Dictionary in GameState.technology.upgrades_for_part(company, str(each.id)):
			if str(tech_upgrade.id) != fitted:
				var info := tech_upgrade.duplicate()
				info.part_name = str(each.name)
				out.append(info)
	return out


## Every drydock a company's ship could sail to from where it lies, nearest first: [{port, own, days, nm}].
static func yards_for(ship: Ship) -> Array:
	var company: Company = GameState.owner_of(ship)
	var from := ship.docked_at
	var out := []
	var ports := shipyard_ports().duplicate()
	for hub: Hub in company.hubs:
		if own_dock(hub.port_id, company) and not hub.port_id in ports:
			ports.append(hub.port_id)
	for port_id: String in ports:
		if not ship.fits_port(port_id) or (port_id != from and not ship.fits_lane(from, port_id)):
			continue
		var nm := 0.0 if port_id == from else GameData.distance_nm(from, port_id)
		if port_id != from and not GameState.reachable(ship, from, port_id):
			continue
		out.append({port = port_id, own = own_dock(port_id, company), days = drydock_days(ship, port_id), nm = nm})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.nm) < float(b.nm))
	return out
