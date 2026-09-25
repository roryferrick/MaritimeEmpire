extends Control
## Prices for one commodity at a time (picked at the top): the cheapest ports to
## buy it, the most expensive to sell it, and the best trades between two ports,
## both anywhere and within SHORT_TRADE_NM (for small, short-range ships).
## Clicking a port shows it on the World map. Refreshes every few seconds while
## visible.

const REFRESH_SECONDS := 3.0
const LIST_SIZE := 10
## "Best short trades" only pairs ports at most this far apart by sea.
const SHORT_TRADE_NM := 800.0
const FONT_SIZE := 14

var _picker := OptionButton.new()
var _lists := GridContainer.new()
var _clock := 0.0


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
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	content.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Markets"
	header.add_child(title)
	for commodity: Dictionary in GameData.commodities:
		_picker.add_item("%s (per %s)" % [commodity.name, commodity.unit])
		_picker.set_item_metadata(_picker.item_count - 1, commodity.id)
	_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_picker.item_selected.connect(_refresh.unbind(1))
	header.add_child(_picker)
	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.text = "Buy prices include the %d%% spread. Prices drift slowly, and your own trades nudge them." % roundi(float(GameData.markets.get("spread", 0.0)) * 100.0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	_lists.columns = 2
	_lists.add_theme_constant_override(&"h_separation", 32)
	_lists.add_theme_constant_override(&"v_separation", 16)
	content.add_child(_lists)
	visibility_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	if not is_visible_in_tree() or _picker.item_count == 0:
		return
	for child in _lists.get_children():
		_lists.remove_child(child)
		child.queue_free()
	var commodity_id: String = _picker.get_selected_metadata()
	var market := GameState.market
	var buys := {}
	var sells := {}
	for port: Dictionary in GameData.ports:
		buys[port.id] = market.buy_price(port.id, commodity_id)
		sells[port.id] = market.sell_price(port.id, commodity_id)
	var cheapest: Array = buys.keys()
	cheapest.sort_custom(func(a: String, b: String) -> bool: return buys[a] < buys[b])
	var most_expensive: Array = sells.keys()
	most_expensive.sort_custom(func(a: String, b: String) -> bool: return sells[a] > sells[b])
	_add_list("Cheapest to buy", cheapest.slice(0, LIST_SIZE).map(func(id: String) -> Array:
		return [[id], Fmt.money(roundi(buys[id]))]))
	_add_list("Most expensive to sell", most_expensive.slice(0, LIST_SIZE).map(func(id: String) -> Array:
		return [[id], Fmt.money(roundi(sells[id]))]))
	var best := []
	var best_short := []
	var from_ports: Array = cheapest.slice(0, 40)
	for from: String in from_ports:
		for to: String in sells:
			var margin: float = sells[to] - buys[from]
			if to == from or margin <= 0.0:
				continue
			best.append([from, to, margin])
	for from: String in buys:
		for to: String in sells:
			var margin: float = sells[to] - buys[from]
			if to != from and margin > 0.0 and GameData.distance_nm(from, to) <= SHORT_TRADE_NM:
				best_short.append([from, to, margin])
	var by_margin := func(a: Array, b: Array) -> bool: return a[2] > b[2]
	best.sort_custom(by_margin)
	best_short.sort_custom(by_margin)
	_add_list("Best trades", best.slice(0, LIST_SIZE).map(_trade_row))
	_add_list("Best trades within %s nm" % Fmt.thousands(roundi(SHORT_TRADE_NM)), best_short.slice(0, LIST_SIZE).map(_trade_row))


func _trade_row(trade: Array) -> Array:
	var nm := GameData.distance_nm(trade[0], trade[1])
	return [[trade[0], trade[1]], "+%s a unit · %s nm" % [Fmt.money(roundi(trade[2])), Fmt.thousands(roundi(nm))]]


## A titled list of rows: [[port ids], text]. Each port is a button to it on the map.
func _add_list(title: String, rows: Array) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"DimLabel"
	box.add_child(heading)
	if rows.is_empty():
		var none := Label.new()
		none.text = "Nothing profitable right now"
		none.theme_type_variation = &"DimLabel"
		box.add_child(none)
	for row: Array in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 4)
		var ports: Array = row[0]
		for i in ports.size():
			if i > 0:
				line.add_child(_label("→"))
			var button := Button.new()
			button.flat = true
			button.text = "%s (%s)" % [GameData.port_name(ports[i]), GameData.port_region(ports[i]).get("name", "")] if ports.size() == 1 else GameData.port_name(ports[i])
			button.add_theme_font_size_override(&"font_size", FONT_SIZE)
			button.pressed.connect(func() -> void: GameRoot.find(self).show_port_on_map(ports[i]))
			line.add_child(button)
		var value := _label(row[1])
		value.theme_type_variation = &"GainLabel" if ports.size() > 1 else &""
		line.add_child(value)
		box.add_child(line)
	_lists.add_child(box)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return label
