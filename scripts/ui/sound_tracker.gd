# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name SoundTracker
extends PanelContainer
## The little panel at the top left of the World map that says which bird is
## calling (Ambience call_started): the very bird that's calling, drawn big
## in its mirror image, then the species' name, then a speaker mark; shown
## while the call plays and fading after.

const SPRITE_PX := 46.0
const FADE_S := 0.8

var _map: Control
var _sprite := Control.new()
var _name := Label.new()
var _speaker := Control.new()
var _bird := {}
var _colony := {}
var _info := {}
var _state := {}
var _until := 0.0
var _started := 0.0


func _init(map: Control) -> void:
	_map = map


func _ready() -> void:
	theme_type_variation = &"CardPanel"
	var style := get_theme_stylebox(&"panel", &"CardPanel").duplicate() as StyleBox  # (Snug round its row.)
	style.set_content_margin_all(6.0)
	style.content_margin_right = 14.0
	add_theme_stylebox_override(&"panel", style)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 12.0
	offset_top = 12.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	add_child(row)
	_sprite.custom_minimum_size = Vector2.ONE * SPRITE_PX
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.draw.connect(_draw_sprite)
	row.add_child(_sprite)
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name.add_theme_font_size_override(&"font_size", 17)
	row.add_child(_name)
	_speaker.custom_minimum_size = Vector2(26.0, 26.0)
	_speaker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker.draw.connect(_draw_speaker)
	row.add_child(_speaker)


## A bird's call has started: show it for `seconds`.
func show_call(bird: Dictionary, colony: Dictionary, info: Dictionary, state: Dictionary, seconds: float) -> void:
	_bird = bird
	_colony = colony
	_info = info
	_state = state
	_name.text = str(info.get("name", "A bird"))
	reset_size.call_deferred()  # (Fitted to this name: a shorter one shrinks it.)
	_started = Time.get_ticks_msec() / 1000.0
	_until = _started + seconds
	visible = true
	_sprite.queue_redraw()
	_speaker.queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var left := _until - now
	modulate.a = clampf(minf((now - _started) / 0.3, left / FADE_S), 0.0, 1.0)
	_speaker.queue_redraw()
	if left <= 0.0:
		visible = false


## The calling bird itself, as the map draws it (MapView._draw_one_bird(), on
## this control for a moment), mirrored and big. No shadow here:
## a flying bird's falls far off, apart from it.
func _draw_sprite() -> void:
	if _bird.is_empty() or _colony.is_empty() or _state.is_empty():
		return
	var canvas_before: Control = _map._canvas
	_map._canvas = _sprite
	var mirrored := Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	# (Wings folded, a bird is about half its span long: drawn bigger to fill its box.)
	var span := SPRITE_PX * (0.95 if MapView.FLYING_MODES.has(str(_state.get("mode", ""))) else 1.6)
	_map.bird_shadows = false
	_map._draw_one_bird(_bird, _colony, _info, _state, _sprite.size / 2.0, span, GameState.play_time, mirrored)
	_map.bird_shadows = true
	_map._canvas = canvas_before


## A speaker with sound waves, the waves flickering while the call plays.
func _draw_speaker() -> void:
	var c := _speaker.size / 2.0
	var color := Color(0.95, 0.9, 0.75)
	_speaker.draw_colored_polygon(PackedVector2Array([c + Vector2(-11.0, -4.0), c + Vector2(-6.0, -4.0), c + Vector2(-1.0, -9.0), c + Vector2(-1.0, 9.0), c + Vector2(-6.0, 4.0), c + Vector2(-11.0, 4.0)]), color)
	var t := Time.get_ticks_msec() / 1000.0
	for k in 3:
		var on := fmod(t * 3.0, 3.0) >= float(k)
		_speaker.draw_arc(c + Vector2(-1.0, 0.0), 4.0 + k * 3.5, -0.9, 0.9, 10, Color(color, 0.9 if on else 0.3), 1.8, true)
