# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name NewCompany
extends Control
## New game setup: name the company, pick the home port new ships are delivered
## to on the globe (only the recommended starts from data/starts.json,
## excellent, great, fair and hard, and the Great Lakes ports, colored by kind,
## the excellent ones shining; the Great Lakes come with a warning), choose the
## company's color, its fastest game speed, its storms (none, moderate or
## harsh), and whether to have seasonal closures and the tutorial; then make
## the CEO: their name and looks (Characters), part by part or at random.
## Before all that, the company type (CompanyTypeCards: game_config
## company_types), which sets the ships it starts with; after the company, its
## logo (LogoEditor) in its colour with its type's mark.

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const DEFAULT_HOME_PORT := "ROM"
const DEFAULT_COLOR := "purple"
const DEFAULT_STORMS := "moderate"
const SWATCH_SIZE := Vector2(44, 30)
## The starting ports' colors on the map (and their notes'), by kind of start:
## excellent a bright green (shining on the map), great green, fair yellow,
## hard red, the Great Lakes blue.
const START_COLORS := {excellent = Color(0.3, 1.0, 0.45), great = Color(0.3, 0.75, 0.35), fair = Color(1.0, 0.85, 0.25), hard = Color(0.95, 0.35, 0.3), great_lakes = Color(0.45, 0.75, 1.0)}
## What each kind of start is called in its note.
const START_TITLES := {excellent = "Excellent start", great = "Great start", fair = "Fair start", hard = "Hard start", great_lakes = "Great Lakes"}

var _home_port := DEFAULT_HOME_PORT
var _color := DEFAULT_COLOR
var _max_speed: int = GameState.TIME_SPEEDS[-1]
var _storms := DEFAULT_STORMS
## The CEO's page (see _add_ceo_page()).
var _ceo_page := CeoEditor.new()
## The company type (the first page: see _add_type_page()).
var _company_type := "cargo"
var _type_page := Control.new()
var _type_label := Label.new()
## The logo (the page after the company's: see _show_logo_page()).
var _logo := {}
var _logo_page := Control.new()
## The backstory start picked (Backstories): the one at the chosen port, or a custom one.
var _chosen_start := {}
var _custom := false
var _custom_money: int = Backstories.CUSTOM_MONEY[1]
var _start_title := Label.new()
var _start_lines := Label.new()
var _custom_toggle := CheckButton.new()
var _money_picker := OptionButton.new()


func _ready() -> void:
	%NameEdit.max_length = GameState.MAX_COMPANY_NAME_LENGTH
	_add_ports()
	_add_start_box()
	_add_color_swatches()
	_add_speed_choices()
	_add_storm_choices()
	%NameEdit.text_changed.connect(_validate.unbind(1))
	%NameEdit.text_submitted.connect(_start.unbind(1))
	%StartButton.pressed.connect(_start)
	%StartButton.text = "Next: Your Logo"
	_add_ceo_page()
	%BackButton.pressed.connect(_show_type_page)
	_add_type_page()
	_validate()


## The starting ports on the map: the recommended starts (from
## data/starts.json) and the Great Lakes ports, each in its kind's color
## (START_COLORS); every other port is a faint dot that can't be picked.
func _add_ports() -> void:
	var map: MapView = %MapView
	map.selectable_ports = start_choices([], _company_type)
	map.shining_ports = shining_choices(_company_type)
	map.opens_at_port = DEFAULT_HOME_PORT
	map.opens_whole_globe = true
	map.port_clicked.connect(_pick_port)
	_pick_port(DEFAULT_HOME_PORT)


func _pick_port(port_id: String) -> void:
	_home_port = port_id
	%MapView.selected_port = port_id
	var port := GameData.get_port(port_id)
	%PortName.text = "Headquarters: %s, %s" % [port.name, port.get("country", "")]
	_refresh_start()


func _selected_port() -> String:
	return _home_port


## The start at the chosen port (Backstories: its story in the note, what it
## gives below), or the custom start: a money preset and the port's kind of start.
func _add_start_box() -> void:
	%StartNote.max_lines_visible = 6
	%StartNote.custom_minimum_size.y = 96.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	_start_title.add_theme_font_size_override(&"font_size", 15)
	box.add_child(_start_title)
	_start_lines.theme_type_variation = &"DimLabel"
	_start_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_lines.add_theme_font_size_override(&"font_size", 12)
	box.add_child(_start_lines)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	_custom_toggle.text = "Custom start"
	_custom_toggle.tooltip_text = "Your own start instead of the port's story: pick the money, no ships, debt, backers or CEO traits."
	_custom_toggle.toggled.connect(func(on: bool) -> void:
		_custom = on
		_money_picker.visible = on
		_refresh_start())
	row.add_child(_custom_toggle)
	for amount: int in Backstories.CUSTOM_MONEY:
		_money_picker.add_item(Fmt.money(amount))
		_money_picker.set_item_metadata(_money_picker.item_count - 1, amount)
	_money_picker.select(1)
	_money_picker.visible = false
	_money_picker.item_selected.connect(func(index: int) -> void:
		_custom_money = int(_money_picker.get_item_metadata(index))
		_refresh_start())
	row.add_child(_money_picker)
	box.add_child(row)
	%StartNote.add_sibling(box)
	_refresh_start()


## The start for the port and type picked now, shown.
func _refresh_start() -> void:
	if not is_node_ready():
		return
	var port_id := _selected_port()
	if _custom:
		_chosen_start = Backstories.custom(_company_type, port_id, _custom_money)
	else:
		_chosen_start = Backstories.for_type(_company_type).get(port_id, Backstories.custom(_company_type, port_id, _custom_money))
	var kind := start_note(port_id, _company_type)
	_start_title.text = str(_chosen_start.get("name", "Your start"))
	_start_title.add_theme_color_override(&"font_color", start_note_color(port_id, _company_type))
	var story := Backstories.story(_chosen_start, "")
	%StartNote.text = story if not str(_chosen_start.get("archetype", "")).is_empty() else kind
	%StartNote.remove_theme_color_override(&"font_color")
	%StartNote.tooltip_text = "%s

%s" % [story, kind] if not kind.is_empty() else story
	_start_lines.text = " · ".join(Backstories.summary(_chosen_start))
	_start_lines.tooltip_text = kind


## What kind of start the chosen port is, and why.
func _show_start_note() -> void:
	%StartNote.text = start_note(_selected_port(), _company_type)
	%StartNote.add_theme_color_override(&"font_color", start_note_color(_selected_port(), _company_type))


## The ports a company can start at, each in its kind of start's color
## (START_COLORS: MapView.selectable_ports) for a company type, leaving out `taken` ones.
static func start_choices(taken: Array = [], type_id := "cargo") -> Dictionary:
	var choices := {}
	for kind: String in GameData.START_KINDS:
		for entry: Dictionary in GameData.start_list(kind, type_id):
			choices[entry.port] = START_COLORS[kind]
	for port_id: String in GameData.starts.get("great_lakes", {}).get("ports", []):
		choices[port_id] = START_COLORS.great_lakes
	for port_id: Variant in taken:
		choices.erase(port_id)
	return choices


## A company type's excellent starts, which shine on the map (MapView.shining_ports).
static func shining_choices(type_id := "cargo") -> Dictionary:
	var shining := {}
	for entry: Dictionary in GameData.start_list("excellent", type_id):
		shining[entry.port] = true
	return shining


## "Great start: ..." (what kind of start a port is, and why), or "".
static func start_note(port_id: String, type_id := "cargo") -> String:
	var info := GameData.start_info(port_id, type_id)
	if info.is_empty():
		return ""
	return "%s: %s" % [START_TITLES.get(info.kind, ""), info.note]


## The color of a port's start note: its kind's, lightened to read on the card.
static func start_note_color(port_id: String, type_id := "cargo") -> Color:
	var kind: String = GameData.start_info(port_id, type_id).get("kind", "")
	return (START_COLORS[kind] as Color).lerp(Color.WHITE, 0.25) if START_COLORS.has(kind) else Color(0.75, 0.78, 0.82)


## One swatch per company color; the chosen one gets a white border (dark on
## the palest colors, so it shows).
func _add_color_swatches() -> void:
	var group := ButtonGroup.new()
	for entry: Array in GameData.config.get("company_colors", []):
		var swatch := Button.new()
		swatch.toggle_mode = true
		swatch.button_group = group
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.tooltip_text = entry[1]
		var color := Color.from_string(entry[2], Color.WHITE)
		for style_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
			swatch.add_theme_stylebox_override(style_name, _swatch_style(color, style_name in [&"pressed", &"hover_pressed"]))
		swatch.button_pressed = entry[0] == DEFAULT_COLOR
		swatch.pressed.connect(func() -> void: _color = entry[0])
		%ColorRow.add_child(swatch)


## A button per game speed (1x, 2x, 4x, 8x) for the fastest this company can
## run at; the fastest is picked to start with.
func _add_speed_choices() -> void:
	var group := ButtonGroup.new()
	for speed in GameState.TIME_SPEEDS:
		if speed == 0:
			continue
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(SWATCH_SIZE.x, 40)
		button.text = "%dx" % speed
		button.tooltip_text = "This company's game speed can go up to %dx." % speed
		button.button_pressed = speed == _max_speed
		button.pressed.connect(func() -> void: _max_speed = speed)
		%SpeedRow.add_child(button)


## A button per storm level (Weather.LEVELS: None, Moderate, Harsh); Moderate
## is picked to start with.
func _add_storm_choices() -> void:
	var group := ButtonGroup.new()
	var tips := {
		none = "No storms at all.",
		moderate = "Storms up to 40% slower and 2x wear at their core; only the strongest hurricane cores close ports.",
		harsh = "Storms up to 60% slower and 3x wear at their core, half as many again, and ports close more often.",
	}
	for level in Weather.LEVELS:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0, 40)
		button.text = " %s " % level.capitalize()
		button.tooltip_text = tips[level]
		button.button_pressed = level == _storms
		button.pressed.connect(func() -> void: _storms = level)
		%StormRow.add_child(button)


static func _swatch_style(color: Color, chosen: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.set_border_width_all(3 if chosen else 0)
	style.border_color = Color(0.1, 0.12, 0.15) if color.get_luminance() > 0.8 else Color.WHITE
	return style


func _validate() -> bool:
	var error := GameState.company_name_error(%NameEdit.text)
	%StartButton.disabled = not error.is_empty()
	return error.is_empty()


## On to the logo (once the company's name will do).
func _start() -> void:
	if not _validate():
		return
	$Row.visible = false
	_show_logo_page()


# --- The CEO --------------------------------------------------------------------

## The CEO page (CeoEditor), hidden till Next: Back returns to the logo,
## Found Company starts the game.
func _add_ceo_page() -> void:
	_ceo_page.visible = false
	_ceo_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ceo_page.back_pressed.connect(func() -> void:
		_ceo_page.visible = false
		_show_logo_page())
	_ceo_page.confirmed.connect(_found.unbind(1))
	add_child(_ceo_page)


func _found() -> void:
	if str(_ceo_page.ceo.name).is_empty() or not _validate():
		return
	GameState.new_game(%NameEdit.text, _selected_port(), _color, {
		tutorials = %TutorialToggle.button_pressed,
		max_time_speed = _max_speed,
		storms = _storms,
		seasons = %SeasonsToggle.button_pressed,
		divine = %DivineToggle.button_pressed,
		company_type = _company_type,
		logo = _logo.duplicate(),
		ceo = _ceo_page.ceo.duplicate(true),
		start = _chosen_start.duplicate(true),
	})
	if GameState.multiplayer_save:
		Net.host_error = Net.host(MainMenu.host_settings)  # Friends can join it; the game says if it couldn't.
	LoadingScreen.open_game(get_tree())


# --- The company type -------------------------------------------------------------

## The first page: the company types as cards (CompanyTypeCards), one picked
## to start with; Next goes on to the headquarters and the rest, whose Back
## returns here (and this page's Back to the main menu). The pick shows on the
## next page's card.
func _add_type_page() -> void:
	_type_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_type_page)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_type_page.add_child(center)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 10)
	center.add_child(content)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override(&"font_size", 40)  # (A size down from the title size, so the cards fit under it.)
	title.text = "Choose your company type"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override(&"font_size", 15)
	note.custom_minimum_size.x = 900
	note.text = "Your company starts in one trade, and every ship of that trade can be bought from the start. Branch out into another trade whenever you like by opening a division (%s)." % Fmt.money(GameState.division_price())
	content.add_child(note)
	var cards := CompanyTypeCards.new()
	cards.selected.connect(_pick_type)
	content.add_child(cards)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 16)
	content.add_child(buttons)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 44)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	buttons.add_child(back)
	var next := Button.new()
	next.text = "Next: Headquarters"
	next.custom_minimum_size = Vector2(220, 44)
	next.pressed.connect(func() -> void:
		_type_page.visible = false
		$Row.visible = true
		%NameEdit.grab_focus())
	buttons.add_child(next)
	_type_label.theme_type_variation = &"DimLabel"
	$Row/Side/Card/Content/Title.add_sibling(_type_label)
	cards.select.call_deferred(_company_type)
	_show_type_page()


func _show_type_page() -> void:
	$Row.visible = false
	_ceo_page.visible = false
	_logo_page.visible = false
	_type_page.visible = true


func _pick_type(type_id: String) -> void:
	_company_type = type_id
	# Its own recommended starts: the HQ moves to its best if the one picked isn't one.
	var map: MapView = %MapView
	map.selectable_ports = start_choices([], type_id)
	map.shining_ports = shining_choices(type_id)
	if not map.selectable_ports.has(_home_port):
		var best: Array = GameData.start_list("excellent", type_id)
		if not best.is_empty():
			_pick_port(str(best[0].port))
			map.focus_port(_home_port)
	_show_start_note()
	_refresh_start()
	_type_label.text = "Company type: %s" % Progression.type_name(type_id)
	_type_label.add_theme_color_override(&"font_color", CompanyTypeIcon.type_color(type_id))


# --- The logo ---------------------------------------------------------------------

## The logo page, between the company and the CEO: the LogoEditor in the
## company's colour with its type's mark (made afresh each time, so a changed
## colour or type shows), Back to the company and Next: Your CEO.
func _show_logo_page() -> void:
	if _logo.is_empty():
		_logo = CompanyLogo.default_logo(_color)
	elif str(_logo.get("secondary", "")) == _color:  # (The company colour changed to the second one.)
		_logo.secondary = CompanyLogo.default_logo(_color).secondary
	for child in _logo_page.get_children():
		_logo_page.remove_child(child)
		child.queue_free()
	if _logo_page.get_parent() == null:
		_logo_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_logo_page)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo_page.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 16)
	card.add_child(content)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "Your company logo"
	content.add_child(title)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 700
	note.text = "Your colour with a second one, round the mark of your company type (%s). It flies at your HQ and hubs, sits beside your name in the company tables and goes on your cruise ships' funnels. You can change it later for %s." % [Progression.type_name(_company_type), Fmt.money(GameState.LOGO_CHANGE_COST)]
	content.add_child(note)
	var editor := LogoEditor.new(_logo, _color, _company_type)
	editor.changed.connect(func(logo: Dictionary) -> void: _logo = logo)
	content.add_child(editor)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(buttons)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 44)
	back.pressed.connect(func() -> void:
		_logo_page.visible = false
		$Row.visible = true)
	buttons.add_child(back)
	var next := Button.new()
	next.text = "Next: Your CEO"
	next.custom_minimum_size = Vector2(220, 44)
	next.pressed.connect(func() -> void:
		_logo_page.visible = false
		_ceo_page.visible = true
		_ceo_page.focus_name())
	buttons.add_child(next)
	_logo_page.visible = true
