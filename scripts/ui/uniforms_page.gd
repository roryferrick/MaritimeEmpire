# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name UniformsPage
extends Control
## The Uniforms page (the Ships screen's Uniforms button, or a ship's Crew
## page): what this company's people wear on deck, line by line (CrewLooks),
## the captain and mates in one column and the crew in the other. Each has a
## hat (any of Characters' 20, or none), a shirt colour (the shoulders, seen
## from above) and a trousers colour (the legs, walking), with a figure
## walking on the spot to show them, and Default to put a line's outfit back.
## Over the map, dimming it; Esc, X or a click outside closes it.

const PANEL_SIZE := Vector2(760, 600)
const SWATCH := Vector2(30, 24)

var _line := "container"
var _lines := OptionButton.new()
var _columns := HBoxContainer.new()


## Opens on a line (a model category; see CrewLooks.line_of()).
func _init(line := "container") -> void:
	_line = line if CrewLooks.has_line(line) else "container"


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
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Uniforms"
	header.add_child(title)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.text = "What your people wear on deck, zoomed right in"
	note.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(note)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.text = "Ships"
	pick.add_child(label)
	for line: Dictionary in CrewLooks.lines():
		_lines.add_item(str(line.title))
		_lines.set_item_metadata(_lines.item_count - 1, str(line.id))
		if line.id == _line:
			_lines.select(_lines.item_count - 1)
	_lines.item_selected.connect(func(index: int) -> void:
		_line = str(_lines.get_item_metadata(index))
		_show())
	pick.add_child(_lines)
	content.add_child(pick)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_columns.add_theme_constant_override(&"separation", 24)
	_columns.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_columns)
	GameState.uniforms_changed.connect(_on_uniforms_changed)
	_show()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _on_uniforms_changed(company: Company) -> void:
	if company == GameState.company:
		_show()


func _show() -> void:
	for child in _columns.get_children():
		child.queue_free()
	for role: String in CrewLooks.ROLES:
		_columns.add_child(_column(role))


## A role's column: its figure, then its hat, shirt and trousers.
func _column(role: String) -> Control:
	var outfit := CrewLooks.outfit(GameState.company, _line, role)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 8)
	var top := HBoxContainer.new()
	var heading := Label.new()
	heading.theme_type_variation = &"HeaderLabel"
	heading.text = "Captain and mates" if role == "captain" else "Crew"
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(heading)
	var reset := Button.new()
	reset.text = "Default"
	reset.tooltip_text = "Back to how %s dress them." % CrewLooks.line_title(_line).to_lower()
	reset.disabled = outfit == CrewLooks.default_outfit(_line, role)
	reset.pressed.connect(func() -> void: GameState.set_uniform(_line, role, "", ""))
	top.add_child(reset)
	box.add_child(top)
	var preview := UniformFigure.new(outfit)
	preview.custom_minimum_size = Vector2(0, 120)
	box.add_child(preview)
	# The hat: < its name >.
	var hats := CrewLooks.choices("hat")
	var hat_row := HBoxContainer.new()
	hat_row.add_theme_constant_override(&"separation", 6)
	var hat_label := Label.new()
	hat_label.text = "Hat"
	hat_label.custom_minimum_size.x = 70
	hat_row.add_child(hat_label)
	var at := maxi(hats.find(str(outfit.hat)), 0)
	for step: int in [-1, 1]:
		var button := Button.new()
		button.text = "<" if step < 0 else ">"
		button.custom_minimum_size.x = 30
		button.pressed.connect(func() -> void: GameState.set_uniform(_line, role, "hat", str(hats[posmod(at + step, hats.size())])))
		hat_row.add_child(button)
		if step < 0:
			var name_label := Label.new()
			name_label.text = str(outfit.hat)
			name_label.custom_minimum_size.x = 130
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hat_row.add_child(name_label)
	box.add_child(hat_row)
	box.add_child(_swatches("Shirt", role, "shirt", str(outfit.shirt)))
	box.add_child(_swatches("Trousers", role, "trousers", str(outfit.trousers)))
	return box


## A part's colour swatches, the chosen one outlined.
func _swatches(title: String, role: String, part: String, chosen: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 70
	label.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	for color_name: String in CrewLooks.choices(part):
		var swatch := Button.new()
		swatch.custom_minimum_size = SWATCH
		swatch.focus_mode = FOCUS_NONE
		swatch.tooltip_text = color_name
		var style := StyleBoxFlat.new()
		style.bg_color = CrewLooks.shirt_color(color_name) if part == "shirt" else CrewLooks.trouser_color(color_name)
		style.set_corner_radius_all(4)
		style.set_border_width_all(3 if color_name == chosen else 1)
		style.border_color = Color.WHITE if color_name == chosen else Color(0, 0, 0, 0.5)
		for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
			swatch.add_theme_stylebox_override(state, style)
		swatch.pressed.connect(func() -> void: GameState.set_uniform(_line, role, part, color_name))
		grid.add_child(swatch)
	row.add_child(grid)
	return row


## A person seen from above as they look on deck, walking on the spot.
class UniformFigure extends Control:
	var outfit := {}
	var _atlas: Texture2D = null

	func _init(dress: Dictionary) -> void:
		outfit = dress
		_atlas = load(MapView.DECK_ATLAS_PATH)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var middle := size / 2.0
		var cell := minf(size.y * 0.95, 120.0)
		var t := Time.get_ticks_msec() / 1000.0
		var hat := CrewLooks.hat_index(str(outfit.hat))
		var cells := []  # [offset, index, color].
		cells.append([Vector2(cell * 0.12, cell * 0.12), 0, Color(0, 0, 0, MapView.DECK_SHADOW_ALPHA)])
		var swing := sin(t * 4.0) * cell * 0.2
		var legs := CrewLooks.trouser_color(str(outfit.trousers))
		cells.append([Vector2(swing, -cell * 0.11), 2, legs])
		cells.append([Vector2(-swing, cell * 0.11), 2, legs])
		cells.append([Vector2.ZERO, 1, CrewLooks.shirt_color(str(outfit.shirt))])
		cells.append([Vector2.ZERO, 3, Portrait.SKINS[3]])
		cells.append([Vector2.ZERO, 4 if hat == 0 else MapView.DECK_HAT_CELL + hat, Portrait.HAIR_COLORS[2] if hat == 0 else Color.WHITE])
		# Facing up the page, as if walking away up the deck.
		draw_set_transform(middle, -PI / 2.0)
		for entry: Array in cells:
			var index: int = entry[1]
			var from := Rect2(Vector2(index % 8, index / 8) * (Vector2(_atlas.get_size()) / MapView.DECK_ATLAS_CELLS), Vector2(_atlas.get_size()) / MapView.DECK_ATLAS_CELLS)
			var offset: Vector2 = entry[0]
			if index == 0:
				offset = offset.rotated(PI / 2.0)  # (The shadow falls down and right on the page.)
			draw_texture_rect_region(_atlas, Rect2(offset - Vector2.ONE * cell / 2.0, Vector2.ONE * cell), from, entry[2])
		draw_set_transform_matrix(Transform2D.IDENTITY)
