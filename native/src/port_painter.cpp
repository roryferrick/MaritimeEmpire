// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See port_painter.h. Follows MapView._draw_ports()'s draw_port: every dot,
// ring and glow made as triangles here and handed over in one call (drawn
// one by one, Godot's antialiased outlines cost more than the rest put
// together), in the same order, so they overlap the same way.
#include "port_painter.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace {
constexpr real_t TAU_F = 6.2831853071795864769252867666f;
// Points round a dot, and an antialiased outline's soft edge (px) either side.
constexpr int DOT_POINTS = 24;
constexpr real_t FEATHER = 1.0f;

// Triangles being built: points, their colors, and indices into them.
struct Mesh {
	PackedVector2Array points;
	PackedColorArray colors;
	PackedInt32Array indices;
	Vector2 unit[DOT_POINTS + 1];

	Mesh() {
		for (int i = 0; i <= DOT_POINTS; i++) {
			real_t theta = (i / (real_t)DOT_POINTS) * TAU_F;
			unit[i] = Vector2(Math::cos(theta), Math::sin(theta));
		}
	}

	int32_t add(Vector2 point, Color color) {
		points.push_back(point);
		colors.push_back(color);
		return (int32_t)points.size() - 1;
	}

	// A filled circle (CanvasItem.draw_circle()).
	void disc(Vector2 center, real_t radius, Color color) {
		int32_t middle = add(center, color);
		int32_t first = (int32_t)points.size();
		for (int i = 0; i < DOT_POINTS; i++) {
			add(center + unit[i] * radius, color);
		}
		for (int i = 0; i < DOT_POINTS; i++) {
			indices.push_back(middle);
			indices.push_back(first + i);
			indices.push_back(first + (i + 1) % DOT_POINTS);
		}
	}

	// A band between two radii, its color fading from `inner` to `outer`.
	void band(Vector2 center, real_t from, real_t to, Color inner, Color outer) {
		int32_t first = (int32_t)points.size();
		for (int i = 0; i < DOT_POINTS; i++) {
			add(center + unit[i] * from, inner);
			add(center + unit[i] * to, outer);
		}
		for (int i = 0; i < DOT_POINTS; i++) {
			int32_t a = first + i * 2;
			int32_t b = first + ((i + 1) % DOT_POINTS) * 2;
			indices.push_back(a);
			indices.push_back(a + 1);
			indices.push_back(b);
			indices.push_back(b);
			indices.push_back(a + 1);
			indices.push_back(b + 1);
		}
	}

	// An antialiased outline `width` px wide round a circle (CanvasItem.draw_arc(), antialiased).
	void ring(Vector2 center, real_t radius, Color color, real_t width) {
		Color clear(color, 0.0f);
		real_t inner = radius - width / 2.0f;
		real_t outer = radius + width / 2.0f;
		band(center, MAX(inner - FEATHER, 0.0f), inner, clear, color);
		band(center, inner, outer, color, color);
		band(center, outer, outer + FEATHER, color, clear);
	}
};
} // namespace

void PortPainter::set_units(const PackedVector3Array &units) {
	_units = units;
}

void PortPainter::set_styles(const PackedFloat32Array &radii, const PackedFloat32Array &layout_radii, const PackedColorArray &fills, const PackedByteArray &flags) {
	_radii = radii;
	_layout_radii = layout_radii;
	_fills = fills;
	_flags = flags;
}

// The dots of `ports` (indices into GameData.ports) in view. params: right,
// up, toward, radius, middle (the view), area (Rect2: the screen grown),
// outline, locked_fill, dimmed (Colors), locked_radius, shine (Array of [px out,
// alpha]), selected (port index or -1), selected_ring (Color), docks (bool:
// marinas can show), scale (px a dock unit), over_dot_px.
void PortPainter::draw(const RID &canvas, const PackedInt32Array &ports, const Dictionary &params) {
	Vector3 right = params["right"];
	Vector3 up = params["up"];
	Vector3 toward = params["toward"];
	real_t globe = (real_t)(double)params["radius"];
	Vector2 middle = params["middle"];
	Rect2 area = params["area"];
	Color outline = params["outline"];
	Color locked_fill = params["locked_fill"];
	Color dimmed = params["dimmed"];
	real_t locked_radius = (real_t)(double)params["locked_radius"];
	Array shine = params["shine"];
	int selected = params["selected"];
	Color selected_ring = params["selected_ring"];
	bool docks = params["docks"];
	double scale = params["scale"];
	double over_dot = params["over_dot_px"];
	Mesh mesh;
	for (int64_t k = 0; k < ports.size(); k++) {
		int i = ports[k];
		if (i < 0 || i >= _units.size() || i >= _flags.size()) {
			continue;
		}
		uint8_t flags = _flags[i];
		if (flags & 4) {
			continue; // A hub: MapView draws it, with its rings.
		}
		Vector3 p = _units[i];
		if (p.dot(toward) < 0.0f) {
			continue;
		}
		Vector2 pos = middle + Vector2(p.dot(right), -p.dot(up)) * globe;
		if (!area.has_point(pos)) {
			continue;
		}
		real_t radius = _radii[i];
		if (docks && (double)_layout_radii[i] * scale >= (double)radius + over_dot) {
			continue; // Grown into its marina (see MapView._update_marinas()).
		}
		if (flags & 1) {
			// In a locked region: a small faint dot, no more.
			mesh.disc(pos, locked_radius, locked_fill);
			continue;
		}
		Color fill = _fills[i];
		bool shining = (flags & 2) != 0;
		if (shining) {
			for (int64_t r = 0; r < shine.size(); r++) {
				Array glow = shine[r];
				mesh.disc(pos, radius + (real_t)(double)glow[0], Color(fill, (real_t)(double)glow[1]));
			}
		}
		mesh.disc(pos, radius, (flags & 8) ? dimmed : fill);
		mesh.ring(pos, radius, outline, 1.5f);
		if (shining) {
			mesh.disc(pos + Vector2(-0.35f, -0.35f) * radius, radius * 0.3f, Color(1.0f, 1.0f, 1.0f, 0.85f));
		}
		if (i == selected) {
			mesh.ring(pos, radius + 4.0f, selected_ring, 3.0f);
		}
	}
	if (!mesh.indices.is_empty()) {
		RenderingServer::get_singleton()->canvas_item_add_triangle_array(canvas, mesh.indices, mesh.points, mesh.colors);
	}
}

void PortPainter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_units", "units"), &PortPainter::set_units);
	ClassDB::bind_method(D_METHOD("set_styles", "radii", "layout_radii", "fills", "flags"), &PortPainter::set_styles);
	ClassDB::bind_method(D_METHOD("draw", "canvas", "ports", "params"), &PortPainter::draw);
	ClassDB::bind_method(D_METHOD("marinas", "ports", "params"), &PortPainter::marinas);
}

// The ports of `ports` whose marina may show, near enough the screen
// (MapView._update_marinas() then looks at them properly). With a px to
// spare: the sizes here can be a moment old. params: right, up, toward,
// radius, middle, near (Rect2), scale, over_dot_px.
PackedInt32Array PortPainter::marinas(const PackedInt32Array &ports, const Dictionary &params) {
	PackedInt32Array out;
	Vector3 right = params["right"];
	Vector3 up = params["up"];
	Vector3 toward = params["toward"];
	real_t globe = (real_t)(double)params["radius"];
	Vector2 middle = params["middle"];
	Rect2 near = params["near"];
	double scale = params["scale"];
	double over_dot = params["over_dot_px"];
	for (int64_t k = 0; k < ports.size(); k++) {
		int i = ports[k];
		if (i < 0 || i >= _units.size() || i >= _radii.size()) {
			continue;
		}
		Vector3 p = _units[i];
		if (p.dot(toward) < 0.0f) {
			continue;
		}
		Vector2 pos = middle + Vector2(p.dot(right), -p.dot(up)) * globe;
		if (!near.has_point(pos)) {
			continue;
		}
		if ((double)_layout_radii[i] * scale >= (double)_radii[i] + over_dot - 1.0) {
			out.push_back(i);
		}
	}
	return out;
}
