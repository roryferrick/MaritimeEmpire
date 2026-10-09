# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name LandLifePopup
extends AnchoredPopup
## Opened by clicking a land animal on the map (see Wildlife): its species
## with its picture, its group (how many, and how many young), what they're up
## to now (on the move, grazing, asleep at their den, hibernating...), their
## home, where they live, their habits and a fact. Follows the group; looks
## again a few times a second.

const REFRESH_SECONDS := 0.5
const FONT_SIZE := 14
const LABEL_WIDTH := 64.0
const VALUE_WIDTH := 360.0
const PICTURE_SIZE := 56.0
## One of each kind of young.
const ONE_YOUNG := {cubs = "cub", calves = "calf", joeys = "joey", chicks = "chick", babies = "baby", foals = "foal", crias = "cria"}

## Set before adding to the tree: the group (its index in Wildlife.groups, as
## text) and its species (see MapView.animals_clicked).
var key := ""
var kind := ""

var _title := Label.new()
var _rows := GridContainer.new()
var _clock := 0.0


func _init() -> void:
	theme_type_variation = &"MapPopup"


func _ready() -> void:
	super()
	Achievements.discover(["land:" + kind])  # Seen: checked in the field guide.
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	content.add_child(header)
	header.add_child(FieldGuide._picture(MapView.WILDLIFE_ART_DIR + kind + ".svg", Vector2.ONE * PICTURE_SIZE))
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
	var wildlife := Wildlife.shared()
	var index := int(key)
	if index < 0 or index >= wildlife.groups.size():
		return
	var group: Dictionary = wildlife.groups[index]
	var info: Dictionary = wildlife.land.get(kind, {})
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_title.text = str(info.get("name", kind))
	_row("Group", group_text(group, info))
	_row("Now", wildlife.group_doing(group, float(GameState.calendar_time())))
	_row("Home", home_text(group, info))
	_row("Where", str(info.get("where", "")))
	if info.has("habits"):
		_row("Habits", str(info.habits))
	_row("Fact", str(info.get("fact", "")))
	_row("", "Just for looking at: they don't affect ships.", &"DimLabel")


## "A pride of 6 with 2 cubs", "A mother with 2 cubs", "On its own".
static func group_text(group: Dictionary, info: Dictionary) -> String:
	var count := int(group.members)
	var young := int(group.young)
	var young_word := str(info.get("young_word", "young"))
	var young_text := "%d %s" % [young, young_word] if young != 1 else "a " + str(ONE_YOUNG.get(young_word, young_word))
	if count == 1:
		return "On its own"
	if young == count - 1:
		return "A mother with " + ("her " + str(ONE_YOUNG.get(young_word, young_word)) if young == 1 else young_text)
	if info.get("group_word", "") == "pair" and count == 2 and young == 0:
		return "A pair"
	var text := "A %s of %d" % [info.get("group_word", "group"), count]
	if young > 0:
		text += " with " + young_text
	return text


## Its home, and when it's there: "A cave: home at night", "None: they roam
## and bed down where they are", plus winter sleep and migration.
static func home_text(group: Dictionary, info: Dictionary) -> String:
	var when: String = {day = "back by night", night = "back by day", dusk = "back in the middle of the day and night"}.get(str(info.get("active", "day")), "")
	var text := "None: they roam and bed down where they are" if group.home_kind == "none" else "A %s, %s" % [Wildlife.home_name(group.home_kind), when]
	if info.has("hibernate"):
		text += "; they sleep the winter away in it" if not info.get("den_young", false) else "; a mother and her young keep to it through the winter"
	if info.has("migrate"):
		text += "; they migrate with the seasons"
	return text


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
