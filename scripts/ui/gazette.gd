# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Gazette
extends Control
## The newspaper (DESIGN_LIVING_WORLD.md M1): The Maritime Gazette, an issue
## a calendar week laid out from the News (and the player's own log): a
## masthead and dateline, the week's lead story (its biggest market move),
## then columns for the markets, the companies and the world, and the
## company's own notes down the side. Earlier issues page back. Opened over
## the map (GameRoot.open_gazette()) from the News tab and the ticker.

const WEEK_S := 7 * 86400
const PAPER := Color("#f1ead8")
const INK := Color("#1d1a16")
const RULE := Color("#5a5247")
const COLUMN_WIDTH := 300.0
const SIDE_WIDTH := 260.0
const ITEMS_A_COLUMN := 9
const FONT_SIZE := 14

## The week shown (its index from the calendar's start); -1 for the latest with news.
var week := -1

var _page := VBoxContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var paper := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_content_margin_all(28.0)
	paper.add_theme_stylebox_override(&"panel", style)
	paper.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(paper)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(scroll)
	_page.add_theme_constant_override(&"separation", 10)
	_page.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_page)
	_build()


## The weeks with news, oldest first.
func _weeks() -> PackedInt32Array:
	var start := GameState.calendar_time_at(0.0)
	var seen := {}
	for item: Dictionary in GameState.news.items:
		seen[floori(float(int(item.time) - start) / WEEK_S)] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


func _build() -> void:
	for child in _page.get_children():
		_page.remove_child(child)
		child.queue_free()
	var weeks := _weeks()
	if weeks.is_empty():
		_page.add_child(_masthead(-1, weeks))
		_page.add_child(_ink("No issue yet: the first comes with the first week's news.", FONT_SIZE, true))
		return
	if week < 0 or not weeks.has(week):
		week = weeks[-1]
	_page.add_child(_masthead(week, weeks))
	var start := GameState.calendar_time_at(0.0) + week * WEEK_S
	var items := []
	for item: Dictionary in GameState.news.items:
		if int(item.time) >= start and int(item.time) < start + WEEK_S:
			items.append(item)
	items.reverse()  # Newest first.
	var by_kind := {market = [], company = [], world = []}
	for item: Dictionary in items:
		(by_kind.get_or_add(str(item.kind), []) as Array).append(item)
	# The lead: the week's digest of tight markets if there is one, else the first market move, else anything.
	var lead: Dictionary = {}
	for item: Dictionary in by_kind.market:
		if str(item.text).begins_with("Tightest markets"):
			lead = item
			break
	if lead.is_empty() and not items.is_empty():
		lead = by_kind.market[0] if not by_kind.market.is_empty() else items[0]
	if not lead.is_empty():
		_page.add_child(_rule())
		_page.add_child(_ink(_headline(lead), 30, false, true))
		_page.add_child(_ink(_lead_paragraph(lead, by_kind), FONT_SIZE + 1))
	_page.add_child(_rule())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 24)
	_page.add_child(columns)
	for kind: Array in [["market", "Markets"], ["company", "Shipping"], ["world", "The world"]]:
		var column := VBoxContainer.new()
		column.add_theme_constant_override(&"separation", 6)
		column.custom_minimum_size.x = COLUMN_WIDTH
		column.size_flags_horizontal = SIZE_EXPAND_FILL
		column.add_child(_ink(kind[1], 20, false, true))
		var list: Array = by_kind.get(kind[0], [])
		if list.is_empty():
			column.add_child(_ink("Quiet this week.", FONT_SIZE, true))
		for item: Dictionary in list.slice(0, ITEMS_A_COLUMN):
			if item == lead:
				continue
			column.add_child(_ink("• " + str(item.text), FONT_SIZE))
		if list.size() > ITEMS_A_COLUMN:
			column.add_child(_ink("and %d more" % (list.size() - ITEMS_A_COLUMN), FONT_SIZE, true))
		columns.add_child(column)
	var side := VBoxContainer.new()
	side.add_theme_constant_override(&"separation", 6)
	side.custom_minimum_size.x = SIDE_WIDTH
	side.add_child(_ink("Company notes", 20, false, true))
	var notes := 0
	var entries := ActivityLog.entries.duplicate()
	entries.reverse()
	for entry: Dictionary in entries:
		var when := GameState.calendar_time_at(float(entry.time))
		if when < start or when >= start + WEEK_S or entry.kind == ActivityLog.Kind.INFO:
			continue
		side.add_child(_ink("• " + str(entry.text), FONT_SIZE - 1))
		notes += 1
		if notes >= ITEMS_A_COLUMN:
			break
	if notes == 0:
		side.add_child(_ink("Nothing of note from the company this week.", FONT_SIZE - 1, true))
	columns.add_child(side)


func _masthead(shown: int, weeks: PackedInt32Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	box.add_child(_ink("The Maritime Gazette", 44, false, true, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 16)
	var at := weeks.find(shown)
	var back := Button.new()
	back.text = "◂ Earlier"
	back.flat = true
	back.disabled = at <= 0
	back.pressed.connect(func() -> void:
		week = weeks[at - 1]
		_build())
	row.add_child(back)
	var date := "" if shown < 0 else "Week of %s · Issue %d" % [Fmt.calendar_short(GameState.calendar_time_at(0.0) + shown * WEEK_S).get_slice(" ", 0) + " " + Fmt.calendar_short(GameState.calendar_time_at(0.0) + shown * WEEK_S).get_slice(" ", 1), at + 1]
	row.add_child(_ink(date, FONT_SIZE, true))
	var forward := Button.new()
	forward.text = "Later ▸"
	forward.flat = true
	forward.disabled = at < 0 or at >= weeks.size() - 1
	forward.pressed.connect(func() -> void:
		week = weeks[at + 1]
		_build())
	row.add_child(forward)
	for button: Button in [back, forward]:
		for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_disabled_color"]:
			button.add_theme_color_override(state, INK if state != &"font_disabled_color" else Color(INK, 0.35))
	box.add_child(row)
	return box


static func _headline(item: Dictionary) -> String:
	var text := str(item.text)
	var cut := text.find(":")
	return text if cut < 0 or cut > 60 else text.substr(0, cut)


static func _lead_paragraph(lead: Dictionary, by_kind: Dictionary) -> String:
	var parts := PackedStringArray([str(lead.text) + "."])
	var gluts: Array = by_kind.market.filter(func(item: Dictionary) -> bool: return str(item.text).begins_with("Deepest gluts"))
	if not gluts.is_empty():
		parts.append(str(gluts[0].text) + ".")
	var company: Array = by_kind.get("company", [])
	if not company.is_empty():
		parts.append("On the shipping side, %s." % str(company[0].text).substr(0, 1).to_lower() + str(company[0].text).substr(1))
	return " ".join(parts)


func _rule() -> Control:
	var line := ColorRect.new()
	line.color = RULE
	line.custom_minimum_size.y = 2.0
	return line


func _ink(text: String, size: int, dim := false, heading := false, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = align
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	if heading:
		label.theme_type_variation = &"HeaderLabel"
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", Color(INK, 0.65) if dim else INK)
	label.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
	label.add_theme_color_override(&"font_outline_color", Color.TRANSPARENT)
	return label
