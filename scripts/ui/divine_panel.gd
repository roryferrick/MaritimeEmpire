# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name DivinePanel
extends Control
## The Divine Actions panel (the bolt button on the World map, in games
## founded with Divine Actions: see Divine): every power with what it does,
## its price now and an Unleash button each (greyed, with why, while it can't
## be used: too expensive, on cooldown, Wrath used this year, three storms out),
## and the last few acts of every company. A power with a target closes the
## panel and has the player pick it on the map (WorldScreen._start_divine()).
## Over the map, dimming it; Esc, X or a click outside closes it.

signal pick(power: String)

const PANEL_SIZE := Vector2(720, 660)
const BOLT := Color(1.0, 0.85, 0.3)

var _rows := VBoxContainer.new()
var _ledger := Label.new()
var _clock := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(PANEL_SIZE.x, minf(PANEL_SIZE.y, get_viewport_rect().size.y - 80.0))
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	card.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	var bolt := BoltIcon.new()
	bolt.custom_minimum_size = Vector2(26, 30)
	header.add_child(bolt)
	var title := Label.new()
	title.text = "Divine Actions"
	title.theme_type_variation = &"HeaderLabel"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var note := Label.new()
	note.text = "Unfair by design. Your storms and plagues hit your own ships too if they're there, and rivals have these powers as well. Prices rise with your company level; Wrath is a flat billion, once a year."
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_rows.add_theme_constant_override(&"separation", 8)
	_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_ledger.theme_type_variation = &"DimLabel"
	_ledger.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ledger.add_theme_font_size_override(&"font_size", 13)
	content.add_child(_ledger)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 1.0:
		_clock = 0.0
		_refresh()


## Every power's row: its name and price, what it does, and its button.
func _refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var divine: Divine = GameState.divine
	var who: Company = GameState.company
	for power: String in Divine.ORDER:
		var info: Dictionary = Divine.POWERS[power]
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		_rows.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.add_theme_constant_override(&"separation", 0)
		row.add_child(text)
		var name := Label.new()
		name.text = "%s  ·  %s" % [info.name, Fmt.money(divine.price(power, who))]
		text.add_child(name)
		var blurb := Label.new()
		blurb.text = str(info.blurb)
		blurb.theme_type_variation = &"DimLabel"
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.add_theme_font_size_override(&"font_size", 13)
		text.add_child(blurb)
		var button := Button.new()
		button.custom_minimum_size = Vector2(110, 34)
		button.size_flags_vertical = SIZE_SHRINK_CENTER
		var target := str(info.target)
		# What error() says with no target yet: only its target's absence is fine here.
		var probe: Variant = Vector2.ZERO if target == "point" else ("" if target == "port" else (0 if target == "ship" else null))
		var why := divine.error(power, probe, who)
		var picking := why.begins_with("Pick ") or why.begins_with("No rival has a hub") or why.begins_with("Not one of your") or why.begins_with("The Kraken")
		var can := why.is_empty() or picking
		button.text = "Unleash" if can else ("Not yet" if "ready again" in why or "once a year" in why or "are out already" in why else "Too expensive")
		button.disabled = not can
		button.tooltip_text = ("Pick the target on the map next." if target != "none" else "") if can else why
		button.pressed.connect(func() -> void:
			pick.emit(power)
			queue_free())
		row.add_child(button)
	var lines := PackedStringArray()
	for entry: Dictionary in divine.ledger:
		lines.append("%s: %s%s" % [entry.who, Divine.POWERS[entry.power].name, (" at " + str(entry.where)) if not str(entry.where).is_empty() else ""])
	_ledger.text = ("Lately: " + "; ".join(lines)) if not lines.is_empty() else "No divine act yet."


## A lightning bolt (the Divine Actions mark), filling the control.
class BoltIcon:
	extends Control
	var color := Color(1.0, 0.85, 0.3)

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var side := minf(size.x, size.y)
		var o := (size - Vector2.ONE * side) / 2.0
		var at := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * side
		draw_colored_polygon(PackedVector2Array([at.call(0.6, 0.0), at.call(0.2, 0.55), at.call(0.47, 0.55), at.call(0.35, 1.0), at.call(0.8, 0.4), at.call(0.53, 0.4)]), color)
