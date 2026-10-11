# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name UiLook
extends RefCounted
## How the game's panels, buttons and text look, the player's choice of 10
## themes (THEMES: the panels' and bars' colours, the popups' borders, the
## buttons' shape, fill and edge, the accent and the headings' colour) and 10
## pairs of fonts (FONTS: one for the headings and titles, one for everything
## else, bundled in fonts/, all SIL Open Font License), so 100 looks. Chosen on
## the Appearance page (AppearancePage), kept in user://settings.cfg and put on
## at boot (apply_saved()). It changes the project theme (ui/theme.tres) in
## memory, never on disk: every control using it changes at once.

const SETTINGS_PATH := "user://settings.cfg"

## Each theme: bar (the top and bottom bars, the activity log), card (cards
## and pages), popup (map popups and menus) and its border, the buttons
## (fill, hover, pressed, disabled, edge, its width, an extra bottom edge for
## a raised look, corner radius, text colour), the accent (focus rings, the
## chosen tab) and the headings' colour.
const THEMES := [
	{name = "Harbour Night", note = "The slate blue the game has always worn, buttons given a crisp edge.",
		bar = "#1f242e", card = "#292e3b", popup = "#262b36", popup_border = "#737f94", popup_border_w = 2, radius = 6,
		button = "#313744", hover = "#3c4454", pressed = "#252a34", disabled = "#2a2e37", edge = "#4a5262", edge_w = 1, raise = 0, button_radius = 4,
		text = "#f0f2f5", accent = "#5aa0e6", heading = "#ffffff"},
	{name = "Deep Ocean", note = "Navy water and teal light, soft rounded buttons.",
		bar = "#0b1a2b", card = "#10263d", popup = "#0f2338", popup_border = "#1fa3a3", popup_border_w = 2, radius = 10,
		button = "#12405a", hover = "#17536f", pressed = "#0d3146", disabled = "#13283a", edge = "#1fa3a3", edge_w = 1, raise = 0, button_radius = 10,
		text = "#e6fbff", accent = "#2fd0c4", heading = "#8ee8e0"},
	{name = "Brass & Mahogany", note = "A captain's cabin: dark wood panels trimmed in brass.",
		bar = "#1e120c", card = "#2b1a12", popup = "#2b1a12", popup_border = "#c9a25a", popup_border_w = 2, radius = 4,
		button = "#3a2418", hover = "#4a2f1f", pressed = "#2a1810", disabled = "#2a1e18", edge = "#c9a25a", edge_w = 1, raise = 0, button_radius = 3,
		text = "#f3e3c3", accent = "#e0b860", heading = "#e8c47a"},
	{name = "Admiralty", note = "Navy blue and gold braid, square-cut like a dress uniform.",
		bar = "#0d1730", card = "#142240", popup = "#142240", popup_border = "#d4af37", popup_border_w = 2, radius = 0,
		button = "#1b2d55", hover = "#24396a", pressed = "#111f3d", disabled = "#18223a", edge = "#d4af37", edge_w = 1, raise = 0, button_radius = 0,
		text = "#ffffff", accent = "#d4af37", heading = "#f0d27a"},
	{name = "Signal Flags", note = "Charcoal with bold red signal buttons that press down.",
		bar = "#18181b", card = "#222226", popup = "#222226", popup_border = "#f2f2f2", popup_border_w = 2, radius = 3,
		button = "#c8343a", hover = "#dc4a50", pressed = "#9e262b", disabled = "#46464c", edge = "#7e1a1e", edge_w = 1, raise = 3, button_radius = 2,
		text = "#ffffff", accent = "#f2c230", heading = "#ffffff"},
	{name = "Coral Reef", note = "Twilight reef panels with coral pill buttons.",
		bar = "#161b29", card = "#1d2433", popup = "#1d2433", popup_border = "#ff7a59", popup_border_w = 2, radius = 14,
		button = "#d9563c", hover = "#e86a4f", pressed = "#b8452f", disabled = "#3a3f4e", edge = "#ff9e82", edge_w = 0, raise = 0, button_radius = 18,
		text = "#ffffff", accent = "#ffb38a", heading = "#ffb38a"},
	{name = "Arctic", note = "Ice-grey panels with frosted blue edges.",
		bar = "#1f2833", card = "#26313d", popup = "#26313d", popup_border = "#9fc4e0", popup_border_w = 1, radius = 8,
		button = "#34485c", hover = "#40597a", pressed = "#2a3a4c", disabled = "#2b3440", edge = "#9fc4e0", edge_w = 1, raise = 0, button_radius = 8,
		text = "#eef7ff", accent = "#9fd6ff", heading = "#cfe8ff"},
	{name = "Steel Hull", note = "Gunmetal plate, riveted edges and safety orange.",
		bar = "#202326", card = "#2a2d31", popup = "#2a2d31", popup_border = "#5a6068", popup_border_w = 3, radius = 4,
		button = "#3d434a", hover = "#4a525b", pressed = "#30353b", disabled = "#2e3135", edge = "#6a727c", edge_w = 2, raise = 3, button_radius = 4,
		text = "#e8eaed", accent = "#f2a541", heading = "#ffffff"},
	{name = "Sunset Sail", note = "Plum dusk with warm amber buttons.",
		bar = "#241726", card = "#2e1f2f", popup = "#2e1f2f", popup_border = "#f2a541", popup_border_w = 2, radius = 12,
		button = "#b8691c", hover = "#cc7c2c", pressed = "#9a5614", disabled = "#46344a", edge = "#ffd08a", edge_w = 0, raise = 0, button_radius = 12,
		text = "#ffffff", accent = "#ff9a59", heading = "#ffcf8a"},
	{name = "Kelp Forest", note = "Deep green water with sea-glass buttons.",
		bar = "#111c17", card = "#16241d", popup = "#16241d", popup_border = "#3fa66a", popup_border_w = 2, radius = 6,
		button = "#1f3a2c", hover = "#285039", pressed = "#172d22", disabled = "#1a2620", edge = "#3fa66a", edge_w = 1, raise = 0, button_radius = 6,
		text = "#e8f5ec", accent = "#6fd69a", heading = "#a8e6c0"},
]

## Each pair: the headings' font and the body's, each [file, weight (for a
## variable font; 0 for its own)], with a size for the headings (a share of
## their usual) and for the body (of the usual 18).
const FONTS := [
	{name = "Harbour Standard", note = "Montserrat headings, Open Sans text: clean and familiar.",
		heading = ["montserrat/Montserrat-Variable.ttf", 700], body = ["opensans/OpenSans-Variable.ttf", 600], heading_scale = 1.0, body_scale = 1.0},
	{name = "Nautical Classic", note = "Cinzel's carved capitals over friendly Lato.",
		heading = ["cinzel/Cinzel-Variable.ttf", 700], body = ["lato/Lato-Regular.ttf", 0], heading_scale = 0.95, body_scale = 1.02},
	{name = "Captain's Log", note = "Playfair Display's ink-pen contrast with Source Sans.",
		heading = ["playfairdisplay/PlayfairDisplay-Variable.ttf", 700], body = ["sourcesans3/SourceSans3-Variable.ttf", 500], heading_scale = 1.0, body_scale = 1.04},
	{name = "Harbour Signage", note = "Tall Bebas Neue signage with Roboto.",
		heading = ["bebasneue/BebasNeue-Regular.ttf", 0], body = ["roboto/Roboto-Variable.ttf", 500], heading_scale = 1.2, body_scale = 1.0},
	{name = "Dockyard", note = "Condensed industrial Oswald over crisp Inter.",
		heading = ["oswald/Oswald-Variable.ttf", 600], body = ["inter/Inter-Variable.ttf", 500], heading_scale = 1.05, body_scale = 0.97},
	{name = "Cartoon Sea", note = "Round, bubbly Fredoka and Nunito, to match the art.",
		heading = ["fredoka/Fredoka-Variable.ttf", 600], body = ["nunito/Nunito-Variable.ttf", 600], heading_scale = 1.0, body_scale = 1.02},
	{name = "Old Charts", note = "IM Fell's old engraved capitals with bookish Crimson Pro.",
		heading = ["imfellenglishsc/IMFeENsc28P.ttf", 0], body = ["crimsonpro/CrimsonPro-Variable.ttf", 500], heading_scale = 1.05, body_scale = 1.12},
	{name = "Pirate's Cove", note = "Blackletter Pirata One over warm Alegreya Sans.",
		heading = ["pirataone/PirataOne-Regular.ttf", 0], body = ["alegreyasans/AlegreyaSans-Regular.ttf", 0], heading_scale = 1.15, body_scale = 1.06},
	{name = "Bridge Console", note = "Space Grotesk and IBM Plex Sans, like a ship's instruments.",
		heading = ["spacegrotesk/SpaceGrotesk-Variable.ttf", 700], body = ["ibmplexsans/IBMPlexSans-Variable.ttf", 500], heading_scale = 1.0, body_scale = 0.98},
	{name = "Ocean Liner", note = "Art deco Josefin Sans with elegant Raleway.",
		heading = ["josefinsans/JosefinSans-Variable.ttf", 700], body = ["raleway/Raleway-Variable.ttf", 500], heading_scale = 1.05, body_scale = 1.0},
]

## The heading styles (theme type variations) that take the headings' font,
## with their usual sizes; the body's usual size.
const HEADING_TYPES := {HeaderLabel = 26, TitleLabel = 56, ShopCardTitle = 17}
const BODY_SIZE := 18

static var theme_index := 0
static var font_index := 0
static var _fonts := {}  # [file, weight] -> its Font, made once.


## The saved choice, put on (at boot).
static func apply_saved() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		theme_index = clampi(int(config.get_value("look", "theme", 0)), 0, THEMES.size() - 1)
		font_index = clampi(int(config.get_value("look", "fonts", 0)), 0, FONTS.size() - 1)
	apply(theme_index, font_index)


## Puts on a theme and a pair of fonts, and keeps the choice.
static func choose(new_theme: int, new_fonts: int) -> void:
	apply(new_theme, new_fonts)
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # (Keeping whatever else it holds.)
	config.set_value("look", "theme", theme_index)
	config.set_value("look", "fonts", font_index)
	config.save(SETTINGS_PATH)


## Puts a theme and a pair of fonts on the project theme.
static func apply(new_theme: int, new_fonts: int) -> void:
	theme_index = clampi(new_theme, 0, THEMES.size() - 1)
	font_index = clampi(new_fonts, 0, FONTS.size() - 1)
	var theme := ThemeDB.get_project_theme()
	if theme == null:
		return
	_apply_theme(theme, THEMES[theme_index])
	_apply_fonts(theme, FONTS[font_index])


static func _apply_theme(theme: Theme, look: Dictionary) -> void:
	var radius := int(look.radius)
	theme.set_stylebox(&"panel", &"BarPanel", _box(look.bar, 0, "", 0, Vector4(20, 10, 20, 10)))
	theme.set_stylebox(&"panel", &"ActivityLogPanel", _box(look.bar, 0, "", 0, Vector4(12, 10, 12, 10)))
	theme.set_stylebox(&"panel", &"CardPanel", _box(look.card, radius + 2, "", 0, Vector4(24, 20, 24, 20)))
	theme.set_stylebox(&"panel", &"ShopCard", _box(look.card, radius + 2, "", 0, Vector4(10, 10, 10, 10)))
	theme.set_stylebox(&"panel", &"MapPopup", _box(look.popup, radius, look.popup_border, int(look.popup_border_w), Vector4(14, 10, 14, 12)))
	theme.set_stylebox(&"panel", &"TooltipPanel", _box(look.popup, mini(radius, 6), look.popup_border, 1, Vector4(8, 5, 8, 5)))
	theme.set_stylebox(&"panel", &"PopupMenu", _box(look.popup, mini(radius, 8), look.popup_border, 1, Vector4(6, 6, 6, 6)))
	theme.set_stylebox(&"hover", &"PopupMenu", _box(look.hover, mini(int(look.button_radius), 6), "", 0, Vector4(4, 2, 4, 2)))
	theme.set_stylebox(&"panel", &"TabContainer", _box(look.card, radius, "", 0, Vector4(10, 10, 10, 10)))
	var text := Color(look.text)
	var text_disabled := Color(str(look.get("text_disabled", ""))) if look.has("text_disabled") else Color(text, 0.4)
	for kind: StringName in [&"Button", &"OptionButton", &"MenuButton"]:
		theme.set_stylebox(&"normal", kind, _button_box(look, look.button, look.edge))
		theme.set_stylebox(&"hover", kind, _button_box(look, look.hover, look.accent if int(look.edge_w) > 0 else look.edge))
		theme.set_stylebox(&"pressed", kind, _button_box(look, look.pressed, look.accent, true))
		theme.set_stylebox(&"disabled", kind, _button_box(look, look.disabled, look.disabled))
		var focus := StyleBoxFlat.new()
		focus.draw_center = false
		focus.set_border_width_all(2)
		focus.border_color = Color(look.accent)
		focus.set_corner_radius_all(int(look.button_radius))
		theme.set_stylebox(&"focus", kind, focus)
		theme.set_color(&"font_color", kind, text)
		theme.set_color(&"font_hover_color", kind, text)
		theme.set_color(&"font_pressed_color", kind, text)
		theme.set_color(&"font_focus_color", kind, text)
		theme.set_color(&"font_hover_pressed_color", kind, text)
		theme.set_color(&"font_disabled_color", kind, text_disabled)
	# Tiles (the ship tiles: a whole card that's a button) in the panels'
	# colours, not the buttons': a shade lighter than a card, its edge the
	# popups', the accent when hovered or pressed.
	var tile := Color(look.card).lightened(0.06)
	theme.set_type_variation(&"TileButton", &"Button")
	theme.set_stylebox(&"normal", &"TileButton", _box(tile.to_html(), int(look.radius), look.popup_border, 1, Vector4(8, 6, 8, 6)))
	theme.set_stylebox(&"hover", &"TileButton", _box(tile.lightened(0.06).to_html(), int(look.radius), look.accent, 1, Vector4(8, 6, 8, 6)))
	theme.set_stylebox(&"pressed", &"TileButton", _box(tile.darkened(0.1).to_html(), int(look.radius), look.accent, 2, Vector4(8, 6, 8, 6)))
	theme.set_stylebox(&"disabled", &"TileButton", _box(tile.to_html(), int(look.radius), "", 0, Vector4(8, 6, 8, 6)))
	theme.set_stylebox(&"focus", &"TileButton", StyleBoxEmpty.new())
	var page_text := Color(1, 1, 1, 0.95)
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		theme.set_color(state, &"TileButton", page_text)
	# Flat buttons (text links, the X on pages) keep the page's text colour.
	# Tabs: the chosen one in the card's colour with the accent along its top.
	var chosen := _box(look.card, int(look.button_radius), look.accent, 0, Vector4(12, 6, 12, 6))
	chosen.border_width_top = 3
	chosen.corner_radius_bottom_left = 0
	chosen.corner_radius_bottom_right = 0
	theme.set_stylebox(&"tab_selected", &"TabBar", chosen)
	theme.set_stylebox(&"tab_selected", &"TabContainer", chosen)
	var other := _box(look.bar, int(look.button_radius), "", 0, Vector4(12, 6, 12, 6))
	other.corner_radius_bottom_left = 0
	other.corner_radius_bottom_right = 0
	theme.set_stylebox(&"tab_unselected", &"TabBar", other)
	theme.set_stylebox(&"tab_unselected", &"TabContainer", other)
	var over := other.duplicate() as StyleBoxFlat
	over.bg_color = Color(look.hover) if not look.has("text_disabled") else Color(look.card).lightened(0.08)
	theme.set_stylebox(&"tab_hovered", &"TabBar", over)
	theme.set_stylebox(&"tab_hovered", &"TabContainer", over)
	var field := _box(look.bar, mini(int(look.button_radius), 6), look.edge, 1, Vector4(8, 4, 8, 4))
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


## A button's box in a state: its fill, its edge, and a raised theme's thicker
## bottom edge (pressed down, it loses it and the text drops with it).
static func _button_box(look: Dictionary, fill: String, edge: String, pressed := false) -> StyleBoxFlat:
	var box := _box(fill, int(look.button_radius), edge, int(look.edge_w), Vector4(12, 5, 12, 5))
	var raise := int(look.raise)
	if raise > 0:
		box.border_color = Color(look.edge)
		box.border_width_bottom = int(look.edge_w) + (0 if pressed else raise)
		box.content_margin_top = 5.0 + (raise if pressed else 0)
		box.content_margin_bottom = 5.0
	return box


static func _apply_fonts(theme: Theme, pair: Dictionary) -> void:
	var heading := _font(pair.heading)
	var body := _font(pair.body)
	theme.default_font = body
	theme.default_font_size = roundi(BODY_SIZE * float(pair.body_scale))
	for type: String in HEADING_TYPES:
		theme.set_font(&"font", StringName(type), heading)
		theme.set_font_size(&"font_size", StringName(type), roundi(int(HEADING_TYPES[type]) * float(pair.heading_scale)))
	# Rich text (the field guide, licences...) in the body font, bold in the headings'.
	theme.set_font(&"normal_font", &"RichTextLabel", body)
	theme.set_font(&"bold_font", &"RichTextLabel", heading)


## A font file at a weight (a variable font set to it), the engine's own font
## behind it for any character it lacks (stars, ticks, arrows).
static func _font(spec: Array) -> Font:
	var key := str(spec)
	if _fonts.has(key):
		return _fonts[key]
	var file: FontFile = load("res://fonts/" + str(spec[0]))
	var fallback := ThemeDB.fallback_font
	if fallback != null and not file.fallbacks.has(fallback):
		file.fallbacks = [fallback]
	var font: Font = file
	if int(spec[1]) > 0:
		var variation := FontVariation.new()
		variation.base_font = file
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): int(spec[1])}
		font = variation
	_fonts[key] = font
	return font
