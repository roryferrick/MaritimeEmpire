// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rid.hpp>

#include "bird_batch.h"

#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

// Every bird of the wildlife's colonies as a permanent map object, worked out
// and drawn natively: the C++ side of scripts/sim/bird_life.gd (BirdLife), which
// builds it from Wildlife's colonies and Birds' species and hands it the map's
// spots, the ships and the birds' meshes through callables. Same rules as the
// GDScript it replaced: each bird's day goes in spells (each class its own
// length, each bird its own phase); at the start of each it picks what to do by
// its class and the hour and flies there from wherever it was, then does it;
// colonies on their migration fly in a V. Times are bird time (real seconds);
// the hour and seasons are the calendar's.
class BirdSim : public RefCounted {
	GDCLASS(BirdSim, RefCounted)

public:
	struct V2 {
		double x = 0.0;
		double y = 0.0;
	};

	enum Cls { GULLS, RAPTORS, CORMORANTS, WADERS, SEA_DUCKS, SEABIRDS, CLS_COUNT };
	enum Act { A_REST, A_SLEEP, A_SWIM, A_CIRCLE, A_PERCH, A_FOLLOW, A_SOAR, A_HUNT, A_STAND, A_STALK, A_GLIDE };
	enum Mode { M_FLY, M_CIRCLE, M_SOAR, M_GLIDE, M_HUNT, M_PERCH, M_REST, M_SLEEP, M_SWIM, M_DIVE, M_STAND, M_STALK, M_FOLLOW, MODE_COUNT };
	enum Where { W_HOME, W_AWAY, W_TO_AWAY, W_TO_HOME };

	struct State {
		V2 pos;
		double heading = 0.0; // NAN: from its movement.
		int mode = M_REST;
		double height = 0.0;
		double wings = 0.0;
		double splash = 0.0;
	};

private:
	struct Species {
		String id;
		double span = 1.0;
		bool night_heron = false;
		bool frigate = false; // Never settles on the water.
		bool hide = false;
		bool crane = false;
		double follow = 0.3;
		Color dot;
	};

	struct Colony {
		int cls = GULLS;
		int species = 0;
		int64_t seed = 0;
		int count = 0;
		V2 spot;
		V2 away_spot;
		int port = -1;
		int away_port = -1;
		double range_km = 500.0;
		int months = 0; // Bit m (1-12) set for a home month.
		int first_bird = 0;
		// Where it is (cached for the calendar hour).
		int64_t where_hour = INT64_MIN;
		int where = W_HOME;
		double progress = 0.0;
		// How many times it has set off or arrived: its birds' kept states and
		// bounds are from before a change (see Fixed, Bound epoch).
		int64_t changes = 0;
	};

	struct Bird {
		int colony = 0;
		int n = 0;
		int64_t seed = 0;
		bool hen = false;
		double length = 30.0;
		double phase = 0.0;
		// Its place in the perching order at its port and at the port it spends
		// its away months at (see _perch()), or -1.
		int perch_home = -1;
		int perch_away = -1;
	};

	struct Plan {
		bool valid = false;
		int64_t k = 0;
		bool away = false;
		double start = 0.0;
		int act = A_REST;
		V2 place;
		V2 to;
		bool has_to = false;
		double radius = 5.0;
		bool has_radius = false;
		bool dives = false;
		int64_t ship = -1;
		double facing = 0.0, turn = 1.0, speed = 0.1, angle0 = 0.0, height = 1.0;
		double hunt_phase = 0.0, dive_phase = 0.0, bend = 1.0;
		bool has_from = false;
		V2 from;
		double travel = 0.0;
		bool has_arrive = false;
		V2 arrive;
		bool has_still = false;
		State still;
	};

	struct Last {
		bool has = false;
		V2 pos;
		double time = 0.0;
		double heading = 0.0;
	};

	struct Fixed {
		State state;
		double until = -INFINITY;
		double since = INFINITY;
		int64_t epoch = -1;
	};

	struct Bound {
		double x0 = 0.0, y0 = 0.0, x1 = -1.0, y1 = -1.0; // A lon/lat box.
		double until = -INFINITY;
		int64_t epoch = -1;
	};

	struct Spots {
		bool asked = false;
		bool ready = false;
		V2 center;
		double radius_km = 15.0;
		bool has_radius = false;
		std::vector<V2> breakwater, shore, inland, sea;
		std::unordered_map<int, V2> homes;
		V2 roost;
		bool has_roost = false;
	};

	struct Hit {
		Vector2 at;
		float reach = 0.0f;
		int colony = 0;
	};

	std::vector<Species> _species;
	std::vector<Colony> _colonies;
	std::vector<Bird> _birds;
	std::vector<Plan> _plans;
	Array _following_stats; // [ms, states, colonies near] of the last following().
	std::vector<Last> _last;
	std::vector<Fixed> _fixed;
	std::vector<Bound> _bounds;
	std::vector<char> _joining;
	std::vector<V2> _join_from;
	std::vector<double> _join_since;
	std::vector<char> _still_drawn;
	std::vector<Spots> _spots;
	std::vector<String> _port_ids;
	HashMap<String, int> _port_index;
	HashMap<String, int> _species_index;
	double _migrate_days = 10.0;
	int64_t _where_changes = 0;
	// (Counted only when a colony with birds on the still layer changes: that layer is drawn again then.)
	// Season by home months, for the calendar hour.
	int64_t _season_hour = INT64_MIN;
	std::unordered_map<int, std::pair<int, double>> _seasons;

	Callable _spots_provider;
	Callable _ships_provider;
	Callable _mesh_provider;
	// The ships birds can follow, as of a frame: id -> (lon, lat).
	uint64_t _ships_frame = UINT64_MAX;
	std::vector<int64_t> _ship_ids;
	std::vector<V2> _ship_spots;
	std::unordered_map<int64_t, int> _ship_slot;
	// The birds' shapes (MapView's: see _shape()), each a triangle list, asked once.
	struct Shape {
		std::vector<Vector2> points;
		std::vector<Color> colors;
	};
	std::unordered_map<int64_t, Shape> _shapes;
	// The pass's batch: every bird's triangles, drawn in one go (see draw()).
	std::vector<Vector2> _batch_points;
	std::vector<Color> _batch_colors;
	BirdBatch _moving; // The birds on the move, as one mesh kept from frame to frame.
	std::vector<Hit> _hits;
	std::vector<Hit> _still_hits;
	double _still_redraw_at = -INFINITY;
	double _full_px = 4.0;
	int64_t _stats[12] = {};
	int64_t _still_epoch = -1;

	// The view, for a draw (see draw()).
	struct View {
		Vector3 right, up, toward;
		double radius = 1.0;
		Vector2 middle;
	} _view;

	// Maths shared with the GDScript (Wildlife, Birds, Geo).
	static double _mix(int64_t n);
	static V2 _disc_n(int64_t n);
	static V2 _offset(V2 spot, V2 km);
	// A perched bird's spot on its port's breakwater: its own (see Bird.perch_home).
	static V2 _perch(const std::vector<V2> &slots, int order, V2 fallback);
	// Where a bird on the water has paddled to (km east and north of its spot) and the way it faces (BirdLife._paddle()).
	static void _paddle(double now, int64_t seed, V2 &out, double &heading);
	static double _distance_km(V2 a, V2 b);
	static double _local_hour(double lon, double unix);
	static double _chance(const Array &parts);

	void _where(Colony &colony, double cal);
	std::pair<int, double> _season(int months, double cal);
	Spots &_port_spots(int port);
	void _ships_now();
	int64_t _ship_near(V2 spot, double km, int64_t seed);
	V2 _target(const Plan &plan, const Bird &bird, double now) const;
	Plan _plan(int index, bool away, int64_t k, double start, double cal, double now, bool with_from);
	State _doing(Plan &plan, const Bird &bird, const Colony &colony, double into, double now);
	State _spell_state(int index, bool away, double now, double cal);
	State _migrating(int index, double now);
	bool _bound(int index, double now, double cal, Bound &out);

	// Drawing.
	Vector2 _to_screen(V2 lon_lat) const;
	static bool _hidden(Vector2 at);
	Transform2D _basis(V2 spot, Vector2 at) const;
	const Shape &_shape(int kind, int species, bool hen, int step, int bucket);
	void _draw_one(int index, const State &state, Vector2 at, double span, double now, const Transform2D &basis);
	void _draw_shape(int kind, int species, bool hen, int step, Vector2 at, double angle, double span, double shadow_height);
	void _draw_wader_shadow(Vector2 at, double heading, const Species &info, double span, double neck, bool bill_up);
	void _draw_reeds(Vector2 at, double span, double now, double seed);
	// Into the batch: a triangle, a line as a quad, a filled oval (a circle when round), a ring.
	void _tri(Vector2 a, Vector2 b, Vector2 c, Color color);
	void _line(Vector2 from, Vector2 to, double width, Color color);
	void _oval(Vector2 at, double angle, Vector2 half, Color color, int segments = 14);
	void _ring(Vector2 at, double radius, int segments, Color color, double width);

protected:
	static void _bind_methods();

public:
	void setup(const Array &colonies, const Dictionary &species, double migrate_days);
	void set_providers(const Callable &spots, const Callable &ships, const Callable &meshes);
	int bird_count() const { return (int)_birds.size(); }
	PackedInt32Array birds_of(int colony) const;
	State state(int index, double now, double cal);
	Dictionary bird_state(int index, double now, double cal);
	Dictionary doing_counts(int colony, double now, double cal);
	Dictionary following(int64_t ship, Vector2 at, double now, double cal, int64_t cap = 0, int64_t max_states = 0);
	Array following_stats() const { return _following_stats; }
	int64_t where_changes() const { return _where_changes; }
	void forget_spots();
	bool draw(const RID &canvas, bool still, const Dictionary &params);
	int hit_at(Vector2 screen, double reach) const;
	double still_redraw_at() const { return _still_redraw_at; }
	int64_t still_epoch() const { return _still_epoch; }
	static String mode_name(int mode);
	Dictionary stats();
};

} // namespace godot
