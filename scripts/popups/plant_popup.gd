# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name PlantPopup
extends AnchoredPopup
## Opened by clicking one of the other producers' plants on a port's
## industrial estate (or picked from a city's card): the works and its good,
## who owns it (and from where, and how many plants they have), what it makes
## a year, and the market it sells into with the price there now. Follows the
## port (or the city).

const FONT_SIZE := 13
const WIDTH := 300.0

## Set before adding to the tree: the plant (an index into Producers.plants).
var plant := -1

var _title := Label.new()
var _lines := Label.new()


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
	_lines.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines.custom_minimum_size.x = WIDTH
	content.add_child(_lines)
	_refresh()


func _refresh() -> void:
	var world: WorldEconomy = GameState.world
	var producers := world.producers
	if plant < 0 or plant >= producers.plants.size():
		queue_free()
		return
	var each: Dictionary = producers.plants[plant]
	var good := str(each.good)
	var company := producers.company_of(each)
	_title.text = Producers.plant_title(each)
	var owner := str(company.get("name", "Unknown"))
	var from := "a global company" if bool(company.get("global", false)) else "of %s" % str(WorldEconomy.country(str(company.get("country", ""))).get("name", company.get("country", "")))
	var text := "%s, %s (%d plants)" % [owner, from, producers.plant_count(int(each.company))]
	var unit := str(GameData.commodity(good).get("units", "units"))
	text += "\nMakes %s %s of %s a year" % [Fmt.short(float(each.capacity)), unit, str(GameData.commodity(good).get("name", good)).to_lower()]
	var site := str(each.site)
	if str(each.site_kind) == "city":
		var city := WorldEconomy.city(site)
		text += "\nAt %s, inland" % str(city.get("name", site))
		var ports := PackedStringArray()
		for serving: Array in city.get("ports", []):
			ports.append(GameData.port_name(str(serving[0])))
		if not ports.is_empty():
			text += ", shipped through " + ", ".join(ports)
	else:
		var z := world.zone_of_port(site)
		if z >= 0:
			var zone: Dictionary = world.zones[z]
			var price := world.sell_price(site, good)
			var base := float(GameData.commodity(good).get("base", 1.0))
			text += "\nSells into the %s market: %s a %s there now (x%s of base)" % [str(zone.name), Fmt.money(roundi(price)), unit.trim_suffix("s"), Fmt.decimal(price / maxf(base, 0.0001), 2)]
	_lines.text = text
