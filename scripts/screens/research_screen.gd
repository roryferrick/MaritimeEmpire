# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name ResearchScreen
extends Control
## The Research screen (the Research page over the map, for Research
## companies): a view picked at the top left, its list down the left and the
## one picked on the right.
## - Contracts board: the offers on the board shared by every company (yours
##   first), each with its client, pay, deadline, depth and gear needed; take
##   one, send a ship on it, or give it up.
## - Expeditions: your research ships, what each is doing; send an idle one to
##   a site (or a contract), call one home, or move one to another port.
## - Atlas: the sites by category, how many done and the perk each category
##   gives at 25/50/100%; a site's card with its picture and facts.
## - Gear: each ship's gear slots; fit or take off sonar, ROVs, subs and more.
## See Research.

const LIST_WIDTH := 330.0
const FONT_SIZE := 14
const VIEWS := ["Contracts board", "Expeditions", "Atlas", "Gear", "Technology"]
const REFRESH_S := 2.0
## A contract given up takes a second click within this many seconds.
const CONFIRM_S := 3.0
## Ports offered to move a ship to: its company's HQ and hubs and this many nearest.
const MOVE_PORTS := 30

## What's shown on the right: "offer:ID", "ship:ID", "cat:ID", "site:ID" or "".
var place := ""
var _view := 0
var _list := VBoxContainer.new()
var _detail := VBoxContainer.new()
var _picker := OptionButton.new()
var _summary := Label.new()
var _dirty := true
var _clock := 0.0
var _pickers: Array[OptionButton] = []
var _confirm := {}  # Offer id -> when its giving up was first clicked (ms).
## The site picked to send each ship to (ship id -> site id), and the port to move it to.
var _send_site := {}
var _move_port := {}


func _ready() -> void:
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override(&"separation", 0)
	add_child(split)
	var left := PanelContainer.new()
	left.theme_type_variation = &"CardPanel"
	left.custom_minimum_size.x = LIST_WIDTH
	split.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override(&"separation", 8)
	left.add_child(left_box)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Research"
	left_box.add_child(title)
	left_box.add_child(_dim("Contracts pay. Your own expeditions to the sites under the sea pay nothing, but earn research points (banked for developing your own technology), fill the Atlas and win perks for the whole company."))
	_summary.add_theme_font_size_override(&"font_size", FONT_SIZE - 1)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_box.add_child(_summary)
	for each: String in VIEWS:
		_picker.add_item(each)
	_picker.item_selected.connect(func(index: int) -> void:
		_view = index
		place = ""
		_dirty = true)
	left_box.add_child(_picker)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_box.add_child(scroll)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 2)
	scroll.add_child(_list)
	var right := ScrollContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	right.add_child(margin)
	_detail.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail.add_theme_constant_override(&"separation", 10)
	margin.add_child(_detail)
	GameState.research.changed.connect(func() -> void: _dirty = true)
	GameState.technology.changed.connect(func() -> void: _dirty = true)
	GameState.ships_changed.connect(func() -> void: _dirty = true)
	visibility_changed.connect(func() -> void: _dirty = true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_S:
		_clock = 0.0
		_dirty = true
	if _dirty and not _pickers.any(func(picker: OptionButton) -> bool: return is_instance_valid(picker) and picker.get_popup().visible):
		_dirty = false
		_rebuild()


## Opens the Expeditions view at one of this player's research ships.
func show_ship(ship_id: int) -> void:
	_view = 1
	_picker.select(_view)
	place = "ship:%d" % ship_id
	_dirty = true


## Opens the Atlas at a site's card.
func show_site(site_id: String) -> void:
	_view = 2
	_picker.select(_view)
	place = "site:" + site_id
	_dirty = true


func _rebuild() -> void:
	var research: Research = GameState.research
	var who := GameState.company
	var all := Research.progress(who)
	var firsts := research.firsts.values().filter(func(index: int) -> bool: return index == GameState.all_companies().find(who)).size()
	_summary.text = "Sites done: %d of %d · first discoveries: %d · contracts held: %d of %d" % [all[0], all[1], firsts, research.taken_by(who).size(), research.max_open(who)]
	_pickers.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	match _view:
		0:
			_contracts_list()
		1:
			_ships_list("ship:")
		2:
			_atlas_list()
		3:
			_ships_list("gear:")
		4:
			_tech_list()
	if place.begins_with("offer:"):
		_offer_detail(int(place.substr(6)))
	elif place.begins_with("ship:"):
		_ship_detail(_ship_by_id(int(place.substr(5))))
	elif place.begins_with("gear:"):
		_gear_detail(_ship_by_id(int(place.substr(5))))
	elif place.begins_with("cat:"):
		_category_detail(place.substr(4))
	elif place.begins_with("site:"):
		_site_detail(place.substr(5))
	elif place.begins_with("tech:"):
		_tech_detail(place.substr(5))
	elif place.begins_with("rnd:"):
		_rnd_detail(place.substr(4))
	elif place == "own":
		_own_rnd_detail()
	else:
		_detail.add_child(_dim("Pick one on the left."))


func _research_ships() -> Array:
	return GameState.fleet().filter(func(ship: Ship) -> bool: return ship.is_research())


func _ship_by_id(id: int) -> Ship:
	for ship: Ship in _research_ships():
		if ship.id == id:
			return ship
	return null


# --- Contracts --------------------------------------------------------------------------------

func _contracts_list() -> void:
	var research: Research = GameState.research
	var mine_index := GameState.all_companies().find(GameState.company)
	var mine := research.board.filter(func(offer: Dictionary) -> bool: return int(offer.taken_by) == mine_index)
	var open := research.board.filter(func(offer: Dictionary) -> bool: return int(offer.taken_by) < 0)
	open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.pay) > int(b.pay))
	if not mine.is_empty():
		_list.add_child(_heading("Yours"))
		for offer: Dictionary in mine:
			_list.add_child(_list_button("offer:%d" % int(offer.id), "%s\n%s · due in %d days" % [offer.title, Fmt.money(int(offer.pay)), maxi(int(offer.due) - research.today(), 0)]))
	_list.add_child(_heading("On the board"))
	if open.is_empty():
		_list.add_child(_dim("Nothing on offer just now: new contracts come in every few days."))
	for offer: Dictionary in open:
		var can := _any_ship_could(offer)
		_list.add_child(_list_button("offer:%d" % int(offer.id), "%s%s\n%s · %s · %s m" % ["" if can else "(no ship for it) ", offer.title, Fmt.money(int(offer.pay)),
			str(Research.kind(str(offer.kind)).get("name", "")), Fmt.thousands(int(offer.depth))]))
	if place.is_empty():
		var first: Array = mine if not mine.is_empty() else open
		if not first.is_empty():
			place = "offer:%d" % int(first[0].id)


## Whether any of this company's research ships could do an offer (deep enough, its gear fittable), wherever it is.
func _any_ship_could(offer: Dictionary) -> bool:
	for ship: Ship in _research_ships():
		if Research.depth_of(ship.model()) >= int(offer.depth) and (offer.needs as Array).all(func(gear_id: String) -> bool: return Research.can_fit(ship.model(), gear_id)):
			return true
	return false


func _offer_detail(contract_id: int) -> void:
	var research: Research = GameState.research
	var offer := research.offer_by_id(contract_id)
	if offer.is_empty():
		_detail.add_child(_dim("That contract has gone."))
		return
	var head := Label.new()
	head.theme_type_variation = &"HeaderLabel"
	head.text = str(offer.title)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(head)
	_detail.add_child(_dim("%s for %s" % [str(Research.kind(str(offer.kind)).get("name", "")), str(offer.client)]))
	if not str(offer.site).is_empty():
		var art := SiteArt.new(str(offer.site), not Research.is_known(GameState.company, str(offer.site)) and int(offer.taken_by) < 0)
		art.custom_minimum_size = Vector2(420, 170)
		_detail.add_child(art)
	var lines := PackedStringArray([
		"Pays %s on completion%s" % [Fmt.money(int(offer.pay)), " (half again with a film crew aboard)" if str(offer.kind) == "documentary" else ""],
		"Where: %s, %s m down" % [Research.target_name(str(offer.target)), Fmt.thousands(int(offer.depth))],
		"Needs: %s fitted · %s days on station · a tier %d ship or better" % [_gear_names(offer.needs), Fmt.decimal(float(offer.days), 1), int(offer.tier)],
	])
	if str(offer.kind) == "salvage":
		lines.append("Salvage can fail: a quarter of the pay if little is brought up.")
	if int(offer.taken_by) < 0:
		lines.append("%d days to do it once taken · leaves the board in %d days" % [int(offer.deadline), maxi(int(offer.expires) - research.today(), 0)])
	else:
		lines.append("Due in %d days. Missing the deadline loses the pay and costs %s." % [maxi(int(offer.due) - research.today(), 0), Fmt.money(roundi(float(offer.pay) * float(Research.setting("penalty", 0.1))))])
	for line in lines:
		_detail.add_child(_text(line))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	_detail.add_child(buttons)
	var mine := int(offer.taken_by) == GameState.all_companies().find(GameState.company)
	if int(offer.taken_by) < 0:
		var take := Button.new()
		take.text = "Take this contract"
		var error := research.accept_error(GameState.company, contract_id)
		take.disabled = not error.is_empty()
		take.tooltip_text = error
		take.pressed.connect(func() -> void:
			GameState.accept_contract(contract_id)
			_dirty = true)
		buttons.add_child(take)
	elif mine:
		var give := Button.new()
		var armed := Time.get_ticks_msec() - int(_confirm.get(contract_id, -100000)) < CONFIRM_S * 1000
		give.text = "Click again to give it up" if armed else "Give it up"
		give.tooltip_text = "Giving it up fails it: the penalty is paid."
		give.pressed.connect(func() -> void:
			if Time.get_ticks_msec() - int(_confirm.get(contract_id, -100000)) < CONFIRM_S * 1000:
				GameState.abandon_contract(contract_id)
				place = ""
			else:
				_confirm[contract_id] = Time.get_ticks_msec()
			_dirty = true)
		buttons.add_child(give)
	buttons.add_child(_map_button(str(offer.target)))
	if not mine:
		return
	# Send a ship on it.
	var sent := _research_ships().filter(func(ship: Ship) -> bool: return ship.research_contract == contract_id)
	if not sent.is_empty():
		_detail.add_child(_text("%s is on it: %s." % [(sent[0] as Ship).name, GameState.research.status_text(sent[0])]))
		return
	_detail.add_child(_heading("Send a ship"))
	var any := false
	for ship: Ship in _research_ships():
		var error := research.trip_error(GameState.company, ship, str(offer.target), offer)
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var label := _text("%s (%s) at %s" % [ship.name, ship.model().get("name", ""), GameData.port_name(ship.docked_at) if ship.is_docked() else "sea"])
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(label)
		var send := Button.new()
		send.text = "Send"
		send.disabled = not error.is_empty()
		send.tooltip_text = error
		send.pressed.connect(func() -> void:
			GameState.send_expedition(ship, str(offer.target), contract_id)
			_dirty = true)
		row.add_child(send)
		_detail.add_child(row)
		if not error.is_empty():
			_detail.add_child(_dim("   " + error))
		any = true
	if not any:
		_detail.add_child(_dim("You have no research ships yet: buy one in the Shop (Research)."))


# --- Ships: expeditions and gear ---------------------------------------------------------------

func _ships_list(prefix: String) -> void:
	var ships := _research_ships()
	if ships.is_empty():
		_list.add_child(_dim("No research ships yet: buy a survey vessel or a mothership in the Shop (Research)."))
		return
	for ship: Ship in ships:
		var note := GameState.research.status_text(ship) if prefix == "ship:" else "%d of %d gear slots: %s" % [ship.research_gear.size(), Research.slots_of(ship.model()), _gear_names(ship.research_gear) if not ship.research_gear.is_empty() else "nothing fitted"]
		_list.add_child(_list_button(prefix + str(ship.id), "%s · %s\n%s" % [ship.name, ship.model().get("name", ""), note]))
	if place.is_empty() or not place.begins_with(prefix):
		place = prefix + str((ships[0] as Ship).id)


func _ship_detail(ship: Ship) -> void:
	if ship == null:
		return
	var research: Research = GameState.research
	var head := Label.new()
	head.theme_type_variation = &"HeaderLabel"
	head.text = ship.name
	_detail.add_child(head)
	var model := ship.model()
	_detail.add_child(_dim("%s · %s · dives to %s m · reaches %s nm from port" % [model.get("name", ""), Research.line_name(str(model.get("category", ""))),
		Fmt.thousands(Research.depth_of(model)), Fmt.thousands(roundi(ship.range_nm()))]))
	_detail.add_child(_text("Now: %s." % GameState.research.status_text(ship)))
	_detail.add_child(_text("Gear: %s (%d of %d slots)" % [_gear_names(ship.research_gear) if not ship.research_gear.is_empty() else "nothing fitted", ship.research_gear.size(), Research.slots_of(model)]))
	if ship.job_phase == Ship.JOB_RESEARCH or not ship.research_target.is_empty():
		var recall := Button.new()
		recall.text = "Call it home" if ship.job_phase == Ship.JOB_RESEARCH else "Call it off"
		recall.size_flags_horizontal = SIZE_SHRINK_BEGIN
		recall.pressed.connect(func() -> void:
			GameState.recall_expedition(ship)
			_dirty = true)
		_detail.add_child(recall)
		if ship.job_phase == Ship.JOB_RESEARCH and ship.research_phase == "work":
			var bar := ProgressBar.new()
			var offer := research.offer_by_id(ship.research_contract) if ship.research_contract > 0 else {}
			bar.max_value = 1.0
			bar.step = 0.001
			bar.value = clampf(ship.research_work / maxf(research.station_s(ship, ship.research_target, offer), 0.001), 0.0, 1.0)
			bar.custom_minimum_size = Vector2(320, 14)
			bar.size_flags_horizontal = SIZE_SHRINK_BEGIN
			_detail.add_child(bar)
		return
	if not ship.is_docked() or ship.is_lost():
		return
	# Send it to a site.
	_detail.add_child(_heading("Send it to a site"))
	var sites := _sites_for(ship)
	if sites.is_empty():
		_detail.add_child(_dim("No sites known within its reach yet."))
	else:
		var picker := OptionButton.new()
		picker.fit_to_longest_item = false
		picker.custom_minimum_size.x = 460
		var chosen := str(_send_site.get(ship.id, ""))
		var index := 0
		for i in sites.size():
			var entry: Dictionary = sites[i]
			picker.add_item("%s%s · %s · %s nm" % ["✓ " if entry.done else "", Research.site(entry.id).name, Research.category(str(Research.site(entry.id).category)).get("name", ""), Fmt.thousands(roundi(entry.miles))])
			if entry.id == chosen:
				index = i
		picker.select(index)
		_send_site[ship.id] = sites[index].id
		picker.item_selected.connect(func(i: int) -> void:
			_send_site[ship.id] = sites[i].id
			_dirty = true)
		_pickers.append(picker)
		_detail.add_child(picker)
		var site_id: String = _send_site[ship.id]
		var error := research.trip_error(GameState.company, ship, Research.end_of(site_id))
		var site := Research.site(site_id)
		_detail.add_child(_dim("%s m down · needs %s · %s days on station%s" % [Fmt.thousands(int(site.depth_m)), _gear_names(site.needs), Fmt.decimal(float(site.days), 1),
			" · done already (a quarter of the research points again)" if Research.is_done(GameState.company, site_id) else (" · no one's been: first discovery bonus" if not research.firsts.has(site_id) else "")]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var send := Button.new()
		send.text = "Send"
		send.disabled = not error.is_empty()
		send.tooltip_text = error
		send.pressed.connect(func() -> void:
			GameState.send_expedition(ship, Research.end_of(site_id))
			_dirty = true)
		row.add_child(send)
		var card := Button.new()
		card.text = "Its card"
		card.pressed.connect(func() -> void: show_site(site_id))
		row.add_child(card)
		_detail.add_child(row)
		if not error.is_empty():
			_detail.add_child(_dim(error))
	# Contracts it could go on.
	var mine := research.taken_by(GameState.company).filter(func(offer: Dictionary) -> bool:
		return not _research_ships().any(func(other: Ship) -> bool: return other.research_contract == int(offer.id)))
	if not mine.is_empty():
		_detail.add_child(_heading("Your contracts"))
		for offer: Dictionary in mine:
			var row := HBoxContainer.new()
			row.add_theme_constant_override(&"separation", 8)
			var label := _text("%s · %s" % [offer.title, Fmt.money(int(offer.pay))])
			label.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_child(label)
			var error := research.trip_error(GameState.company, ship, str(offer.target), offer)
			var send := Button.new()
			send.text = "Send"
			send.disabled = not error.is_empty()
			send.tooltip_text = error
			var target := str(offer.target)
			var contract_id := int(offer.id)
			send.pressed.connect(func() -> void:
				GameState.send_expedition(ship, target, contract_id)
				_dirty = true)
			row.add_child(send)
			_detail.add_child(row)
	# Move it.
	_detail.add_child(_heading("Move it to another port"))
	_detail.add_child(_dim("Sites further than its reach need a nearer port to set out from."))
	var ports := _move_ports(ship)
	var move_picker := OptionButton.new()
	move_picker.custom_minimum_size.x = 320
	var picked := str(_move_port.get(ship.id, ports[0] if not ports.is_empty() else ""))
	for i in ports.size():
		move_picker.add_item(GameData.port_name(ports[i]))
		if ports[i] == picked:
			move_picker.select(i)
	move_picker.item_selected.connect(func(i: int) -> void: _move_port[ship.id] = ports[i])
	_pickers.append(move_picker)
	var move_row := HBoxContainer.new()
	move_row.add_theme_constant_override(&"separation", 8)
	move_row.add_child(move_picker)
	var move := Button.new()
	move.text = "Move"
	move.disabled = ports.is_empty()
	move.pressed.connect(func() -> void:
		var to := str(_move_port.get(ship.id, ports[0]))
		GameState.move_research_ship(ship, to)
		_dirty = true)
	move_row.add_child(move)
	_detail.add_child(move_row)


## The sites a company knows of that a ship could reach from its port (within
## its range and depth, its needs fittable): {id, miles, done}, the ones not
## done first, nearest first.
func _sites_for(ship: Ship) -> Array:
	var out := []
	for site_id: String in Research.site_ids():
		if not Research.is_known(GameState.company, site_id):
			continue
		var site := Research.site(site_id)
		if int(site.depth_m) > Research.depth_of(ship.model()) or not (site.needs as Array).all(func(gear_id: String) -> bool: return Research.can_fit(ship.model(), gear_id)):
			continue
		var miles := Research.miles_to(ship.docked_at, Research.end_of(site_id))
		if miles == INF or miles > ship.range_nm():
			continue
		out.append({id = site_id, miles = miles, done = Research.is_done(GameState.company, site_id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.miles < b.miles if a.done == b.done else not a.done)
	return out


## Ports to move a ship to: its company's HQ and hubs, then the nearest others within its range.
func _move_ports(ship: Ship) -> Array:
	var out := []
	for hub in GameState.hubs:
		if hub.port_id != ship.docked_at:
			out.append(hub.port_id)
	var near := []
	for port: Dictionary in GameData.ports:
		var id := str(port.id)
		if id == ship.docked_at or out.has(id):
			continue
		var miles := GameData.distance_nm(ship.docked_at, id)
		if miles < ship.range_nm():
			near.append([miles, id])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in near.slice(0, MOVE_PORTS):
		out.append(entry[1])
	return out


func _gear_detail(ship: Ship) -> void:
	if ship == null:
		return
	var head := Label.new()
	head.theme_type_variation = &"HeaderLabel"
	head.text = "%s's gear" % ship.name
	_detail.add_child(head)
	var model := ship.model()
	_detail.add_child(_dim("%d of %d slots used. Gear is fitted in port; taking it off gives back half what it cost." % [ship.research_gear.size(), Research.slots_of(model)]))
	for info: Dictionary in Research.gear_list():
		var gear_id := str(info.id)
		if not Research.can_fit(model, gear_id):
			continue
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanel"
		var box := VBoxContainer.new()
		card.add_child(box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var name := Label.new()
		name.text = "%s%s" % ["✓ " if ship.research_gear.has(gear_id) else "", info.name]
		name.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(name)
		var button := Button.new()
		if ship.research_gear.has(gear_id):
			button.text = "Take off (+%s)" % Fmt.money(roundi(Research.gear_cost(model, gear_id) * Research.GEAR_REFUND))
			button.disabled = not ship.is_docked() or ship.job_phase != Ship.JOB_NONE
			button.pressed.connect(func() -> void:
				GameState.remove_gear(ship, gear_id)
				_dirty = true)
		else:
			button.text = "Fit (%s)" % Fmt.money(Research.gear_cost(model, gear_id))
			var error := GameState.research.fit_error(GameState.company, ship, gear_id)
			button.disabled = not error.is_empty()
			button.tooltip_text = error
			button.pressed.connect(func() -> void:
				GameState.fit_gear(ship, gear_id)
				_dirty = true)
		row.add_child(button)
		box.add_child(row)
		box.add_child(_dim(str(info.get("blurb", ""))))
		_detail.add_child(card)


# --- The Atlas ---------------------------------------------------------------------------------

func _atlas_list() -> void:
	for info: Dictionary in Research.categories():
		var counts := Research.progress(GameState.company, info.id)
		var step := Research.perk_step(GameState.company, info.id)
		_list.add_child(_list_button("cat:" + str(info.id), "%s\n%d of %d done%s" % [info.name, counts[0], counts[1], (" · perk " + "★".repeat(step)) if step > 0 else ""]))
	if place.is_empty():
		place = "cat:" + str(Research.categories()[0].id)


func _category_detail(category_id: String) -> void:
	var info := Research.category(category_id)
	var who := GameState.company
	var head := Label.new()
	head.theme_type_variation = &"HeaderLabel"
	head.text = str(info.get("name", category_id))
	head.add_theme_color_override(&"font_color", Color.from_string(str(info.get("color", "#ffffff")), Color.WHITE).lightened(0.3))
	_detail.add_child(head)
	var counts := Research.progress(who, category_id)
	var step := Research.perk_step(who, category_id)
	var perk: Dictionary = info.get("perk", {})
	var thresholds: Array = Research.setting("perk_steps", [25, 50, 100])
	var steps := PackedStringArray()
	for i in (perk.get("steps", []) as Array).size():
		var value := float(perk.steps[i])
		steps.append("%s%d%%: %s%d%%" % ["✓ " if step > i else "", int(thresholds[i]), "+" if value >= 0 else "−", absi(roundi(value * 100.0))])
	_detail.add_child(_text("%d of %d done. Perk, %s: %s." % [counts[0], counts[1], str(perk.get("name", "")).to_lower(), " · ".join(steps)]))
	_detail.add_child(_dim(str(perk.get("text", "")).replace("{p}", "the share above")))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 4)
	_detail.add_child(grid)
	var research: Research = GameState.research
	for site_id: String in Research.site_ids():
		var site := Research.site(site_id)
		if str(site.category) != category_id:
			continue
		var known := Research.is_known(who, site_id)
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.x = 300
		button.add_theme_font_size_override(&"font_size", FONT_SIZE - 1)
		if known:
			var mark := "✓ " if Research.is_done(who, site_id) else ""
			if research.firsts.get(site_id, -1) == GameState.all_companies().find(who):
				mark = "★ "
			button.text = "%s%s · %s m" % [mark, site.name, Fmt.thousands(int(site.depth_m))]
		else:
			button.text = "? Uncharted site"
			button.tooltip_text = "Somewhere in a search area on the map: a sonar ship working nearby, a site done nearby or a contract will reveal it."
		button.pressed.connect(func() -> void:
			place = "site:" + site_id
			_dirty = true)
		grid.add_child(button)


func _site_detail(site_id: String) -> void:
	var site := Research.site(site_id)
	if site.is_empty():
		return
	var who := GameState.company
	var known := Research.is_known(who, site_id)
	var research: Research = GameState.research
	var head := Label.new()
	head.theme_type_variation = &"HeaderLabel"
	head.text = str(site.name) if known else "Uncharted site"
	_detail.add_child(head)
	var info := Research.category(str(site.category))
	var art := SiteArt.new(site_id, not known)
	art.custom_minimum_size = Vector2(460, 200)
	_detail.add_child(art)
	if not known:
		_detail.add_child(_text("%s: something lies in this search area. A sonar ship working nearby, a site done nearby or a contract will reveal it." % info.get("name", "")))
		_detail.add_child(_map_button("", Research.hint_lonlat(site_id)))
		return
	_detail.add_child(_dim("%s · %s m down · %s" % [info.get("name", ""), Fmt.thousands(int(site.depth_m)), site.get("when", "")]))
	_detail.add_child(_text(str(site.get("fact", ""))))
	_detail.add_child(_text("Needs: %s fitted · %s days on station · difficulty %s" % [_gear_names(site.needs), Fmt.decimal(float(site.days), 1), "●".repeat(int(site.get("difficulty", 1)))]))
	var all := GameState.all_companies()
	if research.firsts.has(site_id):
		var first_index := int(research.firsts[site_id])
		var first_name: String = all[first_index].name if first_index >= 0 and first_index < all.size() else "a company"
		_detail.add_child(_dim("First discovered by %s." % ("you" if first_index == all.find(who) else first_name)))
	else:
		_detail.add_child(_dim("No company has been yet: the first earns half as many research points again."))
	if Research.is_done(who, site_id):
		var entry: Dictionary = (Research.record_of(who).done as Dictionary)[site_id]
		var by := str(entry.get("ship", ""))
		_detail.add_child(_text("✓ Done%s." % ((" by " + by) if not by.is_empty() else "")))
	if not Research.reachable(Research.end_of(site_id)):
		_detail.add_child(_dim("No lanes laid out to it yet."))
	_detail.add_child(_map_button(Research.end_of(site_id)))


# --- Bits --------------------------------------------------------------------------------------

# --- Technology (Technology, DESIGN M5) -----------------------------------------------------------

func _tech_list() -> void:
	var who := GameState.company
	var tech: Technology = GameState.technology
	var plan: Dictionary = who.rnd
	_list.add_child(_list_button("own", "Your own R&D\n%s" % ("working on %s (%d%%)" % [str(Technology.tech(str(plan.tech)).get("name", "")), roundi(100.0 * float(plan.get("progress", 0.0)) / tech.rnd_cost(str(plan.tech)))] if not str(plan.get("tech", "")).is_empty() else "nothing chosen · %d points banked" % roundi(who.research_points))))
	for branch: String in Technology.branches():
		var head := Label.new()
		head.theme_type_variation = &"DimLabel"
		head.text = str(Technology.branches()[branch])
		_list.add_child(head)
		for each: Dictionary in Technology.techs():
			if str(each.branch) != branch:
				continue
			var state := tech.standing(who, str(each.id))
			var mark: String = {held = "✓ ", licence = "", early = "★ ", future = "· "}[str(state.how)]
			var note: String = {held = "held" + (" (yours alone)" if tech.exclusive(who, str(each.id)) else ""), licence = "licence %s" % Fmt.money_short(int(state.price)), early = "early offer %s" % Fmt.money_short(int(state.price)), future = "expected %d" % int(each.year)}[str(state.how)]
			_list.add_child(_list_button("tech:" + str(each.id), "%s%s (tier %d)\n%s" % [mark, each.name, int(each.tier), note]))
	var head := Label.new()
	head.theme_type_variation = &"DimLabel"
	head.text = "R&D companies"
	_list.add_child(head)
	for info: Dictionary in Technology.companies():
		_list.add_child(_list_button("rnd:" + str(info.id), "%s\n%s · %s · likes you %d" % [info.name, GameData.port_name(str(info.port)), str(Technology.branches()[str(info.branch)]), roundi(tech.liking(who, str(info.id)))]))
	if place.is_empty():
		place = "own"


func _tech_detail(tech_id: String) -> void:
	var each := Technology.tech(tech_id)
	if each.is_empty():
		return
	var who := GameState.company
	var tech: Technology = GameState.technology
	var state := tech.standing(who, tech_id)
	_detail.add_child(_heading("%s (%s, tier %d)" % [str(each.name), str(Technology.branches()[str(each.branch)]), int(each.tier)]))
	_detail.add_child(_text(str(each.get("text", ""))))
	if each.has("perk"):
		_detail.add_child(_text("Perk, fleet-wide the moment you hold it: %s." % EventCard._perk_text(each.perk)))
	else:
		var upgrade: Dictionary = each.upgrade
		_detail.add_child(_text("Upgrade for the %s, fitted in drydock ship by ship (%d%% of a ship's list price): %s. New ships you order come with it." % [str(ShipParts.part(str(upgrade.part)).get("name", upgrade.part)).to_lower(), roundi(float(upgrade.cost) * 100.0), DrydockPopup._effects_text(upgrade.get("effects", {}))]))
	var by: Dictionary = Technology.rnd(str(each.by))
	_detail.add_child(_dim("Developed by %s (%s), expected about %d.%s" % [str(by.get("name", "")), GameData.port_name(str(by.get("port", ""))), int(each.year), " Published %s." % Fmt.calendar_short(int(tech.published[tech_id])) if tech.published.has(tech_id) else ""]))
	match str(state.how):
		"held":
			var entry: Dictionary = who.techs[tech_id]
			_detail.add_child(_text("Held since %s (%s)%s." % [Fmt.calendar_short(int(entry.since)), str(entry.how), "; yours alone till %s, with royalties" % Fmt.calendar_short(int(entry.exclusive_until)) if tech.exclusive(who, tech_id) else ""]))
		"licence", "early":
			var button := Button.new()
			button.text = "License for %s%s" % [Fmt.money(int(state.price)), " (early, a friend's price)" if str(state.how) == "early" else ""]
			var error := tech.license_error(who, tech_id)
			button.disabled = not error.is_empty()
			button.tooltip_text = error
			button.pressed.connect(func() -> void: GameState.license_tech(tech_id))
			_detail.add_child(button)
			_detail.add_child(_dim("The fee is a share of your fleet at list price (tier %d: %s%%), at least %s; 30%% off from an R&D company that likes you (60 or more)." % [int(each.tier), Fmt.decimal(float((Technology.setting("licence", [0.004, 0.008, 0.015]) as Array)[int(each.tier) - 1]) * 100.0, 1), Fmt.money(int((Technology.setting("floor", [250000, 500000, 1000000]) as Array)[int(each.tier) - 1]))]))
		"future":
			_detail.add_child(_dim("Not published yet. An R&D company that likes you (60 or more) offers its techs a year early at 30%% off; or develop it yourself first and hold it alone."))
	if str(state.how) != "held":
		var own := Button.new()
		var plan: Dictionary = who.rnd
		var chosen := str(plan.get("tech", "")) == tech_id
		own.text = "Being developed by your R&D" if chosen else "Develop it yourself (%d research points)" % roundi(tech.rnd_cost(tech_id))
		own.disabled = chosen
		own.pressed.connect(func() -> void:
			GameState.set_rnd(tech_id, int(plan.get("budget", 0)))
			place = "own"
			_dirty = true)
		_detail.add_child(own)


func _rnd_detail(rnd_id: String) -> void:
	var info := Technology.rnd(rnd_id)
	if info.is_empty():
		return
	var who := GameState.company
	var tech: Technology = GameState.technology
	_detail.add_child(_heading(str(info.name)))
	_detail.add_child(_text("%s, based at %s. Thinks of you: %d of 100 (%s)." % [str(Technology.branches()[str(info.branch)]), GameData.port_name(str(info.port)), roundi(tech.liking(who, rnd_id)), "a friend: early offers and 30% off" if tech.liking(who, rnd_id) >= float(Technology.setting("early_at", 60)) else "liking grows by licensing their techs, fitting their upgrades, trading at their port and selling them your survey data"]))
	var sell := Button.new()
	sell.text = "Sell survey data: %d research points for %s" % [int(Technology.setting("data_points", 100)), Fmt.money(int(Technology.setting("data_price", 600000)))]
	var error := tech.sell_data_error(who, rnd_id)
	sell.disabled = not error.is_empty()
	sell.tooltip_text = error if not error.is_empty() else "Liking +%d." % int(Technology.setting("like_data", 10))
	sell.pressed.connect(func() -> void: GameState.sell_research_data(rnd_id))
	_detail.add_child(sell)
	_detail.add_child(_heading("Their technologies"))
	for each: Dictionary in Technology.techs():
		if str(each.by) != rnd_id:
			continue
		var state := tech.standing(who, str(each.id))
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override(&"font_size", FONT_SIZE - 1)
		button.text = "%s (tier %d) · %s" % [str(each.name), int(each.tier), str(state.how) if str(state.how) != "future" else "expected %d" % int(each.year)]
		button.pressed.connect(func() -> void:
			place = "tech:" + str(each.id)
			_dirty = true)
		_detail.add_child(button)


func _own_rnd_detail() -> void:
	var who := GameState.company
	var tech: Technology = GameState.technology
	var plan: Dictionary = who.rnd
	_detail.add_child(_heading("Your own R&D"))
	_detail.add_child(_text("One technology at a time: your banked research points (%d; a quarter drawn each month) and a monthly budget (%s a point, more per dollar with a CTO strong in Engineering and a Technology centre at a hub: x%s now) progress it. Finish before the world publishes it and it is yours alone for two years, rivals paying royalties." % [roundi(who.research_points), Fmt.money(int(Technology.setting("point_cost", 20000))), Fmt.decimal(tech.monthly_points(who) / maxf(float(plan.get("budget", 0)) / float(Technology.setting("point_cost", 20000)), 0.001) if int(plan.get("budget", 0)) > 0 else 1.0 + People.bonus(who, "research"), 2)]))
	var chosen := str(plan.get("tech", ""))
	if chosen.is_empty():
		_detail.add_child(_dim("Nothing chosen: pick a technology on the left and press Develop it yourself."))
	else:
		var each := Technology.tech(chosen)
		var progress := float(plan.get("progress", 0.0))
		var cost := tech.rnd_cost(chosen)
		_detail.add_child(_text("Working on %s: %d of %d points (%d%%).%s" % [str(each.name), roundi(progress), roundi(cost), roundi(100.0 * progress / cost), " The world has it already: finishing saves the licence." if tech.published.has(chosen) else " Not published yet: finish first and hold it alone."]))
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = cost
		bar.value = progress
		bar.custom_minimum_size = Vector2(320.0, 14.0)
		_detail.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var budget_label := Label.new()
	budget_label.text = "Monthly budget"
	budget_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	row.add_child(budget_label)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 50000000
	spin.step = 100000
	spin.prefix = "$"
	spin.custom_minimum_size.x = 180.0
	spin.size_flags_vertical = SIZE_SHRINK_CENTER
	spin.value = int(plan.get("budget", 0))
	spin.value_changed.connect(func(v: float) -> void: GameState.set_rnd(chosen, int(v)))
	row.add_child(spin)
	var rate := Label.new()
	rate.theme_type_variation = &"DimLabel"
	rate.add_theme_font_size_override(&"font_size", FONT_SIZE - 1)
	rate.text = "about %d points a month" % roundi(tech.monthly_points(who))
	row.add_child(rate)
	_detail.add_child(row)
	if not chosen.is_empty():
		var stop := Button.new()
		stop.text = "Stop (the work so far is lost)"
		stop.pressed.connect(func() -> void: GameState.set_rnd("", int(plan.get("budget", 0))))
		_detail.add_child(stop)
	var held := who.techs.keys()
	if not held.is_empty():
		_detail.add_child(_heading("Held"))
		_detail.add_child(_dim(", ".join(PackedStringArray(held.map(func(id: String) -> String: return str(Technology.tech(id).get("name", id)))))))


func _gear_names(ids: Array) -> String:
	return ", ".join(PackedStringArray(ids.map(func(gear_id: String) -> String: return Research.gear_name(gear_id))))


## A button that closes the page and turns the map to a target (or a place).
func _map_button(end: String, lon_lat := Vector2.INF) -> Button:
	var button := Button.new()
	button.text = "Show on the map"
	button.size_flags_horizontal = SIZE_SHRINK_BEGIN
	var where := lon_lat if lon_lat != Vector2.INF else Research.target_lonlat(end)
	button.pressed.connect(func() -> void: GameRoot.find(self).show_on_map(where))
	return button


func _list_button(key: String, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_pressed = key == place
	button.add_theme_font_size_override(&"font_size", FONT_SIZE - 1)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(func() -> void:
		place = key
		_dirty = true)
	return button


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", FONT_SIZE + 2)
	return label


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dim(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = &"DimLabel"
	label.add_theme_font_size_override(&"font_size", FONT_SIZE - 1)
	return label
