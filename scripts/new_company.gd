# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name NewCompany
extends Control
## New game setup: name the company, pick the home port new ships are delivered
## to on the globe (only the recommended starts from data/starts.json,
## excellent, great, fair and hard, and the Great Lakes ports, colored by kind,
## the excellent ones shining; the Great Lakes come with a warning), choose the
## company's color, its fastest game speed, its storms (none, moderate or
## harsh), how many AI rivals (and how well they play: see RivalAI), and
## whether to have seasonal closures and the tutorial; then make
## the CEO: their name and looks (Characters), part by part or at random.
## Before all that, the company type (CompanyTypeCards: game_config
## company_types), which sets the ships it starts with.

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
## How many AI rivals the game starts with, and how well they play (see RivalAI).
var _rivals := 0
var _rival_level := "normal"
## The CEO's page (see _add_ceo_page()).
var _ceo_page := CeoEditor.new()
## The company type (the first page: see _add_type_page()).
var _company_type := "cargo"
var _type_page := Control.new()
var _type_label := Label.new()


func _ready() -> void:
	%NameEdit.max_length = GameState.MAX_COMPANY_NAME_LENGTH
	_add_ports()
	_add_color_swatches()
	_add_speed_choices()
	_add_storm_choices()
	_add_rival_choices()
	%NameEdit.text_changed.connect(_validate.unbind(1))
	%NameEdit.text_submitted.connect(_start.unbind(1))
	%StartButton.pressed.connect(_start)
	%StartButton.text = "Next: Your CEO"
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
	_show_start_note()
	%StartNote.tooltip_text = %StartNote.text


func _selected_port() -> String:
	return _home_port


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
		button.tooltip_text = tips[level] + " Storms act on ships from company level 6."
		button.button_pressed = level == _storms
		button.pressed.connect(func() -> void: _storms = level)
		%StormRow.add_child(button)


## The AI rivals row (under Storms): how many (none to RivalAI.MAX_RIVALS, in a
## drop-down) and how well they play (Easy, Normal or Hard; greyed with none).
func _add_rival_choices() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.text = "AI rivals"
	label.theme_type_variation = &"DimLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = "Computer-run shipping companies that trade, grow and compete with you by the same rules, each in its own color."
	row.add_child(label)
	var count := OptionButton.new()
	count.custom_minimum_size = Vector2(0, 40)
	count.tooltip_text = label.tooltip_text
	count.add_item("None", 0)
	for n in range(1, RivalAI.MAX_RIVALS + 1):
		count.add_item(str(n), n)
	row.add_child(count)
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	var tips := {
		easy = "Easy: slow to act, settles for so-so trades and keeps plenty of money back. Starts at a fair or hard port.",
		normal = "Normal: plays like a decent player. Starts at a great or fair port.",
		hard = "Hard: picks the best trades, expands fast, upgrades eagerly and borrows to grow. Starts at an excellent or great port.",
	}
	for level: String in RivalAI.LEVELS:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0, 40)
		button.text = " %s " % RivalAI.LEVEL_NAMES[level]
		button.tooltip_text = tips[level]
		button.button_pressed = level == _rival_level
		button.disabled = true
		button.pressed.connect(func() -> void: _rival_level = level)
		row.add_child(button)
		buttons.append(button)
	count.item_selected.connect(func(index: int) -> void:
		_rivals = count.get_item_id(index)
		for button in buttons:
			button.disabled = _rivals == 0)
	%StormRow.add_sibling(row)


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


## On to making the CEO (once the company's name will do).
func _start() -> void:
	if not _validate():
		return
	$Row.visible = false
	_ceo_page.visible = true
	_ceo_page.focus_name()


# --- The CEO --------------------------------------------------------------------

## The CEO page (CeoEditor), hidden till Next: Back returns to the company,
## Found Company starts the game.
func _add_ceo_page() -> void:
	_ceo_page.visible = false
	_ceo_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ceo_page.back_pressed.connect(func() -> void:
		_ceo_page.visible = false
		$Row.visible = true)
	_ceo_page.confirmed.connect(_found.unbind(1))
	add_child(_ceo_page)


func _found() -> void:
	if str(_ceo_page.ceo.name).is_empty() or not _validate():
		return
	GameState.new_game(%NameEdit.text, _selected_port(), _color, {
		tutorials = %TutorialToggle.button_pressed,
		max_time_speed = _max_speed,
		storms = _storms,
		rivals = _rivals,
		rival_level = _rival_level,
		seasons = %SeasonsToggle.button_pressed,
		divine = %DivineToggle.button_pressed,
		company_type = _company_type,
		ceo = _ceo_page.ceo.duplicate(true),
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
	content.add_theme_constant_override(&"separation", 16)
	center.add_child(content)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "Choose your company type"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 900
	var every := Progression.type_pick_every()
	note.text = "Your company starts in one trade. Its ships open quickly as you level up: the smallest now, the next at levels 4, 9, 16 and 25. At level %d, and every %d levels after, you branch out into another type of your choice." % [every, every]
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
	_type_label.text = "Company type: %s" % Progression.type_name(type_id)
	_type_label.add_theme_color_override(&"font_color", CompanyTypeIcon.type_color(type_id))
