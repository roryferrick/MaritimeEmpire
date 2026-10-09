// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#include "globe_tiles.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2.hpp>

#include <cmath>
#include <map>
#include <utility>
#include <vector>

using namespace godot;

Array GlobeTiles::split(const PackedVector2Array &points, const PackedColorArray &colors, int64_t per_shape, double cell_deg) {
	struct Tile {
		std::vector<Vector2> points;
		std::vector<Color> colors;
		Vector2 low = Vector2(1e30, 1e30);
		Vector2 high = Vector2(-1e30, -1e30);
	};
	std::map<std::pair<int64_t, int64_t>, Tile> tiles;  // (Ordered: the same tiles in the same order every time.)
	const bool colored = colors.size() == points.size();
	const Vector2 *p = points.ptr();
	const Color *c = colored ? colors.ptr() : nullptr;
	const int64_t shapes = per_shape > 0 ? points.size() / per_shape : 0;
	for (int64_t s = 0; s < shapes; s++) {
		const Vector2 first = p[s * per_shape];
		Tile &tile = tiles[{ (int64_t)std::floor(first.x / cell_deg), (int64_t)std::floor(first.y / cell_deg) }];
		for (int64_t k = 0; k < per_shape; k++) {
			const Vector2 q = p[s * per_shape + k];
			tile.points.push_back(q);
			if (colored) {
				tile.colors.push_back(c[s * per_shape + k]);
			}
			tile.low = Vector2(MIN(tile.low.x, q.x), MIN(tile.low.y, q.y));
			tile.high = Vector2(MAX(tile.high.x, q.x), MAX(tile.high.y, q.y));
		}
	}
	Array out;
	for (auto &entry : tiles) {
		Tile &tile = entry.second;
		PackedVector2Array tile_points;
		tile_points.resize(tile.points.size());
		for (size_t i = 0; i < tile.points.size(); i++) {
			tile_points.set(i, tile.points[i]);
		}
		PackedColorArray tile_colors;
		tile_colors.resize(tile.colors.size());
		for (size_t i = 0; i < tile.colors.size(); i++) {
			tile_colors.set(i, tile.colors[i]);
		}
		Dictionary each;
		each["points"] = tile_points;
		each["colors"] = tile_colors;
		each["box"] = Rect2(tile.low, tile.high - tile.low);
		out.append(each);
	}
	return out;
}

void GlobeTiles::_bind_methods() {
	ClassDB::bind_static_method("GlobeTiles", D_METHOD("split", "points", "colors", "per_shape", "cell_deg"), &GlobeTiles::split);
}
