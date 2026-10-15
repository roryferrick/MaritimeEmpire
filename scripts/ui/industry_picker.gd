# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name IndustryPicker
extends PopupPanel
## Picking a building for one of a hub's industry plots (see IndustryPanel):
## every commodity's, by ship line, each with its picture, name and
## commodity; one the hub has already can't be picked again.

const COLUMNS := 4
const ICON_SIZE := 48.0
const BUTTON_WIDTH := 170.0

var hub: Hub
var slot := 0


func _init(for_hub: Hub, for_slot: int) -> void:
	hub = for_hub
	slot = for_slot


func _ready() -> void:
	add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"MapPopup"))
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	add_child(content)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Build a warehouse at %s (%s)" % [hub.title(), Fmt.money(GameState.industry_price())]
	content.add_child(title)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	content.add_child(grid)
	for commodity: Dictionary in GameData.commodities:
		if commodity.get("maker", false):
			continue  # (A maker's goods use their kind's building: Cars, Trucks or Boats.)
		var id: String = commodity.id
		var button := Button.new()
		button.custom_minimum_size = Vector2(BUTTON_WIDTH, ICON_SIZE + 12.0)
		button.icon = MapView._industry_texture(id)
		button.expand_icon = false
		button.add_theme_constant_override(&"icon_max_width", int(ICON_SIZE))
		button.text = "%s\n%s" % [GameState.industry_name(id), commodity.get("name", id)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var error := GameState.build_industry_error(hub, slot, id)
		button.disabled = not error.is_empty()
		button.tooltip_text = error
		button.pressed.connect(func() -> void:
			GameState.build_industry(hub, slot, id)
			hide()
			queue_free())
		grid.add_child(button)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		hide()
		queue_free())
	content.add_child(cancel)
	popup_hide.connect(queue_free)
