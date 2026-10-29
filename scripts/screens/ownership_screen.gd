# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name OwnershipScreen
extends Control
## The Ownership page over the map (DESIGN_LIVING_WORLD.md M3): the share
## price and its history, the register (who holds what, and what they think of
## the CEO), the board's motions (a dividend, issuing or buying back shares,
## going public), the IPO as it runs (the bank, the terms, the roadshow, the
## listing), and the paper firms with their values and your stakes, a block to
## buy at a time. Refreshes as the ownership changes.

const FONT_SIZE := 14

var _body := VBoxContainer.new()
var _dividend := 0.1
var _issue_share := 0.1
var _ipo_share := 0.25
var _ipo_low := 0.0
var _ipo_high := 0.0
var _firm_sort := "value"
var _firms_shown := 15


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
	title.text = "Ownership"
	content.add_child(title)
	_body.add_theme_constant_override(&"separation", 14)
	content.add_child(_body)
	visibility_changed.connect(_refresh)
	GameState.ownership.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var company := GameState.company
	var own: Ownership = GameState.ownership
	var shares := own.ensure(company)
	_add_price(company, own, shares)
	_add_register(company, own, shares)
	_add_motions(company, own, shares)
	_add_ipo(company, own, shares)
	_add_firm_cards(company, own)
	_add_firms(company, own)


func _add_price(company: Company, own: Ownership, shares: Dictionary) -> void:
	var box := _card("%s a share · %s shares · %s" % [Fmt.money(roundi(own.price(company))), Fmt.thousands(int(shares.total)), "listed in %s" % str(shares.exchange) if bool(shares.listed) else "private"])
	box.add_child(_dim("The price is the company's value a share%s. Worth %s in all; you hold %d%%." % [", x the market's sentiment (%s now)" % Fmt.decimal(float(shares.sentiment), 2) if bool(shares.listed) else "",
		Fmt.money(roundi(own.price(company) * int(shares.total))), roundi(own.founder_share(company) * 100.0)]))
	var chart := LineChart.new(140.0)
	chart.as_ratio = false
	chart.reference = 0.0
	chart.series = PackedFloat32Array(shares.history)
	chart.labels = GameState.history.month_labels((shares.history as Array).size())
	chart.line_color = Color(0.6, 0.9, 0.6)
	box.add_child(chart)
	if float(shares.last_profit) != 0.0 or float(shares.expected) != 0.0:
		box.add_child(_dim("Last quarter's profit %s%s · dividend %d%% of profit" % [Fmt.money(roundi(float(shares.last_profit))), " · the market expects %s next" % Fmt.money(roundi(float(shares.expected))) if bool(shares.listed) else "", roundi(float(shares.dividend) * 100.0)]))
	_body.add_child(box.get_parent())


func _add_register(company: Company, own: Ownership, shares: Dictionary) -> void:
	var box := _card("The register and the board")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 18)
	for head: String in ["Holder", "Shares", "Stake", "Thinks of the CEO"]:
		grid.add_child(_cell(head, &"DimLabel"))
	for holder: Dictionary in shares.holders:
		var name := str(holder.name)
		if holder.has("character"):
			name += " (%s)" % str((holder.character as Dictionary).get("name", ""))
		grid.add_child(_cell(name))
		grid.add_child(_cell(Fmt.thousands(int(holder.count))))
		grid.add_child(_cell("%s%%" % Fmt.decimal(own.share_of(company, holder) * 100.0, 1)))
		var opinion := float(holder.opinion)
		grid.add_child(_cell("—" if holder.kind == "founder" else ("%s (%d)" % ["warm" if opinion > 20.0 else ("cool" if opinion < -20.0 else "neutral"), roundi(opinion)]), &"GainLabel" if opinion > 20.0 else (&"ErrorLabel" if opinion < -20.0 else &"")))
	box.add_child(grid)
	var members := own.board(company).filter(func(h: Dictionary) -> bool: return h.kind != "founder")
	box.add_child(_dim("The board is every holder of %d%% or more. Big moves (worth a tenth of the company or more, and always the IPO or new shares) need more than half the shares; you vote your own. Dividends please the board, losses and a falling price turn it; a board set against you can vote you out.%s" % [roundi(Ownership.BOARD_MIN * 100.0),
		"" if members.is_empty() else " Outside members: %s." % ", ".join(PackedStringArray(members.map(func(h: Dictionary) -> String: return str(h.name))))]))
	_body.add_child(box.get_parent())


func _add_motions(company: Company, own: Ownership, shares: Dictionary) -> void:
	var box := _card("Motions")
	var dividend := HBoxContainer.new()
	dividend.add_theme_constant_override(&"separation", 8)
	dividend.add_child(_text("Dividend: pay the holders"))
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 50
	spin.step = 5
	spin.suffix = "%"
	spin.value = roundi(_dividend * 100.0)
	spin.value_changed.connect(func(v: float) -> void: _dividend = v / 100.0)
	dividend.add_child(spin)
	dividend.add_child(_text("of each quarter's profit"))
	dividend.add_child(_flat_button("Propose", func() -> void: GameState.propose_motion("dividend", {share = _dividend})))
	box.add_child(dividend)
	var issue := HBoxContainer.new()
	issue.add_theme_constant_override(&"separation", 8)
	issue.add_child(_text("Sell new shares to a fund:"))
	var issue_spin := SpinBox.new()
	issue_spin.min_value = 5
	issue_spin.max_value = 40
	issue_spin.step = 5
	issue_spin.suffix = "%"
	issue_spin.value = roundi(_issue_share * 100.0)
	issue_spin.value_changed.connect(func(v: float) -> void: _issue_share = v / 100.0)
	issue.add_child(issue_spin)
	issue.add_child(_dim("of the shares, at today's price (about %s in; everyone diluted)" % Fmt.money_short(roundi(own.price(company) * int(shares.total) * _issue_share))))
	issue.add_child(_flat_button("Propose", func() -> void: GameState.propose_motion("issue", {share = _issue_share})))
	box.add_child(issue)
	var outside := 1.0 - own.founder_share(company)
	if outside > 0.001:
		var back := HBoxContainer.new()
		back.add_theme_constant_override(&"separation", 8)
		back.add_child(_text("Buy back 5%% of the shares from the outside holders (about %s)" % Fmt.money_short(roundi(own.price(company) * int(shares.total) * 0.05))))
		back.add_child(_flat_button("Propose", func() -> void: GameState.propose_motion("buyback", {share = 0.05})))
		box.add_child(back)
	_body.add_child(box.get_parent())


func _add_ipo(company: Company, own: Ownership, shares: Dictionary) -> void:
	var box := _card("Going public")
	if bool(shares.listed):
		box.add_child(_dim("Listed in %s. Each quarter the market measures your profit against what it expected; beat it and the price climbs, miss and it falls." % str(shares.exchange)))
		_body.add_child(box.get_parent())
		return
	var state := own.ipo(company)
	match str(state.get("step", "")):
		"":
			box.add_child(_dim("An IPO sells new shares to the public: money in, your stake diluted, a share price the market sets. The board votes first; then a bank, the terms, a roadshow and listing day."))
			box.add_child(_flat_button("Propose going public", func() -> void: GameState.propose_motion("ipo", {})))
		"bank":
			box.add_child(_text("Pick a bank to take you public:"))
			for id: String in Ownership.BANK_ORDER:
				var bank: Dictionary = Ownership.BANKS[id]
				var row := HBoxContainer.new()
				row.add_theme_constant_override(&"separation", 8)
				var can := id in own.banks_for(company)
				var choose := _flat_button(str(bank.name), func() -> void: GameState.ipo_choose_bank(id))
				choose.disabled = not can
				row.add_child(choose)
				row.add_child(_dim("fee %d%% of what's raised · reach %s · %s" % [roundi(float(bank.fee) * 100.0), "+%d%% demand" % roundi(float(bank.reach) * 100.0) if float(bank.reach) > 0.0 else "none", "takes you" if can else "only companies worth %s or more" % Fmt.money_short(roundi(float(bank.min_value)))]))
				box.add_child(row)
		"terms":
			var mid := float(state.valuation) / float(shares.total)
			if _ipo_low <= 0.0:
				_ipo_low = snappedf(mid * (1.0 - Ownership.RANGE_WIDTH), 0.01)
				_ipo_high = snappedf(mid * (1.0 + Ownership.RANGE_WIDTH), 0.01)
			box.add_child(_text("%s values the company at %s (%s a share). Set the price range and how much to sell:" % [str(Ownership.BANKS[state.bank].name), Fmt.money(roundi(float(state.valuation))), Fmt.money(roundi(mid))]))
			var row := HBoxContainer.new()
			row.add_theme_constant_override(&"separation", 8)
			var low := SpinBox.new()
			low.min_value = snappedf(mid * 0.7, 0.01)
			low.max_value = snappedf(mid, 0.01)
			low.step = 0.01 if mid < 10.0 else 1.0
			low.prefix = "$"
			low.value = _ipo_low
			low.value_changed.connect(func(v: float) -> void: _ipo_low = v)
			row.add_child(_text("from"))
			row.add_child(low)
			var high := SpinBox.new()
			high.min_value = snappedf(mid, 0.01)
			high.max_value = snappedf(mid * 1.3, 0.01)
			high.step = low.step
			high.prefix = "$"
			high.value = _ipo_high
			high.value_changed.connect(func(v: float) -> void: _ipo_high = v)
			row.add_child(_text("to"))
			row.add_child(high)
			var share := SpinBox.new()
			share.min_value = roundi(float(Ownership.IPO_SHARE[0]) * 100.0)
			share.max_value = roundi(float(Ownership.IPO_SHARE[1]) * 100.0)
			share.step = 1
			share.suffix = "%"
			share.value = roundi(_ipo_share * 100.0)
			share.value_changed.connect(func(v: float) -> void: _ipo_share = v / 100.0)
			row.add_child(_text("selling"))
			row.add_child(share)
			row.add_child(_dim("of the company (new shares)"))
			box.add_child(row)
			box.add_child(_dim("A higher range raises more if demand holds, and sinks the listing if it doesn't."))
			box.add_child(_flat_button("Start the roadshow", func() -> void: GameState.ipo_set_terms(_ipo_low, _ipo_high, _ipo_share)))
		"roadshow":
			box.add_child(_text("The roadshow: %d of %d meetings done, demand %d%%. The next investor's question comes as a card." % [int(state.meetings), Ownership.ROADSHOW_MEETINGS, roundi(float(state.demand) * 100.0)]))
		"listing":
			box.add_child(_text("Listing day is %s in %s. Demand stands at %d%%." % [Fmt.calendar_short(int(state.listing_day)), str(state.exchange), roundi(float(state.demand) * 100.0)]))
	_body.add_child(box.get_parent())


## A card for each firm the company controls: its figures, its focus and trade groups, the dividend, its orders.
func _add_firm_cards(company: Company, own: Ownership) -> void:
	var firms: ShippingFirms = GameState.firms
	for key: String in company.stakes:
		var i := int(key)
		if own.stake_in(company, i) < Ownership.CONTROL:
			continue
		var firm: Dictionary = firms.firms[i]
		var plan := own.ensure_plan(company, i)
		var box := _card("%s (yours: %d%%)" % [str(firm.name), roundi(own.stake_in(company, i) * 100.0)])
		var hulls := 0
		for model_id: String in firm.fleet:
			hulls += int(firm.fleet[model_id])
		box.add_child(_dim("Based in %s. %d ships on the books (about %s hulls), %d at sea now, %d sailings last month. Cash %s; earned %s last month; worth %s." % [GameData.port_name(str(firm.home)), hulls, Fmt.thousands(roundi(hulls * ShippingFirms.CONVOY)), firms.voyages_of(i), int(firm.get("month_voyages", 0)), Fmt.money(roundi(float(firm.money))), Fmt.money(roundi(float(firm.get("last_month_earned", 0.0)))), "$" + Fmt.short(own.firm_value(i))]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		row.add_child(_text("Focus"))
		var focus := OptionButton.new()
		focus.add_item("World-wide")
		focus.add_item("Home: voyages out of %s only" % str(WorldEconomy.country(str(firm.country)).get("name", firm.country)))
		focus.select(1 if str(plan.focus) == "home" else 0)
		focus.item_selected.connect(func(index: int) -> void: GameState.set_firm_plan(i, "focus", "home" if index == 1 else "world"))
		row.add_child(focus)
		row.add_child(_text("Dividend"))
		var dividend := SpinBox.new()
		dividend.min_value = 0
		dividend.max_value = 100
		dividend.step = 5
		dividend.suffix = "%"
		dividend.value = roundi(float(plan.dividend) * 100.0)
		dividend.value_changed.connect(func(v: float) -> void: GameState.set_firm_plan(i, "dividend", v / 100.0))
		row.add_child(dividend)
		row.add_child(_dim("of each month's earnings to you; the rest builds its cash"))
		box.add_child(row)
		var lines := {}
		for model_id: String in firm.fleet:
			lines[str(GameData.get_ship_model(model_id).get("category", ""))] = true
		if lines.size() > 1:
			var groups := HBoxContainer.new()
			groups.add_theme_constant_override(&"separation", 8)
			groups.add_child(_text("Trades"))
			for line: String in lines:
				var tick := CheckBox.new()
				tick.text = People.group_name(line)
				tick.add_theme_font_size_override(&"font_size", FONT_SIZE)
				tick.button_pressed = (plan.groups as Array).is_empty() or line in plan.groups
				tick.toggled.connect(func(_on: bool) -> void:
					var chosen := []
					for child in groups.get_children():
						if child is CheckBox and (child as CheckBox).button_pressed:
							chosen.append(child.get_meta(&"line"))
					GameState.set_firm_plan(i, "groups", [] if chosen.size() == lines.size() else chosen))
				tick.set_meta(&"line", line)
				groups.add_child(tick)
			box.add_child(groups)
		var orders: Array = plan.orders
		var order_row := HBoxContainer.new()
		order_row.add_theme_constant_override(&"separation", 8)
		if orders.is_empty():
			order_row.add_child(_dim("No ship on order. It asks you when it has the cash for one."))
		else:
			order_row.add_child(_dim("On order: " + ", ".join(PackedStringArray(orders.map(func(o: Dictionary) -> String: return "%s from %s, due %s" % [str(GameData.get_ship_model(str(o.model)).get("name", "")), str(GameState.shipyards.yard(str(o.yard)).get("name", "")), Fmt.calendar_short(int(o.due))])))))
		order_row.add_child(_flat_button("Order a ship now", func() -> void: GameState.request_firm_order(i)))
		box.add_child(order_row)
		_body.add_child(box.get_parent())


func _add_firms(company: Company, own: Ownership) -> void:
	var box := _card("The shipping firms")
	box.add_child(_dim("A firm is worth its fleet at list price plus four years of its earnings so far. A block is %d%% of it, dearer with each block you hold (and dearer still from a firm you poached people from); past %d%% you control it (its ships sail in your colour and you take its earnings each month), and you run it from its card above." % [roundi(Ownership.BLOCK * 100.0), roundi(Ownership.CONTROL * 100.0)]))
	var firms: ShippingFirms = GameState.firms
	var order := range(firms.firms.size()).filter(func(k: int) -> bool: return not FirmLife.is_dead(firms.firms[k]))
	order.sort_custom(func(a: int, b: int) -> bool:
		if own.stake_in(company, a) != own.stake_in(company, b):
			return own.stake_in(company, a) > own.stake_in(company, b)
		return own.firm_value(a) > own.firm_value(b))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 2)
	for head: String in ["Firm", "Based in", "Worth", "Your stake", ""]:
		grid.add_child(_cell(head, &"DimLabel"))
	for i: int in order.slice(0, _firms_shown):
		var firm: Dictionary = firms.firms[i]
		var sore := People.soreness(company, i)
		var name_cell := _cell(str(firm.name) + (" (sore)" if sore > 0.0 else ""), &"ErrorLabel" if sore > 0.0 else &"")
		name_cell.tooltip_text = "%s: %s. %s%s" % [str((firm.get("ceo", {}) as Dictionary).get("name", "Its chief")), FirmLife.leaning_name(firm).to_lower(), str(FirmLife.LEANING_TEXT.get(FirmLife.leaning(firm), "")), " A stubborn leadership: it will not sell." if FirmLife.stubborn(firm) else ""] + (" You poached from them." if sore > 0.0 else "")
		name_cell.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(name_cell)
		grid.add_child(_cell("%s · %s" % [str(WorldEconomy.country(str(firm.country)).get("name", firm.country)), FirmLife.leaning_name(firm)]))
		grid.add_child(_cell("$" + Fmt.short(own.firm_value(i))))
		var stake := own.stake_in(company, i)
		grid.add_child(_cell("%d%%%s" % [roundi(stake * 100.0), " (control)" if stake >= Ownership.CONTROL else ""], &"GainLabel" if stake >= Ownership.CONTROL else &""))
		var buy := Button.new()
		buy.text = "Buy %d%% for %s" % [roundi(Ownership.BLOCK * 100.0), Fmt.money_short(own.block_cost(company, i))]
		buy.add_theme_font_size_override(&"font_size", FONT_SIZE)
		var error := own.buy_block_error(company, i)
		buy.disabled = not error.is_empty()
		buy.tooltip_text = error
		buy.pressed.connect(func() -> void: GameState.propose_motion("buy_block", {firm = i}))
		grid.add_child(buy)
	box.add_child(grid)
	if firms.firms.size() > _firms_shown:
		box.add_child(_flat_button("Show more firms", func() -> void:
			_firms_shown += 15
			_refresh()))
	_body.add_child(box.get_parent())


# --- Bits --------------------------------------------------------------------------------------

func _card(title_text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
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


func _cell(text: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return label


func _flat_button(text: String, then: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	button.pressed.connect(then)
	return button
