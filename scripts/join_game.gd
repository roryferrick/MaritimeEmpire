extends Control
## Joining a friend's multiplayer game: the games hosted on this network (each
## with its host's company, players and a lock if it has a password), or one
## at an address; then a password if it needs one; then picking a company:
## taking back one of the game's companies no one is playing, or founding a
## new one at a home port no company has. Once the host lets you in, the game
## opens (see Net).

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const WIDTH := 640.0
const SWATCH_SIZE := Vector2(34, 26)

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
## The game a password is being asked for: [address, port].
var _asking := []
## Picking a company (see _show_choice()).
var _color := "red"
var _port_picker := OptionButton.new()
var _company_name := LineEdit.new()


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.2, 0.36)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_page.custom_minimum_size.x = WIDTH
	_page.add_theme_constant_override(&"separation", 12)
	center.add_child(_page)
	_password_dialog.title = "Password"
	_password_dialog.ok_button_text = "Join"
	_password_edit.secret = true
	_password_edit.placeholder_text = "This game's password"
	_password_dialog.add_child(_password_edit)
	_password_dialog.register_text_enter(_password_edit)
	_password_dialog.confirmed.connect(func() -> void: _join(_asking[0], _asking[1], _password_edit.text))
	add_child(_password_dialog)
	Net.games_changed.connect(_show_games)
	Net.join_status.connect(func(text: String) -> void: _status.text = text)
	Net.join_failed.connect(_on_failed)
	Net.join_choose.connect(_show_choice)
	Net.joined.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	Net.start_browsing()
	_show_find()


func _exit_tree() -> void:
	Net.stop_browsing()


func _clear() -> void:
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
	_name_edit.placeholder_text = "What friends see you as"
	_name_edit.max_length = GameState.MAX_COMPANY_NAME_LENGTH
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(text: String) -> void: player_name = text)
	name_row.add_child(_name_edit)
	_page.add_child(name_row)
	_page.add_child(_dim("Games on your network:"))
	_page.add_child(_games)
	_show_games()
	_page.add_child(_dim("Or join by address (your friend's IP address; over the internet they'll need to forward port %d):" % Net.PORT))
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
			_join(last_address, int(_port_edit.text) if _port_edit.text.is_valid_int() else Net.PORT, ""))
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


## A row per game found: "Rory's Empire · Host Co · 2/4 players · Password"
## and Join (asking for the password first if it has one).
func _show_games() -> void:
	if not is_instance_valid(_games) or not _games.is_inside_tree():
		return
	for child in _games.get_children():
		_games.remove_child(child)
		child.queue_free()
	if Net.games.is_empty():
		_games.add_child(_dim("  Looking for games... (your friend hosts one from Multiplayer)"))
		return
	for key: String in Net.games:
		var game: Dictionary = Net.games[key]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s  ·  %s  ·  %d/%d players%s" % [game.name, game.company, int(game.players), int(game.max_players),
			"  ·  Password" if game.locked else ""]
		row.add_child(label)
		var join := Button.new()
		join.text = "Join"
		join.disabled = int(game.players) >= int(game.max_players)
		join.pressed.connect(func() -> void:
			if game.locked:
				_asking = [game.address, int(game.port)]
				_password_edit.text = ""
				_password_dialog.popup_centered(Vector2i(320, 100))
				_password_edit.grab_focus()
			else:
				_join(game.address, int(game.port), ""))
		row.add_child(join)
		_games.add_child(row)


func _join(address: String, port: int, password: String) -> void:
	var who := _name_edit.text.strip_edges()
	if who.is_empty():
		_status.text = "Enter your name first."
		return
	var error := Net.join(address, port, password, who)
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
	grid.add_child(_dim("Home port", false))
	_port_picker.clear()
	var taken: Array = info.get("taken_ports", [])
	for port in GameData.ports_by_name():
		if not taken.has(port.id):
			_port_picker.add_item("%s, %s" % [port.name, port.get("country", "")])
			_port_picker.set_item_metadata(_port_picker.item_count - 1, port.id)
	# Start on the first recommended start no one has (see data/starts.json).
	for entry: Dictionary in GameData.starts.get("great", []):
		var at := _find_port(entry.port)
		if at >= 0:
			_port_picker.select(at)
			break
	_port_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_port_picker)
	grid.add_child(_dim("Color", false))
	grid.add_child(_swatches())
	_page.add_child(grid)
	var found := Button.new()
	found.text = "Found Company and Join"
	found.custom_minimum_size = Vector2(280, 44)
	found.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	found.pressed.connect(func() -> void:
		Net.choose_company({name = _company_name.text.strip_edges(), color = _color,
			home_port = str(_port_picker.get_item_metadata(_port_picker.selected))}))
	_page.add_child(found)
	_status.text = note if note != "Pick your company." else ""
	_page.add_child(_status)
	_page.add_child(_back_button())


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
		swatch.pressed.connect(func() -> void: _color = entry[0])
		row.add_child(swatch)
	return row


## Where a port is in the home port picker, or -1 if it isn't there (taken).
func _find_port(port_id: String) -> int:
	for i in _port_picker.item_count:
		if _port_picker.get_item_metadata(i) == port_id:
			return i
	return -1
