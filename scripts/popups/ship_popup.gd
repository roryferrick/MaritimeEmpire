class_name ShipPopup
extends AnchoredPopup
## A ship's stats, live status and route, with Assign Route and Pause/Go.

## Set before adding to the tree.
var ship: Ship


func _ready() -> void:
	super()
	var model := ship.model()
	%NameLabel.text = ship.name
	%ModelValue.text = model.get("name", ship.model_id)
	%SpeedValue.text = "%s nm/s" % Fmt.thousands(int(model.get("speed_nm_per_s", 0)))
	%RangeValue.text = "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))
	%CapacityValue.text = "%s containers" % Fmt.thousands(ship.capacity())
	%CloseButton.pressed.connect(queue_free)
	%AssignButton.pressed.connect(func() -> void: GameRoot.find(self).open_route_screen(ship))
	%PauseButton.pressed.connect(func() -> void: GameState.set_paused(ship, not ship.paused))
	GameState.ship_changed.connect(_on_ship_changed)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	%StatusLabel.text = ship.status_text()


func _on_ship_changed(changed: Ship) -> void:
	if changed == ship:
		_refresh()


func _refresh() -> void:
	%StatusLabel.text = ship.status_text()
	if ship.has_route():
		%RouteLabel.text = "Route: %s (loops)" % GameData.route_text(ship.route)
	else:
		%RouteLabel.text = "No route assigned."
	%PendingLabel.visible = not ship.pending_route.is_empty()
	%PendingLabel.text = "After this leg: %s" % GameData.route_text(ship.pending_route)
	%PauseButton.disabled = not ship.has_route()
	%PauseButton.text = "Go" if ship.paused else "Pause"
	reset_size.call_deferred()
