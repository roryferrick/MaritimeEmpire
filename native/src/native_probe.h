// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

// Says the native code is loaded, and which build (GDScript checks for it:
// ClassDB.class_exists("NativeProbe")).
class NativeProbe : public RefCounted {
	GDCLASS(NativeProbe, RefCounted)

protected:
	static void _bind_methods();

public:
	static String version();
};

} // namespace godot
