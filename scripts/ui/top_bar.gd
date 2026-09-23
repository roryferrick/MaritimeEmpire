extends PanelContainer
## Company name and level (with an XP bar), money and containers delivered,
## shown above the main screens.


func _ready() -> void:
	%CompanyLabel.text = GameState.company_name
	GameState.money_changed.connect(_on_money_changed)
	GameState.containers_changed.connect(_on_containers_changed)
	GameState.company_xp_changed.connect(_on_xp_changed)
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
	%LevelBar.tooltip_text = "Max level" if at_max else "%s / %s XP to level %d" % [
		Fmt.thousands(floori(info.xp)), Fmt.thousands(info.cost), info.level + 1]
