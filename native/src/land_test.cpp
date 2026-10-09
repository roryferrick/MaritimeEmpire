// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See land_test.h.
#include "land_test.h"

#include <godot_cpp/classes/geometry2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

// MapView._build_land_cells().
void LandTest::build(const PackedVector2Array &triangles, double cell) {
	_triangles = triangles;
	_cell = cell;
	_cells.clear();
	_bounds.clear();
	for (int64_t i = 0; i + 2 < triangles.size(); i += 3) {
		Rect2 box = Rect2(triangles[i], Vector2()).expand(triangles[i + 1]).expand(triangles[i + 2]);
		_bounds.push_back(box);
		int64_t x0 = UtilityFunctions::floori(box.position.x / cell);
		int64_t x1 = UtilityFunctions::floori((box.position.x + box.size.x) / cell);
		int64_t y0 = UtilityFunctions::floori(box.position.y / cell);
		int64_t y1 = UtilityFunctions::floori((box.position.y + box.size.y) / cell);
		for (int64_t x = x0; x <= x1; x++) {
			for (int64_t y = y0; y <= y1; y++) {
				_cells[_key(x, y)].push_back((int32_t)i);
			}
		}
	}
}

// MapView._on_land() for a point already projected (Geo.project()): its
// cell's triangles, each Godot's Geometry2D.point_is_inside_triangle()
// (worked out here as it does it, after a look at the triangle's bounds).
bool LandTest::contains(const Vector2 &p) const {
	auto found = _cells.find(_key(UtilityFunctions::floori(p.x / _cell), UtilityFunctions::floori(p.y / _cell)));
	if (found == _cells.end()) {
		return false;
	}
	const Vector2 *t = _triangles.ptr();
	const Rect2 *bounds = _bounds.data();
	for (int32_t i : found->second) {
		const Rect2 &box = bounds[i / 3];
		if (p.x < box.position.x || p.y < box.position.y || p.x > box.position.x + box.size.x || p.y > box.position.y + box.size.y) {
			continue;
		}
		const Vector2 an = t[i] - p;
		const Vector2 bn = t[i + 1] - p;
		const Vector2 cn = t[i + 2] - p;
		const bool orientation = an.cross(bn) > 0;
		if ((bn.cross(cn) > 0) != orientation) {
			continue;
		}
		if ((cn.cross(an) > 0) == orientation) {
			return true;
		}
	}
	return false;
}


namespace {
struct Marina {
	double lon = 0.0;
	double lat = 0.0;
	double angle = 0.0;
	double clear = 0.0; // Its circle's radius and half the jetty's width.
	double quay_inland = 0.0;
};

constexpr double SHIP_WORLD_ZOOM = 75.0;
constexpr double MAX_LAT = 85.0;
constexpr double PI_D = 3.1415926535897932384626433833;

// MapView._dock_lon_lat().
Vector2 dock_lon_lat(double lon, double lat, double angle, double flip, Vector2 local) {
	Vector2 off = Vector2(local.x, (real_t)(local.y * flip)).rotated((real_t)angle) / (real_t)SHIP_WORLD_ZOOM;
	return Vector2((real_t)(lon + off.x / MAX(UtilityFunctions::cos(Math::deg_to_rad(lat)), 0.05)), (real_t)(lat - off.y));
}

// MapView._in_marina_at().
bool in_marina(const Marina &m, Vector2 spot) {
	Vector2 off = Vector2((real_t)(UtilityFunctions::wrapf(spot.x - m.lon, -180.0, 180.0) * MAX(UtilityFunctions::cos(Math::deg_to_rad(m.lat)), 0.05)), (real_t)(m.lat - spot.y)) * (real_t)SHIP_WORLD_ZOOM;
	Vector2 local = off.rotated((real_t)-m.angle);
	double margin = m.clear * 0.1;
	return local.length() < m.clear + margin || (local.x <= margin && local.x >= m.quay_inland - margin && UtilityFunctions::absf(local.y) <= m.clear + margin);
}
} // namespace

// Geo.project() (as MapView._on_land() asks it).
static Vector2 project(Vector2 lon_lat) {
	double lat = Math::deg_to_rad(CLAMP((double)lon_lat.y, -MAX_LAT, MAX_LAT));
	return Vector2(lon_lat.x, (real_t)Math::rad_to_deg(UtilityFunctions::log(UtilityFunctions::tan(PI_D / 4.0 + lat / 2.0))));
}

// MapView._shore_spots()'s search, natively: [[the water's edge, a spot a
// little inland (or Vector2.INF where that isn't land)]] in dock units, or
// [] for none found (MapView then makes some up). port: {lon, lat, angle,
// flip, radius}; marinas: [{lon, lat, angle, clear, quay_inland}] (the port's
// own and those near it); samples, reach, seaward, inland: its SHORE_*.
Array LandTest::shore_spots(const Dictionary &port, const Array &marinas, int samples, double reach, double seaward, double inland_share) {
	double lon = port["lon"];
	double lat = port["lat"];
	double angle = port["angle"];
	double flip = port["flip"];
	double radius = port["radius"];
	std::vector<Marina> near;
	for (int64_t i = 0; i < marinas.size(); i++) {
		Dictionary d = marinas[i];
		near.push_back({ d["lon"], d["lat"], d["angle"], d["clear"], d["quay_inland"] });
	}
	// MapView._local_on_land().
	auto on_land = [&](Vector2 local, bool blocked) -> bool {
		Vector2 spot = dock_lon_lat(lon, lat, angle, flip, local);
		bool land = contains(project(Vector2((real_t)UtilityFunctions::wrapf(spot.x, -180.0, 180.0), spot.y)));
		if (land && blocked) {
			return true;
		}
		if (!land && !blocked) {
			return false;
		}
		for (const Marina &m : near) {
			if (in_marina(m, spot)) {
				return blocked;
			}
		}
		return !blocked;
	};
	Array out;
	for (int i = 0; i < samples; i++) {
		double y = UtilityFunctions::lerpf(-reach, reach, (i + 0.5) / samples) * radius;
		if (UtilityFunctions::absf(y) < radius * 1.05) {
			continue; // The marina's own.
		}
		// In from out at sea to the first land, then narrowed down.
		double sea_x = seaward * radius;
		if (on_land(Vector2((real_t)sea_x, (real_t)y), true)) {
			continue;
		}
		double land_x = INFINITY;
		for (int s = 1; s < 23; s++) {
			double x = UtilityFunctions::lerpf(seaward, -inland_share, s / 22.0) * radius;
			if (on_land(Vector2((real_t)x, (real_t)y), true)) {
				land_x = x;
				break;
			}
			sea_x = x;
		}
		if (land_x == INFINITY) {
			continue;
		}
		for (int n = 0; n < 6; n++) {
			double mid = (sea_x + land_x) / 2.0;
			if (on_land(Vector2((real_t)mid, (real_t)y), true)) {
				land_x = mid;
			} else {
				sea_x = mid;
			}
		}
		if (!on_land(Vector2((real_t)land_x, (real_t)y), false)) {
			continue; // (Up against a marina, not the shore.)
		}
		Vector2 inland = Vector2((real_t)(land_x - radius * 0.9), (real_t)y);
		Array spot;
		spot.push_back(Vector2((real_t)((sea_x + land_x) / 2.0), (real_t)y));
		spot.push_back(on_land(inland, false) ? inland : Vector2(INFINITY, INFINITY));
		out.push_back(spot);
	}
	return out;
}

void LandTest::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "triangles", "cell"), &LandTest::build);
	ClassDB::bind_method(D_METHOD("contains", "projected"), &LandTest::contains);
	ClassDB::bind_method(D_METHOD("shore_spots", "port", "marinas", "samples", "reach", "seaward", "inland"), &LandTest::shore_spots);
}
