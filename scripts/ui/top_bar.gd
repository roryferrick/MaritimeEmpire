extends PanelContainer
## Money and containers-delivered readout shown above the main screens.


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	GameState.containers_changed.connect(_on_containers_changed)
	_on_money_changed(GameState.money)
	_on_containers_changed(GameState.containers_delivered)


func _on_money_changed(money: int) -> void:
	%MoneyLabel.text = Fmt.money(money)


func _on_containers_changed(total: int) -> void:
	%ContainersLabel.text = "Containers delivered: %s" % Fmt.thousands(total)
