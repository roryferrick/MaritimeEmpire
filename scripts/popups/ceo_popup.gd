# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CeoPopup
extends AnchoredPopup
## The player's CEO, from the round headshot button at the top left of the
## map (WorldScreen): their portrait, name, traits with what each does for the
## company (Traits), the five skills, the company's backstory (Company.story)
## and what came with it (backers, debt). The people system (M3) grows from here.

const FONT_SIZE := 13
const WIDTH := 340.0
const SKILL_SHOWN_MAX := 20.0

var _portrait := Portrait.new()


func _init() -> void:
	theme_type_variation = &"MapPopup"


func _ready() -> void:
	super()
	var company := GameState.company
	var ceo: Dictionary = company.ceo
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	add_child(row)
	_portrait.character = ceo
	_portrait.custom_minimum_size = Vector2(120, 240)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_portrait)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 6)
	content.custom_minimum_size.x = WIDTH
	row.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = str(ceo.get("name", "Your CEO"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(_dim("Chief executive of %s, founded at %s" % [company.name, GameData.port_name(company.home_port)]))
	var traits := Traits.of(ceo)
	content.add_child(_text("Traits" if not traits.is_empty() else "No traits of note yet"))
	for id: String in traits:
		var info := Traits.info(id)
		var line := _text("%s — %s %s" % [Traits.trait_name(id), str(info.get("text", "")), _effects_text(info.get("effects", {}))])
		line.theme_type_variation = &"DimLabel"
		content.add_child(line)
	content.add_child(_text("Skills"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 2)
	var skills := Traits.skills_of(ceo)
	for skill: String in Traits.SKILLS:
		var value := int(skills.get(skill, 0))
		var name := _text(str(Traits.SKILL_NAMES[skill]))
		name.custom_minimum_size.x = 110.0
		grid.add_child(name)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = SKILL_SHOWN_MAX
		bar.value = minf(value, SKILL_SHOWN_MAX)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150.0, 12.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.tooltip_text = "%s %d (from %d, no top; traits add to it)." % [Traits.SKILL_NAMES[skill], value, Traits.BASE_SKILL]
		grid.add_child(bar)
		grid.add_child(_text(str(value)))
	content.add_child(grid)
	if not company.story.is_empty():
		content.add_child(_text("The story"))
		var story := _dim(company.story)
		content.add_child(story)
	var strings := PackedStringArray()
	if not company.investors.is_empty():
		strings.append("%s hold %d%% of the company." % [str(company.investors.get("name", "Backers")).capitalize() if str(company.investors.get("name", "")).begins_with("the ") else str(company.investors.get("name", "Backers")), roundi(float(company.investors.get("stake", 0.0)) * 100.0)])
	if company.loan > 0:
		strings.append("%s owed to the bank." % Fmt.money(company.loan))
	if not strings.is_empty():
		content.add_child(_dim(" ".join(strings)))


static func _effects_text(effects: Dictionary) -> String:
	var parts := PackedStringArray()
	var words := {price = "prices", fuel = "fuel", wear = "wear", breakdowns = "breakdowns", wages = "wages", interest = "interest", fees = "fees"}
	for key: String in effects:
		var value := float(effects[key])
		var up := key == "price"
		var good := (value > 0.0) == up or (not up and value > 0.0)
		parts.append("%s%d%% %s" % ["+" if (up and value > 0.0) or (not up and value < 0.0) else "-", roundi(absf(value) * 100.0), words.get(key, key)])
		if good:
			pass
	return "(%s)" % ", ".join(parts) if not parts.is_empty() else ""


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return label


func _dim(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = &"DimLabel"
	return label
