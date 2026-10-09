# Native code (C++)

The game's heaviest per-frame work runs in C++, as a GDExtension built with
[godot-cpp](https://github.com/godotengine/godot-cpp) (a git submodule at
`native/godot-cpp`, tag 10.0.0-stable, against Godot 4.7's API). The rest of
the game stays in GDScript and calls it.

| Class | What it does | GDScript side |
|---|---|---|
| `BirdSim` (`src/bird_sim.cpp`) | Every bird: where it is and what it's doing (the spells, migrations, still birds), culling, and drawing them onto the map's canvas items | `scripts/sim/bird_life.gd` (BirdLife: builds it, and does the same in GDScript if the library isn't there), `MapView._draw_bird_pass()`, `MapView._native_bird_mesh()` |
| `ShipStepper` (`src/ship_stepper.cpp`) | Each step's loop over the ships: a ship plainly sailing its leg moves, burns fuel and wears natively (calling GameState for its arrival, loss, at-risk check, storm factors and new legs, in the same order), and ships idle in port are skipped; every other ship goes to `GameState._advance()`. Checked to give exactly the same numbers as the GDScript (no `/fp:fast`) | `GameState._step()` (`use_ship_stepper`) |
| `LaneMath` (`src/lane_math.cpp`) | Sea lanes' geometry: their points and miles, speed and wear zones, canal crossings, and a ship's seconds along a leg (with its harbor speed), using Godot's own maths functions so the numbers match the GDScript to the last bit | `GameData.lane()`, `canal_crossings()`, `lane_zones()` (`native_lanes`), `Ship._leg_seconds()`, `_with_harbor_speed()` |
| `RouteFinder` (`src/route_finder.cpp`) | The AI rivals' loop search (`RivalAI._work_out_loops()`, with its legs, cargo and prices), giving the same loops in the same order (Godot's sort); fixed facts about pairs of ports are asked of the GDScript once and kept | `RivalAI._route_context()` and its `_route_*()` providers (`use_native_routes`) |
| `LandSim` (`src/land_sim.cpp`) | The land animals: where each is and what it's doing (`Wildlife.land_state()`'s rules), culling, and drawing them and their homes onto the wildlife layer | `MapView._draw_wildlife()`, `_land_texture()`, `_land_region()` |
| `DecorSim` (`src/decor_sim.cpp`) | The drawings on the land (trees, mountains, grass...): picking those in view and drawing them, nearer ones in front | `MapView._draw_decor()` |
| `PortPainter` (`src/port_painter.cpp`) | The ports' dots (all but the hubs, whose rings MapView adds) placed and drawn in one batch of triangles, their looks worked out by the GDScript only when they change; and which ports' marinas may show | `MapView._draw_ports()`, `_update_port_styles()`, `_update_marinas()` |
| `LandTest` (`src/land_test.cpp`) | Whether a point's on the land (the same answers as `MapView._on_land()`), and the search along a port's shore for its water's edge (`_shore_spots()`) | `MapView._on_land()`, `_shore_spots()` |
| `GustPainter` (`src/gust_painter.cpp`) | The wind's gusts on the map (`Wind`'s noise, Godot's own seeded randomness), all the streaks in one batch | `MapView._draw_gusts()`, `_gust_storm_wind()` |
| `SeaPainter` (`src/sea_painter.cpp`) | The sea animals of the pods in view: their places, shadows, surfacing, breaching and leaping, kept off the land | `MapView._draw_sea_life()`, `_sea_kind_index()` |
| `NativeProbe` | Says the library's loaded | |

The library is loaded by `addons/maritime_native/maritime_native.gdextension`
from `addons/maritime_native/bin/` (built files are committed, like GodotSteam's).

## Building (Windows)

Needs Visual Studio 2022 Build Tools (the C++ workload), CMake and Python 3
(godot-cpp generates its bindings with it). From `native/`:

```
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
cmake -S . -B build-release -G "Visual Studio 17 2022" -A x64 -DGODOTCPP_TARGET=template_release
cmake --build build-release --config Release
```

After that, `native/build.sh` (Git Bash) rebuilds both:

```
native/build.sh
```

The first makes the `template_debug` library the editor and debug runs use;
the second the `template_release` one exported games use. Close the game (the
editor reloads the library itself) before building.

When adding a class, register it in `src/register_types.cpp`.
