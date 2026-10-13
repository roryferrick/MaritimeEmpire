# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name FishingPanel
extends VBoxContainer
## A fishing or crabbing boat's controls in its popup (ShipPopup): its base
## (any port: it sails there and works from it), what it goes after (the most
## timely and profitable this season, chosen again each trip, or one of the
## species and grounds its gear and size can work within reach of its base,
## in season or not, with what a day of it is worth now), and what happens to
## its catch when it's landed (sold, or kept in the cold store for the
## company's seafood carriers).

var ship: Ship
## Each model's ports with what months its boats could fish from each (see
## _port_months()), kept for every popup after the first: port id -> {species: months}.
static var _months_by_model := {}
var _base := OptionButton.new()
var _target := OptionButton.new()
var _landing := OptionButton.new()


func _init(for_ship: Ship) -> void:
	ship = for_ship


func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	_row("Base", _base, "Where it lands its catch and sets out from: any port. It sails there once it's in port.")
	_row("Target", _target, "What it goes after. The most timely and profitable is chosen again for every trip from what's in season and the stocks left.")
	_row("Catch", _landing, "Kept in the cold store, its catch waits for your seafood carriers (Reefers) to take it where it pays most.")
	var ports := GameData.ports.duplicate()
	ports.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name) < str(b.name))
	for port: Dictionary in ports:
		_base.add_item(str(port.name))
		_base.set_item_metadata(_base.item_count - 1, str(port.id))
		if port.id == ship.base_port:
			_base.select(_base.item_count - 1)
	# Beside each port: how many months of the year this boat could fish from
	# there (any species in season) and how many species, with each species'
	# months in the tooltip, so a base can be chosen for the most fishing.
	# Worked out for every port off the main thread the first time a boat of
	# the model asks (a few seconds for a long-range boat), and kept.
	if _months_by_model.has(ship.model_id):
		_apply_months()
	else:
		var ids := PackedStringArray()
		for port: Dictionary in ports:
			ids.append(str(port.id))
		_months_task = WorkerThreadPool.add_task(_compute_months.bind(ship.model(), ids), false, "Fishing months")
		set_process(true)
	_base.item_selected.connect(func(index: int) -> void:
		GameState.set_fishing_base(ship, str(_base.get_item_metadata(index)))
		_fill_targets.call_deferred())
	for entry: Array in [["auto", "Store for my carriers where they call, else sell"], ["sell", "Sell where it's landed"], ["store", "Keep in the cold store"]]:
		_landing.add_item(entry[1])
		_landing.set_item_metadata(_landing.item_count - 1, entry[0])
		if entry[0] == ship.fish_landing:
			_landing.select(_landing.item_count - 1)
	_landing.item_selected.connect(func(index: int) -> void: GameState.set_fish_landing(ship, str(_landing.get_item_metadata(index))))
	_target.item_selected.connect(func(index: int) -> void:
		var pick: Array = _target.get_item_metadata(index)
		GameState.set_fishing_target(ship, pick[0], pick[1]))
	_fill_targets()


var _months_task := -1
var _computed := {}  # Port id -> {species: months}, as the task fills it.

## What a model's boats could fish from every port over the year
## (Fisheries.months_from()), each port's species longest season first: on a
## worker thread (reads only).
func _compute_months(model: Dictionary, ids: PackedStringArray) -> void:
	var fish := Fisheries.shared()
	var out := {}
	for port_id: String in ids:
		var months := fish.months_from(model, port_id)
		var ordered := {}
		var species: Array = months.keys()
		species.sort_custom(func(a: String, b: String) -> bool: return (months[a] as Array).size() > (months[b] as Array).size())
		for id: String in species:
			ordered[id] = months[id]
		out[port_id] = ordered
	_computed = out


func _process(_delta: float) -> void:
	if _months_task < 0:
		set_process(false)
		return
	if not WorkerThreadPool.is_task_completed(_months_task):
		return
	WorkerThreadPool.wait_for_task_completion(_months_task)
	_months_task = -1
	_months_by_model[ship.model_id] = _computed
	_apply_months()
	set_process(false)


func _exit_tree() -> void:
	if _months_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_months_task)
		_months_by_model[ship.model_id] = _computed
		_months_task = -1


## The months beside each port's name, and each species' in its tooltip.
func _apply_months() -> void:
	var fish := Fisheries.shared()
	var by_port: Dictionary = _months_by_model.get(ship.model_id, {})
	for i in _base.item_count:
		var port_id := str(_base.get_item_metadata(i))
		var port_name := GameData.port_name(port_id)
		var months: Dictionary = by_port.get(port_id, {})
		var all_months := []
		var lines := []
		for species_id: String in months:
			var when: Array = months[species_id]
			for m: int in when:
				if not all_months.has(m):
					all_months.append(m)
			lines.append("%s: %d months (%s)" % [fish.species_name(species_id), when.size(), Fisheries.months_text(when)])
		if months.is_empty():
			_base.set_item_text(i, "%s — nothing within reach" % port_name)
			_base.set_item_tooltip(i, "Nothing its gear can catch within reach of %s." % port_name)
		else:
			_base.set_item_text(i, "%s — %d of 12 months, %d species" % [port_name, all_months.size(), months.size()])
			_base.set_item_tooltip(i, "
".join(lines))


func _row(title: String, picker: OptionButton, tip: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 52
	label.theme_type_variation = &"DimLabel"
	row.add_child(label)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = tip
	picker.fit_to_longest_item = false
	picker.clip_text = true
	row.add_child(picker)
	add_child(row)


## The targets from its base now: the best first ("Most timely and profitable"), then each it can work.
func _fill_targets() -> void:
	_target.clear()
	var fish := Fisheries.shared()
	_target.add_item("Most timely and profitable (re-chosen each trip)")
	_target.set_item_metadata(0, ["", ""])
	var options := GameState.fishing_options(ship, ship.base_port)
	for option: Dictionary in options:
		var where := GameData.port_name(Fisheries.end_of(option.ground))
		var text := "%s, %s" % [fish.species_name(option.species), where]
		if option.in_season:
			text += " — %s a day" % Fmt.money(roundi(option.per_day))
		else:
			text += " — in season %s" % option.season
		if float(option.stock) < 0.6:
			text += " (fished down)"
		_target.add_item(text)
		_target.set_item_metadata(_target.item_count - 1, [option.species, option.ground])
		_target.set_item_tooltip(_target.item_count - 1, "%s (%s): %s nm from %s, in season %s; %s a crate landed at %s." % [fish.species_name(option.species),
			fish.species[option.species].latin, Fmt.thousands(roundi(option.miles)), GameData.port_name(ship.base_port), option.season,
			Fmt.money(roundi(option.price)), GameData.port_name(ship.base_port)])
		if option.species == ship.fish_target and (ship.fish_area.is_empty() or option.ground == ship.fish_area):
			_target.select(_target.item_count - 1)
	if ship.fish_target.is_empty():
		_target.select(0)
	if options.is_empty():
		_target.add_item("Nothing its gear can catch within reach of %s" % GameData.port_name(ship.base_port))
		_target.set_item_disabled(_target.item_count - 1, true)
