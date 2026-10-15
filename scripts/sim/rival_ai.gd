# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name RivalAI
extends RefCounted
## AI rivals: companies (Company.ai: "easy", "normal" or "hard") that play the
## game for themselves, by the same rules and with the same money as a person.
## Added when a game is founded (add_rivals()), saved with it like any company,
## and run by the host (or in single player) every few seconds of play each
## (step()). Each think, a rival:
## - keeps afloat: in debt it borrows (if the bank will lend) or sells its
##   least useful ship; it pays its loans back once it can spare the money;
## - unlocks market regions (the one nearest its hubs) and founds hubs (the
##   port its best ship would earn most from) as its level allows;
## - starts as a company type picked at random, and picks another type it
##   lacks at random each time its level allows (Progression.type_slots());
## - buys ships: the cargo model that pays for itself soonest on the best loop
##   it can find from one of its hubs (2 or 3 ports, by the same prices, fuel,
##   repairs and wages a ship of its pays), keeping back the money its ships
##   need for their loads; and gives every ship without a route the best loop
##   from where it is (a hard rival also moves ships to better loops later);
## - spends upgrade points (ships' skills, hub paths), buys mega upgrades and
##   builds industry at its hubs for the commodities its ships trade there;
## - buys tugs, a recovery boat (its ships recover themselves automatically)
##   and, with seasonal closures, icebreakers for the ice its routes run into;
## - saves up (its bank reserve) when what it wants next costs more than it has.
## It acts through GameState's own functions with itself as GameState.company
## (GameState.ai_acting meanwhile, so nothing goes in this player's log and
## nothing saves), and reports its big moves to this player's activity log.

const LEVELS := ["easy", "normal", "hard"]
const LEVEL_NAMES := {easy = "Easy", normal = "Normal", hard = "Hard"}
const MAX_RIVALS := 5
## By difficulty: how often it thinks (s of play); how many of its best loops
## it picks from (at random: 1 = always the best); whether it looks at 3-port
## loops; how often (s) it looks for a better loop for a ship it has (0:
## never); the share of its money it keeps back beyond what its ships need;
## how long (s) a new ship may take to pay for itself; how often (thinks) it
## spends upgrade points; the most of its money one hub upgrade, industry
## building or mega upgrade may cost (luxury); whether it borrows to grow
## (else only when in debt);
## and which kinds of recommended start it gets (see data/starts.json).
const SETTINGS := {
	easy = {think_s = 15.0, pick = 5, loops3 = false, reroute_s = 0.0, keep = 0.3, payback_s = 900.0, upgrade_every = 4, luxury = 0.1, borrow = false, starts = ["fair", "hard"]},
	normal = {think_s = 7.0, pick = 2, loops3 = true, reroute_s = 300.0, keep = 0.1, payback_s = 1500.0, upgrade_every = 2, luxury = 0.15, borrow = false, starts = ["great", "fair"]},
	hard = {think_s = 3.0, pick = 1, loops3 = true, reroute_s = 120.0, keep = 0.0, payback_s = 2400.0, upgrade_every = 2, luxury = 0.25, borrow = true, starts = ["excellent", "great"]},
}
## Rivals' names: a first word and a second.
const NAME_FIRST := ["Northstar", "Blue Anchor", "Meridian", "Tidewater", "Ironclad", "Silver Wake", "Crescent", "Harbor Light",
	"Seaborne", "Atlas", "Pacific Rim", "Coral Bay", "Windward", "Saltmarsh", "Polaris", "Red Funnel", "Greywater", "Lighthouse",
	"Cape Horn", "Trident", "Admiral", "Seagull", "Long Reach", "Bluewater"]
const NAME_SECOND := ["Shipping", "Lines", "Maritime", "Freight", "Logistics", "Marine", "Carriers", "Navigation", "Shipping Co", "Transport"]
## Seconds a ship spends coming in and going out at a port, beyond its dock time.
const STOP_EXTRA_S := 6.0
## The most ports it looks at from one port for 3-port loops (its best 2-port partners).
const LOOP_PARTNERS := 12
## A loop other ships of its already sail is worth this much less for each.
const CROWDING := 0.8
## A hard or normal rival moves a ship to a new loop only if it's this much better.
const REROUTE_GAIN := 1.25
## It announces its company level every this many levels.
const NEWS_LEVELS := 10
## How long (s of play) it keeps its loops (prices move slowly) and the ports
## a model can sail to from a port (they change only with its regions and port sizes).
## How many ports it weighs up a think when choosing where to found a hub.
const HUB_PORTS_A_THINK := 4
const LOOPS_KEEP_S := 30.0
const FRESH_LOOPS_A_THINK := 2
## It looks at its tugs, recovery boat and icebreakers every this many thinks.
const SERVICE_EVERY := 3
const PARTNERS_KEEP_S := 300.0

var _state: Node
## Per rival (Company -> {think (s till it next thinks), reroute (s), thinks
## (count), level (last announced)}); not saved: worked out again on load.
var _minds := {}
var _rng := RandomNumberGenerator.new()
## Worked out before (see _best_loops() and _partners()): key -> {time, loops or ports}.
var _loops_kept := {}
## Prices and bonuses looked up in this think (Market.best_cargo()'s memo):
## nothing changes them mid-think but a new hub or building, which clears it.
var _prices := {}
var _partners_kept := {}
## Loops worked out afresh this think (see _best_loops()).
var _fresh_loops := 0
## Whether this think bought or sold a ship, or changed a hub or region: this
## player's screens are then told again once it's done (they may have heard of
## it meanwhile, with the rival as GameState.company).
var _ships_changed := false
var _hubs_changed := false


func _init(state: Node) -> void:
	_state = state
	_rng.randomize()


## Forgets what it worked out about the last game's rivals (a new game or a load).
func reset() -> void:
	_minds.clear()
	_loops_kept.clear()
	_partners_kept.clear()


## Adds `count` rivals (up to MAX_RIVALS) of a difficulty to a new game: each
## with a name and color no one has, a home port from its difficulty's
## recommended starts (no one's, and in a market region no one has yet if it
## can), the starting money, an HQ and a CEO.
func add_rivals(count: int, level: String) -> void:
	if not SETTINGS.has(level):
		level = "normal"
	for i in clampi(count, 0, MAX_RIVALS):
		var type_id := str(Progression.company_types().pick_random().id)  # (Any type, repeats and all.)
		var port := _pick_home_port(level, type_id)
		if port.is_empty():
			return
		var rival := Company.new(_pick_name(), _pick_color(), port)
		rival.ai = level
		rival.company_types = {type_id: 1}
		rival.logo = CompanyLogo.default_logo(rival.color, _rng.randi())  # (A shape, layout and second colour at random.)
		rival.money = int(GameData.config.get("starting_money", 10000))
		rival.ceo = Company.random_ceo()
		rival.hubs.assign([Hub.new(port, true)])
		rival.regions.assign([str(GameData.port_region(port).get("id", ""))])
		if _state.companies.is_empty():
			_state.companies.assign([_state.company])
		_state.companies.append(rival)


## The game's AI rivals.
func rivals() -> Array[Company]:
	var out: Array[Company] = []
	for each: Company in _state.companies:
		if each.is_ai():
			out.append(each)
	return out


## Each rival thinks when its time comes (they're spread out, so not all at once).
func step(delta: float) -> void:
	var i := 0
	for rival in rivals():
		var mind: Dictionary = _minds.get_or_add(rival, {think = 1.0 + i * 0.7, reroute = 0.0, thinks = 0, level = -1})
		i += 1
		mind.think = float(mind.think) - delta
		mind.reroute = float(mind.reroute) - delta
		if float(mind.think) > 0.0:
			continue
		mind.think = float(_settings(rival).think_s) * _rng.randf_range(0.8, 1.2)
		mind.thinks = int(mind.thinks) + 1
		_fresh_loops = 0
		_forget_fleet(rival)
		_think(rival, mind)


static func _settings(rival: Company) -> Dictionary:
	return SETTINGS.get(rival.ai, SETTINGS.normal)


# --- Divine Actions ---------------------------------------------------------------

## How often (game weeks, scaled by the difficulty's divine_every) a rival
## looks to use a divine power, and how many times a power's price it keeps in
## hand before it buys one.
const DIVINE_WEEKS := {easy = 3.0, normal = 1.5, hard = 1.0}
const DIVINE_CUSHION := 2.0

## In a Divine Actions game: about once a week (or three, for an easy rival)
## the rival picks on the richest other company, and uses the first power it
## can afford twice over (so it keeps running) and that it has a target for,
## trying them in a random order: a storm or the Kraken on one of that
## company's ships at sea, a plague, a deluge or lightning on its busiest port
## (its hub, for lightning), fair winds for its own fleet, calm seas where its
## own ship is caught in a storm, a great flock on its own busiest port.
func _divine(rival: Company, settings: Dictionary, mind: Dictionary) -> Array:
	var divine: Divine = _state.divine
	if not divine.on:
		return []
	if float(mind.get("divine", 0.0)) > _state.play_time:
		return []
	mind.divine = _state.play_time + divine.week_s() * float(DIVINE_WEEKS.get(rival.ai, 1.5)) * _rng.randf_range(0.6, 1.4)
	var foes: Array = _state.all_companies().filter(func(each: Company) -> bool: return each != rival)
	if foes.is_empty():
		return []
	foes.sort_custom(func(a: Company, b: Company) -> bool: return a.money > b.money)
	var foe: Company = foes[0]
	var order := Divine.ORDER.duplicate()
	order.shuffle()
	for power: String in order:
		if rival.money < divine.price(power, rival) * DIVINE_CUSHION:
			continue
		var target: Variant = _divine_target(power, rival, foe)
		if target == null and str(Divine.POWERS[power].target) != "none":
			continue
		if not divine.error(power, target, rival).is_empty():
			continue
		var text: String = _state.divine_act(power, target)
		if text.is_empty():
			continue
		if power == "lightning":
			_hubs_changed = true
		return []  # (divine_act() logged it, in the rival's colour.)
	return []


## A rival's target for a power against a foe (see _divine()), or null if it has none.
func _divine_target(power: String, rival: Company, foe: Company) -> Variant:
	var at_sea: Array = _state.fleet(foe).filter(func(ship: Ship) -> bool:
		return not ship.is_service() and not ship.is_docked() and not ship.is_lost() and not ship.is_carried() and not ship.is_towed())
	match power:
		"squall", "tempest", "wrath":
			if at_sea.is_empty():
				return null
			var ship: Ship = at_sea[_rng.randi() % at_sea.size()]
			return Geo.unproject(ship.world_position())
		"kraken":
			return int((at_sea[_rng.randi() % at_sea.size()] as Ship).id) if not at_sea.is_empty() else null
		"plague", "deluge":
			return _busiest_port(foe)
		"sea_change":
			return _busiest_port(rival)
		"lightning":
			var hubs: Array = foe.hubs.filter(func(hub: Hub) -> bool: return hub.level > 0)
			return str((hubs[_rng.randi() % hubs.size()] as Hub).port_id) if not hubs.is_empty() else null
		"calm_seas":
			for ship: Ship in _state.fleet(rival):
				if not ship.is_docked() and not ship.is_lost() and float(_state._storm_factors(ship)[0]) < 0.9:
					return Geo.unproject(ship.world_position())
			return null
	return null


## The port a company's ships are at and bound for most (its HQ if none), or "".
func _busiest_port(who: Company) -> Variant:
	var counts := {}
	for ship: Ship in _state.fleet(who):
		for port: String in [ship.docked_at, ship.to_port]:
			if not port.is_empty():
				counts[port] = int(counts.get(port, 0)) + 1
	var best := who.home_port
	var most := 0
	for port: String in counts:
		if int(counts[port]) > most:
			most = int(counts[port])
			best = port
	return best if not best.is_empty() else null


# --- Thinking -------------------------------------------------------------------

## One think: as the rival (see the top), what it does now. Then this player's
## screens are told everything may have changed back.
## How often (in thinks) a rival looks at its farms.
const FARM_EVERY := 5

func _think(rival: Company, mind: Dictionary) -> void:
	var mine: Company = _state.company
	_state.company = rival
	_state.ai_acting = rival
	var news: Array = []
	_ships_changed = false
	_hubs_changed = false
	var settings := _settings(rival)
	_prices.clear()
	_keep_afloat(rival, settings)
	news.append_array(_grow(rival))
	_prices.clear()  # (A new hub changes its prices.)
	_route_idle_ships(rival, settings)
	news.append_array(_buy_ships(rival, settings))
	news.append_array(_run_cruises(rival))
	if int(mind.thinks) % FARM_EVERY == 0:  # (Its farms, simply: see Farms.run_rival().)
		news.append_array((_state.farms as Farms).run_rival(rival, maxi(rival.money - _needs(rival, settings) * 2, 0)))
	if float(settings.reroute_s) > 0.0 and float(mind.reroute) <= 0.0:
		mind.reroute = float(settings.reroute_s)
		_reroute_one(rival, settings)
	if int(mind.thinks) % int(settings.upgrade_every) == 0:
		news.append_array(_spend(rival, settings))
	if int(mind.thinks) % SERVICE_EVERY == 0:
		news.append_array(_service_ships(rival, settings))
	news.append_array(_divine(rival, settings, mind))
	_save_up(rival, settings)
	_state.company = mine
	_state.ai_acting = null
	_state.money_changed.emit(mine.money)
	_state.company_xp_changed.emit(mine.xp)
	if _ships_changed:
		_state.ships_changed.emit()
	if _hubs_changed:
		_state.hubs_changed.emit()
		_state.regions_changed.emit()
	var level := rival.level()
	if int(mind.level) < 0:
		mind.level = level - level % NEWS_LEVELS  # (Nothing to announce on loading a game.)
	elif level >= int(mind.level) + NEWS_LEVELS:
		mind.level = level - level % NEWS_LEVELS
		news.append("reached company level %d" % mind.level)
	for text: String in news:
		ActivityLog.add("%s %s." % [rival.name, text], ActivityLog.Kind.INFO, _state.company_color_value(rival.color))


## In debt: borrow (if the bank will lend), else sell its least useful docked
## ship (never its last cargo ship). Out of debt with money to spare: pay a
## step of its loan back.
func _keep_afloat(rival: Company, settings: Dictionary) -> void:
	if rival.money < 0:
		if _state.take_loan_error().is_empty():
			_state.take_loan()
			return
		var cargo := _cargo_ships(rival)
		if cargo.size() > 1:
			var worst: Ship = null
			var worst_rate := INF
			for ship in cargo:
				if not _state.sell_error(ship).is_empty():
					continue
				var rate := _route_rate(rival, ship, ship.route)
				if rate < worst_rate:
					worst = ship
					worst_rate = rate
			if worst != null:
				_state.sell_ship(worst)
				_forget_fleet(rival)
		return
	var step := int(_state.loan_settings().get("step", 1000000))
	if rival.loan > 0 and rival.money > step * 2 + _needs(rival, settings) and _state.repay_loan_error().is_empty():
		_state.repay_loan()


## Unlocks a region (the one with a port nearest its hubs) and founds a hub (at
## the port its best cargo model would earn most from) when its level allows.
func _grow(rival: Company) -> Array:
	var news := []
	if _state.company_types_available(rival) > 0:
		var choices := Progression.company_types().filter(func(each: Dictionary) -> bool: return not rival.has_type(each.id))
		if not choices.is_empty():
			var type_id := str(choices.pick_random().id)
			_state.take_company_type(rival, type_id)
			_forget_fleet(rival)
			news.append("branched out into %s" % Progression.type_name(type_id))
	if _state.regions_available() > 0:
		var region := _nearest_region(rival)
		if not region.is_empty() and _state.unlock_region(region).is_empty():
			_hubs_changed = true
			news.append("opened up %s" % _state._region_name(region))
	if _state.hubs_available() > 0:
		var port := _best_hub_port(rival)
		if not port.is_empty() and _state.build_hub(port).is_empty():
			_hubs_changed = true
			news.append("founded a hub at %s" % GameData.port_name(port))
	return news


## Gives each of its cargo ships with no route (and not lost) the best loop from where it is.
func _route_idle_ships(rival: Company, settings: Dictionary) -> void:
	for ship in _cargo_ships(rival):
		if ship.has_route() or ship.is_lost() or not ship.pending_route.is_empty():
			continue
		var loops := _best_loops(rival, ship.model(), ship.reference_port(), settings)
		if not loops.is_empty():
			var route: Array[String] = []
			route.assign(_pick(loops, settings)[1])
			_state.assign_route(ship, route)
			(_minds[rival] as Dictionary).erase("sailing")  # (Its loops have changed.)


## Buys the cargo ship that pays for itself soonest on its best loop from one
## of its hubs (within the difficulty's payback time), as long as it keeps
## back what its ships need; a hard rival may buy a few in one think, and
## borrow for one. Each new ship sets off on its loop and recovers itself if lost.
func _buy_ships(rival: Company, settings: Dictionary) -> Array:
	var news := []
	# Starting out (fewer than 3 cargo ships), any ship that makes money will do.
	var starting_out := _cargo_ships(rival).size() < 3
	var step := int(_state.loan_settings().get("step", 1000000))
	for attempt in (3 if rival.ai == "hard" else 1):
		var best := {}
		var level := rival.level()
		var counts := _model_counts(rival)
		# What it could spend (borrowing too, if it would): it looks at ships up
		# to 3x that, to save up for.
		var budget := rival.money - _needs(rival, settings) + (step if bool(settings.borrow) and rival.loan < _borrow_limit(rival) else 0)
		for model: Dictionary in GameData.ship_models:
			if _is_service_model(model) or Progression.unlock_level(model, rival) > level or int(counts.get(model.id, 0)) >= Progression.model_slots(model, level, rival):
				continue
			var price: int = _state.ship_price(model.id)
			if price > maxi(budget, 0) * 3:
				continue
			for hub in rival.hubs:
				if not _state.can_launch_at(model.id, hub.port_id):
					continue
				var loops := _best_loops(rival, model, hub.port_id, settings)
				if loops.is_empty():
					continue
				var rate: float = loops[0][0]  # $ a second.
				# The richer it is for the price, the longer it'll wait for a ship to pay for itself (up to 4x).
				var payback := float(settings.payback_s) * clampf(rival.money / (maxf(price, 1.0) * 10.0), 1.0, 4.0)
				if rate <= 0.0 or (price / rate > payback and not starting_out):
					continue
				var score := rate - price / payback
				if best.is_empty() or score > float(best.score):
					best = {score = score, model = model, port = hub.port_id, loops = loops, price = price}
		if best.is_empty():
			break
		var error: String = _state.buy_error(best.model.id)
		if not error.is_empty() and error != "You can't afford this ship.":
			break
		var spare: int = rival.money - _needs(rival, settings) - int(best.price)
		if spare < 0 and bool(settings.borrow) and rival.loan < _borrow_limit(rival) and int(best.price) / maxf(float(best.loops[0][0]), 0.001) < float(settings.payback_s) / 2.0 \
				and rival.money + int(_state.loan_settings().get("step", 1000000)) - _needs(rival, settings) >= int(best.price) and _state.take_loan_error().is_empty():
			_state.take_loan()
			spare = rival.money - _needs(rival, settings) - int(best.price)
		if spare < 0:
			mind_saving(rival, int(best.price) + _needs(rival, settings))
			break
		var model: Dictionary = best.model
		var first: bool = _state.owned_count(model.id) == 0
		var ship: Ship = _state.buy_ship(model.id, _state.suggest_ship_name(), best.port)
		_forget_fleet(rival)
		if ship == null:
			break
		_state.set_auto_recover(ship, true)
		var route: Array[String] = []
		route.assign(_pick(best.loops, settings)[1])
		_state.assign_route(ship, route)
		(_minds[rival] as Dictionary).erase("sailing")  # (Its loops have changed.)
		if first and Progression.unlock_level(model, rival) > 1:
			news.append("launched its first %s" % model.get("name", model.id))
	return news


## Looks again at one of its ships: on a loop much worse than the best it could
## sail now, it moves to that one.
func _reroute_one(rival: Company, settings: Dictionary) -> void:
	var cargo := _cargo_ships(rival).filter(func(ship: Ship) -> bool: return ship.has_route() and ship.pending_route.is_empty())
	if cargo.is_empty():
		return
	var ship: Ship = cargo[_rng.randi() % cargo.size()]
	var now := _route_rate(rival, ship, ship.route, ship)
	var loops := _best_loops(rival, ship.model(), ship.reference_port(), settings, ship)
	if loops.is_empty() or float(loops[0][0]) <= maxf(now, 0.0) * REROUTE_GAIN + 0.01:
		return
	var route: Array[String] = []
	route.assign(loops[0][1])
	_state.assign_route(ship, route)
	(_minds[rival] as Dictionary).erase("sailing")  # (Its loops have changed.)


## Spends upgrade points: ships' skills (Upgrade all), hub paths (Sale prices
## first, then port stops, fuel and repairs, ship XP), mega upgrades it
## qualifies for, and industry buildings on its hubs' open plots.
func _spend(rival: Company, settings: Dictionary) -> Array:
	var news := []
	var keep := _needs(rival, settings)
	if _state.fleet(rival).any(func(ship: Ship) -> bool: return ship.skill_points() > 0):
		_state.bank_reserve = keep  # (Upgrade all stops short of it.)
		_state.upgrade_all()
	for hub in rival.hubs:
		for path: String in ["pay", "speed", "costs", "xp"]:
			while _state.upgrade_hub_error(hub, path).is_empty() and rival.money - hub.upgrade_cost(path) >= keep and _affords(rival, settings, hub.upgrade_cost(path)):
				_state.upgrade_hub(hub, path)
				_hubs_changed = true
	var counts := _model_counts(rival)
	for model: Dictionary in GameData.ship_models:
		if int(counts.get(model.id, 0)) >= int(model.get("max_owned", 8)) and _state.mega_error(model.id).is_empty() and rival.money - _state.mega_cost(model.id) >= keep and _affords(rival, settings, _state.mega_cost(model.id)):
			_state.buy_mega(model.id)
			news.append("mega-upgraded its %ss" % model.get("name", model.id))
	for hub in rival.hubs:
		for slot in hub.industry_slots():
			if not hub.industries[slot].is_empty() or rival.money - _state.industry_price() < keep * 2 or not _affords(rival, settings, _state.industry_price()):
				continue
			var commodity := _industry_choice(rival, hub)
			if not commodity.is_empty() and _state.build_industry_error(hub, slot, commodity).is_empty():
				_state.build_industry(hub, slot, commodity)
				_prices.clear()  # (Its new building changes its prices there.)
				_hubs_changed = true
				news.append("built a %s at %s" % [_state.industry_name(commodity), GameData.port_name(hub.port_id)])
	return news


## True if something costs no more than its difficulty's luxury share of its money.
static func _affords(rival: Company, settings: Dictionary, cost: int) -> bool:
	return cost <= rival.money * float(settings.luxury)


## Tugs (one a think, once it has 4 cargo ships: up to 2 and one more for every
## 4 cargo ships), a recovery boat (once it has
## 5 and none), and with seasonal closures an icebreaker stationed at each
## icebreaker area its routes' ports are in (and none of its own there yet).
func _service_ships(rival: Company, settings: Dictionary) -> Array:
	var news := []
	var cargo := _cargo_ships(rival)
	var keep := _needs(rival, settings)
	var tug: String = _state.tug_model_id()
	var counts := _model_counts(rival)
	var tugs := int(counts.get(tug, 0))
	if cargo.size() >= 4 and tugs < 2 + cargo.size() / 4 and not tug.is_empty() and _state.buy_error(tug).is_empty() and rival.money - _state.ship_price(tug) * 2 >= keep:
		_state.buy_ship(tug, _state.suggest_ship_name())
		_forget_fleet(rival)

	if cargo.size() >= 5 and not counts.keys().any(func(model_id: String) -> bool: return GameData.get_ship_model(model_id).get("recovery", false)):
		var cheapest := _cheapest(func(model: Dictionary) -> bool: return model.get("recovery", false))
		if not cheapest.is_empty() and _state.buy_error(cheapest).is_empty() and rival.money - _state.ship_price(cheapest) >= keep:
			var boat: Ship = _state.buy_ship(cheapest, _state.suggest_ship_name())
			_forget_fleet(rival)
			if boat != null:
				news.append("bought its first recovery boat")
	if _state.seasons:
		var ports := {}
		for ship in cargo:
			for port_id in ship.route:
				ports[port_id] = true
		for area: Dictionary in _state.icebreaking.areas():
			if not ports.keys().any(func(port_id: String) -> bool: return _state.icebreaking.port_inside(area, port_id)):
				continue
			if _state.icebreaking.stationed(area.id).any(func(ship: Ship) -> bool: return _state.owner_of(ship) == rival):
				continue
			var model_id := _cheapest(func(model: Dictionary) -> bool:
				return not str(model.get("icebreaker", "")).is_empty() and _state.icebreaking.station_error(area, model).is_empty())
			if model_id.is_empty() or not _state.buy_error(model_id).is_empty() or rival.money - _state.ship_price(model_id) < keep * 2:
				continue
			var breaker: Ship = _state.buy_ship(model_id, _state.suggest_ship_name())
			_forget_fleet(rival)
			if breaker != null and _state.station_icebreaker(breaker, area.id).is_empty():
				news.append("stationed an icebreaker at the %s" % area.get("name", area.id))
	return news


## Saving up: with what it wants next costing more than it has (see
## mind_saving()), ships keep back half of what it has towards it; otherwise nothing.
func _save_up(rival: Company, settings: Dictionary) -> void:
	var mind: Dictionary = _minds.get(rival, {})
	var goal := int(mind.get("goal", 0))
	mind.erase("goal")
	_state.bank_reserve = clampi(goal / 2, 0, maxi(rival.money / 2, 0)) if goal > rival.money else 0


## What it's saving for next (see _save_up()).
func mind_saving(rival: Company, amount: int) -> void:
	(_minds.get_or_add(rival, {}) as Dictionary).goal = amount


# --- Judging trades ---------------------------------------------------------------

## Its best loops for a model from a port, best first: [[$ a second, route]],
## each 2 ports (and 3, if its difficulty looks at them), every leg one the
## model can sail between ports it has unlocked. A loop its other ships
## already sail is worth less for each (CROWDING); `ship` (if moving one)
## doesn't count. The loops are worked out again after LOOPS_KEEP_S of play or
## so (prices move slowly; spread out so they don't all fall due at once, and
## no more than FRESH_LOOPS_A_THINK a think: past that it makes do with older
## ones, or none till a later think), the
## ports it can sail to every PARTNERS_KEEP_S.
func _best_loops(rival: Company, model: Dictionary, start: String, settings: Dictionary, ship: Ship = null) -> Array:
	var key := "%d|%s|%s|%s" % [rival.get_instance_id(), model.id, start, settings.loops3]
	var kept: Dictionary = _loops_kept.get(key, {})
	var loops: Array
	var stale: bool = kept.is_empty() or _state.play_time > float(kept.due)
	if not stale:
		loops = kept.loops
	elif _fresh_loops >= FRESH_LOOPS_A_THINK:
		loops = kept.get("loops", [])  # (None yet: it'll look next think.)
	else:
		_fresh_loops += 1
		loops = _work_out_loops(rival, model, start, bool(settings.loops3))
		_loops_kept[key] = {due = _state.play_time + LOOPS_KEEP_S * _rng.randf_range(0.7, 1.3), loops = loops}
	var sailing := _routes_sailed(rival)
	var crowded := []
	for loop: Array in loops:
		var route_key := _route_key(loop[1])
		var count := int(sailing.get(route_key, 0))
		if ship != null and _route_key(ship.route if ship.pending_route.is_empty() else ship.pending_route) == route_key:
			count -= 1
		crowded.append([float(loop[0]) * pow(CROWDING, maxi(count, 0)), loop[1]])
	crowded.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return crowded.slice(0, 8)


## The loop search natively (RouteFinder: the same loops, in the same order),
## when the native library's there and use_native_routes is on (tests turn it
## off to compare).
var _route_finder: Object = ClassDB.instantiate(&"RouteFinder") if ClassDB.class_exists(&"RouteFinder") else null
var use_native_routes := true
var _route_probe: Ship = null


## What RouteFinder needs to find a model's loops from a port as RivalAI does.
func _route_context(rival: Company, model: Dictionary, start: String, probe: Ship, partners: Array, loops3: bool) -> Dictionary:
	var hubs := {}
	for hub in rival.hubs:
		var sells := {}
		var buys := {}
		for commodity: String in model.get("cargo", []):
			sells[commodity] = hub.industry_bonus(commodity, "sell")
			buys[commodity] = hub.industry_bonus(commodity, "buy")
		hubs[hub.port_id] = [hub.bonus("pay"), sells, buys]
	var markets := GameData.markets
	return {start = start, partners = partners, loops3 = loops3, loop_partners = LOOP_PARTNERS, model = model,
		model_id = str(model.get("id", "")), cargo = model.get("cargo", []), capacity = float(model.get("capacity", 0)),
		model_fuel_per_s = float(model.get("fuel_per_s", 0.0)), wear_pct_per_min = float(model.get("wear_pct_per_min", 0.0)),
		repair_cost_per_pct = float(model.get("repair_cost_per_pct", 0.0)), dock_s = float(model.get("dock_s", 0.0)),
		stop_extra_s = STOP_EXTRA_S, port_fee = float(GameData.config.get("port_fee", 0.1)),
		wages_s = float(_state.crew_wages(model)) / maxf(float(GameData.config.get("crew", {}).get("period_days", 14)) * 86400.0 / maxf(_state.calendar_seconds_per_second(), 0.001), 1.0),
		mega = 1.0 + (float(GameData.config.get("mega", {}).get("profit_bonus", 0.5)) if rival.has_mega(str(model.get("id", ""))) else 0.0),
		hubs = hubs, impacts = _state.market._impacts, play_time = _state.play_time,
		drift = float(markets.get("drift", 0.0)), drift_period_s = float(markets.get("drift_period_s", 1200)),
		impact_half_life_s = float(markets.get("impact_half_life_s", 40)), spread = float(markets.get("spread", 0.0)),
		fuel_per_oil = float(markets.get("fuel_per_oil", 0.0)), range_nm = probe.range_nm(), seaway = bool(model.get("seaway", false)),
		fuel_per_s = probe.fuel_per_s(), fuel_tank = probe.fuel_tank(), departure_margin_s = GameState.DEPARTURE_MARGIN_S,
		top_speed = probe.top_speed(), wear_per_s = probe.wear_per_s()}


## For RouteFinder: a pair of ports' fixed facts [nm, toll share, lock s, convoy s, sale factor, needs the seaway].
func _route_pair(a: String, b: String) -> Array:
	return [GameData.distance_nm(a, b), GameData.leg_toll_share(a, b), GameData.canal_lock_seconds(a, b),
		GameData.convoy_wait_seconds(a, b), GameData.sale_factor(a, b), GameData.needs_seaway(a, b)]


## For RouteFinder: a port now [impact factor, cost factor, whether the model fits, lon, lat].
func _route_port(port_id: String, model: Dictionary) -> Array:
	var port := GameData.get_port(port_id)
	return [_state.port_sizes.impact_factor(port_id), _state.port_sizes.cost_factor(port_id), _state.port_sizes.fits(model, port_id),
		float(port.get("lon", 0.0)), float(port.get("lat", 0.0))]


func _route_base_price(port_id: String, commodity_id: String) -> float:
	return GameData.base_price(port_id, commodity_id)


## For RouteFinder: the search's ship's seconds for a whole leg.
func _route_leg_seconds(a: String, b: String, miles: float) -> float:
	return _route_probe.leg_seconds(a, b, 0.0, miles, 1.0)


func _work_out_loops(rival: Company, model: Dictionary, start: String, loops3: bool) -> Array:
	var probe := Ship.new("", model.id, start)
	probe.company = rival
	if _route_finder != null and use_native_routes:
		_route_probe = probe
		return _route_finder.work_out(self, _route_context(rival, model, start, probe, _partners(rival, probe, start), loops3))
	var legs := {}
	var partners := []
	for other: String in _partners(rival, probe, start):
		var rate := _loop_rate(rival, probe, [start, other], legs)
		if rate > 0.0:
			partners.append([rate, [start, other]])
	partners.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var loops: Array = partners.slice(0, 16)
	if loops3:
		var near: Array = partners.slice(0, LOOP_PARTNERS).map(func(entry: Array) -> String: return entry[1][1])
		for p: String in near:
			for q: String in near:
				if p != q and probe.can_sail(p, q):
					var rate := _loop_rate(rival, probe, [start, p, q], legs)
					if rate > 0.0:
						loops.append([rate, [start, p, q]])
	loops.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return loops.slice(0, 16)


## The ports (unlocked for it) a ship (`probe`) can sail to and back from a port.
func _partners(rival: Company, probe: Ship, start: String) -> Array:
	var key := "%d|%s|%s|%d" % [rival.get_instance_id(), probe.model_id, start, rival.regions.size()]
	var kept: Dictionary = _partners_kept.get(key, {})
	if not kept.is_empty() and _state.play_time - float(kept.time) < PARTNERS_KEEP_S:
		return kept.ports
	var ports := []
	for port: Dictionary in GameData.ports:
		var other: String = port.id
		if other != start and _state.is_port_unlocked(other) and probe.can_sail(start, other) and probe.can_sail(other, start):
			ports.append(other)
	_partners_kept[key] = {time = _state.play_time, ports = ports}
	return ports

## How many of its cargo ships sail each loop (by _route_key()), worked out once a think.
func _routes_sailed(rival: Company) -> Dictionary:
	var mind: Dictionary = _minds[rival]
	if not mind.has("sailing"):
		var sailing := {}
		for ship in _cargo_ships(rival):
			var key := _route_key(ship.route if ship.pending_route.is_empty() else ship.pending_route)
			sailing[key] = int(sailing.get(key, 0)) + 1
		mind.sailing = sailing
	return mind.sailing


## A route's ports in order of name, as one string: the same for a loop sailed either way round.
static func _route_key(route: Array) -> String:
	var ports := []
	ports.assign(route)
	ports.sort()
	return ",".join(ports)


## What a ship of its earns sailing a route now, in $ a second (-INF without one).
func _route_rate(rival: Company, ship: Ship, route: Array, _but: Ship = null) -> float:
	if route.size() < 2:
		return -INF
	return _loop_rate(rival, ship, route, {})


## $ a second a ship (`probe`, for its model and company) earns round a loop:
## each leg's best cargo (its margin with sale bonuses and the port fee, less
## tolls) less fuel, repairs and the crew's wages, over sailing, port, lock
## and convoy time. -INF if a leg can't be sailed.
func _loop_rate(rival: Company, probe: Ship, loop: Array, legs: Dictionary) -> float:
	var model := probe.model()
	var money := 0.0
	var seconds := 0.0
	for i in loop.size():
		var a: String = loop[i]
		var b: String = loop[(i + 1) % loop.size()]
		var key := a + ">" + b
		if not legs.has(key):
			legs[key] = _leg(rival, probe, a, b)
		var leg: Array = legs[key]
		if leg.is_empty():
			return -INF
		money += float(leg[0])
		seconds += float(leg[1])
	var wages_s := float(_state.crew_wages(model)) / maxf(float(GameData.config.get("crew", {}).get("period_days", 14)) * 86400.0 / maxf(_state.calendar_seconds_per_second(), 0.001), 1.0)
	return money / maxf(seconds, 1.0) - wages_s


## [money, seconds] for one leg (see _loop_rate()), or [] if it can't be sailed.
func _leg(rival: Company, probe: Ship, a: String, b: String) -> Array:
	var model := probe.model()
	var nm := GameData.distance_nm(a, b)
	var sail := probe.leg_seconds(a, b, 0.0, nm, 1.0)
	if not is_finite(sail):
		return []
	var cargo: Array = _state.market.best_cargo(model, a, b, rival, _prices)
	var unit := float(cargo[1])
	if rival.hub_at(b) == null:
		unit *= 1.0 - float(GameData.config.get("port_fee", 0.1))
	var fuel_key := "o" + a
	if not _prices.has(fuel_key):
		_prices[fuel_key] = float(_state.market.fuel_price(a))
	var fuel := float(model.get("fuel_per_s", 0.0)) * sail * float(_prices[fuel_key])
	var repair := float(model.get("wear_pct_per_min", 0.0)) / 60.0 * sail * float(model.get("repair_cost_per_pct", 0.0))
	var seconds := sail + float(model.get("dock_s", 0.0)) + STOP_EXTRA_S + GameData.canal_lock_seconds(a, b) + GameData.convoy_wait_seconds(a, b)
	return [unit * float(model.get("capacity", 0)) - fuel - repair, seconds]


## The most a hard rival borrows to buy ships: a loan step for every 5
## company levels (and one to start).
func _borrow_limit(rival: Company) -> int:
	return int(_state.loan_settings().get("step", 1000000)) * (1 + rival.level() / 5)


## One of its best loops by its difficulty: the best, or one of the best few at random.
func _pick(loops: Array, settings: Dictionary) -> Array:
	return loops[_rng.randi() % mini(int(settings.pick), loops.size())]


## The money it keeps back: half a load for each of its cargo ships (at the
## world price of the most expensive thing it carries), and its difficulty's share of the rest.
func _needs(rival: Company, settings: Dictionary) -> int:
	var mind: Dictionary = _minds.get_or_add(rival, {})
	if not mind.has("loads"):
		var loads := 0.0
		for ship in _cargo_ships(rival):
			var model := ship.model()
			var priciest := 0.0
			for commodity: String in model.get("cargo", []):
				priciest = maxf(priciest, GameData.world_price(commodity))
			loads += priciest * float(model.get("capacity", 0)) * 0.5
		mind.loads = loads
	var loads: float = mind.loads
	return int(loads + maxf(rival.money - loads, 0.0) * float(settings.keep))


# --- Choosing places --------------------------------------------------------------

## The locked region with a port nearest one of its hubs (by sea), or "".
func _nearest_region(rival: Company) -> String:
	var best := ""
	var best_nm := INF
	for port: Dictionary in GameData.ports:
		var region := str(GameData.port_region(port.id).get("id", ""))
		if region.is_empty() or rival.regions.has(region):
			continue
		for hub in rival.hubs:
			var nm := GameData.distance_nm(hub.port_id, port.id)
			if nm < best_nm:
				best_nm = nm
				best = region
	return best


## Where its next hub should go: of the 30 biggest ports it has unlocked (and no
## hub at), the one its most expensive cargo model would earn most from on a 2-port
## loop. Worked out a few ports a think (HUB_PORTS_A_THINK, and within
## FRESH_LOOPS_A_THINK, so the game never
## stalls on it): "" until it's done.
func _best_hub_port(rival: Company) -> String:
	var mind: Dictionary = _minds[rival]
	if not mind.has("hub_search"):
		var model := {}
		for each: Dictionary in GameData.ship_models:
			if not _is_service_model(each) and Progression.unlock_level(each, rival) <= rival.level() and int(each.get("price", 0)) > int(model.get("price", -1)):
				model = each
		if model.is_empty():
			return ""
		var candidates := GameData.ports.filter(func(port: Dictionary) -> bool:
			return _state.is_port_unlocked(port.id) and rival.hub_at(port.id) == null and _state.build_hub_error(port.id).is_empty())
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _state.port_sizes.level(a.id) > _state.port_sizes.level(b.id))
		mind.hub_search = {model = model, ports = candidates.slice(0, 30).map(func(port: Dictionary) -> String: return port.id), best = "", rate = 0.0}
	var search: Dictionary = mind.hub_search
	for i in HUB_PORTS_A_THINK:
		if (search.ports as Array).is_empty():
			mind.erase("hub_search")
			return search.best
		if _fresh_loops >= FRESH_LOOPS_A_THINK:
			return ""  # (Enough worked out this think: the rest next think.)
		var port: String = (search.ports as Array).pop_front()
		var loops := _best_loops(rival, search.model, port, SETTINGS.easy)
		if not loops.is_empty() and float(loops[0][0]) > float(search.rate):
			search.rate = loops[0][0]
			search.best = port
	return ""

## The commodity its ships trade most through a hub's port (loaded or sold
## there, by what they're carrying and where), that the hub has no building for; or "".
func _industry_choice(rival: Company, hub: Hub) -> String:
	var counts := {}
	for ship in _cargo_ships(rival):
		if not ship.route.has(hub.port_id):
			continue
		for commodity: String in ship.model().get("cargo", []):
			if not hub.has_industry(commodity):
				counts[commodity] = float(counts.get(commodity, 0.0)) + (2.0 if ship.cargo_id == commodity else 0.1)
	var best := ""
	for commodity: String in counts:
		if best.is_empty() or float(counts[commodity]) > float(counts[best]):
			best = commodity
	return best


## A home port for a new rival: a recommended start for its company type, of
## its difficulty's kinds, that no company has, in a market region no company
## is in if there is one.
func _pick_home_port(level: String, type_id := "cargo") -> String:
	var taken := {}
	var regions := {}
	for each: Company in _state.all_companies():
		taken[each.home_port] = true
		regions[str(GameData.port_region(each.home_port).get("id", ""))] = true
	var choices := []
	for kind: String in SETTINGS[level].starts:
		for entry: Dictionary in GameData.start_list(kind, type_id):
			if not taken.has(entry.port):
				choices.append(entry.port)
	if choices.is_empty():
		for kind: String in GameData.START_KINDS:
			for entry: Dictionary in GameData.start_list(kind, type_id):
				if not taken.has(entry.port):
					choices.append(entry.port)
	var fresh := choices.filter(func(port: String) -> bool: return not regions.has(str(GameData.port_region(port).get("id", ""))))
	var pool := fresh if not fresh.is_empty() else choices
	return pool[_rng.randi() % pool.size()] if not pool.is_empty() else ""


func _pick_name() -> String:
	var names := {}  # Every company's name, and its first word (so no two rivals start alike).
	for each: Company in _state.all_companies():
		names[each.name.to_lower()] = true
		for first: String in NAME_FIRST:
			if each.name.begins_with(first):
				names[first.to_lower()] = true
	for attempt in 50:
		var first: String = NAME_FIRST[_rng.randi() % NAME_FIRST.size()]
		var candidate := "%s %s" % [first, NAME_SECOND[_rng.randi() % NAME_SECOND.size()]]
		if not names.has(candidate.to_lower()) and not names.has(first.to_lower()):
			return candidate
	return "Rival %d" % (_state.all_companies().size() + 1)


## A company color no company has (any, if they're all taken).
func _pick_color() -> String:
	var used := {}
	for each: Company in _state.all_companies():
		used[each.color] = true
	var free := []
	for entry: Array in GameData.config.get("company_colors", []):
		if not used.has(entry[0]) and not entry[0] in ["black", "white", "gray"]:
			free.append(entry[0])
	return free[_rng.randi() % free.size()] if not free.is_empty() else "gray"


# --- Small helpers ----------------------------------------------------------------

## Its cargo ships (not tugs, recovery boats or icebreakers), worked out once
## a think (and again after it buys or sells one: see _forget_fleet()).
func _cargo_ships(rival: Company) -> Array[Ship]:
	var mind: Dictionary = _minds.get_or_add(rival, {})
	if not mind.has("cargo"):
		var out: Array[Ship] = []
		for ship: Ship in _state.fleet(rival):
			if not ship.is_service():
				out.append(ship)
		mind.cargo = out
	return mind.cargo


## How many of each model it owns (model id -> count), worked out once a think.
func _model_counts(rival: Company) -> Dictionary:
	var mind: Dictionary = _minds.get_or_add(rival, {})
	if not mind.has("counts"):
		var counts := {}
		for ship: Ship in _state.fleet(rival):
			counts[ship.model_id] = int(counts.get(ship.model_id, 0)) + 1
		mind.counts = counts
	return mind.counts


## After it buys or sells a ship: its fleet (and what it keeps back for it) changed.
func _forget_fleet(rival: Company) -> void:
	_ships_changed = true
	var mind: Dictionary = _minds.get_or_add(rival, {})
	for key: String in ["cargo", "counts", "loads", "sailing"]:
		mind.erase(key)


static func _is_service_model(model: Dictionary) -> bool:
	return model.get("recovery", false) or model.get("tug", false) or not str(model.get("icebreaker", "")).is_empty() or model.has("fishing") or model.has("cruise")


## The cheapest ship model passing a test, or "".
func _cheapest(test: Callable) -> String:
	var best := ""
	var best_price := 0
	for model: Dictionary in GameData.ship_models:
		if test.call(model) and (best.is_empty() or int(model.get("price", 0)) < best_price):
			best = model.id
			best_price = int(model.get("price", 0))
	return best


# --- Cruises ------------------------------------------------------------------------

## A rival with the Cruises type runs a simple cruise line: every cruise ship
## without an itinerary gets one from its best hub (up to 3 of the most
## appealing ports within reach, sailed nearest first), recommended prices
## and seasonal adjustments; and it buys the biggest cruise model it can
## afford twice over (at most one more for every 10 company levels), fitting
## its deck slots with the amenities that add most.
func _run_cruises(rival: Company) -> Array:
	var news := []
	if not rival.has_type("cruises") or rival.all_types():
		return news
	var cruises: Cruises = _state.cruises
	var fleet: Array = _state.fleet(rival).filter(func(ship: Ship) -> bool: return ship.is_cruise())
	for ship: Ship in fleet:
		if ship.route.size() < 2 and ship.is_docked() and ship.pending_route.is_empty():
			var route := _cruise_itinerary(rival, ship)
			if route.size() >= 2:
				var typed: Array[String] = []
				typed.assign(route)
				_state.assign_route(ship, typed)
				cruises.use_recommended(ship)
				var monthly := []
				for m in 12:
					monthly.append(cruises.recommended_monthly(ship, m))
				ship.cruise.monthly = monthly
	if fleet.size() >= 1 + rival.level() / 10:
		return news
	var best := {}
	for model: Dictionary in GameData.ship_models:
		if not model.has("cruise") or not _state.buy_error(model.id).is_empty():
			continue
		if rival.money < _state.ship_price(model.id) * 2:
			continue
		if best.is_empty() or int(model.get("price", 0)) > int(best.get("price", 0)):
			best = model
	if best.is_empty():
		return news
	var port := ""
	for hub in rival.hubs:
		if _state.can_launch_at(best.id, hub.port_id):
			port = hub.port_id
			break
	if port.is_empty():
		return news
	var ship: Ship = _state.buy_ship(best.id, _state.suggest_ship_name(), port)
	_forget_fleet(rival)
	if ship == null:
		return news
	_state.set_auto_recover(ship, true)
	var picks := Cruises.amenities_for(best)
	picks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.points) + float(a.spend) > float(b.points) + float(b.spend))
	var setup := {cabins = ship.cruise.cabins, amenities = picks.slice(0, int(best.cruise.get("deck_slots", 2))).map(func(each: Dictionary) -> String: return str(each.id)), looks = ship.cruise.looks}
	while not (setup.amenities as Array).is_empty() and rival.money < int(cruises.refit_quote(ship, setup).cost) * 2:
		(setup.amenities as Array).pop_back()
	if not (setup.amenities as Array).is_empty() and cruises.refit_error(ship, setup).is_empty():
		cruises.refit(ship, setup)
	var route := _cruise_itinerary(rival, ship)
	if route.size() >= 2:
		var typed: Array[String] = []
		typed.assign(route)
		_state.assign_route(ship, typed)
		cruises.use_recommended(ship)
	news.append("launched the cruise ship %s (%s)" % [ship.name, best.get("name", "")])
	return news


## A rival's itinerary for a cruise ship: its home the hub it's at (or its HQ),
## then up to 3 of the most appealing ports it can reach and back, nearest first.
func _cruise_itinerary(rival: Company, ship: Ship) -> Array:
	var home := ship.docked_at if rival.hub_at(ship.docked_at) != null else rival.home_port
	var expedition := Cruises.is_expedition(ship)
	var scored := []
	for port: Dictionary in GameData.ports:
		var id: String = port.id
		if id == home or not _state.is_port_unlocked(id) or not ship.fits_port(id) or not ship.can_sail(home, id) or not ship.can_sail(id, home):
			continue
		var miles := GameData.distance_nm(home, id)
		if miles > float(ship.model().get("range_nm", 1000)) * 0.8:
			continue
		var near := Cruises.attractions(id)
		var score := 1.0 + 2.0 * (near.wonders as Array).size() + (3.0 if near.polar and expedition else 0.0) - miles / 1500.0
		scored.append([score, id])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var stops: Array = scored.slice(0, 3).map(func(entry: Array) -> String: return entry[1])
	var route := [home]
	var here := home
	while not stops.is_empty():
		stops.sort_custom(func(a: String, b: String) -> bool: return GameData.distance_nm(here, a) < GameData.distance_nm(here, b))
		here = stops.pop_front()
		if ship.can_sail(route[-1], here):
			route.append(here)
	return route
