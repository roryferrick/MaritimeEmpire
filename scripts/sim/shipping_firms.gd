# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name ShippingFirms
extends RefCounted
## The world's AI shipping companies, simulated on paper (DESIGN_LIVING_WORLD.md
## M1): about FIRMS firms based in the real shipowning nations, with fleets of
## the game's models sized so that between them they can carry the world's
## surplus from zone to zone (WorldEconomy). Every calendar day the dispatch
## matches zones long of a good (days of cover over the normal) with zones
## short of it, where the price gap pays the freight, and sends voyages: each
## {firm, model, good, qty, from, to (ports), start, arrive, free (play time)}.
## A voyage takes its goods from the source zone's stockpile as it sails and
## delivers them on arrival; the capacity it uses is free again after a half
## trip home (a backhaul found half the time). The firms earn the margin less
## the freight. Voyages at sea are what the map draws as ambient traffic.
##
## The matching is spread over frames (a good a call) so no frame stalls; a
## day's dispatch finishes long before the next day.

## How many firms, and where they're based (ISO3 -> share of the world fleet,
## roughly the real 2016 shipowning nations); the rest are small operators
## spread over every country with a port.
const FIRMS := 200
const HOMES := {"GRC": 0.16, "JPN": 0.13, "CHN": 0.11, "DEU": 0.07, "SGP": 0.05, "HKG": 0.05, "KOR": 0.04, "NOR": 0.04, "USA": 0.04,
	"GBR": 0.03, "DNK": 0.03, "TWN": 0.03, "ITA": 0.02, "TUR": 0.02, "IND": 0.02, "BEL": 0.015, "NLD": 0.015, "RUS": 0.015, "ARE": 0.01,
	"SAU": 0.01, "IDN": 0.01, "MYS": 0.01, "BRA": 0.01, "CAN": 0.01, "FRA": 0.01, "CHE": 0.01, "IRN": 0.01, "VNM": 0.005}
const TAIL_SHARE := 0.1  # Of the fleet, in the small operators.
## Fleet sizing: the world's daily surplus per line, carried over a typical
## voyage of MEAN_VOYAGE_NM and back (BACKHAUL of the way back empty), with
## SLACK spare; a firm's fleet is its share of each line in the line's models,
## big firms leaning to big ships.
const MEAN_VOYAGE_NM := 5000.0
const BACKHAUL := 0.5
const SLACK := 2.5
## Dispatch: a zone exports a good above EXPORT_COVER days of cover and orders
## more when what it has and what's coming fall under STOCK_DAYS plus the lead
## time; a voyage sails only where the price gap beats the freight
## (HANDLING of the base price plus the base price per FREIGHT_NM sailed) by
## MARGIN; at most LOTS voyages a good a day; a lot is at most the line's
## biggest model's hold.
const EXPORT_COVER := 40.0
## What a zone keeps on the quay (days of use), ordered a lead time ahead and FILL_DAYS more at a time.
const STOCK_DAYS := 30.0
const FILL_DAYS := 15.0
## Importers looked at a call (frame).
const IMPORTERS_PER_CALL := 12
## Days between dispatches (voyages take weeks of the calendar: no need to look every day).
const DISPATCH_DAYS := 8
const HANDLING := 0.03
const FREIGHT_NM := 40000.0
const MARGIN := 0.02
const LOTS := 60
## A lot smaller than MIN_LOT_SHARE of the line's smallest ship isn't worth a voyage.
const MIN_LOT_SHARE := 0.5
## A good to keep dispatch figures for (probes): {exporters, importers, sent, qty, no_gain, small, no_room}.
var debug_good := ""
var debug := {}
var _debug_now := false
## Days a calendar day lasts in play seconds come from the calendar; a voyage's
## speed is its model's.

var _state: Node  # GameState
## [{id, name, country, home (port), size (share of the world fleet), fleet: {model id: count}, money, carried (units all time)}].
var firms: Array = []
## Capacity per line (hold units) and what's busy; voyages at sea.
var capacity := {}
var voyages: Array = []
## The dispatch's progress through the day: the good it's up to (-1: done) and the day.
var _good_cursor := -1
var _dispatch_day := -1
## Zone to zone sailing distance (main ports), zones x zones; INF with no way.
var _zone_nm := PackedFloat64Array()
var _models := {}  # line -> models, biggest first.
var seed := 0


func _init(state: Node) -> void:
	_state = state


# --- Making the firms ---------------------------------------------------------------

func generate(world: WorldEconomy, new_seed: int) -> void:
	seed = new_seed
	firms.clear()
	voyages.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed + 1
	_build_models()
	_build_distances(world)
	capacity = _world_capacity(world)
	# Firm sizes: the named nations' shares split among their firms (a few big,
	# many small: a power law), the tail among every other country with a port.
	var taken := {}
	var ports_by_country := {}
	for port: Dictionary in GameData.ports:
		var country := world.country_of_port(port.id)
		if not country.is_empty():
			ports_by_country.get_or_add(country, []).append(port.id)
	var named := 0
	for country: String in HOMES:
		if not ports_by_country.has(country):
			continue
		var count := maxi(roundi(FIRMS * (1.0 - TAIL_SHARE) * float(HOMES[country]) / _named_total()), 1)
		var weights := []
		var total := 0.0
		for i in count:
			var w := pow(float(i + 1), -1.1)
			weights.append(w)
			total += w
		for i in count:
			var ports: Array = ports_by_country[country]
			var home: String = ports[rng.randi() % mini(ports.size(), 3)]  # (One of its biggest ports.)
			firms.append({id = firms.size(), name = CompanyNames.shipping(country, GameData.port_name(home), rng, taken), country = country, home = home,
				size = float(HOMES[country]) * (1.0 - TAIL_SHARE) * float(weights[i]) / total, fleet = {}, money = 0.0, carried = 0.0})
			named += 1
	var others := ports_by_country.keys().filter(func(country: String) -> bool: return not HOMES.has(country))
	var tail := maxi(FIRMS - named, 0)
	for i in tail:
		var country: String = others[rng.randi() % others.size()]
		var ports: Array = ports_by_country[country]
		var home: String = ports[rng.randi() % ports.size()]
		firms.append({id = firms.size(), name = CompanyNames.shipping(country, GameData.port_name(home), rng, taken), country = country, home = home,
			size = TAIL_SHARE / tail, fleet = {}, money = 0.0, carried = 0.0})
	_give_fleets(rng)


func _named_total() -> float:
	var total := 0.0
	for country: String in HOMES:
		total += float(HOMES[country])
	return total


## The models of each line, biggest hold first.
func _build_models() -> void:
	_models.clear()
	for model: Dictionary in GameData.ship_models:
		if (model.get("cargo", []) as Array).is_empty() or model.get("coming_soon", false):
			continue
		_models.get_or_add(str(model.category), []).append(model)
	for line: String in _models:
		(_models[line] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.capacity) > int(b.capacity))


func _build_distances(world: WorldEconomy) -> void:
	var n := world.zones.size()
	_zone_nm.resize(n * n)
	for a in n:
		for b in n:
			_zone_nm[a * n + b] = 0.0 if a == b else GameData.distance_nm(world.zones[a].main, world.zones[b].main)


## The hold units each line needs at sea to carry the world's daily surplus of
## its goods over MEAN_VOYAGE_NM and back, with SLACK.
func _world_capacity(world: WorldEconomy) -> Dictionary:
	var g_count := world.goods.size()
	var daily := {}  # line -> hold units a day
	for g in g_count:
		var line := WorldEconomy.line_of(world.goods[g])
		if line.is_empty():
			continue
		var surplus := 0.0
		for z in world.zones.size():
			var i := z * g_count + g
			surplus += maxf(world.capacity[i] - world.need_base[i] - world.user_base[i], 0.0)
		daily[line] = float(daily.get(line, 0.0)) + surplus * GameData.hold_of(world.goods[g])
	var out := {}
	for line: String in daily:
		var speed := _mean_speed(line)
		var days := MEAN_VOYAGE_NM / maxf(speed * _nm_per_day_per_speed(), 1.0) * (1.0 + BACKHAUL)
		out[line] = float(daily[line]) * days * SLACK
	return out


## A line's models' mean speed (nm a play second).
func _mean_speed(line: String) -> float:
	var total := 0.0
	var models: Array = _models.get(line, [])
	for model: Dictionary in models:
		total += float(model.get("speed_nm_per_s", 5.0))
	return total / maxf(models.size(), 1.0)


## Play seconds in a calendar day: a ship at speed s sails s x this nm a day.
func _nm_per_day_per_speed() -> float:
	return 86400.0 / _state.calendar_seconds_per_second()


## Each firm's fleet: its share of each line's capacity in that line's models,
## the biggest firms in the biggest ships.
func _give_fleets(rng: RandomNumberGenerator) -> void:
	for firm: Dictionary in firms:
		var big := clampf(float(firm.size) * FIRMS / 4.0, 0.0, 1.0)  # (0 for the smallest, 1 for a giant.)
		for line: String in capacity:
			var units := float(capacity[line]) * float(firm.size)
			var models: Array = _models[line]
			var fleet: Dictionary = firm.fleet
			while units > 0.0 and not models.is_empty():
				# A tier by the firm's size with some spread; the biggest ship that fits the units left.
				var pick := clampi(roundi(lerpf(2.0, 0.0, big) + rng.randfn(0.0, 0.7)), 0, models.size() - 1)  # (Tiers 3 to 5: the world's fleet is big ships.)
				while pick < models.size() - 1 and float(models[pick].capacity) > units * 1.5:
					pick += 1
				var model: Dictionary = models[pick]
				fleet[model.id] = int(fleet.get(model.id, 0)) + 1
				units -= float(model.capacity)


# --- Each day -------------------------------------------------------------------------

## Advances the voyages (arrivals deliver) and, a good a call, the day's dispatch.
func step(_delta: float) -> void:
	var world: WorldEconomy = _state.world
	if firms.is_empty() or world.zones.is_empty():
		return
	_arrive(world)
	if _good_cursor < 0 and world.day - _dispatch_day >= DISPATCH_DAYS:
		_dispatch_day = world.day
		_good_cursor = 0
	if _good_cursor >= 0:
		if _job.is_empty():
			_begin_good(world, _good_cursor)
		_work(world, IMPORTERS_PER_CALL)
		if _job.is_empty():
			_good_cursor += 1
			if _good_cursor >= world.goods.size():
				_good_cursor = -1
				_flush_batch()


## A whole day's dispatch at once (tests and probes).
func dispatch_day() -> void:
	var world: WorldEconomy = _state.world
	_dispatch_day = world.day
	for g in world.goods.size():
		_begin_good(world, g)
		_work(world, 1 << 30)
	_good_cursor = -1
	_flush_batch()


## The dispatch's gathered lots sail: each batch a voyage of the line's biggest
## ships (as many as its hold units take), at their speed.
func _flush_batch() -> void:
	var day_s: float = _state.calendar_seconds_per_second()
	var now: float = _state.play_time
	for key: String in _batch:
		var lot_entry: Dictionary = _batch[key]
		var model: Dictionary = _models[lot_entry.line][0]
		var ships := maxi(ceili(float(lot_entry.hold) / float(model.capacity)), 1)
		var days := float(lot_entry.nm) / maxf(float(model.get("speed_nm_per_s", 5.0)) * _nm_per_day_per_speed(), 1.0)
		_insert_sorted(voyages, {firm = lot_entry.firm, model = model.id, ships = ships, line = lot_entry.line, goods = lot_entry.goods, hold = lot_entry.hold,
			from = lot_entry.from, to = lot_entry.to, start = now, arrive = now + days * 86400.0 / day_s,
			free = now + days * (1.0 + BACKHAUL) * 86400.0 / day_s, cost = lot_entry.cost}, "arrive")
	_batch.clear()


## Voyages that have arrived deliver their goods and the firm is paid; ships
## home again free their capacity. `voyages` is kept in order of arrival and
## `_returning` ([free time, line, hold]) in order of coming free, so only the
## front of each is looked at.
func _arrive(world: WorldEconomy) -> void:
	var now: float = _state.play_time
	while not voyages.is_empty() and float(voyages[0].arrive) <= now:
		var v: Dictionary = voyages.pop_front()
		var z := world.zone_of_port(v.to)
		var value := 0.0
		var units := 0.0
		for good: String in v.goods:
			var g := world.good_index(good)
			if z < 0 or g < 0:
				continue
			var qty := float(v.goods[good])
			value += qty * world.sell_price(v.to, good)
			units += qty
			world.add_inbound(z, g, -qty)
			world.deliver(z, g, qty, qty * world.sell_price(v.to, good))
		var firm: Dictionary = firms[int(v.firm)]
		firm.money = float(firm.money) + value - float(v.cost)
		firm.carried = float(firm.carried) + units
		_insert_sorted(_returning, [float(v.free), v.line, float(v.hold)], 0)
	while not _returning.is_empty() and float(_returning[0][0]) <= now:
		var home: Array = _returning.pop_front()
		_busy[home[1]] = float(_busy.get(home[1], 0.0)) - float(home[2])


## Puts an entry into a list kept in order of its `key` field (a Dictionary's
## key, or an Array's index), after any equal.
static func _insert_sorted(list: Array, entry: Variant, key: Variant) -> void:
	var value := float(entry[key])
	var lo := 0
	var hi := list.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(list[mid][key]) <= value:
			lo = mid + 1
		else:
			hi = mid
	list.insert(lo, entry)


## Hold units of a line's capacity out on voyages now (kept as voyages come and go).
func busy(line: String) -> float:
	return float(_busy.get(line, 0.0))
var _busy := {}
var _returning: Array = []


func _count_busy() -> void:
	_busy.clear()
	for v: Dictionary in voyages:
		_busy[v.line] = float(_busy.get(v.line, 0.0)) + float(v.hold)
	for home: Array in _returning:
		_busy[home[1]] = float(_busy.get(home[1], 0.0)) + float(home[2])


## Days a line's typical voyage takes on the calendar (MEAN_VOYAGE_NM at the
## line's mean speed): how far ahead a zone orders.
func lead_days(line: String) -> float:
	return MEAN_VOYAGE_NM / maxf(_mean_speed(line) * _nm_per_day_per_speed(), 1.0)


## A dispatch's lots between the same two zones on one line, gathered into one
## voyage of as many ships as they take ("from|to|line" -> {goods, hold, cost, from, to, line, nm}).
var _batch := {}


## The good being dispatched (a few importers a call, so no frame stalls):
## {g, good, line, n, hold, base, lot, small_lot, models, prices, exporters, importers, index, free, sent}.
var _job := {}


## Sizes up a good's day: the zones long of it (stock on the quay over
## EXPORT_COVER days of use or output), the zones short of it (stock and cargo
## on its way under STOCK_DAYS plus the line's lead time of what they use;
## filled FILL_DAYS further so one voyage lasts; a market too small for that to
## be worth a ship gets the line's smallest ship's worth instead), and the
## prices; nothing to do leaves _job empty.
func _begin_good(world: WorldEconomy, g: int) -> void:
	_job = {}
	var good := world.goods[g]
	var line := WorldEconomy.line_of(good)
	if line.is_empty() or not capacity.has(line):
		return
	var g_count := world.goods.size()
	var n := world.zones.size()
	var hold := GameData.hold_of(good)
	var models: Array = _models[line]
	var small_lot := float(models[-1].capacity) / hold
	var nm_a_day := _mean_speed(line) * _nm_per_day_per_speed()
	var exporters := []  # [zone, surplus units]
	var importers := []  # [zone, units wanted]
	var prices := PackedFloat64Array()
	prices.resize(n)
	var short := []  # [zone, local use, held]
	for z in n:
		var i := z * g_count + g
		prices[z] = world.price[i]
		var use := world.use_for_price(i)
		if use <= 0.0:
			continue
		var local := world.need_base[i] + world.user_base[i]
		if world.stock[i] > EXPORT_COVER * use:
			exporters.append([z, world.stock[i] - EXPORT_COVER * use])
		elif local > 0.0:
			short.append([z, local, world.stock[i] + world.inbound[i]])
	# A zone orders a lead time ahead: the voyage from its nearest source.
	for each: Array in short:
		var z: int = each[0]
		var nearest := INF
		for exporter: Array in exporters:
			nearest = minf(nearest, _zone_nm[int(exporter[0]) * n + z])
		if nearest == INF:
			continue
		var lead := nearest / maxf(nm_a_day, 1.0) + DISPATCH_DAYS
		var local: float = each[1]
		var held: float = each[2]
		if held < (STOCK_DAYS + lead) * local:
			importers.append([z, maxf((STOCK_DAYS + lead + FILL_DAYS) * local - held, small_lot - held)])
	_debug_now = good == debug_good
	if _debug_now:
		debug.exporters = int(debug.get("exporters", 0)) + exporters.size()
		debug.importers = int(debug.get("importers", 0)) + importers.size()
		debug.free = float(capacity[line]) - busy(line)
		debug.days = int(debug.get("days", 0)) + 1
	if exporters.is_empty() or importers.is_empty():
		return
	importers.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	_job = {g = g, good = good, line = line, n = n, hold = hold, base = float(GameData.commodity(good).get("base", 1.0)),
		lot = float(models[0].capacity) / hold, small_lot = small_lot, models = models, prices = prices,
		exporters = exporters, importers = importers, index = 0, free = float(capacity[line]) - busy(line), sent = 0}


## Works through up to `count` of the job's importers, each filled from its
## best sources in turn (a voyage of as many ships as it takes); the job is
## done (emptied) when they're all seen, the line's ships are all out or LOTS
## voyages have gone.
func _work(world: WorldEconomy, count: int) -> void:
	if _job.is_empty():
		return
	var g: int = _job.g
	var good: String = _job.good
	var line: String = _job.line
	var n: int = _job.n
	var hold: float = _job.hold
	var base: float = _job.base
	var lot: float = _job.lot
	var small_lot: float = _job.small_lot
	var models: Array = _job.models
	var prices: PackedFloat64Array = _job.prices
	var exporters: Array = _job.exporters
	var importers: Array = _job.importers
	var free: float = _job.free
	var sent: int = _job.sent
	var end: int = mini(int(_job.index) + count, importers.size())
	for k in range(int(_job.index), end):
		if sent >= LOTS or free <= 0.0:
			_note("no_room")
			end = importers.size()
			break
		var importer: Array = importers[k]
		var to: int = importer[0]
		var price_to := prices[to]
		var wanted := float(importer[1])
		if _debug_now:
			_log("%s wants %.0f at x%.2f (free %.0f, sent %d)" % [world.zones[to].id, wanted, price_to / base, free, sent])
		for attempt in 4:
			if wanted <= 0.0 or free <= 0.0 or sent >= LOTS:
				break
			var best := -1
			var best_rate := 0.0
			for e in exporters.size():
				var from: int = exporters[e][0]
				if float(exporters[e][1]) <= 0.0:
					continue
				var nm := _zone_nm[from * n + to]
				if nm == INF:
					continue
				var freight := base * (HANDLING + nm / FREIGHT_NM)
				var gain := price_to - prices[from] - freight - base * MARGIN
				var rate := gain / (nm / MEAN_VOYAGE_NM + 0.5)  # (Per ship-day: a near source beats a far one at the same gain.)
				if gain > 0.0 and rate > best_rate:
					best_rate = rate
					best = e
			if best < 0:
				_note("no_gain")
				break
			var from: int = exporters[best][0]
			var qty := minf(minf(wanted, float(exporters[best][1])), free / hold)
			if qty < small_lot * MIN_LOT_SHARE:  # (Not worth a ship.)
				if float(exporters[best][1]) < wanted:
					exporters[best][1] = 0.0  # (This source is the short one: the next.)
					_note("source_short")
					continue
				_note("small")
				break
			var nm := _zone_nm[from * n + to]
			var firm := _firm_for(world, from, line)
			var got := world.take(from, g, qty, qty * prices[from])
			if got <= 0.0:
				exporters[best][1] = 0.0  # (Nothing there after all: the next source.)
				_note("empty")
				continue
			var cost := got * prices[from] + got * base * (HANDLING + nm / FREIGHT_NM)
			var key := "%d|%d|%s" % [from, to, line]
			var lot_entry: Dictionary = _batch.get_or_add(key, {goods = {}, hold = 0.0, cost = 0.0, line = line, nm = nm, from = world.zones[from].main, to = world.zones[to].main, firm = firm})
			lot_entry.goods[good] = float(lot_entry.goods.get(good, 0.0)) + got
			lot_entry.hold = float(lot_entry.hold) + got * hold
			lot_entry.cost = float(lot_entry.cost) + cost
			world.add_inbound(to, g, got)
			_busy[line] = float(_busy.get(line, 0.0)) + got * hold
			if _debug_now:
				debug.sent = int(debug.get("sent", 0)) + 1
				debug.qty = float(debug.get("qty", 0.0)) + got
				_log("  %s -> %s: %.0f %s" % [world.zones[from].id, world.zones[to].id, got, good])
			exporters[best][1] = float(exporters[best][1]) - got
			wanted -= got
			free -= got * hold
			sent += 1
	_job.index = end
	_job.free = free
	_job.sent = sent
	if end >= importers.size():
		_job = {}


func _note(what: String) -> void:
	if not debug_good.is_empty() and _debug_now:
		debug[what] = int(debug.get(what, 0)) + 1
		_log("  " + what)


## A line of the debug log (probes): kept for debug_good from debug_from_day on.
var debug_from_day := 0
func _log(text: String) -> void:
	if _debug_now and _dispatch_day >= debug_from_day:
		(debug.get_or_add("log", []) as Array).append("d%d %s" % [_dispatch_day, text])


## The smallest model of a line whose hold takes the lot (else the biggest).
func _model_for(models: Array, hold_units: float) -> Dictionary:
	for i in range(models.size() - 1, -1, -1):
		if float(models[i].capacity) >= hold_units:
			return models[i]
	return models[0]


## A firm for a voyage: by fleet share, firms of the source's country favoured
## (each country's running totals worked out once).
func _firm_for(world: WorldEconomy, from: int, _line: String) -> int:
	var country: String = world.zones[from].country
	var sums: PackedFloat64Array = _firm_sums.get(country, PackedFloat64Array())
	if sums.is_empty():
		var total := 0.0
		for firm: Dictionary in firms:
			total += float(firm.size) * (3.0 if firm.country == country else 1.0)
			sums.append(total)
		_firm_sums[country] = sums
	var pick := randf() * sums[-1]
	return mini(sums.bsearch(pick), firms.size() - 1)
var _firm_sums := {}


# --- Saving ----------------------------------------------------------------------------

## What's saved of a voyage, in this order (its line and hold units follow from
## its good; times and amounts whole numbers): there are thousands.
const VOYAGE_KEYS := ["firm", "model", "ships", "goods", "from", "to", "start", "arrive", "free", "cost"]


func to_dict() -> Dictionary:
	var rows := []
	for v: Dictionary in voyages:
		var goods := {}
		for good: String in v.goods:
			goods[good] = roundi(float(v.goods[good]))
		rows.append([v.firm, v.model, v.ships, goods, v.from, v.to, roundi(float(v.start)), roundi(float(v.arrive)), roundi(float(v.free)), roundi(float(v.cost))])
	return {seed = seed, dispatch_day = _dispatch_day, voyages = rows,
		returning = _returning.map(func(home: Array) -> Array: return [roundi(float(home[0])), home[1], roundi(float(home[2]))]),
		money = firms.map(func(firm: Dictionary) -> Array: return [snappedf(float(firm.money), 1.0), snappedf(float(firm.carried), 1.0)])}


func from_dict(data: Dictionary, world: WorldEconomy) -> void:
	if data.is_empty():
		return
	generate(world, int(data.get("seed", 0)))
	voyages = []
	for row: Array in data.get("voyages", []):
		var v := {}
		for k in mini(row.size(), VOYAGE_KEYS.size()):
			v[VOYAGE_KEYS[k]] = row[k]
		v.hold = 0.0
		for good: String in v.goods:
			v.line = WorldEconomy.line_of(good)
			v.hold = float(v.hold) + float(v.goods[good]) * GameData.hold_of(good)
		voyages.append(v)
	_returning = data.get("returning", [])
	_count_busy()
	_dispatch_day = int(data.get("dispatch_day", -1))
	var money: Array = data.get("money", [])
	for i in mini(money.size(), firms.size()):
		firms[i].money = float(money[i][0])
		firms[i].carried = float(money[i][1])
