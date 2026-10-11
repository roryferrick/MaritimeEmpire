# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name AppearancePage
extends Control
## The Appearance page (Appearance on the title screen and in the Esc menu):
## the look of the game's panels and buttons, one of UiLook's 10 themes, each
## shown as a small card with a heading and a button in its colours; and its
## fonts, one of UiLook's 10 pairs, each shown with a heading and a line of
## text in them. A click puts it on at once (the whole game, this page too)
## and keeps it. Over whatever opened it, dimming it; Esc, X or a click
## outside closes it.

const PANEL_SIZE := Vector2(900, 660)
const THEME_CARD := Vector2(160, 118)

var _content := VBoxContainer.new()


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
	card.custom_minimum_size = Vector2(PANEL_SIZE.x, minf(PANEL_SIZE.y, get_viewport_rect().size.y - 60.0))
	center.add_child(card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 10)
	card.add_child(page)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Appearance"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	page.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_content.add_theme_constant_override(&"separation", 12)
	_content.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_show()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _show() -> void:
	for child in _content.get_children():
		child.queue_free()
	_content.add_child(_heading("Theme", "The panels, bars and buttons: %d themes x %d font pairs, %d looks in all." % [UiLook.THEMES.size(), UiLook.FONTS.size(), UiLook.THEMES.size() * UiLook.FONTS.size()]))
	var themes := GridContainer.new()
	themes.columns = 5
	themes.add_theme_constant_override(&"h_separation", 10)
	themes.add_theme_constant_override(&"v_separation", 10)
	for i in UiLook.THEMES.size():
		themes.add_child(_theme_card(i))
	_content.add_child(themes)
	_content.add_child(_heading("Fonts", "One for headings and titles, one for everything else."))
	var fonts := GridContainer.new()
	fonts.columns = 2
	fonts.add_theme_constant_override(&"h_separation", 10)
	fonts.add_theme_constant_override(&"v_separation", 10)
	for i in UiLook.FONTS.size():
		fonts.add_child(_font_card(i))
	_content.add_child(fonts)


func _heading(text: String, note: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = text
	box.add_child(title)
	var dim := Label.new()
	dim.theme_type_variation = &"DimLabel"
	dim.text = note
	box.add_child(dim)
	return box


## A theme's card: its panel colour, a heading and a button in its colours, its
## name under; outlined in its accent when it's the one on.
func _theme_card(index: int) -> Control:
	var look: Dictionary = UiLook.THEMES[index]
	var on := index == UiLook.theme_index
	var button := Button.new()
	button.custom_minimum_size = THEME_CARD
	button.focus_mode = FOCUS_NONE
	button.tooltip_text = "%s: %s" % [look.name, look.note]
	var face := StyleBoxFlat.new()
	face.bg_color = Color(look.card)
	face.set_corner_radius_all(int(look.radius) + 2)
	face.set_border_width_all(3 if on else 1)
	face.border_color = Color(look.accent) if on else Color(look.popup_border)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		button.add_theme_stylebox_override(state, face)
	button.pressed.connect(func() -> void:
		UiLook.choose(index, UiLook.font_index)
		_show.call_deferred())
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 10)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	var bar := ColorRect.new()  # (Its bar colour, as the top bar.)
	bar.color = Color(look.bar)
	bar.custom_minimum_size.y = 8
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(bar)
	var name_label := Label.new()
	name_label.text = str(look.name)
	name_label.add_theme_color_override(&"font_color", Color(look.heading))
	name_label.add_theme_font_size_override(&"font_size", 15)
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var sample := PanelContainer.new()  # (A button as it looks.)
	sample.add_theme_stylebox_override(&"panel", UiLook._button_box(look, look.button, look.edge))
	sample.mouse_filter = MOUSE_FILTER_IGNORE
	sample.size_flags_horizontal = SIZE_SHRINK_BEGIN
	var sample_text := Label.new()
	sample_text.text = "Set sail"
	sample_text.add_theme_color_override(&"font_color", Color(look.text))
	sample_text.add_theme_font_size_override(&"font_size", 14)
	sample.add_child(sample_text)
	box.add_child(sample)
	var tick := Label.new()
	tick.text = "In use" if on else ""
	tick.add_theme_color_override(&"font_color", Color(look.accent))
	tick.add_theme_font_size_override(&"font_size", 12)
	tick.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(tick)
	button.add_child(box)
	return button


## A font pair's card: a heading and a line of text in its fonts, its name and note.
func _font_card(index: int) -> Control:
	var pair: Dictionary = UiLook.FONTS[index]
	var on := index == UiLook.font_index
	var look: Dictionary = UiLook.THEMES[UiLook.theme_index]
	var button := Button.new()
	button.custom_minimum_size = Vector2(410, 104)
	button.focus_mode = FOCUS_NONE
	var face := StyleBoxFlat.new()
	face.bg_color = Color(look.bar)
	face.set_corner_radius_all(int(look.radius))
	face.set_border_width_all(3 if on else 1)
	face.border_color = Color(look.accent) if on else Color(look.popup_border)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		button.add_theme_stylebox_override(state, face)
	button.pressed.connect(func() -> void:
		UiLook.choose(UiLook.theme_index, index)
		_show.call_deferred())
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 10)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 2)
	var heading := Label.new()
	heading.text = "%s%s" % [pair.name, "  (in use)" if on else ""]
	heading.add_theme_font_override(&"font", UiLook._font(pair.heading))
	heading.add_theme_font_size_override(&"font_size", roundi(24 * float(pair.heading_scale)))
	heading.add_theme_color_override(&"font_color", Color(look.heading))
	heading.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(heading)
	var body := Label.new()
	body.text = "Loaded 5,000 tons of grain at Santos for Rotterdam."
	body.add_theme_font_override(&"font", UiLook._font(pair.body))
	body.add_theme_font_size_override(&"font_size", roundi(16 * float(pair.body_scale)))
	body.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(body)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.text = str(pair.note)
	note.add_theme_font_size_override(&"font_size", 12)
	note.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(note)
	button.add_child(box)
	return button
