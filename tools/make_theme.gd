# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends SceneTree
## Writes the game's look into ui/theme.tres (run once after changing LOOK or
## FONTS here): navy panels, bars, cards and popups everywhere but the map and
## the buttons; Signal Flags buttons (signal red, a raised bottom edge that
## presses down, a signal-yellow focus ring); ship tiles in the panels' navy
## (TileButton); every button's text, the bottom bar's page buttons (PageButton,
## a size up) and the headings and titles in Cinzel, everything else in Lato (Nautical Classic; fonts/,
## SIL Open Font License). Run:
##   Godot --headless --path . -s tools/make_theme.gd

const THEME_PATH := "res://ui/theme.tres"

const LOOK := {
	bar = "#0e1f3d", card = "#142a52", popup = "#132849", popup_border = "#dfe6f2", popup_border_w = 2, radius = 4,
	button = "#c8343a", hover = "#dc4a50", pressed = "#9e262b", disabled = "#3b4a6b", edge = "#7e1a1e", edge_w = 1, raise = 3, button_radius = 3,
	text = "#ffffff", accent = "#f2c230", heading = "#ffffff",
}
## The headings' font (Cinzel, bold) and the body's (Lato), and their sizes.
const HEADING_FONT := ["cinzel/Cinzel-Variable.ttf", 700]
const BODY_FONT := ["lato/Lato-Regular.ttf", 0]
const HEADING_TYPES := {HeaderLabel = 25, TitleLabel = 53, ShopCardTitle = 16}
const PAGE_BUTTON_SIZE := 20
const BODY_SIZE := 18


func _init() -> void:
	var theme: Theme = load(THEME_PATH)
	_apply_look(theme, LOOK)
	_apply_fonts(theme)
	var err := ResourceSaver.save(theme, THEME_PATH)
	print("theme saved" if err == OK else "couldn't save the theme: %d" % err)
	quit()


func _apply_look(theme: Theme, look: Dictionary) -> void:
	var radius := int(look.radius)
	theme.set_stylebox(&"panel", &"BarPanel", _box(look.bar, 0, "", 0, Vector4(20, 10, 20, 10)))
	theme.set_stylebox(&"panel", &"ActivityLogPanel", _box(look.bar, 0, "", 0, Vector4(12, 10, 12, 10)))
	theme.set_stylebox(&"panel", &"CardPanel", _box(look.card, radius + 2, "", 0, Vector4(24, 20, 24, 20)))
	theme.set_stylebox(&"panel", &"ShopCard", _box(look.card, radius + 2, "", 0, Vector4(10, 10, 10, 10)))
	theme.set_stylebox(&"panel", &"MapPopup", _box(look.popup, radius, look.popup_border, int(look.popup_border_w), Vector4(14, 10, 14, 12)))
	theme.set_stylebox(&"panel", &"TooltipPanel", _box(look.popup, radius, look.popup_border, 1, Vector4(8, 5, 8, 5)))
	theme.set_stylebox(&"panel", &"PopupMenu", _box(look.popup, radius, look.popup_border, 1, Vector4(6, 6, 6, 6)))
	theme.set_stylebox(&"hover", &"PopupMenu", _box(look.hover, int(look.button_radius), "", 0, Vector4(4, 2, 4, 2)))
	theme.set_stylebox(&"panel", &"TabContainer", _box(look.card, radius, "", 0, Vector4(10, 10, 10, 10)))
	theme.set_stylebox(&"panel", &"PanelContainer", _box(look.card, radius, "", 0, Vector4(0, 0, 0, 0)))
	theme.set_stylebox(&"panel", &"Panel", _box(look.card, radius, "", 0, Vector4(0, 0, 0, 0)))
	var text := Color(look.text)
	for kind: StringName in [&"Button", &"OptionButton", &"MenuButton"]:
		theme.set_stylebox(&"normal", kind, _button_box(look, look.button, look.edge))
		theme.set_stylebox(&"hover", kind, _button_box(look, look.hover, look.edge))
		theme.set_stylebox(&"pressed", kind, _button_box(look, look.pressed, look.edge, true))
		theme.set_stylebox(&"hover_pressed", kind, _button_box(look, look.pressed, look.edge, true))
		theme.set_stylebox(&"disabled", kind, _button_box(look, look.disabled, look.disabled))
		var focus := StyleBoxFlat.new()
		focus.draw_center = false
		focus.set_border_width_all(2)
		focus.border_color = Color(look.accent)
		focus.set_corner_radius_all(int(look.button_radius))
		theme.set_stylebox(&"focus", kind, focus)
		for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
			theme.set_color(state, kind, text)
		theme.set_color(&"font_disabled_color", kind, Color(text, 0.45))
	# The page buttons along the bottom bar: Button's look, in the headings' font.
	theme.set_type_variation(&"PageButton", &"Button")
	# Ship tiles (a whole card that's a button) in the panels' navy, the accent on hover.
	var tile := Color(look.card).lightened(0.07)
	theme.set_type_variation(&"TileButton", &"Button")
	theme.set_stylebox(&"normal", &"TileButton", _box(tile.to_html(), radius, "#3c5585", 1, Vector4(8, 6, 8, 6)))
	theme.set_stylebox(&"hover", &"TileButton", _box(tile.lightened(0.07).to_html(), radius, look.accent, 1, Vector4(8, 6, 8, 6)))
	theme.set_stylebox(&"pressed", &"TileButton", _box(tile.darkened(0.1).to_html(), radius, look.accent, 2, Vector4(8, 6, 8, 6)))
	theme.set_stylebox(&"hover_pressed", &"TileButton", _box(tile.darkened(0.1).to_html(), radius, look.accent, 2, Vector4(8, 6, 8, 6)))
	theme.set_stylebox(&"disabled", &"TileButton", _box(tile.to_html(), radius, "", 0, Vector4(8, 6, 8, 6)))
	theme.set_stylebox(&"focus", &"TileButton", StyleBoxEmpty.new())
	# Tabs: the chosen one in the card's navy with signal yellow along its top.
	var chosen := _box(look.card, int(look.button_radius), look.accent, 0, Vector4(12, 6, 12, 6))
	chosen.border_width_top = 3
	var other := _box(look.bar, int(look.button_radius), "", 0, Vector4(12, 6, 12, 6))
	var over := _box(Color(look.card).lightened(0.08).to_html(), int(look.button_radius), "", 0, Vector4(12, 6, 12, 6))
	for kind: StringName in [&"TabBar", &"TabContainer"]:
		theme.set_stylebox(&"tab_selected", kind, chosen)
		theme.set_stylebox(&"tab_unselected", kind, other)
		theme.set_stylebox(&"tab_hovered", kind, over)
	var field := _box(look.bar, int(look.button_radius), "#3c5585", 1, Vector4(8, 4, 8, 4))
	theme.set_stylebox(&"normal", &"LineEdit", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = Color(look.accent)
	theme.set_stylebox(&"focus", &"LineEdit", field_focus)
	for heading: StringName in [&"HeaderLabel", &"TitleLabel", &"ShopCardTitle"]:
		theme.set_color(&"font_color", heading, Color(look.heading))


## A panel's box: its fill, corners, border and content margins (left, top, right, bottom).
static func _box(fill: String, radius: int, border: String, border_w: int, margins: Vector4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill)
	box.set_corner_radius_all(radius)
	if border_w > 0 and not border.is_empty():
		box.set_border_width_all(border_w)
		box.border_color = Color(border)
	box.content_margin_left = margins.x
	box.content_margin_top = margins.y
	box.content_margin_right = margins.z
	box.content_margin_bottom = margins.w
	box.anti_aliasing = radius > 0
	return box


## A button's box: its fill and edge, the raised bottom edge (pressed down, it
## loses it and the text drops with it).
static func _button_box(look: Dictionary, fill: String, edge: String, pressed := false) -> StyleBoxFlat:
	var box := _box(fill, int(look.button_radius), edge, int(look.edge_w), Vector4(12, 5, 12, 5))
	var raise := int(look.raise)
	box.border_color = Color(look.edge)
	box.border_width_bottom = int(look.edge_w) + (0 if pressed else raise)
	box.content_margin_top = 5.0 + (raise if pressed else 0)
	return box


static func _apply_fonts(theme: Theme) -> void:
	var heading := _font(HEADING_FONT)
	var body := _font(BODY_FONT)
	theme.default_font = body
	theme.default_font_size = BODY_SIZE
	for type: String in HEADING_TYPES:
		theme.set_font(&"font", StringName(type), heading)
		theme.set_font_size(&"font_size", StringName(type), int(HEADING_TYPES[type]))
	theme.set_font(&"font", &"PageButton", heading)
	theme.set_font_size(&"font_size", &"PageButton", PAGE_BUTTON_SIZE)
	# Every button's text in the headings' font too.
	for kind: StringName in [&"Button", &"OptionButton", &"MenuButton", &"CheckButton", &"CheckBox"]:
		theme.set_font(&"font", kind, heading)
	theme.set_font(&"normal_font", &"RichTextLabel", body)
	theme.set_font(&"bold_font", &"RichTextLabel", heading)


## A font file at a weight (a variable font set to it). Any character it
## lacks (stars, ticks, arrows) comes from the system's fonts (FontFile
## allow_system_fallback).
static func _font(spec: Array) -> Font:
	var file: FontFile = load("res://fonts/" + str(spec[0]))
	if int(spec[1]) <= 0:
		return file
	var variation := FontVariation.new()
	variation.base_font = file
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): int(spec[1])}
	return variation
