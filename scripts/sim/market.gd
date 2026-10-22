# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Market
extends RefCounted
## Live commodity prices (see data/markets.json). A port's sell price for a
## commodity (what it pays you) is GameData.base_price() x a slow drift x the
## impact of the player's own trades there; its buy price (what you pay) is
## `spread` more. The drift is a fixed function of play time, so it needs no
## saving; trade impacts fade with a half-life and are saved.

var _state: Node  # GameState
## "PORT/commodity" -> [impact (e.g. -0.01 for 1% cheaper), play_time it was set].
var _impacts := {}
## For the drift (see _drift()), worked out once: port id -> its (lon, lat) in
## radians; commodity id -> its two waves' phases.
var _places := {}
var _phases := {}


func _init(state: Node) -> void:
	_state = state


func clear() -> void:
	_impacts.clear()


## What a port pays for a unit of a commodity now: the living world's price
## (WorldEconomy: its zone's stockpile), or for a good the world doesn't
## trade, the old steady price with its drift and the player's trades' impact.
func sell_price(port_id: String, commodity_id: String) -> float:
	if _state.world.zone_of_port(port_id) >= 0 and _state.world.has_good(commodity_id):
		return _state.world.sell_price(port_id, commodity_id)
	return GameData.base_price(port_id, commodity_id) * _drift(port_id, commodity_id) * (1.0 + _impact(port_id, commodity_id))


## What a unit of a commodity costs to buy at a port now.
func buy_price(port_id: String, commodity_id: String) -> float:
	return sell_price(port_id, commodity_id) * (1.0 + float(GameData.markets.get("spread", 0.0)))


## What ships pay for their own fuel at a port: the oil price there x
## fuel_per_oil, x the port size's cost factor (see PortSizes).
func fuel_price(port_id: String) -> float:
	return sell_price(port_id, "oil") * float(GameData.markets.get("fuel_per_oil", 0.0)) * _state.port_sizes.cost_factor(port_id)


## Selling lowers the port's price for that commodity, buying raises it: by up
## to impact_max for a load worth impact_ref_value, less for smaller loads,
## times the port size's impact factor (more at small ports, less at big ones).
func trade(port_id: String, commodity_id: String, value: float, buying: bool) -> void:
	var world: WorldEconomy = _state.world
	var zone := world.zone_of_port(port_id)
	var good := world.good_index(commodity_id)
	if zone >= 0 and good >= 0:  # The living world: the goods come out of (or go into) the zone's stockpile.
		var quantity := value / maxf(world.sell_price(port_id, commodity_id), 0.01)
		if buying:
			world.take(zone, good, quantity, value)
		else:
			world.deliver(zone, good, quantity, value)
		return
	var size := minf(value / float(GameData.markets.get("impact_ref_value", 1.0)), 1.0)
	var change: float = float(GameData.markets.get("impact_max", 0.0)) * size * (1.0 if buying else -1.0) * _state.port_sizes.impact_factor(port_id)
	_impacts["%s/%s" % [port_id, commodity_id]] = [_impact(port_id, commodity_id) + change, _state.play_time]


## A slow wander of up to +-drift, from two sine waves with a period of about
## drift_period_s. Their phases vary smoothly across the map (and differ per
## commodity), so neighbouring ports drift together and far-apart regions don't.
func _drift(port_id: String, commodity_id: String) -> float:
	var amount := float(GameData.markets.get("drift", 0.0))
	if amount <= 0.0:
		return 1.0
	var period := float(GameData.markets.get("drift_period_s", 1200))
	var place: PackedFloat64Array = _places.get(port_id, PackedFloat64Array())  # (Kept: the sim asks often.)
	if place.is_empty():
		var port := GameData.get_port(port_id)
		place = PackedFloat64Array([deg_to_rad(float(port.get("lon", 0.0))), deg_to_rad(float(port.get("lat", 0.0)))])
		_places[port_id] = place
	var phases: PackedFloat64Array = _phases.get(commodity_id, PackedFloat64Array())
	if phases.is_empty():
		phases = PackedFloat64Array([GameData._hash01(commodity_id + "/a") * TAU, GameData._hash01(commodity_id + "/b") * TAU])
		_phases[commodity_id] = phases
	var lon := place[0]
	var lat := place[1]
	var phase := phases[0] + lon * 2.0 + lat * 1.5
	var phase2 := phases[1] + lon * 3.0 - lat * 2.5
	var t: float = _state.play_time
	var wave := 0.65 * sin(TAU * t / period + phase) + 0.35 * sin(TAU * t / (period * 0.37) + phase2)
	return 1.0 + amount * wave


## The trade impact left at a port, fading with impact_half_life_s (longer at
## small ports, shorter at big ones; see _half_life()).
func _impact(port_id: String, commodity_id: String) -> float:
	var entry: Array = _impacts.get("%s/%s" % [port_id, commodity_id], [])
	if entry.is_empty():
		return 0.0
	var age: float = _state.play_time - float(entry[1])
	return float(entry[0]) * pow(0.5, age / _half_life(port_id))


## How long (seconds) half of a trade's impact on a port's prices takes to fade.
func _half_life(port_id: String) -> float:
	return float(GameData.markets.get("impact_half_life_s", 40)) * _state.port_sizes.impact_factor(port_id)


## A unit of a commodity's profit carried from one port to another, as
## best_cargo() works it out: the margin between the company's prices, with
## the leg's bonuses for a ship of model_id on a profit, less the canal tolls
## (a company's: this player's unless `of` says).
func unit_profit(commodity_id: String, from_port: String, to_port: String, model_id := "", of: Company = null) -> float:
	var sell: float = _state.company_sell_price(to_port, commodity_id, of)
	var margin: float = sell - _state.company_buy_price(from_port, commodity_id, of)
	return margin + _state.trade_bonus(from_port, to_port, margin, model_id, of) - sell * GameData.leg_toll_share(from_port, to_port)


## The commodity a ship of this model would load at one port to sell at the
## next, and its profit per unit there (after the canal tolls, and with the
## leg's bonuses on the profit, with a company's hubs and upgrades: this
## player's unless `of` says), as [commodity id, profit per unit]; ["", 0] if nothing it
## carries makes a profit. The profit is a unit of hold's (a horse takes
## three: markets.json hold), and fresh cargo's counts what it loses on the
## way. `memo` (when given) keeps the prices and bonuses
## it looks up for the next call, for a caller asking about many legs while
## nothing can change them.
func best_cargo(model: Dictionary, from_port: String, to_port: String, of: Company = null, memo: Variant = null) -> Array:
	var best := ""
	var best_profit := 0.0
	var model_id := str(model.get("id", ""))
	var toll_share := GameData.leg_toll_share(from_port, to_port)
	var factor := NAN  # (The leg's bonuses, from the memo: looked up once.)
	var days := -1.0  # (The leg's calendar days at sea, for fresh cargo: worked out once if needed.)
	for commodity_id: String in model.get("cargo", []):
		if GameData.hold_of(commodity_id) > float(model.get("capacity", 0)):
			continue  # (Doesn't fit at all: a superyacht on a Boat Barge.)
		var sell: float
		var buy: float
		var bonus: float
		if memo == null:
			sell = maxf(_state.company_sell_price(to_port, commodity_id, of), _state.industry.input_value(of if of != null else _state.company, to_port, commodity_id))
			buy = _state.company_buy_price(from_port, commodity_id, of)
			bonus = _state.trade_bonus(from_port, to_port, sell - buy, model_id, of)
		else:
			var kept: Dictionary = memo
			var sell_key := "s" + to_port + "/" + commodity_id
			if not kept.has(sell_key):
				kept[sell_key] = maxf(_state.company_sell_price(to_port, commodity_id, of), _state.industry.input_value(of if of != null else _state.company, to_port, commodity_id))  # (Or what its own site there would pay: Industry.)
			sell = kept[sell_key]
			var buy_key := "b" + from_port + "/" + commodity_id
			if not kept.has(buy_key):
				kept[buy_key] = _state.company_buy_price(from_port, commodity_id, of)
			buy = kept[buy_key]
			if sell - buy <= 0.0:
				bonus = 0.0
			else:
				if is_nan(factor):
					var factor_key := "f" + from_port + ">" + to_port + "/" + model_id
					if not kept.has(factor_key):
						kept[factor_key] = _state.trade_bonus_factor(from_port, to_port, model_id, of)
					factor = kept[factor_key]
				bonus = (sell - buy) * (factor - 1.0)
		var loss := Farms.loses_a_day(commodity_id)
		if loss > 0.0:  # Fresh cargo: what it'll have lost by the time it's there (see Ship.cargo_value_factor()).
			if days < 0.0:
				days = GameData.distance_nm(from_port, to_port) / maxf(float(model.get("speed_nm_per_s", 1.0)), 0.1) * _state.days_per_second()
			var kept := maxf(1.0 - loss * (1.0 - float(model.get("keeps_fresh", 0.0))) * days, 0.1)
			bonus -= sell * (1.0 - kept)
		var margin := sell - buy
		var profit := (margin + bonus - sell * toll_share) / GameData.hold_of(commodity_id)  # (A unit of hold: a horse takes three.)
		if profit > best_profit:
			best = commodity_id
			best_profit = profit
	return [best, best_profit]


func to_dict() -> Dictionary:
	var out := {}
	for key: String in _impacts:
		var parts := key.split("/")
		var left := _impact(parts[0], parts[1])
		if absf(left) > 0.0001:
			out[key] = left
	return out


func from_dict(data: Dictionary) -> void:
	_impacts.clear()
	for key: String in data:
		_impacts[key] = [float(data[key]), _state.play_time]
