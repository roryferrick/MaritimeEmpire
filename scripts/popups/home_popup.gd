# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name HomePopup
extends AnchoredPopup
## Opened by clicking a home on the map (see Wildlife): a bird colony's (a gull
## colony, an eyrie, a heronry...) or a land animal group's (a den, a cave, a
## burrow, a rookery...). Whose it is (with their picture), how many live
## there and where they are now (home, out and about, away for the winter or
## on the wing), when they're there through the year, any eggs or chicks in
## the season, and a fact. Follows the home; looks again every second.

const REFRESH_SECONDS := 1.0
const FONT_SIZE := 14
const LABEL_WIDTH := 64.0
const VALUE_WIDTH := 360.0
const PICTURE_SIZE := 56.0
const MONTH_NAMES := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

## Set before adding to the tree: "colony" or "home", and its index (see MapView.home_clicked).
var kind := ""
var index := -1

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
	header.add_theme_constant_override(&"separation", 10)
	content.add_child(header)
	var wildlife := Wildlife.shared()
	var home_kind: String = (wildlife.colonies[index] if kind == "colony" else wildlife.groups[index]).home_kind
	header.add_child(FieldGuide._picture(MapView.WILDLIFE_ART_DIR + "home_" + home_kind + ".svg", Vector2.ONE * PICTURE_SIZE))
	_title.theme_type_variation = &"HeaderLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if kind == "colony":
		_colony_rows()
	else:
		_group_rows()
	_row("", "Just for looking at: they don't affect ships.", &"DimLabel")


func _colony_rows() -> void:
	var wildlife := Wildlife.shared()
	var colony: Dictionary = wildlife.colonies[index]
	var info := Birds.shared().species(colony.species)
	var cal := float(GameState.calendar_time())
	Achievements.discover(["bird:" + str(colony.species)])  # Seen: checked in the field guide.
	var name := str(info.get("name", colony.species))
	_title.text = "%s (%s)" % [_upper(Wildlife.home_name(colony.home_kind)), name]
	_row("Where", "On the shore near %s" % GameData.port_name(colony.port))
	var where := wildlife.colony_where(colony, cal)
	var away := GameData.port_name(colony.away_port) if not str(colony.away_port).is_empty() else "their winter grounds"
	var now := ""
	match where[0]:
		"home":
			now = "%d live here: %s" % [int(colony.count), ", ".join(BirdLife.shared().doing_text(index, Wildlife.shared().bird_time, cal))]
		"away":
			now = "Away at %s for now" % away
		"to_away":
			now = "%d on the wing to %s" % [int(colony.count), away]
		"to_home":
			now = "%d on the wing, coming home from %s" % [int(colony.count), away]
	_row("Now", now)
	var months: Array = colony.home_months
	if months.size() >= 12:
		_row("Year", "Here all year")
	else:
		_row("Year", "Here %s; the rest of the year at %s" % [_months_text(months), away])
	var young := wildlife.young_now(colony, cal)
	if not young.is_empty():
		_row("Young", "Eggs in the nests" if young == "eggs" else "Chicks in the nests")
	_row("Fact", str(info.get("fact", "")))


func _group_rows() -> void:
	var wildlife := Wildlife.shared()
	var group: Dictionary = wildlife.groups[index]
	var info: Dictionary = wildlife.land.get(group.species, {})
	Achievements.discover(["land:" + str(group.species)])  # Seen: checked in the field guide.
	_title.text = "%s (%s)" % [_upper(Wildlife.home_name(group.home_kind)), str(info.get("name", group.species))]
	_row("Lives here", LandLifePopup.group_text(group, info))
	_row("Now", wildlife.group_doing(group, float(GameState.calendar_time())))
	_row("Home", LandLifePopup.home_text(group, info))
	if info.has("habits"):
		_row("Habits", str(info.habits))
	_row("Fact", str(info.get("fact", "")))


## "April to September" (months it's home, a run that can wrap round the new year).
static func _months_text(months: Array) -> String:
	var first := -1
	for m in range(1, 13):
		var before := (m + 10) % 12 + 1
		if months.has(m) and not months.has(before):
			first = m
			break
	if first < 0:
		return "all year"
	var last := first
	while months.has(last % 12 + 1) and last % 12 + 1 != first:
		last = last % 12 + 1
	return "%s to %s" % [MONTH_NAMES[first - 1], MONTH_NAMES[last - 1]] if last != first else MONTH_NAMES[first - 1]


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


## Text with its first letter a capital.
static func _upper(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)
