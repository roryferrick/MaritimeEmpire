// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rid.hpp>

namespace godot {

// The ports' dots on the map (MapView._draw_ports()'s draw_port, for every
// port but the hubs, whose rings MapView adds): placed on the globe as the
// view turns and drawn natively, with their looks (MapView._port_styles())
// worked out by the GDScript only when they change.
class PortPainter : public RefCounted {
	GDCLASS(PortPainter, RefCounted)

	PackedVector3Array _units;
	PackedFloat32Array _radii;
	PackedFloat32Array _layout_radii;
	PackedColorArray _fills;
	PackedByteArray _flags; // 1 locked, 2 shining, 4 skip (a hub: drawn by MapView), 8 dimmed.


protected:
	static void _bind_methods();

public:
	void set_units(const PackedVector3Array &units);
	void set_styles(const PackedFloat32Array &radii, const PackedFloat32Array &layout_radii, const PackedColorArray &fills, const PackedByteArray &flags);
	void draw(const RID &canvas, const PackedInt32Array &ports, const Dictionary &params);
	PackedInt32Array marinas(const PackedInt32Array &ports, const Dictionary &params);
};

} // namespace godot
