extends Control
## Grid of the player's ships, three tiles wide.


func _ready() -> void:
	GameState.ships_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for child in %ShipGrid.get_children():
		%ShipGrid.remove_child(child)
		child.queue_free()
	for ship in GameState.ships:
		var tile := ShipTile.new(ship)
		tile.pressed.connect(_open_ship.bind(tile))
		%ShipGrid.add_child(tile)
	%EmptyLabel.visible = GameState.ships.is_empty()


func _open_ship(tile: ShipTile) -> void:
	var follow := func() -> Vector2:
		return tile.get_global_rect().get_center() if is_instance_valid(tile) else Vector2.ZERO
	PopupHost.find(self).show_ship(tile.ship, follow, tile.size.y / 2.0 + 8.0)
