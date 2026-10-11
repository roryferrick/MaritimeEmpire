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
#include <godot_cpp/variant/rect2.hpp>
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
	// One texture holding all of them (see set_atlas()), and where each is in it.
	RID _atlas;
	Vector2 _atlas_size;
	std::vector<Rect2> _atlas_regions;
	// The season (see set_seasons()): each kind's texture before and now (and
	// in the snow), per hemisphere, how far the change has come, and the snow line.
	PackedInt32Array _before[2], _now[2], _snow[2];
	double _mix[2] = { 1.0, 1.0 };
	double _snow_lat[2] = { 999.0, 999.0 };
	bool _seasons = false;
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
	// Every drawing's art in one texture of atlas_size px (regions: a Rect2
	// for each of setup()'s textures, px), so all the drawings in view go
	// down as one batch of triangles: one call, one draw call.
	void set_atlas(const RID &atlas, const Array &regions, const Vector2 &atlas_size);
	// The season's textures (indexes into setup()'s textures) by kind: before
	// and now (drawings change over from one to the other as mix goes 0 to 1,
	// each at its own moment), and in the snow (beyond snow_lat degrees from the
	// equator), for the north (0) and south (1).
	void set_seasons(const Dictionary &north, const Dictionary &south);
	void draw(const RID &canvas, const Dictionary &params);
};

} // namespace godot
