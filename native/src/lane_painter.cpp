// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See lane_painter.h. The arithmetic is MapView._lane_pieces()' and
// _draw_line_runs()' (LaneMath.lane_on_screen(), visible_runs()).
#include "lane_painter.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2.hpp>

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
	_entries.clear();
	_entries_epoch = -1;
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
// Straight in Web Mercator between the two (longitude and northing lerped), as
// MapView._bent_sample() places a ship between its lane's points, so the line
// drawn and the dots on it agree even on a long open-ocean segment.
Vector3 LanePainter::_between(const Vector3 &a, const Vector3 &b, double t) {
	double lon_a = std::atan2((double)a.y, (double)a.x);
	double lon_b = std::atan2((double)b.y, (double)b.x);
	double d = lon_b - lon_a;
	if (d > PI_D) {
		d -= 2.0 * PI_D;
	} else if (d < -PI_D) {
		d += 2.0 * PI_D;
	}
	double lon = lon_a + d * t;
	double m = std::atanh(std::clamp((double)a.z, -0.9999, 0.9999)) * (1.0 - t) + std::atanh(std::clamp((double)b.z, -0.9999, 0.9999)) * t;
	double c = 1.0 / std::cosh(m);
	return Vector3((real_t)(c * std::cos(lon)), (real_t)(c * std::sin(lon)), (real_t)std::tanh(m));
}

Vector2 LanePainter::_at_mile(const Lane &lane, double mile) const {
	double length = lane.miles.back();
	mile = std::clamp(mile, 0.0, length);
	int64_t i = std::lower_bound(lane.miles.begin(), lane.miles.end(), mile) - lane.miles.begin();
	i = std::clamp(i, (int64_t)1, (int64_t)lane.miles.size() - 1);
	double span = lane.miles[i] - lane.miles[i - 1];
	double t = span > 0.0 ? (mile - lane.miles[i - 1]) / span : 1.0;
	return _screen(_between(lane.units[i - 1], lane.units[i], t));
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
	int64_t prev_k = -2; // The lane point last pushed (so a segment is only split from its own start).
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
				Vector2 at = _screen(lane.units[k]);
				// A long segment from the point before (the last one pushed) in
				// pieces along the path the ships sail, so it bends with the globe as they do.
				if (prev_k == k - 1 && !_line.empty() && _line.back().x > _hidden.x / 2.0f && at.x > _hidden.x / 2.0f) {
					double far = (double)_line.back().distance_to(at);
					if (far > _subdivide_px) {
						int pieces = (int)std::min(std::ceil(far / _subdivide_px), 24.0);
						for (int j = 1; j < pieces; j++) {
							_line.push_back(_screen(_between(lane.units[k - 1], lane.units[k], (double)j / pieces)));
						}
					}
				}
				_line.push_back(at);
				prev_k = k;
			}
		}
	}
}

// LaneMath.visible_runs(), batched: the line's runs on the near side of the
// globe (each at least two points), simplified (a point is dropped while the
// line through its neighbours passes within _min_px of it: zoomed out, a
// great circle's many points go, a bend round a coast stays; each run's ends
// always kept), each tessellated into the pass's one triangle batch (see
// _emit_run()).
void LanePainter::_draw_line(const RID &canvas, const Color &color, double width) {
	const double tol_sq = _min_px * _min_px;
	const int64_t count = (int64_t)_line.size();
	_run.clear();
	bool held = false; // A point kept back: dropped if the next keeps the line within _min_px of it.
	Vector2 candidate;
	auto finish = [&]() {
		if (held) {
			_run.push_back(candidate);
			held = false;
		}
		if (_run.size() >= 2) {
			_emit_run(color, width);
		}
		_run.clear();
	};
	for (int64_t i = 0; i < count; i++) {
		const Vector2 &p = _line[(size_t)i];
		if (p.x <= _hidden.x / 2.0f) {
			finish();
			continue;
		}
		if (_run.empty()) {
			_run.push_back(p);
			continue;
		}
		if (!held) {
			candidate = p;
			held = true;
			continue;
		}
		const Vector2 &a = _run.back();
		const Vector2 d = p - a;
		const real_t len_sq = d.length_squared();
		const Vector2 c = candidate - a;
		real_t dev_sq;
		if (len_sq > 1.0e-6f) {
			const real_t cross = d.x * c.y - d.y * c.x;
			const real_t along = d.dot(c);
			dev_sq = (along < 0.0f || along > len_sq) ? MIN(c.length_squared(), (candidate - p).length_squared()) : cross * cross / len_sq;
		} else {
			dev_sq = c.length_squared();
		}
		if (dev_sq <= tol_sq) {
			candidate = p; // (The held point lies on the line to this one: dropped.)
		} else {
			_run.push_back(candidate);
			candidate = p;
		}
	}
	finish();
	_line.clear();
}

// A run as a ribbon `width` wide with a feather a pixel wide fading out
// each side (antialiased like a polyline), its corners mitred (clamped at
// sharp turns): four vertices a point, six triangles a segment, appended to
// the batch.
void LanePainter::_emit_run(const Color &color, double width) {
	const int64_t n = (int64_t)_run.size();
	const real_t half = (real_t)(width / 2.0);
	const real_t feather = 1.0f;
	Color clear = color;
	clear.a = 0.0f;
	const int32_t base = (int32_t)_batch_points.size();
	for (int64_t i = 0; i < n; i++) {
		Vector2 dir_in = i > 0 ? (_run[(size_t)i] - _run[(size_t)i - 1]).normalized() : Vector2();
		Vector2 dir_out = i < n - 1 ? (_run[(size_t)i + 1] - _run[(size_t)i]).normalized() : Vector2();
		Vector2 t = dir_in + dir_out;
		if (t.length_squared() < 1.0e-12f) {
			t = dir_out.length_squared() > 0.0f ? dir_out : dir_in;
		}
		t.normalize();
		Vector2 nrm(-t.y, t.x);
		real_t scale = 1.0f;
		if (i > 0 && i < n - 1) {
			real_t c = nrm.dot(Vector2(-dir_out.y, dir_out.x));
			scale = 1.0f / std::max(c, 0.5f);
		}
		const Vector2 &p = _run[(size_t)i];
		Vector2 outer = nrm * (half + feather) * scale;
		Vector2 inner = nrm * half * scale;
		_batch_points.push_back(p - outer);
		_batch_colors.push_back(clear);
		_batch_points.push_back(p - inner);
		_batch_colors.push_back(color);
		_batch_points.push_back(p + inner);
		_batch_colors.push_back(color);
		_batch_points.push_back(p + outer);
		_batch_colors.push_back(clear);
	}
	for (int64_t i = 1; i < n; i++) {
		const int32_t a = base + (int32_t)(4 * (i - 1));
		const int32_t b = base + (int32_t)(4 * i);
		for (int32_t s = 0; s < 3; s++) {
			_batch_indices.push_back(a + s);
			_batch_indices.push_back(b + s);
			_batch_indices.push_back(b + s + 1);
			_batch_indices.push_back(a + s);
			_batch_indices.push_back(b + s + 1);
			_batch_indices.push_back(a + s + 1);
		}
	}
}

// The pass: `lanes` the lanes to draw, each [from_port, to_port, color, sailed
// both ways (the way back's curves too)]; params: toward, right, up (Vector3),
// radius, middle (Vector2), view_angle (radians from the view's middle a
// lane's chunk can show within), curves (whether any port's marina can show
// at this zoom: only then are a lane's harbour curves asked of the map, and
// only for a port on screen or within `near`, a Rect2), width, epoch (a
// count the map raises when `lanes` changes: they're resolved to their
// Lanes once an epoch). All the lanes go down as one batch of triangles
// (one call into the rendering server, one draw call). Returns how many
// lanes were drawn.
int64_t LanePainter::draw(const RID &canvas, const Array &lanes, const Dictionary &params) {
	if (_forget) {
		_forget = false;
		_lanes.clear();
		_entries.clear();
		_entries_epoch = -1;
	}
	int64_t epoch = params.get("epoch", -1);
	if (epoch < 0 || epoch != _entries_epoch || _entries.size() != (size_t)lanes.size()) {
		// (Every lane put in first, then pointed to: the map's lanes don't move once in.)
		_entries.clear();
		for (int64_t i = 0; i < lanes.size(); i++) {
			Array entry = lanes[i];
			if (entry.size() < 3) {
				continue;
			}
			Entry e;
			e.from = entry[0];
			e.to = entry[1];
			e.color = entry[2];
			e.both_ways = entry.size() > 3 && (bool)entry[3];
			_lane(e.from, e.to);
			_entries.push_back(e);
		}
		for (Entry &e : _entries) {
			e.lane = &_lane(e.from, e.to);
		}
		_entries_epoch = epoch;
	}
	_toward = params.get("toward", Vector3());
	_right = params.get("right", Vector3());
	_up = params.get("up", Vector3());
	_radius = params.get("radius", 1.0);
	_middle = params.get("middle", Vector2());
	_view_angle = params.get("view_angle", 0.0);
	bool curves = params.get("curves", false);
	Rect2 near = params.get("near", Rect2());
	double width = params.get("width", 1.5);
	int64_t drawn = 0;
	_batch_points.clear();
	_batch_colors.clear();
	_batch_indices.clear();
	for (const Entry &e : _entries) {
		const String &from = e.from;
		const String &to = e.to;
		const Color &color = e.color;
		bool both_ways = e.both_ways;
		Lane &lane = *e.lane;
		if (!lane.valid) {
			continue;
		}
		if (lane.cap_center.dot(_toward) < std::cos(std::min(_view_angle + lane.cap_span, PI_D))) {
			continue; // (None of it can be in view.)
		}
		// Its ports' harbour curves, where a port's near the view (the map says
		// whether its marina shows, and keeps the curves).
		Array ends;
		if (curves && _ends_provider.is_valid()) {
			Vector2 from_at = _screen(lane.units.front());
			Vector2 to_at = _screen(lane.units.back());
			bool from_near = from_at.x > _hidden.x / 2.0f && near.has_point(from_at);
			bool to_near = to_at.x > _hidden.x / 2.0f && near.has_point(to_at);
			if (from_near || to_near) {
				ends = _ends_provider.call(from, to);
			}
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
	if (!_batch_indices.empty()) {
		PackedVector2Array points;
		PackedColorArray colors;
		PackedInt32Array indices;
		points.resize((int64_t)_batch_points.size());
		colors.resize((int64_t)_batch_colors.size());
		indices.resize((int64_t)_batch_indices.size());
		std::copy(_batch_points.begin(), _batch_points.end(), points.ptrw());
		std::copy(_batch_colors.begin(), _batch_colors.end(), colors.ptrw());
		std::copy(_batch_indices.begin(), _batch_indices.end(), indices.ptrw());
		RenderingServer::get_singleton()->canvas_item_add_triangle_array(canvas, indices, points, colors);
	}
	return drawn;
}

void LanePainter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "constants"), &LanePainter::setup);
	ClassDB::bind_method(D_METHOD("set_providers", "lanes", "ends"), &LanePainter::set_providers);
	ClassDB::bind_method(D_METHOD("forget_lanes"), &LanePainter::forget_lanes);
	ClassDB::bind_method(D_METHOD("draw", "canvas", "lanes", "params"), &LanePainter::draw);
}
