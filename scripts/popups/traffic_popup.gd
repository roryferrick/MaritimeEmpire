# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name TrafficPopup
extends AnchoredPopup
## Opened by clicking one of the other firms' ships on the map (the ambient
## traffic: AmbientTraffic): the firm and its home country, the ship's class
## and how many of them are on this run, where it's from and bound, what it
## carries (or that it's in ballast, homeward), and what it's doing now, kept
## current every REFRESH_SECONDS. Follows the ship.

const REFRESH_SECONDS := 1.0
const FONT_SIZE := 13
const WIDTH := 300.0

## Set before adding to the tree.
var ship: Ship

var _title := Label.new()
var _lines := Label.new()
var _status := Label.new()
var _clock := 0.0


func _init() -> void:
	theme_type_variation = &"MapPopup"


func _ready() -> void:
	super()
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 6)
	content.custom_minimum_size.x = WIDTH
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_title.theme_type_variation = &"HeaderLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	for label in [_lines, _status]:
		label.add_theme_font_size_override(&"font_size", FONT_SIZE)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH
		content.add_child(label)
	_status.modulate = Color(1.0, 1.0, 1.0, 0.8)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	var about: Dictionary = GameState.traffic.describe(ship)
	if about.is_empty():
		queue_free()  # (Sailed out of view: gone.)
		return
	_title.text = str(about.firm)
	var country := str(WorldEconomy.country(str(about.country)).get("name", about.country))
	var text := "%s of %s\n%s" % [country, GameData.port_name(GameState.owner_of(ship).home_port), about.model]
	if int(about.ships) > 1:
		text += " (%d on this run)" % int(about.ships)
	text += "\n%s to %s" % [GameData.port_name(str(about.from)), GameData.port_name(str(about.to))]
	var goods: Dictionary = about.goods
	if not goods.is_empty():
		var names := []
		for good: String in goods:
			names.append("%s %s" % [Fmt.short(float(goods[good])), str(GameData.commodity(good).get("name", good)).to_lower()])
		text += "\nCarrying " + ", ".join(names)
	_lines.text = text
	var when := "Due %s" % Fmt.calendar_short(int(about.arrives)) if not ship.is_docked() else ""
	_status.text = str(about.status) + ("" if when.is_empty() else "\n" + when)
