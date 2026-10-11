// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// Registers the native classes with Godot (see native/CMakeLists.txt).

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "bird_sim.h"
#include "lane_math.h"
#include "lane_painter.h"
#include "decor_sim.h"
#include "land_test.h"
#include "gust_painter.h"
#include "globe_tiles.h"
#include "land_sim.h"
#include "native_probe.h"
#include "port_painter.h"
#include "route_finder.h"
#include "sea_painter.h"
#include "ship_culler.h"
#include "ship_stepper.h"
#include "town_mesh.h"

using namespace godot;

static void initialize_maritime_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(NativeProbe);
	GDREGISTER_CLASS(BirdSim);
	GDREGISTER_CLASS(ShipStepper);
	GDREGISTER_CLASS(ShipCuller);
	GDREGISTER_CLASS(LaneMath);
	GDREGISTER_CLASS(LanePainter);
	GDREGISTER_CLASS(RouteFinder);
	GDREGISTER_CLASS(LandSim);
	GDREGISTER_CLASS(DecorSim);
	GDREGISTER_CLASS(PortPainter);
	GDREGISTER_CLASS(LandTest);
	GDREGISTER_CLASS(GustPainter);
	GDREGISTER_CLASS(SeaPainter);
	GDREGISTER_CLASS(GlobeTiles);
	GDREGISTER_CLASS(TownMesh);
}

static void uninitialize_maritime_native(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT maritime_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_maritime_native);
	init_obj.register_terminator(uninitialize_maritime_native);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
