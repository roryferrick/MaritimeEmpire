# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends PanelContainer
## Above the main screens: the level (with an XP bar) and money on the left;
## the company name (in the company's color) over the calendar date and time
## in the middle; the game speed buttons on the right (Pause, 1x, 2x, 4x, 8x; F
## steps through them). Clicking the money opens the Finances screen; clicking
## the level opens (or closes) the level popup with XP progress, upcoming
## unlocks and time estimates.

const SPEED_BUTTON_WIDTH := 64.0

## Multiplayer: who's playing (see _update_players()).
var _players := Label.new()


func _ready() -> void:
	# The company's name, the clock, the level and the money in the headings' font (Cinzel: see ui/theme.tres), a size up for its small capitals.
	var heading_font := get_theme_font(&"font", &"HeaderLabel")
	%CompanyLabel.add_theme_font_override(&"font", heading_font)
	%CompanyLabel.add_theme_font_size_override(&"font_size", 17)
	%DateLabel.add_theme_font_override(&"font", heading_font)
	%DateLabel.add_theme_font_size_override(&"font_size", 14)
	for label: Label in [%LevelLabel, %MoneyLabel]:  # (The level and the money too.)
		label.add_theme_font_override(&"font", heading_font)
	%CompanyLabel.text = GameState.company_name
	GameState.apply_company_text_color(%CompanyLabel)
	GameState.money_changed.connect(_on_money_changed)
	GameState.company_xp_changed.connect(_on_xp_changed)
	for control: Control in [%LevelLabel, %LevelBar]:
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		control.gui_input.connect(_on_level_input)
	%MoneyLabel.mouse_filter = Control.MOUSE_FILTER_STOP
	%MoneyLabel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	%MoneyLabel.tooltip_text = "Open Finances"
	%MoneyLabel.gui_input.connect(_on_money_input)
	_on_money_changed(GameState.money)
	_on_xp_changed(GameState.company_xp)
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


func _process(_delta: float) -> void:
	%DateLabel.text = Fmt.calendar(GameState.calendar_time())


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



func _on_xp_changed(total_xp: float) -> void:
	var info := Progression.company_level(total_xp)
	%LevelLabel.text = "Level %d" % info.level
	var at_max: bool = info.cost <= 0
	%LevelBar.value = 1.0 if at_max else info.xp / float(info.cost)
	%LevelBar.tooltip_text = "Click for details"


func _on_level_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if not click or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var host := PopupHost.find(self)
	if is_instance_valid(host.current) and host.current is LevelPopup:
		host.close()
		return
	var popup := LevelPopup.new()
	popup.follow = func() -> Vector2: return %LevelBar.get_global_rect().get_center() + Vector2(0, 14)
	host.open(popup)


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
