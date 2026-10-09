// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See gust_painter.h. Follows MapView._draw_gusts(), _gust_offset(),
// _gust_spot() and Wind.at() / prevailing().
#include "gust_painter.h"

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

namespace {
constexpr double GUST_SCALE = 3.2;
constexpr double GUST_RATE = 0.012;
constexpr double PI_D = 3.1415926535897932384626433833;
constexpr real_t FEATHER = 1.0f;

int64_t cell_key(int col, int row) {
	return ((int64_t)col << 32) ^ (uint32_t)row;
}

double smoothstep(double from, double to, double x) {
	return UtilityFunctions::smoothstep(from, to, x);
}

// Wind.prevailing().
Vector2 prevailing(double lat) {
	double hemisphere = lat >= 0.0 ? 1.0 : -1.0;
	double a = std::abs(lat);
	double trades = smoothstep(2.0, 9.0, a) * (1.0 - smoothstep(24.0, 33.0, a));
	double westerlies = smoothstep(30.0, 38.0, a) * (1.0 - smoothstep(58.0, 66.0, a));
	double polar = smoothstep(62.0, 70.0, a);
	Vector2 trade_wind = Vector2(-1.0f, (real_t)(-0.45 * hemisphere)).normalized() * 0.55f;
	Vector2 westerly_wind = Vector2(1.0f, (real_t)(0.3 * hemisphere)).normalized() * (hemisphere < 0.0 ? 0.95f : 0.7f);
	Vector2 polar_wind = Vector2(-1.0f, (real_t)(-0.25 * hemisphere)).normalized() * 0.45f;
	Vector2 calm(-0.12f, 0.0f);
	return calm + trade_wind * (real_t)trades + westerly_wind * (real_t)westerlies + polar_wind * (real_t)polar;
}

Vector3 unit(double lon_deg, double lat_deg) {
	double lon = Math::deg_to_rad(lon_deg);
	double lat = Math::deg_to_rad(lat_deg);
	return Vector3((real_t)(std::cos(lat) * std::cos(lon)), (real_t)(std::cos(lat) * std::sin(lon)), (real_t)std::sin(lat));
}
} // namespace

// MapView._gust_offset(): a cell's steady offset into the gust cycle.
double GustPainter::_offset(int col, int row) {
	int64_t key = cell_key(col, row);
	auto found = _offsets.find(key);
	if (found != _offsets.end()) {
		return found->second;
	}
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	Array parts;
	parts.push_back(col);
	parts.push_back(row);
	rng->set_seed(UtilityFunctions::hash(parts));
	double value = rng->randf();
	_offsets[key] = value;
	return value;
}

// MapView._gust_spot(): where in its cell a cell's gust is this cycle, and its roll.
const GustPainter::Spot &GustPainter::_spot(int col, int row, int64_t cycle) {
	Spot &spot = _spots[cell_key(col, row)];
	if (spot.cycle != cycle) {
		Ref<RandomNumberGenerator> rng;
		rng.instantiate();
		Array parts;
		parts.push_back(col);
		parts.push_back(row);
		parts.push_back(cycle);
		rng->set_seed(UtilityFunctions::hash(parts));
		spot.cycle = cycle;
		spot.x = rng->randf();
		spot.y = rng->randf();
		spot.z = rng->randf();
	}
	return spot;
}

// params: size, right, up, toward, radius (the view), play_time, noise
// (Wind's FastNoiseLite), storms ([[lon, lat, radius_nm]]), storm_wind (a
// Callable(storm index, lon_lat) -> Vector2: Wind.storm_wind()), cell_px,
// cycle_s, strength (Vector2), length_px (Vector2), alpha.
void GustPainter::draw(const RID &canvas, const Dictionary &params) {
	Vector2 size = params["size"];
	Vector3 right = params["right"];
	Vector3 up = params["up"];
	Vector3 toward = params["toward"];
	double globe = params["radius"];
	double t = params["play_time"];
	Ref<FastNoiseLite> noise = params["noise"];
	Array storms = params["storms"];
	Callable storm_wind = params["storm_wind"];
	double cell_px = params["cell_px"];
	double cycle_s = params["cycle_s"];
	Vector2 strength_range = params["strength"];
	Vector2 length_range = params["length_px"];
	double gust_alpha = params["alpha"];
	if (noise.is_null()) {
		return;
	}
	Vector2 middle = size / 2.0f;
	double reach = globe * 0.97;
	PackedVector2Array points;
	PackedColorArray colors;
	PackedInt32Array indices;
	int rows = (int)std::ceil(size.y / cell_px);
	int cols = (int)std::ceil(size.x / cell_px);
	for (int row = 0; row < rows; row++) {
		for (int col = 0; col < cols; col++) {
			double cycle = t / cycle_s + _offset(col, row);
			const Spot &spot = _spot(col, row, (int64_t)std::floor(cycle));
			Vector2 at = Vector2((real_t)(col + spot.x), (real_t)(row + spot.y)) * (real_t)cell_px;
			if (at.distance_to(middle) > reach) {
				continue;
			}
			// MapView._screen_lon_lat().
			Vector2 q = (at - middle) / (real_t)globe;
			q.y = -q.y;
			real_t d = q.length_squared();
			if (d > 1.0f) {
				q /= std::sqrt(d);
				d = 1.0f;
			}
			Vector3 p = right * q.x + up * q.y + toward * std::sqrt(1.0f - d);
			double lon = Math::rad_to_deg(std::atan2((double)p.y, (double)p.x));
			double lat = Math::rad_to_deg(std::asin(CLAMP((double)p.z, -1.0, 1.0)));
			// Wind.at().
			Vector2 wind = prevailing(lat);
			Vector3 n = unit(lon, lat) * (real_t)GUST_SCALE;
			double drift = t * GUST_RATE;
			double turn = noise->get_noise_3d(n.x + drift, n.y, n.z) * 0.9;
			double gust = 1.0 + noise->get_noise_3d(n.x + 40.0, n.y - drift, n.z + 17.0) * 0.6;
			wind = wind.rotated((real_t)turn) * (real_t)MAX(gust, 0.2);
			for (int64_t s = 0; s < storms.size(); s++) {
				Array storm = storms[s];
				// (Weather.strength_at()'s quick ruling out: too far north or south.)
				if (std::abs((double)storm[1] - lat) * 60.0 >= (double)storm[2]) {
					continue;
				}
				wind += (Vector2)storm_wind.call(s, Vector2((real_t)lon, (real_t)lat));
			}
			double strength = wind.length();
			if (spot.z > smoothstep(strength_range.x, strength_range.y, strength)) {
				continue;
			}
			// MapView._screen_way(): the wind's way on screen there.
			Vector2 dir = wind / (real_t)strength;
			double lon_r = Math::deg_to_rad(lon);
			Vector3 here = unit(lon, CLAMP(lat, -85.0, 85.0));
			Vector3 east((real_t)-std::sin(lon_r), (real_t)std::cos(lon_r), 0.0f);
			Vector3 along = east * dir.x + here.cross(east) * dir.y;
			Vector2 way = Vector2(along.dot(right), -along.dot(up)).normalized();
			double u = UtilityFunctions::fposmod(cycle, 1.0);
			double length = UtilityFunctions::lerpf(length_range.x, length_range.y, CLAMP(strength / 1.5, 0.0, 1.0));
			Vector2 head = at + way * (real_t)(length * u * 1.5);
			double alpha = std::sin(PI_D * u) * CLAMP(strength, 0.0, 1.2) * gust_alpha;
			// The streak (CanvasItem.draw_polyline_colors(), 1.5 px, antialiased): a
			// straight line fading in from its tail, as triangles with soft edges.
			Vector2 side = Vector2(way.y, -way.x);
			Vector2 along_points[3] = { head - way * (real_t)length, head - way * (real_t)(length * 0.4), head };
			Color along_colors[3] = { Color(1, 1, 1, 0.0f), Color(1, 1, 1, (real_t)(alpha * 0.6)), Color(1, 1, 1, (real_t)alpha) };
			real_t offsets[4] = { -(0.75f + FEATHER), -0.75f, 0.75f, 0.75f + FEATHER };
			int32_t first = (int32_t)points.size();
			for (int k = 0; k < 3; k++) {
				for (int e = 0; e < 4; e++) {
					points.push_back(along_points[k] + side * offsets[e]);
					Color c = along_colors[k];
					if (e == 0 || e == 3) {
						c.a = 0.0f;
					}
					colors.push_back(c);
				}
			}
			for (int k = 0; k < 2; k++) {
				for (int e = 0; e < 3; e++) {
					int32_t a = first + k * 4 + e;
					int32_t b = first + (k + 1) * 4 + e;
					indices.push_back(a);
					indices.push_back(a + 1);
					indices.push_back(b);
					indices.push_back(b);
					indices.push_back(a + 1);
					indices.push_back(b + 1);
				}
			}
		}
	}
	if (!indices.is_empty()) {
		RenderingServer::get_singleton()->canvas_item_add_triangle_array(canvas, indices, points, colors);
	}
}

void GustPainter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("draw", "canvas", "params"), &GustPainter::draw);
}
