// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See lane_painter.h. The arithmetic is MapView._lane_pieces()' and
// _draw_line_runs()' (LaneMath.lane_on_screen(), visible_runs()).
#include "lane_painter.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
constexpr double PI_D = 3.141592653589793;
}

// constants: chunk (MapView.LANE_CHUNK), min_px (LINE_MIN_PX), hidden (HIDDEN).
void LanePainter::setup(const Dictionary &constants) {
	_chunk = std::max((int64_t)constants.get("chunk", 32), (int64_t)1);
	_min_px = constants.get("min_px", 1.5);
	_hidden = constants.get("hidden", Vector2(-1.0e5f, -1.0e5f));
}

// lanes: (from_port, to_port) -> [the bent lane's miles, its chunks' middles
// and spans (MapView._chunk_caps()), its points on the unit sphere], or []
// for no lane. ends: (from_port, to_port) -> [how far (nm) from each end the
// curves into and out of its ports' harbours take, [in, out]; the curve in
// and the curve out, each as points on the unit sphere], or [] where neither
// port's marina shows (the lane then runs straight to it).
void LanePainter::set_providers(const Callable &lanes, const Callable &ends) {
	_lane_provider = lanes;
	_ends_provider = ends;
}

// (Put off till the next pass: the map may ask while a pass is using a lane,
// bending lanes afresh when the ports' zones have changed.)
void LanePainter::forget_lanes() {
	_forget = true;
}

LanePainter::Lane &LanePainter::_lane(const String &from, const String &to) {
	String key = from + String(">") + to;
	Lane *found = _lanes.getptr(key);
	if (found != nullptr) {
		return *found;
	}
	// (Asked of the map before the lane's put in: the map may bend lanes afresh meanwhile.)
	Array made;
	if (_lane_provider.is_valid()) {
		made = _lane_provider.call(from, to);
	}
	Lane &lane = _lanes[key];
	{
		if (made.size() >= 4) {
			PackedFloat64Array miles = made[0];
			PackedVector3Array centers = made[1];
			PackedFloat64Array spans = made[2];
			PackedVector3Array units = made[3];
			lane.miles.assign(miles.ptr(), miles.ptr() + miles.size());
			lane.centers.assign(centers.ptr(), centers.ptr() + centers.size());
			lane.spans.assign(spans.ptr(), spans.ptr() + spans.size());
			lane.units.assign(units.ptr(), units.ptr() + units.size());
			lane.valid = !lane.miles.empty() && !lane.centers.empty() && lane.units.size() == lane.miles.size();
		}
	}
	if (lane.valid) {
		Vector3 sum;
		for (const Vector3 &u : lane.units) {
			sum += u;
		}
		lane.cap_center = sum.length() > 1.0e-6f ? sum.normalized() : lane.units.front();
		double furthest = 0.0;
		for (const Vector3 &u : lane.units) {
			furthest = std::max(furthest, (double)lane.cap_center.angle_to(u));
		}
		lane.cap_span = furthest;
	}
	return lane;
}

Vector2 LanePainter::_screen(const Vector3 &p) const {
	if (p.dot(_toward) < 0.0f) {
		return _hidden;
	}
	return _middle + Vector2(p.dot(_right), -p.dot(_up)) * (real_t)_radius;
}

// The lane's point `mile` along it on screen (between its points there).
Vector2 LanePainter::_at_mile(const Lane &lane, double mile) const {
	double length = lane.miles.back();
	mile = std::clamp(mile, 0.0, length);
	int64_t i = std::lower_bound(lane.miles.begin(), lane.miles.end(), mile) - lane.miles.begin();
	i = std::clamp(i, (int64_t)1, (int64_t)lane.miles.size() - 1);
	double span = lane.miles[i] - lane.miles[i - 1];
	double t = span > 0.0 ? (mile - lane.miles[i - 1]) / span : 1.0;
	return _screen(lane.units[i - 1].lerp(lane.units[i], (real_t)t).normalized());
}

void LanePainter::_append_curve(const PackedVector3Array &curve) {
	const Vector3 *p = curve.ptr();
	for (int64_t i = 0; i < curve.size(); i++) {
		_line.push_back(_screen(p[i]));
	}
}

// LaneMath.lane_on_screen(): the lane's points on screen from `start` to
// `stop` nm along it (both ends kept where start is 0 or there's no curve in
// at stop), its chunks that can't be in view broken off with one hidden point each.
void LanePainter::_append_middle(const Lane &lane, double start, double stop, bool curve_in) {
	const int64_t count = (int64_t)lane.units.size();
	for (size_t c = 0; c < lane.centers.size(); c++) {
		const int64_t first = (int64_t)c * _chunk;
		if (lane.centers[c].dot(_toward) < std::cos(std::min(_view_angle + lane.spans[c], PI_D))) {
			if (!_line.empty() && _line.back().x > _hidden.x / 2.0f) {
				_line.push_back(_hidden);
			}
			continue;
		}
		const int64_t last = std::min(first + _chunk, count);
		for (int64_t k = first; k < last; k++) {
			const double mile = lane.miles[k];
			if ((mile > start || (start <= 0.0 && k == 0)) && (mile < stop || (!curve_in && k == count - 1))) {
				_line.push_back(_screen(lane.units[k]));
			}
		}
	}
}

// LaneMath.visible_runs(), drawn: the line's runs on the near side of the
// globe (each at least two points), without points closer than _min_px to the
// last one kept (each run's ends always kept), each as one smooth line.
void LanePainter::_draw_line(const RID &canvas, const Color &color, double width) {
	RenderingServer *rs = RenderingServer::get_singleton();
	PackedColorArray colors;
	colors.push_back(color);
	const double min_sq = _min_px * _min_px;
	const int64_t count = (int64_t)_line.size();
	PackedVector2Array run;
	auto finish = [&]() {
		if (run.size() >= 2) {
			rs->canvas_item_add_polyline(canvas, run, colors, (real_t)width, true);
		}
		run = PackedVector2Array();
	};
	for (int64_t i = 0; i < count; i++) {
		const Vector2 &p = _line[(size_t)i];
		if (p.x <= _hidden.x / 2.0f) {
			finish();
			continue;
		}
		const bool run_ends = i + 1 >= count || _line[(size_t)i + 1].x <= _hidden.x / 2.0f;
		if (min_sq > 0.0 && run.size() > 0 && !run_ends && run[run.size() - 1].distance_squared_to(p) < min_sq) {
			continue;
		}
		run.push_back(p);
	}
	finish();
	_line.clear();
}

// The pass: `lanes` the lanes to draw, each [from_port, to_port, color, sailed
// both ways (the way back's curves too)]; params: toward, right, up (Vector3),
// radius, middle (Vector2), view_angle (radians from the view's middle a
// lane's chunk can show within), near_angle (the same for a port whose
// harbour curves could show), width. Returns how many lanes were drawn.
int64_t LanePainter::draw(const RID &canvas, const Array &lanes, const Dictionary &params) {
	if (_forget) {
		_forget = false;
		_lanes.clear();
	}
	_toward = params.get("toward", Vector3());
	_right = params.get("right", Vector3());
	_up = params.get("up", Vector3());
	_radius = params.get("radius", 1.0);
	_middle = params.get("middle", Vector2());
	_view_angle = params.get("view_angle", 0.0);
	_near_angle = params.get("near_angle", 0.0);
	double width = params.get("width", 1.5);
	int64_t drawn = 0;
	for (int64_t i = 0; i < lanes.size(); i++) {
		Array entry = lanes[i];
		if (entry.size() < 3) {
			continue;
		}
		String from = entry[0];
		String to = entry[1];
		Color color = entry[2];
		bool both_ways = entry.size() > 3 && (bool)entry[3];
		Lane &lane = _lane(from, to);
		if (!lane.valid) {
			continue;
		}
		if (lane.cap_center.dot(_toward) < std::cos(std::min(_view_angle + lane.cap_span, PI_D))) {
			continue; // (None of it can be in view.)
		}
		// Its ports' harbour curves, where a port's near the view (the map says
		// whether its marina shows, and keeps the curves).
		Array ends;
		bool from_near = lane.units.front().dot(_toward) >= std::cos(std::min(_near_angle, PI_D));
		bool to_near = lane.units.back().dot(_toward) >= std::cos(std::min(_near_angle, PI_D));
		if ((from_near || to_near) && _ends_provider.is_valid()) {
			ends = _ends_provider.call(from, to);
		}
		double reach_in = 0.0, reach_out = 0.0;
		PackedVector3Array curve_in, curve_out;
		if (ends.size() >= 3) {
			PackedFloat32Array reaches = ends[0];
			if (reaches.size() >= 2) {
				reach_in = reaches[0];
				reach_out = reaches[1];
			}
			curve_in = ends[1];
			curve_out = ends[2];
		}
		double length = lane.miles.back();
		double start = reach_out;
		double stop = length - reach_in;
		_line.clear();
		_append_curve(curve_out);
		if (start > 0.0) {
			_line.push_back(_at_mile(lane, start));
		}
		_append_middle(lane, start, stop, reach_in > 0.0);
		if (reach_in > 0.0) {
			_line.push_back(_at_mile(lane, stop));
		}
		_append_curve(curve_in);
		_draw_line(canvas, color, width);
		drawn++;
		if (both_ways && ends.size() >= 3 && _ends_provider.is_valid()) {
			// The way back's curves only (it shares this one's middle).
			Array back = _ends_provider.call(to, from);
			if (back.size() >= 3) {
				_line.clear();
				_append_curve(back[2]);
				_draw_line(canvas, color, width);
				_append_curve(back[1]);
				_draw_line(canvas, color, width);
			}
		}
	}
	return drawn;
}

void LanePainter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "constants"), &LanePainter::setup);
	ClassDB::bind_method(D_METHOD("set_providers", "lanes", "ends"), &LanePainter::set_providers);
	ClassDB::bind_method(D_METHOD("forget_lanes"), &LanePainter::forget_lanes);
	ClassDB::bind_method(D_METHOD("draw", "canvas", "lanes", "params"), &LanePainter::draw);
}
