// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// See land_sim.h. Follows Wildlife.land_state() and MapView._draw_wildlife().
#include "land_sim.h"

#include <godot_cpp/classes/font.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
constexpr double KM_PER_DEGREE = 111.32;
constexpr double TAU_D = 6.2831853071795864769252867666;
constexpr double MOVE_SHARE = 0.55;
constexpr double YOUNG_SIZE = 0.55;
constexpr double MAX_LAT = 85.0;
const Vector2 HIDDEN(-1.0e5, -1.0e5);

double smoothstep(double from, double to, double x) {
	return UtilityFunctions::smoothstep(from, to, x);
}

int month_bits(const Array &months) {
	int bits = 0;
	for (int64_t i = 0; i < months.size(); i++) {
		bits |= 1 << (int)(double)months[i];
	}
	return bits;
}
} // namespace

double LandSim::_mix(int64_t n) {
	int64_t h = n & 0xffffffffLL;
	h = ((h ^ (h >> 16)) * 0x45d9f3bLL) & 0xffffffffLL;
	h = ((h ^ (h >> 16)) * 0x45d9f3bLL) & 0xffffffffLL;
	h ^= h >> 16;
	return (double)(h & 0x7fffffffLL) / (double)0x7fffffffLL;
}

// Wildlife._disc_n() (as a Vector2: its parts are float32).
LandSim::V2 LandSim::_disc_n(int64_t n) {
	Vector2 v = Vector2::from_angle((real_t)(_mix(n) * TAU_D)) * (real_t)UtilityFunctions::sqrt(_mix(n ^ 0x5bd1e995LL));
	return { (double)v.x, (double)v.y };
}

// Wildlife._offset() (a Vector2 again).
LandSim::V2 LandSim::_offset(V2 spot, V2 km) {
	Vector2 out((real_t)spot.x, (real_t)spot.y);
	out += Vector2((real_t)(km.x / (KM_PER_DEGREE * MAX(UtilityFunctions::cos(Math::deg_to_rad(spot.y)), 0.1))), (real_t)(km.y / KM_PER_DEGREE));
	return { (double)out.x, (double)out.y };
}

int LandSim::_month_of(double cal) {
	int64_t hour = (int64_t)std::floor(cal / 3600.0);
	if (hour != _month_hour) {
		_month_hour = hour;
		_month = (int)Time::get_singleton()->get_datetime_dict_from_unix_time((int64_t)cal)["month"];
	}
	return _month;
}

// Wildlife._season() for a set of away months.
std::pair<int, double> LandSim::_season(int away_months, double cal) {
	Time *time = Time::get_singleton();
	Dictionary date = time->get_datetime_dict_from_unix_time((int64_t)cal);
	int month = date["month"];
	auto is_away = [away_months](int m) { return (away_months & (1 << m)) != 0; };
	bool away = is_away(month);
	int start_month = month;
	for (int step = 0; step < 11; step++) {
		int before = (start_month + 10) % 12 + 1;
		if (is_away(before) != away) {
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
		return { away ? 2 : 3, CLAMP(days / _migrate_days, 0.0, 1.0) };
	}
	return { away ? 1 : 0, 0.0 };
}

// Wildlife._migration_base().
LandSim::V2 LandSim::_base(Group &group, const Species &info, double cal) {
	if (!info.migrates) {
		return group.home;
	}
	int64_t hour = (int64_t)std::floor(cal / 3600.0);
	if (group.season_hour != hour) {
		group.season_hour = hour;
		std::pair<int, double> season = _season(info.away_months, cal);
		group.where = season.first;
		group.progress = season.second;
	}
	Vector2 home((real_t)group.home.x, (real_t)group.home.y);
	Vector2 away((real_t)group.away.x, (real_t)group.away.y);
	switch (group.where) {
		case 1:
			return group.away;
		case 2: {
			Vector2 v = home.lerp(away, (real_t)group.progress);
			return { (double)v.x, (double)v.y };
		}
		case 3: {
			Vector2 v = away.lerp(home, (real_t)group.progress);
			return { (double)v.x, (double)v.y };
		}
	}
	return group.home;
}

void LandSim::setup(const Array &groups, const Dictionary &land, double migrate_days, const Callable &textures, const Callable &regions) {
	_migrate_days = migrate_days;
	_texture_provider = textures;
	_region_provider = regions;
	_species.clear();
	_groups.clear();
	_textures.clear();
	std::unordered_map<std::string, int> index;
	Array ids = land.keys();
	for (int64_t i = 0; i < ids.size(); i++) {
		String id = ids[i];
		Dictionary info = land[id];
		Species s;
		s.id = id;
		s.km = info.get("km", 6.0);
		s.hibernate = month_bits(info.get("hibernate", Array()));
		s.den_young = info.get("den_young", false);
		String active = info.get("active", "day");
		s.active = active == "night" ? 1 : (active == "dusk" ? 2 : 0);
		s.roam_km = info.get("roam_km", 30.0);
		s.kmh = MAX((double)info.get("kmh", 3.0), 0.3);
		s.migrates = info.has("migrate");
		if (s.migrates) {
			s.away_months = month_bits(((Dictionary)info["migrate"]).get("months", Array()));
		}
		index[id.utf8().get_data()] = (int)_species.size();
		_species.push_back(s);
	}
	for (int64_t i = 0; i < groups.size(); i++) {
		Dictionary g = groups[i];
		Group group;
		String species = g["species"];
		auto found = index.find(species.utf8().get_data());
		group.species = found != index.end() ? found->second : 0;
		group.seed = (int64_t)g["seed"];
		Vector2 home = g["home"];
		Vector2 away = g["away"];
		group.home = { (double)home.x, (double)home.y };
		group.away = { (double)away.x, (double)away.y };
		group.members = g["members"];
		group.young = g["young"];
		group.home_kind = g["home_kind"];
		group.has_home = group.home_kind != "none";
		_groups.push_back(group);
	}
}

// Wildlife.land_state().
LandSim::State LandSim::state(int gi, int member, double cal, double life_time) {
	Group &group = _groups[gi];
	const Species &info = _species[group.species];
	State s;
	int64_t seed = group.seed;
	s.young = member > 0 && member >= group.members - group.young;
	s.size = info.km * (s.young ? YOUNG_SIZE : 1.0);
	int month = _month_of(cal);
	bool hibernating = (info.hibernate & (1 << month)) != 0;
	if (hibernating && (!info.den_young || group.young > 0)) {
		s.pos = group.home;
		s.mode = DEN;
		return s;
	}
	V2 base = _base(group, info, cal);
	double hour = UtilityFunctions::fposmod(UtilityFunctions::fposmod(cal, 86400.0) / 3600.0 + base.x / 15.0, 24.0);
	// Wildlife._activity().
	double day = smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(18.5, 20.5, hour));
	double up = day;
	if (info.active == 1) {
		up = 1.0 - day;
	} else if (info.active == 2) {
		up = MAX(UtilityFunctions::exp(-UtilityFunctions::pow((hour - 6.5) / 2.0, 2.0)), UtilityFunctions::exp(-UtilityFunctions::pow((hour - 19.0) / 2.0, 2.0)));
	}
	double roam = info.roam_km;
	double kmh = info.kmh;
	double leg_s = roam / kmh * 3600.0 * 1.4 / MOVE_SHARE;
	double t = life_time / leg_s + _mix(seed) * 7.0;
	int64_t leg = (int64_t)std::floor(t);
	double u = t - (double)leg;
	V2 d1 = _disc_n(seed + leg * 7919);
	V2 d2 = _disc_n(seed + (leg + 1) * 7919);
	Vector2 k1 = Vector2((real_t)d1.x, (real_t)d1.y) * (real_t)roam;  // (A Vector2 times a float, as the GDScript has it.)
	Vector2 k2 = Vector2((real_t)d2.x, (real_t)d2.y) * (real_t)roam;
	V2 from = _offset(base, { (double)k1.x, (double)k1.y });
	V2 to = _offset(base, { (double)k2.x, (double)k2.y });
	double going = smoothstep(0.0, MOVE_SHARE, u);
	Vector2 middle_v = Vector2((real_t)from.x, (real_t)from.y).lerp(Vector2((real_t)to.x, (real_t)to.y), (real_t)going);
	V2 middle = { (double)middle_v.x, (double)middle_v.y };
	bool moving = u < MOVE_SHARE;
	// Each member round the middle (the young close by their mother).
	double spread = info.km * (1.2 + 0.4 * group.members);
	int64_t mseed = seed * 31 + member * 1009;
	V2 disc = _disc_n(mseed);
	Vector2 mine_v = Vector2((real_t)disc.x, (real_t)disc.y) * (real_t)spread * (real_t)(s.young ? 0.35 : 1.0);
	V2 mine = { (double)mine_v.x, (double)mine_v.y };
	V2 active = _offset(middle, mine);
	V2 rest_at = group.has_home ? group.home : from;
	Vector2 mine_rest = mine_v * 0.35f;
	V2 resting = _offset(rest_at, { (double)mine_rest.x, (double)mine_rest.y });
	Vector2 pos_v = Vector2((real_t)resting.x, (real_t)resting.y).lerp(Vector2((real_t)active.x, (real_t)active.y), (real_t)up);
	s.pos = { (double)pos_v.x, (double)pos_v.y };
	s.heading = _mix(mseed + 7) * TAU_D;
	s.mode = SLEEP;
	if (up > 0.5) {
		if (moving) {
			s.heading = UtilityFunctions::atan2(to.y - from.y, (to.x - from.x) * UtilityFunctions::cos(Math::deg_to_rad(base.y)));
			s.mode = WALK;
		} else {
			s.mode = _mix(mseed + leg * 13) < 0.6 ? GRAZE : REST;
		}
	} else if (up > 0.05) {
		s.mode = WALK;
		Vector2 way = hour < 12.0 ? Vector2((real_t)active.x, (real_t)active.y) - Vector2((real_t)resting.x, (real_t)resting.y) : Vector2((real_t)resting.x, (real_t)resting.y) - Vector2((real_t)active.x, (real_t)active.y);
		if (way.length() > 0.0001f) {
			s.heading = UtilityFunctions::atan2(way.y, (double)way.x * UtilityFunctions::cos(Math::deg_to_rad(base.y)));
		}
	}
	return s;
}

RID LandSim::_texture(const String &name) {
	std::string key = name.utf8().get_data();
	auto found = _textures.find(key);
	if (found != _textures.end()) {
		return found->second;
	}
	RID rid;
	if (_texture_provider.is_valid()) {
		rid = _texture_provider.call(name);
	}
	_textures[key] = rid;
	return rid;
}

// MapView._draw_wildlife()'s land animals and their homes, drawn on `canvas`.
// params: box (lon/lat Rect2), reach (screen Rect2), right, up, toward,
// radius, middle (the view), km (px a km), home_side, home_min_px, min_px,
// stride_s, cal, life_time, unlocked (region id -> true; null: no locks),
// font. Returns what's where for clicks: [[screen point, reach, "group" or
// "home", group index]].
Array LandSim::draw(const RID &canvas, const Dictionary &params) {
	Array hits;
	Rect2 box = params["box"];
	Rect2 reach = params["reach"];
	Vector3 right = params["right"];
	Vector3 up_axis = params["up"];
	Vector3 toward = params["toward"];
	double radius = params["radius"];
	Vector2 middle = params["middle"];
	double km = params["km"];
	double home_side = params["home_side"];
	double home_min = params["home_min_px"];
	double min_px = params["min_px"];
	double stride_s = params["stride_s"];
	double cal = params["cal"];
	double life_time = params["life_time"];
	Variant unlocked_v = params.get("unlocked", Variant());
	bool check_locks = unlocked_v.get_type() == Variant::DICTIONARY;
	Dictionary unlocked = check_locks ? (Dictionary)unlocked_v : Dictionary();
	Ref<Font> font = params.get("font", Variant());
	auto to_screen = [&](V2 lon_lat) -> Vector2 {
		// MapView.world_to_screen(Geo.project()).
		double lon = Math::deg_to_rad(lon_lat.x);
		double lat = Math::deg_to_rad(CLAMP(lon_lat.y, -MAX_LAT, MAX_LAT));
		Vector3 p((real_t)(std::cos(lat) * std::cos(lon)), (real_t)(std::cos(lat) * std::sin(lon)), (real_t)std::sin(lat));
		if (p.dot(toward) < 0.0f) {
			return HIDDEN;
		}
		return middle + Vector2(p.dot(right), -p.dot(up_axis)) * (real_t)radius;
	};
	double box_x0 = box.position.x, box_x1 = box.position.x + box.size.x, box_y0 = box.position.y, box_y1 = box.position.y + box.size.y;
	std::vector<Item> items;
	for (size_t gi = 0; gi < _groups.size(); gi++) {
		Group &group = _groups[gi];
		const Species &info = _species[group.species];
		// Wildlife.groups_in(): its range reaching into the box (round its home or its away spot).
		double reach_deg = (info.roam_km + info.km * (1.2 + 0.4 * group.members)) / KM_PER_DEGREE + 1.0;
		bool near = false;
		for (const V2 &spot : { group.home, group.away }) {
			double wide = reach_deg / MAX(std::cos(Math::deg_to_rad(spot.y)), 0.1);
			for (double shift : { 0.0, 360.0, -360.0 }) {
				double x = spot.x + shift;
				if (x >= box_x0 - wide && x <= box_x1 + wide && spot.y >= box_y0 - reach_deg && spot.y <= box_y1 + reach_deg) {
					near = true;
				}
			}
		}
		if (!near) {
			continue;
		}
		if (check_locks) {
			if (!group.region_known && _region_provider.is_valid()) {
				Variant region = _region_provider.call(Vector2((real_t)group.home.x, (real_t)group.home.y));
				if (region.get_type() == Variant::STRING) {
					group.region = region;
					group.region_known = true;
				}
			}
			if (!group.region_known || !unlocked.has(group.region)) {
				continue;
			}
		}
		bool in_den = false;
		if (group.has_home && home_side >= home_min) {
			Vector2 home_at = to_screen(group.home);
			if (home_at != HIDDEN && reach.has_point(home_at)) {
				double side = home_side * 1.3;
				RID texture = _texture(String("home_") + group.home_kind);
				if (texture.is_valid()) {
					items.push_back({ (double)home_at.y - side, texture, home_at, 0.0, side, Color(1, 1, 1) });
				}
				Array hit;
				hit.push_back(home_at);
				hit.push_back(MAX(side * 0.5, 6.0));
				hit.push_back("home");
				hit.push_back((int64_t)gi);
				hits.push_back(hit);
			}
		}
		for (int m = 0; m < group.members; m++) {
			State s = state((int)gi, m, cal, life_time);
			if (s.mode == DEN) {
				in_den = true;
				continue;
			}
			Vector2 at = to_screen(s.pos);
			if (at == HIDDEN || !reach.has_point(at)) {
				continue;
			}
			double side = s.size * km;
			if (side < min_px) {
				continue;
			}
			// Its heading on screen: a step that way on the map.
			Vector2 ahead = to_screen({ s.pos.x + std::cos(s.heading) * 0.01 / MAX(std::cos(Math::deg_to_rad(s.pos.y)), 0.1), s.pos.y + std::sin(s.heading) * 0.01 });
			double angle = ahead != HIDDEN ? (double)(ahead - at).angle() : 0.0;
			bool stepping = s.mode == WALK && std::fmod(life_time / stride_s + m * 0.37, 1.0) < 0.5;
			RID texture = _texture(stepping ? info.id + String("_step") : info.id);
			if (!texture.is_valid()) {
				continue;
			}
			Color tint = s.mode == SLEEP ? Color(0.78f, 0.8f, 0.88f) : Color(1, 1, 1);
			items.push_back({ (double)at.y, texture, at, angle, side, tint });
			Array hit;
			hit.push_back(at);
			hit.push_back(MAX(side * 0.6, 6.0));
			hit.push_back("group");
			hit.push_back((int64_t)gi);
			hits.push_back(hit);
		}
		if (in_den && home_side >= home_min) {
			Vector2 home_at = to_screen(group.home);
			if (home_at != HIDDEN) {
				Item z = { (double)home_at.y + 1.0, RID(), home_at, 0.0, home_side, Color(1, 1, 1) };
				z.z = true;
				items.push_back(z);
			}
		}
	}
	std::stable_sort(items.begin(), items.end(), [](const Item &a, const Item &b) { return a.y < b.y; });
	RenderingServer *rs = RenderingServer::get_singleton();
	for (const Item &item : items) {
		if (item.z) {
			// A den with its family asleep inside: z's rising.
			if (font.is_valid()) {
				rs->canvas_item_add_set_transform(canvas, Transform2D());
				double z = MAX(item.side * 0.3, 8.0);
				font->draw_string(canvas, item.at + Vector2((real_t)(item.side * 0.2), (real_t)(-item.side * 0.3)), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, (int)z, Color(1, 1, 1, 0.85f));
				font->draw_string(canvas, item.at + Vector2((real_t)(item.side * 0.35), (real_t)(-item.side * 0.55)), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, (int)(z * 0.75), Color(1, 1, 1, 0.7f));
			}
			continue;
		}
		rs->canvas_item_add_set_transform(canvas, Transform2D((real_t)item.angle, Size2((real_t)(item.side / 64.0), (real_t)(item.side / 64.0)), 0.0f, item.at));
		rs->canvas_item_add_texture_rect(canvas, Rect2(-32.0f, -32.0f, 64.0f, 64.0f), item.texture, false, item.tint);
	}
	rs->canvas_item_add_set_transform(canvas, Transform2D());
	return hits;
}

void LandSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "groups", "land", "migrate_days", "textures", "regions"), &LandSim::setup);
	ClassDB::bind_method(D_METHOD("draw", "canvas", "params"), &LandSim::draw);
}
