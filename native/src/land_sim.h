// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

// The wildlife's land animals, worked out and drawn natively: the C++ side of
// Wildlife.land_state() and MapView._draw_wildlife()'s animals and their
// homes. The same rules, with Godot's own maths functions so they come out
// as the GDScript (and the group popups, which still ask it) has them.
class LandSim : public RefCounted {
	GDCLASS(LandSim, RefCounted)

public:
	struct V2 {
		double x = 0.0;
		double y = 0.0;
	};
	enum Mode { WALK, GRAZE, REST, SLEEP, DEN };
	struct State {
		V2 pos;
		double heading = 0.0;
		int mode = REST;
		bool young = false;
		double size = 6.0;
	};

private:
	struct Species {
		String id;
		double km = 6.0;
		int hibernate = 0; // Month bits.
		bool den_young = false;
		int active = 0; // 0 day, 1 night, 2 dusk.
		double roam_km = 30.0;
		double kmh = 3.0;
		bool migrates = false;
		int away_months = 0;
	};
	struct Group {
		int species = 0;
		int64_t seed = 0;
		V2 home;
		V2 away;
		int members = 1;
		int young = 0;
		String home_kind;
		bool has_home = false;
		// Its migration this calendar hour.
		int64_t season_hour = INT64_MIN;
		int where = 0; // 0 home, 1 away, 2 to away, 3 to home.
		double progress = 0.0;
		// Its region (asked once the map's regions are ready).
		bool region_known = false;
		String region;
	};
	struct Item {
		double y;
		RID texture;
		Vector2 at;
		double angle;
		double side;
		Color tint;
		bool z = false;
	};

	std::vector<Species> _species;
	std::vector<Group> _groups;
	double _migrate_days = 10.0;
	int64_t _month_hour = INT64_MIN;
	int _month = 1;
	std::unordered_map<std::string, RID> _textures;
	Callable _texture_provider;
	Callable _region_provider;

	static double _mix(int64_t n);
	static V2 _disc_n(int64_t n);
	static V2 _offset(V2 spot, V2 km);
	int _month_of(double cal);
	std::pair<int, double> _season(int away_months, double cal);
	V2 _base(Group &group, const Species &info, double cal);
	RID _texture(const String &name);

protected:
	static void _bind_methods();

public:
	void setup(const Array &groups, const Dictionary &land, double migrate_days, const Callable &textures, const Callable &regions);
	State state(int group, int member, double cal, double life_time);
	Array draw(const RID &canvas, const Dictionary &params);
};

} // namespace godot
