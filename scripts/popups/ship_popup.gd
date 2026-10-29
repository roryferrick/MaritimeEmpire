# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name ShipPopup
extends AnchoredPopup
## A ship's stats, live status, bars and route, with the repair, refuel, rescue
## and full-load toggles, Assign Route, Pause/Go, Sell and Follow on Map (the map keeps it in the middle as it goes; again to stop). Click the
## name to rename the ship. Lost ships get a Send Recovery button; recovery boats
## have no route controls. Under the stats, the captain's picture and name; the
## Crew button swaps the bars for all its officers (captain and mates) and crew.

## Selling takes a second click within this many seconds.
const SELL_CONFIRM_SECONDS := 3.0
const BIRDS_SECONDS := 1.0

## Set before adding to the tree.
var ship: Ship

var _sell_confirm_until := 0.0
## "Carrying 10 containers of Toys, bought for $1,200 at Shanghai, worth about
## $3,500 at Rotterdam".
var _cargo_label := Label.new()
## The Crew button, and the page it swaps the bars for: every officer (the
## captain and mates) with their picture, and the crew.
var _crew_button := Button.new()
var _keep_toggle := CheckButton.new()
var _parts_button := Button.new()
var _parts_box := VBoxContainer.new()
var _crew_box := VBoxContainer.new()
## The gulls round it and the seabirds following it (see Birds), redone every
## BIRDS_SECONDS.
var _birds_label := Label.new()
var _skin_button := Button.new()
var _birds_clock := 0.0


func _ready() -> void:
	super()
	var model := ship.model()
	%NameLabel.text = ship.name
	%ModelValue.text = model.get("name", ship.model_id)
	if ship.is_recovery():
		%RangeValue.text = "Recovers lost ships"
		%CapacityValue.text = GameData.carries_text(model)
	elif ship.is_icebreaker():
		$Content/Stats/RangeName.text = "Job"
		$Content/Stats/CapacityName.text = "Needed"
		%RangeValue.text = "Leads convoys through seasonal ice"
		%CapacityValue.text = "Only needed in winter ice"
	elif ship.is_tug():
		$Content/Stats/RangeName.text = "Reach"
		$Content/Stats/CapacityName.text = "Job"
		%CapacityValue.text = "Tows in ships lost near its port"
	elif ship.is_fishing():
		var gear: Dictionary = model.get("fishing", {})
		%RangeValue.text = "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))
		$Content/Stats/CapacityName.text = "Hold"
		%CapacityValue.text = "%s crates" % Fmt.thousands(ship.capacity())
		%CapacityValue.tooltip_text = "%s, %d crew; %s" % [Fisheries.gear_text(gear), int(gear.get("crew", 0)), Fisheries.trip_text(gear)]
		%CapacityValue.mouse_filter = Control.MOUSE_FILTER_PASS
	elif ship.is_research():
		%RangeValue.text = "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))
		$Content/Stats/CapacityName.text = "Dives to"
		%CapacityValue.text = "%s m · %d gear slots" % [Fmt.thousands(Research.depth_of(model)), Research.slots_of(model)]
	else:
		%RangeValue.text = "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))
		%CapacityValue.text = GameData.cargo_text(model)
		%CapacityValue.tooltip_text = "Carries %s" % GameData.cargo_names(model)
		%CapacityValue.mouse_filter = Control.MOUSE_FILTER_PASS
	_cargo_label.theme_type_variation = &"DimLabel"
	_cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%CostLabel.add_sibling(_cargo_label)
	_birds_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_birds_label.add_theme_color_override(&"font_color", PortPopup.BIRDS_COLOR)
	_cargo_label.add_sibling(_birds_label)
	_update_birds()
	if ship.is_icebreaker():
		%Buttons.add_sibling(_station_picker())
		%Buttons.get_parent().move_child(%Buttons, -1)
	if ship.is_fishing() and GameState.is_mine(ship):
		%Buttons.add_sibling(FishingPanel.new(ship))
		%Buttons.get_parent().move_child(%Buttons, -1)
	%BarsSlot.add_child(ShipBars.new(ship))
	_add_captain()
	_add_parts()
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
	_keep_toggle.text = "Keep on route"
	_keep_toggle.tooltip_text = "A department head may take a ship off its route for a contract that pays better (a card asks you). Ticked, this ship is never proposed."
	_keep_toggle.toggled.connect(func(on: bool) -> void: GameState.set_keep_on_route(ship, on))
	%Toggles.add_child(_keep_toggle)
	%SellButton.pressed.connect(_on_sell_pressed)
	_skin_button.text = "Skin"
	_skin_button.tooltip_text = "Dress this ship in a skin you own, or the base ship."
	_skin_button.pressed.connect(func() -> void: GameRoot.find(self).add_child(SkinPicker.new(ship)))
	%Buttons.add_child(_skin_button)
	if ship.is_cruise() and GameState.owner_of(ship) == GameState.company:  # (Its itinerary, prices, departures, ship and reviews.)
		var planner := Button.new()
		planner.text = "Cruise planner"
		planner.tooltip_text = "Its itinerary, prices, departures, cabins and amenities, and its guests' reviews."
		planner.pressed.connect(func() -> void: GameRoot.find(self).add_child(CruisePlanner.new(ship)))
		%Buttons.add_child(planner)
	if ship.is_research() and GameState.owner_of(ship) == GameState.company:  # (Its expeditions, contracts and gear: see Research.)
		var page := Button.new()
		page.text = "Expeditions"
		page.tooltip_text = "Send it to a site or on a contract, move it, or fit its gear (the Research page)."
		page.pressed.connect(func() -> void:
			queue_free()
			GameRoot.find(self).show_research_ship(ship.id))
		%Buttons.add_child(page)
	%Buttons.move_child(_skin_button, %SellButton.get_index())
	GameState.ship_sold.connect(func(sold: Ship, _price: int) -> void:
		if sold == ship:
			queue_free())
	GameState.ship_changed.connect(_on_ship_changed)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	_update_live()
	_birds_clock += delta
	if _birds_clock >= BIRDS_SECONDS:
		_birds_clock = 0.0
		_update_birds()


## "Following: Herring Gull (3), Wandering Albatross (2)" (BirdLife), or
## hidden when there are none.
func _update_birds() -> void:
	var parts := PackedStringArray()
	var following := Birds.shared().counts_text(BirdLife.shared().following(ship))
	if not following.is_empty():
		parts.append("Following: %s" % following)
		var boosts := BirdBoosts.describe(GameState.bird_boosts(ship))  # What they give the ship (see BirdBoosts).
		if not boosts.is_empty():
			parts.append(boosts)
	_birds_label.text = " · ".join(parts)
	_set_shown(_birds_label, not parts.is_empty() and not _crew_button.button_pressed)


func _on_ship_changed(changed: Ship) -> void:
	if changed == ship:
		_refresh()


func _update_live() -> void:
	%StatusLabel.text = ship.status_text() if GameState.is_mine(ship) else "%s — %s's ship" % [ship.status_text(), GameState.owner_of(ship).name]
	%SpeedValue.text = "%s nm/s (top %s)" % [Fmt.decimal(ship.speed(), 2), Fmt.decimal(ship.top_speed(), 2)]
	if ship.is_tug():
		%RangeValue.text = "%d nm from %s" % [roundi(ship.reach_nm()), GameData.port_name(ship.base_port)]
	var fuel := roundi(ship.stop_fuel_cost)
	var repair := roundi(ship.stop_repair_cost)
	var toll := ship.stop_toll
	var has_costs := ship.is_docked() and (ship.stop_sale > 0 or fuel + repair + toll > 0)
	_update_cargo()
	_set_shown(%CostLabel, has_costs and not _crew_button.button_pressed and GameState.is_mine(ship))
	var costs := "Fuel %s · Repair %s" % [Fmt.money(-fuel), Fmt.money(-repair)]
	if toll > 0:
		costs += " · Toll %s" % Fmt.money(-toll)
	if ship.is_service():
		%CostLabel.text = "This stop: %s" % costs
	else:
		%CostLabel.text = "This stop: Sold %s (cargo cost %s) · %s\nProfit %s" % [Fmt.money(ship.stop_sale),
			Fmt.money(ship.stop_cost), costs, Fmt.money(ship.stop_sale - ship.stop_cost - fuel - repair - toll)]
	_update_recovery()
	_update_sell()


## What's aboard: its cost and what it should sell for where it's going, at
## today's prices; hidden when the hold is empty (the cargo bar says so).
func _update_cargo() -> void:
	var stops := _next_stops()
	var at: String = stops[0]
	var after: String = stops[1]
	_set_shown(_cargo_label, not ship.is_service() and not _crew_button.button_pressed
		and (not ship.cargo_id.is_empty() or not at.is_empty()))
	var lines: Array[String] = []
	var sale_worth := 0.0
	if not ship.cargo_id.is_empty():
		var commodity := GameData.commodity(ship.cargo_id)
		var what := str(commodity.get("name", ship.cargo_id))
		if not ship.cargo_breed.is_empty():  # (A farm's young stock: its breed's worth, see Farms.)
			what = "%s %s (worth x%s)" % [Farms.breed_name(ship.cargo_breed), what.to_lower(), Fmt.decimal(Farms.breed_value(ship.cargo_breed), 1)]
		var source := "from the farm at %s (worth %s there)" % [GameData.port_name(ship.cargo_from), Fmt.money(ship.cargo_cost)] if ship.cargo_farm else "bought for %s at %s" % [Fmt.money(ship.cargo_cost), GameData.port_name(ship.cargo_from)]
		if Energy.is_field_end(ship.cargo_from):  # (From its company's rigs: see Energy.load_at_field().)
			source = "from your rigs at %s" % Energy.field_name(Energy.field_of_end(ship.cargo_from))
		if ship.cargo_cut > 0.0:  # (From its factory: see Manufacturers.load_ship().)
			source = "from your factory at %s (%s takes %d%% of the sale)" % [GameData.port_name(ship.cargo_from), commodity.get("name", ship.cargo_id), roundi(ship.cargo_cut * 100.0)]
		if commodity.get("maker", false):
			what = "%s (%s)" % [what, Manufacturers.describe(ship.cargo_id).to_lower()]
		lines.append("Carrying %s %s of %s, %s." % [Fmt.thousands(ship.cargo_qty), commodity.get("units", "units"), what, source])
		if Farms.loses_a_day(ship.cargo_id) > 0.0:
			lines.append("Fresh: %d%% of its full value now, losing about %s%% a day aboard." % [roundi(ship.cargo_value_factor(GameState.play_time, GameState.days_per_second()) * 100.0),
				Fmt.decimal(Farms.loses_a_day(ship.cargo_id) * (1.0 - float(ship.model().get("keeps_fresh", 0.0))) * 100.0, 1)])
	if ship.is_rig_runner():  # (Rig runs: see Energy.)
		lines.append("On rig runs: out to the rigs at %s, delivering to %s. The Energy page sends or stops it; a new route takes it off them." % [Energy.field_name(ship.rig_field), GameData.port_name(ship.rig_port)])
		_cargo_label.text = "\n".join(lines)
		return
	if at.is_empty():
		_cargo_label.text = "\n".join(lines)
		return
	# At its next stop: what it sells there, then what it buys there for the stop after.
	var plan := "At %s: " % GameData.port_name(at)
	if not ship.cargo_id.is_empty():
		var sale := ship.cargo_qty * GameState.company_sell_price(at, ship.cargo_id, GameState.owner_of(ship)) * ship.cargo_value_factor(GameState.play_time, GameState.days_per_second())
		sale_worth = sale + GameState.trade_bonus(ship.cargo_from, at, sale - ship.cargo_cost, ship.model_id, GameState.owner_of(ship))
		plan += "sells for about %s" % Fmt.money(roundi(sale_worth))
	else:
		plan += "nothing to sell"
	if not after.is_empty() and after != at:
		var buy := _next_load(at, after, sale_worth)
		if buy.is_empty():
			plan += "; nothing there pays to carry on to %s." % GameData.port_name(after)
		else:
			var commodity := GameData.commodity(buy[0])
			plan += "; then buys about %s %s of %s for about %s, for %s." % [Fmt.thousands(buy[1]), commodity.get("units", "units"),
				commodity.get("name", buy[0]), Fmt.money(buy[2]), GameData.port_name(after)]
	else:
		plan += "."
	lines.append(plan)
	_cargo_label.text = "\n".join(lines)


## The ship's next stop on its route (where it sells what it carries and
## loads for the leg after), and the stop after that: [next, after], "" when
## it has no route. In port, the next is here until it has loaded here for the
## leg on (it has a cargo from elsewhere to sell, or is yet to load), then
## where it sails next.
func _next_stops() -> Array:
	if ship.is_service() or (not ship.has_route() and ship.pending_route.is_empty()):
		return ["", ""]
	var at := ship.to_port
	if ship.is_docked():
		var loaded_here := not ship.cargo_id.is_empty() and ship.cargo_from == ship.docked_at
		at = ship.route[ship.next_route_index()] if loaded_here and ship.has_route() else ship.docked_at
	# The route it'll be on from there (a new one takes over when it arrives).
	var route: Array[String] = ship.pending_route if not ship.pending_route.is_empty() and not ship.is_docked() else ship.route
	if at.is_empty() or route.is_empty():
		return [at, ""]
	var here := route.find(at)
	return [at, route[(here + 1) % route.size()] if here >= 0 else route[0]]


## What the ship would load at a port for the next leg, as the game would
## pick it (GameState._load_cargo()): [commodity, quantity, cost], with the
## money it'll have after selling there (less the fuel reserve and the bank
## reserve), or [] if nothing pays.
func _next_load(port_id: String, to: String, sale: float) -> Array:
	var who := GameState.owner_of(ship)
	var best: Array = GameState.market.best_cargo(ship.model(), port_id, to, who)
	if str(best[0]).is_empty():
		return []
	var price := GameState.company_buy_price(port_id, best[0], who)
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(port_id, to, ship.model())) / GameData.hold_of(best[0]))
	var quantity := room
	if not GameState.in_debt(who) and price > 0.0:
		var spare := float(who.money) + sale - GameState.fuel_reserve(who) - who.bank_reserve
		quantity = clampi(floori(spare / price), 0, room)
	if quantity <= 0:
		return []
	return [best[0], quantity, roundi(quantity * price)]


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
	var needs_rescue := ship.is_lost() and ship.rescuer == null and GameState.is_mine(ship)
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
	if plan.has("tugs"):
		var names: Array = plan.tugs.map(func(tug: Ship) -> String: return tug.name)
		%RecoveryLabel.text = "%s → %s, about %s" % [" and ".join(names), GameData.port_name(plan.tow_port), Fmt.duration(plan.seconds)]
		return
	var mammoth: Ship = plan.mammoth
	%RecoveryLabel.text = "%s → %s, about %s" % [mammoth.name,
		("%d nm off %s for its tugs" % [roundi(plan.handoff_nm), GameData.port_name(plan.tow_port)]) if float(plan.get("handoff_nm", 0.0)) > 0.0 else GameData.port_name(plan.tow_port),
		Fmt.duration(plan.seconds)]


func _set_shown(control: Control, shown: bool) -> void:
	if control.visible != shown:
		control.visible = shown
		reset_size.call_deferred()


## An icebreaker's station: "Station: [Gulf of Finland (ice 10 Jan - 31 Mar)]",
## with a note under it of why one couldn't be picked.
func _station_picker() -> VBoxContainer:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	box.add_child(row)
	var label := Label.new()
	label.text = "Station"
	label.theme_type_variation = &"DimLabel"
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = "Icebreakers are only needed in seasonal ice: station one at an ice area and it leads your ships through it in convoys while it's frozen."
	picker.add_item("Not stationed")
	picker.set_item_metadata(0, "")
	var lists := {closure = GameState.seasonal.closures(), zone = GameState.seasonal.ice_zones()}
	for item: Dictionary in GameState.icebreaking.areas():
		var season := ""
		for key: String in lists:
			for entry: Dictionary in lists[key]:
				if entry.id == item.get(key, ""):
					season = " (ice %s - %s)" % [Seasons.date_text(entry.from), Seasons.date_text(entry.to)]
		picker.add_item(item.name + season)
		picker.set_item_metadata(picker.item_count - 1, item.id)
		if item.id == ship.station:
			picker.select(picker.item_count - 1)
	row.add_child(picker)
	var error := Label.new()
	error.theme_type_variation = &"ErrorLabel"
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.visible = false
	box.add_child(error)
	picker.item_selected.connect(func(index: int) -> void:
		var problem := GameState.station_icebreaker(ship, str(picker.get_item_metadata(index)))
		error.text = problem
		error.visible = not problem.is_empty()
		if not problem.is_empty():
			for i in picker.item_count:
				if picker.get_item_metadata(i) == ship.station:
					picker.select(i)
		reset_size.call_deferred())
	return box


func _refresh() -> void:
	%NameLabel.text = ship.name
	var root := GameRoot.find(self)
	%MapButton.text = "Stop Following" if root != null and root.followed_ship() == ship else "Follow on Map"
	_update_live()
	%RepairToggle.set_pressed_no_signal(ship.auto_repair)
	%RefuelToggle.set_pressed_no_signal(ship.auto_refuel)
	%RescueToggle.set_pressed_no_signal(ship.auto_recover)
	%FullToggle.set_pressed_no_signal(ship.full_loads)
	_keep_toggle.set_pressed_no_signal(ship.keep_on_route)
	_keep_toggle.visible = not ship.is_service() and not ship.is_research()
	%RescueToggle.visible = not ship.is_service()
	%FullToggle.visible = not ship.is_service() and not ship.is_research()
	%AssignButton.visible = not ship.is_service() and not ship.is_research()
	%PauseButton.visible = (not ship.is_service() or ship.is_fishing()) and not ship.is_research()
	%RouteLabel.visible = not ship.is_service()
	if ship.is_research():
		%RouteLabel.text = "Research: %s. Gear: %s." % [GameState.research.status_text(ship), ", ".join(PackedStringArray(ship.research_gear.map(func(gear_id: String) -> String: return Research.gear_name(gear_id)))) if not ship.research_gear.is_empty() else "none fitted"]
	elif ship.has_route():
		%RouteLabel.text = "Route: %s (loops)" % GameData.route_text(ship.route)
		# Legs beyond one tank: the refuel stops on the way.
		var stops: Array[String] = []
		for i in ship.route.size():
			for port in GameState.refuel_stops(ship, ship.route[i], ship.route[(i + 1) % ship.route.size()]):
				if not stops.has(port):
					stops.append(port)
		if not stops.is_empty():
			%RouteLabel.text += " — %s on the way" % GameState.refuel_text(stops)
	else:
		%RouteLabel.text = "No route assigned."
	%PendingLabel.visible = not ship.pending_route.is_empty()
	%PendingLabel.text = "After this leg: %s" % GameData.route_text(ship.pending_route)
	%PauseButton.disabled = not ship.has_route() and not ship.is_fishing()
	%PauseButton.text = "Go" if ship.paused else "Pause"
	# Another player's ship (multiplayer): to look at, not to run.
	if not GameState.is_mine(ship):
		for control: Control in [%Toggles, %AssignButton, %PauseButton, %SellButton, _skin_button]:
			control.visible = false
	reset_size.call_deferred()


## Clicking the name swaps it for a text box to rename the ship.
func _on_name_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if not click or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or not GameState.is_mine(ship):
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


# --- Officers --------------------------------------------------------------------

## The captain's picture and name under the stats (and the mates and crew, in
## brief), and the Crew button and its page.
func _add_captain() -> void:
	var crew := GameState.crew_of(ship.model())
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var picture := Portrait.new(CrewLooks.dressed(ship.captain(), ship), true)
	picture.custom_minimum_size = Vector2(44, 44)
	row.add_child(picture)
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override(&"separation", 0)
	var name_label := Label.new()
	name_label.text = "Captain %s" % ship.captain().get("name", "")
	column.add_child(name_label)
	var mates := ship.captains.size() - 1
	var detail := Label.new()
	detail.theme_type_variation = &"DimLabel"
	detail.text = "%s%d crew" % ["%d %s · " % [mates, "mate" if mates == 1 else "mates"] if mates > 0 else "", int(crew[1])]
	column.add_child(detail)
	row.add_child(column)
	$Content/Stats.add_sibling(row)
	_crew_button.text = "Crew"
	_crew_button.toggle_mode = true
	_crew_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_crew_button.tooltip_text = "The ship's captain, mates and crew."
	_crew_button.toggled.connect(_show_crew)
	%CloseButton.add_sibling(_crew_button)
	%CloseButton.get_parent().move_child(_crew_button, %CloseButton.get_index())
	_crew_box.visible = false
	_crew_box.add_theme_constant_override(&"separation", 6)
	%BarsSlot.add_sibling(_crew_box)
	for i in ship.captains.size():
		var officer: Dictionary = ship.captains[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 10)
		var face := Portrait.new(CrewLooks.dressed(officer, ship), true)
		face.custom_minimum_size = Vector2(56, 56)
		line.add_child(face)
		var text := VBoxContainer.new()
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.add_theme_constant_override(&"separation", 0)
		var who := Label.new()
		who.text = str(officer.get("name", ""))
		text.add_child(who)
		var rank := Label.new()
		rank.theme_type_variation = &"DimLabel"
		rank.text = Characters.rank(i) + (" (in command)" if i == 0 and ship.captains.size() > 1 else "")
		text.add_child(rank)
		line.add_child(text)
		_crew_box.add_child(line)
	var settings: Dictionary = GameData.config.get("crew", {})
	var hands := Label.new()
	hands.theme_type_variation = &"DimLabel"
	hands.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hands.text = "And %d crew. Wages %s every %d days it works." % [int(crew[1]), Fmt.money(GameState.crew_wages(ship.model())), int(settings.get("period_days", 14))]
	_crew_box.add_child(hands)
	var uniform := Button.new()  # What they wear on deck (UniformsPage, on this ship's line).
	uniform.text = "Uniform"
	uniform.tooltip_text = "What the captain and crew of your %s wear on deck." % CrewLooks.line_title(CrewLooks.line_of(ship.model())).to_lower()
	uniform.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	uniform.pressed.connect(func() -> void: get_tree().root.add_child(UniformsPage.new(CrewLooks.line_of(ship.model()))))
	_crew_box.add_child(uniform)


## The Parts view (ShipParts): each part's condition by group, the upgrades fitted, and the Drydock button.
func _add_parts() -> void:
	_parts_button.text = "Parts"
	_parts_button.toggle_mode = true
	_parts_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_parts_button.tooltip_text = "The ship's parts and their condition; drydock for the major ones and upgrades."
	_parts_button.toggled.connect(_show_parts)
	%CloseButton.add_sibling(_parts_button)
	%CloseButton.get_parent().move_child(_parts_button, %CloseButton.get_index())
	_parts_box.visible = false
	_parts_box.add_theme_constant_override(&"separation", 4)
	%BarsSlot.add_sibling(_parts_box)


func _fill_parts() -> void:
	for child in _parts_box.get_children():
		_parts_box.remove_child(child)
		child.queue_free()
	ShipParts.flush(ship)
	var list := ShipParts.for_model(ship.model())
	var groups := {}
	for each: Dictionary in list:
		(groups.get_or_add(str(each.group), []) as Array).append(each)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 1)
	for group: String in ["hull", "propulsion", "engine", "electrics", "deck", "systems"]:
		if not groups.has(group):
			continue
		var head := Label.new()
		head.text = ShipParts.group_name(group)
		head.theme_type_variation = &"DimLabel"
		grid.add_child(head)
		grid.add_child(Control.new())
		grid.add_child(Control.new())
		for each: Dictionary in groups[group]:
			var name := Label.new()
			name.text = "  " + str(each.name) + ("*" if bool(each.get("major", false)) else "")
			name.add_theme_font_size_override(&"font_size", 13)
			grid.add_child(name)
			var bar := ProgressBar.new()
			var condition := float(ship.parts.get(each.id, 1.0))
			bar.min_value = 0.0
			bar.max_value = 1.0
			bar.value = condition
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(110.0, 10.0)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.modulate = Color(0.6, 0.9, 0.6) if condition > 0.6 else (Color(0.95, 0.8, 0.4) if condition > 0.3 else Color(0.95, 0.5, 0.45))
			grid.add_child(bar)
			var note := Label.new()
			note.add_theme_font_size_override(&"font_size", 13)
			note.theme_type_variation = &"DimLabel"
			note.text = "%d%%%s" % [roundi(condition * 100.0), " · %s fitted" % str((each.get("upgrade", {}) as Dictionary).get("name", "")) if ship.upgrades.has(each.id) else ""]
			grid.add_child(note)
	var scroll := ScrollContainer.new()  # (Fifty parts on a giant: scrolls.)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, minf(24.0 * (list.size() + groups.size()) + 8.0, 330.0))
	scroll.add_child(grid)
	_parts_box.add_child(scroll)
	var foot := Label.new()
	foot.theme_type_variation = &"DimLabel"
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_theme_font_size_override(&"font_size", 13)
	foot.text = "* major: only put right in drydock (a shipyard port or a hub of yours with the Drydock facility). Fuel x%s (hull), speed x%s (propulsion), breakdowns x%s, port time x%s from the parts now." % [Fmt.decimal(ShipParts.factor(ship, "fuel"), 2), Fmt.decimal(ShipParts.factor(ship, "speed"), 2), Fmt.decimal(ShipParts.factor(ship, "breakdowns"), 2), Fmt.decimal(ShipParts.factor(ship, "dock"), 2)]
	_parts_box.add_child(foot)
	if GameState.is_mine(ship):
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		if ship.in_drydock():
			row.add_child(foot.duplicate())
			(row.get_child(0) as Label).text = ship.status_text()
		elif not ship.drydock_to.is_empty():
			var cancel := Button.new()
			cancel.text = "Cancel the drydock"
			cancel.pressed.connect(func() -> void:
				GameState.cancel_drydock(ship)
				_fill_parts())
			row.add_child(cancel)
		else:
			var dock := Button.new()
			dock.text = "Drydock…"
			dock.tooltip_text = "Send it to a yard: every part put right, upgrades fitted, days out of service."
			dock.pressed.connect(func() -> void: PopupHost.find(self).open(DrydockPopup.new(ship)))
			row.add_child(dock)
		_parts_box.add_child(row)


func _show_parts(on: bool) -> void:
	if on:
		_fill_parts()
		if _crew_button.button_pressed:
			_crew_button.button_pressed = false
	_parts_box.visible = on
	%BarsSlot.visible = not on and not _crew_button.button_pressed
	%Toggles.visible = not on and not _crew_button.button_pressed
	_update_live()
	reset_size.call_deferred()


func _show_crew(on: bool) -> void:
	if on and _parts_button.button_pressed:
		_parts_button.button_pressed = false
	_crew_box.visible = on
	%BarsSlot.visible = not on
	%Toggles.visible = not on
	_update_live()
	reset_size.call_deferred()
