extends PanelContainer
## Above the main screens: the level (with an XP bar) and money on the left;
## the company name (in the company's color) over the calendar date and time
## in the middle; the game speed buttons on the right (Pause, 1x, 2x, 4x, 8x; F
## steps through them). Clicking the money opens the Finances screen; clicking
## the level opens (or closes) the level popup with XP progress, upcoming
## unlocks and time estimates.

const SPEED_BUTTON_WIDTH := 64.0


func _ready() -> void:
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
	%CompanyLabel.mouse_filter = Control.MOUSE_FILTER_STOP  # The hidden gem: no cursor or tooltip.
	%CompanyLabel.gui_input.connect(_on_company_input)
	_on_money_changed(GameState.money)
	_on_xp_changed(GameState.company_xp)
	_add_speed_buttons()
	GameState.time_speed_changed.connect(_on_time_speed_changed)
	_on_time_speed_changed(GameState.time_speed)


## F cycles the game speed (not while typing: text fields take the key first).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F:
		GameState.cycle_time_speed()
		get_viewport().set_input_as_handled()


func _on_money_changed(money: int) -> void:
	%MoneyLabel.text = Fmt.money(money)


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
		button.tooltip_text = ("Pause the game" if speed == 0 else "Run the game at %dx speed" % speed) + " (F steps through the speeds)."
		button.pressed.connect(func() -> void: GameState.time_speed = speed)
		%SpeedButtons.add_child(button)


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


## The hidden gem: clicking the company name opens its popup, until it's claimed.
func _on_company_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if not click or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or GameState.hidden_gem_claimed:
		return
	var host := PopupHost.find(self)
	if is_instance_valid(host.current) and host.current is GemPopup:
		return
	var popup := GemPopup.new()
	popup.follow = func() -> Vector2: return %CompanyLabel.get_global_rect().get_center() + Vector2(0, 30)
	host.open(popup)
