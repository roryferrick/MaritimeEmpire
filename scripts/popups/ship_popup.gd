class_name ShipPopup
extends AnchoredPopup
## A ship's stats, live status, bars and route, with the repair/refuel/rescue
## toggles, Assign Route, Pause/Go and Sell. Lost ships get a Send Recovery
## button; recovery boats have no route controls.

## Selling takes a second click within this many seconds.
const SELL_CONFIRM_SECONDS := 3.0

## Set before adding to the tree.
var ship: Ship

var _sell_confirm_until := 0.0


func _ready() -> void:
	super()
	var model := ship.model()
	%NameLabel.text = ship.name
	%ModelValue.text = model.get("name", ship.model_id)
	if ship.is_recovery():
		%RangeValue.text = "Recovers lost ships"
		var carries: Array = model.get("carries", [])
		var biggest: String = GameData.get_ship_model(carries[-1]).get("name", "") if carries else ""
		%CapacityValue.text = "Carries 1 ship" if carries.is_empty() else "1 ship, up to %s" % biggest
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
	%RescueToggle.toggled.connect(func(on: bool) -> void: GameState.set_auto_recover(ship, on))
	%SellButton.pressed.connect(_on_sell_pressed)
	GameState.ship_sold.connect(func(sold: Ship, _price: int) -> void:
		if sold == ship:
			queue_free())
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
	_update_sell()


func _update_sell() -> void:
	var error := GameState.sell_error(ship)
	%SellButton.disabled = not error.is_empty()
	%SellButton.tooltip_text = error
	if _seconds() < _sell_confirm_until and error.is_empty():
		%SellButton.text = "Sell for %s?" % Fmt.money(ship.sell_price())
	else:
		%SellButton.text = "Sell"


## First click asks for confirmation (showing the price); a second click sells.
func _on_sell_pressed() -> void:
	if _seconds() < _sell_confirm_until:
		GameState.sell_ship(ship)
	else:
		_sell_confirm_until = _seconds() + SELL_CONFIRM_SECONDS
		reset_size.call_deferred()


static func _seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


## A lost ship with no recovery boat on the way can have one sent, if one is free.
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
	%RescueToggle.set_pressed_no_signal(ship.auto_recover)
	%RescueToggle.visible = not ship.is_recovery()
	%AssignButton.visible = not ship.is_recovery()
	%PauseButton.visible = not ship.is_recovery()
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
