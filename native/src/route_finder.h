// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

// The AI rivals' loop finding (RivalAI._work_out_loops() and the legs, cargo
// and prices under it), worked out natively with the same arithmetic in the
// same order (and Godot's own maths functions and sort), so the same loops
// in the same order. Static facts about a pair of ports (miles, tolls, locks,
// convoys, sale factor, the seaway) are asked of the GDScript once and kept;
// what changes (prices' trade impacts, port sizes, a ship's leg times) is
// asked for each search.
class RouteFinder : public RefCounted {
	GDCLASS(RouteFinder, RefCounted)

	struct Pair {
		double miles = 0.0;
		double toll_share = 0.0;
		double lock_s = 0.0;
		double convoy_s = 0.0;
		double sale_factor = 1.0;
		bool seaway = false;
	};
	struct Port {
		double impact_factor = 1.0;
		double cost_factor = 1.0;
		bool fits = true;
		double lon = 0.0;
		double lat = 0.0;
	};
	struct Leg {
		bool sails = false;
		double money = 0.0;
		double seconds = 0.0;
	};

	HashMap<String, Pair> _pairs;
	HashMap<String, double> _bases;
	HashMap<String, double> _hashes;
	HashMap<String, double> _leg_seconds; // "a>b|top|wear" -> seconds

	// The search being worked out.
	Object *_provider = nullptr;
	Dictionary _context;
	Dictionary _hubs;
	Dictionary _impacts;
	Array _cargo;
	HashMap<String, Port> _ports;
	HashMap<String, double> _prices;
	HashMap<String, Leg> _legs;
	double _play_time = 0.0;
	String _model_id;

	const Pair &_pair(const String &a, const String &b);
	const Port &_port(const String &id);
	double _base(const String &port, const String &commodity);
	double _hash01(const String &text);
	double _drift(const String &port, const String &commodity);
	double _impact(const String &port, const String &commodity);
	double _sell_price(const String &port, const String &commodity);
	double _company_sell(const String &port, const String &commodity);
	double _company_buy(const String &port, const String &commodity);
	double _fuel_price(const String &port);
	double _seconds(const String &a, const String &b);
	bool _can_sail(const String &a, const String &b);
	Array _best_cargo(const String &a, const String &b);
	const Leg &_leg(const String &a, const String &b);
	double _loop_rate(const Array &loop);
	static bool _higher(const Variant &a, const Variant &b);

protected:
	static void _bind_methods();

public:
	Array work_out(Object *provider, const Dictionary &context);
	double loop_rate(Object *provider, const Dictionary &context, const Array &loop);
	void forget();
};

} // namespace godot
