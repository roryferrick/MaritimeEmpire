# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name ContractsScreen
extends Control
## The Contracts page over the map (DESIGN_LIVING_WORLD.md M2): the producers'
## open offers to the company (what, where, how much, what they pay, how long
## they stand, and what standing they need), the contracts signed (each with
## its progress by quarter or towards its delivery, the ships on it and what
## they can carry, Assign and Unassign), the contracts done and failed, and
## the company's standing with every country and producer it has dealt with.
## Refreshes as the contracts change and every few seconds while open.

const REFRESH_SECONDS := 4.0
const FONT_SIZE := 14
const ROW_WIDTH := 760.0

var _body := VBoxContainer.new()
var _clock := 0.0
var _picking := -1  # The contract a ship is being picked for, or -1.


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 12)
	margin.add_child(content)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Contracts"
	content.add_child(title)
	_body.add_theme_constant_override(&"separation", 14)
	content.add_child(_body)
	visibility_changed.connect(_refresh)
	GameState.contracts.offers_changed.connect(_refresh)
	GameState.contracts.contracts_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var contracts: Contracts = GameState.contracts
	var company := GameState.company
	var tier := contracts.best_tier(company)
	_body.add_child(_dim("Producers offer shipping where their markets call for it. Your standing with each (its country's and its own) decides what they offer: Unknown gets small one-off voyages, Known recurring contracts, Trusted tenders, Renowned the biggest. You stand %s at best; deliveries lift it, shortfalls and failures sink it." % Contracts.tier_name(tier)))
	_add_offers(contracts, company)
	_add_contracts(contracts, company)
	_add_standing(contracts, company)


# --- Offers -----------------------------------------------------------------------------

func _add_offers(contracts: Contracts, company: Company) -> void:
	var box := _card("Offers (%d)" % contracts.offers.size())
	if contracts.offers.is_empty():
		box.add_child(_dim("No offers open. New ones come every %d days as the markets move." % Contracts.OFFER_DAYS))
	var offers := contracts.offers.duplicate()
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.value) > float(b.value))
	for offer: Dictionary in offers:
		var row := VBoxContainer.new()
		row.add_theme_constant_override(&"separation", 2)
		var head := HBoxContainer.new()
		head.add_theme_constant_override(&"separation", 10)
		var title := _text("%s · %s" % [Contracts.KINDS.get(str(offer.kind), "Offer"), contracts.producer_name(int(offer.producer))])
		title.add_theme_color_override(&"font_color", Color(0.98, 0.85, 0.55))
		title.size_flags_horizontal = SIZE_EXPAND_FILL
		head.add_child(title)
		var error := contracts.can_sign(company, offer)
		var accept := Button.new()
		accept.text = "Accept"
		accept.disabled = not error.is_empty()
		accept.tooltip_text = error
		var id := int(offer.id)
		accept.pressed.connect(func() -> void: GameState.sign_contract(id))
		head.add_child(accept)
		var decline := Button.new()
		decline.text = "Decline"
		decline.flat = true
		decline.pressed.connect(func() -> void: GameState.decline_offer(id))
		head.add_child(decline)
		row.add_child(head)
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 4)
		line.add_child(_text(GameState.contract_summary(offer) + ","))
		line.add_child(_port_button(str(offer.from)))
		line.add_child(_text("to"))
		line.add_child(_port_button(str(offer.to)))
		line.add_child(_dim("(%s nm)" % Fmt.thousands(roundi(float(offer.nm)))))
		row.add_child(line)
		var standing := Contracts.tier_of(contracts.opinion(company, int(offer.producer)))
		row.add_child(_dim("Worth %s%s · premium x%s over plain freight · stands till %s · needs %s standing (you're %s with them, %d)" % [Fmt.money(int(offer.value)),
			" over %d quarters" % int(offer.quarters) if int(offer.get("quarters", 0)) > 0 else "", Fmt.decimal(float(offer.premium), 2), Fmt.calendar_short(int(offer.expires)),
			Contracts.tier_name(str(offer.min_tier)), Contracts.tier_name(standing), roundi(contracts.opinion(company, int(offer.producer)))]))
		box.add_child(row)
	_body.add_child(box.get_parent())


# --- Signed ------------------------------------------------------------------------------

func _add_contracts(contracts: Contracts, company: Company) -> void:
	var mine := int(GameState.all_companies().find(company))
	var active := contracts.contracts.filter(func(c: Dictionary) -> bool: return int(c.company) == mine and str(c.status) == "active")
	var past := contracts.contracts.filter(func(c: Dictionary) -> bool: return int(c.company) == mine and str(c.status) != "active")
	var box := _card("Your contracts (%d)" % active.size())
	if active.is_empty():
		box.add_child(_dim("None signed. Accept an offer above, then assign ships to it here."))
	for contract: Dictionary in active:
		box.add_child(_contract_row(contracts, contract))
	if not past.is_empty():
		box.add_child(HSeparator.new())
		box.add_child(_dim("Earlier: " + ", ".join(PackedStringArray(past.slice(-8).map(func(c: Dictionary) -> String: return "%s for %s (%s)" % [GameState.contract_summary(c), contracts.producer_name(int(c.producer)), str(c.status)])))))
	_body.add_child(box.get_parent())


func _contract_row(contracts: Contracts, contract: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 4)
	var title := _text("%s for %s," % [GameState.contract_summary(contract), contracts.producer_name(int(contract.producer))])
	title.add_theme_color_override(&"font_color", Color(0.75, 0.9, 1.0))
	head.add_child(title)
	head.add_child(_port_button(str(contract.from)))
	head.add_child(_text("to"))
	head.add_child(_port_button(str(contract.to)))
	row.add_child(head)
	var progress := ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = float(contract.units)
	progress.value = float(contract.quarter_delivered if str(contract.kind) == "recurring" else contract.delivered)
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(ROW_WIDTH, 10.0)
	progress.tooltip_text = contracts.progress_text(contract)
	row.add_child(progress)
	row.add_child(_dim(contracts.progress_text(contract) + " · earned %s so far%s" % [Fmt.money(roundi(float(contract.delivered) * float(contract.rate))), "" if int(contract.fees) == 0 else " · fees %s" % Fmt.money(int(contract.fees))]))
	var ships := HFlowContainer.new()
	ships.add_theme_constant_override(&"h_separation", 6)
	ships.add_child(_text("Ships:"))
	var any := false
	for id: int in contract.ships:
		var ship: Ship = GameState.ship_by_id(id)
		if ship == null:
			continue
		any = true
		var chip := Button.new()
		chip.text = "%s ✕" % ship.name
		chip.flat = true
		chip.tooltip_text = "%s: %s. Click to take it off the contract." % [ship.model().get("name", ""), ship.status_text()]
		chip.add_theme_font_size_override(&"font_size", FONT_SIZE)
		chip.pressed.connect(func() -> void: GameState.unassign_contract_ship(ship))
		ships.add_child(chip)
	if not any:
		ships.add_child(_dim("none yet"))
	var capacity := contracts.capacity_a_quarter(contract)
	if str(contract.kind) == "recurring":
		ships.add_child(_dim("(they can carry about %s a quarter of the %s needed)" % [Fmt.short(capacity), Fmt.thousands(int(contract.units))]))
	var assign := Button.new()
	assign.text = "Assign a ship"
	assign.add_theme_font_size_override(&"font_size", FONT_SIZE)
	var id := int(contract.id)
	assign.pressed.connect(func() -> void:
		_picking = -1 if _picking == id else id
		_refresh())
	ships.add_child(assign)
	row.add_child(ships)
	if _picking == id:
		row.add_child(_ship_picker(contract))
	return row


## The company's ships that can carry the contract's good, each a button that assigns it.
func _ship_picker(contract: Dictionary) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 6)
	var good := str(contract.good)
	var any := false
	for ship in GameState.fleet():
		if ship.is_service() or not good in ship.model().get("cargo", []) or ship.contract_id == int(contract.id):
			continue
		any = true
		var button := Button.new()
		var on_other := ship.contract_id > 0
		button.text = "%s (%s%s)" % [ship.name, ship.model().get("name", ""), ", on another contract" if on_other else ""]
		button.add_theme_font_size_override(&"font_size", FONT_SIZE)
		var error := GameState.contract_ship_error(contract, ship)
		button.disabled = not error.is_empty()
		button.tooltip_text = error if not error.is_empty() else ship.status_text()
		button.pressed.connect(func() -> void:
			GameState.assign_contract_ship(int(contract.id), ship)
			_picking = -1
			_refresh())
		flow.add_child(button)
	if not any:
		flow.add_child(_dim("No ship of yours carries %s. The Shop has them." % str(GameData.commodity(good).get("name", good)).to_lower()))
	return flow


# --- Standing ----------------------------------------------------------------------------

func _add_standing(contracts: Contracts, company: Company) -> void:
	var box := _card("Your standing")
	var countries: Dictionary = company.relations.get("countries", {})
	var ids: Array = countries.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return float(countries[a]) > float(countries[b]))
	var parts := PackedStringArray()
	for id: String in ids:
		var value := float(countries[id])
		if absf(value) < 0.5:
			continue
		parts.append("%s %s (%d)" % [str(WorldEconomy.country(id).get("name", id)), Contracts.tier_name(Contracts.tier_of(value)), roundi(value)])
	box.add_child(_text("Countries: " + (", ".join(parts) if not parts.is_empty() else "nowhere known yet")))
	var producers: Dictionary = company.relations.get("producers", {})
	var names := PackedStringArray()
	var keys: Array = producers.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(producers[a]) > float(producers[b]))
	for key: String in keys.slice(0, 12):
		if absf(float(producers[key])) >= 0.5:
			names.append("%s %s%d" % [contracts.producer_name(int(key)), "+" if float(producers[key]) > 0.0 else "", roundi(float(producers[key]))])
	box.add_child(_dim("Producers who remember you: " + (", ".join(names) if not names.is_empty() else "none yet") + ". Standing fades slowly towards neutral."))
	_body.add_child(box.get_parent())


# --- Bits --------------------------------------------------------------------------------

func _card(title_text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	card.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override(&"font_size", 17)
	box.add_child(title)
	return box


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return label


func _dim(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = &"DimLabel"
	return label


func _port_button(port_id: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = GameData.port_name(port_id)
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	button.pressed.connect(func() -> void: GameRoot.find(self).show_port_on_map(port_id))
	return button
