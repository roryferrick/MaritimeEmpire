// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See ship_culler.h. The rules are MapView._draw_ships()' and its loops'.
#include "ship_culler.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rect2.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

// The Ship members read (looked up once).
struct Names {
	StringName docked_at = "docked_at", from_port = "from_port", to_port = "to_port", traveled_nm = "traveled_nm";
	StringName rescuer = "rescuer", rescuing = "rescuing", kind = "_kind_cache", canal_state = "canal_state";
	StringName lost_reason = "lost_reason", at_risk = "at_risk", company = "company", job_phase = "job_phase", ice_phase = "ice_phase";
	StringName is_carrying = "is_carrying", is_service = "is_service";
};

const Names &names() {
	static Names n;
	return n;
}

constexpr double PI_D = 3.141592653589793;

} // namespace

// constants: kind_cargo, kind_tug (Ship.KIND_*), chunk (MapView.LANE_CHUNK),
// held_states (the canal states a ship is drawn off its lane in).
void ShipCuller::setup(const Dictionary &constants) {
	_kind_cargo = constants.get("kind_cargo", 0);
	_kind_tug = constants.get("kind_tug", 3);
	_chunk = std::max((int64_t)constants.get("chunk", 24), (int64_t)1);
	_held_states.clear();
	Array held = constants.get("held_states", Array());
	for (int64_t i = 0; i < held.size(); i++) {
		_held_states.push_back(held[i]);
	}
}

// (from_port, to_port) -> [the bent lane's miles, its chunks' middles and
// spans (MapView._chunk_caps()), its points on the unit sphere], or [] for no lane.
void ShipCuller::set_lane_provider(const Callable &provider) {
	_lane_provider = provider;
}

// (Put off till the next pass: the map may ask while a pass is using a lane,
// bending lanes afresh when the ports' zones have changed.)
void ShipCuller::forget_lanes() {
	_forget = true;
}

ShipCuller::Lane &ShipCuller::_lane(const String &from, const String &to) {
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
	return lane;
}

Vector3 ShipCuller::_between(const Vector3 &a, const Vector3 &b, double t) {
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

Vector3 ShipCuller::_at_mile(const Lane &lane, double mile) {
	double length = lane.miles.back();
	mile = std::clamp(mile, 0.0, length);
	int64_t i = std::lower_bound(lane.miles.begin(), lane.miles.end(), mile) - lane.miles.begin();
	i = std::clamp(i, (int64_t)1, (int64_t)lane.miles.size() - 1);
	double span = lane.miles[i] - lane.miles[i - 1];
	double t = span > 0.0 ? (mile - lane.miles[i - 1]) / span : 1.0;
	return _between(lane.units[i - 1], lane.units[i], t);
}

// Whether a ship `mile` along a lane could be in view (MapView._on_lane_in_view()):
// its chunk of lane near enough; and (`plain`: a cargo ship plainly on its
// lane, well away from either port) its own point within _tight_angle.
bool ShipCuller::_lane_in_view(const String &from, const String &to, double mile, bool plain) {
	Lane &lane = _lane(from, to);
	if (!lane.valid) {
		return true;
	}
	if (lane.epoch != _epoch) {
		lane.epoch = _epoch;
		lane.chunks.resize(lane.centers.size());
		for (size_t c = 0; c < lane.centers.size(); c++) {
			lane.chunks[c] = lane.centers[c].dot(_toward) >= std::cos(std::min(_view_angle + lane.spans[c], PI_D)) ? 1 : 0;
		}
	}
	double length = lane.miles.back();
	mile = std::clamp(mile, 0.0, length);
	int64_t i = std::lower_bound(lane.miles.begin(), lane.miles.end(), mile) - lane.miles.begin();
	i = std::clamp(i, (int64_t)1, (int64_t)lane.miles.size() - 1);
	int64_t chunk = std::min((i - 1) / _chunk, (int64_t)lane.chunks.size() - 1);
	if (lane.chunks[chunk] != 1) {
		return false;
	}
	if (!plain || _end_zone <= 0.0) {
		return true;
	}
	double span = lane.miles[i] - lane.miles[i - 1];
	double t = span > 0.0 ? (mile - lane.miles[i - 1]) / span : 1.0;
	Vector3 p = lane.units[i - 1].lerp(lane.units[i], (real_t)t).normalized();
	bool near_start = mile <= _end_zone;
	bool near_end = length - mile <= _end_zone;
	if (!near_start && !near_end) {
		return p.dot(_toward) >= std::cos(std::min(_tight_angle, PI_D));
	}
	// Within reach of a port's harbour, its curve in or out may have it anywhere
	// between its point on the lane and the port (the lane's end): the lens
	// round those, with room to spare.
	auto lens = [&](const Vector3 &port) {
		Vector3 mid = (p + port).normalized();
		double half = std::acos(std::clamp((double)p.dot(port), -1.0, 1.0)) / 2.0;
		return mid.dot(_toward) >= std::cos(std::min(_tight_angle + half + _end_slack, PI_D));
	};
	return (near_start && lens(lane.units.front())) || (near_end && lens(lane.units.back()));
}

// The pass (see the top): `order` the ships in drawing order; params:
// view_epoch (a count going up each time the view changes), toward
// (Vector3), view_angle (radians from the view's middle a ship could show
// within), tight_angle and end_zone_nm (the same for a cargo ship plainly on
// its lane, by its own point that far from either port, where nothing moves
// it off its lane; nearer, by the lens between its point and the port, and
// end_slack_angle more), docks_shown (bool), mine (the player's company), port_shown (a
// callable: port id -> whether ships in port there show); and for the dots
// (see the top; left out when dots is false): dots_canvas (the RID to draw
// on), right, up, radius, middle, screen (Rect2), scale (px a dock unit),
// dot_px (a ship shorter than this on screen is a dot), dot_half_px (half a dot's side), lengths (each ship's
// length in dock units, by its place in `order`) and colors (its dot's).
// Gives {draw: the places in `order` of the ships to draw, plain: a byte for
// each, 1 for a cargo ship plainly on its lane (its stretch of lane in view,
// nothing more to check), carried: those riding on a recovery boat, markers:
// those that may want a marker, tugs: those with a ship on their line, dots:
// how many ships were drawn as dots}.
Dictionary ShipCuller::sort(const Array &order, const Dictionary &params) {
	const Names &n = names();
	if (_forget) {
		_forget = false;
		_lanes.clear();
	}
	_epoch = params.get("view_epoch", 0);
	_toward = params.get("toward", Vector3());
	_view_angle = params.get("view_angle", 0.0);
	_tight_angle = params.get("tight_angle", 0.0);
	_end_zone = params.get("end_zone_nm", 0.0);
	_end_slack = params.get("end_slack_angle", 0.0);
	bool docks_shown = params.get("docks_shown", true);
	Object *mine = params.get("mine", Variant());
	Callable port_shown = params.get("port_shown", Callable());
	bool dots = params.get("dots", false);
	RID dots_canvas = params.get("dots_canvas", RID());
	Vector3 right = params.get("right", Vector3());
	Vector3 up = params.get("up", Vector3());
	double radius = params.get("radius", 1.0);
	Vector2 middle = params.get("middle", Vector2());
	Rect2 screen = params.get("screen", Rect2());
	double scale = params.get("scale", 1.0);
	double dot_px = params.get("dot_px", 0.0);
	real_t dot_half = (real_t)(double)params.get("dot_half_px", 1.0);
	PackedFloat32Array lengths = params.get("lengths", PackedFloat32Array());
	PackedColorArray colors = params.get("colors", PackedColorArray());
	if (!dots_canvas.is_valid() || lengths.size() < order.size() || colors.size() < order.size()) {
		dots = false;
	}
	PackedVector2Array dot_points;
	PackedColorArray dot_colors;
	PackedInt32Array dot_indices;
	int64_t dotted = 0;
	HashMap<String, bool> shown;
	PackedInt32Array draw, carried, markers, tugs;
	PackedByteArray plain;
	for (int64_t i = 0; i < order.size(); i++) {
		Object *ship = order[i];
		if (ship == nullptr) {
			continue;
		}
		Object *rescuer = ship->get(n.rescuer);
		bool is_carried = rescuer != nullptr && (bool)rescuer->call(n.is_carrying);
		String docked_at = ship->get(n.docked_at);
		bool docked = !docked_at.is_empty();
		int kind = ship->get(n.kind);
		if (kind < 0) {
			ship->call(n.is_service); // (Works its kind out and keeps it.)
			kind = ship->get(n.kind);
		}
		bool held = false;
		if (!docked) {
			String canal_state = ship->get(n.canal_state);
			if (!canal_state.is_empty()) {
				held = std::find(_held_states.begin(), _held_states.end(), canal_state) != _held_states.end();
			}
		}
		// Whether its stretch of lane could be in view (MapView._ship_maybe_in_view()):
		// looked at for a cargo ship plainly sailing, and for any other wanting a marker.
		bool plain_sailing = !docked && !is_carried && kind == _kind_cargo && rescuer == nullptr && !held;
		// A service ship with nothing on (no job, no ship on its line, no ice to break)
		// is plainly on its lane too (drawn off it only on a job).
		bool idle_service = !docked && !is_carried && kind != _kind_cargo && rescuer == nullptr && !held && String(ship->get(n.job_phase)).is_empty() && ship->get(n.rescuing).get_type() == Variant::NIL && String(ship->get(n.ice_phase)).is_empty();
		bool in_view = true;
		bool lane_looked = docked || held;
		String from, to;
		double mile = 0.0;
		auto look_at_lane = [&]() {
			if (lane_looked) {
				return;
			}
			lane_looked = true;
			from = ship->get(n.from_port);
			to = ship->get(n.to_port);
			if (!from.is_empty() && !to.is_empty()) {
				mile = ship->get(n.traveled_nm);
				in_view = _lane_in_view(from, to, mile, plain_sailing);
			}
		};
		if (plain_sailing || idle_service) {
			look_at_lane();
		}
		if (is_carried) {
			carried.push_back((int32_t)i);
		} else if (docked) {
			if (docks_shown) {
				bool *known = shown.getptr(docked_at);
				bool port_ok = known != nullptr ? *known : (bool)port_shown.call(docked_at);
				if (known == nullptr) {
					shown[docked_at] = port_ok;
				}
				if (port_ok) {
					draw.push_back((int32_t)i);
					plain.push_back(0);
				}
			}
		} else if ((!plain_sailing && !idle_service) || in_view) {
			// A cargo ship plainly on its lane, too small to make out: a dot
			// where it is (MapView._draw_tiny_ship()), drawn here.
			if (dots && plain_sailing && !from.is_empty() && !to.is_empty() && (double)lengths[i] * scale < dot_px) {
				Lane &lane = _lane(from, to);
				if (lane.valid) {
					Vector3 p = _at_mile(lane, mile);
					if (p.dot(_toward) >= 0.0f) {
						Vector2 at = middle + Vector2(p.dot(right), -p.dot(up)) * (real_t)radius;
						if (screen.has_point(at)) {
							int32_t base = (int32_t)dot_points.size();
							dot_points.push_back(at + Vector2(-dot_half, -dot_half));
							dot_points.push_back(at + Vector2(dot_half, -dot_half));
							dot_points.push_back(at + Vector2(dot_half, dot_half));
							dot_points.push_back(at + Vector2(-dot_half, dot_half));
							for (int k = 0; k < 4; k++) {
								dot_colors.push_back(colors[i]);
							}
							for (int32_t k : { 0, 1, 2, 0, 2, 3 }) {
								dot_indices.push_back(base + k);
							}
						}
					}
					dotted++;
					continue; // (Not the map's to draw, on screen or not.)
				}
			}
			draw.push_back((int32_t)i);
			plain.push_back(plain_sailing ? 1 : 0);
		}
		if (kind == _kind_tug && ship->get(n.rescuing).get_type() != Variant::NIL) {
			tugs.push_back((int32_t)i);
		}
		Object *company = ship->get(n.company);
		if (company == nullptr || company == mine) { // (GameState.owner_of(): no company means the player's.)
			bool lost = !String(ship->get(n.lost_reason)).is_empty();
			if ((lost && !is_carried) || (bool)ship->get(n.at_risk)) {
				look_at_lane();
				if (in_view) {
					markers.push_back((int32_t)i);
				}
			}
		}
	}
	if (!dot_indices.is_empty()) {
		RenderingServer::get_singleton()->canvas_item_add_triangle_array(dots_canvas, dot_indices, dot_points, dot_colors);
	}
	Dictionary out;
	out["draw"] = draw;
	out["plain"] = plain;
	out["carried"] = carried;
	out["markers"] = markers;
	out["tugs"] = tugs;
	out["dots"] = dotted;
	return out;
}

void ShipCuller::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "constants"), &ShipCuller::setup);
	ClassDB::bind_method(D_METHOD("set_lane_provider", "provider"), &ShipCuller::set_lane_provider);
	ClassDB::bind_method(D_METHOD("forget_lanes"), &ShipCuller::forget_lanes);
	ClassDB::bind_method(D_METHOD("sort", "order", "params"), &ShipCuller::sort);
}
