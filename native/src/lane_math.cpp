// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#include "lane_math.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <godot_cpp/classes/geometry2d.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

namespace {
constexpr double EARTH_RADIUS_NM = 3440.065;
constexpr double MAX_LAT = 85.0;
constexpr double PI_D = 3.1415926535897932384626433833;
constexpr double WORLD_WIDTH = 360.0;
} // namespace

// (Godot's own maths functions, as GDScript calls them, so the numbers are
// the same to the last bit: the C library's differ in the last place.)

// Geo.project().
Vector2 LaneMath::project(const Vector2 &lon_lat) {
	double lat = Math::deg_to_rad(CLAMP((double)lon_lat.y, -MAX_LAT, MAX_LAT));
	return Vector2(lon_lat.x, (real_t)Math::rad_to_deg(UtilityFunctions::log(UtilityFunctions::tan(PI_D / 4.0 + lat / 2.0))));
}

// Geo.distance_nm().
double LaneMath::distance_nm(const Vector2 &a, const Vector2 &b) {
	double lat1 = Math::deg_to_rad((double)a.y);
	double lat2 = Math::deg_to_rad((double)b.y);
	double dlat = lat2 - lat1;
	double dlon = Math::deg_to_rad((double)b.x - (double)a.x);
	double h = UtilityFunctions::pow(UtilityFunctions::sin(dlat / 2.0), 2.0) + UtilityFunctions::cos(lat1) * UtilityFunctions::cos(lat2) * UtilityFunctions::pow(UtilityFunctions::sin(dlon / 2.0), 2.0);
	return 2.0 * EARTH_RADIUS_NM * UtilityFunctions::asin(MIN(1.0, UtilityFunctions::sqrt(h)));
}

Array LaneMath::lane_points(const PackedVector2Array &lon_lats) {
	PackedVector2Array points;
	PackedFloat64Array miles;
	points.resize(lon_lats.size());
	miles.resize(lon_lats.size());
	double total = 0.0;
	for (int64_t i = 0; i < lon_lats.size(); i++) {
		if (i > 0) {
			total += distance_nm(lon_lats[i - 1], lon_lats[i]);
		}
		points.set(i, project(lon_lats[i]));
		miles.set(i, total);
	}
	Array out;
	out.push_back(points);
	out.push_back(miles);
	return out;
}


// Geo.unproject()'s latitude, as the Vector2 it makes holds it.
static double unprojected_lat(double y) {
	return (double)(real_t)Math::rad_to_deg(2.0 * UtilityFunctions::atan(UtilityFunctions::exp(Math::deg_to_rad(y))) - PI_D / 2.0);
}

// GameData.SeaLane.bounds().
Rect2 LaneMath::lane_bounds(const PackedVector2Array &points) {
	Rect2 bounds(points[0], Vector2());
	for (int64_t i = 0; i < points.size(); i++) {
		bounds = bounds.expand(points[i]);
	}
	return bounds;
}

// GameData.SeaLane.sample(distance)[0]: where a ship is `distance` nm along it.
Vector2 LaneMath::lane_position(const PackedVector2Array &points, const PackedFloat64Array &miles, double distance) {
	distance = CLAMP(distance, 0.0, miles[miles.size() - 1]);
	int64_t i = std::lower_bound(miles.ptr(), miles.ptr() + miles.size(), distance) - miles.ptr();
	i = CLAMP(i, (int64_t)1, points.size() - 1);
	double span = miles[i] - miles[i - 1];
	double t = span > 0.0 ? (distance - miles[i - 1]) / span : 1.0;
	return points[i - 1].lerp(points[i], (real_t)t);
}

// GameData._mile_on_lane().
double LaneMath::mile_on_lane(const PackedVector2Array &points, const PackedFloat64Array &miles, const Vector2 &point, double on_lane) {
	Geometry2D *geometry = Geometry2D::get_singleton();
	for (int64_t i = 1; i < points.size(); i++) {
		Vector2 a = points[i - 1];
		Vector2 b = points[i];
		Vector2 p((real_t)((double)point.x + UtilityFunctions::roundf(((double)a.x - (double)point.x) / WORLD_WIDTH) * WORLD_WIDTH), point.y);
		Vector2 q = geometry->get_closest_point_to_segment(p, a, b);
		if ((double)q.distance_to(p) <= on_lane) {
			double t = a != b ? (double)a.distance_to(q) / (double)a.distance_to(b) : 0.0;
			return UtilityFunctions::lerpf(miles[i - 1], miles[i], t);
		}
	}
	return -1.0;
}

// GameData._crossing(): a lane's crossing of a canal, or {}.
Dictionary LaneMath::crossing(const PackedVector2Array &points, const PackedFloat64Array &miles, const Rect2 &bounds, const Dictionary &canal, double on_lane) {
	Dictionary none;
	PackedVector2Array path = canal["projected_path"];
	Rect2 rect = canal["bounds"];
	bool near = false;
	for (double shift : { -WORLD_WIDTH, 0.0, WORLD_WIDTH }) {
		if (bounds.intersects(Rect2(rect.position + Vector2((real_t)shift, 0.0f), rect.size))) {
			near = true;
			break;
		}
	}
	if (!near) {
		return none;
	}
	std::vector<Dictionary> stops;
	Array chambers = canal["chambers"];
	for (int64_t c = 0; c < chambers.size(); c++) {
		Dictionary chamber = chambers[c];
		double mile = mile_on_lane(points, miles, chamber["position"], on_lane);
		if (mile < 0.0) {
			return none;
		}
		Dictionary stop;
		stop["index"] = chamber["index"];
		stop["lock"] = chamber["lock"];
		stop["mile"] = mile;
		stops.push_back(stop);
	}
	if (stops.empty()) {
		for (int64_t i : { (int64_t)UtilityFunctions::floori(path.size() * 0.25), (int64_t)UtilityFunctions::floori(path.size() * 0.75) }) {
			if (mile_on_lane(points, miles, path[i], on_lane) < 0.0) {
				return none;
			}
		}
	}
	double first_mile = INFINITY;
	int64_t first_vertex = -1;
	double last_mile = -INFINITY;
	int64_t last_vertex = -1;
	for (int64_t i = 0; i < path.size(); i++) {
		double mile = mile_on_lane(points, miles, path[i], on_lane);
		if (mile < 0.0) {
			continue;
		}
		if (mile < first_mile) {
			first_mile = mile;
			first_vertex = i;
		}
		if (mile > last_mile) {
			last_mile = mile;
			last_vertex = i;
		}
	}
	bool forward = first_vertex < last_vertex;
	double start_nm = first_mile;
	double end_nm = last_mile;
	if (!stops.empty()) {
		std::sort(stops.begin(), stops.end(), [](const Dictionary &a, const Dictionary &b) { return (double)a["mile"] < (double)b["mile"]; });
		start_nm = MIN(start_nm, (double)stops.front()["mile"]);
		end_nm = MAX(end_nm, (double)stops.back()["mile"]);
	}
	PackedFloat64Array path_nm = canal["path_nm"];
	int64_t vertex = first_vertex >= 0 ? first_vertex : path_nm.size() - 1; // (As GDScript reads [-1]: the last.)
	Array stop_list;
	for (const Dictionary &stop : stops) {
		stop_list.push_back(stop);
	}
	Dictionary out;
	out["canal"] = canal;
	out["forward"] = forward;
	out["start_nm"] = start_nm;
	out["end_nm"] = end_nm;
	out["chambers"] = stop_list;
	out["join_s"] = path_nm[vertex] + (first_mile - start_nm) * (forward ? -1.0 : 1.0);
	return out;
}

// GameData.lane_zones() from a lane and its slow stretches ([[start nm, end
// nm, speed factor]], from its canal crossings): [[end mile, speed, wear]].
Array LaneMath::zones(const PackedVector2Array &points, const PackedFloat64Array &miles, const Array &slow, double rough_lat, double rough_wear) {
	std::vector<double> breaks;
	breaks.push_back(miles[miles.size() - 1]);
	for (int64_t i = 1; i < points.size(); i++) {
		bool a = unprojected_lat(points[i - 1].y) < rough_lat;
		bool b = unprojected_lat(points[i].y) < rough_lat;
		if (a != b) {
			breaks.push_back(UtilityFunctions::lerpf(miles[i - 1], miles[i], 0.5));
		}
	}
	for (int64_t s = 0; s < slow.size(); s++) {
		Array stretch = slow[s];
		breaks.push_back(stretch[0]);
		breaks.push_back(stretch[1]);
	}
	std::sort(breaks.begin(), breaks.end());
	Array out;
	double previous = 0.0;
	for (double mile : breaks) {
		if (mile <= previous + 0.0001) {
			continue;
		}
		double middle = (previous + mile) / 2.0;
		double speed = 1.0;
		for (int64_t s = 0; s < slow.size(); s++) {
			Array stretch = slow[s];
			if (middle > (double)stretch[0] && middle < (double)stretch[1]) {
				speed = stretch[2];
			}
		}
		double wear = unprojected_lat(lane_position(points, miles, middle).y) < rough_lat ? rough_wear : 1.0;
		Array zone;
		zone.push_back(mile);
		zone.push_back(speed);
		zone.push_back(wear);
		out.push_back(zone);
		previous = mile;
	}
	return out;
}


// Ship._seconds_at().
static double seconds_at(double distance, double m, double v, double w) {
	if (distance <= 0.0) {
		return 0.0;
	}
	if (v <= 0.0 || m <= 0.0) {
		return INFINITY;
	}
	if (w <= 0.0) {
		return distance / (v * m);
	}
	double discriminant = m * m - 2.0 * w * distance / v;
	if (discriminant < 0.0) {
		return INFINITY;
	}
	return (m - UtilityFunctions::sqrt(discriminant)) / w;
}

// Ship._with_harbor_speed(): a lane's zones with a ship's harbor speed laid over each end.
Array LaneMath::with_harbor_speed(const Array &zones, double length, double top_speed, const Dictionary &settings) {
	double start = settings.get("start", 1.0);
	int64_t steps = settings.get("steps", 0);
	double ramp = MIN(top_speed * (double)settings.get("seconds", 0.0) * (1.0 + start) / 2.0, length / 2.0);
	if (zones.is_empty() || steps <= 0 || start >= 1.0 || ramp <= 0.0) {
		return zones;
	}
	std::vector<double> breaks;
	for (int64_t i = 0; i < zones.size(); i++) {
		breaks.push_back(((Array)zones[i])[0]);
	}
	for (int64_t k = 1; k <= steps; k++) {
		breaks.push_back(ramp * k / steps);
		breaks.push_back(length - ramp * k / steps);
	}
	std::sort(breaks.begin(), breaks.end());
	Array out;
	double previous = 0.0;
	for (double mile : breaks) {
		if (mile <= previous + 0.0001) {
			continue;
		}
		double middle = (previous + mile) / 2.0;
		Array lane_zone = zones[zones.size() - 1];
		for (int64_t i = 0; i < zones.size(); i++) {
			Array zone = zones[i];
			if (middle < (double)zone[0]) {
				lane_zone = zone;
				break;
			}
		}
		double from_port_end = MIN(middle, length - middle);
		double harbor = from_port_end < ramp ? UtilityFunctions::sqrt(start * start + (1.0 - start * start) * from_port_end / ramp) : 1.0;
		Array piece;
		piece.push_back(mile);
		piece.push_back((double)lane_zone[1] * harbor);
		piece.push_back(lane_zone[2]);
		out.push_back(piece);
		previous = mile;
	}
	return out;
}

// Ship._leg_seconds() over a leg's zones (with its harbor speed).
double LaneMath::leg_seconds(const Array &zones, double start_mile, double end_mile, double start_maintenance, double top_speed, double wear_per_s) {
	double seconds = 0.0;
	double m = start_maintenance;
	double mile = start_mile;
	for (int64_t i = 0; i < zones.size(); i++) {
		Array zone = zones[i];
		if (mile >= end_mile - 0.0001) {
			break;
		}
		if ((double)zone[0] <= mile) {
			continue;
		}
		double piece = MIN((double)zone[0], end_mile) - mile;
		double t = seconds_at(piece, m, top_speed * (double)zone[1], wear_per_s * (double)zone[2]);
		if (t == INFINITY) {
			return INFINITY;
		}
		seconds += t;
		m -= wear_per_s * (double)zone[2] * t;
		mile += piece;
	}
	return seconds;
}

void LaneMath::_bind_methods() {
	ClassDB::bind_static_method("LaneMath", D_METHOD("lane_points", "lon_lats"), &LaneMath::lane_points);
	ClassDB::bind_static_method("LaneMath", D_METHOD("project", "lon_lat"), &LaneMath::project);
	ClassDB::bind_static_method("LaneMath", D_METHOD("distance_nm", "a", "b"), &LaneMath::distance_nm);
	ClassDB::bind_static_method("LaneMath", D_METHOD("lane_bounds", "points"), &LaneMath::lane_bounds);
	ClassDB::bind_static_method("LaneMath", D_METHOD("lane_position", "points", "miles", "distance"), &LaneMath::lane_position);
	ClassDB::bind_static_method("LaneMath", D_METHOD("mile_on_lane", "points", "miles", "point", "on_lane"), &LaneMath::mile_on_lane);
	ClassDB::bind_static_method("LaneMath", D_METHOD("crossing", "points", "miles", "bounds", "canal", "on_lane"), &LaneMath::crossing);
	ClassDB::bind_static_method("LaneMath", D_METHOD("zones", "points", "miles", "slow", "rough_lat", "rough_wear"), &LaneMath::zones);
	ClassDB::bind_static_method("LaneMath", D_METHOD("with_harbor_speed", "zones", "length", "top_speed", "settings"), &LaneMath::with_harbor_speed);
	ClassDB::bind_static_method("LaneMath", D_METHOD("leg_seconds", "zones", "start_mile", "end_mile", "start_maintenance", "top_speed", "wear_per_s"), &LaneMath::leg_seconds);
}
