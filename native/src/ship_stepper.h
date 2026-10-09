// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {

// One step of every ship (GameState._step()'s loop over the ships), with the
// commonest case worked out natively: a ship plainly sailing its leg (no canal
// on it, no convoy, its storm factors and stats already worked out, no storm
// closing ports and no ice closure anywhere, and not arriving, running out of
// fuel or maintenance, or due its at-risk check this step) moves, burns fuel
// and wears exactly as GameState._sail() would. Every other ship, and those
// cases, go to GameState._advance() as before, in the same order, so the
// game plays exactly the same.
class ShipStepper : public RefCounted {
	GDCLASS(ShipStepper, RefCounted)

	Object *_state = nullptr;
	Object *_weather = nullptr;
	Object *_icebreaking = nullptr;
	Array _open_sea_zone;
	double _min_recovery_speed = 0.05;
	int _kind_icebreaker = 2;
	int _kind_cargo = 0;
	double _at_risk_check_s = 1.0;
	int _kind_recovery = 1;
	int _kind_tug = 3;
	int64_t _idle_steps = 0;
	int64_t _native_steps = 0;
	int64_t _script_steps = 0;
	int64_t _why[8] = {};  // Why ships went to GameState (see counts()).


	bool _sail(Object *ship, double delta, double play_time, bool can_close, bool any_closure, bool events);
	bool _idle_in_port(Object *ship, double play_time);

protected:
	static void _bind_methods();

public:
	void setup(Object *state, const Dictionary &constants);
	void advance(const Array &ships, double delta);
	Dictionary counts() const;
	bool try_sail(Object *ship, double delta);
};

} // namespace godot
