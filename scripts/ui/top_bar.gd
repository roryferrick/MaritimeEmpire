# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends PanelContainer
## Above the main screens: the company's value (with its trend) and money on the left;
## the company name (in the company's color) over the calendar date and time
## in the middle; the game speed buttons on the right (Pause, 1x, 2x, 4x, 8x; F
## steps through them). Clicking the value or the money opens the Finances screen.

const SPEED_BUTTON_WIDTH := 64.0
## The company's logo before its name (px).
const LOGO_SIZE := 22.0
## How often the company value is worked out again (s), and how far back its
## trend arrow looks (s of play).
const VALUE_REFRESH_S := 2.0
const TREND_BACK_S := 300.0

## Multiplayer: who's playing (see _update_players()).
var _players := Label.new()
## The company value lately: [[play time, value]...], oldest first.
var _values: Array = []
var _value_clock := 0.0


func _ready() -> void:
	# The company's name, the clock, its value and the money in the headings' font (Cinzel: see ui/theme.tres), a size up for its small capitals.
	var heading_font := get_theme_font(&"font", &"HeaderLabel")
	%CompanyLabel.add_theme_font_override(&"font", heading_font)
	%CompanyLabel.add_theme_font_size_override(&"font_size", 17)
	%DateLabel.add_theme_font_override(&"font", heading_font)
	%DateLabel.add_theme_font_size_override(&"font_size", 14)
	for label: Label in [%ValueLabel, %MoneyLabel]:  # (The value and the money too.)
		label.add_theme_font_override(&"font", heading_font)
	%CompanyLabel.text = GameState.company_name
	GameState.apply_company_text_color(%CompanyLabel)
	_add_logo()
	GameState.money_changed.connect(_on_money_changed)
	for label: Label in [%ValueLabel, %MoneyLabel]:
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.gui_input.connect(_on_money_input)
	%MoneyLabel.tooltip_text = "Open Finances"
	_on_money_changed(GameState.money)
	_update_value()
	_add_speed_buttons()
	GameState.time_speed_changed.connect(_on_time_speed_changed)
	_on_time_speed_changed(GameState.time_speed)
	# Multiplayer: who's playing, beside the speeds (which only the host sets).
	_players.theme_type_variation = &"DimLabel"
	_players.mouse_filter = Control.MOUSE_FILTER_STOP
	%SpeedButtons.add_sibling(_players)
	%SpeedButtons.get_parent().move_child(_players, %SpeedButtons.get_index())
	Net.players_changed.connect(_update_players)
	_update_players()
	_players.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_players.gui_input.connect(_on_players_input)


## F cycles the game speed (not while typing: text fields take the key first).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F:
		GameState.cycle_time_speed()
		get_viewport().set_input_as_handled()


func _on_money_changed(money: int) -> void:
	%MoneyLabel.text = Fmt.money(money)
	# In debt (crew wages can do it: see GameState.in_debt()): in red, saying so.
	if money < 0:
		%MoneyLabel.add_theme_color_override(&"font_color", Color(0.95, 0.35, 0.3))
		%MoneyLabel.tooltip_text = "In debt: your ships run on credit, but nothing can be bought until you're back above $0. Open Finances"
	else:
		%MoneyLabel.remove_theme_color_override(&"font_color")
		%MoneyLabel.tooltip_text = "Open Finances"


func _process(delta: float) -> void:
	%DateLabel.text = Fmt.calendar(GameState.calendar_time())
	_value_clock += delta
	if _value_clock >= VALUE_REFRESH_S:
		_value_clock = 0.0
		_update_value()


## One button per game speed this save allows (Pause, 1x, 2x, 4x, 8x, up to
## GameState.max_time_speed); the current one is shown pressed.
func _add_speed_buttons() -> void:
	var group := ButtonGroup.new()
	for speed in GameState.allowed_time_speeds():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(SPEED_BUTTON_WIDTH, 0)
		button.text = "Pause" if speed == 0 else "%dx" % speed
		button.tooltip_text = ("Pause the game" if speed == 0 else "Run the game at %dx speed" % speed) + " (F steps through the speeds; Space pauses and carries on)."
		button.pressed.connect(func() -> void: GameState.time_speed = speed)
		%SpeedButtons.add_child(button)


## "Hosting · 3 players" or "Joined on Steam · 3 players" (the tooltip names
## them); hidden in single player. A joined player's speed buttons only show
## the host's speed.
func _update_players() -> void:
	_players.visible = Net.is_online()
	var names := PackedStringArray()
	for id: int in Net.players:
		var who: Dictionary = Net.players[id]
		names.append("%s%s" % [who.name, " (host)" if id == 1 else ""])
	var count := "%d player%s" % [Net.players.size(), "" if Net.players.size() == 1 else "s"]
	_players.text = "%s%s · %s" % ["Hosting" if Net.is_host() else "Joined", " on Steam" if Net.is_on_steam() else "", count]
	_players.tooltip_text = "Playing: %s" % ", ".join(names)
	for button: Button in %SpeedButtons.get_children():
		button.disabled = Net.is_client()
		if Net.is_client():
			button.tooltip_text = "Only the host sets the game speed."


func _on_time_speed_changed(speed: int) -> void:
	var speeds := GameState.allowed_time_speeds()
	for i in speeds.size():
		(%SpeedButtons.get_child(i) as Button).set_pressed_no_signal(speeds[i] == speed)



## "Worth $12.4M ▲": the company's value (GameState.company_value()), with an
## arrow when it's up or down more than 1% on TREND_BACK_S ago.
func _update_value() -> void:
	var value := GameState.company_value()
	var now := GameState.play_time
	if _values.is_empty() or now - float(_values[-1][0]) >= VALUE_REFRESH_S * 5.0 or now < float(_values[-1][0]):
		if not _values.is_empty() and now < float(_values[-1][0]):
			_values.clear()  # (Another game loaded.)
		_values.append([now, value])
	while _values.size() > 1 and now - float(_values[1][0]) >= TREND_BACK_S:
		_values.pop_front()
	var was := float(_values[0][1])
	var arrow := ""
	if now - float(_values[0][0]) >= TREND_BACK_S * 0.5 and absf(was) > 1.0:
		var change := (value - was) / absf(was)
		arrow = " ▲" if change > 0.01 else (" ▼" if change < -0.01 else "")
	%ValueLabel.text = "Worth %s%s" % [Fmt.money_short(roundi(value)), arrow]
	%ValueLabel.tooltip_text = "Company value: money less loans, plus what your ships would sell for and what your hubs cost.
Open Finances"


func _on_money_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		GameRoot.find(self).show_screen(GameRoot.Screen.FINANCES)


## Clicking the players opens who's playing (each company, the host marked),
## Invite Friends for a host on Steam, and Leave Game: the host saves and
## stops hosting; a joined player leaves
## (their company carries on in the host's game). Both go back to the title.
func _on_players_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if not click or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var lines := PackedStringArray()
	for id: int in Net.players:
		var who: Dictionary = Net.players[id]
		lines.append("%s%s" % [who.name, "  (host)" if id == 1 else ""])
	var dialog := ConfirmationDialog.new()
	dialog.title = "Players"
	dialog.dialog_text = "\n".join(lines) + ("\n\nLeaving saves the game and ends it for everyone." if Net.is_host() else "\n\nYour company carries on in the host's game; join again to take it back.")
	dialog.ok_button_text = "Leave Game"
	dialog.cancel_button_text = "Close"
	if Net.is_host() and Net.is_on_steam():  # Steam's overlay, to invite friends.
		dialog.add_button("Invite Friends", false, "invite")
		dialog.custom_action.connect(func(_action: StringName) -> void:
			var problem := Net.invite_friends()
			if not problem.is_empty():
				dialog.dialog_text = "\n".join(lines) + "\n\n" + problem)
	dialog.confirmed.connect(func() -> void:
		if Net.is_host():
			GameState.save_game()
		Net.leave()
		GameState.in_session = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


## The company's logo before its name (CompanyLogo), the two centred together.
func _add_logo() -> void:
	var label: Label = %CompanyLabel
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 8)
	var parent := label.get_parent()
	var index := label.get_index()
	parent.remove_child(label)
	parent.add_child(row)
	parent.move_child(row, index)
	var logo := CompanyLogo.of(GameState.company)
	logo.custom_minimum_size = Vector2.ONE * LOGO_SIZE
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(logo)
	row.add_child(label)
	GameState.logo_changed.connect(func() -> void:
		logo.logo = GameState.company.logo
		logo.queue_redraw())
