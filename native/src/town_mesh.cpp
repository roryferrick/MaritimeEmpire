// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See town_mesh.h. Follows MapView._town_mesh().
#include "town_mesh.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
constexpr double TAU_D = 6.283185307179586;
}

void TownMesh::_quad_points(const Vector2 *p, const Color &color) {
	int32_t base = (int32_t)_points.size();
	for (int i = 0; i < 4; i++) {
		_points.push_back(p[i]);
		_colors.push_back(color);
	}
	for (int32_t k : { 0, 1, 2, 0, 2, 3 }) {
		_indices.push_back(base + k);
	}
}

void TownMesh::_quad(const Rect2 &rect, const Color &color) {
	Vector2 end = rect.get_end();
	Vector2 p[4] = { rect.position, Vector2(end.x, rect.position.y), end, Vector2(rect.position.x, end.y) };
	_quad_points(p, color);
}

void TownMesh::_disc(Vector2 center, real_t r, const Color &color, int steps) {
	int32_t base = (int32_t)_points.size();
	for (int i = 0; i < steps; i++) {
		double a = TAU_D * i / steps;
		_points.push_back(center + Vector2((real_t)std::cos(a), (real_t)std::sin(a)) * r);
		_colors.push_back(color);
	}
	for (int i = 1; i < steps - 1; i++) {
		_indices.push_back(base);
		_indices.push_back(base + i);
		_indices.push_back(base + i + 1);
	}
}

Dictionary TownMesh::build(const Array &roads, const Array &buildings, const Array &parks, const Vector2 &drop, const Dictionary &colors) {
	_points.clear();
	_colors.clear();
	_indices.clear();
	Color walk = colors["walk"];
	Color road = colors["road"];
	Color lane = colors["lane"];
	Color shadow = colors["shadow"];
	Color park = colors["park"];
	Color park_light = park.lightened(0.12f);
	for (int64_t i = 0; i < roads.size(); i++) {
		Array entry = roads[i];
		Rect2 rect = entry[0];
		String kind = entry[1];
		if (rect.size.x <= 0.0f || rect.size.y <= 0.0f) {
			continue;
		}
		_quad(rect, kind == "walk" ? walk : road);
		if (kind == "avenue") {
			real_t x = rect.position.x + 0.5f;
			real_t y = rect.get_center().y;
			while (x < rect.get_end().x - 0.8f) {
				_quad(Rect2(x, y - 0.05f, 0.8f, 0.1f), lane);
				x += 1.6f;
			}
		}
	}
	// Shadows first (every building's, so no block's shadow lies over another's roof).
	for (int64_t i = 0; i < buildings.size(); i++) {
		Array block = buildings[i];
		Rect2 rect = block[0];
		real_t height = (real_t)(double)block[3];
		Vector2 off = drop * height;
		Vector2 end = rect.get_end();
		Vector2 p[4] = { rect.position + off, Vector2(end.x, rect.position.y) + off, end + off, Vector2(rect.position.x, end.y) + off };
		_quad_points(p, shadow);
	}
	for (int64_t i = 0; i < parks.size(); i++) {
		Array entry = parks[i];
		Vector2 at = entry[0];
		real_t r = (real_t)(double)entry[1];
		_disc(at, r, park, 20);
		_disc(at + Vector2(r * 0.4f, -r * 0.3f), r * 0.55f, park_light, 20);
	}
	PackedInt32Array landmarks;
	for (int64_t i = 0; i < buildings.size(); i++) {
		Array block = buildings[i];
		Rect2 rect = block[0];
		Color wall = block[1];
		Color roof = block[2];
		String kind = block[4];
		real_t salt = (real_t)(double)block[5];
		_quad(rect, wall);
		Rect2 top = rect.grow(-0.14f);
		if (kind.begins_with("landmark:")) {
			landmarks.push_back((int32_t)i);
			continue;
		}
		if (kind == "pitched") {
			// Two slopes either side of a ridge along the longer way, the sunny one lighter.
			bool along_x = top.size.x >= top.size.y;
			Rect2 a(top.position, along_x ? Vector2(top.size.x, top.size.y / 2.0f) : Vector2(top.size.x / 2.0f, top.size.y));
			Rect2 b(top.position + (along_x ? Vector2(0.0f, top.size.y / 2.0f) : Vector2(top.size.x / 2.0f, 0.0f)), a.size);
			_quad(a, roof.lightened(0.12f));
			_quad(b, roof.darkened(0.1f));
		} else if (kind == "pagoda") {
			_quad(top, roof);
			_quad(top.grow(-0.35f), roof.lightened(0.18f));
			_quad(top.grow(-0.6f), roof);
		} else if (kind == "warehouse") {
			_quad(top, roof);
			int ribs = std::max((int)(top.size.y / 0.7f), 2);
			for (int k = 0; k < ribs; k++) {
				real_t y = top.position.y + top.size.y * (k + 0.5f) / ribs;
				_quad(Rect2(top.position.x + 0.1f, y - 0.08f, top.size.x - 0.2f, 0.16f), roof.darkened(0.18f));
			}
		} else if (kind == "tall") {
			_quad(top, roof);
			_quad(top.grow(-0.3f), roof.lightened(0.14f));
			_quad(Rect2(top.get_center() - Vector2(0.18f, 0.18f), Vector2(0.36f, 0.36f)), roof.darkened(0.3f));
		} else {
			_quad(top, roof);
			_quad(top.grow(-0.22f), roof.lightened(0.07f));
			if (salt > 0.4f) { // Roof gear: a tank or an air unit.
				Vector2 at = top.position + Vector2(top.size.x * (0.25f + salt * 0.5f), top.size.y * 0.3f);
				_quad(Rect2(at - Vector2(0.14f, 0.14f), Vector2(0.28f, 0.28f)), roof.darkened(0.35f));
			}
		}
	}
	PackedVector2Array points;
	PackedColorArray out_colors;
	PackedInt32Array indices;
	points.resize((int64_t)_points.size());
	out_colors.resize((int64_t)_colors.size());
	indices.resize((int64_t)_indices.size());
	std::copy(_points.begin(), _points.end(), points.ptrw());
	std::copy(_colors.begin(), _colors.end(), out_colors.ptrw());
	std::copy(_indices.begin(), _indices.end(), indices.ptrw());
	Dictionary out;
	out["points"] = points;
	out["colors"] = out_colors;
	out["indices"] = indices;
	out["landmarks"] = landmarks;
	return out;
}

void TownMesh::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "roads", "buildings", "parks", "drop", "colors"), &TownMesh::build);
}
