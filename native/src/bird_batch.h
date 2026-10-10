// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <cstdint>
#include <cstring>
#include <vector>

namespace godot {

// A batch of triangles (points and colors, a multiple of 3) drawn onto a canvas
// item each frame as one mesh kept from frame to frame: only its vertices are
// sent again, into the same buffers, rather than a new polygon (and its
// buffers) made and thrown away every frame. Room for a power of two vertices,
// grown as needed; the part past this frame's is left degenerate (at the
// origin). Falls back to a polygon if the mesh's layout isn't the expected one.
class BirdBatch {
	RID _mesh;
	int64_t _capacity = 0;
	int64_t _last_used = 0;
	bool _layout_ok = false;

	bool _make(int64_t capacity) {
		RenderingServer *rs = RenderingServer::get_singleton();
		_mesh = rs->mesh_create();
		_capacity = capacity;
		_last_used = 0;
		PackedVector2Array points;
		points.resize(capacity);
		points.fill(Vector2());
		PackedColorArray colors;
		colors.resize(capacity);
		colors.fill(Color());
		Array arrays;
		arrays.resize(RenderingServer::ARRAY_MAX);
		arrays[RenderingServer::ARRAY_VERTEX] = points;
		arrays[RenderingServer::ARRAY_COLOR] = colors;
		rs->mesh_add_surface_from_arrays(_mesh, RenderingServer::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(), RenderingServer::ARRAY_FLAG_USE_2D_VERTICES);
		// (Never culled by its own box: the birds are wherever they are.)
		rs->mesh_set_custom_aabb(_mesh, AABB(Vector3(-1.0e6f, -1.0e6f, -1.0f), Vector3(2.0e6f, 2.0e6f, 2.0f)));
		Dictionary surface = rs->mesh_get_surface(_mesh, 0);
		PackedByteArray vertex_data = surface.get("vertex_data", PackedByteArray());
		PackedByteArray attribute_data = surface.get("attribute_data", PackedByteArray());
		// A 2D vertex is two floats; a color four bytes.
		_layout_ok = vertex_data.size() == capacity * 8 && attribute_data.size() == capacity * 4;
		return _layout_ok;
	}

public:
	~BirdBatch() { free(); }

	void free() {
		if (_mesh.is_valid() && RenderingServer::get_singleton() != nullptr) {
			RenderingServer::get_singleton()->free_rid(_mesh);
		}
		_mesh = RID();
		_capacity = 0;
		_last_used = 0;
	}

	// Draws the batch; false if the mesh can't be used (draw it some other way).
	bool draw(const RID &canvas, const std::vector<Vector2> &points, const std::vector<Color> &colors) {
		int64_t n = (int64_t)points.size();
		if (n == 0 || sizeof(Vector2) != 8) {
			return false;
		}
		if (!_mesh.is_valid() || n > _capacity) {
			free();
			int64_t capacity = 4096;
			while (capacity < n) {
				capacity *= 2;
			}
			if (!_make(capacity)) {
				free();
				return false;
			}
		}
		RenderingServer *rs = RenderingServer::get_singleton();
		PackedByteArray vertex_bytes;
		vertex_bytes.resize(n * 8);
		std::memcpy(vertex_bytes.ptrw(), points.data(), (size_t)(n * 8));
		PackedByteArray color_bytes;
		color_bytes.resize(n * 4);
		uint8_t *c = color_bytes.ptrw();
		for (int64_t i = 0; i < n; i++) {
			const Color &color = colors[(size_t)i];
			c[i * 4] = (uint8_t)CLAMP((int)(color.r * 255.0f + 0.5f), 0, 255);
			c[i * 4 + 1] = (uint8_t)CLAMP((int)(color.g * 255.0f + 0.5f), 0, 255);
			c[i * 4 + 2] = (uint8_t)CLAMP((int)(color.b * 255.0f + 0.5f), 0, 255);
			c[i * 4 + 3] = (uint8_t)CLAMP((int)(color.a * 255.0f + 0.5f), 0, 255);
		}
		rs->mesh_surface_update_vertex_region(_mesh, 0, 0, vertex_bytes);
		rs->mesh_surface_update_attribute_region(_mesh, 0, 0, color_bytes);
		if (_last_used > n) {
			// What was drawn last frame past this frame's: put away (degenerate).
			PackedByteArray blank;
			blank.resize((_last_used - n) * 8);
			std::memset(blank.ptrw(), 0, (size_t)((_last_used - n) * 8));
			rs->mesh_surface_update_vertex_region(_mesh, 0, n * 8, blank);
		}
		_last_used = n;
		rs->canvas_item_add_mesh(canvas, _mesh, Transform2D(), Color(1, 1, 1, 1));
		return true;
	}
};

} // namespace godot
