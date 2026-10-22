# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CityPopup
extends AnchoredPopup
## Opened by clicking an inland city on the map (see MapView._draw_cities()):
## its country and region, its people now (and by stratum: the living world's
## pops), the ports that serve it (with their shares, till land transport
## exists), and the producers' plants there, each a button to its card
## (PlantPopup). Follows the city.

const FONT_SIZE := 13
const WIDTH := 320.0
const PLANTS_SHOWN := 8

## Set before adding to the tree.
var city_id := ""
## The map (for the plants' cards to follow the city).
var map: MapView

var _title := Label.new()


func _init() -> void:
	theme_type_variation = &"MapPopup"


func _ready() -> void:
	super()
	var city := WorldEconomy.city(city_id)
	var world: WorldEconomy = GameState.world
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 6)
	content.custom_minimum_size.x = WIDTH
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_title.theme_type_variation = &"HeaderLabel"
	_title.text = str(city.get("name", city_id))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	var country := str(WorldEconomy.country(str(city.get("country", ""))).get("name", city.get("country", "")))
	var where := "%s%s%s" % [str(city.get("region", "")), ", " if not str(city.get("region", "")).is_empty() else "", country]
	if bool(city.get("capital", false)):
		where += " (the capital)"
	content.add_child(_text(where))
	var people := world.place_people("city", city_id)
	var place_at := int(world._place_index.get("city/%s" % city_id, -1))
	if place_at >= 0:
		var strata: Array = world.strata_of(world.places[place_at])
		content.add_child(_text("%s people: %s lower, %s middle, %s upper" % [Fmt.short(people), Fmt.short(float(strata[0])), Fmt.short(float(strata[1])), Fmt.short(float(strata[2]))]))
	else:
		content.add_child(_text("%s people" % Fmt.short(float(city.get("population", 0)))))
	var ports := PackedStringArray()
	for serving: Array in city.get("ports", []):
		ports.append("%s %d%%" % [GameData.port_name(str(serving[0])), roundi(float(serving[1]) * 100.0)])
	if not ports.is_empty():
		content.add_child(_dim("Served by " + ", ".join(ports) + " (no roads or rail yet: its trade goes by the nearest ports)."))
	var here: Array = world.producers.plants_at(city_id)
	if here.is_empty():
		content.add_child(_dim("No plants here."))
		return
	content.add_child(_text("%d plants here:" % here.size()))
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 2)
	content.add_child(list)
	for i in mini(here.size(), PLANTS_SHOWN):
		var index: int = here[i]
		var plant: Dictionary = world.producers.plants[index]
		var button := Button.new()
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override(&"font_size", FONT_SIZE)
		button.text = "%s — %s" % [Producers.plant_title(plant), str(world.producers.company_of(plant).get("name", ""))]
		button.pressed.connect(_open_plant.bind(index))
		list.add_child(button)
	if here.size() > PLANTS_SHOWN:
		list.add_child(_dim("and %d more" % (here.size() - PLANTS_SHOWN)))


func _open_plant(index: int) -> void:
	var card := PlantPopup.new()
	card.plant = index
	card.follow = follow
	PopupHost.find(self).open(card)


func _text(text: String) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH
	label.text = text
	return label


func _dim(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = &"DimLabel"
	return label
