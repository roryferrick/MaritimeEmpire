// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See sea_painter.h. Follows MapView._draw_sea_animal(), _on_water(),
// _sea_event(), _draw_sea_sprite(), _draw_breach(), _draw_leap(),
// _draw_splash() and _draw_blow().
#include "sea_painter.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace {
constexpr real_t PI_F = 3.14159265358979f;
constexpr real_t TAU_F = 6.28318530717959f;
constexpr real_t SEA_ART_ASPECT = 128.0f / 48.0f;
constexpr double SEA_SURFACE_S = 3.0;
constexpr double SEA_BREACH_S = 2.4;
constexpr double SEA_LEAP_S = 1.0;
const Color SEA_SPLASH(0.94f, 0.98f, 1.0f);
const Color SEA_SHADOW(0.62f, 0.78f, 0.9f, 0.5f);

// What's needed to draw this frame.
struct Frame {
	RID canvas;
	Vector3 right, up, toward;
	real_t radius;
	Vector2 middle;
	PackedByteArray mask;
	int mask_w = 0, mask_h = 0;

	// MapView._screen_lon_lat() then SeaLife.is_sea().
	bool sea_at(Vector2 screen) const {
		if (mask_w == 0) {
			return true;
		}
		Vector2 q = (screen - middle) / radius;
		q.y = -q.y;
		real_t d = q.length_squared();
		if (d > 1.0f) {
			q /= std::sqrt(d);
			d = 1.0f;
		}
		Vector3 p = right * q.x + up * q.y + toward * std::sqrt(1.0f - d);
		double lon = Math::rad_to_deg(std::atan2((double)p.y, (double)p.x));
		double lat = Math::rad_to_deg(std::asin(CLAMP((double)p.z, -1.0, 1.0)));
		int64_t col = UtilityFunctions::posmod(UtilityFunctions::floori((lon + 180.0) / 360.0 * mask_w), mask_w);
		int64_t row = CLAMP((int64_t)UtilityFunctions::floori((90.0 - lat) / 180.0 * mask_h), (int64_t)0, (int64_t)mask_h - 1);
		int64_t i = row * mask_w + col;
		return ((mask[i >> 3] >> (i & 7)) & 1) == 1;
	}

	// MapView._on_water(): middle, nose, tail and both sides over water.
	bool on_water(Vector2 at, real_t facing, real_t length) const {
		Vector2 along = Vector2::from_angle(facing) * length * 0.55f;
		Vector2 across = Vector2(along.y, -along.x) * (1.0f / SEA_ART_ASPECT);
		for (Vector2 point : { at, at + along, at - along, at + across, at - across }) {
			if (!sea_at(point)) {
				return false;
			}
		}
		return true;
	}

	void sprite(const RID &texture, Vector2 at, real_t facing, real_t length, real_t grow, Color tint) const {
		RenderingServer *rs = RenderingServer::get_singleton();
		Vector2 size = Vector2(length, length / SEA_ART_ASPECT) * grow;
		rs->canvas_item_add_set_transform(canvas, Transform2D(facing, at));
		rs->canvas_item_add_texture_rect(canvas, Rect2(-size / 2.0f, size), texture, false, tint);
		rs->canvas_item_add_set_transform(canvas, Transform2D());
	}

	void arc(Vector2 center, real_t r, int points, Color color, real_t width) const {
		PackedVector2Array line;
		line.resize(points);
		for (int i = 0; i < points; i++) {
			real_t theta = (i / (points - 1.0f)) * TAU_F;
			line.set(i, center + Vector2(std::cos(theta), std::sin(theta)) * r);
		}
		PackedColorArray colors;
		colors.push_back(color);
		RenderingServer::get_singleton()->canvas_item_add_polyline(canvas, line, colors, width, true);
	}

	void splash(Vector2 at, real_t reach, real_t t) const {
		real_t fade = 1.0f - t;
		for (real_t ring : { 1.0f, 0.6f }) {
			arc(at, reach * (0.3f + t * 0.7f) * ring, 20, Color(SEA_SPLASH, 0.8f * fade), MAX(reach * 0.08f, 1.0f));
		}
		for (int k = 0; k < 6; k++) {
			Vector2 drop = at + Vector2::from_angle(k * TAU_F / 6.0f + 0.4f) * reach * (0.4f + t * 0.9f) - Vector2(0.0f, std::sin(PI_F * t) * reach * 0.5f);
			RenderingServer::get_singleton()->canvas_item_add_circle(canvas, drop, MAX(reach * 0.06f, 0.8f), Color(SEA_SPLASH, 0.9f * fade));
		}
	}

	void blow(Vector2 at, real_t length, real_t t) const {
		real_t fade = std::sin(PI_F * t);
		for (int k = 0; k < 3; k++) {
			Vector2 puff = at - Vector2((k - 1) * length * 0.07f, length * (0.1f + t * 0.35f + k * 0.05f));
			RenderingServer::get_singleton()->canvas_item_add_circle(canvas, puff, length * (0.07f + t * 0.06f), Color(SEA_SPLASH, 0.75f * fade));
		}
	}
};
} // namespace

// MapView._sea_event(): how far (0..1) into a breach or surfacing an animal
// is now, or -1; its roll for each slot kept till the next.
double SeaPainter::_event(int64_t pod, int64_t animal, const String &what, int64_t what_id, double every, double chance, double seconds, double t) {
	double slot = std::floor(t / every);
	Key key = { pod, animal, what_id, (int64_t)slot };
	auto found = _events.find(key);
	double start;
	if (found != _events.end()) {
		start = found->second;
	} else {
		Ref<RandomNumberGenerator> rng;
		rng.instantiate();
		Array parts;
		parts.push_back(pod);
		parts.push_back(animal);
		parts.push_back(what);
		parts.push_back((int64_t)slot);
		rng->set_seed(UtilityFunctions::hash(parts));
		start = NAN;
		if (rng->randf() < chance) {
			start = slot * every + rng->randf() * MAX(every - seconds, 0.0);
		}
		if (_events.size() > 4096) {
			_events.clear();
		}
		_events[key] = start;
	}
	if (std::isnan(start)) {
		return -1.0;
	}
	double into = (t - start) / seconds;
	return into >= 0.0 && into < 1.0 ? into : -1.0;
}

// pods: [[pod index, center (screen), angle, kind index, shown]]; kinds:
// [{texture, silhouette (RIDs), length_px, spacing_px, leap (an arc, as a
// dolphin's, else a breach), blow (spray on surfacing), breach
// ([every, chance] or []), surface (likewise)}]; params: right, up, toward,
// radius, middle (the view), play_time, scale, mask (PackedByteArray),
// mask_size (Vector2i).
void SeaPainter::draw(const RID &canvas, const Array &pods, const Array &kinds, const Dictionary &params) {
	Frame frame;
	frame.canvas = canvas;
	frame.right = params["right"];
	frame.up = params["up"];
	frame.toward = params["toward"];
	frame.radius = (real_t)(double)params["radius"];
	frame.middle = params["middle"];
	frame.mask = params["mask"];
	Vector2i mask_size = params["mask_size"];
	frame.mask_w = mask_size.x;
	frame.mask_h = mask_size.y;
	double t = params["play_time"];
	real_t scale = (real_t)(double)params["scale"];
	static const String BREACH = "breach";
	static const String SURFACE = "surface";
	for (int64_t p = 0; p < pods.size(); p++) {
		Array pod = pods[p];
		int64_t index = pod[0];
		Vector2 center = pod[1];
		real_t angle = (real_t)(double)pod[2];
		Dictionary kind = kinds[(int64_t)pod[3]];
		int64_t shown = pod[4];
		RID texture = kind["texture"];
		RID silhouette = kind["silhouette"];
		real_t length = (real_t)(double)kind["length_px"] * scale;
		real_t spacing = (real_t)(double)kind["spacing_px"] * scale;
		bool dolphin = kind["leap"]; // (A leap, as a dolphin's; else a breach.)
		bool blows = kind["blow"];
		Array breach = kind["breach"];
		Array surface = kind["surface"];
		for (int64_t j = 0; j < shown; j++) {
			// Its place in the group (spread round the middle, drifting a little).
			Vector2 spot = Vector2::from_angle(j * 2.39996f) * spacing * std::sqrt((real_t)j) * 0.9f;
			spot += Vector2((real_t)std::sin(t * 0.7 + j * 1.3), (real_t)std::cos(t * 0.5 + j * 0.9)) * spacing * 0.15f;
			Vector2 at = center + spot.rotated(angle);
			real_t facing = angle + (real_t)(std::sin(t * 1.4 + j * 2.1) * 0.12);
			if (!texture.is_valid() || !frame.on_water(at, facing, length)) {
				continue; // Never drawn over land, even partly.
			}
			frame.sprite(silhouette, at, facing, length, 1.0f, SEA_SHADOW);
			if (!breach.is_empty()) {
				double up = _event(index, j, BREACH, 1, breach[0], breach[1], dolphin ? SEA_LEAP_S : SEA_BREACH_S, t);
				// A leap or breach reaches out ahead and up the screen (and
				// splashes round it): only where all that is water too.
				Vector2 reach = at + Vector2::from_angle(facing) * length * (dolphin ? 0.7f : 0.0f) - Vector2(0.0f, length * (dolphin ? 0.7f : 0.25f));
				if (up >= 0.0 && frame.on_water(reach, facing, length * 1.6f)) {
					real_t u = (real_t)up;
					if (dolphin) {
						real_t arc = MIN(u / 0.8f, 1.0f);
						if (u < 0.8f) {
							Vector2 ahead = Vector2::from_angle(facing) * (arc - 0.5f) * length * 1.4f;
							frame.sprite(texture, at + ahead - Vector2(0.0f, std::sin(PI_F * arc) * length * 0.7f), facing - (arc - 0.5f) * 0.5f, length, 1.0f + 0.25f * std::sin(PI_F * arc), Color(1, 1, 1));
						}
						if (u > 0.7f) {
							frame.splash(at + Vector2::from_angle(facing) * length * 0.7f, length * 0.6f, (u - 0.7f) / 0.3f);
						}
					} else {
						real_t rise = std::sin(PI_F * MIN(u / 0.7f, 1.0f));
						if (u < 0.7f) {
							frame.sprite(texture, at - Vector2(0.0f, rise * length * 0.25f), facing, length, 1.0f + 0.6f * rise, Color(1, 1, 1));
						}
						if (u > 0.55f) {
							frame.splash(at, length * 0.9f, (u - 0.55f) / 0.45f);
						}
					}
					continue;
				}
			}
			if (!surface.is_empty()) {
				double up = _event(index, j, SURFACE, 2, surface[0], surface[1], SEA_SURFACE_S, t);
				if (up >= 0.0) {
					real_t u = (real_t)up;
					frame.sprite(texture, at, facing, length, 1.0f, Color(1, 1, 1, std::sin(PI_F * u) * 0.95f));
					if (blows && u > 0.15f && u < 0.75f) {
						frame.blow(at + Vector2::from_angle(facing) * length * 0.32f, length, (u - 0.15f) / 0.6f);
					}
				}
			}
		}
	}
}

void SeaPainter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("draw", "canvas", "pods", "kinds", "params"), &SeaPainter::draw);
}
