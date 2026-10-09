// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <cmath>
#include <cstdint>
#include <unordered_map>

namespace godot {

// The sea animals of the pods in view (MapView._draw_sea_animal() for each),
// natively: each one's place in its pod, kept off the land (by SeaLife's sea
// mask), its shadow under the water, and its surfacing, breaching or leaping
// (MapView._sea_event()'s rolls: the same random numbers) with splashes and
// blows. MapView works out the pods (where, which way) and keeps their clicks.
class SeaPainter : public RefCounted {
	GDCLASS(SeaPainter, RefCounted)

	struct Key {
		int64_t pod, animal, what, slot;
		bool operator==(const Key &o) const { return pod == o.pod && animal == o.animal && what == o.what && slot == o.slot; }
	};
	struct KeyHash {
		size_t operator()(const Key &k) const { return (size_t)((k.pod * 73856093) ^ (k.animal * 19349663) ^ (k.what * 83492791) ^ (k.slot * 2654435761u)); }
	};
	std::unordered_map<Key, double, KeyHash> _events;

	double _event(int64_t pod, int64_t animal, const String &what, int64_t what_id, double every, double chance, double seconds, double t);

protected:
	static void _bind_methods();

public:
	void draw(const RID &canvas, const Array &pods, const Array &kinds, const Dictionary &params);
};

} // namespace godot
