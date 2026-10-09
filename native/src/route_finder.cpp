// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See route_finder.h. Each function says which GDScript it follows; their
// arithmetic is kept in the same order so the numbers are the same.
#include "route_finder.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>
#include <cstring>

using namespace godot;

namespace {
constexpr double TAU_D = 6.2831853071795864769252867666;

String pair_key(const String &a, const String &b) {
	return a + String(">") + b;
}
} // namespace

// GameData.distance_nm(), leg_toll_share(), canal_lock_seconds(),
// convoy_wait_seconds(), sale_factor() and needs_seaway() (the provider's
// _route_pair()): all fixed by the map.
const RouteFinder::Pair &RouteFinder::_pair(const String &a, const String &b) {
	String key = pair_key(a, b);
	if (!_pairs.has(key)) {
		Array got = _provider->call("_route_pair", a, b);
		Pair pair;
		pair.miles = got[0];
		pair.toll_share = got[1];
		pair.lock_s = got[2];
		pair.convoy_s = got[3];
		pair.sale_factor = got[4];
		pair.seaway = got[5];
		_pairs[key] = pair;
	}
	return _pairs[key];
}

// A port as it is now (the provider's _route_port(): PortSizes' impact and
// cost factors, whether the model fits, where it is).
const RouteFinder::Port &RouteFinder::_port(const String &id) {
	if (!_ports.has(id)) {
		Array got = _provider->call("_route_port", id, _context["model"]);
		Port port;
		port.impact_factor = got[0];
		port.cost_factor = got[1];
		port.fits = got[2];
		port.lon = got[3];
		port.lat = got[4];
		_ports[id] = port;
	}
	return _ports[id];
}

double RouteFinder::_base(const String &port, const String &commodity) {
	String key = port + String("/") + commodity;
	if (!_bases.has(key)) {
		_bases[key] = (double)_provider->call("_route_base_price", port, commodity);
	}
	return _bases[key];
}

// GameData._hash01().
double RouteFinder::_hash01(const String &text) {
	if (!_hashes.has(text)) {
		_hashes[text] = (double)(text.hash() & 0xFFFFFF) / (double)0x1000000;
	}
	return _hashes[text];
}

// Market._drift().
double RouteFinder::_drift(const String &port_id, const String &commodity) {
	double amount = _context["drift"];
	if (amount <= 0.0) {
		return 1.0;
	}
	double period = _context["drift_period_s"];
	const Port &port = _port(port_id);
	double lon = Math::deg_to_rad(port.lon);
	double lat = Math::deg_to_rad(port.lat);
	double phase = _hash01(commodity + String("/a")) * TAU_D + lon * 2.0 + lat * 1.5;
	double phase2 = _hash01(commodity + String("/b")) * TAU_D + lon * 3.0 - lat * 2.5;
	double t = _play_time;
	double wave = 0.65 * UtilityFunctions::sin(TAU_D * t / period + phase) + 0.35 * UtilityFunctions::sin(TAU_D * t / (period * 0.37) + phase2);
	return 1.0 + amount * wave;
}

// Market._impact().
double RouteFinder::_impact(const String &port, const String &commodity) {
	Variant found = _impacts.get(port + String("/") + commodity, Variant());
	if (found.get_type() != Variant::ARRAY) {
		return 0.0;
	}
	Array entry = found;
	if (entry.is_empty()) {
		return 0.0;
	}
	double age = _play_time - (double)entry[1];
	double half_life = (double)_context["impact_half_life_s"] * _port(port).impact_factor;
	return (double)entry[0] * UtilityFunctions::pow(0.5, age / half_life);
}

// Market.sell_price().
double RouteFinder::_sell_price(const String &port, const String &commodity) {
	return _base(port, commodity) * _drift(port, commodity) * (1.0 + _impact(port, commodity));
}

// A hub's bonus of a kind for a commodity at a port (Hub.industry_bonus(): from the context's hubs).
static double industry(const Dictionary &hubs, const String &port, const String &commodity, int kind) {
	Variant hub = hubs.get(port, Variant());
	if (hub.get_type() != Variant::ARRAY) {
		return 0.0;
	}
	Dictionary bonuses = ((Array)hub)[kind];
	return bonuses.get(commodity, 0.0);
}

// GameState.company_sell_price() and company_buy_price().
double RouteFinder::_company_sell(const String &port, const String &commodity) {
	String key = String("s") + port + String("/") + commodity;
	if (!_prices.has(key)) {
		_prices[key] = _sell_price(port, commodity) * (1.0 + (_hubs.has(port) ? industry(_hubs, port, commodity, 1) : 0.0));
	}
	return _prices[key];
}

double RouteFinder::_company_buy(const String &port, const String &commodity) {
	String key = String("b") + port + String("/") + commodity;
	if (!_prices.has(key)) {
		double buy = _sell_price(port, commodity) * (1.0 + (double)_context["spread"]);
		_prices[key] = buy * (1.0 - (_hubs.has(port) ? industry(_hubs, port, commodity, 2) : 0.0));
	}
	return _prices[key];
}

// Market.fuel_price().
double RouteFinder::_fuel_price(const String &port) {
	String key = String("o") + port;
	if (!_prices.has(key)) {
		_prices[key] = _sell_price(port, "oil") * (double)_context["fuel_per_oil"] * _port(port).cost_factor;
	}
	return _prices[key];
}

// The search's model's seconds for a whole leg (Ship.leg_seconds() from full
// maintenance: the provider's _route_leg_seconds()), kept by its speed and wear.
double RouteFinder::_seconds(const String &a, const String &b) {
	double top = _context["top_speed"];
	double wear = _context["wear_per_s"];
	int64_t top_bits;
	int64_t wear_bits;
	memcpy(&top_bits, &top, sizeof(double));
	memcpy(&wear_bits, &wear, sizeof(double));
	String key = pair_key(a, b) + String("|") + String::num_int64(top_bits) + String("|") + String::num_int64(wear_bits);
	if (!_leg_seconds.has(key)) {
		_leg_seconds[key] = (double)_provider->call("_route_leg_seconds", a, b, _pair(a, b).miles);
	}
	return _leg_seconds[key];
}

// Ship.can_sail() for the search's model.
bool RouteFinder::_can_sail(const String &a, const String &b) {
	if (a == b) {
		return false;
	}
	const Pair &pair = _pair(a, b);
	if (!(pair.miles <= (double)_context["range_nm"])) {
		return false;
	}
	// Ship.can_reach(): Ship.fits_lane(), fits_port(), and fuel for it.
	if (!((bool)_context["seaway"] || !pair.seaway) || !_port(b).fits) {
		return false;
	}
	double seconds = _seconds(a, b) + (double)_context["departure_margin_s"];
	return (double)_context["fuel_per_s"] * seconds <= (double)_context["fuel_tank"];
}

// Market.best_cargo() (its memo path).
Array RouteFinder::_best_cargo(const String &a, const String &b) {
	String best;
	double best_profit = 0.0;
	const Pair &pair = _pair(a, b);
	double toll_share = pair.toll_share;
	double factor = NAN;
	for (int64_t i = 0; i < _cargo.size(); i++) {
		String commodity = _cargo[i];
		double sell = _company_sell(b, commodity);
		double buy = _company_buy(a, commodity);
		double bonus;
		if (sell - buy <= 0.0) {
			bonus = 0.0;
		} else {
			if (std::isnan(factor)) {
				// GameState.trade_bonus_factor().
				double pay = 0.0;
				Variant hub = _hubs.get(b, Variant());
				if (hub.get_type() == Variant::ARRAY) {
					pay = ((Array)hub)[0];
				}
				factor = pair.sale_factor * (1.0 + pay) * (double)_context["mega"];
			}
			bonus = (sell - buy) * (factor - 1.0);
		}
		double margin = sell - buy;
		double profit = margin + bonus - sell * toll_share;
		if (profit > best_profit) {
			best = commodity;
			best_profit = profit;
		}
	}
	Array out;
	out.push_back(best);
	out.push_back(best_profit);
	return out;
}

// RivalAI._leg().
const RouteFinder::Leg &RouteFinder::_leg(const String &a, const String &b) {
	String key = pair_key(a, b);
	if (!_legs.has(key)) {
		Leg leg;
		double sail = _seconds(a, b);
		if (std::isfinite(sail)) {
			Array cargo = _best_cargo(a, b);
			double unit = cargo[1];
			if (!_hubs.has(b)) {
				unit *= 1.0 - (double)_context["port_fee"];
			}
			double fuel = (double)_context["model_fuel_per_s"] * sail * _fuel_price(a);
			double repair = (double)_context["wear_pct_per_min"] / 60.0 * sail * (double)_context["repair_cost_per_pct"];
			const Pair &pair = _pair(a, b);
			double seconds = sail + (double)_context["dock_s"] + (double)_context["stop_extra_s"] + pair.lock_s + pair.convoy_s;
			leg.sails = true;
			leg.money = unit * (double)_context["capacity"] - fuel - repair;
			leg.seconds = seconds;
		}
		_legs[key] = leg;
	}
	return _legs[key];
}

// RivalAI._loop_rate().
double RouteFinder::_loop_rate(const Array &loop) {
	double money = 0.0;
	double seconds = 0.0;
	for (int64_t i = 0; i < loop.size(); i++) {
		String a = loop[i];
		String b = loop[(i + 1) % loop.size()];
		const Leg &leg = _leg(a, b);
		if (!leg.sails) {
			return -INFINITY;
		}
		money += leg.money;
		seconds += leg.seconds;
	}
	return money / MAX(seconds, 1.0) - (double)_context["wages_s"];
}

bool RouteFinder::_higher(const Variant &a, const Variant &b) {
	return (double)((Array)a)[0] > (double)((Array)b)[0];
}

// RivalAI._work_out_loops(): its best loops from `start` ([rate, ports]),
// best first. The context: see RivalAI._route_context().
Array RouteFinder::work_out(Object *provider, const Dictionary &context) {
	_provider = provider;
	_context = context;
	_hubs = context["hubs"];
	_impacts = context["impacts"];
	_cargo = context["cargo"];
	_play_time = context["play_time"];
	_model_id = context["model_id"];
	_ports.clear();
	_prices.clear();
	_legs.clear();
	String start = context["start"];
	Array partners_in = context["partners"];
	Callable higher = callable_mp_static(&RouteFinder::_higher);
	Array partners;
	for (int64_t i = 0; i < partners_in.size(); i++) {
		String other = partners_in[i];
		Array loop;
		loop.push_back(start);
		loop.push_back(other);
		double rate = _loop_rate(loop);
		if (rate > 0.0) {
			Array entry;
			entry.push_back(rate);
			entry.push_back(loop);
			partners.push_back(entry);
		}
	}
	partners.sort_custom(higher);
	Array loops = partners.slice(0, 16);
	if ((bool)context["loops3"]) {
		Array near;
		Array top = partners.slice(0, (int)context["loop_partners"]);
		for (int64_t i = 0; i < top.size(); i++) {
			near.push_back(((Array)((Array)top[i])[1])[1]);
		}
		for (int64_t i = 0; i < near.size(); i++) {
			String p = near[i];
			for (int64_t j = 0; j < near.size(); j++) {
				String q = near[j];
				if (p != q && _can_sail(p, q)) {
					Array loop;
					loop.push_back(start);
					loop.push_back(p);
					loop.push_back(q);
					double rate = _loop_rate(loop);
					if (rate > 0.0) {
						Array entry;
						entry.push_back(rate);
						entry.push_back(loop);
						loops.push_back(entry);
					}
				}
			}
		}
	}
	loops.sort_custom(higher);
	_provider = nullptr;
	return loops.slice(0, 16);
}

// RivalAI._loop_rate() for one loop (a ship's own route, say).
double RouteFinder::loop_rate(Object *provider, const Dictionary &context, const Array &loop) {
	_provider = provider;
	_context = context;
	_hubs = context["hubs"];
	_impacts = context["impacts"];
	_cargo = context["cargo"];
	_play_time = context["play_time"];
	_model_id = context["model_id"];
	_ports.clear();
	_prices.clear();
	_legs.clear();
	double rate = loop.size() < 2 ? -INFINITY : _loop_rate(loop);
	_provider = nullptr;
	return rate;
}

void RouteFinder::forget() {
	_pairs.clear();
	_bases.clear();
	_leg_seconds.clear();
}

void RouteFinder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("work_out", "provider", "context"), &RouteFinder::work_out);
	ClassDB::bind_method(D_METHOD("loop_rate", "provider", "context", "loop"), &RouteFinder::loop_rate);
	ClassDB::bind_method(D_METHOD("forget"), &RouteFinder::forget);
}
