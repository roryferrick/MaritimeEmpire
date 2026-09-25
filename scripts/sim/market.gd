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


func _init(state: Node) -> void:
	_state = state


func clear() -> void:
	_impacts.clear()


## What a port pays for a unit of a commodity now.
func sell_price(port_id: String, commodity_id: String) -> float:
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
	var port := GameData.get_port(port_id)
	var lon := deg_to_rad(float(port.get("lon", 0.0)))
	var lat := deg_to_rad(float(port.get("lat", 0.0)))
	var phase := GameData._hash01(commodity_id + "/a") * TAU + lon * 2.0 + lat * 1.5
	var phase2 := GameData._hash01(commodity_id + "/b") * TAU + lon * 3.0 - lat * 2.5
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


## The commodity a ship of this model would load at one port to sell at the
## next, and its profit per unit there (after the canal tolls, and with the
## leg's bonuses on the profit), as [commodity id, profit per unit]; ["", 0] if nothing it
## carries makes a profit.
func best_cargo(model: Dictionary, from_port: String, to_port: String) -> Array:
	var best := ""
	var best_profit := 0.0
	var toll_share := GameData.leg_toll_share(from_port, to_port)
	for commodity_id: String in model.get("cargo", []):
		var sell := sell_price(to_port, commodity_id)
		var margin := sell - buy_price(from_port, commodity_id)
		var profit: float = margin + _state.trade_bonus(from_port, to_port, margin, str(model.get("id", ""))) - sell * toll_share
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
