# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name AchievementsPage
extends Control
## The achievements (the trophy button at the map's top right, see
## Achievements): this player's company's stars, all told, then each line with
## its three stars and how far along it is (cargo delivered of each commodity;
## the fleet, company value, money and field guide), then the badges. Over the
## map, dimming it; Esc, X or a click outside closes it.

const PANEL_SIZE := Vector2(820, 640)
const SMALL_FONT := 14
const STAR_SIDE := 22.0
const GOLD := Color(1.0, 0.8, 0.3)
const UNEARNED := Color(0.55, 0.55, 0.6)

var _list := VBoxContainer.new()


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
	content.add_theme_constant_override(&"separation", 10)
	card.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	var trophy := TrophyIcon.new()
	trophy.color = GOLD
	trophy.custom_minimum_size = Vector2(30, 30)
	header.add_child(trophy)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Achievements"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var company := GameState.company
	Achievements.check(company)
	var score := Achievements.score(company)
	var total := Label.new()
	total.text = "%d of %d stars" % [score.x, score.y]
	header.add_child(total)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_list.add_theme_constant_override(&"separation", 8)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var lines := Achievements.lines()
	_heading("Cargo delivered")
	var grid := _grid()
	for line: Dictionary in lines:
		if str(line.id).begins_with("deliver_"):
			_line_row(grid, company, line)
	_heading("Company")
	grid = _grid()
	for line: Dictionary in lines:
		if not str(line.id).begins_with("deliver_"):
			_line_row(grid, company, line)
	_heading("Milestones")
	grid = _grid()
	for badge: Array in Achievements.BADGES:
		_badge_row(grid, company.achievements.has(badge[0]), badge[1], badge[2])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _heading(text: String) -> void:
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = text
	_list.add_child(title)


## Two columns of rows.
func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 24)
	grid.add_theme_constant_override(&"v_separation", 10)
	_list.add_child(grid)
	return grid


## A line: its stars, its name, and how far along it is (to the next star).
func _line_row(grid: GridContainer, company: Company, line: Dictionary) -> void:
	var stars := int(company.achievements.get(line.id, 0))
	var amount := Achievements.progress(company, line.id)
	var needs: Array = line.stars
	var text := ""
	if stars >= needs.size():
		text = "All 3 stars: %s %s" % [_amount(line.id, amount), line.unit]
	else:
		text = "%s of %s %s" % [_amount(line.id, amount), _amount(line.id, int(needs[stars])), line.unit]
	if line.id == "animals":
		text += " (see the field guide's checks)"
	grid.add_child(_row(_Stars.new(stars, 3), str(line.name), text, float(amount) / maxf(float(needs[mini(stars, needs.size() - 1)]), 1.0) if stars < needs.size() else 1.0))


func _badge_row(grid: GridContainer, done: bool, name: String, takes: String) -> void:
	grid.add_child(_row(_Stars.new(1 if done else 0, 1), name, takes, -1.0))


## A row: stars, then the name over a line of text (and a bar, how far to the
## next star; none for -1).
func _row(stars: Control, name: String, line: String, share: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.custom_minimum_size.x = (PANEL_SIZE.x - 90.0) / 2.0
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	stars.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(stars)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 1)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = name
	text.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"DimLabel"
	sub.add_theme_font_size_override(&"font_size", SMALL_FONT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.text = line
	text.add_child(sub)
	if share >= 0.0 and share < 1.0:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 5
		bar.max_value = 1.0
		bar.value = clampf(share, 0.0, 1.0)
		bar.modulate = GOLD
		text.add_child(bar)
	row.add_child(text)
	return row


## An amount on a line, as its unit reads.
static func _amount(line_id: String, amount: int) -> String:
	if line_id == "money" or line_id == "value":
		return Fmt.money_short(amount)
	return Fmt.short(amount) if amount >= 100000 else Fmt.thousands(amount)


## Stars in a row: `earned` of `count` filled.
class _Stars extends Control:
	var earned := 0
	var count := 3

	func _init(stars_earned: int, stars: int) -> void:
		earned = stars_earned
		count = stars
		mouse_filter = MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(STAR_SIDE * 3 + 4.0, STAR_SIDE)

	func _draw() -> void:
		var left := (size.x - STAR_SIDE * count - 2.0 * (count - 1)) / 2.0
		for i in count:
			TrophyIcon.draw_star(self, Vector2(left + i * (STAR_SIDE + 2.0), 0.0), STAR_SIDE, GOLD if i < earned else UNEARNED, i < earned)
