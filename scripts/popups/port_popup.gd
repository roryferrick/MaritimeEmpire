class_name PortPopup
extends AnchoredPopup
## Shows a port's name, its HQ or hub (level, XP and upgrade tree) or a button
## to found a hub there when one is available, and the player's ships docked
## there with their bars.

const SHIP_BARS_WIDTH := 80.0
## Founding a hub takes a second click within this many seconds (it's permanent).
const BUILD_CONFIRM_SECONDS := 3.0
const REFRESH_SECONDS := 1.0

## Set before adding to the tree.
var port_id := ""

var _build_confirm_until := 0.0
var _xp_label: Label = null
var _clock := 0.0


func _ready() -> void:
	super()
	var port := GameData.get_port(port_id)
	%TitleLabel.text = port.get("name", port_id)
	%CloseButton.pressed.connect(queue_free)
	GameState.ships_changed.connect(_refresh_ships)
	GameState.ship_changed.connect(_refresh_ships.unbind(1))
	GameState.hubs_changed.connect(_refresh_hub)
	GameState.company_leveled.connect(_refresh_hub.unbind(2))
	_refresh_hub()
	_refresh_ships()


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_update_hub_xp()


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
