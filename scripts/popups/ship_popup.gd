class_name ShipPopup
extends AnchoredPopup
## A ship's stats, live status, bars and route, with the refuel/repair toggles,
## Assign Route and Pause/Go. Lost ships get a Send Recovery button; Mammoths
## have no route controls.

## Set before adding to the tree.
var ship: Ship


func _ready() -> void:
	super()
	var model := ship.model()
	%NameLabel.text = ship.name
	%ModelValue.text = model.get("name", ship.model_id)
	if ship.is_recovery():
		%RangeValue.text = "Recovers lost ships"
		%CapacityValue.text = "Carries 1 ship"
	else:
		%RangeValue.text = "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))
		%CapacityValue.text = "%s containers" % Fmt.thousands(ship.capacity())
	%BarsSlot.add_child(ShipBars.new(ship))
	%CloseButton.pressed.connect(queue_free)
	%AssignButton.pressed.connect(func() -> void: GameRoot.find(self).open_route_screen(ship))
	%PauseButton.pressed.connect(func() -> void: GameState.set_paused(ship, not ship.paused))
	%RecoveryButton.pressed.connect(func() -> void: GameState.send_recovery(ship))
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
	var fuel := roundi(ship.stop_fuel_cost)
	var repair := roundi(ship.stop_repair_cost)
	_set_shown(%CostLabel, ship.is_docked() and (ship.stop_sale > 0 or fuel + repair > 0))
	var costs := "Fuel %s · Repair %s" % [Fmt.money(-fuel), Fmt.money(-repair)]
	if ship.is_recovery():
		%CostLabel.text = "This stop: %s" % costs
	else:
		%CostLabel.text = "This stop: Sold %s · %s\nProfit %s" % [
			Fmt.money(ship.stop_sale), costs, Fmt.money(ship.stop_sale - fuel - repair)]
	_update_recovery()


## A lost ship with no Mammoth on the way can have one sent, if one is free.
func _update_recovery() -> void:
	var needs_rescue := ship.is_lost() and ship.rescuer == null
	_set_shown(%RecoveryButton, needs_rescue)
	_set_shown(%RecoveryLabel, needs_rescue)
	if not needs_rescue:
		return
	var plan := GameState.recovery_plan(ship)
	%RecoveryButton.disabled = plan.has("error")
	if plan.has("error"):
		%RecoveryButton.text = "Send Recovery"
		%RecoveryLabel.text = plan.error
		return
	%RecoveryButton.text = "Send Recovery (about %s)" % Fmt.money(roundi(plan.cost))
	var mammoth: Ship = plan.mammoth
	%RecoveryLabel.text = "%s → %s, about %s" % [
		mammoth.name, GameData.port_name(plan.tow_port), Fmt.duration(plan.seconds)]


func _set_shown(control: Control, shown: bool) -> void:
	if control.visible != shown:
		control.visible = shown
		reset_size.call_deferred()


func _refresh() -> void:
	_update_live()
	%RepairToggle.set_pressed_no_signal(ship.auto_repair)
	%RefuelToggle.set_pressed_no_signal(ship.auto_refuel)
	%Buttons.visible = not ship.is_recovery()
	%RouteLabel.visible = not ship.is_recovery()
	if ship.has_route():
		%RouteLabel.text = "Route: %s (loops)" % GameData.route_text(ship.route)
	else:
		%RouteLabel.text = "No route assigned."
	%PendingLabel.visible = not ship.pending_route.is_empty()
	%PendingLabel.text = "After this leg: %s" % GameData.route_text(ship.pending_route)
	%PauseButton.disabled = not ship.has_route()
	%PauseButton.text = "Go" if ship.paused else "Pause"
	reset_size.call_deferred()
