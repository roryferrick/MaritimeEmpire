// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace godot {

// The globe art's triangle and line lists cut into tiles (see
// MapView._tiled()), so a view zoomed in draws only the tiles near it.
class GlobeTiles : public RefCounted {
	GDCLASS(GlobeTiles, RefCounted)

protected:
	static void _bind_methods();

public:
	// Shapes of `per_shape` points each (3: triangles, 2: line segments),
	// grouped by the cell_deg square (projected degrees) their first point's
	// in: [{points, colors (if any), box (the bounds of all its points)}, ...].
	static Array split(const PackedVector2Array &points, const PackedColorArray &colors, int64_t per_shape, double cell_deg);
};

} // namespace godot
