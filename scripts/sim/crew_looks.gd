# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CrewLooks
extends RefCounted
## What the people on deck wear (data/uniforms.json): each ship line (a
## model's category) dresses its captain and mates one way and its crew
## another, a hat (Characters headwear, by name), a shirt (the shoulders'
## colour seen from above) and trousers (the legs', walking). A company can
## change any line's outfits (Company.uniforms: {line: {role: {part: name}}},
## set with GameState.set_uniform()); what it hasn't changed is the line's
## default. Dock workers wear the port's hi-vis (dock_outfit()).

const ROLES := ["captain", "crew"]
const PARTS := ["hat", "shirt", "trousers"]

static var _data := {}
static var _lines := {}  # id -> the line's entry.
static var _colors := {}  # "shirts"/"trousers" -> {name: Color}.


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/uniforms.json"))
		for line: Dictionary in _data.lines:
			_lines[line.id] = line
		for list: String in ["shirts", "trousers"]:
			var colors := {}
			for pair: Array in _data[list]:
				colors[pair[0]] = Color(pair[1])
			_colors[list] = colors
	return _data


## The lines in the order the Uniforms page shows them: [{id, title, captain, crew}].
static func lines() -> Array:
	return data().lines


## A model's line (its category; any line without an entry dresses as container ships).
static func line_of(model: Dictionary) -> String:
	data()
	var category := str(model.get("category", ""))
	return category if _lines.has(category) else "container"


static func has_line(line: String) -> bool:
	data()
	return _lines.has(line)


static func line_title(line: String) -> String:
	data()
	return str(_lines.get(line, {}).get("title", line.capitalize()))


## The names a part can be: the hats (Characters headwear), shirt or trouser colours.
static func choices(part: String) -> Array:
	if part == "hat":
		for entry: Array in Characters.PARTS:
			if entry[0] == "headwear":
				return entry[2]
		return []
	return (data()[("shirts" if part == "shirt" else "trousers")] as Array).map(func(pair: Array) -> String: return pair[0])


## A line's default outfit for a role ("captain" or "crew"): {hat, shirt, trousers}.
static func default_outfit(line: String, role: String) -> Dictionary:
	data()
	return (_lines.get(line, _lines.container) as Dictionary)[role]


## What a company's people of a role wear on a line: its own choices over the line's defaults.
static func outfit(company: Company, line: String, role: String) -> Dictionary:
	var dressed := default_outfit(line, role).duplicate()
	if company != null:
		var own: Dictionary = company.uniforms.get(line, {}).get(role, {})
		for part: String in own:
			dressed[part] = own[part]
	return dressed


## A ship's outfit for a role (its owner's, for its model's line).
static func ship_outfit(ship: Ship, role: String) -> Dictionary:
	return outfit(GameState.owner_of(ship), line_of(ship.model()), role)


## The dock workers' outfits (one picked by each worker's seed).
static func dock_outfit(seed: int) -> Dictionary:
	var list: Array = data().dock
	return list[absi(seed) % list.size()]


## A hat's index in Characters headwear (0, none, for a name it doesn't know).
static func hat_index(hat_name: String) -> int:
	return maxi(choices("hat").find(hat_name), 0)


static func shirt_color(color_name: String) -> Color:
	data()
	return _colors.shirts.get(color_name, Color("#8a8f96"))


static func trouser_color(color_name: String) -> Color:
	data()
	return _colors.trousers.get(color_name, Color("#3c4046"))


## Whether a choice is one a part can take (GameState.set_uniform() checks with this).
static func is_choice(part: String, value: String) -> bool:
	return part in PARTS and choices(part).has(value)


## An officer (Characters {name, look}) as they look aboard a ship: wearing
## the captain's hat of its line's uniform, the rest of their look their own.
static func dressed(officer: Dictionary, ship: Ship) -> Dictionary:
	if officer.is_empty():
		return officer
	var copy := officer.duplicate(true)
	var look: Dictionary = copy.get("look", {})
	look["headwear"] = hat_index(str(ship_outfit(ship, "captain").hat))
	copy["look"] = look
	return copy


## The crew's settings (uniforms.json crew).
static func settings() -> Dictionary:
	return data().crew
