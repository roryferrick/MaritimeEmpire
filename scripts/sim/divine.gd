# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Divine
extends RefCounted
## Divine Actions: a game mode chosen when a company is founded (GameState.divine
## on), unrealistic and unfair by design. Two halves:
## - Powers a company buys (POWERS; the Divine panel on the World map, or a
##   rival AI: RivalAI._divine()), each with a price (most scaling with the
##   company's level), a cooldown, and a target picked on the map: a point (the
##   three storms, Calm seas), a port (Plague of gulls, Deluge, Sea change,
##   Lightning strike), a ship (the Kraken) or nothing (Fair winds). Storms are
##   real storms (Weather.spawn_divine()): they slow, wear, close ports and
##   blow out like the weather's own, named for their sender. At most
##   MAX_STORMS_ALIVE of a company's storms are out at once, and Wrath, the
##   super-storm, once a calendar year.
## - Blessings and omens that act by themselves (speed_factor(), stop_factor(),
##   price_factor()...): birds following a ship speed it up (BLESS_PER_BIRD a
##   bird, an albatross two, up to BLESS_CAP); birds at a port speed its
##   loading and better its prices for ships there (PORT_BIRDS_FULL birds for
##   the most); frigatebirds following a ship steal a little of its sale;
##   whales and dolphins near a ship shield it from a storm's wear; sharks near
##   a lost ship hurry its rescuers; a port's lamps turn ships round faster by
##   night; cherry blossom (April, Japan) doubles delivery XP; the first snow
##   (1 to 7 December, ports north of 50) slows northern stops; and a comet
##   one day a year lifts everyone's sale prices.
## Everything here is worked out by the host (GameState) and saved with the game;
## joined players see the effects as they come in the host's updates.

## Each power: name, base price, whether it scales with level (price()),
## target (point, port, ship, none), cooldown in game weeks, the effect's
## length in game weeks (for those that last), yearly (once a calendar year),
## and what it does.
const POWERS := {
	squall = {name = "Squall", base = 25000000, scaled = true, target = "point", cooldown_weeks = 0.2, blurb = "A gale, two days long, where you point: ships slow and wear in it."},
	tempest = {name = "Tempest", base = 200000000, scaled = true, target = "point", cooldown_weeks = 0.6, blurb = "A hurricane-class storm with an eye, a week long, drifting from where you point: it closes ports under its core."},
	wrath = {name = "Wrath", base = 1000000000, scaled = false, target = "point", cooldown_weeks = 0.0, yearly = true, blurb = "A super-storm beyond anything the weather makes: twice the size and power of the harshest typhoon, two weeks long, closing every port it crosses. Once a year."},
	fair_winds = {name = "Fair winds", base = 100000000, scaled = true, target = "none", cooldown_weeks = 1.0, effect_weeks = 1.0, blurb = "Your whole fleet sails half as fast again for a week."},
	calm_seas = {name = "Calm seas", base = 50000000, scaled = true, target = "point", cooldown_weeks = 1.0, blurb = "Every storm within 500 nm of where you point blows out at once."},
	plague = {name = "Plague of gulls", base = 30000000, scaled = true, target = "port", cooldown_weeks = 1.0, effect_weeks = 1.0, blurb = "A port is mobbed by gulls for a week: every other company's ships there take twice as long to turn round."},
	kraken = {name = "The Kraken", base = 150000000, scaled = true, target = "ship", cooldown_weeks = 1.0, blurb = "A rival's ship at sea is taken: lost where it is, for a tug or recovery boat to fetch."},
	deluge = {name = "Deluge", base = 80000000, scaled = true, target = "port", cooldown_weeks = 1.0, effect_weeks = 1.0, blurb = "A port's market is flooded for a week: its prices halve, for everyone."},
	sea_change = {name = "Sea change", base = 60000000, scaled = true, target = "port", cooldown_weeks = 1.0, effect_weeks = 4.0, blurb = "A great flock settles on a port of your choice for a month: it counts as 40 more birds blessing it."},
	lightning = {name = "Lightning strike", base = 120000000, scaled = true, target = "port", cooldown_weeks = 1.0, blurb = "Lightning strikes a rival's hub at a port: it drops a level."},
}
## The powers in the order the panel lists them.
const ORDER := ["squall", "tempest", "wrath", "fair_winds", "calm_seas", "plague", "deluge", "sea_change", "kraken", "lightning"]
## The three storms: kind (tropical: by where it's called down), radius (nm),
## days of life, and power (its strength times this; over 1 is beyond nature).
const STORM_TIERS := {
	squall = {tropical = false, radius_nm = 180.0, days = 2.0, power = 1.0},
	tempest = {tropical = true, radius_nm = 300.0, days = 7.0, power = 1.0},
	wrath = {tropical = true, radius_nm = 600.0, days = 14.0, power = 2.0},
}
const MAX_STORMS_ALIVE := 3
const CALM_SEAS_NM := 500.0
## The blessings (see the note above).
const BLESS_PER_BIRD := 0.02
const BLESS_CAP := 0.5
const PORT_BIRDS_FULL := 80.0
const PORT_PRICE_SHARE := 0.2
const FRIGATE_STEAL := 0.02
const FRIGATE_STEAL_CAP := 0.1
const ESCORT_NM := 50.0
const SHARK_NM := 100.0
const SHARK_HURRY := 1.5
const LAMPS_STOP := 0.8
const SNOW_STOP := 1.3
const SNOW_LAT := 50.0
const COMET_SELL := 1.1
const SEA_CHANGE_BIRDS := 40
const FAIR_WINDS_SPEED := 1.5
const PLAGUE_STOP := 2.0
const DELUGE_PRICES := 0.5
## How long (s of play) the visual effects of the Kraken and a lightning strike last.
const KRAKEN_SHOW_S := 20.0
const LIGHTNING_SHOW_S := 4.0
## How often (s of play) a ship's blessings and escorts are looked at again,
## and a port's birds counted again.
const REFRESH_S := 5.0
const LEDGER_KEPT := 12

## Whether this game has Divine Actions (chosen when the company was founded).
var on := false
## The effects running: {kind, company (name; "" for none), port, ship (id),
## until (play time), since}.
var effects: Array[Dictionary] = []
## Company name -> {power: play time it's ready again}.
var cooldowns := {}
## Company name -> the calendar year it last called down Wrath.
var wrath_years := {}
## The last few acts, newest last: {who, power, where, at (play time)}.
var ledger: Array[Dictionary] = []

var _state: Node  # GameState
var _factors := {}  # Ship -> [until, speed factor, storm wear cancelled, hurrying]
var _port_birds := {}  # Port id -> [until, birds]
var _pods := []  # [(lon, lat), shark] each, as of _pods_until - REFRESH_S.
var _pods_until := -INF
var _comet_day := -1  # The last calendar day the comet was told of.
var _comet_cache := [-1, false]  # [calendar day, whether the comet is up]


func _init(state: Node) -> void:
	_state = state


func reset() -> void:
	effects.clear()
	cooldowns.clear()
	wrath_years.clear()
	ledger.clear()
	_factors.clear()
	_port_birds.clear()
	_pods.clear()
	_pods_until = -INF
	_comet_day = -1


# --- Powers ---------------------------------------------------------------------

## Seconds of play in a game week.
func week_s() -> float:
	return 7.0 * 86400.0 / float(_state.calendar_seconds_per_second())


## What a power costs a company now: its base, scaling with the company's level
## for most (1 + level / 50).
func price(power: String, who: Company) -> int:
	var info: Dictionary = POWERS[power]
	if not bool(info.get("scaled", false)):
		return int(info.base)
	return int(float(info.base) * (1.0 + who.level() / 50.0))


## When (play time) a company can use a power again (-INF: now).
func ready_at(power: String, who: Company) -> float:
	return float((cooldowns.get(who.name, {}) as Dictionary).get(power, -INF))


## How many of a company's storms are out.
func storms_out(who: Company) -> int:
	var count := 0
	for storm: Dictionary in _state.weather.storms:
		if str(storm.get("sender", "")) == who.name:
			count += 1
	return count


## Why a company can't use a power on a target now, or "" if it can. The
## target: a (lon, lat) Vector2 for a point, a port id, a ship's id (int), or
## anything for a power with no target.
func error(power: String, target: Variant, who: Company) -> String:
	if not on:
		return "Divine Actions are off in this game."
	if not POWERS.has(power):
		return "No such power."
	var info: Dictionary = POWERS[power]
	var cost := price(power, who)
	if who.money < cost:
		return "%s costs %s; you have %s." % [info.name, Fmt.money(cost), Fmt.money(who.money)]
	var ready := ready_at(power, who)
	if _state.play_time < ready:
		return "%s is ready again in %s." % [info.name, _days_text(ready - _state.play_time)]
	if bool(info.get("yearly", false)):
		var year := _year()
		if int(wrath_years.get(who.name, -1)) == year:
			return "Wrath can be called down once a year: again in %d." % (year + 1)
	if STORM_TIERS.has(power) and storms_out(who) >= MAX_STORMS_ALIVE:
		return "Three of your storms are out already: wait for one to blow out."
	match str(info.target):
		"point":
			if not target is Vector2:
				return "Pick a point on the map."
		"port":
			if not target is String or GameData.get_port(str(target)).is_empty():
				return "Pick a port on the map."
			if power == "lightning" and _rival_hub_at(str(target), who) == null:
				return "No rival has a hub at %s." % GameData.port_name(str(target))
		"ship":
			var ship: Ship = _state.ship_by_id(int(target)) if target is int or target is float else null
			if ship == null:
				return "Pick a ship on the map."
			if _state.owner_of(ship) == who:
				return "Not one of your own ships."
			if ship.is_docked() or ship.is_lost() or ship.is_carried() or ship.is_towed():
				return "The Kraken takes ships at sea."
	return ""


## Uses a power (see error() first): takes the money, starts the cooldown,
## does the deed, and returns what was done, for the log ("called down a
## Tempest on the Bay of Biscay").
func act(power: String, target: Variant, who: Company) -> String:
	var info: Dictionary = POWERS[power]
	var cost := price(power, who)
	_state._add_money(who, -cost)
	if not cooldowns.has(who.name):
		cooldowns[who.name] = {}
	cooldowns[who.name][power] = _state.play_time + float(info.get("cooldown_weeks", 0.0)) * week_s()
	if bool(info.get("yearly", false)):
		wrath_years[who.name] = _year()
	var now: float = float(_state.play_time)
	var text := ""
	var where := ""
	match power:
		"squall", "tempest", "wrath":
			_state.weather.spawn_divine(power, target, who.name)
			where = _place_name(target)
			text = "called down %s %s on %s" % ["a" if power != "wrath" else "its", info.name, where]
		"fair_winds":
			effects.append({kind = "fair_winds", company = who.name, port = "", ship = -1, until = now + float(info.effect_weeks) * week_s(), since = now})
			text = "called up fair winds for its fleet"
		"calm_seas":
			var before: int = _state.weather.storms.size()
			_state.weather.storms.assign(_state.weather.storms.filter(func(storm: Dictionary) -> bool:
				return Geo.distance_nm(Vector2(storm.lon, storm.lat), target) > CALM_SEAS_NM))
			where = _place_name(target)
			var gone: int = before - _state.weather.storms.size()
			text = "calmed the seas round %s (%d %s blown out)" % [where, gone, "storm" if gone == 1 else "storms"]
		"plague", "deluge", "sea_change":
			where = GameData.port_name(str(target))
			effects.append({kind = power, company = who.name, port = str(target), ship = -1, until = now + float(info.effect_weeks) * week_s(), since = now})
			text = {plague = "sent a plague of gulls on %s", deluge = "sent a deluge on %s", sea_change = "brought a great flock to %s"}[power] % where
		"kraken":
			var ship: Ship = _state.ship_by_id(int(target))
			var victim: Company = _state.owner_of(ship)
			_state.lose_to_kraken(ship)
			effects.append({kind = "kraken", company = who.name, port = "", ship = ship.id, until = now + KRAKEN_SHOW_S, since = now})
			where = ship.name
			text = "set the Kraken on %s's %s" % [victim.name, ship.name]
		"lightning":
			var hub: Hub = _rival_hub_at(str(target), who)
			hub.level = maxi(hub.level - 1, 0)
			_state.hubs_changed.emit()
			effects.append({kind = "lightning", company = who.name, port = str(target), ship = -1, until = now + LIGHTNING_SHOW_S, since = now})
			where = GameData.port_name(str(target))
			text = "struck %s's hub at %s with lightning" % [_hub_owner(hub).name, where]
	ledger.append({who = who.name, power = power, where = where, at = now})
	while ledger.size() > LEDGER_KEPT:
		ledger.pop_front()
	_factors.clear()
	return text


## Whether a power's target hits a company (its port with its ships or hub,
## its ship), for the log's colour.
func hits(power: String, target: Variant, who: Company) -> bool:
	var info: Dictionary = POWERS[power]
	match str(info.target):
		"port":
			var port := str(target)
			if power == "lightning":
				return who.hub_at(port) != null
			for ship: Ship in _state.ships:
				if _state.owner_of(ship) == who and (ship.docked_at == port or ship.to_port == port):
					return true
			return who.hub_at(port) != null
		"ship":
			var ship: Ship = _state.ship_by_id(int(target)) if target is int or target is float else null
			return ship != null and _state.owner_of(ship) == who
		"point":
			if power == "calm_seas":
				return false
			for ship: Ship in _state.ships:
				if _state.owner_of(ship) == who and not ship.is_docked() and Geo.distance_nm(Geo.unproject(ship.world_position()), target) < float(STORM_TIERS[power].radius_nm) * 1.5:
					return true
	return false


## Whose a hub is.
func _hub_owner(hub: Hub) -> Company:
	for each: Company in _state.all_companies():
		if each.hubs.has(hub):
			return each
	return _state.company


## The hub another company than `who` has at a port, or null.
func _rival_hub_at(port_id: String, who: Company) -> Hub:
	for each: Company in _state.all_companies():
		if each == who:
			continue
		var hub: Hub = each.hub_at(port_id)
		if hub != null:
			return hub
	return null


## A point's name for the log: the nearest port's waters, or the open sea.
func _place_name(lon_lat: Vector2) -> String:
	var best := ""
	var nearest := 300.0
	for port: Dictionary in GameData.ports:
		var d := Geo.distance_nm(Vector2(float(port.lon), float(port.lat)), lon_lat)
		if d < nearest:
			nearest = d
			best = str(port.id)
	return "the waters off %s" % GameData.port_name(best) if not best.is_empty() else "the open sea (%.0f, %.0f)" % [lon_lat.x, lon_lat.y]


func _year() -> int:
	return int(Time.get_datetime_dict_from_unix_time(_state.calendar_time()).year)


## Seconds of play as game days ("3 days", "a day", "6 hours").
func _days_text(seconds: float) -> String:
	var hours := seconds * float(_state.calendar_seconds_per_second()) / 3600.0
	if hours >= 36.0:
		return "%d days" % roundi(hours / 24.0)
	if hours >= 18.0:
		return "a day"
	return "%d hours" % maxi(roundi(hours), 1)


## Whether an effect of a kind runs now, for a company (by name; "" for any)
## or at a port.
func effect(kind: String, company := "", port := "") -> Dictionary:
	for each: Dictionary in effects:
		if each.kind == kind and (company.is_empty() or each.company == company) and (port.is_empty() or each.port == port):
			return each
	return {}


# --- Every step ----------------------------------------------------------------

func step(_delta: float) -> void:
	if not on:
		return
	var now: float = float(_state.play_time)
	if not effects.is_empty() and effects.any(func(each: Dictionary) -> bool: return now >= float(each.until)):
		effects = effects.filter(func(each: Dictionary) -> bool: return now < float(each.until))
	# The comet, told of once the day it's up.
	var day := _calendar_day()
	if comet_up() and day != _comet_day and _state.in_session:
		_comet_day = day
		ActivityLog.add("A comet blazes across the sky: everyone's sale prices are up 10% today.", ActivityLog.Kind.GOOD)


# --- Blessings and omens ----------------------------------------------------------

## A ship's speed from its blessings and the winds ([factor]), whether the
## sea's escorts shield it from storms' wear, and whether sharks hurry it (a
## rescuer); looked at again every REFRESH_S.
func _ship_factors(ship: Ship) -> Array:
	var kept: Array = _factors.get(ship, [])
	if not kept.is_empty() and _state.play_time < float(kept[0]):
		return kept
	var speed := 1.0
	var shielded := false
	var who: Company = _state.owner_of(ship)
	if not effect("fair_winds", who.name).is_empty():
		speed *= FAIR_WINDS_SPEED
	speed *= 1.0 + blessing(ship)
	if not ship.is_docked():
		var at := Geo.unproject(ship.world_position())
		shielded = _pod_near(at, ESCORT_NM, false)
		if ship.is_service() and ship.rescuing != null and _pod_near(Geo.unproject(ship.rescuing.world_position()), SHARK_NM, true):
			speed *= SHARK_HURRY
	kept = [_state.play_time + REFRESH_S, speed, shielded]
	_factors[ship] = kept
	return kept


## How much faster a ship sails for its blessings and the winds (1: as ever).
func speed_factor(ship: Ship) -> float:
	return float(_ship_factors(ship)[1]) if on else 1.0


## True if the sea's escorts (a pod within ESCORT_NM) shield a ship from a storm's wear.
func escorted(ship: Ship) -> bool:
	return on and bool(_ship_factors(ship)[2])


## The share (0 to BLESS_CAP) the birds following a ship add to its speed.
func blessing(ship: Ship) -> float:
	if not on:
		return 0.0
	var share := 0.0
	for entry: Dictionary in BirdLife.shared().following(ship):
		var kind := str(Birds.shared().species(str(entry.id)).get("kind", ""))
		share += BLESS_PER_BIRD * int(entry.count) * (2.0 if kind == "Albatross" else 1.0)
	return minf(share, BLESS_CAP)


## The share a ship's sale loses to the frigatebirds following it (0 to FRIGATE_STEAL_CAP).
func stolen(ship: Ship) -> float:
	if not on:
		return 0.0
	var share := 0.0
	for entry: Dictionary in BirdLife.shared().following(ship):
		if str(Birds.shared().species(str(entry.id)).get("kind", "")) == "Frigatebird":
			share += FRIGATE_STEAL * int(entry.count)
	return minf(share, FRIGATE_STEAL_CAP)


## How many birds a port has about it now (gulls, cormorants, seabirds and
## sea ducks), plus a great flock brought by Sea change; counted again every REFRESH_S.
func port_birds(port_id: String) -> int:
	var kept: Array = _port_birds.get(port_id, [])
	if not kept.is_empty() and _state.play_time < float(kept[0]):
		return int(kept[1])
	var count := 0
	var cal := float(_state.calendar_time())
	for cls in ["gulls", "cormorants", "seabirds", "sea_ducks"]:
		for entry: Dictionary in Wildlife.shared().birds_at(port_id, cls, cal):
			count += int(entry.count)
	if not effect("sea_change", "", port_id).is_empty():
		count += SEA_CHANGE_BIRDS
	_port_birds[port_id] = [_state.play_time + REFRESH_S, count]
	return count


## A port's blessing from its birds (0 to 1: the share of PORT_BIRDS_FULL).
func port_blessing(port_id: String) -> float:
	return clampf(port_birds(port_id) / PORT_BIRDS_FULL, 0.0, 1.0)


## How a docked ship's stop (its loading, repairs and refuelling) is scaled: the
## port's birds quicken it (by up to half), a plague of gulls doubles it for
## every company but the sender's, the lamps quicken it by night, and the
## first snow slows it in the north.
func stop_factor(ship: Ship) -> float:
	if not on or not ship.is_docked():
		return 1.0
	var port := ship.docked_at
	var factor := 1.0 - 0.5 * port_blessing(port)
	var plague := effect("plague", "", port)
	if not plague.is_empty() and str(plague.company) != _state.owner_of(ship).name:
		factor *= PLAGUE_STOP
	var lon_lat := Vector2(float(GameData.get_port(port).get("lon", 0.0)), float(GameData.get_port(port).get("lat", 0.0)))
	if night_at(lon_lat) > 0.5:
		factor *= LAMPS_STOP
	var date := Time.get_datetime_dict_from_unix_time(_state.calendar_time())
	if int(date.month) == 12 and int(date.day) <= 7 and lon_lat.y > SNOW_LAT:
		factor *= SNOW_STOP
	return factor


## How a port's prices are scaled for a company's ships there: its birds'
## blessing (up to PORT_PRICE_SHARE better each way), a deluge (halved), the comet (sales up).
func price_factor(port_id: String, selling: bool) -> float:
	if not on:
		return 1.0
	var blessing_share := port_blessing(port_id) * PORT_PRICE_SHARE
	var factor := (1.0 + blessing_share) if selling else (1.0 - blessing_share)
	if not effect("deluge", "", port_id).is_empty():
		factor *= DELUGE_PRICES
	if selling and comet_up():
		factor *= COMET_SELL
	return factor


## Extra delivery XP (a share) at a port from the omens: cherry blossom in Japan in April doubles it.
func xp_bonus(port_id: String) -> float:
	if not on or port_id.is_empty():
		return 0.0
	if str(GameData.get_port(port_id).get("country", "")) == "Japan" and int(Time.get_datetime_dict_from_unix_time(_state.calendar_time()).month) == 4:
		return 1.0
	return 0.0


## Whether the comet is up today: one day a calendar year, by the year.
func comet_up() -> bool:
	if not on:
		return false
	var day := _calendar_day()
	if _comet_cache[0] != day:
		var date := Time.get_datetime_dict_from_unix_time(_state.calendar_time())
		var day_of_year := int([0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334][int(date.month) - 1]) + int(date.day)
		_comet_cache = [day, day_of_year == 1 + hash(int(date.year) * 7919) % 365]
	return bool(_comet_cache[1])


func _calendar_day() -> int:
	return int(floor(_state.calendar_time() / 86400.0))


## Whether a pod of sea animals (sharks only, or any) is within some nm of a
## point; the pods' places are looked at again every REFRESH_S.
func _pod_near(lon_lat: Vector2, nm: float, sharks: bool) -> bool:
	if _state.play_time >= _pods_until:
		_pods.clear()
		var sea := SeaLife.shared()
		var unix := float(_state.calendar_time())
		for i in sea.pods.size():
			var kind := str((sea.species[sea.pods[i].species] as Dictionary).get("kind", ""))
			_pods.append([sea.state(i, unix).pos, kind == "shark"])
		_pods_until = _state.play_time + REFRESH_S
	for pod: Array in _pods:
		if (not sharks or bool(pod[1])) and Geo.distance_nm(pod[0], lon_lat) <= nm:
			return true
	return false


## How dark it is at a point (0 day, 1 the dead of night), as the World map
## draws it (MapView._update_night(): the calendar is Greenwich time).
static func night_at(lon_lat: Vector2) -> float:
	var unix := GameState.calendar_time()
	var date := Time.get_datetime_dict_from_unix_time(unix)
	var day_of_year := int([0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334][int(date.month) - 1]) + int(date.day)
	var tilt := deg_to_rad(23.44) * sin(TAU * (day_of_year - 81) / 365.0)
	var hours := fposmod(float(unix), 86400.0) / 3600.0
	var lon := deg_to_rad((12.0 - hours) * 15.0 + GameState.clock_longitude())
	var sun := Vector3(cos(tilt) * cos(lon), cos(tilt) * sin(lon), sin(tilt))
	var lat_r := deg_to_rad(lon_lat.y)
	var lon_r := deg_to_rad(lon_lat.x)
	var unit := Vector3(cos(lat_r) * cos(lon_r), cos(lat_r) * sin(lon_r), sin(lat_r))
	return 1.0 - smoothstep(-0.14, 0.1, unit.dot(sun))


# --- Saving ----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {on = on, effects = effects, cooldowns = cooldowns, wrath_years = wrath_years, ledger = ledger}


func from_dict(data: Dictionary) -> void:
	on = bool(data.get("on", false))
	effects.assign(data.get("effects", []))
	cooldowns = data.get("cooldowns", {})
	wrath_years = data.get("wrath_years", {})
	ledger.assign(data.get("ledger", []))
	_factors.clear()
	_port_birds.clear()
