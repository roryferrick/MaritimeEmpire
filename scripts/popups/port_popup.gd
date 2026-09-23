class_name PortPopup
extends AnchoredPopup
## Shows a port's name and the player's ships docked there, with their bars.

const SHIP_BARS_WIDTH := 80.0

## Set before adding to the tree.
var port_id := ""


func _ready() -> void:
	super()
	var port := GameData.get_port(port_id)
	%TitleLabel.text = port.get("name", port_id)
	%CloseButton.pressed.connect(queue_free)
	GameState.ships_changed.connect(_refresh_ships)
	GameState.ship_changed.connect(_refresh_ships.unbind(1))
	_refresh_ships()


func _refresh_ships() -> void:
	for child in %ShipList.get_children():
		%ShipList.remove_child(child)
		child.queue_free()
	var count := 0
	for ship in GameState.ships:
		if ship.docked_at != port_id:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var button := Button.new()
		button.text = ship.name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_open_ship.bind(ship))
		row.add_child(button)
		var bars := ShipBars.new(ship, true)
		bars.custom_minimum_size.x = SHIP_BARS_WIDTH
		bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bars)
		%ShipList.add_child(row)
		count += 1
	%NoShipsLabel.visible = count == 0
	reset_size.call_deferred()


func _open_ship(ship: Ship) -> void:
	PopupHost.find(self).show_ship(ship, follow)
