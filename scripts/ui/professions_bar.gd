# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name ProfessionsBar
extends VBoxContainer
## The pops' professions (WorldEconomy.professions_of_zone() and friends):
## a thin stacked bar in each profession's colour with the shares written
## under it ("farmers 31% · factory hands 22% · ..."), on the country and city
## cards and the port popup. Set `shares` ({profession id: share}) and it draws.

const BAR_HEIGHT := 10.0
const FONT_SIZE := 12

var shares := {}:
	set(value):
		shares = value
		_refresh()

var _bar := Control.new()
var _text := Label.new()


func _init(for_shares := {}) -> void:
	add_theme_constant_override(&"separation", 3)
	_bar.custom_minimum_size.y = BAR_HEIGHT
	_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	_bar.draw.connect(_draw_bar)
	_bar.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bar)
	_text.theme_type_variation = &"DimLabel"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_child(_text)
	shares = for_shares


func _refresh() -> void:
	var parts := PackedStringArray()
	for id: String in WorldEconomy.PROFESSION_ORDER:
		var share := float(shares.get(id, 0.0))
		if share >= 0.005:
			parts.append("%s %d%%" % [WorldEconomy.PROFESSIONS[id][0], roundi(share * 100.0)])
	_text.text = " · ".join(parts) if not parts.is_empty() else "No working people counted yet."
	_bar.queue_redraw()


func _draw_bar() -> void:
	var x := 0.0
	var width := _bar.size.x
	_bar.draw_rect(Rect2(0.0, 0.0, width, BAR_HEIGHT), Color(0, 0, 0, 0.25))
	for id: String in WorldEconomy.PROFESSION_ORDER:
		var share := float(shares.get(id, 0.0))
		if share <= 0.0:
			continue
		var w := width * share
		_bar.draw_rect(Rect2(x, 0.0, maxf(w - 1.0, 0.0), BAR_HEIGHT), Color.from_string(str(WorldEconomy.PROFESSIONS[id][1]), Color.GRAY))
		x += w
