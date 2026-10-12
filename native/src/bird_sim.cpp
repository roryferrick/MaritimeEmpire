// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See bird_sim.h. Ported from scripts/sim/bird_life.gd and MapView's bird
// drawing; the numbers are theirs.
#include "bird_sim.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <numeric>

using namespace godot;

namespace {

constexpr double KM_PER_DEGREE = 111.32;
constexpr double EARTH_RADIUS_NM = 3440.065;
constexpr double MAX_LAT = 85.0;
constexpr double TAU_D = 6.283185307179586;
constexpr double PI_D = 3.141592653589793;

// Each class's spell length (s: the fewest and most), and how fast it flies (km a second).
const double SPELL_S[BirdSim::CLS_COUNT][2] = { { 18, 40 }, { 30, 70 }, { 25, 55 }, { 40, 90 }, { 45, 100 }, { 50, 130 } };
const double SPEED_KMS[BirdSim::CLS_COUNT] = { 2.4, 3.0, 3.2, 1.6, 3.4, 5.0 };
// Flying somewhere takes at most this share of a spell (it flies faster if it must).
constexpr double TRAVEL_SHARE = 0.8;
constexpr double GULL_FOLLOW_KM = 60.0;
constexpr double SEABIRD_FOLLOW_KM = 250.0;
constexpr double SEABIRD_ROAM_KM = 120.0;
constexpr double V_SPACING_KM = 4.5;
constexpr double NIGHT_FROM = 20.0;
constexpr double NIGHT_TO = 5.5;
constexpr double LAST_FRESH_S = 2.0;
constexpr double MIGRATION_JOIN_S = 25.0;
// Mesh sizes and wing steps (MapView BIRD_SIZE_STEP, BIRD_WING_STEP).
constexpr double SIZE_STEP = 1.12;
constexpr double WING_STEP = 0.05;
const Vector2 HIDDEN(-1.0e5, -1.0e5);

double smoothstep(double from, double to, double x) {
	if (from == to) {
		return x < from ? 0.0 : 1.0;
	}
	double s = std::clamp((x - from) / (to - from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

double deg2rad(double d) { return d * PI_D / 180.0; }
double rad2deg(double r) { return r * 180.0 / PI_D; }

double circle_speed(int act) {
	switch (act) {
		case BirdSim::A_CIRCLE: return 0.12;
		case BirdSim::A_SOAR: return 0.06;
		case BirdSim::A_GLIDE: return 0.035;
		case BirdSim::A_HUNT: return 0.09;
		default: return 0.1;
	}
}

double circle_height(int act) {
	switch (act) {
		case BirdSim::A_CIRCLE: return 1.3;
		case BirdSim::A_SOAR: return 2.2;
		case BirdSim::A_GLIDE: return 1.0;
		case BirdSim::A_HUNT: return 1.6;
		default: return 1.0;
	}
}

bool is_still(int act) {
	return act == BirdSim::A_STAND || act == BirdSim::A_PERCH || act == BirdSim::A_REST || act == BirdSim::A_SLEEP;
}

bool is_flying(int mode) {
	return mode == BirdSim::M_FLY || mode == BirdSim::M_CIRCLE || mode == BirdSim::M_SOAR || mode == BirdSim::M_GLIDE || mode == BirdSim::M_HUNT || mode == BirdSim::M_FOLLOW;
}

int cls_of(const String &name) {
	if (name == "gulls") return BirdSim::GULLS;
	if (name == "raptors") return BirdSim::RAPTORS;
	if (name == "cormorants") return BirdSim::CORMORANTS;
	if (name == "waders") return BirdSim::WADERS;
	if (name == "sea_ducks") return BirdSim::SEA_DUCKS;
	return BirdSim::SEABIRDS;
}

BirdSim::V2 v2(Vector2 v) { return { (double)v.x, (double)v.y }; }
Vector2 gv(BirdSim::V2 v) { return Vector2((real_t)v.x, (real_t)v.y); }

BirdSim::V2 lerp(BirdSim::V2 a, BirdSim::V2 b, double t) { return { a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t }; }

Vector3 unit(BirdSim::V2 lon_lat) {
	double lon = deg2rad(lon_lat.x);
	double lat = deg2rad(lon_lat.y);
	return Vector3((real_t)(std::cos(lat) * std::cos(lon)), (real_t)(std::cos(lat) * std::sin(lon)), (real_t)std::sin(lat));
}

BirdSim::V2 lon_lat_of(Vector3 p) {
	return { rad2deg(std::atan2((double)p.y, (double)p.x)), rad2deg(std::asin(std::clamp((double)p.z, -1.0, 1.0))) };
}

} // namespace

// --- Maths shared with the GDScript ---------------------------------------------

double BirdSim::_mix(int64_t n) {
	int64_t h = n & 0xffffffffLL;
	h = ((h ^ (h >> 16)) * 0x45d9f3bLL) & 0xffffffffLL;
	h = ((h ^ (h >> 16)) * 0x45d9f3bLL) & 0xffffffffLL;
	h ^= h >> 16;
	return (double)(h & 0x7fffffffLL) / (double)0x7fffffffLL;
}

BirdSim::V2 BirdSim::_disc_n(int64_t n) {
	double angle = _mix(n) * TAU_D;
	double r = std::sqrt(_mix(n ^ 0x5bd1e995LL));
	return { std::cos(angle) * r, std::sin(angle) * r };
}

BirdSim::V2 BirdSim::_offset(V2 spot, V2 km) {
	return { spot.x + km.x / (KM_PER_DEGREE * std::max(std::cos(deg2rad(spot.y)), 0.1)), spot.y + km.y / KM_PER_DEGREE };
}

double BirdSim::_distance_km(V2 a, V2 b) {
	double lat1 = deg2rad(a.y);
	double lat2 = deg2rad(b.y);
	double dlat = lat2 - lat1;
	double dlon = deg2rad(b.x - a.x);
	double h = std::pow(std::sin(dlat / 2.0), 2) + std::cos(lat1) * std::cos(lat2) * std::pow(std::sin(dlon / 2.0), 2);
	return 2.0 * EARTH_RADIUS_NM * std::asin(std::min(1.0, std::sqrt(h))) * 1.852;
}

double BirdSim::_local_hour(double lon, double unix) {
	double day = std::fmod(std::fmod(unix, 86400.0) + 86400.0, 86400.0);
	double hour = day / 3600.0 + lon / 15.0;
	return std::fmod(std::fmod(hour, 24.0) + 24.0, 24.0);
}

double BirdSim::_chance(const Array &parts) {
	int64_t h = (int64_t)UtilityFunctions::str(parts).hash() & 0xffffffffLL;
	h = ((h ^ (h >> 16)) * 0x45d9f3bLL) & 0xffffffffLL;
	h = ((h ^ (h >> 16)) * 0x45d9f3bLL) & 0xffffffffLL;
	h ^= h >> 16;
	return (double)(h & 0x7fffffffLL) / (double)0x7fffffffLL;
}

// --- Setting up -------------------------------------------------------------------

void BirdSim::setup(const Array &colonies, const Dictionary &species, double migrate_days) {
	_migrate_days = migrate_days;
	_species.clear();
	_species_index.clear();
	Array ids = species.keys();
	for (int i = 0; i < ids.size(); i++) {
		String id = ids[i];
		Dictionary info = species[id];
		Species s;
		s.id = id;
		s.span = info.get("span", 1.0);
		String kind = info.get("kind", "");
		// About by night, asleep by day: night herons, and owls but those active by day (the snowy owl).
		s.night_heron = kind == "Night heron" || (kind == "Owl" && String(info.get("active", "night")) != "day");
		s.frigate = kind == "Frigatebird";
		s.crane = kind == "Crane";
		s.hide = String(info.get("behavior", "")) == "hide";
		Array follow = info.get("follow", Array());
		s.follow = follow.is_empty() ? 0.3 : (double)follow[0];
		Dictionary colors = info.get("colors", Dictionary());
		s.dot = Color::from_string(colors.get("mantle", "#aab4bd"), Color(0.5, 0.5, 0.5));
		_species_index[id] = (int)_species.size();
		_species.push_back(s);
	}
	_colonies.clear();
	_birds.clear();
	_port_ids.clear();
	_port_index.clear();
	auto port_of = [this](const String &id) -> int {
		if (id.is_empty()) {
			return -1;
		}
		if (!_port_index.has(id)) {
			_port_index[id] = (int)_port_ids.size();
			_port_ids.push_back(id);
		}
		return _port_index[id];
	};
	for (int i = 0; i < colonies.size(); i++) {
		Dictionary c = colonies[i];
		Colony colony;
		colony.cls = cls_of(c.get("cls", ""));
		String id = c.get("species", "");
		colony.species = _species_index.has(id) ? _species_index[id] : 0;
		colony.seed = (int64_t)c.get("seed", 0);
		colony.count = c.get("count", 0);
		colony.spot = v2(c.get("spot", Vector2()));
		colony.away_spot = v2(c.get("away_spot", Vector2()));
		colony.port = port_of(c.get("port", ""));
		colony.away_port = port_of(c.get("away_port", ""));
		colony.range_km = c.get("range_km", 500.0);
		Array months = c.get("home_months", Array());
		for (int m = 0; m < months.size(); m++) {
			colony.months |= 1 << (int)(double)months[m];
		}
		colony.first_bird = (int)_birds.size();
		for (int n = 0; n < colony.count; n++) {
			Bird bird;
			bird.colony = i;
			bird.n = n;
			bird.seed = colony.seed * 977 + n * 131;
			bird.hen = colony.cls == SEA_DUCKS && n % 2 == 1;
			bird.length = SPELL_S[colony.cls][0] + (SPELL_S[colony.cls][1] - SPELL_S[colony.cls][0]) * _mix(bird.seed);
			bird.phase = _mix(bird.seed + 1);
			_birds.push_back(bird);
		}
		_colonies.push_back(colony);
	}
	// Perching order at each port: its own birds (gulls and cormorants, the
	// ones that perch on the rocks and the breakwater) first, then those spending their away
	// months there, so each has its own spot (see _perch()).
	std::vector<int> perchers(_port_ids.size(), 0);
	for (int away = 0; away < 2; away++) {
		for (Bird &bird : _birds) {
			const Colony &colony = _colonies[(size_t)bird.colony];
			int port = away ? colony.away_port : colony.port;
			if ((colony.cls == GULLS || colony.cls == CORMORANTS) && port >= 0) {
				(away ? bird.perch_away : bird.perch_home) = perchers[(size_t)port]++;
			}
		}
	}
	size_t n = _birds.size();
	_plans.assign(n, Plan());
	_last.assign(n, Last());
	_fixed.assign(n, Fixed());
	_bounds.assign(n, Bound());
	_joining.assign(n, 0);
	_join_from.assign(n, V2());
	_join_since.assign(n, 0.0);
	_still_drawn.assign(n, 0);
	_spots.assign(_port_ids.size(), Spots());
	_shapes.clear();
}

void BirdSim::set_providers(const Callable &spots, const Callable &ships, const Callable &meshes) {
	_spots_provider = spots;
	_ships_provider = ships;
	_mesh_provider = meshes;
}

void BirdSim::forget_spots() {
	_spots.assign(_port_ids.size(), Spots());
}

PackedInt32Array BirdSim::birds_of(int colony) const {
	PackedInt32Array out;
	if (colony < 0 || colony >= (int)_colonies.size()) {
		return out;
	}
	const Colony &c = _colonies[colony];
	for (int i = 0; i < c.count; i++) {
		out.push_back(c.first_bird + i);
	}
	return out;
}

// --- Where colonies are (Wildlife.colony_where()) -------------------------------

std::pair<int, double> BirdSim::_season(int months, double cal) {
	Time *time = Time::get_singleton();
	Dictionary date = time->get_datetime_dict_from_unix_time((int64_t)cal);
	int month = date["month"];
	auto home = [months](int m) { return (months & (1 << m)) != 0; };
	bool away = !home(month);
	int start_month = month;
	for (int step = 0; step < 11; step++) {
		int before = (start_month + 10) % 12 + 1;
		if (!home(before) != away) {
			break;
		}
		start_month = before;
	}
	Dictionary start_date;
	start_date["year"] = start_month <= month ? (int)date["year"] : (int)date["year"] - 1;
	start_date["month"] = start_month;
	start_date["day"] = 1;
	start_date["hour"] = 0;
	start_date["minute"] = 0;
	start_date["second"] = 0;
	double start = (double)time->get_unix_time_from_datetime_dict(start_date);
	double days = (cal - start) / 86400.0;
	if (days < _migrate_days) {
		return { away ? W_TO_AWAY : W_TO_HOME, std::clamp(days / _migrate_days, 0.0, 1.0) };
	}
	return { away ? W_AWAY : W_HOME, 0.0 };
}

void BirdSim::_where(Colony &colony, double cal) {
	if ((colony.months & 0x1ffe) == 0x1ffe) {
		colony.where = W_HOME;
		return;
	}
	int64_t hour = (int64_t)std::floor(cal / 3600.0);
	if (colony.where_hour == hour) {
		return;
	}
	if (_season_hour != hour) {
		_season_hour = hour;
		_seasons.clear();
	}
	auto found = _seasons.find(colony.months);
	if (found == _seasons.end()) {
		found = _seasons.emplace(colony.months, _season(colony.months, cal)).first;
	}
	bool first = colony.where_hour == INT64_MIN;
	int was = colony.where;
	colony.where_hour = hour;
	colony.where = found->second.first;
	colony.progress = found->second.second;
	if (!first && was != colony.where) {
		// Its own birds are worked out again (their epoch); the still layer is
		// drawn again only if any of them are on it (a change far away costs nothing here).
		colony.changes++;
		for (int i = 0; i < colony.count; i++) {
			int b = colony.first_bird + i;
			if (b < (int)_still_drawn.size() && _still_drawn[b]) {
				_where_changes++;
				break;
			}
		}
	}
}

// --- Ports' spots and ships -------------------------------------------------------

BirdSim::Spots &BirdSim::_port_spots(int port) {
	static Spots none;
	if (port < 0) {
		return none;
	}
	Spots &spots = _spots[port];
	if (spots.ready || !_spots_provider.is_valid()) {
		return spots;
	}
	_stats[0]++;
	Dictionary d = _spots_provider.call(_port_ids[port]);
	if (d.is_empty()) {
		return spots; // (Not ready yet: the map's land is still being sorted.)
	}
	spots.ready = true;
	spots.center = v2(d.get("center", Vector2()));
	spots.has_radius = d.has("radius_km");
	spots.radius_km = d.get("radius_km", 15.0);
	auto list = [](const Variant &v, std::vector<V2> &out) {
		Array a = v;
		out.clear();
		for (int i = 0; i < a.size(); i++) {
			out.push_back(v2(a[i]));
		}
	};
	list(d.get("perches", d.get("breakwater", Array())), spots.breakwater); // (The rocks' spots first, then the breakwater's.)
	list(d.get("shore", Array()), spots.shore);
	list(d.get("inland", Array()), spots.inland);
	list(d.get("sea", Array()), spots.sea);
	Dictionary homes = d.get("homes", Dictionary());
	Array keys = homes.keys();
	for (int i = 0; i < keys.size(); i++) {
		spots.homes[(int)keys[i]] = v2(homes[keys[i]]);
	}
	spots.has_roost = d.has("roost");
	spots.roost = v2(d.get("roost", Vector2()));
	return spots;
}

void BirdSim::_ships_now() {
	uint64_t frame = Engine::get_singleton()->get_process_frames();
	if (frame == _ships_frame) {
		return;
	}
	_ships_frame = frame;
	_ship_ids.clear();
	_ship_spots.clear();
	_ship_slot.clear();
	if (!_ships_provider.is_valid()) {
		return;
	}
	_stats[1]++;
	Array got = _ships_provider.call();
	if (got.size() < 2) {
		return;
	}
	PackedInt64Array ids = got[0];
	PackedVector2Array spots = got[1];
	for (int i = 0; i < ids.size() && i < spots.size(); i++) {
		_ship_slot[ids[i]] = (int)_ship_ids.size();
		_ship_ids.push_back(ids[i]);
		_ship_spots.push_back(v2(spots[i]));
	}
}

int64_t BirdSim::_ship_near(V2 spot, double km, int64_t seed) {
	_ships_now();
	std::vector<int64_t> near;
	double reach = km / KM_PER_DEGREE;
	for (size_t i = 0; i < _ship_ids.size(); i++) {
		V2 at = _ship_spots[i];
		if (std::abs(at.y - spot.y) > reach) {
			continue;
		}
		if (_distance_km(at, spot) <= km) {
			near.push_back(_ship_ids[i]);
		}
	}
	if (near.empty()) {
		return -1;
	}
	return near[(size_t)((int64_t)(_mix(seed) * near.size()) % (int64_t)near.size())];
}

BirdSim::V2 BirdSim::_target(const Plan &plan, const Bird &bird, double now) const {
	if (plan.act == A_FOLLOW) {
		auto slot = _ship_slot.find(plan.ship);
		if (slot != _ship_slot.end()) {
			// Behind and off to a side of it, by the bird.
			V2 d = _disc_n(bird.seed + 3);
			return _offset(_ship_spots[slot->second], { d.x * 8.0, d.y * 8.0 });
		}
	}
	return plan.place;
}

// Its own slot (`order`, see Bird.perch_home) among a port's perching spots
// (MapView._bird_spots() perches: those on the rocks first, then along the
// breakwater), taken in order so the rocks fill first. Each bird has its own
// while there are as many slots as perching birds; past that, two share one,
// and only meet if both perch at once.
// BirdLife._paddle(): along a slow wandering line it only moves along while it
// paddles (a stretch every so often, sitting and bobbing between), within about a km.
void BirdSim::_paddle(double now, int64_t seed, V2 &out, double &heading) {
	const double rate = 0.04, speed = 0.012, km = 1.0;
	double phase = (double)(seed % 101) / 101.0 * TAU_D;
	double u = now * speed + speed / rate * 0.9 * std::sin(now * rate + phase);
	double a = (double)(seed % 17) / 17.0 * TAU_D;
	double b = (double)(seed % 23) / 23.0 * TAU_D;
	out = { (std::sin(u + a) + 0.35 * std::sin(2.7 * u + b)) * km + std::sin(now * 0.05 + (double)(seed % 13)) * 0.15,
		(std::cos(0.8 * u + b) + 0.35 * std::cos(2.3 * u + a)) * km + std::cos(now * 0.04 + (double)(seed % 7)) * 0.15 };
	double vx = std::cos(u + a) + 0.945 * std::cos(2.7 * u + b);
	double vy = -0.8 * std::sin(0.8 * u + b) - 0.805 * std::sin(2.3 * u + a);
	heading = std::atan2(vy, vx);
}

BirdSim::V2 BirdSim::_perch(const std::vector<V2> &slots, int order, V2 fallback) {
	const int64_t n = (int64_t)slots.size();
	if (n == 0) {
		return fallback;
	}
	return slots[(size_t)((int64_t)std::max(order, 0) % n)];
}

// --- Spells -------------------------------------------------------------------

BirdSim::Plan BirdSim::_plan(int index, bool away, int64_t k, double start, double cal, double now, bool with_from) {
	const Bird &bird = _birds[index];
	const Colony &colony = _colonies[bird.colony];
	const Species &info = _species[colony.species];
	int cls = colony.cls;
	Spots &spots = _port_spots(away ? colony.away_port : colony.port);
	V2 fallback = away ? colony.away_spot : colony.spot;
	V2 center = spots.ready ? spots.center : fallback;
	V2 home = center;
	if (!away) {
		auto found = spots.homes.find(bird.colony);
		if (spots.ready && found != spots.homes.end()) {
			home = found->second;
		}
	} else if (spots.ready && spots.has_roost) {
		home = spots.roost;
	}
	double radius_km = spots.ready && spots.has_radius ? spots.radius_km : 15.0;
	double hour = _local_hour(center.x, cal);
	bool night = hour < NIGHT_TO || hour > NIGHT_FROM;
	if (info.night_heron) {
		night = !night;
	}
	double roll = _mix(bird.seed + k * 7919);
	// Ducks and cormorants keep together: their colony picks for them.
	double group_roll = _mix(colony.seed + k * 7919);
	Plan plan;
	plan.valid = true;
	plan.k = k;
	plan.away = away;
	plan.start = start;
	plan.act = A_REST;
	plan.place = home;
	auto pick = [&](const std::vector<V2> &list, int64_t salt) -> V2 {
		if (list.empty()) {
			return center;
		}
		int64_t i = (int64_t)(_mix(bird.seed + k * 31 + salt) * (double)list.size()) % (int64_t)list.size();
		return list[(size_t)i];
	};
	switch (cls) {
		case GULLS:
			if (night) {
				plan.act = roll < 0.85 ? A_SLEEP : A_SWIM;
				plan.place = plan.act == A_SLEEP ? home : pick(spots.sea, 1);
			} else if (roll < 0.33) {
				plan.act = A_CIRCLE;
				plan.place = center;
				plan.radius = radius_km * (0.5 + 0.7 * _mix(bird.seed + k * 3));
				plan.has_radius = true;
			} else if (roll < 0.53) {
				plan.act = A_PERCH;
				plan.place = _perch(spots.breakwater, away ? bird.perch_away : bird.perch_home, center);
			} else if (roll < 0.68) {
				plan.act = A_SWIM;
				plan.place = pick(spots.sea, 3);
			} else if (roll < 0.88 && _ship_near(center, GULL_FOLLOW_KM, bird.seed + k) >= 0) {
				plan.act = A_FOLLOW;
				plan.ship = _ship_near(center, GULL_FOLLOW_KM, bird.seed + k);
			} else {
				plan.act = A_REST;
			}
			break;
		case RAPTORS:
			if (night) {
				plan.act = A_SLEEP;
			} else if (roll < 0.35) {
				plan.act = A_PERCH;
				plan.place = pick(spots.inland, 4);
			} else if (roll < 0.65) {
				plan.act = A_SOAR;
				plan.place = pick(spots.inland, 5);
				plan.radius = 3.0 + 4.0 * _mix(bird.seed + k * 5);
				plan.has_radius = true;
			} else if (roll < 0.9) {
				plan.act = A_HUNT;
				plan.place = pick(spots.sea, 6);
				plan.radius = 2.0 + 2.0 * _mix(bird.seed + k * 9);
				plan.has_radius = true;
			}
			break;
		case CORMORANTS:
			if (night) {
				plan.act = A_SLEEP;
			} else if (group_roll < 0.4) {
				plan.act = A_PERCH;
				plan.place = _perch(spots.breakwater, away ? bird.perch_away : bird.perch_home, center);
			} else if (group_roll < 0.82) {
				plan.act = A_SWIM;
				if (spots.sea.empty()) {
					plan.place = center;
				} else {
					plan.place = spots.sea[(size_t)((int64_t)(group_roll * 997) % (int64_t)spots.sea.size())];
				}
				plan.dives = true;
			} else {
				plan.act = A_CIRCLE;
				plan.place = center;
				plan.radius = radius_km * 1.6;
				plan.has_radius = true;
			}
			break;
		case WADERS:
			if (night) {
				plan.act = A_SLEEP;
			} else if (info.hide || roll < 0.5) {
				plan.act = A_STAND;
				plan.place = pick(spots.shore, 8);
			} else if (roll < 0.85) {
				plan.act = A_STALK;
				plan.place = pick(spots.shore, 9);
				plan.to = pick(spots.shore, 10);
				plan.has_to = true;
			}
			break;
		case SEA_DUCKS: {
			// A raft off the port, day and night, now and then flying round together.
			std::vector<V2> one = { center };
			const std::vector<V2> &sea = spots.sea.empty() ? one : spots.sea;
			if (group_roll < 0.88 || night) {
				plan.act = A_SWIM;
				size_t i = (size_t)((int64_t)(_mix(colony.seed + k) * (double)sea.size()) % (int64_t)std::max<size_t>(sea.size(), 1));
				V2 d = _disc_n(bird.seed);
				double r = 1.0 + 0.4 * colony.count;
				plan.place = _offset(sea[i], { d.x * r, d.y * r });
				plan.dives = !night;
			} else {
				plan.act = A_CIRCLE;
				plan.place = center;
				plan.radius = radius_km * 1.8;
				plan.has_radius = true;
			}
			break;
		}
		case SEABIRDS: {
			V2 base = away ? colony.away_spot : colony.spot;
			// Wandering out over the sea, a stretch at a time.
			V2 a = _disc_n(bird.seed + (k / 6) * 104729);
			V2 out = _offset(base, { a.x * colony.range_km * 0.6, a.y * colony.range_km * 0.6 });
			V2 b = _disc_n(bird.seed + k * 7);
			V2 spot = _offset(out, { b.x * SEABIRD_ROAM_KM, b.y * SEABIRD_ROAM_KM });
			int64_t ship = _ship_near(spot, SEABIRD_FOLLOW_KM, bird.seed + k);
			if (night) {
				plan.act = info.frigate ? A_GLIDE : A_SWIM; // (A frigatebird never settles on the water.)
				plan.place = spot;
				plan.radius = 8.0 + 17.0 * _mix(bird.seed + k * 11);
				plan.has_radius = true;
			} else if (roll < 0.35 && ship >= 0) {
				Array parts;
				parts.push_back("follow");
				parts.push_back(ship);
				parts.push_back(info.id);
				if (_chance(parts) < info.follow + 0.3) {
					plan.act = A_FOLLOW;
					plan.ship = ship;
				} else {
					plan.act = A_GLIDE;
					plan.place = spot;
					plan.radius = 8.0 + 17.0 * _mix(bird.seed + k * 11);
					plan.has_radius = true;
				}
			} else if (roll < 0.8) {
				plan.act = A_GLIDE;
				plan.place = spot;
				plan.radius = 8.0 + 17.0 * _mix(bird.seed + k * 11);
				plan.has_radius = true;
			} else {
				plan.act = info.frigate ? A_GLIDE : A_SWIM;
				plan.place = spot;
				plan.radius = 8.0 + 17.0 * _mix(bird.seed + k * 11);
				plan.has_radius = true;
			}
			break;
		}
	}
	plan.facing = _mix(bird.seed + k * 13) * TAU_D;
	// Worked out once a spell: which way it circles and how fast, where on its
	// circle it starts, how high, its own rhythm for hunting and diving, and
	// which way its flight there bends.
	int64_t seed = bird.seed;
	plan.turn = seed % 2 == 0 ? 1.0 : -1.0;
	plan.speed = circle_speed(plan.act) * plan.turn;
	plan.angle0 = _mix(seed + 5) * TAU_D;
	plan.height = circle_height(plan.act);
	plan.hunt_phase = _mix(seed + 9);
	plan.dive_phase = _mix(seed + 2);
	plan.bend = _mix(seed + k) < 0.5 ? 1.0 : -1.0;
	if (!with_from) {
		return plan;
	}
	// Where it flies from: where it really was, if it was just seen; else where
	// its last spell left it (worked out again), so it's never anywhere new.
	double length = bird.length;
	const Last &last = _last[index];
	if (last.has && now - last.time < LAST_FRESH_S) {
		plan.from = last.pos;
	} else {
		Plan before = _plan(index, away, k - 1, start - length, cal, start, false);
		plan.from = _doing(before, bird, colony, length, start).pos;
	}
	plan.has_from = true;
	if (plan.act == A_FOLLOW) {
		_ships_now();
	}
	// (To where it starts circling, on its circle, for the circling kinds.)
	double distance = _distance_km(plan.from, _doing(plan, bird, colony, 0.0, start).pos);
	plan.travel = std::min(distance / SPEED_KMS[cls], length * TRAVEL_SHARE);
	return plan;
}

BirdSim::State BirdSim::_doing(Plan &plan, const Bird &bird, const Colony &colony, double into, double now) {
	if (plan.act == A_FOLLOW) {
		_ships_now();
	}
	V2 target = _target(plan, bird, now);
	double flap = 0.75 + 0.25 * std::abs(std::sin(now * 9.0 + (double)(bird.seed % 97)));
	State s;
	if (plan.has_from && into < plan.travel) {
		// Flying to just where the thing starts (so it carries straight on into
		// it); kept with the spell where that's fixed (not drifting on the
		// water, nor following a ship).
		V2 arrive;
		if (plan.has_arrive) {
			arrive = plan.arrive;
		} else {
			arrive = _doing(plan, bird, colony, plan.travel, now).pos;
			if (plan.act != A_SWIM && plan.act != A_FOLLOW) {
				plan.arrive = arrive;
				plan.has_arrive = true;
			}
		}
		double u = into / std::max(plan.travel, 0.001);
		V2 from = plan.from;
		V2 along = lerp(from, arrive, smoothstep(0.0, 1.0, u));
		// A gentle curve, not a ruler line.
		double gx = (arrive.x - from.x) * std::cos(deg2rad(along.y));
		double gy = arrive.y - from.y;
		double f = std::sin(u * PI_D) * 0.12 * plan.bend;
		double bx = gy * f; // (Vector2.orthogonal(): (y, -x).)
		double by = -gx * f;
		along.x += bx / std::max(std::cos(deg2rad(along.y)), 0.1);
		along.y += by;
		s.pos = along;
		s.heading = NAN;
		s.mode = M_FLY;
		s.height = 1.2;
		s.wings = flap;
		return s;
	}
	double since = into - plan.travel;
	int64_t seed = bird.seed;
	switch (plan.act) {
		case A_CIRCLE:
		case A_SOAR:
		case A_GLIDE:
		case A_HUNT: {
			// At its full size from the start: its flight there ends just where it
			// joins its circle (not at the middle, flung out to it).
			double radius = plan.has_radius ? plan.radius : 5.0;
			double angle = plan.angle0 + since * plan.speed;
			s.pos = _offset(target, { std::cos(angle) * radius, std::sin(angle) * radius });
			s.height = plan.height;
			if (plan.act == A_HUNT) {
				// Now and then plunging in, then up again.
				double cycle = std::fmod(since / 14.0 + plan.hunt_phase, 1.0);
				if (cycle > 0.8) {
					double dip = std::sin((cycle - 0.8) / 0.2 * PI_D);
					s.height *= 1.0 - dip;
					s.splash = dip > 0.8 ? dip : 0.0;
				}
			}
			s.heading = angle + PI_D / 2.0 * plan.turn;
			s.mode = plan.act == A_CIRCLE ? M_CIRCLE : (plan.act == A_SOAR ? M_SOAR : (plan.act == A_GLIDE ? M_GLIDE : M_HUNT));
			s.wings = plan.act != A_CIRCLE ? 1.0 : flap;
			return s;
		}
		case A_FOLLOW:
			s.pos = target;
			s.heading = NAN;
			s.mode = M_FOLLOW;
			s.height = 1.2;
			s.wings = flap;
			return s;
		case A_SWIM: {
			// Sitting on the water, bobbing, and now and then paddling about.
			V2 paddled;
			double facing;
			_paddle(now, seed, paddled, facing);
			s.pos = _offset(target, paddled);
			s.mode = M_SWIM;
			if (plan.dives) {
				double cycle = std::fmod(since / (20.0 + (double)(seed % 9)) + plan.dive_phase, 1.0);
				if (cycle > 0.6) {
					s.mode = M_DIVE;
				}
			}
			s.heading = facing + 0.2 * std::sin(now * 0.3 + (double)(seed % 5));
			s.wings = 0.2;
			return s;
		}
		case A_STAND:
			s.pos = target;
			s.heading = plan.facing;
			s.mode = M_STAND;
			return s;
		case A_STALK: {
			V2 to = plan.has_to ? plan.to : target;
			double u = 0.5 - 0.5 * std::cos(since * 0.03 + (double)(seed % 11));
			s.pos = lerp(target, to, u);
			s.heading = NAN;
			s.mode = M_STALK;
			return s;
		}
		case A_PERCH: {
			bool drying = colony.cls == CORMORANTS && std::sin(now * 0.12 + (double)(seed % 17)) > 0.55;
			s.pos = target;
			s.heading = plan.facing;
			s.mode = M_PERCH;
			s.height = 0.03;
			s.wings = drying ? 0.7 : 0.2;
			return s;
		}
		case A_SLEEP: {
			V2 d = _disc_n(seed);
			s.pos = _offset(target, { d.x * 1.2, d.y * 1.2 });
			s.heading = plan.facing;
			s.mode = M_SLEEP;
			s.wings = 0.15;
			return s;
		}
		default: {
			V2 d = _disc_n(seed);
			s.pos = _offset(target, { d.x * 1.5, d.y * 1.5 });
			s.heading = plan.facing;
			s.mode = M_REST;
			s.wings = 0.2;
			return s;
		}
	}
}

BirdSim::State BirdSim::_spell_state(int index, bool away, double now, double cal) {
	const Bird &bird = _birds[index];
	const Colony &colony = _colonies[bird.colony];
	double length = bird.length;
	double t = now + bird.phase * length;
	int64_t k = (int64_t)std::floor(t / length);
	double into = t - (double)k * length;
	Plan &plan = _plans[index];
	if (!plan.valid || plan.k != k || plan.away != away) {
		_stats[2]++;
		plan = _plan(index, away, k, now - into, cal, now, true);
	}
	// Once there, a bird standing, perched, resting or asleep is just so (but a
	// cormorant drying its wings): kept, not worked out again every frame.
	double since = now - plan.start;
	if (since >= plan.travel && plan.has_still) {
		Fixed &fixed = _fixed[index];
		fixed.state = plan.still;
		fixed.until = plan.start + length;
		fixed.since = now;
		fixed.epoch = colony.changes;
		return plan.still;
	}
	State state = _doing(plan, bird, colony, since, now);
	if (since >= plan.travel && is_still(plan.act) && !(plan.act == A_PERCH && colony.cls == CORMORANTS)) {
		plan.still = state;
		plan.has_still = true;
	}
	return state;
}

BirdSim::State BirdSim::_migrating(int index, double now) {
	const Bird &bird = _birds[index];
	const Colony &colony = _colonies[bird.colony];
	bool to_home = colony.where == W_TO_HOME;
	V2 from = to_home ? colony.away_spot : colony.spot;
	V2 to = to_home ? colony.spot : colony.away_spot;
	double p = colony.progress;
	Vector3 a = unit(from);
	Vector3 b = unit(to);
	V2 lead = lon_lat_of(a.slerp(b, (real_t)p));
	V2 ahead = lon_lat_of(a.slerp(b, (real_t)std::min(p + 0.001, 1.0)));
	double wx = (ahead.x - lead.x) * std::cos(deg2rad(lead.y));
	double wy = ahead.y - lead.y;
	double wl = std::sqrt(wx * wx + wy * wy);
	if (wl > 0.0) {
		wx /= wl;
		wy /= wl;
	} else {
		wx = 1.0;
		wy = 0.0;
	}
	// Its place in the V: the leader at the point, the rest back along either arm by turns.
	int n = bird.n;
	int rank = (n + 1) / 2;
	double arm = n == 0 ? 0.0 : (n % 2 == 1 ? 1.0 : -1.0);
	V2 back = { -wx * rank * V_SPACING_KM + wy * arm * rank * V_SPACING_KM * 0.9, -wy * rank * V_SPACING_KM - wx * arm * rank * V_SPACING_KM * 0.9 };
	V2 pos = _offset(lead, back);
	// Joining the V from wherever it was (if it was just seen), over MIGRATION_JOIN_S.
	if (!_joining[index]) {
		const Last &last = _last[index];
		_joining[index] = 1;
		_join_from[index] = last.has && now - last.time < LAST_FRESH_S ? last.pos : pos;
		_join_since[index] = now;
	}
	double u = smoothstep(0.0, MIGRATION_JOIN_S, now - _join_since[index]);
	State s;
	s.mode = M_FLY;
	s.wings = 0.8 + 0.2 * std::sin(now * 5.0 + n * 0.7);
	if (u < 1.0) {
		s.pos = lerp(_join_from[index], pos, u);
		s.heading = NAN;
		s.height = 2.0;
		return s;
	}
	s.pos = pos;
	s.heading = std::atan2(wy, wx);
	s.height = 2.5;
	return s;
}

BirdSim::State BirdSim::state(int index, double now, double cal) {
	// Standing, perched, resting or asleep: just so till its spell ends (or a
	// colony sets off somewhere or arrives).
	Bird &bird = _birds[index];
	Colony &colony = _colonies[bird.colony];
	const Fixed &fixed = _fixed[index];
	if (now < fixed.until && now >= fixed.since && fixed.epoch == colony.changes) {
		return fixed.state;
	}
	_where(colony, cal);
	State s;
	if (colony.where == W_TO_HOME || colony.where == W_TO_AWAY) {
		s = _migrating(index, now);
	} else {
		_joining[index] = 0;
		s = _spell_state(index, colony.where == W_AWAY, now, cal);
	}
	// Its heading from how it moved since last time, when it's moving.
	Last &last = _last[index];
	if (std::isnan(s.heading)) {
		s.heading = 0.0;
		if (last.has) {
			double mx = (s.pos.x - last.pos.x) * std::cos(deg2rad(s.pos.y));
			double my = s.pos.y - last.pos.y;
			if (std::sqrt(mx * mx + my * my) > 0.00001) {
				s.heading = std::atan2(my, mx);
			} else {
				s.heading = last.heading;
			}
		}
	}
	last.has = true;
	last.pos = s.pos;
	last.time = now;
	last.heading = s.heading;
	return s;
}

bool BirdSim::_bound(int index, double now, double cal, Bound &out) {
	const Bird &bird = _birds[index];
	Colony &colony = _colonies[bird.colony];
	_where(colony, cal);
	if (colony.where == W_TO_HOME || colony.where == W_TO_AWAY) {
		return false;
	}
	double length = bird.length;
	double t = now + bird.phase * length;
	int64_t k = (int64_t)std::floor(t / length);
	bool away = colony.where == W_AWAY;
	Plan &plan = _plans[index];
	if (!plan.valid || plan.k != k || plan.away != away) {
		_stats[2]++;
		plan = _plan(index, away, k, now - (t - (double)k * length), cal, now, true);
	}
	if (plan.act == A_FOLLOW) {
		return false;
	}
	V2 place = plan.place;
	double reach = (plan.has_radius ? plan.radius : 0.0) + 2.0;
	if (plan.act == A_STALK) {
		reach += _distance_km(place, plan.has_to ? plan.to : place);
	}
	V2 middle = place;
	if (plan.has_from) {
		middle = lerp(plan.from, place, 0.5);
		reach += _distance_km(plan.from, place) * 0.65; // (Half the way, and its bend.)
	}
	double lat_reach = reach / KM_PER_DEGREE;
	double wide = lat_reach / std::max(std::cos(deg2rad(std::clamp(std::abs(middle.y) + lat_reach, 0.0, 89.0))), 0.05);
	out.x0 = middle.x - wide;
	out.x1 = middle.x + wide;
	out.y0 = middle.y - lat_reach;
	out.y1 = middle.y + lat_reach;
	out.until = plan.start + length;
	return true;
}

// --- For popups ---------------------------------------------------------------------

String BirdSim::mode_name(int mode) {
	static const char *names[MODE_COUNT] = { "fly", "circle", "soar", "glide", "hunt", "perch", "rest", "sleep", "swim", "dive", "stand", "stalk", "follow" };
	return mode >= 0 && mode < MODE_COUNT ? String(names[mode]) : String("rest");
}

Dictionary BirdSim::bird_state(int index, double now, double cal) {
	Dictionary out;
	if (index < 0 || index >= (int)_birds.size()) {
		return out;
	}
	State s = state(index, now, cal);
	out["pos"] = gv(s.pos);
	out["heading"] = s.heading;
	out["mode"] = mode_name(s.mode);
	out["height"] = s.height;
	out["wings"] = s.wings;
	out["splash"] = s.splash;
	return out;
}

Dictionary BirdSim::doing_counts(int colony, double now, double cal) {
	Dictionary out;
	if (colony < 0 || colony >= (int)_colonies.size()) {
		return out;
	}
	const Colony &c = _colonies[colony];
	for (int i = 0; i < c.count; i++) {
		String mode = mode_name(state(c.first_bird + i, now, cal).mode);
		out[mode] = (int)out.get(mode, 0) + 1;
	}
	return out;
}

// `cap`: no more than this many of a species are counted (0: all); `max_states`:
// no more than this many birds' states are worked out (0: all), a bound on
// the cost (a big colony that all planned to follow one ship).
Dictionary BirdSim::following(int64_t ship, Vector2 at, double now, double cal, int64_t cap, int64_t max_states) {
	Dictionary out;
	V2 here = v2(at);
	int64_t states = 0;
	for (size_t ci = 0; ci < _colonies.size(); ci++) {
		const Colony &c = _colonies[ci];
		double reach = c.cls == SEABIRDS ? c.range_km + SEABIRD_ROAM_KM + SEABIRD_FOLLOW_KM : GULL_FOLLOW_KM * 2.0;
		if (c.cls != GULLS && c.cls != SEABIRDS) {
			continue; // (Only gulls and seabirds follow ships.)
		}
		if (_distance_km(c.spot, here) > reach && _distance_km(c.away_spot, here) > reach) {
			continue;
		}
		String species_id = _species[c.species].id;
		if (cap > 0 && (int)out.get(species_id, 0) >= cap) {
			continue;
		}
		for (int i = 0; i < c.count; i++) {
			int b = c.first_bird + i;
			// (Its plan first: a cheap check, where working out its state isn't,
			// and a colony has many birds, few of them after this ship.)
			if (_plans[b].ship != ship) {
				continue;
			}
			if (max_states > 0 && states >= max_states) {
				return out;
			}
			states++;
			if (state(b, now, cal).mode != M_FOLLOW) {
				continue;
			}
			out[species_id] = (int)out.get(species_id, 0) + 1;
			if (cap > 0 && (int)out.get(species_id, 0) >= cap) {
				break;
			}
		}
	}
	return out;
}

// --- Drawing --------------------------------------------------------------------------

Vector2 BirdSim::_to_screen(V2 lon_lat) const {
	V2 clamped = { lon_lat.x, std::clamp(lon_lat.y, -MAX_LAT, MAX_LAT) };
	Vector3 p = unit(clamped);
	if (p.dot(_view.toward) < 0.0f) {
		return HIDDEN;
	}
	return _view.middle + Vector2(p.dot(_view.right), -p.dot(_view.up)) * (real_t)_view.radius;
}

bool BirdSim::_hidden(Vector2 at) {
	return at == HIDDEN;
}

Transform2D BirdSim::_basis(V2 spot, Vector2 at) const {
	Vector2 east = _to_screen({ spot.x + 0.01 / std::max(std::cos(deg2rad(spot.y)), 0.1), spot.y });
	Vector2 north = _to_screen({ spot.x, spot.y + 0.01 });
	if (_hidden(east) || _hidden(north)) {
		return Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2());
	}
	return Transform2D(east - at, north - at, Vector2());
}

// A bird's shape (MapView's shapes: 0 a bird from above, 1 a sea duck
// flying, 2 a sea duck swimming, 3 a cormorant swimming, 4 a wader on the
// ground) as a triangle list a bucket's size across, asked of the map once.
const BirdSim::Shape &BirdSim::_shape(int kind, int species, bool hen, int step, int bucket) {
	int64_t key = ((((int64_t)kind * 1024 + species) * 2 + (hen ? 1 : 0)) * 64 + step) * 256 + bucket;
	auto found = _shapes.find(key);
	if (found != _shapes.end()) {
		return found->second;
	}
	Shape &shape = _shapes[key];
	if (_mesh_provider.is_valid()) {
		_stats[5]++;
		Array made = _mesh_provider.call(kind, _species[species].id, hen, step, bucket);
		if (made.size() >= 2) {
			PackedVector2Array points = made[0];
			PackedColorArray colors = made[1];
			int64_t count = std::min(points.size(), colors.size()) / 3 * 3;
			shape.points.assign(points.ptr(), points.ptr() + count);
			shape.colors.assign(colors.ptr(), colors.ptr() + count);
		}
	}
	return shape;
}

// Every bird of a pass goes into one batch of triangles (see draw()): one
// draw call for them all rather than one or two each.
void BirdSim::_tri(Vector2 a, Vector2 b, Vector2 c, Color color) {
	_batch_points.push_back(a);
	_batch_points.push_back(b);
	_batch_points.push_back(c);
	_batch_colors.push_back(color);
	_batch_colors.push_back(color);
	_batch_colors.push_back(color);
}

void BirdSim::_line(Vector2 from, Vector2 to, double width, Color color) {
	Vector2 way = to - from;
	if (way.length_squared() < 1.0e-12f) {
		return;
	}
	Vector2 side = way.normalized().orthogonal() * (real_t)(width * 0.5);
	_tri(from + side, to + side, to - side, color);
	_tri(from + side, to - side, from - side, color);
}

void BirdSim::_oval(Vector2 at, double angle, Vector2 half, Color color, int segments) {
	Vector2 x = Vector2(1, 0).rotated((real_t)angle);
	Vector2 y = Vector2(0, 1).rotated((real_t)angle);
	Vector2 first = at + x * half.x;
	Vector2 last = first;
	for (int i = 1; i <= segments; i++) {
		double a = TAU_D * i / segments;
		Vector2 next = i == segments ? first : at + x * (real_t)(std::cos(a) * half.x) + y * (real_t)(std::sin(a) * half.y);
		_tri(at, last, next, color);
		last = next;
	}
}

void BirdSim::_ring(Vector2 at, double radius, int segments, Color color, double width) {
	double in = std::max(radius - width * 0.5, 0.0);
	double out = radius + width * 0.5;
	Vector2 last_in, last_out;
	for (int i = 0; i <= segments; i++) {
		double a = TAU_D * i / segments;
		Vector2 way((real_t)std::cos(a), (real_t)std::sin(a));
		Vector2 p_in = at + way * (real_t)in;
		Vector2 p_out = at + way * (real_t)out;
		if (i > 0) {
			_tri(last_in, last_out, p_out, color);
			_tri(last_in, p_out, p_in, color);
		}
		last_in = p_in;
		last_out = p_out;
	}
}

// A bird as its shape, placed, turned and scaled into the batch; its shadow
// the same shape in the dark, shadow_height times as far off as a gull's
// usual (none when below 0).
void BirdSim::_draw_shape(int kind, int species, bool hen, int step, Vector2 at, double angle, double span, double shadow_height) {
	int bucket = std::clamp((int)std::lround(std::log(std::max(span, 1.0)) / std::log(SIZE_STEP)), 0, 255);
	const Shape &shape = _shape(kind, species, hen, step, bucket);
	if (shape.points.empty()) {
		return;
	}
	double made = std::pow(SIZE_STEP, bucket);
	real_t scale = (real_t)(span / made);
	real_t c = (real_t)std::cos(angle) * scale;
	real_t s = (real_t)std::sin(angle) * scale;
	size_t count = shape.points.size();
	if (shadow_height >= 0.0) {
		Vector2 off = Vector2((real_t)(span * 0.45), (real_t)(span * 0.55)) * (real_t)shadow_height;
		Vector2 origin = at + off;
		real_t alpha = (real_t)(0.16 / std::sqrt(std::max(shadow_height, 0.5)));
		_batch_points.reserve(_batch_points.size() + count * 2);
		_batch_colors.reserve(_batch_colors.size() + count * 2);
		for (size_t i = 0; i < count; i++) {
			Vector2 v = shape.points[i];
			_batch_points.push_back(Vector2(origin.x + v.x * c - v.y * s, origin.y + v.x * s + v.y * c));
			_batch_colors.push_back(Color(0, 0, 0, shape.colors[i].a * alpha));
		}
	}
	for (size_t i = 0; i < count; i++) {
		Vector2 v = shape.points[i];
		_batch_points.push_back(Vector2(at.x + v.x * c - v.y * s, at.y + v.x * s + v.y * c));
		_batch_colors.push_back(shape.colors[i]);
	}
}

// A wader's long shadow as it falls (MapView.draw_wader()'s shadow).
void BirdSim::_draw_wader_shadow(Vector2 at, double heading, const Species &info, double span, double neck, bool bill_up) {
	bool crane = info.crane;
	Vector2 fwd = Vector2(1, 0).rotated((real_t)heading);
	Vector2 side_way(fwd.y, -fwd.x);
	double body_len = span * 0.3;
	double body_wide = span * 0.12;
	double neck_len = span * (0.02 + 0.2 * neck);
	double upright = span * 0.22 * (1.0 - neck);
	double legs = span * (crane ? 0.32 : 0.26);
	Vector2 cast = Vector2(0.45f, 0.55f).normalized();
	Vector2 hips = at + cast * (real_t)legs;
	Color dark(0, 0, 0, 0.18f);
	for (double side : { -1.0, 1.0 }) {
		_line(at + side_way * (real_t)(side * body_wide * 0.3), hips, std::max(span * 0.012, 1.0), dark);
	}
	_oval(hips, heading, Vector2((real_t)(body_len * 0.5), (real_t)(body_wide * 0.5)), dark);
	Vector2 shadow_head = hips + fwd * (real_t)(body_len * 0.45 + neck_len) + cast * (real_t)upright;
	_line(hips + fwd * (real_t)(body_len * 0.4), shadow_head, std::max(span * 0.022, 1.0), dark);
	_oval(shadow_head, 0.0, Vector2((real_t)(span * 0.025), (real_t)(span * 0.025)), dark, 8);
	if (!bill_up) {
		_line(shadow_head, shadow_head + fwd * (real_t)(span * (crane ? 0.05 : 0.075)), std::max(span * 0.012, 1.0), dark);
	}
}

// A clump of reeds round a bittern, swaying (MapView._draw_reeds()).
void BirdSim::_draw_reeds(Vector2 at, double span, double now, double seed) {
	double wind = 0.0;
	Vector2 lean = Vector2(1, 0).rotated((real_t)wind) * (real_t)(span * 0.06 * (1.0 + std::sin(now * 0.9 + wind)));
	for (int i = 0; i < 11; i++) {
		double a = TAU_D * (i / 11.0 + seed);
		double r = span * (0.12 + 0.22 * std::fmod(seed * 7.0 + i * 0.37, 1.0));
		Vector2 base = at + Vector2(1, 0).rotated((real_t)a) * (real_t)r;
		Color color = i % 3 == 0 ? Color(0.62f, 0.56f, 0.32f) : Color(0.42f, 0.5f, 0.26f);
		Vector2 tip = base + lean + Vector2(1, 0).rotated((real_t)(a + 0.6)) * (real_t)(span * 0.1);
		_line(base, tip, std::max(span * 0.025, 1.0), color);
		if (i % 4 == 0) {
			real_t head = (real_t)std::max(span * 0.022, 0.8);
			_oval(tip, 0.0, Vector2(head, head), Color(0.45f, 0.3f, 0.18f), 8);
		}
	}
}

// One bird on screen as it is now (MapView._draw_one_bird()), into the batch.
void BirdSim::_draw_one(int index, const State &state, Vector2 at, double span, double now, const Transform2D &basis) {
	const Bird &bird = _birds[index];
	const Colony &colony = _colonies[bird.colony];
	const Species &info = _species[colony.species];
	if (span < _full_px) {
		real_t dot = (real_t)std::max(span * 0.22, 0.7);
		_oval(at, 0.0, Vector2(dot, dot), info.dot, 8);
		return;
	}
	Vector2 way = basis.columns[0] * (real_t)std::cos(state.heading) + basis.columns[1] * (real_t)std::sin(state.heading);
	double angle = way.angle();
	int mode = state.mode;
	double wings = state.wings;
	double height = state.height;
	bool flying = is_flying(mode);
	int step = std::clamp((int)std::lround(std::clamp(wings, 0.0, 1.5) / WING_STEP), 0, 63);
	if (mode == M_DIVE) {
		// Under the water: a dark shape and a ripple over it.
		_oval(at, angle, Vector2((real_t)(span * 0.3), (real_t)(span * 0.1)), Color(0.08f, 0.12f, 0.18f, 0.35f));
		double ripple = std::fmod(now * 0.7 + (double)(bird.seed % 10), 1.0);
		_ring(at, span * (0.15 + 0.25 * ripple), 14, Color(1, 1, 1, (real_t)(0.5 * (1.0 - ripple))), std::max(span * 0.03, 1.0));
		return;
	}
	switch (colony.cls) {
		case SEA_DUCKS:
			if (flying) {
				_draw_shape(1, colony.species, bird.hen, step, at, angle, span, height);
			} else {
				_draw_shape(2, colony.species, bird.hen, 0, at, angle, span, -1.0);
			}
			break;
		case WADERS:
			if (flying) {
				_draw_shape(0, colony.species, false, step, at, angle, span, height);
			} else {
				bool hiding = info.hide && mode == M_STAND;
				if (hiding) {
					_draw_reeds(at, span, now, (double)(bird.seed % 100));
				}
				double neck = mode == M_STAND ? 0.55 : (mode == M_STALK ? 0.85 : (mode == M_SLEEP ? 0.1 : (mode == M_REST || mode == M_PERCH ? 0.3 : 0.5)));
				_draw_wader_shadow(at, angle, info, span, neck, hiding);
				_draw_shape(4, colony.species, hiding, (int)std::lround(neck * 20.0), at, angle, span, -1.0);
			}
			break;
		case CORMORANTS:
			if (mode == M_SWIM) {
				_draw_shape(3, colony.species, false, 0, at, angle, span * 1.2, -1.0);
			} else {
				_draw_shape(0, colony.species, false, step, at, angle, span, flying ? height : 0.03);
			}
			break;
		default:
			if (mode == M_SWIM) {
				_draw_shape(0, colony.species, false, (int)std::lround(0.2 / WING_STEP), at, angle, span, -1.0);
			} else {
				_draw_shape(0, colony.species, false, step, at, angle, span, flying ? height : 0.03);
			}
			break;
	}
	if (state.splash > 0.0) {
		double s = state.splash;
		_ring(at, span * (0.2 + 0.4 * (1.0 - s)), 16, Color(1, 1, 1, (real_t)(0.8 * s)), std::max(span * 0.05, 1.0));
	}
}

// One pass over the birds in view (MapView._draw_bird_pass()): those keeping
// still for still_s or more (`still`: marked so the other pass skips them), or
// all the others. params: box (lon/lat Rect2, the screen's), view (screen
// Rect2, grown), right, up, toward (Vector3), radius, middle (Vector2), now,
// cal, scale (bird px per span unit), dot_px, full_px, reach_gulls_km,
// reach_other_km, view_lat, still_s, still_margin_s. Returns false if it drew nothing.
bool BirdSim::draw(const RID &canvas, bool still, const Dictionary &params) {
	std::vector<Hit> &hits = still ? _still_hits : _hits;
	hits.clear();
	_batch_points.clear();
	_batch_colors.clear();
	if (still) {
		std::fill(_still_drawn.begin(), _still_drawn.end(), 0);
		_still_redraw_at = INFINITY;
		_still_epoch = _where_changes;
	}
	if (_birds.empty()) {
		return false;
	}
	Rect2 box = params.get("box", Rect2());
	Rect2 view = params.get("view", Rect2());
	_view.right = params.get("right", Vector3());
	_view.up = params.get("up", Vector3());
	_view.toward = params.get("toward", Vector3());
	_view.radius = params.get("radius", 1.0);
	_view.middle = params.get("middle", Vector2());
	double now = params.get("now", 0.0);
	double cal = params.get("cal", 0.0);
	double scale = params.get("scale", 1.0);
	double dot_px = params.get("dot_px", 1.6);
	_full_px = params.get("full_px", 4.0);
	double reach_gulls = (double)params.get("reach_gulls_km", 80.0) / KM_PER_DEGREE;
	double reach_other = (double)params.get("reach_other_km", 60.0) / KM_PER_DEGREE;
	double view_lat = params.get("view_lat", 0.0);
	double still_s = params.get("still_s", 4.0);
	double still_margin = params.get("still_margin_s", 0.5);
	double bx0 = box.position.x, by0 = box.position.y, bx1 = box.position.x + box.size.x, by1 = box.position.y + box.size.y;
	double wide_by = 1.0 / std::max(std::cos(deg2rad(std::clamp(view_lat, -80.0, 80.0))), 0.1);
	bool wraps = bx0 < -180.0 || bx1 > 180.0;
	auto in_box = [&](V2 p, double reach_x, double reach_y) {
		for (double shift : { 0.0, 360.0, -360.0 }) {
			if (shift != 0.0 && !wraps) {
				break;
			}
			double x = p.x + shift;
			if (x >= bx0 - reach_x && x <= bx1 + reach_x && p.y >= by0 - reach_y && p.y <= by1 + reach_y) {
				return true;
			}
		}
		return false;
	};
	auto meets = [&](const Bound &b) {
		for (double shift : { 0.0, 360.0, -360.0 }) {
			if (shift != 0.0 && !wraps) {
				break;
			}
			if (b.x1 + shift >= bx0 && b.x0 + shift <= bx1 && b.y1 >= by0 && b.y0 <= by1) {
				return true;
			}
		}
		return false;
	};
	uint64_t t_loop = Time::get_singleton()->get_ticks_usec();
	bool drew = false;
	// Birds in the air are drawn after (over) those on the water and the
	// ground, whatever their colonies: kept here till the rest are down.
	struct Flyer {
		int b;
		State s;
		Vector2 at;
		double span;
		Transform2D basis;
		int colony;
	};
	std::vector<Flyer> flyers;
	for (size_t ci = 0; ci < _colonies.size(); ci++) {
		Colony &colony = _colonies[ci];
		const Species &info = _species[colony.species];
		double span = info.span * scale;
		if (span < dot_px) {
			continue;
		}
		_stats[8]++;
		_where(colony, cal);
		bool flying_off = colony.where == W_TO_HOME || colony.where == W_TO_AWAY;
		// The colonies whose birds could be in view: those of the ports near it
		// (no further from their port than reach_*_km), the seabirds whose range
		// reaches it, and those on the wing.
		if (flying_off) {
			if (still) {
				continue;
			}
		} else if (colony.cls == SEABIRDS) {
			double reach = colony.range_km / KM_PER_DEGREE;
			double wide = reach / std::max(std::cos(deg2rad(colony.spot.y)), 0.1);
			if (!in_box(colony.spot, wide, reach) && !in_box(colony.away_spot, wide, reach)) {
				continue;
			}
		} else {
			double reach = colony.cls == GULLS ? reach_gulls : reach_other;
			if (!in_box(colony.where == W_AWAY ? colony.away_spot : colony.spot, reach * wide_by, reach)) {
				continue;
			}
		}
		// Which way east and north are on screen about its birds, for their
		// headings: worked out at the first one drawn (they're never far
		// apart; a seabird's each).
		Transform2D basis = Transform2D(Vector2(), Vector2(), Vector2());
		bool basis_set = false;
		bool each_own = colony.cls == SEABIRDS;
		for (int i = 0; i < colony.count; i++) {
			int b = colony.first_bird + i;
			if (!still && _still_drawn[b]) {
				continue; // (On the still birds' layer.)
			}
			_stats[9]++;
			// Skipped while all it can do till its spell ends is out of view.
			Bound &bound = _bounds[b];
			if (now >= bound.until || bound.epoch != colony.changes) {
				_stats[3]++;
				if (!_bound(b, now, cal, bound)) {
					bound.x0 = -1.0e9;
					bound.x1 = 1.0e9;
					bound.y0 = -1.0e9;
					bound.y1 = 1.0e9;
					bound.until = now + 1.0;
				}
				bound.epoch = colony.changes;
			}
			if (!meets(bound)) {
				continue;
			}
			_stats[4]++;
			State s = state(b, now, cal);
			if (still) {
				const Fixed &fixed = _fixed[b];
				double until = fixed.epoch == colony.changes ? fixed.until : -INFINITY;
				if (until < now + still_s) {
					continue;
				}
				_still_drawn[b] = 1;
				_still_redraw_at = std::min(_still_redraw_at, until - still_margin);
			}
			Vector2 at = _to_screen(s.pos);
			if (_hidden(at) || !view.has_point(at)) {
				continue;
			}
			if (span >= _full_px && (each_own || !basis_set)) {
				basis = _basis(s.pos, at);
				basis_set = true;
			}
			if (!still && is_flying(s.mode)) {
				flyers.push_back({ b, s, at, span, basis, (int)ci });
				continue;
			}
			_draw_one(b, s, at, span, now, basis);
			hits.push_back({ at, (float)std::max(span * 0.6, 6.0), (int)ci });
			drew = true;
		}
	}
	for (const Flyer &f : flyers) {
		_draw_one(f.b, f.s, f.at, f.span, now, f.basis);
		hits.push_back({ f.at, (float)std::max(f.span * 0.6, 6.0), f.colony });
		drew = true;
	}
	_stats[6] += Time::get_singleton()->get_ticks_usec() - t_loop;
	uint64_t t_flush = Time::get_singleton()->get_ticks_usec();
	_stats[10] += (int64_t)_batch_points.size();
	// All of them in one go: the birds on the move as a mesh kept from frame to
	// frame (its vertices sent again each frame), the still ones (drawn again
	// only now and then) as a polygon.
	if (!_batch_points.empty() && (still || !_moving.draw(canvas, _batch_points, _batch_colors))) {
		PackedVector2Array points;
		PackedColorArray colors;
		points.resize(_batch_points.size());
		colors.resize(_batch_colors.size());
		std::copy(_batch_points.begin(), _batch_points.end(), points.ptrw());
		std::copy(_batch_colors.begin(), _batch_colors.end(), colors.ptrw());
		RenderingServer::get_singleton()->canvas_item_add_triangle_array(canvas, PackedInt32Array(), points, colors);
	}
	_stats[7] += Time::get_singleton()->get_ticks_usec() - t_flush;
	return drew;
}

// The colony of the bird drawn under a screen point (moving ones over still
// ones), or -1; `reach` times its usual reach.
int BirdSim::hit_at(Vector2 screen, double reach) const {
	for (const std::vector<Hit> *list : { &_hits, &_still_hits }) {
		for (auto it = list->rbegin(); it != list->rend(); ++it) {
			if (it->at.distance_to(screen) <= it->reach * reach) {
				return it->colony;
			}
		}
	}
	return -1;
}

void BirdSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "colonies", "species", "migrate_days"), &BirdSim::setup);
	ClassDB::bind_method(D_METHOD("set_providers", "spots", "ships", "meshes"), &BirdSim::set_providers);
	ClassDB::bind_method(D_METHOD("bird_count"), &BirdSim::bird_count);
	ClassDB::bind_method(D_METHOD("birds_of", "colony"), &BirdSim::birds_of);
	ClassDB::bind_method(D_METHOD("bird_state", "index", "now", "cal"), &BirdSim::bird_state);
	ClassDB::bind_method(D_METHOD("doing_counts", "colony", "now", "cal"), &BirdSim::doing_counts);
	ClassDB::bind_method(D_METHOD("following", "ship", "at", "now", "cal", "cap", "max_states"), &BirdSim::following, DEFVAL(0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("where_changes"), &BirdSim::where_changes);
	ClassDB::bind_method(D_METHOD("forget_spots"), &BirdSim::forget_spots);
	ClassDB::bind_method(D_METHOD("draw", "canvas", "still", "params"), &BirdSim::draw);
	ClassDB::bind_method(D_METHOD("hit_at", "screen", "reach"), &BirdSim::hit_at);
	ClassDB::bind_method(D_METHOD("still_redraw_at"), &BirdSim::still_redraw_at);
	ClassDB::bind_method(D_METHOD("still_epoch"), &BirdSim::still_epoch);
	ClassDB::bind_method(D_METHOD("stats"), &BirdSim::stats);
}

// What the passes since the last asking did (for profiling): spots asked,
// ships asked, plans made, bounds worked out, states worked out, shapes asked,
// the time (us) in the passes and in sending the batch, colonies and birds
// looked at, and vertices drawn.
Dictionary BirdSim::stats() {
	Dictionary out;
	const char *names[11] = { "spots", "ships", "plans", "bounds", "states", "meshes", "loop_us", "flush_us", "colonies", "birds_looked", "verts" };
	for (int i = 0; i < 11; i++) {
		out[names[i]] = _stats[i];
		_stats[i] = 0;
	}
	return out;
}
