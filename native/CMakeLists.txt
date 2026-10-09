# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#
# The game's native (C++) code: a GDExtension (godot-cpp) the GDScript calls
# for its heaviest per-frame work. Built into addons/maritime_native/bin, which
# addons/maritime_native/maritime_native.gdextension loads. See native/README.md.
cmake_minimum_required(VERSION 3.17)
project(maritime_native LANGUAGES CXX)

set(GODOTCPP_API_VERSION "4.7" CACHE STRING "The Godot version whose API to build against")
add_subdirectory(godot-cpp)

add_library(maritime_native SHARED)
file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h")
target_sources(maritime_native PRIVATE ${SOURCES})
target_link_libraries(maritime_native PRIVATE godot-cpp)

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../addons/maritime_native/bin/")

set_target_properties(
    maritime_native
    PROPERTIES
        CXX_STANDARD 17
        CXX_EXTENSIONS OFF
        CXX_VISIBILITY_PRESET ${GODOTCPP_SYMBOL_VISIBILITY}
        POSITION_INDEPENDENT_CODE ON
        LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        PDB_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        PREFIX "lib"
        OUTPUT_NAME "maritime_native${GODOTCPP_SUFFIX}"
)

if(MSVC)
    # (No /fp:fast: the ships must come out exactly as the GDScript works them out.)
    target_compile_options(maritime_native PRIVATE /W3 /fp:precise $<$<CONFIG:Release>:/O2>)
endif()
