// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See ship_stepper.h. The arithmetic is GameState._advance() and _sail()'s,
// in the same order, so the results are the same to the last bit.
#include "ship_stepper.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

using namespace godot;

namespace {

// The Ship and GameState members read and written (looked up once).
struct Names {
	StringName docked_at = "docked_at", lost_reason = "lost_reason", job_phase = "job_phase", kind = "_kind_cache";
	StringName worked = "worked", lock_time = "lock_time", canal_state = "canal_state";
	StringName leg_from = "_leg_from", leg_to = "_leg_to", from_port = "from_port", to_port = "to_port";
	StringName leg_has_canal = "_leg_has_canal", leg_zones = "_leg_zones", leg_length = "_leg_length";
	StringName escort = "escort", traveled_nm = "traveled_nm", storm_check_time = "storm_check_time", storm_factors = "storm_factors";
	StringName stats_dirty = "_stats_dirty", top_speed = "_top_speed", fuel_per_s = "_fuel_per_s", wear_per_s = "_wear_per_s";
	StringName maintenance = "maintenance", fuel = "fuel", sea_time = "sea_time", risk_check_time = "risk_check_time";
	StringName weather_wait = "weather_wait", ice_wait = "ice_wait", route = "route", paused = "paused";
	StringName play_time = "play_time", weather = "weather", icebreaking = "icebreaking";
	StringName can_close = "_can_close", any_open_closure = "_any_open_closure", advance = "_advance", closed_by = "closed_by";
	StringName leg_length_method = "leg_length", top_speed_method = "top_speed", storm_factors_method = "_storm_factors";
	StringName lose = "_lose", check_at_risk = "_check_at_risk", arrive = "_arrive";
	StringName berth_phase = "berth_phase", load_wait = "load_wait", load_check_time = "load_check_time", short_of_load = "_short_of_load";
	StringName dock_time = "dock_time", hold_reason = "hold_reason", base_port = "base_port", berth = "berth";
};

const Names &names() {
	static Names n;
	return n;
}

} // namespace

void ShipStepper::setup(Object *state, const Dictionary &constants) {
	_state = state;
	_weather = Object::cast_to<Object>(state->get(names().weather));
	_icebreaking = Object::cast_to<Object>(state->get(names().icebreaking));
	_open_sea_zone = constants.get("open_sea_zone", Array());
	_min_recovery_speed = constants.get("min_recovery_speed", 0.05);
	_kind_icebreaker = constants.get("kind_icebreaker", 2);
	_kind_cargo = constants.get("kind_cargo", 0);
	_at_risk_check_s = constants.get("at_risk_check_s", 1.0);
	_kind_recovery = constants.get("kind_recovery", 1);
	_kind_tug = constants.get("kind_tug", 3);
}

// One step of a ship sailing its leg (see the top): true if done here
// (calling GameState for its arrival, loss or at-risk check as _advance()
// would, unless `events` is off, when those cases are left), false (and
// nothing changed) if GameState should do it.
bool ShipStepper::_sail(Object *ship, double delta, double play_time, bool can_close, bool any_closure, bool events) {
	const Names &n = names();
	if (!String(ship->get(n.docked_at)).is_empty() || !String(ship->get(n.lost_reason)).is_empty() || !String(ship->get(n.job_phase)).is_empty()) {
		return false;
	}
	int kind = ship->get(n.kind);
	if (kind < 0 || kind == _kind_icebreaker) {
		return false;
	}
	String from = ship->get(n.from_port);
	if (from.is_empty()) {
		return false;
	}
	// Its leg as worked out (Ship._update_leg(), asked for if it's new), with no canal on it.
	if (from != String(ship->get(n.leg_from)) || String(ship->get(n.to_port)) != String(ship->get(n.leg_to))) {
		ship->call(n.leg_length_method);
		_why[0]++;
	}
	if ((double)ship->get(n.lock_time) >= 0.0 || !String(ship->get(n.canal_state)).is_empty() || (bool)ship->get(n.leg_has_canal)) {
		_why[1]++;
		return false;
	}
	if (ship->get(n.escort).get_type() != Variant::NIL) {
		_why[2]++;
		return false;
	}
	if (any_closure || !String(ship->get(n.ice_wait)).is_empty()) {
		_why[3]++;
		return false;
	}
	double traveled = ship->get(n.traveled_nm);
	// Ship.zone_at().
	Array zones = ship->get(n.leg_zones);
	Array zone = _open_sea_zone;
	for (int i = 0; i < zones.size(); i++) {
		Array each = zones[i];
		if (traveled < (double)each[0]) {
			zone = each;
			break;
		}
	}
	// Its storm factors (GameState._storm_factors(), when they're due a look) and stats.
	Array storm = play_time < (double)ship->get(n.storm_check_time) ? (Array)ship->get(n.storm_factors) : (Array)_state->call(n.storm_factors_method, ship);
	if ((bool)ship->get(n.stats_dirty)) {
		ship->call(n.top_speed_method);
		_why[4]++;
	}
	double top_speed = ship->get(n.top_speed);
	double maintenance = ship->get(n.maintenance);
	bool service = kind != _kind_cargo;
	double speed = top_speed * std::clamp(maintenance, 0.0, 1.0);
	if (service) {
		speed = std::max(speed, top_speed * _min_recovery_speed);
	}
	speed *= (double)zone[1] * (double)storm[0];
	double target = traveled + speed * delta;
	// A storm closing ports somewhere: one closing its port it waits off
	// (GameState._storm_hold()); otherwise it sails on as ever.
	if (can_close && !service) {
		Dictionary closing = _weather->call(n.closed_by, ship->get(n.to_port));
		if (!closing.is_empty()) {
			_why[5]++;
			return false;
		}
	}
	double effort = speed * delta > 0.0 ? std::clamp((target - traveled) / (speed * delta), 0.0, 1.0) : 1.0;
	double new_maintenance = maintenance;
	Array route = ship->get(n.route);
	bool running = !route.is_empty() && !(bool)ship->get(n.paused);
	if (running || service) {
		new_maintenance = std::max(maintenance - (double)ship->get(n.wear_per_s) * (double)zone[2] * (double)storm[1] * delta * effort, 0.0);
	}
	double new_fuel = std::max((double)ship->get(n.fuel) - (double)ship->get(n.fuel_per_s) * (double)storm[0] * delta * effort, 0.0);
	bool lost = !service && (new_fuel <= 0.0 || new_maintenance <= 0.0);
	bool risk = !service && !lost && play_time >= (double)ship->get(n.risk_check_time);
	bool arrives = !lost && target >= (double)ship->get(n.leg_length);
	if (!events && (lost || risk || arrives)) {
		return false;
	}
	if (!(bool)ship->get(n.worked)) {
		ship->set(n.worked, true);
	}
	if (!String(ship->get(n.weather_wait)).is_empty()) {
		ship->set(n.weather_wait, String()); // (A storm that closed its port has eased.)
	}
	if (running || service) {
		ship->set(n.maintenance, new_maintenance);
	}
	ship->set(n.fuel, new_fuel);
	ship->set(n.traveled_nm, target);
	if (!service) {
		ship->set(n.sea_time, (double)ship->get(n.sea_time) + delta * effort);
		if (new_fuel <= 0.0) {
			_why[6]++;
			_state->call(n.lose, ship, "out of fuel");
			return true;
		}
		if (new_maintenance <= 0.0) {
			_why[6]++;
			_state->call(n.lose, ship, "broken down");
			return true;
		}
		if (risk) {
			ship->set(n.risk_check_time, play_time + _at_risk_check_s);
			_state->call(n.check_at_risk, ship);
		}
	}
	if (arrives) {
		_why[7]++;
		_state->call(n.arrive, ship, ship->get(n.to_port));
	}
	return true;
}

// True if GameState._advance() would do nothing for a ship in port this step
// (its first three checks, in its order): one waiting for money for a full
// load and not due another look, a tug or recovery boat standing by at its
// base, or a cargo ship lying idle at the anchorage.
bool ShipStepper::_idle_in_port(Object *ship, double play_time) {
	const Names &n = names();
	String docked_at = ship->get(n.docked_at);
	if (docked_at.is_empty()) {
		return false;
	}
	bool no_berth_phase = String(ship->get(n.berth_phase)).is_empty();
	if (!String(ship->get(n.load_wait)).is_empty() && play_time < (double)ship->get(n.load_check_time) && (bool)_state->call(n.short_of_load, ship) && no_berth_phase) {
		return true;
	}
	if ((double)ship->get(n.dock_time) >= 0.0 || !String(ship->get(n.hold_reason)).is_empty()) {
		return false;
	}
	int kind = ship->get(n.kind);
	if (kind < 0) {
		return false;
	}
	bool on_job = !String(ship->get(n.job_phase)).is_empty();
	if (docked_at == String(ship->get(n.base_port)) && (kind == _kind_recovery || kind == _kind_tug) && !on_job) {
		return true;
	}
	if ((int)ship->get(n.berth) < 0 && no_berth_phase && kind == _kind_cargo) {
		Array route = ship->get(n.route);
		bool running = !route.is_empty() && !(bool)ship->get(n.paused);
		return !running;
	}
	return false;
}


// True if GameState._advance() would do nothing for a ship this step because
// it's lost at sea waiting to be fetched (not on a tow, not an icebreaker).
bool ShipStepper::_adrift(Object *ship) {
	const Names &n = names();
	if (String(ship->get(n.lost_reason)).is_empty() || !String(ship->get(n.docked_at)).is_empty() || !String(ship->get(n.job_phase)).is_empty()) {
		return false;
	}
	int kind = ship->get(n.kind);
	return kind >= 0 && kind != _kind_icebreaker;
}

// GameState._step()'s `for ship in ships: _advance(ship, delta)`.
void ShipStepper::advance(const Array &ships, double delta) {
	const Names &n = names();
	double play_time = _state->get(n.play_time);
	bool can_close = _weather != nullptr && (bool)_weather->get(n.can_close);
	for (int i = 0; i < ships.size(); i++) {
		Object *ship = ships[i];
		if (ship == nullptr) {
			continue;
		}
		// (Read for each ship: an icebreaker before it may have opened or closed one.)
		bool any_closure = _icebreaking != nullptr && (bool)_icebreaking->get(n.any_open_closure);
		if (_idle_in_port(ship, play_time) || _adrift(ship)) {
			_idle_steps++;
		} else if (_sail(ship, delta, play_time, can_close, any_closure, true)) {
			_native_steps++;
		} else {
			_script_steps++;
			_state->call(n.advance, ship, delta);
		}
	}
}

Dictionary ShipStepper::counts() const {
	Dictionary out;
	out["native"] = _native_steps;
	out["script"] = _script_steps;
	out["idle_in_port"] = _idle_steps;
	const char *reasons[8] = { "new_leg", "canal", "convoy", "ice", "stats_refreshed", "port_closed", "lost", "arrived" };
	for (int i = 0; i < 8; i++) {
		out[reasons[i]] = _why[i];
	}
	return out;
}

void ShipStepper::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "state", "constants"), &ShipStepper::setup);
	ClassDB::bind_method(D_METHOD("advance", "ships", "delta"), &ShipStepper::advance);
	ClassDB::bind_method(D_METHOD("counts"), &ShipStepper::counts);
	ClassDB::bind_method(D_METHOD("try_sail", "ship", "delta"), &ShipStepper::try_sail);
}

// One ship's step done here if it's the plain case (see _sail()); for tests
// comparing it with GameState._advance().
bool ShipStepper::try_sail(Object *ship, double delta) {
	const Names &n = names();
	bool can_close = _weather != nullptr && (bool)_weather->get(n.can_close);
	bool any_closure = _icebreaking != nullptr && (bool)_icebreaking->get(n.any_open_closure);
	return _sail(ship, delta, _state->get(n.play_time), can_close, any_closure, false);
}
