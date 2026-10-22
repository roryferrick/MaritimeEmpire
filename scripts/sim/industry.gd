# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Industry
extends RefCounted
## Cargo & Ore industry (data/industry.json): a building for every good the
## type trades. Mines (ore) and logging camps (timber) on claims at their
## resource ports, shared by every company; plants (metals, plastics,
## fertilizer) and factories (the container ships' goods) at any port a company
## has unlocked. Each makes its good a day at a time into its stockpile, from
## inputs in its store (what its company's ships unload there) or bought at
## the port when those run short; its company's ships load the stockpile free,
## or it's sold there. GameState owns one (its industry), saved with the world
## (the claims are everyone's); its actions are GameState's (with their Net
## commands), which call these for a company.
##
## Sites are keyed "PORT|building|n" (n from 0: a mine's claim, or a plant's
## place among those of its kind at the port).

const PATH := "res://data/industry.json"
const DAY_S := 86400.0
const MONTH_DAYS := 365.25 / 12.0
const KIND_NAMES := {mine = "Mines", camp = "Logging camps", plant = "Plants", factory = "Factories"}

static var _data := {}
static var _goods := {}
static var _buildings := {}
static var _makes := {}  # Good id -> its building's id.
static var _costs := {}

## Site key -> {building, port, owner (company index in GameState.all_companies()),
## stock (output units waiting), inputs {good: units}, day (the calendar day it
## last ran), made (units all time), paid, listing (asking price, 0 if not listed)}.
var sites := {}
## Counts every change (the map and screens look again when it moves on).
var version := 0
var _state: Node
var _by_port := {}  # Port id -> [site keys], worked out again when version moves.
var _by_port_version := -1


func _init(state: Node) -> void:
	_state = state


func _changed() -> void:
	version += 1
	_state.industry_changed.emit()


# --- The data ---------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {}
		for each: Dictionary in _data.get("goods", []):
			_goods[each.id] = each
		for each: Dictionary in _data.get("buildings", []):
			_buildings[each.id] = each
			_makes[each.makes] = each.id
	return _data


static func setting(key: String, default: Variant = 0.0) -> Variant:
	return data().get("settings", {}).get(key, default)


## The goods the industry adds to the markets (data order).
static func goods() -> Array:
	return data().get("goods", [])


static func good(id: String) -> Dictionary:
	data()
	return _goods.get(id, {})


## Every building, in the data's order (mines and camps, plants, factories).
static func buildings() -> Array:
	return data().get("buildings", [])


static func building(id: String) -> Dictionary:
	data()
	return _buildings.get(id, {})


## The building that makes a good ("" if none).
static func building_for(good_id: String) -> String:
	data()
	return str(_makes.get(good_id, ""))


## True for a building on claims at its resource ports (a mine or logging camp).
static func on_claims(building_id: String) -> bool:
	return str(building(building_id).get("kind", "")) in ["mine", "camp"]


## The good's colour for the map and screens (its hold colour, say), or "".
static func color_of(good_id: String) -> String:
	return str(good(good_id).get("color", ""))


## The commodities GameData adds to the markets, and their prices:
## [commodity, {region id: multiplier}, {port: multiplier}] each. A mine's or
## camp's ports are its good's sources at mine_price.
static func market_goods() -> Array:
	var out := []
	var defaults: Dictionary = setting("default_regions", {})
	for each: Dictionary in goods():
		var item := {id = each.id, name = each.name, unit = each.unit, units = each.units, base = float(each.base), industry = true}
		var regions: Dictionary = (defaults.get(each.line, {}) as Dictionary).duplicate()
		regions.merge(each.get("regions", {}), true)
		var sources: Dictionary = (each.get("sources", {}) as Dictionary).duplicate()
		var maker := building_for(str(each.id))
		if on_claims(maker):
			for port_id: String in building(maker).get("ports", {}):
				sources[port_id] = minf(float(sources.get(port_id, 1.0)), float(setting("mine_price", 0.5)))
		out.append([item, regions, sources])
	return out


## Units a building makes a calendar month.
static func output_a_month(building_id: String) -> float:
	return float(setting("output_a_month", {}).get(building(building_id).get("kind", "factory"), 600))


static func output_a_day(building_id: String) -> float:
	return output_a_month(building_id) / MONTH_DAYS


## The most a building's stockpile holds.
static func stock_cap(building_id: String) -> float:
	return output_a_month(building_id) * float(setting("stock_months", 3))


## The most of an input its store takes (stock_months of what it uses).
static func input_cap(building_id: String, good_id: String) -> float:
	return stock_cap(building_id) * float(building(building_id).get("inputs", {}).get(good_id, 0.0))


## What a building costs: its month's output over its inputs at base prices x
## cost_months, to the nearest $1M within cost_range (no_input_factor more for
## a plant or factory that takes nothing shipped), unless it sets its own.
static func cost(building_id: String) -> int:
	if _costs.has(building_id):
		return _costs[building_id]
	var each := building(building_id)
	var value := float(GameData.commodity(str(each.get("makes", ""))).get("base", 0.0))
	for input: String in each.get("inputs", {}):
		value -= float(each.inputs[input]) * float(GameData.commodity(input).get("base", 0.0))
	var amount := maxf(value, 0.0) * output_a_month(building_id) * float(setting("cost_months", 14))
	if (each.get("inputs", {}) as Dictionary).is_empty() and not on_claims(building_id):
		amount *= float(setting("no_input_factor", 1.5))
	var range: Array = setting("cost_range", [5000000, 80000000])
	var out := int(each.get("cost", clampi(roundi(amount / 1000000.0) * 1000000, int(range[0]), int(range[1]))))
	_costs[building_id] = out
	return out


static func upkeep_a_month(building_id: String) -> int:
	return roundi(cost(building_id) * float(setting("upkeep_a_month", 0.01)))


## True if a company can build: a Cargo & Ore company (or one from before types).
static func can_build(who: Company) -> bool:
	return who != null and who.has_type("cargo")


# --- State ----------------------------------------------------------------------

func reset() -> void:
	sites.clear()
	version += 1


func to_dict() -> Dictionary:
	return {sites = sites}


func from_dict(saved: Dictionary) -> void:
	sites = saved.get("sites", {}) if saved.get("sites") is Dictionary else {}
	for key: String in sites:
		var site: Dictionary = sites[key]
		site.owner = int(site.get("owner", -1))
		if not site.get("inputs") is Dictionary:
			site.inputs = {}
	version += 1


static func key_of(port_id: String, building_id: String, n: int) -> String:
	return "%s|%s|%d" % [port_id, building_id, n]


static func port_of(key: String) -> String:
	return key.get_slice("|", 0)


static func building_of(key: String) -> String:
	return key.get_slice("|", 1)


func site(key: String) -> Dictionary:
	return sites.get(key, {})


func owner_of(key: String) -> Company:
	var index := int(site(key).get("owner", -1))
	var all: Array[Company] = _state.all_companies()
	return all[index] if index >= 0 and index < all.size() else null


func _index_of(who: Company) -> int:
	return _state.all_companies().find(who)


## A company's sites ("" building for all), by port and building.
func owned_by(who: Company, building_id := "") -> Array[String]:
	var index := _index_of(who)
	var out: Array[String] = []
	for key: String in sites:
		if int(sites[key].get("owner", -1)) == index and (building_id.is_empty() or building_of(key) == building_id):
			out.append(key)
	out.sort()
	return out


## The sites at a port (every company's).
func sites_at(port_id: String) -> Array:
	if _by_port_version != version or _by_port.size() == 0 and not sites.is_empty():
		_by_port.clear()
		for key: String in sites:
			(_by_port.get_or_add(port_of(key), []) as Array).append(key)
		_by_port_version = version
	return _by_port.get(port_id, [])


## A resource port's claims for a mine or camp (taken or not), by number.
static func claims(building_id: String, port_id: String) -> int:
	return int(building(building_id).get("ports", {}).get(port_id, 0))


## How many of a port's claims for a building a company holds.
func claims_held(who: Company, building_id: String, port_id: String) -> int:
	return owned_by(who, building_id).filter(func(key: String) -> bool: return port_of(key) == port_id).size()


# --- Actions (a company's, through GameState) -------------------------------------

## Why a company can't build a building at a port ("" if it can).
func build_error(who: Company, building_id: String, port_id: String) -> String:
	if not can_build(who):
		return "Only Cargo & Ore companies build industry"
	var each := building(building_id)
	if each.is_empty() or GameData.get_port(port_id).is_empty():
		return "No such building or port"
	if on_claims(building_id):
		var total := claims(building_id, port_id)
		if total == 0:
			return "No %s claims at %s" % [str(GameData.commodity(str(each.makes)).get("name", "")).to_lower(), GameData.port_name(port_id)]
		if _free_claim(building_id, port_id) < 0:
			return "Every claim here is taken"
		if claims_held(who, building_id, port_id) >= int(setting("most_claims", 2)):
			return "You hold the most claims allowed here (%d)" % int(setting("most_claims", 2))
	elif claims_held(who, building_id, port_id) > 0:
		return "You have a %s here already" % str(each.name).to_lower()
	if _state.in_debt(who) or who.money < cost(building_id):
		return "Not enough money"
	return ""


func _free_claim(building_id: String, port_id: String) -> int:
	var total := claims(building_id, port_id) if on_claims(building_id) else 1 << 20
	for n in total:
		if not sites.has(key_of(port_id, building_id, n)):
			return n
	return -1


func build(who: Company, building_id: String, port_id: String) -> String:
	if not build_error(who, building_id, port_id).is_empty():
		return ""
	var price := cost(building_id)
	_state._add_money(who, -price)
	_state._record(null, "industry", price, who)
	var key := key_of(port_id, building_id, _free_claim(building_id, port_id))
	sites[key] = {building = building_id, port = port_id, owner = _index_of(who), stock = 0.0, inputs = {}, day = _today(), made = 0.0, paid = price, listing = 0}
	_changed()
	return key


## Closes a company's site: close_share of its price back (a claim is freed).
func close(who: Company, key: String) -> int:
	if owner_of(key) != who or who == null:
		return 0
	var refund := roundi(float(site(key).get("paid", 0)) * float(setting("close_share", 0.25)))
	sites.erase(key)
	_state._add_money(who, refund)
	_state._record(null, "industry", -refund, who)
	_changed()
	return refund


## Lists a site for other Cargo & Ore companies at an asking price (0 takes it off).
func list(who: Company, key: String, price: int) -> void:
	if owner_of(key) != who or who == null:
		return
	sites[key].listing = maxi(price, 0)
	_changed()


func listing_error(who: Company, key: String) -> String:
	var seller := owner_of(key)
	var entry := site(key)
	if seller == null or int(entry.get("listing", 0)) <= 0:
		return "Not for sale"
	if seller == who:
		return "Your own"
	if not can_build(who):
		return "Only Cargo & Ore companies build industry"
	var port_id := port_of(key)
	if claims_held(who, building_of(key), port_id) >= (int(setting("most_claims", 2)) if on_claims(building_of(key)) else 1):
		return "You hold as many of these here as you may"
	if _state.in_debt(who) or who.money < int(entry.listing):
		return "Not enough money"
	return ""


## Buys a listed site, stock and store with it: the seller is paid.
func buy_listing(who: Company, key: String) -> void:
	if not listing_error(who, key).is_empty():
		return
	var entry: Dictionary = sites[key]
	var seller := owner_of(key)
	var price := int(entry.listing)
	_state._add_money(who, -price)
	_state._record(null, "industry", price, who)
	_state._add_money(seller, price)
	_state._record(null, "industry", -price, seller)
	entry.owner = _index_of(who)
	entry.listing = 0
	entry.paid = price
	if seller == _state.company:
		ActivityLog.add("%s bought your %s at %s for %s." % [who.name, str(building(building_of(key)).name).to_lower(), GameData.port_name(port_of(key)), Fmt.money(price)], ActivityLog.Kind.GOOD)
	_changed()


## What a site's stockpile would fetch sold at its port now.
func stock_value(key: String) -> int:
	var who := owner_of(key)
	var good_id := str(building(building_of(key)).get("makes", ""))
	return roundi(floorf(float(site(key).get("stock", 0.0))) * float(_state.company_sell_price(port_of(key), good_id, who)))


## Sells a site's stockpile at its port. Returns the money.
func sell_stock(who: Company, key: String) -> int:
	if owner_of(key) != who or who == null:
		return 0
	var entry: Dictionary = sites[key]
	var units := floori(float(entry.get("stock", 0.0)))
	if units <= 0:
		return 0
	var good_id := str(building(building_of(key)).makes)
	var value := stock_value(key)
	entry.stock = float(entry.stock) - units
	_state._add_money(who, value)
	_state._record(null, "industry_sales", value, who)
	_state._tally_port_trade(who, port_of(key), good_id, units, value, true)
	_state.market.trade(port_of(key), good_id, value, false)
	_changed()
	return value


# --- The days ---------------------------------------------------------------------

func _today() -> int:
	return floori((_state.calendar_time() - _state.calendar_time_at(0.0)) / DAY_S)


## Runs every site up to today, a few days a step at most when fast-forwarding.
func step(_delta: float) -> void:
	if sites.is_empty():
		return
	var now := _today()
	var ran_any := false
	for key: String in sites.keys():
		var entry: Dictionary = sites[key]
		var ran := 0
		while int(entry.get("day", now)) < now and ran < 4:
			entry.day = int(entry.get("day", now)) + 1
			ran += 1
			_run_day(key, entry)
		ran_any = ran_any or ran > 0
	if ran_any:
		_changed()


## A day at a site: a day's output into its stockpile (up to its cap), its
## inputs taken from its store, or bought at the port for what's short; and a
## day's upkeep.
func _run_day(key: String, entry: Dictionary) -> void:
	var who := owner_of(key)
	if who == null:
		return
	var building_id := building_of(key)
	var port_id := port_of(key)
	var make := minf(output_a_day(building_id), maxf(stock_cap(building_id) - float(entry.get("stock", 0.0)), 0.0))
	if make > 0.0:
		var bought := 0.0
		var store: Dictionary = entry.get_or_add("inputs", {})
		var inputs: Dictionary = building(building_id).get("inputs", {})
		for input: String in inputs:
			var need := make * float(inputs[input])
			var take := minf(need, float(store.get(input, 0.0)))
			store[input] = float(store.get(input, 0.0)) - take
			if need > take:
				bought += (need - take) * float(_state.company_buy_price(port_id, input, who))
		if bought > 0.0:
			_state._add_money(who, -roundi(bought))
			_state._record(null, "industry", roundi(bought), who)
		entry.stock = float(entry.get("stock", 0.0)) + make
		entry.made = float(entry.get("made", 0.0)) + make
	var upkeep := roundi(upkeep_a_month(building_id) / MONTH_DAYS)
	_state._add_money(who, -upkeep)
	_state._record(null, "industry", upkeep, who)


# --- The ships --------------------------------------------------------------------

## What a unit of a good is worth to a company delivered to a port: the port's
## buy price if one of its sites there takes it as an input and has room (it
## saves buying it there), else 0. Market.best_cargo() weighs it against selling.
func input_value(who: Company, port_id: String, good_id: String) -> float:
	if sites.is_empty():
		return 0.0
	var index := _index_of(who)
	for key: String in sites_at(port_id):
		var entry: Dictionary = sites[key]
		if int(entry.get("owner", -1)) != index:
			continue
		var building_id := building_of(key)
		if (building(building_id).get("inputs", {}) as Dictionary).has(good_id) and float(entry.get("inputs", {}).get(good_id, 0.0)) < input_cap(building_id, good_id) - 1.0:
			return float(_state.company_buy_price(port_id, good_id, who))
	return 0.0


## A ship unloading where its company has a site taking its cargo as an input:
## as much as the store has room for goes into it. Returns [units, their worth
## at the port's buy price] (what the site would have paid for them there).
func take_delivery(ship: Ship) -> Array:
	if sites.is_empty() or ship.cargo_qty <= 0:
		return [0, 0]
	var who: Company = _state.owner_of(ship)
	var index := _index_of(who)
	var left := ship.cargo_qty
	var units := 0
	for key: String in sites_at(ship.docked_at):
		var entry: Dictionary = sites[key]
		var building_id := building_of(key)
		if int(entry.get("owner", -1)) != index or not (building(building_id).get("inputs", {}) as Dictionary).has(ship.cargo_id):
			continue
		var store: Dictionary = entry.get_or_add("inputs", {})
		var room := floori(input_cap(building_id, ship.cargo_id) - float(store.get(ship.cargo_id, 0.0)))
		var put := mini(left, maxi(room, 0))
		if put <= 0:
			continue
		store[ship.cargo_id] = float(store.get(ship.cargo_id, 0.0)) + put
		left -= put
		units += put
	if units > 0:
		_changed()
	return [units, roundi(units * float(_state.company_buy_price(ship.docked_at, ship.cargo_id, who)))]


## A ship loading where its company has a site whose good it carries: it takes
## the stockpile that pays most where it's going, free, up to its room. Sets
## the ship's cargo and returns [commodity, units], or [] for none.
func load_ship(ship: Ship, to: String) -> Array:
	if sites.is_empty():
		return []
	var who: Company = _state.owner_of(ship)
	var index := _index_of(who)
	var carries: Array = ship.model().get("cargo", [])
	var best := ""
	var best_gain := 0.0
	for key: String in sites_at(ship.docked_at):
		var entry: Dictionary = sites[key]
		var good_id := str(building(building_of(key)).get("makes", ""))
		if int(entry.get("owner", -1)) != index or not carries.has(good_id) or float(entry.get("stock", 0.0)) < 1.0:
			continue
		var gain := minf(float(entry.stock), ship.capacity() / GameData.hold_of(good_id)) * maxf(float(_state.company_sell_price(to, good_id, who)), input_value(who, to, good_id))
		if gain > best_gain:
			best_gain = gain
			best = key
	if best.is_empty():
		return []
	var entry: Dictionary = sites[best]
	var good_id := str(building(building_of(best)).makes)
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(ship.docked_at, to, ship.model())) / GameData.hold_of(good_id))
	var quantity := mini(room, floori(float(entry.stock)))
	if quantity <= 0:
		return []
	entry.stock = float(entry.stock) - quantity
	ship.cargo_id = good_id
	ship.cargo_from = ship.docked_at
	ship.cargo_qty = quantity
	ship.cargo_cost = 0  # (Its own: free.)
	_state.cargo_loaded.emit(ship, ship.docked_at, good_id, quantity, 0, to)
	_state.ship_changed.emit(ship)
	_changed()
	return [good_id, quantity]
