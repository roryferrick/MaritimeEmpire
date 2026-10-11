// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

// The sea animals of the pods in view (MapView._draw_sea_animal() for each),
// natively: each one's place in its pod, kept off the land (by SeaLife's sea
// mask), its shadow under the water, and its surfacing, breaching or leaping
// (MapView._sea_event()'s rolls: the same random numbers) with splashes and
// blows. The pods are kept here as the map last worked them out (set_pod():
// where, which way, within what cap till they're worked out again), so a
// frame's pass over them (which are near the view: near(); drawing those in
// it, each eased round to its heading: draw_pods()) costs no loop in
// GDScript. The map keeps their clicks from draw_pods()' hits.
class SeaPainter : public RefCounted {
	GDCLASS(SeaPainter, RefCounted)

	struct Frame;
	struct Pod {
		bool known = false;
		Vector3 unit; // Where it is.
		Vector3 cap; // The cap it stays within till it's worked out again...
		real_t margin = 0.0f; // ...this far (radians) round cap.
		Vector2 heading; // Which way it goes (east, north), or zero.
		real_t angle = 0.0f; // Which way it faces on screen, eased.
		bool angled = false;
		int32_t kind = -1;
		int32_t shown = 0;
	};
	std::vector<Pod> _pods;
	void _draw_pod(const Frame &frame, int64_t index, Vector2 center, real_t angle, const Dictionary &kind, int64_t shown, double t, real_t scale);

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
	void set_count(int64_t count);
	void set_pod(int64_t index, const Vector3 &unit, const Vector3 &cap, double margin, const Vector2 &heading, int64_t kind, int64_t shown);
	PackedInt32Array near(const Dictionary &params);
	PackedFloat32Array draw_pods(const RID &canvas, const Array &kinds, const Dictionary &params);
};

} // namespace godot
