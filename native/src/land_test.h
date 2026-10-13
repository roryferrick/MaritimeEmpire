// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

// Whether a point is on the map's land (MapView._on_land()), natively: the
// land's triangles sorted into cells as MapView._build_land_cells() does,
// and Godot's own point-in-triangle test, so the same answers.
class LandTest : public RefCounted {
	GDCLASS(LandTest, RefCounted)

	PackedVector2Array _triangles;
	double _cell = 1.0;
	std::unordered_map<int64_t, std::vector<int32_t>> _cells;
	std::vector<Rect2> _bounds; // Each triangle's.

	static int64_t _key(int64_t x, int64_t y) { return (x << 32) ^ (y & 0xffffffffLL); }

protected:
	static void _bind_methods();

public:
	void build(const PackedVector2Array &triangles, double cell);
	bool contains(const Vector2 &projected) const;
	PackedFloat64Array land_runs(const PackedVector2Array &points, double step, double world_width) const;
	Array shore_spots(const Dictionary &port, const Array &marinas, int samples, double reach, double seaward, double inland_share);
};

} // namespace godot
