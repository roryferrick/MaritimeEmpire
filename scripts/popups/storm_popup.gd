# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name StormPopup
extends AnchoredPopup
## Opened by clicking a storm on the map, a row each: its strength at the
## center, the core's edge, halfway out and the edge (building up or fading),
## what that does to ships, its cloud (rings, spiral bands, eye), size, course,
## the ships in it now, how long it has been going and has left, and where it
## formed (and its basin's spawn area and season). Follows the storm and
## refreshes a few times a second; closes when it blows out.

const REFRESH_SECONDS := 0.25
const FONT_SIZE := 14
const LABEL_WIDTH := 70.0
const VALUE_WIDTH := 430.0
## How many of the player's ships in the storm are named before "and 3 more".
const NAMED_SHIPS := 4
const COMPASS := ["east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Set before adding to the tree (Weather.key()).
var storm_key := ""

var _title := Label.new()
var _rows := GridContainer.new()
var _clock := 0.0


func _init() -> void:
	theme_type_variation = &"MapPopup"


func _ready() -> void:
	super()
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_title.theme_type_variation = &"HeaderLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	_rows.columns = 2
	_rows.add_theme_constant_override(&"h_separation", 10)
	_rows.add_theme_constant_override(&"v_separation", 5)
	content.add_child(_rows)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	var storm := MapView.storm_by_key(storm_key)
	if storm.is_empty():
		queue_free()  # Blown out.
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var weather := GameState.weather
	var settings: Dictionary = GameData.config.get("weather", {})
	var level: Dictionary = settings.get("levels", {}).get(GameState.storms, {})
	var tropical := Weather.TROPICAL.has(storm.kind)
	var intensity := Weather.intensity(storm)
	var radius := float(storm.radius_nm)
	_title.text = Weather.title(storm)

	# Strength from the center out (full across the core, fading to nothing at
	# the edge), and what it does to ships.
	var halfway := intensity * (1.0 - smoothstep(Weather.CORE, 1.0, 0.5))
	_row("Strength", "Center %d%%  ·  core's edge (%s nm) %d%%  ·  halfway (%s nm) %d%%  ·  edge (%s nm) 0%%  ·  %s" % [
		_pct(intensity), _nm(radius * Weather.CORE), _pct(intensity), _nm(radius * 0.5), _pct(halfway), _nm(radius),
		"building up" if float(storm.age) < float(storm.life) / 2.0 else "fading"])
	if weather.active():
		_row("Ships", "%d%% slower and %sx wear and breakdowns at its center" % [
			roundi(float(level.get("slow", 0.0)) * intensity * 100.0), Fmt.decimal(1.0 + (float(level.get("wear", 1.0)) - 1.0) * intensity, 1)])
		if tropical:
			var close_at := float(level.get("close_at", 2.0))
			if intensity >= close_at:
				_row("Ports", "Closes ports under its core", &"ErrorLabel")
			else:
				_row("Ports", "Closes ports once its center reaches %d%%" % _pct(close_at), &"DimLabel")
	elif GameState.storms == "none":
		_row("Ships", "This game has no storms", &"DimLabel")
	else:
		_row("Ships", "Storms act on ships from company level %d" % int(settings.get("min_company_level", 1)), &"DimLabel")

	# The cloud as drawn, its size and course.
	var eye := tropical and intensity > MapView.STORM_EYE_FROM
	_row("Cloud", "%d rings, %d spiral bands%s" % [MapView.STORM_HAZE.size(), 3 if tropical else 2,
		", a clear eye" if eye else (", no eye yet" if tropical else "")])
	_row("Size", "%s nm radius (%s nm across)" % [_nm(radius), _nm(radius * 2.0)])
	var ahead := weather.track_ahead(storm)
	if ahead.size() >= 2:
		var step := ahead[1] - ahead[0]
		step.x = wrapf(step.x, -180.0, 180.0) * cos(deg_to_rad(float(storm.lat)))
		var sector := posmod(roundi(step.angle() / (PI / 4.0)), 8)
		var nm_per_s := Geo.distance_nm(ahead[0], ahead[1]) / Weather.TRACK_S
		var knots := nm_per_s * 3600.0 / maxf(GameState.calendar_seconds_per_second(), 1.0)
		_row("Course", "%s at about %d knots (%s nm a minute of play)" % [COMPASS[sector].left(1).to_upper() + COMPASS[sector].substr(1), roundi(knots), _nm(nm_per_s * 60.0)])

	# Ships in it now.
	var mine: Array[String] = []
	var total := 0
	for ship in GameState.ships:
		if ship.is_docked() or ship.from_port.is_empty():
			continue
		if Weather.strength_at(storm, Geo.unproject(ship.world_position())) > 0.0:
			total += 1
			if GameState.is_mine(ship):
				mine.append(ship.name)
	if total == 0:
		_row("In it", "No ships right now", &"DimLabel")
	else:
		var text := "%d of yours" % mine.size() if not mine.is_empty() else "None of yours"
		if not mine.is_empty():
			text += ": " + ", ".join(mine.slice(0, NAMED_SHIPS))
			if mine.size() > NAMED_SHIPS:
				text += " and %d more" % (mine.size() - NAMED_SHIPS)
		var others := total - mine.size()
		if others > 0:
			text += "  ·  %d of other players'" % others
		_row("In it", text)

	# Its life.
	var cps := GameState.calendar_seconds_per_second()
	var left := maxf(float(storm.life) - float(storm.age), 0.0)
	_row("Time", "Going %s (%s of play)  ·  blows out in %s (%s of play)" % [Fmt.calendar_duration(float(storm.age) * cps),
		Fmt.rough_duration(float(storm.age)), Fmt.calendar_duration(left * cps), Fmt.rough_duration(left)])

	# Where it formed, and where its basin's storms form.
	_row("Formed", "At %s" % _place(Weather.track_behind(storm)[0]))
	var basin := weather.basin_of(storm)
	if not basin.is_empty():
		var spawn: Array = basin.spawn
		var months: Array = basin.get("months", [])
		_row("Spawns", "%s %ss form in %s to %s, %s to %s; %s, busiest %s" % [_basin_name(str(basin.id)),
			Weather.KIND_NAMES.get(storm.kind, "Storm").to_lower(), _lon(float(spawn[0][0])), _lon(float(spawn[0][1])),
			_lat(float(spawn[1][0])), _lat(float(spawn[1][1])), "all year" if months.size() >= 12 else _months(months),
			_months(basin.get("peak", []))])


## A row: a dim label, then its value (wrapping).
func _row(label_text: String, text: String, variation := &"") -> void:
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"DimLabel"
	label.custom_minimum_size.x = LABEL_WIDTH
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_rows.add_child(label)
	var value := Label.new()
	value.text = text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.custom_minimum_size.x = VALUE_WIDTH
	if variation != &"":
		value.theme_type_variation = variation
	value.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_rows.add_child(value)


static func _pct(share: float) -> int:
	return roundi(share * 100.0)


static func _nm(miles: float) -> String:
	return Fmt.thousands(roundi(miles))


static func _place(lon_lat: Vector2) -> String:
	return "%s %s" % [_lat(lon_lat.y), _lon(lon_lat.x)]


static func _lat(lat: float) -> String:
	return "%s°%s" % [_degrees(lat), "N" if lat >= 0.0 else "S"]


static func _lon(lon: float) -> String:
	lon = wrapf(lon, -180.0, 180.0)
	return "%s°%s" % [_degrees(lon), "E" if lon >= 0.0 else "W"]


## 14 -> "14", -45.13 -> "45.1".
static func _degrees(value: float) -> String:
	value = absf(value)
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else Fmt.decimal(value, 1)


## "east_pacific" -> "East Pacific", "bay_of_bengal" -> "Bay of Bengal".
static func _basin_name(id: String) -> String:
	var words := id.split("_")
	for i in words.size():
		words[i] = words[i] if words[i] == "of" else words[i].capitalize()
	return " ".join(words)


## Months as "Jun–Nov" when they run on, else "Aug, Sep, Oct" ("none" if empty).
static func _months(list: Array) -> String:
	var months: Array[int] = []
	for m: Variant in list:
		months.append(int(m))
	if months.is_empty():
		return "none"
	var runs := true
	for i in range(1, months.size()):
		if months[i] != months[i - 1] % 12 + 1:
			runs = false
	if runs and months.size() >= 3:
		return "%s–%s" % [MONTHS[months[0] - 1], MONTHS[months[-1] - 1]]
	return ", ".join(months.map(func(m: int) -> String: return MONTHS[m - 1]))
