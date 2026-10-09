# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name WonderPopup
extends AnchoredPopup
## Opened by clicking a wonder of the world on the map (data/wonders.json):
## its picture and name, what kind of wonder it is and where, when it was
## built (or formed, or is best seen), and a fact. Checks it off in the field
## guide's Wonders tab. Follows it as the map moves.

const FONT_SIZE := 14
const TEXT_WIDTH := 380.0
const PICTURE_SIZE := 72.0
## What each kind of wonder is called.
const KIND_NAMES := {natural = "Natural wonder", man_made = "Man-made wonder", ancient = "Ancient wonder, now lost"}

## Set before adding to the tree: the wonder's id.
var id := ""


func _init() -> void:
	theme_type_variation = &"MapPopup"


func _ready() -> void:
	super()
	Achievements.discover(["wonder:" + id])  # Seen: checked in the field guide.
	var item := GameData.wonder(id)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	content.add_child(header)
	var picture := FieldGuide._picture(MapView.WONDER_ART_DIR + id + ".svg", Vector2.ONE * PICTURE_SIZE)
	if item.get("kind", "") == "ancient":
		picture.modulate.a = MapView.WONDER_LOST_ALPHA
	header.add_child(picture)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(titles)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = str(item.get("name", id))
	titles.add_child(title)
	titles.add_child(_text("%s · %s" % [KIND_NAMES.get(item.get("kind", ""), "Wonder"), item.get("country", "")], true))
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(_text(str(item.get("when", "")), true))
	content.add_child(_text(str(item.get("fact", "")), false))


func _text(text: String, dim: bool) -> Label:
	var label := Label.new()
	if dim:
		label.theme_type_variation = &"DimLabel"
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TEXT_WIDTH
	label.text = text
	return label
