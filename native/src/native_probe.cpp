// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#include "native_probe.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void NativeProbe::_bind_methods() {
	ClassDB::bind_static_method("NativeProbe", D_METHOD("version"), &NativeProbe::version);
}

String NativeProbe::version() {
	return "maritime_native 1";
}

