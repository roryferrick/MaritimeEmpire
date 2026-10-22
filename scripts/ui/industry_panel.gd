# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name IndustryPanel
extends VBoxContainer
## A hub's industry (on the Hubs page, and in the popup from clicking its
## plots on the map): its Hub.INDUSTRY_SLOTS plots beside the marina, each
## empty (Build: pick one of the commodities'
## buildings, see IndustryPicker) or built (its building, what it does here,
## and Pull down for some of its price back). Rebuilt when the hubs change.

const ICON_SIZE := 44.0
const TEXT_WIDTH := 300.0
const FONT_SIZE := 14

var hub: Hub
## The plot to pick out (clicked on the map), or -1.
var focus := -1


func _init(for_hub: Hub, focus_slot := -1) -> void:
	hub = for_hub
	focus = focus_slot
	add_theme_constant_override(&"separation", 6)


func _ready() -> void:
	GameState.hubs_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "Warehouses"
	add_child(title)
	add_child(_text("Room for %d buildings beside the marina. Each is one commodity's: here it's %s to buy and %s to sell." % [
		Hub.INDUSTRY_SLOTS, _percent(-_bonus("buy")), _percent(_bonus("sell"))]))
	for slot in Hub.INDUSTRY_SLOTS:
		add_child(_slot_row(slot))


## A boost a building gives at this hub (the HQ's are stronger).
func _bonus(kind: String) -> float:
	var key: String = {buy = "buy_discount", sell = "sell_bonus"}[kind]
	return float(Hub.industry_settings().get(key, 0.0)) * (float(Hub.settings().get("hq_multiplier", 1.5)) if hub.is_hq else 1.0)


static func _percent(share: float) -> String:
	return "%s%d%%" % ["+" if share >= 0.0 else "-", roundi(absf(share) * 100.0)]


func _slot_row(slot: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var commodity: String = hub.industries[slot]
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2.ONE * ICON_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = MapView._industry_texture(commodity) if not commodity.is_empty() else null
	if commodity.is_empty():
		picture.modulate = Color(1, 1, 1, 0.25)
	row.add_child(picture)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Label.new()
	var detail: Label
	if not commodity.is_empty():
		name.text = GameState.industry_name(commodity)
		detail = _text("%s here: %s to buy, %s to sell" % [GameData.commodity(commodity).get("name", commodity),
			_percent(-_bonus("buy")), _percent(_bonus("sell"))])
	else:
		name.text = "Empty plot"
		detail = _text("Build any commodity's building here for %s." % Fmt.money(GameState.industry_price()))
	if slot == focus:
		name.theme_type_variation = &"GainLabel"
	text.add_child(name)
	text.add_child(detail)
	row.add_child(text)
	var mine := GameState.hubs.has(hub)
	if mine and not commodity.is_empty():
		var down := Button.new()
		down.text = "Pull down"
		down.tooltip_text = "Pull it down for %s back." % Fmt.money(GameState.industry_refund())
		down.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		down.pressed.connect(_confirm_pull_down.bind(slot))
		row.add_child(down)
	elif mine:
		var build := Button.new()
		build.text = "Build (%s)" % Fmt.short(GameState.industry_price())
		build.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		build.disabled = GameState.money < GameState.industry_price()
		if build.disabled:
			build.tooltip_text = "Costs %s." % Fmt.money(GameState.industry_price())
		build.pressed.connect(func() -> void:
			var picker := IndustryPicker.new(hub, slot)
			get_tree().root.add_child(picker)
			picker.popup_centered())
		row.add_child(build)
	return row


func _confirm_pull_down(slot: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Pull it down?"
	dialog.dialog_text = "Pull down the %s at %s? You get %s back." % [GameState.industry_name(hub.industries[slot]), hub.title(), Fmt.money(GameState.industry_refund())]
	dialog.ok_button_text = "Pull down"
	dialog.confirmed.connect(func() -> void: GameState.demolish_industry(hub, slot))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()


func _text(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TEXT_WIDTH
	label.text = text
	return label
