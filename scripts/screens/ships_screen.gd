extends Control
## Grid of the player's ships, three tiles wide.


func _ready() -> void:
	visibility_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	# Ship tiles are added to ShipGrid once ships exist.
	%EmptyLabel.visible = %ShipGrid.get_child_count() == 0
