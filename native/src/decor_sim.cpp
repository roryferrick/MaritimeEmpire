// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See decor_sim.h. Follows MapView._load_decor() and _draw_decor().
#include "decor_sim.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

void DecorSim::setup(const PackedVector2Array &positions, const PackedVector3Array &units, const PackedInt32Array &kinds, const PackedInt32Array &tiers,
		const PackedFloat64Array &room, const Array &textures, double bucket) {
	_units = units;
	_kinds = kinds;
	_tiers = tiers;
	_room = room;
	_bucket = bucket;
	_columns = (int)std::ceil(360.0 / bucket);
	_textures.clear();
	for (int64_t i = 0; i < textures.size(); i++) {
		_textures.push_back(textures[i]);
	}
	_buckets.clear();
	for (int64_t i = 0; i < positions.size(); i++) {
		Vector2 p = positions[i];
		int column = (int)UtilityFunctions::floori(((double)p.x + 180.0) / bucket);
		int row = (int)UtilityFunctions::floori((double)p.y / bucket);
		_buckets[_cell(column, row)].push_back((int32_t)i);
	}
}

void DecorSim::set_regions(const PackedByteArray &regions) {
	_regions = regions;
}

void DecorSim::set_seasons(const Dictionary &north, const Dictionary &south) {
	const Dictionary *sides[2] = { &north, &south };
	for (int h = 0; h < 2; h++) {
		_before[h] = (*sides[h])["before"];
		_now[h] = (*sides[h])["now"];
		_snow[h] = (*sides[h])["snow"];
		_mix[h] = (*sides[h])["mix"];
		_snow_lat[h] = (*sides[h])["snow_lat"];
	}
	_seasons = true;
}

// MapView._draw_decor()'s picking and drawing. params: right, up, toward,
// radius, middle (the view), screen (Rect2: grown by the largest drawing),
// zoom, sides (px each kind is), tiers (how many tiers each kind shows),
// columns (first, last), rows (first, last), locked (PackedByteArray by
// region + 1: 1 if locked; empty: no locks).
void DecorSim::draw(const RID &canvas, const Dictionary &params) {
	Vector3 right = params["right"];
	Vector3 up = params["up"];
	Vector3 toward = params["toward"];
	double radius = params["radius"];
	Vector2 middle = params["middle"];
	Rect2 screen = params["screen"];
	double zoom = params["zoom"];
	PackedFloat64Array sides = params["sides"];
	PackedInt32Array kind_tiers = params["tiers"];
	Vector2i columns = params["columns"];
	Vector2i rows = params["rows"];
	PackedByteArray locked = params["locked"];
	bool check_locks = !locked.is_empty() && !_regions.is_empty();
	struct Shown {
		Vector2 at;
		int kind;
		double side;
		int texture;
	};
	std::vector<Shown> shown;
	for (int column = columns.x; column <= columns.y; column++) {
		int wrapped = (int)UtilityFunctions::posmod(column, _columns);
		for (int row = rows.x; row <= rows.y; row++) {
			auto found = _buckets.find(_cell(wrapped, row));
			if (found == _buckets.end()) {
				continue;
			}
			for (int32_t i : found->second) {
				int kind = _kinds[i];
				if (_tiers[i] >= kind_tiers[kind]) {
					continue; // Too small to show (or thinned out at this size), or an animal.
				}
				double side = sides[kind];
				if (_room[i] * zoom < side * 0.5) {
					continue; // Would reach into the water (or onto the land).
				}
				if (check_locks) {
					int region = _regions[i];
					if (region < locked.size() && locked[region]) {
						continue; // Its region is locked: shaded, bare.
					}
				}
				// MapView._unit_to_screen().
				Vector3 p = _units[i];
				if (p.dot(toward) < 0.0f) {
					continue;
				}
				Vector2 at = middle + Vector2(p.dot(right), -p.dot(up)) * (real_t)radius;
				if (!screen.has_point(at)) {
					continue;
				}
				int texture = kind;
				if (_seasons) {
					// Its season: by its hemisphere, in the snow beyond the snow line,
					// else changing over at its own moment (a hash of its index).
					int h = p.z < 0.0f ? 1 : 0;
					double lat = Math::rad_to_deg(std::asin(std::clamp((double)p.z, -1.0, 1.0)));
					if (std::abs(lat) >= _snow_lat[h] && kind < _snow[h].size()) {
						texture = _snow[h][kind];
					} else if (kind < _now[h].size() && kind < _before[h].size()) {
						uint32_t x = (uint32_t)i * 2654435761u;
						x ^= x >> 15;
						x *= 2246822519u;
						x ^= x >> 13;
						double moment = (double)(x & 0xffffff) / 16777216.0;
						texture = moment < _mix[h] ? _now[h][kind] : _before[h][kind];
					}
				}
				shown.push_back({ at, kind, side, texture });
			}
		}
	}
	std::stable_sort(shown.begin(), shown.end(), [](const Shown &a, const Shown &b) { return a.at.y < b.at.y; });
	RenderingServer *rs = RenderingServer::get_singleton();
	for (const Shown &item : shown) {
		if (item.texture < 0 || item.texture >= (int)_textures.size() || !_textures[item.texture].is_valid()) {
			continue;
		}
		real_t side = (real_t)item.side;
		rs->canvas_item_add_texture_rect(canvas, Rect2(item.at - Vector2(side / 2.0f, side * 0.92f), Vector2(side, side)), _textures[item.texture], false);
	}
}

void DecorSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "positions", "units", "kinds", "tiers", "room", "textures", "bucket"), &DecorSim::setup);
	ClassDB::bind_method(D_METHOD("set_regions", "regions"), &DecorSim::set_regions);
	ClassDB::bind_method(D_METHOD("set_seasons", "north", "south"), &DecorSim::set_seasons);
	ClassDB::bind_method(D_METHOD("draw", "canvas", "params"), &DecorSim::draw);
}
