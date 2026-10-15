# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## Joining a multiplayer game: the games hosted on Steam and on this
## network (each with its host's company, players and a lock if it has a
## password), or one at an address (a Steam invite joins its game straight
## away); then a password if it needs one; then picking a company:
## taking back one of the game's companies no one is playing, or founding a
## new one at a home port no company has, picked on the globe like a new
## game's (the recommended starts and the Great Lakes), then making its CEO
## (CeoEditor) like a new game's. Once the host lets you in, the game
## opens (see Net).

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const WIDTH := 640.0
const SWATCH_SIZE := Vector2(34, 26)
## The globe a new company's home port is picked on.
const MAP_SIZE := Vector2(640, 400)

## The player's name, kept between visits (also their new company's name).
static var player_name := ""
static var last_address := ""

var _page := VBoxContainer.new()
var _status := Label.new()
var _games := VBoxContainer.new()
var _name_edit := LineEdit.new()
var _address_edit := LineEdit.new()
var _port_edit := LineEdit.new()
var _password_dialog := ConfirmationDialog.new()
var _password_edit := LineEdit.new()
## The game a password is being asked for (one of Net.games).
var _asking := {}
## Picking a company (see _show_choice()).
var _color := "red"
## The colors the game's companies have (from the host): greyed out in the picker.
var _taken_colors: Array[String] = []
## The home port picked on the globe, its name and what kind of start it is.
var _home_port := ""
## The new company's type (game_config company_types; see _type_choices()).
var _company_type := "cargo"
## The globe the HQ is picked on, and the ports companies have already.
var _map: MapView = null
var _taken_ports: Array = []
var _port_name := Label.new()
var _start_note := Label.new()
var _company_name := LineEdit.new()
## The CEO's page, after the company's (see _show_ceo_step()); the page's scroll
## it hides meanwhile; and the company it's for.
var _ceo_editor := CeoEditor.new("Found Company and Join")
var _scroll := ScrollContainer.new()
var _ceo_for := {}


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.2, 0.36)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_ceo_editor.visible = false
	_ceo_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ceo_editor.back_pressed.connect(_leave_ceo_step)
	_ceo_editor.confirmed.connect(func(ceo: Dictionary) -> void:
		_leave_ceo_step()
		var choice := _ceo_for.duplicate()
		choice.ceo = ceo.duplicate(true)
		Net.choose_company(choice))
	add_child(_ceo_editor)
	_page.custom_minimum_size.x = WIDTH
	_page.add_theme_constant_override(&"separation", 12)
	center.add_child(_page)
	_password_dialog.title = "Password"
	_password_dialog.ok_button_text = "Join"
	_password_edit.secret = true
	_password_edit.placeholder_text = "This game's password"
	_password_dialog.add_child(_password_edit)
	_password_dialog.register_text_enter(_password_edit)
	_password_dialog.confirmed.connect(func() -> void: _join_game(_asking, _password_edit.text))
	add_child(_password_dialog)
	Net.games_changed.connect(_show_games)
	Net.join_status.connect(func(text: String) -> void: _status.text = text)
	Net.join_failed.connect(_on_failed)
	Net.join_choose.connect(_show_choice)
	Net.joined.connect(func() -> void: LoadingScreen.open_game(get_tree()))
	if player_name.is_empty():
		player_name = Net.steam_name()
	Net.start_browsing()
	_show_find()
	if Net.invited_lobby != 0:  # A Steam invite accepted: join it.
		var lobby := Net.invited_lobby
		Net.invited_lobby = 0
		_join_game({lobby = lobby, locked = false}, "")


func _exit_tree() -> void:
	Net.stop_browsing()
	for node: Node in _kept():
		if node.get_parent() == null:
			node.free()  # (Off every page just now: nothing else frees it.)


## The fields and labels kept from page to page (see _clear()).
func _kept() -> Array[Node]:
	return [_status, _games, _name_edit, _address_edit, _port_edit, _company_name, _port_name, _start_note]


## Empties the page for the next: the kept fields and labels are only taken
## off it (wherever they are on it), the rest freed.
func _clear() -> void:
	for node: Node in _kept():
		if node.get_parent() != null and _page.is_ancestor_of(node):
			node.get_parent().remove_child(node)
	for child in _page.get_children():
		_page.remove_child(child)
		child.queue_free()


func _title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(title)


func _dim(text: String, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"DimLabel"
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## The games on this network, joining by address, and Back.
func _show_find() -> void:
	_clear()
	_title("Join a Game")
	var name_row := HBoxContainer.new()
	name_row.add_child(_dim("Your name", false))
	_name_edit.text = player_name
	_name_edit.placeholder_text = "What other players see you as"
	_name_edit.max_length = GameState.MAX_COMPANY_NAME_LENGTH
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(text: String) -> void: player_name = text)
	name_row.add_child(_name_edit)
	_page.add_child(name_row)
	_page.add_child(_dim("Games on Steam and your network:" if Net.steam != null else "Games on your network:"))
	_page.add_child(_games)
	_show_games()
	if Net.steam == null:
		_page.add_child(_dim(Net.steam_problem))
	_page.add_child(_dim("Or join by address (the host's IP address; over the internet they'll need to forward port %d):" % Net.PORT))
	var address_row := HBoxContainer.new()
	_address_edit.placeholder_text = "e.g. 192.168.1.20"
	_address_edit.text = last_address
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(_address_edit)
	_port_edit.text = str(Net.PORT)
	_port_edit.custom_minimum_size.x = 80
	address_row.add_child(_port_edit)
	var join := Button.new()
	join.text = "Join"
	join.pressed.connect(func() -> void:
		last_address = _address_edit.text.strip_edges()
		if not last_address.is_empty():
			_join_game({address = last_address, port = int(_port_edit.text) if _port_edit.text.is_valid_int() else Net.PORT}, ""))
	address_row.add_child(join)
	_page.add_child(address_row)
	_status.text = ""
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(_status)
	_page.add_child(_back_button())


func _back_button() -> Button:
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(240, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		Net.leave()
		get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	return back


## A row per game found: "Rory's Empire · Host Co · 2/4 players · Password
## · Steam" and Join (asking for the password first if it has one).
func _show_games() -> void:
	if not is_instance_valid(_games) or not _games.is_inside_tree():
		return
	for child in _games.get_children():
		_games.remove_child(child)
		child.queue_free()
	if Net.games.is_empty():
		_games.add_child(_dim("  Looking for games... (anyone can host one from Multiplayer)"))
		return
	for key: String in Net.games:
		var game: Dictionary = Net.games[key]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s  ·  %s  ·  %d/%d players%s%s  ·  %s" % [game.name, game.company, int(game.players), int(game.max_players),
			"  ·  Password" if game.locked else "", "  ·  Filtered" if game.get("filtered", false) else "", "Steam" if game.has("lobby") else "Network"]
		row.add_child(label)
		var join := Button.new()
		join.text = "Join"
		join.disabled = int(game.players) >= int(game.max_players)
		join.pressed.connect(func() -> void:
			if game.locked:
				_asking = game
				_password_edit.text = ""
				_password_dialog.popup_centered(Vector2i(320, 100))
				_password_edit.grab_focus()
			else:
				_join_game(game, ""))
		row.add_child(join)
		_games.add_child(row)


## Joins a game: a Steam lobby ({lobby}) or one at an address ({address, port}).
func _join_game(game: Dictionary, password: String) -> void:
	var who := _name_edit.text.strip_edges()
	if who.is_empty():
		_status.text = "Enter your name first."
		return
	var error := Net.join_lobby(int(game.lobby), password, who) if game.has("lobby") else Net.join(str(game.address), int(game.port), password, who)
	if not error.is_empty():
		_status.text = error


func _on_failed(reason: String) -> void:
	_show_find()
	_status.text = reason


## Picking a company: one of the game's no one's playing, or a new one (name,
## color and a home port no company has).
func _show_choice(info: Dictionary) -> void:
	var note := _status.text
	_clear()
	_title("Join %s" % info.get("name", "the game"))
	_page.add_child(_dim("%s · %s · game speed set by the host" % [
		Weather.LEVEL_NAMES.get(info.get("storms", "none"), "No storms"),
		"Seasonal closures" if info.get("seasons", false) else "No seasonal closures"]))
	_taken_colors.assign(info.get("taken_colors", []))
	if _taken_colors.has(_color):  # (The first free color, if the usual one is some company's.)
		for entry: Array in GameData.config.get("company_colors", []):
			if not _taken_colors.has(str(entry[0])):
				_color = str(entry[0])
				break
	var free: Array = info.get("companies", []).filter(func(entry: Dictionary) -> bool: return not entry.taken)
	if not free.is_empty():
		_page.add_child(_dim("Play one of this game's companies:"))
		for entry: Dictionary in free:
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.text = "%s  ·  level %d  ·  %s  ·  home %s" % [entry.name, int(entry.level), Fmt.money(int(entry.money)), GameData.port_name(entry.home_port)]
			GameState.apply_company_text_color(button, entry.color)
			button.pressed.connect(Net.choose_company.bind({company = int(entry.index)}))
			_page.add_child(button)
	_page.add_child(_dim("Or found a new company:" if not free.is_empty() else "Found your company:"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_child(_dim("Name", false))
	_company_name.text = player_name if _company_name.text.is_empty() else _company_name.text
	_company_name.max_length = GameState.MAX_COMPANY_NAME_LENGTH
	_company_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_company_name)
	grid.add_child(_dim("Color", false))
	grid.add_child(_swatches())
	grid.add_child(_dim("Type", false))
	grid.add_child(_type_choices())
	_page.add_child(grid)
	# The home port (its HQ), picked on the globe like a new game's: the
	# recommended starts and the Great Lakes ports no company has.
	_page.add_child(_dim("Click your HQ's port on the globe (drag to turn it, scroll to zoom):"))
	_taken_ports = info.get("taken_ports", [])
	var choices := NewCompany.start_choices(_taken_ports, _company_type)
	var map := MapView.new()
	_map = map
	map.custom_minimum_size = MAP_SIZE
	_page.add_child(map)
	map.selectable_ports = choices
	map.shining_ports = NewCompany.shining_choices(_company_type)
	map.opens_whole_globe = true
	_home_port = ""
	for port_id: String in choices:  # Start on the best recommended start no one has (they come best first).
		_home_port = port_id
		break
	map.opens_at_port = _home_port
	_port_name.add_theme_font_size_override(&"font_size", 20)
	_page.add_child(_port_name)
	_start_note.theme_type_variation = &"DimLabel"
	_start_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(_start_note)
	var found := Button.new()
	found.text = "Next: Your CEO"
	found.custom_minimum_size = Vector2(280, 44)
	found.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	found.disabled = _home_port.is_empty()
	found.pressed.connect(func() -> void:
		_show_ceo_step({name = _company_name.text.strip_edges(), color = _color, home_port = _home_port, company_type = _company_type}))
	map.port_clicked.connect(func(port_id: String) -> void:
		_pick_port(map, port_id)
		found.disabled = false)
	_pick_port(map, _home_port)
	_page.add_child(found)
	_status.text = note if note != "Pick your company." else ""
	_page.add_child(_status)
	_page.add_child(_back_button())


## On to making the new company's CEO (CeoEditor), in place of the page;
## founding it sends the company and its CEO to the host.
func _show_ceo_step(choice: Dictionary) -> void:
	if str(choice.name).is_empty():
		_status.text = "Give your company a name."
		return
	_ceo_for = choice
	_scroll.visible = false
	_ceo_editor.visible = true
	_ceo_editor.focus_name()


func _leave_ceo_step() -> void:
	_ceo_editor.visible = false
	_scroll.visible = true


func _swatches() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var group := ButtonGroup.new()
	for entry: Array in GameData.config.get("company_colors", []):
		var swatch := Button.new()
		swatch.toggle_mode = true
		swatch.button_group = group
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.tooltip_text = entry[1]
		var color := Color.from_string(entry[2], Color.WHITE)
		for style_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = color
			style.set_corner_radius_all(4)
			var chosen := style_name in [&"pressed", &"hover_pressed"]
			style.set_border_width_all(3 if chosen else 0)
			style.border_color = Color(0.1, 0.12, 0.15) if color.get_luminance() > 0.8 else Color.WHITE
			swatch.add_theme_stylebox_override(style_name, style)
		swatch.button_pressed = entry[0] == _color
		if _taken_colors.has(str(entry[0])):
			swatch.disabled = true
			swatch.tooltip_text = "%s (another company's)" % entry[1]
		swatch.pressed.connect(func() -> void: _color = entry[0])
		row.add_child(swatch)
	return row


## Picks a new company's home port on the globe.
func _pick_port(map: MapView, port_id: String) -> void:
	_home_port = port_id
	map.selected_port = port_id
	if port_id.is_empty():
		_port_name.text = "Every starting port is taken."
		_start_note.text = ""
		return
	var port := GameData.get_port(port_id)
	_port_name.text = "%s, %s" % [port.name, port.get("country", "")]
	_start_note.text = NewCompany.start_note(port_id, _company_type)
	_start_note.add_theme_color_override(&"font_color", NewCompany.start_note_color(port_id, _company_type))


## A button per company type (in its color, its blurb as the tooltip) for the
## new company's type, the chosen one held down.
func _type_choices() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 6)
	var group := ButtonGroup.new()
	for type: Dictionary in Progression.company_types():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = str(type.name)
		button.tooltip_text = str(type.get("blurb", ""))
		button.add_theme_color_override(&"font_color", CompanyTypeIcon.type_color(type.id))
		button.button_pressed = type.id == _company_type
		button.pressed.connect(_pick_type.bind(str(type.id)))
		row.add_child(button)
	return row


## A company type picked: the globe offers its recommended starts, the HQ
## moving to its best free one if the port picked isn't one of them.
func _pick_type(type_id: String) -> void:
	_company_type = type_id
	if _map == null or not is_instance_valid(_map):
		return
	_map.selectable_ports = NewCompany.start_choices(_taken_ports, type_id)
	_map.shining_ports = NewCompany.shining_choices(type_id)
	var port := _home_port
	if not _map.selectable_ports.has(port):
		port = ""
		for port_id: String in _map.selectable_ports:  # (Best first.)
			port = port_id
			break
	_pick_port(_map, port)
