# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Traits
## Character traits and skills (data/traits.json; DESIGN_LIVING_WORLD.md
## Characters and traits): one system for every character. A character
## ({name, look}: Characters) may carry traits (character.traits, trait ids)
## and skills (character.skills: SKILLS, from 0 with no cap; a character
## without them has BASE_SKILL in each). A CEO's traits work for the whole
## company (effect()): x sale prices, less fuel, wear, breakdowns, wages and
## loan interest. The player's CEO gets theirs from the backstory start
## (Backstories); every paper shipping firm's CEO gets random_traits().

const PATH := "res://data/traits.json"
const SKILLS := ["seamanship", "finance", "negotiation", "engineering", "leadership"]
const SKILL_NAMES := {seamanship = "Seamanship", finance = "Finance", negotiation = "Negotiation", engineering = "Engineering", leadership = "Leadership"}
const BASE_SKILL := 5
## The most traits a character gets at random.
const RANDOM_MOST := 3

static var _data := {}
static var _by_id := {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		for each: Dictionary in _data.get("traits", []):
			_by_id[each.id] = each
	return _data


static func all() -> Array:
	return data().get("traits", [])


static func info(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func trait_name(id: String) -> String:
	return str(info(id).get("name", id.capitalize()))


## A character's traits (ids), [] for none.
static func of(character: Dictionary) -> Array:
	return character.get("traits", []) if character.get("traits") is Array else []


## The names of a character's traits, joined ("Shrewd, Ex-Navy"), or "".
static func names_of(character: Dictionary) -> String:
	var names := PackedStringArray()
	for id: String in of(character):
		names.append(trait_name(id))
	return ", ".join(names)


## A character's skills with their traits' adds: {skill: value}.
static func skills_of(character: Dictionary) -> Dictionary:
	var out := {}
	var base: Dictionary = character.get("skills", {}) if character.get("skills") is Dictionary else {}
	for skill: String in SKILLS:
		out[skill] = int(base.get(skill, BASE_SKILL))
	for id: String in of(character):
		var adds: Dictionary = info(id).get("skills", {})
		for skill: String in adds:
			out[skill] = int(out.get(skill, 0)) + int(adds[skill])
	return out


## What a company's CEO's traits do for it: the sum of their `key` effects
## (price, fuel, wear, breakdowns, wages, interest, fees), 0 for none.
static func effect(who: Company, key: String) -> float:
	if who == null or who.ceo.is_empty():
		return 0.0
	var total := 0.0
	for id: String in of(who.ceo):
		total += float((info(id).get("effects", {}) as Dictionary).get(key, 0.0))
	return total


## 1 + effect, for multiplying something up (x prices), or 1 - effect for down (x fuel).
static func factor(who: Company, key: String, up := true) -> float:
	var e := effect(who, key)
	return maxf(1.0 + e if up else 1.0 - e, 0.0)


## A paper firm's CEO's margin factor (ai.margin, multiplied over the traits): 1 with none.
static func ai_margin(character: Dictionary) -> float:
	var out := 1.0
	for id: String in of(character):
		out *= float((info(id).get("ai", {}) as Dictionary).get("margin", 1.0))
	return out


## One to RANDOM_MOST traits at random, none of them opposites.
static func random_traits(rng: RandomNumberGenerator, count := -1) -> Array:
	var pool: Array = all().duplicate()
	var out := []
	var wanted := count if count >= 0 else 1 + rng.randi() % RANDOM_MOST
	while out.size() < wanted and not pool.is_empty():
		var pick: Dictionary = pool[rng.randi() % pool.size()]
		pool.erase(pick)
		if out.any(func(id: String) -> bool: return id in pick.get("opposites", []) or pick.id in info(id).get("opposites", [])):
			continue
		out.append(str(pick.id))
	return out


## Random skills, mostly middling (the sum of two rolls round BASE_SKILL).
static func random_skills(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for skill: String in SKILLS:
		out[skill] = maxi(BASE_SKILL - 3 + rng.randi() % 4 + rng.randi() % 4, 0)
	return out


## A trait's line in a story, with the character's name in it.
static func story_line(id: String, character_name: String) -> String:
	return str(info(id).get("story", "")).replace("{name}", character_name)
