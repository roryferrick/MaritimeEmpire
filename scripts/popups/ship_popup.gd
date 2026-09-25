class_name ShipPopup
extends AnchoredPopup
## A ship's stats, live status, bars and route, with the repair, refuel, rescue
## and full-load toggles, Assign Route, Pause/Go, Sell and View on Map. Click the
## name to rename the ship. Lost ships get a Send Recovery button; recovery boats
## have no route controls. Cargo ships show their level, and the Upgrades button
## (red dot while points are unspent) swaps the bars for spending upgrade points
## on the skill paths.

## Selling takes a second click within this many seconds.
const SELL_CONFIRM_SECONDS := 3.0
## Skill paths: [key, name, what each level does ("%d" is the total percent)].
const SKILLS := [
	["speed", "Speed", "+%d%%"],
	["efficiency", "Efficiency", "-%d%% fuel"],
	["durability", "Durability", "-%d%% wear"],
]

## Set before adding to the tree.
var ship: Ship

var _sell_confirm_until := 0.0
var _upgrades_alert := AlertDot.new(4.0, Vector2(6, 6))
## "Carrying 10 containers of Toys, bought for $1,200 at Shanghai, worth about
## $3,500 at Rotterdam".
var _cargo_label := Label.new()


func _ready() -> void:
	super()
	var model := ship.model()
	%NameLabel.text = ship.name
	%ModelValue.text = model.get("name", ship.model_id)
	if ship.is_recovery():
		%RangeValue.text = "Recovers lost ships"
		%CapacityValue.text = GameData.carries_text(model)
	else:
		%RangeValue.text = "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))
		%CapacityValue.text = GameData.cargo_text(model)
		%CapacityValue.tooltip_text = "Carries %s" % GameData.cargo_names(model)
		%CapacityValue.mouse_filter = Control.MOUSE_FILTER_PASS
	_cargo_label.theme_type_variation = &"DimLabel"
	_cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%CostLabel.add_sibling(_cargo_label)
	%BarsSlot.add_child(ShipBars.new(ship))
	%SkillsButton.toggled.connect(_show_skills)
	%SkillsButton.add_child(_upgrades_alert)
	%CloseButton.pressed.connect(queue_free)
	%NameLabel.gui_input.connect(_on_name_input)
	%RenameEdit.text_submitted.connect(_finish_rename.unbind(1))
	%RenameEdit.focus_exited.connect(_finish_rename.bind(true))
	%RenameEdit.gui_input.connect(_on_rename_input)
	%AssignButton.pressed.connect(func() -> void: GameRoot.find(self).open_route_screen(ship))
	%MapButton.pressed.connect(func() -> void: GameRoot.find(self).show_ship_on_map(ship))
	%PauseButton.pressed.connect(func() -> void: GameState.set_paused(ship, not ship.paused))
	%RecoveryButton.pressed.connect(func() -> void: GameState.send_recovery(ship))
	%RepairToggle.toggled.connect(func(on: bool) -> void: GameState.set_auto_repair(ship, on))
	%RefuelToggle.toggled.connect(func(on: bool) -> void: GameState.set_auto_refuel(ship, on))
	%RescueToggle.toggled.connect(func(on: bool) -> void: GameState.set_auto_recover(ship, on))
	%FullToggle.toggled.connect(func(on: bool) -> void: GameState.set_full_loads(ship, on))
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
	var toll := ship.stop_toll
	var has_costs := ship.is_docked() and (ship.stop_sale > 0 or fuel + repair + toll > 0)
	_update_cargo()
	_set_shown(%CostLabel, has_costs and not %SkillsButton.button_pressed)
	var costs := "Fuel %s · Repair %s" % [Fmt.money(-fuel), Fmt.money(-repair)]
	if toll > 0:
		costs += " · Toll %s" % Fmt.money(-toll)
	if ship.is_recovery():
		%CostLabel.text = "This stop: %s" % costs
	else:
		%CostLabel.text = "This stop: Sold %s (cargo cost %s) · %s\nProfit %s" % [Fmt.money(ship.stop_sale),
			Fmt.money(ship.stop_cost), costs, Fmt.money(ship.stop_sale - ship.stop_cost - fuel - repair - toll)]
	_update_recovery()
	_update_sell()
	_update_level_text()


## What's aboard: its cost and what it should sell for where it's going, at
## today's prices; hidden when the hold is empty (the cargo bar says so).
func _update_cargo() -> void:
	_set_shown(_cargo_label, not ship.is_recovery() and not %SkillsButton.button_pressed and not ship.cargo_id.is_empty())
	if ship.cargo_id.is_empty():
		return
	var commodity := GameData.commodity(ship.cargo_id)
	var from := ship.cargo_from
	var to := ship.to_port
	if ship.is_docked():
		to = ship.docked_at if not ship.unloaded else (ship.route[ship.next_route_index()] if ship.has_route() else "")
	var text := "Carrying %s %s of %s, bought for %s at %s" % [Fmt.thousands(ship.cargo_qty), commodity.get("units", "units"),
		commodity.get("name", ship.cargo_id), Fmt.money(ship.cargo_cost), GameData.port_name(from)]
	if not to.is_empty():
		var sale := ship.cargo_qty * GameState.market.sell_price(to, ship.cargo_id)
		var worth: float = sale + GameState.trade_bonus(from, to, sale - ship.cargo_cost, ship.model_id)
		text += ", worth about %s at %s" % [Fmt.money(roundi(worth)), GameData.port_name(to)]
	_cargo_label.text = text


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


## Swaps the bars, toggles and stop summary for the upgrades (skills) panel.
func _show_skills(on: bool) -> void:
	%BarsSlot.visible = not on
	%Toggles.visible = not on
	%SkillsBox.visible = on
	_update_live()
	reset_size.call_deferred()


func _update_level_text() -> void:
	var info := ship.level_info()
	if info.cost > 0:
		%LevelValue.text = "%d · %s / %s XP" % [info.level, Fmt.thousands(floori(info.xp)), Fmt.thousands(ceili(info.cost))]
	else:
		%LevelValue.text = "%d (max)" % info.level


## The Upgrades button's point count and dot, and the skills panel's rows.
func _refresh_level() -> void:
	var points := ship.skill_points()
	%SkillsButton.text = "Upgrades (%d)" % points if points > 0 else "Upgrades"
	_upgrades_alert.visible = points > 0
	for child in %SkillsBox.get_children():
		%SkillsBox.remove_child(child)
		child.queue_free()
	for skill: Array in SKILLS:
		var level := int(ship.skills[skill[0]])
		var name_label := Label.new()
		name_label.text = skill[1]
		%SkillsBox.add_child(name_label)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override(&"separation", 3)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in Progression.skill_max_level():
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(8, 12)
			pip.color = _pip_color(i < level)
			pips.add_child(pip)
		%SkillsBox.add_child(pips)
		var effect := Label.new()
		effect.theme_type_variation = &"DimLabel"
		effect.text = skill[2] % roundi(level * Progression.skill_step(skill[0]) * 100.0)
		%SkillsBox.add_child(effect)
		var add := Button.new()
		add.text = "+"
		add.disabled = not ship.can_level_skill(skill[0])
		add.pressed.connect(GameState.level_skill.bind(ship, skill[0]))
		%SkillsBox.add_child(add)


func _pip_color(filled: bool) -> Color:
	var color_name := &"filled" if filled else &"empty"
	if has_theme_color(color_name, &"SkillPip"):
		return get_theme_color(color_name, &"SkillPip")
	return Color(0.45, 0.9, 0.5) if filled else Color(1, 1, 1, 0.15)


func _set_shown(control: Control, shown: bool) -> void:
	if control.visible != shown:
		control.visible = shown
		reset_size.call_deferred()


func _refresh() -> void:
	%NameLabel.text = ship.name
	_update_live()
	_refresh_level()
	%RepairToggle.set_pressed_no_signal(ship.auto_repair)
	%RefuelToggle.set_pressed_no_signal(ship.auto_refuel)
	%RescueToggle.set_pressed_no_signal(ship.auto_recover)
	%FullToggle.set_pressed_no_signal(ship.full_loads)
	%RescueToggle.visible = not ship.is_recovery()
	%FullToggle.visible = not ship.is_recovery()
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


## Clicking the name swaps it for a text box to rename the ship.
func _on_name_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if not click or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	%RenameEdit.text = ship.name
	%RenameEdit.tooltip_text = "Enter to rename, Esc to cancel."
	%RenameEdit.remove_theme_color_override(&"font_color")
	%NameLabel.visible = false
	%RenameEdit.visible = true
	%RenameEdit.grab_focus()
	%RenameEdit.select_all()


func _on_rename_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE:
		%RenameEdit.accept_event()
		_end_rename()


## Enter renames the ship (or, if the name can't be used, says why in red and
## keeps the box open); clicking away with a bad name just cancels.
func _finish_rename(cancel_on_error := false) -> void:
	if not %RenameEdit.visible:
		return
	var error := GameState.rename_ship(ship, %RenameEdit.text)
	if error.is_empty() or cancel_on_error:
		_end_rename()
		return
	%RenameEdit.tooltip_text = error
	%RenameEdit.add_theme_color_override(&"font_color", Color(1.0, 0.45, 0.4))


func _end_rename() -> void:
	%RenameEdit.visible = false
	%NameLabel.visible = true
	%NameLabel.text = ship.name
