extends PanelContainer
## Company name (in the company's color) and level (with an XP bar), money and containers delivered,
## shown above the main screens. Clicking the level opens (or closes) the
## level popup with XP progress, upcoming unlocks and time estimates.


func _ready() -> void:
	%CompanyLabel.text = GameState.company_name
	%CompanyLabel.add_theme_color_override(&"font_color", GameState.company_color_value())
	GameState.money_changed.connect(_on_money_changed)
	GameState.containers_changed.connect(_on_containers_changed)
	GameState.company_xp_changed.connect(_on_xp_changed)
	for control: Control in [%LevelLabel, %LevelBar]:
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		control.gui_input.connect(_on_level_input)
	_on_money_changed(GameState.money)
	_on_containers_changed(GameState.containers_delivered)
	_on_xp_changed(GameState.company_xp)


func _on_money_changed(money: int) -> void:
	%MoneyLabel.text = Fmt.money(money)


func _on_containers_changed(total: int) -> void:
	%ContainersLabel.text = "Containers delivered: %s" % Fmt.thousands(total)


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
