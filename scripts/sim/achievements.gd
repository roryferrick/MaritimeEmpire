# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Achievements
extends RefCounted
## The achievements (the trophy button at the map's top right): lines of up to
## three stars, and single badges. A line for each commodity (units delivered,
## STAR_UNITS by its unit), one for the fleet (ships owned, tugs not counted),
## one for the company level, one for money in the bank, and one for the field
## guide (the animals seen: a flock, pod or group clicked on the map, see
## discover()), one for the wonders of the world seen (clicked on the map, see
## discover()), one for the hidden gems found (GameState.HIDDEN_GEMS). Badges
## for firsts and other milestones (BADGES).
##
## A company's Company.achievements: id -> stars earned (1 for a badge). Once
## earned, kept (selling ships or spending money doesn't take them back).
## Each player's game works out its own (check(), every CHECK_S), and they're
## one of a company's own settings (Company.PREF_KEYS), so a joined player's
## are sent to the host and kept in its save, as are the animals they've seen
## and wonders (Company.discovered: "bird:<id>", "sea:<id>", "land:<id>",
## "wonder:<id>").

const CHECK_S := 1.0
## Units delivered for each star, by commodity unit (markets.json): a few
## loads of a small ship, a good many of a middling one, and hundreds of
## loads of the biggest: a long game's work.
const STAR_UNITS := {
	"container": [2000, 250000, 5000000],
	"ton": [50000, 10000000, 100000000],
	"head": [5000, 1000000, 10000000],
	"vehicle": [2000, 250000, 5000000],
	"crate": [1000, 100000, 2000000],
}
const FLEET_STARS := [10, 50, 200]
const LEVEL_STARS := [10, 30, 60]
const MONEY_STARS := [10000000, 500000000, 5000000000]
## Shares of all the animals in the field guide seen, for each star: a
## third, two thirds and all of them (counted, not shown as percentages).
const ANIMAL_STARS := [1.0 / 3.0, 2.0 / 3.0, 1.0]
## Wonders of the world seen for each star: 10, 25 and all of them (0: all).
const WONDER_STARS := [10, 25, 0]
## Hidden gems found for each star (GameState.HIDDEN_GEMS: three of them).
const GEM_STARS := [1, 2, 3]
## The ship lines owning one of each counts for the Full house badge.
const CARGO_LINES: Array[String] = ["container", "ore", "grain", "livestock", "tanker", "vehicles", "seafood"]
## Badges: [id, name, what it takes].
const BADGES := [
	["first_delivery", "Maiden voyage", "Deliver a cargo"],
	["first_hub", "Branching out", "Build a hub"],
	["five_hubs", "Network", "Have 5 hubs"],
	["second_region", "New horizons", "Unlock a second market region"],
	["all_regions", "Seven seas", "Unlock every market region"],
	["every_cargo", "Jack of all trades", "Deliver every commodity"],
	["full_house", "Full house", "Own a ship of every cargo line"],
	["panama", "Between the oceans", "Cross the Panama Canal"],
	["suez", "Short cut", "Cross the Suez Canal"],
	["all_canals", "Lock keeper", "Cross every canal"],
	["loan", "Borrowed time", "Take out a loan"],
	["debt_free", "Debt free", "Pay a loan back in full"],
	["mega", "Mega", "Give a ship model its mega upgrade"],
]



## Every line: [{id, name, unit (what's counted), stars: [3 amounts]}].
static func lines() -> Array:
	var out := []
	for commodity: Dictionary in GameData.commodities:
		var stars: Array = STAR_UNITS.get(str(commodity.get("unit", "")), [])
		if not stars.is_empty():
			out.append({id = "deliver_" + str(commodity.id), name = str(commodity.name), unit = str(commodity.get("units", "units")) + " delivered", stars = stars})
	out.append({id = "fleet", name = "Fleet", unit = "ships owned (not tugs)", stars = FLEET_STARS})
	out.append({id = "level", name = "Company level", unit = "levels reached", stars = LEVEL_STARS})
	out.append({id = "money", name = "Money in the bank", unit = "in the bank", stars = MONEY_STARS})
	out.append({id = "animals", name = "Field guide", unit = "animals seen", stars = ANIMAL_STARS.map(func(share: float) -> int: return roundi(share * animal_count()))})
	out.append({id = "wonders", name = "Wonders of the world", unit = "wonders seen", stars = WONDER_STARS.map(func(need: int) -> int: return need if need > 0 else GameData.wonders.size())})
	out.append({id = "hidden_gems", name = "Hidden gems", unit = "hidden gems found", stars = GEM_STARS})
	return out


## How far a company has got along a line (in its unit).
static func progress(company: Company, line_id: String) -> int:
	if line_id.begins_with("deliver_"):
		return int(company.delivered.get(line_id.trim_prefix("deliver_"), 0))
	match line_id:
		"fleet":
			var count := 0
			for ship in GameState.fleet(company):
				if str(ship.model().get("category", "")) != "tug":
					count += 1
			return count
		"level":
			return company.level()
		"money":
			return company.money
		"wonders":
			return wonders_seen(company)
		"animals":
			return seen_count(company)
		"hidden_gems":
			return company.hidden_gems.size()
	return 0


## True if a company has done what a badge takes.
static func badge_done(company: Company, badge_id: String) -> bool:
	match badge_id:
		"first_delivery":
			return not company.delivered.is_empty() or company.earlier_containers > 0
		"first_hub":
			return company.hubs.size() >= 2
		"five_hubs":
			return company.hubs.size() >= 6
		"second_region":
			return company.regions.size() >= 2
		"all_regions":
			return company.regions.size() >= (GameData.markets.get("regions", []) as Array).size()
		"every_cargo":
			for commodity: Dictionary in GameData.commodities:
				if int(company.delivered.get(commodity.id, 0)) <= 0:
					return false
			return true
		"full_house":
			var lines_owned := {}
			for ship in GameState.fleet(company):
				lines_owned[str(ship.model().get("category", ""))] = true
			return CARGO_LINES.all(func(line: String) -> bool: return lines_owned.has(line))
		"panama", "suez":
			return int(company.canal_stats.get(badge_id, {}).get("crossings", 0)) > 0
		"all_canals":
			for canal: Dictionary in GameData.canals:
				if int(company.canal_stats.get(str(canal.id), {}).get("crossings", 0)) <= 0:
					return false
			return true
		"loan":
			return company.loan > 0
		"debt_free":  # Had one (the badge for taking it), and none now.
			return company.achievements.has("loan") and company.loan <= 0
		"mega":
			return not company.mega_upgrades.is_empty()
	return false


## Stars earned on a line from how far along it is.
static func stars_for(amount: int, stars: Array) -> int:
	var count := 0
	for need in stars:
		if amount >= int(need):
			count += 1
	return count


## Looks for newly earned achievements for a company and keeps them; returns
## them: [{id, name, stars}] (stars 0 for a badge).
static func check(company: Company) -> Array:
	var news := []
	for line: Dictionary in lines():
		var now := stars_for(progress(company, line.id), line.stars)
		if now > int(company.achievements.get(line.id, 0)):
			company.achievements[line.id] = now
			news.append({id = line.id, name = line.name, stars = now})
	for badge: Array in BADGES:
		if not company.achievements.has(badge[0]) and badge_done(company, badge[0]):
			company.achievements[badge[0]] = 1
			news.append({id = badge[0], name = badge[1], stars = 0})
	return news


## How many achievements and stars there are, and a company has: [stars
## earned, stars in all] (a badge is one star).
static func score(company: Company) -> Vector2i:
	var all := lines()
	var have := 0
	for line: Dictionary in all:
		have += int(company.achievements.get(line.id, 0))
	for badge: Array in BADGES:
		have += 1 if company.achievements.has(badge[0]) else 0
	return Vector2i(have, all.size() * 3 + BADGES.size())


# --- Animals seen (the field guide's checks) ------------------------------------

## Every animal in the field guide: its keys ("bird:<id>", "sea:<id>", "land:<id>").
static func animal_keys() -> Array[String]:
	var out: Array[String] = []
	var birds := Birds.shared()
	for group: Dictionary in [birds.gulls, birds.seabirds, birds.raptors, birds.cormorants, birds.waders, birds.sea_ducks]:
		for id: String in group:
			out.append("bird:" + id)
	for id: String in SeaLife.shared().species:
		out.append("sea:" + id)
	for id: String in birds.land_animals:
		out.append("land:" + id)
	return out


static func animal_count() -> int:
	return animal_keys().size()


## How many of the field guide's animals a company has seen.
static func seen_count(company: Company) -> int:
	var keys := animal_keys()
	var count := 0
	for key in company.discovered:
		if keys.has(key):
			count += 1
	return count


## This player has seen these animals (keys, see animal_keys()): clicked on
## the map, their popup showing them. Kept in their company.
static func discover(keys: Array) -> void:
	for key: String in keys:
		if not GameState.company.discovered.has(key):
			GameState.company.discovered.append(key)


# --- Wonders seen (the field guide's Wonders tab) --------------------------------

## Every wonder of the world on the map: its key ("wonder:<id>").
static func wonder_keys() -> Array[String]:
	var out: Array[String] = []
	for item: Dictionary in GameData.wonders:
		out.append("wonder:" + str(item.id))
	return out


## How many of the wonders a company has seen (clicked on the map).
static func wonders_seen(company: Company) -> int:
	var count := 0
	for key in company.discovered:
		if key.begins_with("wonder:") and not GameData.wonder(key.trim_prefix("wonder:")).is_empty():
			count += 1
	return count
