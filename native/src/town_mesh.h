// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cstdint>
#include <vector>

namespace godot {

// A town's blocks, roads and parks as triangles (MapView._town_mesh(), which
// built them in GDScript: a big town is thousands of quads, and a few ms
// there is a hitch as a port scrolls in). The same shapes in the same order,
// in dock units: the roads (an avenue with its dashes), every building's
// shadow, the parks, then each building's walls and roof by its kind
// (pitched, pagoda, warehouse, tall, flat with roof gear); a landmark's
// walls go in and its index is handed back for the map to draw its details after.
class TownMesh : public RefCounted {
	GDCLASS(TownMesh, RefCounted)

	std::vector<Vector2> _points;
	std::vector<Color> _colors;
	std::vector<int32_t> _indices;

	void _quad(const Rect2 &rect, const Color &color);
	void _quad_points(const Vector2 *p, const Color &color);
	void _disc(Vector2 center, real_t r, const Color &color, int steps);

protected:
	static void _bind_methods();

public:
	// roads: [[Rect2, kind], ...]; buildings: [[Rect2, wall, roof, height, kind, salt], ...];
	// parks: [[Vector2, radius], ...]; drop: the shadows' offset per unit of
	// height (dock units); colors: {walk, road, lane, shadow, park}. Gives
	// {points, colors, indices, landmarks (the buildings' places in `buildings`)}.
	Dictionary build(const Array &roads, const Array &buildings, const Array &parks, const Vector2 &drop, const Dictionary &colors);
};

} // namespace godot
