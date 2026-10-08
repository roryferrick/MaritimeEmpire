# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name LandLifePopup
extends AnchoredPopup
## Opened by clicking a group of land animals on the map (see LandLife): the
## species with its picture, its group (how many, and how many young), what
## they're up to right now (napping, on the move, rubbing its back on its
## tree...), where they live, their habits and a fact. Follows the group;
## looks again a few times a second.

const REFRESH_SECONDS := 0.5
const FONT_SIZE := 14
const LABEL_WIDTH := 64.0
const VALUE_WIDTH := 360.0
const PICTURE_SIZE := 56.0
## What each act (LandLife) looks like in words.
const DOING := {rest = "resting", chew = "chewing", nod = "nodding off", groom = "grooming", graze = "grazing", peck = "pecking about",
	rear = "up on its hind legs, sniffing the air", rub = "rubbing its back on its tree", sprawl = "sprawled out flat", nap = "napping",
	sleep = "fast asleep", wriggle = "rolling on its back", wallow = "wallowing in the dust", roll = "rolling over", spray = "spraying water over its back",
	dust = "tossing dust over its back", browse = "stretching up to browse", splay = "splaying its legs to drink", roar = "roaring", kick = "kicking up its heels",
	box = "boxing", scratch = "having a scratch", kneel = "kneeling down", toss = "tossing its head", spit = "spitting", chest = "beating its chest",
	sit = "sitting about", hang = "hanging about", sunbathe = "sunbathing", flap = "flapping its flippers", stretch = "having a stretch", hop = "hopping about",
	preen = "preening"}
## How each way of getting about looks in words.
const MOVING := {walk = "on the move", hop = "bounding along", waddle = "waddling along", flit = "flitting about", swing = "swinging through the trees",
	slide = "tobogganing on its belly", roll = "rolling over and over"}

## One of each kind of young.
const ONE_YOUNG := {cubs = "cub", calves = "calf", joeys = "joey", chicks = "chick", babies = "baby", foals = "foal", crias = "cria"}

## Set before adding to the tree: the patch's key and species (see MapView.animals_clicked).
var key := ""
var kind := ""

var _title := Label.new()
var _rows := GridContainer.new()
var _clock := 0.0
var _life := LandLife.new()


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
	var picture := FieldGuide._picture(MapView.DECOR_ART_DIR + kind + ".svg", Vector2.ONE * PICTURE_SIZE)
	header.add_child(picture)
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
	var info: Dictionary = Birds.shared().land_animals.get(kind, {})
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_title.text = str(info.get("name", kind))
	_row("Group", group_text(key, info))
	var poses := _life.poses(key, info, Time.get_ticks_msec() / 1000.0)
	_row("Now", now_text(poses, int(LandLife.group_size(key, info)) > 1))
	_row("Where", str(info.get("where", "")))
	if info.has("habits"):
		_row("Habits", str(info.habits))
	_row("Fact", str(info.get("fact", "")))
	_row("", "Just for looking at: they don't affect ships.", &"DimLabel")


## "A pride of 6 with 2 cubs", "A mother with 2 cubs", "On its own".
static func group_text(key: String, info: Dictionary) -> String:
	var count := LandLife.group_size(key, info)
	var young := 0
	for member in count:
		if LandLife.is_young(key, info, member):
			young += 1
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


## What a group's doing now, most first: "3 grazing, 2 on the move, 1 kicking
## up its heels" (or for one, just what it's doing).
static func now_text(poses: Array, many: bool) -> String:
	var counts := {}
	var order: Array[String] = []
	for pose: Dictionary in poses:
		var doing := str(MOVING.get(str(pose.moving), "on the move")) if not str(pose.moving).is_empty() else str(DOING.get(str(pose.act), "resting"))
		if not counts.has(doing):
			order.append(doing)
		counts[doing] = int(counts.get(doing, 0)) + 1
	if not many:
		var only := order[0] if not order.is_empty() else "resting"
		return only.left(1).to_upper() + only.substr(1)
	order.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	var parts := PackedStringArray()
	for doing in order:
		parts.append("%d %s" % [counts[doing], doing])
	return ", ".join(parts)


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
