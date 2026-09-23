class_name ShipPopup
extends AnchoredPopup
## A ship's stats, live status, bars and route, with the refuel/repair toggles,
## Assign Route and Pause/Go.

## Set before adding to the tree.
var ship: Ship


func _ready() -> void:
	super()
	var model := ship.model()
	%NameLabel.text = ship.name
	%ModelValue.text = model.get("name", ship.model_id)
	%RangeValue.text = "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))
	%CapacityValue.text = "%s containers" % Fmt.thousands(ship.capacity())
	%BarsSlot.add_child(ShipBars.new(ship))
	%CloseButton.pressed.connect(queue_free)
	%AssignButton.pressed.connect(func() -> void: GameRoot.find(self).open_route_screen(ship))
	%PauseButton.pressed.connect(func() -> void: GameState.set_paused(ship, not ship.paused))
	%RepairToggle.toggled.connect(func(on: bool) -> void: GameState.set_auto_repair(ship, on))
	%RefuelToggle.toggled.connect(func(on: bool) -> void: GameState.set_auto_refuel(ship, on))
	GameState.ship_changed.connect(_on_ship_changed)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	_update_live()


func _on_ship_changed(changed: Ship) -> void:
	if changed == ship:
		_refresh()


func _update_live() -> void:
	%StatusLabel.text = ship.status_text()
	%SpeedValue.text = "%s nm/s (top %s)" % [Fmt.decimal(ship.speed(), 2), Fmt.decimal(ship.top_speed(), 2)]
	var spent := roundi(ship.stop_fuel_cost + ship.stop_repair_cost)
	var show_cost := ship.is_docked() and spent > 0
	if %CostLabel.visible != show_cost:
		%CostLabel.visible = show_cost
		reset_size.call_deferred()
	%CostLabel.text = "This stop: fuel %s, repair %s" % [
		Fmt.money(roundi(ship.stop_fuel_cost)), Fmt.money(roundi(ship.stop_repair_cost))]


func _refresh() -> void:
	_update_live()
	%RepairToggle.set_pressed_no_signal(ship.auto_repair)
	%RefuelToggle.set_pressed_no_signal(ship.auto_refuel)
	if ship.has_route():
		%RouteLabel.text = "Route: %s (loops)" % GameData.route_text(ship.route)
	else:
		%RouteLabel.text = "No route assigned."
	%PendingLabel.visible = not ship.pending_route.is_empty()
	%PendingLabel.text = "After this leg: %s" % GameData.route_text(ship.pending_route)
	%PauseButton.disabled = not ship.has_route()
	%PauseButton.text = "Go" if ship.paused else "Pause"
	reset_size.call_deferred()
