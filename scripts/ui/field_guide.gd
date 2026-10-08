# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name FieldGuide
extends Control
## The field guide (the paw button at the map's top right): every bird, sea
## animal and land animal in the game, a tab each. Birds (data/birds.json):
## the gulls and the seabirds, each with its picture, Latin name, where and
## when to see it, and a fact. Sea animals (data/sea_life.json): each with its
## picture, size, the waters its pods visit, and a fact. Land animals (the
## drawings on the map: data/birds.json land_animals): each with its picture,
## where it lives, and a fact. Over the map, dimming it; Esc, X or a click
## outside closes it.

const PANEL_SIZE := Vector2(820, 640)
const TEXT_WIDTH := 600.0
const SMALL_FONT := 14
const ICON_SIZE := 56.0
const TABS := ["Birds", "Sea animals", "Land animals"]

var _tabs := TabBar.new()
var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(PANEL_SIZE.x, minf(PANEL_SIZE.y, get_viewport_rect().size.y - 80.0))
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 10)
	card.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	var paw := PawIcon.new()
	paw.custom_minimum_size = Vector2(30, 30)
	header.add_child(paw)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Field guide"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	for tab: String in TABS:
		_tabs.add_tab(tab)
	_tabs.tab_changed.connect(_show)
	content.add_child(_tabs)
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_scroll)
	_list.add_theme_constant_override(&"separation", 12)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_show(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _show(tab: int) -> void:
	for child in _list.get_children():
		child.queue_free()
	_scroll.scroll_vertical = 0
	match tab:
		0:
			var birds := Birds.shared()
			_heading("Gulls", "Over every port, over grain and livestock carriers, and now and then over other ships and sea animals: most at dawn and dusk, few at night, more in the breeding season and round ships loading or unloading.")
			for id: String in birds.gulls:
				_bird_entry(birds.gulls[id])
			_heading("Seabirds", "Out at sea they take up following ships for a few hours at a time, where they are that season: condors along the coasts, albatrosses and shearwaters over the open ocean, terns and pelicans nearer land.")
			for id: String in birds.seabirds:
				_bird_entry(birds.seabirds[id])
		1:
			var sea := SeaLife.shared()
			for id: String in sea.species:
				_sea_entry(sea, id)
		2:
			var land: Dictionary = Birds.shared().land_animals
			for id: String in land:
				_land_entry(id, land[id])


func _heading(text: String, note: String) -> void:
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = text
	_list.add_child(title)
	_list.add_child(_text(note))


func _text(text: String, dim := true) -> Label:
	var label := Label.new()
	if dim:
		label.theme_type_variation = &"DimLabel"
	label.add_theme_font_size_override(&"font_size", SMALL_FONT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TEXT_WIDTH
	label.text = text
	return label


## An entry: a picture, then its name (and a line under it), and its lines.
func _entry(picture: Control, name: String, subtitle: String, lines: Array[String]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	picture.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(picture)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 1)
	var title := Label.new()
	title.text = name
	text.add_child(title)
	if not subtitle.is_empty():
		var sub := _text(subtitle)
		text.add_child(sub)
	for line in lines:
		text.add_child(_text(line, false) if line.begins_with("Where") else _text(line))
	row.add_child(text)
	_list.add_child(row)


func _bird_entry(info: Dictionary) -> void:
	var subtitle := str(info.get("latin", ""))
	if info.has("kind"):
		subtitle = "%s · %s" % [info.kind, subtitle]
	_entry(BirdIcon.new(info, ICON_SIZE), str(info.get("name", "")), subtitle,
		["Where: %s" % info.get("where", ""), str(info.get("fact", ""))])


func _sea_entry(sea: SeaLife, id: String) -> void:
	var kind: Dictionary = sea.species[id]
	# The waters its pods visit, in the order first met.
	var waters := PackedStringArray()
	for pod: Dictionary in sea.pods:
		if pod.species != id:
			continue
		for stay: Dictionary in pod.stays:
			var area_name := str(sea.areas.get(stay.area, {}).get("name", stay.area))
			if not waters.has(area_name):
				waters.append(area_name)
	var places := ", ".join(waters)
	var where := "Where: %s." % (places.left(1).to_upper() + places.substr(1)) if not places.is_empty() else "Where: the open ocean."
	_entry(_picture(MapView.SEA_ART_DIR + str(kind.get("art", id)) + ".svg", Vector2(ICON_SIZE * 1.6, ICON_SIZE * 0.6)),
		str(kind.get("name", id)), "Up to %s m long" % kind.get("length_m", "?"), [where, str(kind.get("fact", ""))])


func _land_entry(id: String, info: Dictionary) -> void:
	_entry(_picture(MapView.DECOR_ART_DIR + id + ".svg", Vector2.ONE * ICON_SIZE), str(info.get("name", id)), "",
		["Where: %s" % info.get("where", ""), str(info.get("fact", ""))])


static func _picture(path: String, side: Vector2) -> Control:
	var picture := TextureRect.new()
	picture.custom_minimum_size = side
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if ResourceLoader.exists(path):
		picture.texture = load(path)
	return picture
