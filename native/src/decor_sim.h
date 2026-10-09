// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

// The drawings on the land (MapView._draw_decor(): mountains, stands of
// trees, grass, scrub...), picked and drawn natively: the same ones, in the
// same places and order (nearer ones in front).
class DecorSim : public RefCounted {
	GDCLASS(DecorSim, RefCounted)

	PackedVector3Array _units;
	PackedInt32Array _kinds;
	PackedInt32Array _tiers;
	PackedFloat64Array _room;
	PackedByteArray _regions;
	std::vector<RID> _textures;
	double _bucket = 2.5;
	int _columns = 144;
	std::unordered_map<int64_t, std::vector<int32_t>> _buckets;

	static int64_t _cell(int column, int row) { return ((int64_t)column << 32) ^ (uint32_t)row; }

protected:
	static void _bind_methods();

public:
	void setup(const PackedVector2Array &positions, const PackedVector3Array &units, const PackedInt32Array &kinds, const PackedInt32Array &tiers,
			const PackedFloat64Array &room, const Array &textures, double bucket);
	void set_regions(const PackedByteArray &regions);
	void draw(const RID &canvas, const Dictionary &params);
};

} // namespace godot
