# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name LogoEditor
extends HBoxContainer
## Making a company logo (CompanyLogo): a big preview beside its choices, the
## second colour (the company colours but the company's own), the shape and
## the arrangement (each a button showing it), and Swap colours. Used on the New
## Company screen's logo page and in LogoDialog (changing it later).

signal changed(logo: Dictionary)

const PREVIEW_SIZE := 180.0
const CHOICE_SIZE := 46.0
const SWATCH_SIZE := Vector2(36, 26)

var logo := {}
var color_id := "purple"
var type_id := ""

var _preview: CompanyLogo
var _choices := VBoxContainer.new()


func _init(start_logo: Dictionary, company_color: String, start_type: String) -> void:
	logo = start_logo.duplicate()
	color_id = company_color
	type_id = start_type
	add_theme_constant_override(&"separation", 28)


func _ready() -> void:
	_preview = CompanyLogo.new(logo, color_id, type_id)
	_preview.custom_minimum_size = Vector2.ONE * PREVIEW_SIZE
	_preview.size_flags_vertical = SIZE_SHRINK_CENTER
	add_child(_preview)
	_choices.add_theme_constant_override(&"separation", 10)
	add_child(_choices)
	_rebuild()


## Uses another company colour (the preview follows; a second colour the same
## as it moves to one that stands out).
func set_company_color(new_color: String) -> void:
	color_id = new_color
	if str(logo.get("secondary", "")) == color_id:
		logo.secondary = CompanyLogo.default_logo(color_id).secondary
	_rebuild()


func _rebuild() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_preview.logo = logo
	_preview.color_id = color_id
	_preview.queue_redraw()
	_choices.add_child(_label("Second colour"))
	var swatches := GridContainer.new()
	swatches.columns = 9
	swatches.add_theme_constant_override(&"h_separation", 6)
	swatches.add_theme_constant_override(&"v_separation", 6)
	for entry: Array in GameData.config.get("company_colors", []):
		var id := str(entry[0])
		if id == color_id:
			continue
		var swatch := Button.new()
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.tooltip_text = id.capitalize()
		var style := StyleBoxFlat.new()
		style.bg_color = GameState.company_color_value(id)
		style.set_corner_radius_all(5)
		style.set_border_width_all(3 if id == str(logo.get("secondary", "")) else 0)
		style.border_color = Color.WHITE if style.bg_color.get_luminance() < 0.8 else Color(0.1, 0.12, 0.15)
		for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
			swatch.add_theme_stylebox_override(state, style)
		swatch.pressed.connect(_change.bind("secondary", id))
		swatches.add_child(swatch)
	_choices.add_child(swatches)
	_choices.add_child(_label("Shape"))
	_choices.add_child(_option_row(CompanyLogo.SHAPES, "shape", CompanyLogo.SHAPE_NAMES))
	_choices.add_child(_label("Arrangement"))
	_choices.add_child(_option_row(CompanyLogo.LAYOUTS, "layout", CompanyLogo.LAYOUT_NAMES))
	var swap := Button.new()
	swap.text = "Swap colours"
	swap.size_flags_horizontal = SIZE_SHRINK_BEGIN
	swap.tooltip_text = "Trade the background and the mark's colours."
	swap.pressed.connect(_change.bind("swap", not bool(logo.get("swap", false))))
	_choices.add_child(swap)


## A button per choice, each showing the logo as it would be with it.
func _option_row(options: Array, key: String, names: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	for option: String in options:
		var button := Button.new()
		button.custom_minimum_size = Vector2(CHOICE_SIZE + 16, CHOICE_SIZE + 16)
		button.toggle_mode = true
		button.button_pressed = str(logo.get(key, "")) == option
		button.tooltip_text = str(names.get(option, option))
		var shown := logo.duplicate()
		shown[key] = option
		var mini := CompanyLogo.new(shown, color_id, type_id)
		mini.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		mini.offset_left = 8
		mini.offset_top = 8
		mini.offset_right = -8
		mini.offset_bottom = -8
		button.add_child(mini)
		button.pressed.connect(_change.bind(key, option))
		row.add_child(button)
	return row


func _change(key: String, value: Variant) -> void:
	logo[key] = value
	_rebuild()
	changed.emit(logo.duplicate())


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"DimLabel"
	return label
