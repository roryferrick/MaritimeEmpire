# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Licences
extends Control
## The game's licences and credits (Licences on the title screen and in the
## Esc menu): the game's own copyright, then each third-party part with its
## notice in full, as their licences ask: GodotSteam (MIT) and the Steamworks
## SDK, Natural Earth, and Godot Engine (MIT) with every third-party part it's
## built from (fonts, FreeType and the rest), straight from the engine
## (Engine.get_copyright_info(), get_license_info()), so it's always complete.
## Over whatever opened it, dimming it; Esc, X or a click outside closes it.

const PANEL_SIZE := Vector2(820, 640)
const GODOTSTEAM_LICENSE := """MIT License

Copyright (c) 2015-Current | GP Garcia, Chris Ridenour, and Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE."""


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
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Licences and credits"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.selection_enabled = true
	text.size_flags_vertical = SIZE_EXPAND_FILL
	text.add_theme_font_size_override(&"normal_font_size", 14)
	text.add_theme_font_size_override(&"bold_font_size", 17)
	text.text = notices()
	content.add_child(text)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


## Everything the page says (BBCode).
static func notices() -> String:
	var out := PackedStringArray()
	out.append("[b]Maritime Empire[/b]\n© 2026 Rory Ferrick. All rights reserved.")
	out.append("[b]Map data[/b]\nMade with Natural Earth: free vector and raster map data @ naturalearthdata.com (public domain).")
	out.append("[b]GodotSteam[/b]\n" + _plain(GODOTSTEAM_LICENSE))
	out.append("[b]Fonts[/b]\n" + _font_notices())
	out.append("[b]Steamworks SDK[/b]\nSteamworks SDK © Valve Corporation, used under the Steamworks SDK Access Agreement. Steam and the Steam logo are trademarks of Valve Corporation.")
	out.append("[b]Godot Engine[/b]\nThis game uses Godot Engine, available under the following license:\n\n" + _plain(Engine.get_license_text()))
	# The parts Godot is built from, each with its copyright and license.
	var parts := PackedStringArray()
	for component: Dictionary in Engine.get_copyright_info():
		for part: Dictionary in component.get("parts", []):
			var lines := PackedStringArray(["[b]%s[/b]" % _plain(str(component.get("name", "")))])
			for holder in part.get("copyright", []):
				lines.append("© " + _plain(str(holder)))
			lines.append("License: " + _plain(str(part.get("license", ""))))
			parts.append("\n".join(lines))
	out.append("[b]Godot Engine's third-party parts[/b]\n\n" + "\n\n".join(parts))
	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for license_name in names:
		out.append("[b]%s[/b]\n%s" % [_plain(str(license_name)), _plain(str(licenses[license_name]))])
	return "\n\n".join(out)


## The bundled fonts (fonts/, see UiLook), each with its licence in full
## (SIL Open Font License 1.1).
static func _font_notices() -> String:
	var out := PackedStringArray()
	var families := DirAccess.get_directories_at("res://fonts")
	for family in families:
		var path := "res://fonts/%s/OFL.txt" % family
		if FileAccess.file_exists(path):
			out.append("[b]%s[/b]\n%s" % [family, _plain(FileAccess.get_file_as_string(path))])
	return "\n\n".join(out)


## Text shown as it is (no BBCode in it).
static func _plain(text: String) -> String:
	return text.replace("[", "[lb]")
