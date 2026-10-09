// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>

namespace godot {

// Sea lanes' geometry (GameData's lanes, worked out natively): the same
// arithmetic as scripts/util/geo.gd and GameData.lane(), so the same numbers.
class LaneMath : public RefCounted {
	GDCLASS(LaneMath, RefCounted)

protected:
	static void _bind_methods();

public:
	// A lane's points (lon, lat) -> [its points projected (Geo.project()), the
	// nm from its start to each (Geo.distance_nm() between them, added up)].
	static Array lane_points(const PackedVector2Array &lon_lats);
	static Vector2 project(const Vector2 &lon_lat);
	static double distance_nm(const Vector2 &a, const Vector2 &b);
	static Rect2 lane_bounds(const PackedVector2Array &points);
	static Vector2 lane_position(const PackedVector2Array &points, const PackedFloat64Array &miles, double distance);
	static double mile_on_lane(const PackedVector2Array &points, const PackedFloat64Array &miles, const Vector2 &point, double on_lane);
	static Dictionary crossing(const PackedVector2Array &points, const PackedFloat64Array &miles, const Rect2 &bounds, const Dictionary &canal, double on_lane);
	static Array zones(const PackedVector2Array &points, const PackedFloat64Array &miles, const Array &slow, double rough_lat, double rough_wear);
	static Array with_harbor_speed(const Array &zones, double length, double top_speed, const Dictionary &settings);
	static double leg_seconds(const Array &zones, double start_mile, double end_mile, double start_maintenance, double top_speed, double wear_per_s);
};

} // namespace godot
