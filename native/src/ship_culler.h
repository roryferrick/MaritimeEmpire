// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cstdint>
#include <vector>

namespace godot {

// A frame's pass over the whole fleet ahead of MapView._draw_ships(): which
// ships are to be drawn (those docked at a port whose marina shows, the
// service ships and any carried, towed or held at a canal, and the cargo
// ships plainly sailing whose stretch of lane could be in view), which ride
// on a recovery boat, which may want a lost or at-risk marker, and which tugs
// have a ship on their line. The same rules as the GDScript loops it replaces
// (MapView._ship_maybe_in_view(), _on_lane_in_view()), run natively, so a big
// fleet's few ships on screen don't cost a loop over every ship in GDScript
// each frame. The lanes' chunks (MapView._chunk_caps()) are asked of the map
// once a lane and kept. Zoomed out, a cargo ship plainly on its lane that's
// too small to make out (sort()'s dots) is drawn here as a dot in its colour
// where it is on its lane, all of them as one batch of triangles, and left
// out of the ships for the map to draw.
class ShipCuller : public RefCounted {
	GDCLASS(ShipCuller, RefCounted)

	struct Lane {
		bool valid = false;
		std::vector<double> miles;
		std::vector<Vector3> centers;
		std::vector<double> spans;
		std::vector<Vector3> units; // The bent lane's points on the unit sphere.
		std::vector<char> chunks; // 1 where a ship on the chunk could be in view, for the view _epoch.
		int64_t epoch = -1;
	};

	HashMap<String, Lane> _lanes;
	bool _forget = false;
	Callable _lane_provider;
	int _kind_cargo = 0;
	int _kind_tug = 3;
	int64_t _chunk = 24;
	std::vector<String> _held_states;
	// The view of the pass being made (see sort()).
	Vector3 _toward;
	double _view_angle = 0.0;
	// For a cargo ship plainly on its lane well away from either port (past
	// _end_zone nm, where no harbour curve moves it): just its own point.
	double _tight_angle = 0.0;
	double _end_zone = 0.0;
	double _end_slack = 0.0; // Room (radians) past the lens between such a ship's point and its port.
	int64_t _epoch = -1;

	Lane &_lane(const String &from, const String &to);
	bool _lane_in_view(const String &from, const String &to, double mile, bool plain);
	// A lane's point t of the way from one of its points to the next, as the
	// ships sail it: straight in the map's projection (MapView._bent_sample()).
	static Vector3 _between(const Vector3 &a, const Vector3 &b, double t);
	// A lane's point `mile` along it on the unit sphere.
	static Vector3 _at_mile(const Lane &lane, double mile);

protected:
	static void _bind_methods();

public:
	void setup(const Dictionary &constants);
	void set_lane_provider(const Callable &provider);
	void forget_lanes();
	Dictionary sort(const Array &order, const Dictionary &params);
};

} // namespace godot
