// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <cstdint>
#include <vector>

namespace godot {

// The fleet's lanes drawn in one pass (MapView._draw_active_lanes(), which
// drew each in GDScript: a big fleet has a hundred or more, drawn again every
// frame the map's dragged). Each lane: skipped whole when none of it can be
// in view; else its points on screen from where its curve out of its first
// port's harbour ends to where its curve into its last port's begins (the
// same as LaneMath.lane_on_screen()), the curves themselves (worked out by
// the map, only while marinas can show and only for a lane with a port on
// or near the screen, and only asked for then) before and after, cut into
// the runs on the near side of the globe (LaneMath.visible_runs()), all of
// them tessellated into one antialiased triangle batch (one draw call). The lanes' points on
// the sphere and their chunks are asked of the map once a lane and kept.
class LanePainter : public RefCounted {
	GDCLASS(LanePainter, RefCounted)

	struct Lane {
		bool valid = false;
		std::vector<double> miles;
		std::vector<Vector3> units;
		std::vector<Vector3> centers;
		std::vector<double> spans;
		Vector3 cap_center; // The whole lane's cap: its middle, and how far (radians) its furthest point is.
		double cap_span = 0.0;
	};

	HashMap<String, Lane> _lanes;
	bool _forget = false;
	// The lanes of the pass as last given (draw()'s epoch), each resolved to
	// its Lane: resolving them is string keys and lookups, every frame otherwise.
	struct Entry {
		Lane *lane = nullptr;
		Color color;
		bool both_ways = false;
		String from, to;
	};
	std::vector<Entry> _entries;
	int64_t _entries_epoch = -1;
	Callable _lane_provider;
	Callable _ends_provider;
	int64_t _chunk = 32;
	double _min_px = 1.5;
	Vector2 _hidden = Vector2(-1.0e5f, -1.0e5f);
	// The view of the pass being made (see draw()).
	Vector3 _toward, _right, _up;
	double _radius = 1.0;
	Vector2 _middle;
	double _view_angle = 0.0;
	std::vector<Vector2> _line;
	// The run being tessellated, and the pass's batch (see _emit_run()).
	std::vector<Vector2> _run;
	std::vector<Color> _batch_colors;
	std::vector<Vector2> _batch_points;
	std::vector<int32_t> _batch_indices;

	Lane &_lane(const String &from, const String &to);
	Vector2 _screen(const Vector3 &p) const;
	Vector2 _at_mile(const Lane &lane, double mile) const;
	// A lane's point t of the way from one of its points to the next, as the
	// ships sail it: straight in the map's projection (MapView._bent_sample()).
	static Vector3 _between(const Vector3 &a, const Vector3 &b, double t);
	// Longer than this on screen (px), a segment is drawn in pieces along that path.
	double _subdivide_px = 16.0;
	void _append_curve(const PackedVector3Array &curve);
	void _append_middle(const Lane &lane, double start, double stop, bool curve_in);
	void _draw_line(const RID &canvas, const Color &color, double width);
	void _emit_run(const Color &color, double width);

protected:
	static void _bind_methods();

public:
	void setup(const Dictionary &constants);
	void set_providers(const Callable &lanes, const Callable &ends);
	void forget_lanes();
	int64_t draw(const RID &canvas, const Array &lanes, const Dictionary &params);
};

} // namespace godot
