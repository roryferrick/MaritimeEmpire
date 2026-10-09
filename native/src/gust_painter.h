// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <cstdint>
#include <unordered_map>

namespace godot {

// The wind's gusts on the map (MapView._draw_gusts()), natively: a pale
// streak now and then in each cell of the screen blowing the way the wind
// does there (Wind.at(): its noise is the same FastNoiseLite; storms' winds
// are asked of the GDScript, only where a storm reaches), all the streaks
// made as triangles and handed over in one call.
class GustPainter : public RefCounted {
	GDCLASS(GustPainter, RefCounted)

	struct Spot {
		int64_t cycle = INT64_MIN;
		double x = 0.0, y = 0.0, z = 0.0;
	};
	std::unordered_map<int64_t, double> _offsets;
	std::unordered_map<int64_t, Spot> _spots;

	double _offset(int col, int row);
	const Spot &_spot(int col, int row, int64_t cycle);

protected:
	static void _bind_methods();

public:
	void draw(const RID &canvas, const Dictionary &params);
};

} // namespace godot
