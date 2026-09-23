extends PanelContainer
## Company name, money and containers delivered, shown above the main screens.


func _ready() -> void:
	%CompanyLabel.text = GameState.company_name
	GameState.money_changed.connect(_on_money_changed)
	GameState.containers_changed.connect(_on_containers_changed)
	_on_money_changed(GameState.money)
	_on_containers_changed(GameState.containers_delivered)


func _on_money_changed(money: int) -> void:
	%MoneyLabel.text = Fmt.money(money)


func _on_containers_changed(total: int) -> void:
	%ContainersLabel.text = "Containers delivered: %s" % Fmt.thousands(total)
