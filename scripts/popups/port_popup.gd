class_name PortPopup
extends AnchoredPopup
## Shows a port's name and size (how far through its band it is, which way
## it's going and what the size does), its HQ or hub (level, XP and upgrade
## tree) or a button to found a hub there when one is available, and the
## player's ships docked there with their bars, and its market: each
## commodity's buy and sell price, green where it's cheap compared with the
## world average and red where expensive.

const SHIP_BARS_WIDTH := 80.0
## Founding a hub takes a second click within this many seconds (it's permanent).
const BUILD_CONFIRM_SECONDS := 3.0
const REFRESH_SECONDS := 1.0
## The market table: its text size, and how far below or above a commodity's
## world average price counts as cheap (green) or expensive (red).
const MARKET_FONT_SIZE := 13
const MARKET_CHEAP := 0.8
const MARKET_EXPENSIVE := 1.25

## Set before adding to the tree.
var port_id := ""

var _build_confirm_until := 0.0
var _xp_label: Label = null
var _clock := 0.0
var _size_label := Label.new()
var _size_bar := ProgressBar.new()
var _size_effects := Label.new()


func _ready() -> void:
	super()
	_build_size()
	%CloseButton.pressed.connect(queue_free)
	GameState.ships_changed.connect(_refresh_ships)
	GameState.ship_changed.connect(_refresh_ships.unbind(1))
	GameState.hubs_changed.connect(_refresh_hub)
	GameState.company_leveled.connect(_refresh_hub.unbind(2))
	_refresh_hub()
	_refresh_ships()
	_refresh_market()


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_update_hub_xp()
		_update_size()
		_refresh_market()


## The port's size: how far through its band it is and which way it's going,
## what the size does here, and which ships are too big for it.
func _build_size() -> void:
	_size_label.theme_type_variation = &"DimLabel"
	%SizeBox.add_child(_size_label)
	_size_bar.show_percentage = false
	_size_bar.custom_minimum_size.y = 8.0
	_size_bar.max_value = 1.0
	%SizeBox.add_child(_size_bar)
	_size_effects.theme_type_variation = &"DimLabel"
	_size_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%SizeBox.add_child(_size_effects)
	_update_size()


func _update_size() -> void:
	var sizes := GameState.port_sizes
	var here := sizes.size(port_id)
	var low := sizes.band_min(sizes.band(port_id))
	var high := sizes.next_band_min(port_id)
	%TitleLabel.text = "%s · %s" % [GameData.port_name(port_id), GameState.port_size_text(port_id)]
	var rate := sizes.rate(port_id)
	var trend := "steady"
	if rate > 0.0:
		trend = "growing (+%s an hour)" % Fmt.decimal(rate, 1)
	elif rate < 0.0:
		trend = "shrinking (%s an hour)" % Fmt.decimal(rate, 1)
	var next := sizes.band_of(high)
	var target := "%s at %d" % [next.capitalize(), roundi(high)] if not next.is_empty() and high <= 100.0 else "the largest size"
	_size_label.text = "Size %s of 100, %s · next: %s" % [Fmt.decimal(here, 1), trend, target]
	_size_bar.value = clampf((here - low) / (high - low), 0.0, 1.0)
	var costs := roundi((sizes.cost_factor(port_id) - 1.0) * 100.0)
	var lines := PackedStringArray([
		"Fuel & repairs %s%d%% · your trades move prices %sx" % ["+" if costs > 0 else "", costs, Fmt.decimal(sizes.impact_factor(port_id), 2)]])
	var too_big := PackedStringArray()
	for band: String in ["medium", "large"]:
		if here < sizes.band_min(band):
			too_big.append("ships needing %s ports" % band.capitalize())
	lines.append("Too small for %s" % " or ".join(too_big) if not too_big.is_empty() else "Every ship can dock here")
	_size_effects.text = "\n".join(lines)


func _refresh_hub() -> void:
	for child in %HubBox.get_children():
		%HubBox.remove_child(child)
		child.queue_free()
	_xp_label = null
	var hub := GameState.hub_at(port_id)
	if hub:
		_show_hub(hub)
	elif GameState.hubs_available() > 0:
		var build := Button.new()
		build.text = "Build a hub here (%d available)" % GameState.hubs_available()
		build.tooltip_text = "Hubs level up from deliveries unloaded here and boost every ship that docks. It's permanent."
		build.pressed.connect(_on_build_pressed.bind(build))
		%HubBox.add_child(build)
	%HubBox.visible = %HubBox.get_child_count() > 0
	%HubSeparator.visible = %HubBox.visible
	reset_size.call_deferred()


func _show_hub(hub: Hub) -> void:
	var title := Label.new()
	title.text = "%s · level %d" % ["Headquarters" if hub.is_hq else "Hub", hub.level]
	%HubBox.add_child(title)
	_xp_label = Label.new()
	_xp_label.theme_type_variation = &"DimLabel"
	%HubBox.add_child(_xp_label)
	_update_hub_xp()
	var company := Label.new()
	company.theme_type_variation = &"GainLabel"
	company.text = hub.company_xp_text()
	%HubBox.add_child(company)
	%HubBox.add_child(HubTree.new(hub))
	var points := hub.upgrade_points()
	if points > 0:
		var hint := Label.new()
		hint.theme_type_variation = &"GainLabel"
		hint.text = "%d upgrade point%s to spend" % [points, "" if points == 1 else "s"]
		%HubBox.add_child(hint)


func _update_hub_xp() -> void:
	if not is_instance_valid(_xp_label):
		return
	var hub := GameState.hub_at(port_id)
	var cost := GameState.hub_level_cost(hub)
	_xp_label.text = "Max level" if cost <= 0.0 else "%s / %s XP to level %d" % [
		Fmt.thousands(floori(hub.xp)), Fmt.thousands(ceili(cost)), hub.level + 1]


## First click asks for confirmation; a second click founds the hub.
func _on_build_pressed(button: Button) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _build_confirm_until:
		GameState.build_hub(port_id)
		return
	_build_confirm_until = now + BUILD_CONFIRM_SECONDS
	button.text = "Build a hub at %s? It's permanent" % GameData.port_name(port_id)
	reset_size.call_deferred()


func _refresh_ships() -> void:
	for child in %ShipList.get_children():
		%ShipList.remove_child(child)
		child.queue_free()
	var count := 0
	for ship in GameState.ships:
		if ship.docked_at != port_id:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var button := Button.new()
		button.text = ship.name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_open_ship.bind(ship))
		row.add_child(button)
		var bars := ShipBars.new(ship, true)
		bars.custom_minimum_size.x = SHIP_BARS_WIDTH
		bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bars)
		%ShipList.add_child(row)
		count += 1
	%NoShipsLabel.visible = count == 0
	reset_size.call_deferred()


func _open_ship(ship: Ship) -> void:
	PopupHost.find(self).show_ship(ship, follow)


## Each commodity's buy and sell price here, colored against its world average,
## in two columns of commodities.
func _refresh_market() -> void:
	for child in %MarketGrid.get_children():
		%MarketGrid.remove_child(child)
		child.queue_free()
	for title: String in ["", "Buy", "Sell", "", "Buy", "Sell"]:
		_add_market_cell(title, &"DimLabel")
	for commodity: Dictionary in GameData.commodities:
		var sell := GameState.market.sell_price(port_id, commodity.id)
		var ratio := sell / GameData.world_price(commodity.id)
		var variation := &"GainLabel" if ratio < MARKET_CHEAP else (&"ErrorLabel" if ratio > MARKET_EXPENSIVE else &"")
		_add_market_cell(commodity.name, &"")
		_add_market_cell(Fmt.money(roundi(GameState.market.buy_price(port_id, commodity.id))), variation)
		_add_market_cell(Fmt.money(roundi(sell)), variation)


func _add_market_cell(text: String, variation: StringName) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", MARKET_FONT_SIZE)
	%MarketGrid.add_child(label)
