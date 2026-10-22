# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name EventCard
extends PanelContainer
## A card in the middle of the screen for the big moments: a rating star
## gained or lost, an achievement earned and a research discovery. The game pauses
## while one shows and carries on at the speed it was at when Continue is
## pressed (Space or Enter too); more than one at once queue up, one card each.
## In multiplayer the host's clock runs for everyone, so the card shows without
## pausing and Continue just closes it.

const WIDTH := 480.0
const GOLD := Color(1.0, 0.8, 0.3)
const LEVEL_COLOR := Color(0.55, 0.85, 1.0)

var _kicker := Label.new()
var _title := Label.new()
var _body := Label.new()
var _picture := CenterContainer.new()
var _button := Button.new()
var _actions := HBoxContainer.new()
var _queue: Array[Dictionary] = []  # [{kicker, title, body, color, site (a research site to picture)}]
## The speed the game ran at before the card paused it (0: it was paused already).
var _was_speed := 0


func _ready() -> void:
	theme_type_variation = &"MapPopup"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	_kicker.theme_type_variation = &"DimLabel"
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_kicker)
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override(&"font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = WIDTH - 32.0
	box.add_child(_title)
	box.add_child(_picture)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.custom_minimum_size.x = WIDTH - 32.0
	box.add_child(_body)
	_button.text = "Continue"
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.custom_minimum_size = Vector2(140, 38)
	_button.pressed.connect(_continue)
	box.add_child(_button)
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override(&"separation", 10)
	box.add_child(_actions)
	visible = false


## A company type's rating reached a new whole star (up) or fell to one (see Ratings).
func show_rating(type_name: String, star: int, up: bool) -> void:
	var body := "Your %s ships' condition, reliability and reach earned it. Their cargo sells a little better and pays lower port fees as the stars rise." % type_name if up \
		else "Look at the Ratings page (the star button on the map) to see which part slipped and how to lift it."
	_enqueue({kicker = "RATING UP" if up else "RATING DOWN", title = "%s: %s" % [type_name, "★".repeat(star) if star > 0 else "no stars"], body = body, color = GOLD if up else Color(0.95, 0.5, 0.45)})


## An achievement earned (stars 0 for a one-off badge), as Achievements.check() reports it.
func show_achievement(name: String, stars: int, unit := "") -> void:
	var title := name if stars == 0 else "%s %s" % [name, "★".repeat(stars)]
	var body := "Achievement earned." if stars == 0 else "%d of 3 stars%s." % [stars, (" for " + unit) if not unit.is_empty() else ""]
	_enqueue({kicker = "ACHIEVEMENT", title = title, body = body, color = GOLD})


## A research site discovered by one of this company's ships (see Research):
## its picture and facts, and whether it was first there.
func show_discovery(site_id: String, first: bool, ship_name: String, points: float) -> void:
	var site := Research.site(site_id)
	var category := Research.category(str(site.get("category", "")))
	var body := "%s · %s m down · %s\n\n%s" % [str(category.get("name", "")), Fmt.thousands(int(site.get("depth_m", 0))), str(site.get("when", "")), str(site.get("fact", ""))]
	body += "\n\n%s surveyed it%s: +%s research points." % [ship_name, ", the first company ever" if first else "", Fmt.thousands(roundi(points))]
	_enqueue({kicker = "FIRST DISCOVERY" if first else "DISCOVERY", title = str(site.get("name", site_id)), body = body, color = GOLD if first else Color.from_string(str(category.get("color", "#9a7bd8")), LEVEL_COLOR).lightened(0.3), site = site_id})


## An important contract offer (Contracts.offer_arrived): the producer, the
## work and the pay, with Accept, Decline and Leave it (it stays on the
## Contracts page). Only for the player's own company.
func show_offer(offer: Dictionary) -> void:
	var contracts: Contracts = GameState.contracts
	var body := "%s offers %s, %s to %s (%s nm).

Worth %s in all%s. %s" % [contracts.producer_name(int(offer.producer)), GameState.contract_summary(offer), GameData.port_name(str(offer.from)), GameData.port_name(str(offer.to)),
		Fmt.thousands(roundi(float(offer.nm))), Fmt.money(int(offer.value)), " over %d quarters" % int(offer.quarters) if int(offer.get("quarters", 0)) > 0 else "",
		"The offer stands till %s." % Fmt.calendar_short(int(offer.expires))]
	if str(offer.kind) == "tender":
		var names := PackedStringArray()
		for index: int in offer.get("bidders", []):
			names.append(str((GameState.firms as ShippingFirms).firms[index].name))
		body = "%s puts out to tender: %s, %s to %s (%s nm).\n\nAsking %s a unit (%s in all). Bidding: %s. Bids are sealed and close %s; the producer takes the lowest, weighing its standing with each bidder." % [contracts.producer_name(int(offer.producer)), GameState.contract_summary(offer), GameData.port_name(str(offer.from)), GameData.port_name(str(offer.to)),
			Fmt.thousands(roundi(float(offer.nm))), Fmt.money(roundi(float(offer.asking))), Fmt.money(int(offer.value)), ", ".join(names), Fmt.calendar_short(int(offer.closes))]
		_enqueue({kicker = "TENDER", title = "%s: %s" % [str(GameData.commodity(str(offer.good)).get("name", offer.good)), GameData.port_name(str(offer.from))], body = body, color = GOLD,
			actions = [["Bid", func() -> void: GameRoot.find(self).show_contracts()], ["Ignore", Callable()]]})
		return
	var id := int(offer.id)
	_enqueue({kicker = "CONTRACT OFFER", title = "%s from %s" % [Contracts.KINDS.get(str(offer.kind), "Offer"), GameData.port_name(str(offer.from))], body = body, color = GOLD,
		actions = [["Accept", func() -> void: GameState.sign_contract(id)], ["Decline", func() -> void: GameState.decline_offer(id)], ["Leave it", Callable()]]})



## A tender the player bid on has closed (Contracts.tender_closed).
func show_tender_result(offer: Dictionary, won: bool, winner: String, rate: float) -> void:
	var good := str(GameData.commodity(str(offer.good)).get("name", offer.good))
	if won:
		_enqueue({kicker = "TENDER WON", title = "%s is yours" % good, body = "%s took your bid of %s a unit: %s, %s to %s. Assign ships to it on the Contracts page." % [GameState.contracts.producer_name(int(offer.producer)), Fmt.money(roundi(rate)), GameState.contract_summary(offer), GameData.port_name(str(offer.from)), GameData.port_name(str(offer.to))], color = GOLD,
			actions = [["Contracts page", func() -> void: GameRoot.find(self).show_contracts()], ["Later", Callable()]]})
	else:
		_enqueue({kicker = "TENDER LOST", title = "%s goes to %s" % [good, winner], body = "%s took %s's bid of %s a unit against your %s. Standing with the producer would have weighed your bid better." % [GameState.contracts.producer_name(int(offer.producer)), winner, Fmt.money(roundi(rate)), Fmt.money(roundi(float(offer.my_bid)))], color = Color(0.95, 0.6, 0.5)})


## Something on one of the player's contracts wants an answer (Contracts.contract_event).
func show_contract_event(contract: Dictionary, kind: String, info: Dictionary) -> void:
	var contracts: Contracts = GameState.contracts
	var party := contracts.party_name(contract)
	var good := str(GameData.commodity(str(contract.good)).get("name", contract.good)).to_lower()
	var id := int(contract.id)
	match kind:
		"raise":
			_enqueue({kicker = "A PRODUCER ASKS", title = "%s wants more %s" % [party, good], color = GOLD,
				body = "Their market at %s has tightened (x%s of the usual price). They ask for %s more units this quarter and will pay %d%% over the contract rate for the whole quarter. Refusing costs a little standing." % [GameData.port_name(str(contract.to)), Fmt.decimal(float(info.get("ratio", 1.0)), 2), Fmt.thousands(int(info.get("extra", 0))), roundi((float(info.get("bonus", 1.2)) - 1.0) * 100.0)],
				actions = [["Take it on", func() -> void: GameState.answer_contract_event(id, "raise", true)], ["Refuse", func() -> void: GameState.answer_contract_event(id, "raise", false)]]})
		"pause":
			_enqueue({kicker = "A PRODUCER ASKS", title = "%s asks to pause %s" % [party, good], color = GOLD,
				body = "Their market at %s is glutted (x%s of the usual price). They ask to skip this quarter's volume, no fee either way; the contract runs on afterwards. Refusing costs a little standing, and the quarter counts as usual." % [GameData.port_name(str(contract.to)), Fmt.decimal(float(info.get("ratio", 1.0)), 2)],
				actions = [["Pause the quarter", func() -> void: GameState.answer_contract_event(id, "pause", true)], ["Refuse", func() -> void: GameState.answer_contract_event(id, "pause", false)]]})
		"at_risk":
			_enqueue({kicker = "QUARTER AT RISK", title = "%s for %s" % [good.capitalize(), party], color = Color(0.95, 0.6, 0.5),
				body = "%d days to the quarter's end and the ships on it can't carry what's left: about %s units short, a %s fee at that rate. Assign another ship or carry on." % [int(info.get("days", 0)), Fmt.thousands(int(info.get("short", 0))), Fmt.money(int(info.get("fee", 0)))],
				actions = [["Contracts page", func() -> void: GameRoot.find(self).show_contracts()], ["Carry on", Callable()]]})
		"short_quarter":
			_enqueue({kicker = "A STERN LETTER", title = "%s short for %s" % [good.capitalize(), party], color = Color(0.95, 0.6, 0.5),
				body = "The quarter closed %s units short. They will take the shortfall on top of next quarter's volume at no extra fee (a smaller mark against you), or the fee of %s now." % [Fmt.thousands(int(info.get("short", 0))), Fmt.money(int(info.get("fee", 0)))],
				actions = [["Make it up next quarter", func() -> void: GameState.answer_contract_event(id, "short_quarter", true)], ["Pay the fee", func() -> void: GameState.answer_contract_event(id, "short_quarter", false)]]})


func _enqueue(card: Dictionary) -> void:
	_queue.append(card)
	if not visible:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		visible = false
		return
	var card: Dictionary = _queue.pop_front()
	_kicker.text = card.kicker
	_title.text = card.title
	_title.add_theme_color_override(&"font_color", card.color)
	_body.text = card.body
	for child in _picture.get_children():
		child.queue_free()
	_picture.visible = card.has("site")
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	_actions.visible = card.has("actions")
	_button.visible = not card.has("actions")
	for action: Array in card.get("actions", []):
		var choice := Button.new()
		choice.text = action[0]
		choice.custom_minimum_size = Vector2(120, 38)
		var then: Callable = action[1]
		choice.pressed.connect(func() -> void:
			if then.is_valid():
				then.call()
			_continue())
		_actions.add_child(choice)
	if card.has("site"):
		var art := SiteArt.new(str(card.site))
		art.custom_minimum_size = Vector2(WIDTH - 40.0, 190.0)
		_picture.add_child(art)
	if not visible:
		visible = true
		if not Net.is_online():
			_was_speed = GameState.time_speed
			if _was_speed > 0:
				GameState.time_speed = 0
	_button.grab_focus()
	if _actions.visible and _actions.get_child_count() > 0:
		(_actions.get_child(0) as Button).grab_focus()


func _continue() -> void:
	if not _queue.is_empty():
		_show_next()
		return
	visible = false
	if _was_speed > 0 and GameState.time_speed == 0:
		GameState.time_speed = _was_speed
	_was_speed = 0


## Space or Enter continues (before the game's own Space, which would unpause behind the card).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
		_continue()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_SPACE:
		_continue()
		get_viewport().set_input_as_handled()
