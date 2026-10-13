# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Portrait
extends Control
## A character (Characters: the CEO, a ship's captain or mates) drawn from
## their look in a clean cartoon style: bold dark outlines, flat colours with
## one soft shade, a big round head with big eyes. Standing, head to shoes,
## or (bust) just head and shoulders on a round backdrop, for small pictures.
## Drawn in a design space DESIGN wide and tall, scaled to fit.
##
## The body is a frame worked out from the look first (_frame(): the body's
## male or female build, the height and build sliders), and every garment is
## drawn against that frame (the torso's width at each height, the arms, the
## legs), so clothes stretch and shrink with the body they're on.

const DESIGN := Vector2(100, 200)
const FLOOR := 193.0
const OUTLINE := Color(0.11, 0.09, 0.15, 0.92)
const OUTLINE_WIDTH := 1.7
const SHADE := Color(0.1, 0.05, 0.2, 0.13)
const BUST_BACKDROP := Color(0.55, 0.68, 0.8)
const HEAD_RADII := Vector2(17.5, 19.5)

const SKINS: Array[Color] = [Color("#ffe6d6"), Color("#f9d4b8"), Color("#f0c29c"), Color("#e0ad7e"), Color("#cb9566"),
	Color("#bb8254"), Color("#a26c44"), Color("#855631"), Color("#674220"), Color("#4b2e16")]
const HAIR_COLORS: Array[Color] = [Color("#1c1a19"), Color("#3b2618"), Color("#5a3a22"), Color("#8a6240"), Color("#8e3b1e"),
	Color("#c4612a"), Color("#d99a6c"), Color("#e3c46e"), Color("#f0e6c8"), Color("#9a9a9a"), Color("#ececec"),
	Color("#3c6fd8"), Color("#e46fb0"), Color("#3fa65a")]
const EYE_COLORS: Array[Color] = [Color("#6b4423"), Color("#3e2615"), Color("#8a7038"), Color("#c6882a"), Color("#3d7cc9"),
	Color("#7fb6e8"), Color("#3f8f4f"), Color("#7d8790"), Color("#7a5bb5")]
const GOLD := Color("#e2b43c")
const WHITE := Color("#f6f6f6")
const NAVY := Color("#1f2b4d")

## Tops: [style, colour, sleeves ("short", "long", "none")].
const TOPS := [
	["captain", Color("#1f2b4d"), "long"], ["stripes", Color("#f4f4f4"), "long"], ["peacoat", Color("#232a3e"), "long"],
	["oilskin", Color("#f2c230"), "long"], ["fisherman", Color("#efe6cc"), "long"], ["whites", Color("#f6f6f6"), "long"],
	["decktee", Color("#22325c"), "short"], ["lifevest", Color("#f4f4f4"), "short"], ["wetsuit", Color("#1a1a22"), "long"],
	["officer", Color("#f6f6f6"), "short"], ["tropical", Color("#2a9d9f"), "short"], ["pirate", Color("#7a1f26"), "long"],
	["tee", Color("#f2f2f2"), "short"], ["tee", Color("#c8343a"), "short"], ["hoodie", Color("#8a8f96"), "long"],
	["suit", Color("#23252b"), "long"], ["flannel", Color("#a8322e"), "long"], ["hivis", Color("#7b8088"), "long"],
	# The skin packs' (see Cosmetics): Thanksgiving, then Baseball.
	["pilgrim_m", Color("#1f1d1f"), "long"], ["pilgrim_f", Color("#5e6a86"), "long"], ["colonial", Color("#2d4a8a"), "long"], ["deckhand", Color("#ece2c8"), "long"], ["farmhand", Color("#8a7a62"), "long"],
	["pinstripes", Color("#f6f6f6"), "short"], ["road_grey", Color("#a9adb3"), "short"], ["catcher", Color("#1f2b4d"), "short"], ["umpire", Color("#1c1c1e"), "short"], ["vendor", Color("#f6f1e6"), "short"], ["flannel_1920", Color("#efe6cc"), "short"],
]
## Bottoms: [style, colour]; trousers, bells, oilskin, shorts, wetsuit, cargo or skirt.
const BOTTOMS := [
	["trousers", Color("#22325c")], ["bells", Color("#f2f2f2")], ["oilskin", Color("#f2c230")], ["shorts", Color("#c9b27e")],
	["wetsuit", Color("#1a1a22")], ["jeans", Color("#3f5f8f")], ["trousers", Color("#c2a878")], ["trousers", Color("#262626")],
	["cargo", Color("#6b6f4a")], ["skirt", Color("#b8323a")], ["skirt", Color("#2c3a5c")], ["shorts", Color("#5577a8")],
	# The skin packs' (see Cosmetics).
	["breeches", Color("#1f1d1f")], ["breeches", Color("#d8c48c")], ["slops", Color("#6b4a2e")], ["hose", Color("#8a8a86")],
	["pants_pin", Color("#f6f6f6")], ["pants_grey", Color("#a9adb3")], ["pants_catcher", Color("#a9adb3")], ["slacks", Color("#6a6e74")], ["knickers", Color("#1f2b4d")],
]
## Shoes: [style, colour]; deck, wellies, barefoot, boots, trainers, dress or sandals.
const SHOES := [
	["deck", Color("#6e4526")], ["wellies", Color("#222222")], ["wellies", Color("#f2c230")], ["barefoot", Color.TRANSPARENT],
	["boots", Color("#222222")], ["boots", Color("#6e4526")], ["trainers", Color("#f2f2f2")], ["dress", Color("#151515")],
	["sandals", Color("#7a4e2a")], ["trainers", Color("#c8343a")],
	["buckle", Color("#151515")], ["wraps", Color("#b9a27c")], ["cleats", Color("#151515")],  # (The skin packs': see Cosmetics.)
]

## {name, look} (see Characters).
var character: Dictionary = {}:
	set(value):
		character = value
		queue_redraw()
## Just the head and shoulders, on a round backdrop.
var bust := false:
	set(value):
		bust = value
		clip_contents = value
		queue_redraw()

var _look := {}
# The frame (see the top): the body's measures in design units.
var _female := false
var _hf := 1.0  # Height factor.
var _bf := 1.0  # Build factor.
var _ankle_y := 0.0
var _hip_y := 0.0
var _waist_y := 0.0
var _chest_y := 0.0
var _shoulder_y := 0.0
var _neck_top := 0.0
var _head := Vector2.ZERO
var _sh := 0.0  # Half-widths: the shoulders, chest, waist, hips.
var _chest := 0.0
var _waist := 0.0
var _hip := 0.0
var _leg_r := 0.0
var _leg_x := 0.0
var _arm_r := 0.0


func _init(for_character := {}, as_bust := false) -> void:
	character = for_character
	bust = as_bust
	mouse_filter = MOUSE_FILTER_PASS


func _part(key: String) -> int:
	return clampi(int(_look.get(key, 0)), 0, Characters.option_count(key) - 1)


## The body's measures from the look (see the top).
func _frame() -> void:
	_female = _part("body") == 1
	_hf = lerpf(0.86, 1.12, Characters.slider(_look, "height") / 100.0)
	_bf = lerpf(0.72, 1.5, Characters.slider(_look, "build") / 100.0)
	_ankle_y = FLOOR - 5.0
	_hip_y = _ankle_y - 66.0 * _hf
	_shoulder_y = _hip_y - 50.0 * _hf
	_waist_y = _shoulder_y + 31.0 * _hf
	_chest_y = _shoulder_y + (16.0 if _female else 12.0) * _hf
	_neck_top = _shoulder_y - 7.0
	_head = Vector2(50.0, _neck_top - HEAD_RADII.y + 4.0)
	_sh = (23.0 if not _female else 19.0) * pow(_bf, 0.75)
	_chest = _sh + (2.5 if _female else 0.5)
	_waist = (16.5 if not _female else 12.5) * _bf
	_hip = (17.0 if not _female else 20.0) * pow(_bf, 0.9)
	_leg_r = 6.5 * pow(_bf, 0.7)
	_leg_x = _hip * 0.5
	_arm_r = 4.2 * pow(_bf, 0.6)


## The torso's half-width at a height (between the shoulders and the hips).
func _torso_half(y: float) -> float:
	if y <= _chest_y:
		return lerpf(_sh, _chest, inverse_lerp(_shoulder_y, _chest_y, y)) if y > _shoulder_y else _sh
	if y <= _waist_y:
		return lerpf(_chest, _waist, inverse_lerp(_chest_y, _waist_y, y))
	return lerpf(_waist, _hip, clampf(inverse_lerp(_waist_y, _hip_y, y), 0.0, 1.0))


## The torso's outline from the shoulders down to a hem (the hips, or lower
## for a coat), as a polygon.
func _torso(hem_y := -1.0, top_y := -1.0) -> PackedVector2Array:
	if hem_y < 0.0:
		hem_y = _hip_y
	if top_y < 0.0:
		top_y = _shoulder_y
	var points := PackedVector2Array()
	points.append(Vector2(50.0 - _sh * 0.45, top_y - 1.5))
	points.append(Vector2(50.0 + _sh * 0.45, top_y - 1.5))
	points.append(Vector2(50.0 + _sh, top_y + 2.0))
	var y := _shoulder_y + 6.0
	while y < minf(hem_y, _hip_y):
		points.append(Vector2(50.0 + _torso_half(y), y))
		y += 6.0
	if hem_y > _hip_y:
		points.append(Vector2(50.0 + _hip + 1.0, _hip_y))
		points.append(Vector2(50.0 + _hip + 2.0, hem_y))
		points.append(Vector2(50.0 - _hip - 2.0, hem_y))
		points.append(Vector2(50.0 - _hip - 1.0, _hip_y))
	else:
		points.append(Vector2(50.0 + _torso_half(hem_y), hem_y))
		points.append(Vector2(50.0 - _torso_half(hem_y), hem_y))
	y -= 6.0
	while y > _shoulder_y + 5.0:
		points.append(Vector2(50.0 - _torso_half(y), y))
		y -= 6.0
	points.append(Vector2(50.0 - _sh, top_y + 2.0))
	return points


## Where an arm starts (the shoulder) and ends (the hand), each side.
func _arm_top(side: float) -> Vector2:
	return Vector2(50.0 + side * (_sh - 1.0), _shoulder_y + 5.0)


func _hand(side: float) -> Vector2:
	return Vector2(50.0 + side * (_hip + _arm_r + 7.0), _hip_y + 9.0 * _hf)


func _draw() -> void:
	_look = character.get("look", {})
	_frame()
	var view := Rect2(_head.x - 29.0, _head.y - 33.0, 58.0, 66.0) if bust else Rect2(Vector2.ZERO, DESIGN)
	var scale := minf(size.x / view.size.x, size.y / view.size.y)
	var offset := (size - view.size * scale) / 2.0 - view.position * scale
	if bust:
		draw_circle(size / 2.0, minf(size.x, size.y) / 2.0, BUST_BACKDROP, true, -1.0, true)
	draw_set_transform(offset, 0.0, Vector2.ONE * scale)
	var skin := SKINS[_part("skin")]
	var hair := HAIR_COLORS[_part("hair_color")]
	_draw_back_hair(hair)
	_draw_legs(skin)
	_draw_bottoms()
	_draw_body(skin)
	_draw_top(skin)
	_draw_shoes(skin)
	_draw_hands(skin)
	_draw_neck_and_head(skin)
	_draw_eyes(hair)
	_draw_nose(skin)
	_draw_beard(hair)
	_draw_mouth(skin)
	_draw_moustache(hair)
	_draw_front_hair(hair)
	_draw_eyewear()
	_draw_headwear(hair)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# --- Shapes --------------------------------------------------------------------

static func _ellipse_points(center: Vector2, radii: Vector2, from := 0.0, to := TAU, steps := 28) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps + 1:
		var angle := lerpf(from, to, float(i) / steps)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


## A rounded bar from a to b, r thick either side (the b end flat if asked).
static func _capsule_points(a: Vector2, b: Vector2, r: float, steps := 8, flat_end := false) -> PackedVector2Array:
	var angle := (b - a).angle()
	var points := PackedVector2Array()
	for i in steps + 1:
		var t := angle + PI / 2.0 + PI * float(i) / steps
		points.append(a + Vector2(cos(t), sin(t)) * r)
	if flat_end:
		points.append(b + Vector2(cos(angle - PI / 2.0), sin(angle - PI / 2.0)) * r)
		points.append(b + Vector2(cos(angle + PI / 2.0), sin(angle + PI / 2.0)) * r)
		return points
	for i in steps + 1:
		var t := angle - PI / 2.0 + PI * float(i) / steps
		points.append(b + Vector2(cos(t), sin(t)) * r)
	return points


## A filled shape with no outline.
func _fill(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)


func _shape(points: PackedVector2Array, color: Color, outline := true, width := OUTLINE_WIDTH) -> void:
	if Geometry2D.triangulate_polygon(points).is_empty():
		print("BAD POLYGON in %s: %s" % [get_stack()[1].function, points])
	_fill(points, color)
	if outline:
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, OUTLINE, width, true)


func _ellipse(center: Vector2, radii: Vector2, color: Color, outline := true) -> void:
	var points := _ellipse_points(center, radii)
	points.resize(points.size() - 1)
	_shape(points, color, outline)


func _capsule(a: Vector2, b: Vector2, r: float, color: Color, outline := true, flat_end := false) -> void:
	_shape(_capsule_points(a, b, r, 8, flat_end), color, outline)


func _line(points: PackedVector2Array, color: Color, width := 1.4) -> void:
	draw_polyline(points, color, width, true)


func _dot(at: Vector2, r: float, color: Color) -> void:
	draw_circle(at, r, color, true, -1.0, true)


static func _p(values: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, values.size(), 2):
		points.append(Vector2(values[i], values[i + 1]))
	return points


## A soft shade down the right of a torso-shaped polygon (the one soft shade
## of the style): the right edge from the shoulders to a hem, back up nearer the middle.
func _shade_torso(hem_y: float, top_y := -1.0) -> void:
	if top_y < 0.0:
		top_y = _shoulder_y
	var points := PackedVector2Array()
	var y := top_y + 3.0
	while y < hem_y:
		points.append(Vector2(50.0 + (_torso_half(y) if y <= _hip_y else _hip + 2.0), y))
		y += 6.0
	points.append(Vector2(50.0 + (_torso_half(hem_y) if hem_y <= _hip_y else _hip + 2.0), hem_y))
	points.append(Vector2(50.0 + (_torso_half(hem_y) if hem_y <= _hip_y else _hip) * 0.45, hem_y))
	y -= 6.0
	while y >= top_y + 3.0:
		points.append(Vector2(50.0 + _torso_half(y) * 0.45, y))
		y -= 6.0
	_fill(points, SHADE)


# --- Body ----------------------------------------------------------------------

func _draw_legs(skin: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var x := 50.0 + side * _leg_x
		_capsule(Vector2(x, _hip_y - 2.0), Vector2(x, _ankle_y + 1.0), _leg_r, skin, true, true)


func _draw_body(skin: Color) -> void:
	_shape(_torso(), skin)
	for side: float in [-1.0, 1.0]:
		_capsule(_arm_top(side), _hand(side), _arm_r, skin)


func _draw_hands(skin: Color) -> void:
	for side: float in [-1.0, 1.0]:
		_ellipse(_hand(side) + Vector2(0.0, 1.0), Vector2(_arm_r + 1.0, _arm_r + 1.6), skin)


func _draw_bottoms() -> void:
	var bottoms: Array = BOTTOMS[_part("bottoms")]
	var style: String = bottoms[0]
	var color: Color = bottoms[1]
	if _draw_pack_bottoms(style, color):
		return
	var hem := _ankle_y - 1.5
	var r := _leg_r + 1.6
	match style:
		"shorts":
			hem = _hip_y + 24.0 * _hf
		"skirt":
			var hem_y := _hip_y + 26.0 * _hf
			_shape(_p([50.0 - _hip - 0.5, _hip_y - 5.0, 50.0 + _hip + 0.5, _hip_y - 5.0, 50.0 + _hip + 7.0, hem_y, 50.0 - _hip - 7.0, hem_y]), color)
			_line(_p([50.0 - _hip - 2.5, _hip_y + 7.0, 50.0 + _hip + 2.5, _hip_y + 7.0]), color.darkened(0.25), 1.0)
			_shade_bottoms(hem_y)
			return
		"wetsuit":
			r = _leg_r + 0.6
	# The seat (tapering from the hips to the legs) and the two legs.
	var seat := _p([50.0 - _hip - 0.5, _hip_y - 5.0, 50.0 + _hip + 0.5, _hip_y - 5.0, 50.0 + _leg_x + r, _hip_y + 10.0, 50.0 - _leg_x - r, _hip_y + 10.0])
	_shape(seat, color)
	for side: float in [-1.0, 1.0]:
		var x := 50.0 + side * _leg_x
		if style == "bells":
			_shape(_p([x - r, _hip_y - 2.0, x + r, _hip_y - 2.0, x + r * 1.7, hem, x - r * 1.7, hem]), color)
		else:
			_capsule(Vector2(x, _hip_y - 2.0), Vector2(x, hem), r, color, true, style != "shorts")
	_shape(seat, color, false)
	_line(_p([50.0, _hip_y + 10.0, 50.0, _hip_y + 18.0]), color.darkened(0.35), 1.0)  # The fly's crease.
	match style:
		"cargo":
			for side: float in [-1.0, 1.0]:
				var x := 50.0 + side * (_leg_x + 1.0)
				_shape(_p([x - 4.0, _hip_y + 26.0 * _hf, x + 4.0, _hip_y + 26.0 * _hf, x + 4.0, _hip_y + 36.0 * _hf, x - 4.0, _hip_y + 36.0 * _hf]), color.darkened(0.12))
		"jeans":
			for side: float in [-1.0, 1.0]:
				var x := 50.0 + side * (_leg_x - r + 2.0)
				_line(_p([x, _hip_y + 10.0, x, hem - 2.0]), color.lightened(0.3), 0.7)
		"oilskin":
			for side: float in [-1.0, 1.0]:
				var x := 50.0 + side * _leg_x
				_line(_p([x - r + 1.0, hem - 6.0, x + r - 1.0, hem - 6.0]), color.darkened(0.3), 1.3)
		"wetsuit":
			for side: float in [-1.0, 1.0]:
				var x := 50.0 + side * (_leg_x + r - 1.5)
				_line(_p([x, _hip_y + 2.0, x, hem - 3.0]), Color("#2f6fd0"), 1.6)
		"bells":
			for side: float in [-1.0, 1.0]:
				var x := 50.0 + side * _leg_x
				_line(_p([x, _hip_y + 14.0, x, hem - 1.0]), color.darkened(0.12), 0.8)
	_line(_p([50.0 - _hip, _hip_y - 2.5, 50.0 + _hip, _hip_y - 2.5]), color.darkened(0.3), 1.2)  # The belt line.
	_shade_bottoms(hem)


## The skin packs' bottoms (breeches over stockings, slops, hose, ball
## pants, shin guards, slacks, knickers with stirrups): true if `style` is one.
func _draw_pack_bottoms(style: String, color: Color) -> bool:
	var r := _leg_r + 1.6
	var hem := _ankle_y - 1.5
	match style:
		"breeches":
			_stockings()
			_legs(color, _hip_y + 36.0 * _hf, r + 1.2)
			for side: float in [-1.0, 1.0]:
				var x := 50.0 + side * _leg_x
				_line(_p([x - r - 1.0, _hip_y + 34.0 * _hf, x + r + 1.0, _hip_y + 34.0 * _hf]), color.darkened(0.4), 1.6)
			_shade_bottoms(_hip_y + 36.0 * _hf)
		"slops":
			_legs(Color("#6b4a2e"), _hip_y + 42.0 * _hf, r + 2.8)
			_shade_bottoms(_hip_y + 42.0 * _hf)
		"hose":
			_legs(Color("#8a8a86"), hem, r - 0.6, false)
			_shade_bottoms(hem)
		"pants_pin":
			_legs(WHITE, hem, r, false)
			for side: float in [-1.0, 1.0]:
				var x := 50.0 + side * _leg_x
				for dx: float in [-3.0, 0.0, 3.0]:
					_line(_p([x + dx, _hip_y + 8.0, x + dx, hem - 1.0]), NAVY, 0.6)
			for dx: float in [-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]:  # (The seat too.)
				if absf(dx) < _hip - 1.0:
					_line(_p([50.0 + dx, _hip_y - 4.0, 50.0 + dx * 0.9, _hip_y + 8.0]), NAVY, 0.6)
			_line(_p([50.0 - _hip, _hip_y - 2.5, 50.0 + _hip, _hip_y - 2.5]), NAVY, 2.2)
			_shade_bottoms(hem)
		"pants_grey":
			_legs(GREY, hem, r, false)
			_line(_p([50.0 - _hip, _hip_y - 2.5, 50.0 + _hip, _hip_y - 2.5]), RED, 2.2)
			_shade_bottoms(hem)
		"pants_catcher":
			_legs(GREY, hem, r, false)
			for side: float in [-1.0, 1.0]:
				var x := 50.0 + side * _leg_x
				_capsule(Vector2(x, _hip_y + 36.0 * _hf), Vector2(x, _ankle_y - 2.0), _leg_r + 2.8, Color("#8a8f96"))
				for k in 4:
					var y := _hip_y + 40.0 * _hf + k * 6.0
					_line(_p([x - _leg_r - 1.5, y, x + _leg_r + 1.5, y]), Color("#b8bcc2"), 1.0)
			_line(_p([50.0 - _hip, _hip_y - 2.5, 50.0 + _hip, _hip_y - 2.5]), NAVY, 2.2)
			_shade_bottoms(hem)
		"slacks":
			_legs(Color("#6a6e74"), hem, r, false)
			_line(_p([50.0 - _hip, _hip_y - 2.5, 50.0 + _hip, _hip_y - 2.5]), Color("#1c1c1e"), 2.2)
			_shade_bottoms(hem)
		"khakis":
			_legs(Color("#c2a878"), hem, r, false)
			_line(_p([50.0 - _hip, _hip_y - 2.5, 50.0 + _hip, _hip_y - 2.5]), Color("#6b4a2e"), 1.6)
			_shade_bottoms(hem)
		"knickers":
			_stockings()
			for side: float in [-1.0, 1.0]:
				var x := 50.0 + side * _leg_x
				_capsule(Vector2(x, _hip_y + 40.0 * _hf), Vector2(x, _ankle_y - 1.5), _leg_r + 1.0, NAVY)
				_line(_p([x - _leg_r, _hip_y + 50.0 * _hf, x + _leg_r, _hip_y + 50.0 * _hf]), WHITE, 1.4)
			_legs(NAVY, _hip_y + 42.0 * _hf, r + 1.6)
			_shade_bottoms(_hip_y + 42.0 * _hf)
		_:
			return false
	return true

## The shade down the right of the bottoms.
func _shade_bottoms(hem: float) -> void:
	var x := 50.0 + _leg_x + _leg_r * 0.4
	_fill(_p([x, _hip_y - 4.0, 50.0 + _hip + 0.5, _hip_y - 4.0, x + _leg_r * 1.3, hem, x, hem]), SHADE)


func _draw_shoes(skin: Color) -> void:
	var shoes: Array = SHOES[_part("shoes")]
	var style: String = shoes[0]
	var color: Color = shoes[1]
	if _draw_pack_shoes(style, color):
		return
	for side: float in [-1.0, 1.0]:
		var x := 50.0 + side * _leg_x
		var r := _leg_r
		var toe := x + side * (r + 7.5)
		var heel := x - side * (r + 2.4)
		var top := _ankle_y - 3.0
		match style:
			"boots":
				top = _ankle_y - 11.0
			"wellies":
				top = _ankle_y - 20.0
		if style == "barefoot":
			_shape(_p([heel + side * 1.5, _ankle_y - 1.0, x + side * (r + 0.5), _ankle_y - 1.0, toe + side * 1.0, FLOOR - 2.5, toe + side * 2.0, FLOOR, heel + side * 1.5, FLOOR]), skin)
			for k in 3:
				_dot(Vector2(toe - side * k * 2.2, FLOOR - 1.5), 0.9, skin.darkened(0.2))
			continue
		if style == "sandals":
			_shape(_p([heel, FLOOR - 2.0, toe + side * 2.0, FLOOR - 2.0, toe + side * 2.0, FLOOR, heel, FLOOR]), color)
			_shape(_p([heel + side * 1.5, _ankle_y - 1.0, x + side * (r + 0.5), _ankle_y - 1.0, toe + side * 0.5, FLOOR - 2.5, heel + side * 1.5, FLOOR - 2.5]), skin)
			_line(_p([x - r + 1.0, FLOOR - 4.5, x + r + 2.0, FLOOR - 4.5]), color, 1.6)
			_line(_p([toe - side * 6.0, FLOOR - 3.2, toe - side * 1.0, FLOOR - 3.2]), color, 1.4)
			continue
		var body := _p([heel, top, x + side * (r + 2.4), top, x + side * (r + 2.4), _ankle_y + 1.0, toe + side * 1.5, _ankle_y + 2.5, toe + side * 2.0, FLOOR, heel, FLOOR])
		_shape(body, color)
		match style:
			"trainers":
				_shape(_p([heel, FLOOR - 3.0, toe + side * 2.0, FLOOR - 3.0, toe + side * 2.0, FLOOR, heel, FLOOR]), Color("#f8f8f8"), false)
				_line(_p([heel, FLOOR - 3.0, toe + side * 2.0, FLOOR - 3.0]), OUTLINE, 0.9)
				_line(_p([x - 2.0, top + 3.0, x + 2.5, top + 2.0]), color.darkened(0.35), 0.9)
			"deck":
				_shape(_p([heel, FLOOR - 2.5, toe + side * 2.0, FLOOR - 2.5, toe + side * 2.0, FLOOR, heel, FLOOR]), Color("#f8f8f8"), false)
				_line(_p([heel, FLOOR - 2.5, toe + side * 2.0, FLOOR - 2.5]), OUTLINE, 0.9)
				_line(_p([x - 2.5, top + 2.0, x + 2.5, top + 2.0]), Color("#f4f4f4"), 1.0)
			"dress":
				_line(_p([heel + side * 1.0, FLOOR - 1.5, toe + side * 1.0, FLOOR - 1.5]), color.lightened(0.35), 0.7)
			"wellies":
				_line(_p([heel + side * 1.0, top + 4.0, x + side * (r + 0.8), top + 4.0]), color.darkened(0.3) if color.get_luminance() > 0.4 else color.lightened(0.25), 1.2)
				_shape(_p([heel, FLOOR - 2.5, toe + side * 2.0, FLOOR - 2.5, toe + side * 2.0, FLOOR, heel, FLOOR]), color.darkened(0.3), false)
			"boots":
				_line(_p([heel + side * 1.0, top + 3.0, x + side * (r + 0.8), top + 3.0]), color.lightened(0.2), 1.0)
				for k in 3:
					_line(_p([x - 1.5, top + 4.5 + k * 2.2, x + 1.5, top + 4.5 + k * 2.2]), color.lightened(0.35), 0.7)
		_fill(_p([x + side * 1.0, top + 1.0, x + side * (r + 0.8), top + 1.0, toe + side * 1.5, FLOOR - 1.0, x + side * 1.0, FLOOR - 1.0]), SHADE if side > 0.0 else Color.TRANSPARENT)


## The skin packs' shoes (buckle shoes, cloth wraps, cleats): true if `style` is one.
func _draw_pack_shoes(style: String, color: Color) -> bool:
	if not style in ["buckle", "wraps", "cleats"]:
		return false
	for side: float in [-1.0, 1.0]:
		var x := 50.0 + side * _leg_x
		var r := _leg_r
		var toe := x + side * (r + 7.5)
		var heel := x - side * (r + 2.4)
		var top := _ankle_y - 3.0
		_shape(_p([heel, top, x + side * (r + 2.4), top, x + side * (r + 2.4), _ankle_y + 1.0, toe + side * 1.5, _ankle_y + 2.5, toe + side * 2.0, FLOOR, heel, FLOOR]), color)
		match style:
			"buckle":
				_line(_p([heel + side * 1.0, FLOOR - 1.5, toe + side * 1.0, FLOOR - 1.5]), color.lightened(0.35), 0.7)
				var bx := x + side * (r + 1.5)
				_shape(_p([bx - 2.0, _ankle_y - 2.0, bx + 2.0, _ankle_y - 2.0, bx + 2.0, _ankle_y + 1.5, bx - 2.0, _ankle_y + 1.5]), GOLD, true, 0.7)
			"wraps":
				_line(_p([x - 3.0, _ankle_y - 2.0, x + 4.0, _ankle_y + 1.0]), color.darkened(0.35), 0.9)
				_line(_p([x - 3.0, _ankle_y + 1.0, x + 4.0, _ankle_y - 2.0]), color.darkened(0.35), 0.9)
			"cleats":
				_line(_p([x - r + 1.0, FLOOR - 2.0, x + side * (r + 6.0), FLOOR - 2.0]), WHITE, 1.0)
		_fill(_p([x + side * 1.0, top + 1.0, x + side * (r + 0.8), top + 1.0, toe + side * 1.5, FLOOR - 1.0, x + side * 1.0, FLOOR - 1.0]), SHADE if side > 0.0 else Color.TRANSPARENT)
	return true


# --- Clothes -------------------------------------------------------------------

## The sleeves and the body of a top in a colour, the body down to a hem (the
## hips by default, lower for coats), the sleeves to a share of the arm.
func _garment(color: Color, sleeves: String, hem_y := -1.0, cuff := Color.TRANSPARENT) -> void:
	var reach := 0.0
	match sleeves:
		"short":
			reach = 0.36
		"long":
			reach = 0.9
	if reach > 0.0:
		for side: float in [-1.0, 1.0]:
			var top := _arm_top(side) - Vector2(0.0, 2.0)
			var end := _arm_top(side).lerp(_hand(side), reach)
			_capsule(top, end, _arm_r + 1.6, color)
			if cuff.a > 0.0:
				var up := _arm_top(side).lerp(_hand(side), reach - 0.08)
				_capsule(up, end, _arm_r + 1.9, cuff)
	_shape(_torso(hem_y), color)
	_shade_torso(hem_y if hem_y > 0.0 else _hip_y)


## A row of buttons down the middle of a top.
func _buttons(color: Color, from_y: float, to_y: float, count := 3, x := 50.0) -> void:
	for k in count:
		var at := Vector2(x, lerpf(from_y, to_y, (k + 0.5) / count))
		_dot(at, 1.9, OUTLINE)
		_dot(at, 1.3, color)


## A collar: a V of an undershirt in a colour.
func _vneck(color: Color, depth := 9.0, half := 6.0) -> void:
	_shape(_p([50.0 - half, _shoulder_y - 1.0, 50.0 + half, _shoulder_y - 1.0, 50.0, _shoulder_y + depth]), color)


func _draw_top(skin: Color) -> void:
	var top: Array = TOPS[_part("top")]
	var style: String = top[0]
	var color: Color = top[1]
	var sleeves: String = top[2]
	match style:
		"captain":
			_garment(color, sleeves)
			_vneck(WHITE, 10.0, 7.0)
			_shape(_p([49.0, _shoulder_y + 2.0, 51.0, _shoulder_y + 2.0, 52.0, _shoulder_y + 16.0, 50.0, _shoulder_y + 19.0, 48.0, _shoulder_y + 16.0]), Color("#1a1a1a"))
			_buttons(GOLD, _shoulder_y + 20.0, _hip_y - 4.0, 3, 45.0)
			_buttons(GOLD, _shoulder_y + 20.0, _hip_y - 4.0, 3, 55.0)
			for side: float in [-1.0, 1.0]:
				var cuff := _arm_top(side).lerp(_hand(side), 0.84)
				_line(_p([cuff.x - _arm_r - 1.0, cuff.y, cuff.x + _arm_r + 1.0, cuff.y]), GOLD, 1.6)
				_line(_p([cuff.x - _arm_r - 1.0, cuff.y + 3.0, cuff.x + _arm_r + 1.0, cuff.y + 3.0]), GOLD, 1.6)
				var board := _arm_top(side) + Vector2(side * 1.0, -4.0)
				_shape(_p([board.x - 4.0, board.y - 1.5, board.x + 4.0, board.y - 1.5, board.x + 4.0, board.y + 1.5, board.x - 4.0, board.y + 1.5]), GOLD, true, 0.9)
		"stripes":
			_garment(color, sleeves)
			var y := _shoulder_y + 8.0
			while y < _hip_y - 2.0:
				_line(_p([50.0 - _torso_half(y) + 0.8, y, 50.0 + _torso_half(y) - 0.8, y]), NAVY, 2.4)
				y += 6.0 * _hf
			for side: float in [-1.0, 1.0]:
				for k in range(1, 6):
					var at := _arm_top(side).lerp(_hand(side), 0.1 + k * 0.15)
					_line(_p([at.x - _arm_r - 1.0, at.y, at.x + _arm_r + 1.0, at.y]), NAVY, 2.2)
			_line(_ellipse_points(Vector2(50.0, _shoulder_y - 1.0), Vector2(8.0, 4.0), 0.0, PI, 10), NAVY, 1.4)
		"peacoat":
			_garment(color, sleeves, _hip_y + 16.0 * _hf)
			_vneck(WHITE, 8.0, 5.0)
			for side: float in [-1.0, 1.0]:
				_shape(_p([50.0 + side * 5.0, _shoulder_y - 1.0, 50.0 + side * _sh * 0.75, _shoulder_y + 1.0, 50.0 + side * 3.0, _shoulder_y + 20.0]), color.darkened(0.2))
			_buttons(Color("#3a3a3a"), _shoulder_y + 20.0, _hip_y + 6.0, 3, 45.0)
			_buttons(Color("#3a3a3a"), _shoulder_y + 20.0, _hip_y + 6.0, 3, 55.0)
		"oilskin":
			_ellipse(Vector2(50.0, _shoulder_y + 2.0), Vector2(_sh * 0.7, 7.0), color.darkened(0.12))  # The hood, behind the neck.
			_garment(color, sleeves, _hip_y + 14.0 * _hf)
			_line(_p([50.0, _shoulder_y + 4.0, 50.0, _hip_y + 12.0]), color.darkened(0.35), 1.1)
			for k in 3:
				var y := lerpf(_shoulder_y + 10.0, _hip_y + 6.0, (k + 0.5) / 3.0)
				_dot(Vector2(50.0, y), 1.6, Color("#9a9a9a"))
			_shape(_p([47.0, _shoulder_y - 1.0, 53.0, _shoulder_y - 1.0, 54.0, _shoulder_y + 5.0, 46.0, _shoulder_y + 5.0]), color.darkened(0.2))
		"fisherman":
			_garment(color, sleeves, -1.0, color.darkened(0.08))
			var cable := color.darkened(0.2)
			for x: float in [43.0, 50.0, 57.0]:
				var points := PackedVector2Array()
				var y := _shoulder_y + 8.0
				while y < _hip_y - 5.0:
					points.append(Vector2(x + sin(y * 0.8) * 1.2, y))
					y += 2.5
				_line(points, cable, 1.0)
			var y := _hip_y - 5.0
			while y < _hip_y:
				_line(_p([50.0 - _torso_half(y) + 0.5, y, 50.0 + _torso_half(y) - 0.5, y]), cable, 0.7)
				y += 2.0
			_line(_ellipse_points(Vector2(50.0, _shoulder_y), Vector2(7.5, 3.5), 0.0, PI, 10), cable, 1.6)
		"whites":
			_garment(color, sleeves)
			_shape(_p([47.0, _shoulder_y - 1.0, 53.0, _shoulder_y - 1.0, 53.0, _shoulder_y + 3.0, 47.0, _shoulder_y + 3.0]), color.darkened(0.06))
			_buttons(GOLD, _shoulder_y + 8.0, _hip_y - 4.0, 5)
			for side: float in [-1.0, 1.0]:
				var board := _arm_top(side) + Vector2(side * 1.0, -4.0)
				_shape(_p([board.x - 4.5, board.y - 1.5, board.x + 4.5, board.y - 1.5, board.x + 4.5, board.y + 1.5, board.x - 4.5, board.y + 1.5]), NAVY, true, 0.9)
				_line(_p([board.x - 3.0, board.y, board.x + 3.0, board.y]), GOLD, 1.0)
		"decktee":
			_garment(color, sleeves)
			_line(_ellipse_points(Vector2(50.0, _shoulder_y - 1.0), Vector2(6.5, 3.0), 0.0, PI, 10), color.darkened(0.3), 1.2)
			var c := Vector2(50.0, _shoulder_y + 20.0)  # A small anchor.
			_line(_p([c.x, c.y - 6.0, c.x, c.y + 6.0]), WHITE, 1.6)
			_line(_p([c.x - 4.0, c.y - 2.5, c.x + 4.0, c.y - 2.5]), WHITE, 1.4)
			_line(_ellipse_points(c + Vector2(0.0, 2.0), Vector2(5.0, 4.5), 0.3, PI - 0.3, 10), WHITE, 1.6)
			_line(_ellipse_points(c + Vector2(0.0, -7.5), Vector2(1.6, 1.6)), WHITE, 1.0)
		"lifevest":
			_garment(color, sleeves)
			var vest := Color("#ff7a1f")
			for side: float in [-1.0, 1.0]:
				var points := PackedVector2Array()
				points.append(Vector2(50.0 + side * 3.5, _shoulder_y + 2.0))
				points.append(Vector2(50.0 + side * (_sh - 2.0), _shoulder_y + 1.0))
				var y := _shoulder_y + 6.0
				while y < _hip_y - 2.0:
					points.append(Vector2(50.0 + side * (_torso_half(y) - 1.5), y))
					y += 6.0
				points.append(Vector2(50.0 + side * (_torso_half(_hip_y - 2.0) - 1.5), _hip_y - 2.0))
				points.append(Vector2(50.0 + side * 3.5, _hip_y - 2.0))
				_shape(points, vest)
			for y: float in [_shoulder_y + 20.0, _hip_y - 10.0]:
				_line(_p([50.0 - _torso_half(y) + 1.0, y, 50.0 + _torso_half(y) - 1.0, y]), Color("#1a1a1a"), 1.8)
				_dot(Vector2(50.0, y), 1.6, Color("#1a1a1a"))
		"wetsuit":
			_garment(color, sleeves)
			_shape(_p([43.0, _shoulder_y + 1.0, 57.0, _shoulder_y + 1.0, 55.0, _waist_y, 45.0, _waist_y]), Color("#2f6fd0"), false)
			_line(_p([50.0, _shoulder_y - 1.0, 50.0, _waist_y]), Color("#9ad0ff"), 0.8)
			for side: float in [-1.0, 1.0]:
				var a := _arm_top(side)
				var b := _arm_top(side).lerp(_hand(side), 0.85)
				_line(_p([a.x + side * 2.5, a.y + 2.0, b.x + side * 2.5, b.y]), Color("#2f6fd0"), 1.6)
		"officer":
			_garment(color, sleeves)
			_vneck(skin.lightened(0.1), 5.0, 3.5)
			for side: float in [-1.0, 1.0]:
				_shape(_p([50.0 + side * 3.5, _shoulder_y - 1.5, 50.0 + side * 9.0, _shoulder_y + 1.0, 50.0 + side * 2.0, _shoulder_y + 7.0]), WHITE)
				var board := _arm_top(side) + Vector2(side * 1.0, -4.0)
				_shape(_p([board.x - 4.5, board.y - 1.5, board.x + 4.5, board.y - 1.5, board.x + 4.5, board.y + 1.5, board.x - 4.5, board.y + 1.5]), NAVY, true, 0.9)
				_line(_p([board.x - 3.0, board.y, board.x + 3.0, board.y]), GOLD, 1.0)
			_buttons(Color("#d8d8d8"), _shoulder_y + 10.0, _hip_y - 4.0, 4)
			_shape(_p([54.0, _shoulder_y + 12.0, 61.0, _shoulder_y + 12.0, 61.0, _shoulder_y + 19.0, 54.0, _shoulder_y + 19.0]), color, true, 0.8)
		"tropical":
			_garment(color, sleeves)
			_vneck(skin.lightened(0.1), 7.0, 4.0)
			for side: float in [-1.0, 1.0]:
				_shape(_p([50.0 + side * 4.0, _shoulder_y - 1.5, 50.0 + side * 10.0, _shoulder_y + 1.0, 50.0 + side * 2.0, _shoulder_y + 8.0]), color.darkened(0.1))
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			for k in 12:
				var y := rng.randf_range(_shoulder_y + 10.0, _hip_y - 4.0)
				var x := 50.0 + rng.randf_range(-1.0, 1.0) * (_torso_half(y) - 4.0)
				var petal: Color = [Color("#ff6f91"), Color("#ffd166"), Color("#f4f4f4")][k % 3]
				for a in 5:
					_dot(Vector2(x, y) + Vector2.from_angle(TAU * a / 5.0) * 1.3, 0.8, petal)
				_dot(Vector2(x, y), 0.6, Color("#ffd166"))
			_buttons(WHITE, _shoulder_y + 10.0, _hip_y - 4.0, 4)
		"pirate":
			_garment(color, sleeves, _hip_y + 20.0 * _hf, GOLD.darkened(0.1))
			_vneck(Color("#f1e6c8"), 12.0, 8.0)
			for side: float in [-1.0, 1.0]:
				_shape(_p([50.0 + side * 8.0, _shoulder_y - 1.0, 50.0 + side * (_sh * 0.85), _shoulder_y + 1.0, 50.0 + side * 4.0, _shoulder_y + 24.0]), color.darkened(0.25))
				_line(_p([50.0 + side * 8.0, _shoulder_y - 0.5, 50.0 + side * (_sh * 0.85), _shoulder_y + 1.0, 50.0 + side * 4.0, _shoulder_y + 24.0]), GOLD, 1.0)
			_buttons(GOLD, _shoulder_y + 26.0, _hip_y + 8.0, 4, 45.0)
			_buttons(GOLD, _shoulder_y + 26.0, _hip_y + 8.0, 4, 55.0)
			_line(_p([50.0 - _hip - 2.0, _hip_y + 19.0 * _hf, 50.0 + _hip + 2.0, _hip_y + 19.0 * _hf]), GOLD, 1.2)
			_line(_p([50.0 - _torso_half(_waist_y) + 1.0, _waist_y + 2.0, 50.0 + _torso_half(_waist_y) - 1.0, _waist_y + 2.0]), Color("#3a2414"), 3.0)  # A broad belt.
			_shape(_p([47.5, _waist_y - 0.5, 52.5, _waist_y - 0.5, 52.5, _waist_y + 4.5, 47.5, _waist_y + 4.5]), GOLD, true, 0.8)
		"tee":
			_garment(color, sleeves)
			_line(_ellipse_points(Vector2(50.0, _shoulder_y - 1.0), Vector2(6.5, 3.0), 0.0, PI, 10), color.darkened(0.3), 1.2)
		"hoodie":
			_ellipse(Vector2(50.0, _shoulder_y + 2.0), Vector2(_sh * 0.72, 7.5), color.darkened(0.15))  # The hood, behind the neck.
			_garment(color, sleeves)
			_shape(_p([50.0 - _waist * 0.8, _hip_y - 18.0, 50.0 + _waist * 0.8, _hip_y - 18.0, 50.0 + _hip * 0.85, _hip_y - 3.0, 50.0 - _hip * 0.85, _hip_y - 3.0]), color.darkened(0.08))
			_line(_p([47.0, _shoulder_y + 4.0, 46.0, _shoulder_y + 20.0]), WHITE, 1.0)
			_line(_p([53.0, _shoulder_y + 4.0, 54.0, _shoulder_y + 20.0]), WHITE, 1.0)
		"suit":
			_garment(color, sleeves, _hip_y + 6.0 * _hf)
			_vneck(WHITE, 18.0, 7.0)
			_shape(_p([49.0, _shoulder_y + 2.0, 51.0, _shoulder_y + 2.0, 52.0, _shoulder_y + 16.0, 50.0, _shoulder_y + 19.0, 48.0, _shoulder_y + 16.0]), Color("#b8323a"))
			for side: float in [-1.0, 1.0]:
				_line(_p([50.0 + side * 7.0, _shoulder_y - 1.0, 50.0 + side * 2.0, _shoulder_y + 26.0, 50.0 + side * 1.0, _hip_y + 4.0]), color.lightened(0.3), 1.0)
			_dot(Vector2(50.0, _shoulder_y + 28.0), 1.4, Color("#555555"))
		"flannel":
			_garment(color, sleeves)
			var dark := color.darkened(0.35)
			var y := _shoulder_y + 8.0
			while y < _hip_y - 2.0:
				_line(_p([50.0 - _torso_half(y) + 0.8, y, 50.0 + _torso_half(y) - 0.8, y]), dark, 1.3)
				y += 7.0 * _hf
			var x := 50.0 - _sh + 4.0
			while x < 50.0 + _sh - 3.0:
				# Each vertical thread follows the torso's taper from the shoulders to the hips.
				_line(_p([x, _shoulder_y + 3.0, 50.0 + (x - 50.0) * (_torso_half(_hip_y) / _sh), _hip_y - 1.0]), dark, 1.1)
				x += 7.0
			_line(_p([50.0, _shoulder_y + 2.0, 50.0, _hip_y - 1.0]), Color(0, 0, 0, 0.35), 0.8)
			_buttons(Color("#f0e6c8"), _shoulder_y + 8.0, _hip_y - 4.0, 4)
		"hivis":
			_garment(color, sleeves)
			var vest := Color("#ff8a1f")
			var points := PackedVector2Array()
			points.append(Vector2(50.0 - _sh + 2.0, _shoulder_y + 3.0))
			points.append(Vector2(50.0 - 7.0, _shoulder_y - 1.0))
			points.append(Vector2(50.0 - 4.0, _shoulder_y + 22.0))
			points.append(Vector2(50.0 + 4.0, _shoulder_y + 22.0))
			points.append(Vector2(50.0 + 7.0, _shoulder_y - 1.0))
			points.append(Vector2(50.0 + _sh - 2.0, _shoulder_y + 3.0))
			points.append(Vector2(50.0 + _torso_half(_hip_y - 2.0) - 1.0, _hip_y - 2.0))
			points.append(Vector2(50.0 - _torso_half(_hip_y - 2.0) + 1.0, _hip_y - 2.0))
			_shape(points, vest)
			for y: float in [_hip_y - 18.0, _hip_y - 9.0]:
				_line(_p([50.0 - _torso_half(y) + 1.5, y, 50.0 + _torso_half(y) - 1.5, y]), Color("#d8dde2"), 2.8)
		"pilgrim_m":
			_garment(BLACK, "long", -1.0, WHITE)
			_collar_falling()
			_buttons(Color("#8a8a8a"), _shoulder_y + 17.0, _hip_y - 4.0, 5)
			_line(_p([50.0 - _torso_half(_waist_y) + 0.5, _waist_y + 1.0, 50.0 + _torso_half(_waist_y) - 0.5, _waist_y + 1.0]), Color("#3a2414"), 3.0)
			_shape(_p([47.5, _waist_y - 1.5, 52.5, _waist_y - 1.5, 52.5, _waist_y + 3.5, 47.5, _waist_y + 3.5]), GOLD, true, 0.8)
		"pilgrim_f":
			var gown := Color("#5e6a86")
			_shape(_p([50.0 - _hip - 1.0, _hip_y - 6.0, 50.0 + _hip + 1.0, _hip_y - 6.0, 50.0 + _hip + 13.0, _ankle_y - 2.0, 50.0 - _hip - 13.0, _ankle_y - 2.0]), gown)
			_garment(gown, "long", _hip_y + 4.0, WHITE)
			_shape(_p([50.0 - _waist * 0.7, _waist_y + 2.0, 50.0 + _waist * 0.7, _waist_y + 2.0, 50.0 + _hip + 8.0, _ankle_y - 7.0, 50.0 - _hip - 8.0, _ankle_y - 7.0]), Color("#f8f6f0"))
			_line(_p([50.0 - _waist * 0.7, _waist_y + 2.0, 50.0 + _waist * 0.7, _waist_y + 2.0]), Color("#d8d2c4"), 1.6)
			_collar_falling()
		"colonial":
			var coat := Color("#2d4a8a")
			_garment(coat, "long", _hip_y + 22.0 * _hf, Color("#c9a24a"))
			_shape(_p([41.0, _shoulder_y + 4.0, 59.0, _shoulder_y + 4.0, 58.0, _hip_y + 10.0, 42.0, _hip_y + 10.0]), Color("#e8d9a6"))
			_buttons(GOLD, _shoulder_y + 12.0, _hip_y + 6.0, 6)
			for side: float in [-1.0, 1.0]:
				_line(_p([50.0 + side * 10.0, _shoulder_y + 2.0, 50.0 + side * 9.0, _hip_y + 20.0 * _hf]), GOLD, 1.1)
				_shape(_p([50.0 + side * 10.0, _shoulder_y + 1.0, 50.0 + side * (_sh * 0.9), _shoulder_y + 2.0, 50.0 + side * 6.0, _shoulder_y + 26.0]), coat.darkened(0.25))
			_ellipse(Vector2(50.0, _shoulder_y + 3.0), Vector2(6.5, 5.0), Color("#f8f6f0"))
			_shape(_p([47.0, _shoulder_y + 6.0, 53.0, _shoulder_y + 6.0, 52.0, _shoulder_y + 16.0, 48.0, _shoulder_y + 16.0]), Color("#f8f6f0"))
		"deckhand":
			_garment(LINEN, "long")
			_shape(_torso(_hip_y + 6.0 * _hf), LEATHER)
			_vneck(LINEN, 14.0, 6.0)
			for k in 3:
				var y := _shoulder_y + 2.0 + k * 4.0
				_line(_p([46.0 + k * 1.0, y, 54.0 - k * 1.0, y + 3.0]), Color("#5a3a1a"), 0.8)
				_line(_p([54.0 - k * 1.0, y, 46.0 + k * 1.0, y + 3.0]), Color("#5a3a1a"), 0.8)
			_rope_belt()
		"farmhand":
			var wool := Color("#8a7a62")
			_garment(wool, "long", _hip_y + 10.0 * _hf)
			_shape(_p([40.0, _shoulder_y + 22.0, 47.0, _shoulder_y + 22.0, 47.0, _shoulder_y + 30.0, 40.0, _shoulder_y + 30.0]), wool.darkened(0.3), true, 0.9)
			_shape(_p([54.0, _hip_y - 10.0, 60.0, _hip_y - 10.0, 60.0, _hip_y - 3.0, 54.0, _hip_y - 3.0]), Color("#6b5a42"), true, 0.9)
			_line(_p([44.0, _shoulder_y - 1.0, 50.0, _shoulder_y + 9.0, 56.0, _shoulder_y - 1.0]), wool.darkened(0.35), 1.0)
			_rope_belt()
		"pinstripes":
			_garment(WHITE, "short")
			_torso_stripes(NAVY, 4.2, 0.7)
			_shape(_p([47.0, _shoulder_y + 1.0, 53.0, _shoulder_y + 1.0, 53.0, _hip_y - 1.0, 47.0, _hip_y - 1.0]), WHITE, false)
			_buttons(NAVY, _shoulder_y + 8.0, _hip_y - 4.0, 5)
			_line(_ellipse_points(Vector2(50.0, _shoulder_y - 1.0), Vector2(7.0, 3.5), 0.0, PI, 10), NAVY, 1.4)
			_sleeve_trim(NAVY, 0.36)
		"road_grey":
			_garment(GREY, "short")
			_line(_p([46.5, _shoulder_y + 2.0, 46.5, _hip_y - 2.0]), RED, 1.2)
			_line(_p([53.5, _shoulder_y + 2.0, 53.5, _hip_y - 2.0]), RED, 1.2)
			_buttons(RED, _shoulder_y + 8.0, _hip_y - 4.0, 5)
			_line(_ellipse_points(Vector2(50.0, _shoulder_y - 1.0), Vector2(7.0, 3.5), 0.0, PI, 10), RED, 1.6)
			_sleeve_trim(RED, 0.36, 1.8)
			_shape(_p([56.0, _shoulder_y + 10.0, 60.0, _shoulder_y + 10.0, 60.0, _shoulder_y + 18.0, 56.0, _shoulder_y + 18.0]), RED, true, 0.8)
		"catcher":
			_garment(NAVY, "short")
			var pad := Color("#2a3a62")
			_shape(_p([50.0 - _sh * 0.8, _shoulder_y + 4.0, 50.0 + _sh * 0.8, _shoulder_y + 4.0, 50.0 + _hip * 0.95, _hip_y + 8.0 * _hf, 50.0 - _hip * 0.95, _hip_y + 8.0 * _hf]), pad)
			var y := _shoulder_y + 10.0
			while y < _hip_y + 4.0:
				_line(_p([50.0 - _torso_half(minf(y, _hip_y)) * 0.85, y, 50.0 + _torso_half(minf(y, _hip_y)) * 0.85, y]), pad.lightened(0.25), 1.1)
				y += 6.0
			_line(_p([50.0 - _sh * 0.8, _shoulder_y + 4.0, 50.0 - _hip * 0.95, _hip_y + 8.0 * _hf]), RED, 1.4)
			_line(_p([50.0 + _sh * 0.8, _shoulder_y + 4.0, 50.0 + _hip * 0.95, _hip_y + 8.0 * _hf]), RED, 1.4)
		"umpire":
			var black := Color("#1c1c1e")
			_garment(black, "short")
			_shape(_p([50.0 - _sh * 0.75, _shoulder_y + 6.0, 50.0 + _sh * 0.75, _shoulder_y + 6.0, 50.0 + _waist * 0.9, _waist_y + 6.0, 50.0 - _waist * 0.9, _waist_y + 6.0]), Color("#2c2c30"), false)
			_shape(_p([43.0, _shoulder_y - 1.0, 50.0, _shoulder_y + 7.0, 57.0, _shoulder_y - 1.0, 55.0, _shoulder_y + 4.0, 50.0, _shoulder_y + 10.0, 45.0, _shoulder_y + 4.0]), Color("#3a3a3e"))
			_buttons(Color("#4a4a4e"), _shoulder_y + 10.0, _shoulder_y + 22.0, 2)
			_sleeve_trim(Color("#3a3a3e"), 0.36, 1.2)
		"vendor":
			_garment(Color("#f6f1e6"), "short")
			_torso_stripes(RED, 6.0, 2.4)
			_shape(_p([42.0, _shoulder_y + 9.0, 58.0, _shoulder_y + 9.0, 50.0 + _hip + 3.0, _hip_y + 12.0 * _hf, 50.0 - _hip - 3.0, _hip_y + 12.0 * _hf]), Color("#f8f6f0"))
			_line(_p([42.0, _shoulder_y + 9.0, 50.0, _shoulder_y - 1.0, 58.0, _shoulder_y + 9.0]), Color("#d8d2c4"), 1.2)
			_line(_p([50.0 - _torso_half(_waist_y) + 0.5, _waist_y + 3.0, 50.0 + _torso_half(_waist_y) - 0.5, _waist_y + 3.0]), Color("#2a2a2a"), 2.4)
			_shape(_p([54.0, _waist_y + 1.0, 62.0, _waist_y + 1.0, 62.0, _waist_y + 9.0, 54.0, _waist_y + 9.0]), Color("#8a8f96"), true, 0.9)
		"flannel_1920":
			_garment(NAVY, "long")
			_garment(Color("#efe6cc"), "short")
			_shape(_p([47.0, _shoulder_y + 1.0, 53.0, _shoulder_y + 1.0, 53.0, _hip_y - 1.0, 47.0, _hip_y - 1.0]), NAVY, false)
			_buttons(Color("#efe6cc"), _shoulder_y + 8.0, _hip_y - 4.0, 4)
			_line(_ellipse_points(Vector2(50.0, _shoulder_y - 1.0), Vector2(7.5, 4.0), 0.0, PI, 10), NAVY, 2.2)
			_line(_p([50.0 - _torso_half(_hip_y - 2.0) + 0.5, _hip_y - 2.0, 50.0 + _torso_half(_hip_y - 2.0) - 0.5, _hip_y - 2.0]), NAVY, 3.0)


func _draw_neck_and_head(skin: Color) -> void:
	var neck_half := 5.5 * pow(_bf, 0.4)
	_shape(_p([50.0 - neck_half, _neck_top - 2.0, 50.0 + neck_half, _neck_top - 2.0, 50.0 + neck_half + 1.0, _shoulder_y + 3.0, 50.0 - neck_half - 1.0, _shoulder_y + 3.0]), skin.darkened(0.1))
	for side: float in [-1.0, 1.0]:
		_ellipse(Vector2(50.0 + side * (HEAD_RADII.x - 0.5), _head.y + 2.0), Vector2(4.0, 5.0), skin)
		_dot(Vector2(50.0 + side * (HEAD_RADII.x - 0.8), _head.y + 2.5), 1.6, skin.darkened(0.18))
	_ellipse(_head, HEAD_RADII, skin)
	# The one soft shade, down the right of the face, and the cheeks' blush.
	var shade := _ellipse_points(_head, HEAD_RADII - Vector2(0.6, 0.6), -PI * 0.45, PI * 0.45, 12)
	shade.append_array(_ellipse_points(_head + Vector2(1.0, 0.0), HEAD_RADII * Vector2(0.62, 0.92), PI * 0.45, -PI * 0.45, 12))
	_fill(shade, SHADE)
	for side: float in [-1.0, 1.0]:
		_dot(_head + Vector2(side * 11.0, 6.5), 3.2, Color(0.95, 0.45, 0.5, 0.16))


# --- Face ----------------------------------------------------------------------

func _eye(side: float) -> Vector2:
	return _head + Vector2(side * 7.5, -1.0)


func _draw_eyes(hair: Color) -> void:
	var shape := _part("eye_shape")  # Round, almond, narrow, wide, sleepy, lashes, smiling, squint.
	var iris: Color = EYE_COLORS[_part("eye_color")]
	var brow := hair.darkened(0.2) if hair.get_luminance() < 0.75 else hair.darkened(0.45)
	var lid := Color("#2a1d16")
	for side: float in [-1.0, 1.0]:
		var at := _eye(side)
		# The eyebrow: a thick arch, raised when wide, angled in when squinting.
		var inner := at + Vector2(-side * 3.8, -6.6)
		var outer := at + Vector2(side * 4.2, -7.2)
		var peak := at + Vector2(side * 0.5, -8.2)
		match shape:
			3:
				inner.y -= 1.2
				outer.y -= 1.2
				peak.y -= 1.6
			7:
				inner.y += 1.2
				outer.y -= 0.6
				peak.y += 0.2
		_line(PackedVector2Array([inner, peak, outer]), brow, 2.0)
		if shape == 6:  # Smiling: a happy closed arc.
			_line(_ellipse_points(at + Vector2(0, 1.2), Vector2(3.6, 2.8), PI + 0.15, TAU - 0.15, 10), lid, 1.7)
			continue
		var radii := Vector2(4.6, 4.0)
		var iris_r := 2.7
		match shape:
			1:  # Almond.
				radii = Vector2(4.8, 3.2)
				iris_r = 2.5
			2, 7:  # Narrow, squint.
				radii = Vector2(4.6, 2.1)
				iris_r = 2.1
			3:  # Wide.
				radii = Vector2(5.2, 4.8)
				iris_r = 3.1
		_ellipse(at, radii, Color("#fbfbfb"), false)
		var look := Vector2(0.3, 0.2)
		_dot(at + look, iris_r, iris)
		_dot(at + look, iris_r * 0.5, Color("#141414"))
		_dot(at + look + Vector2(-iris_r * 0.35, -iris_r * 0.4), iris_r * 0.34, Color.WHITE)
		_dot(at + look + Vector2(iris_r * 0.35, iris_r * 0.35), iris_r * 0.16, Color.WHITE)
		# The lids: a bold upper line, a thinner lower one.
		_line(_ellipse_points(at, radii, PI, TAU, 12), lid, 1.5)
		_line(_ellipse_points(at, radii, 0.0, PI, 12), Color(lid, 0.55), 0.8)
		match shape:
			4:  # Sleepy: a heavy lid over the top half.
				_fill(_ellipse_points(at + Vector2(0.0, -0.2), radii + Vector2(0.4, 0.4), PI, TAU, 12), SKINS[_part("skin")].darkened(0.12))
				_line(_p([at.x - radii.x - 0.4, at.y - 0.2, at.x + radii.x + 0.4, at.y - 0.2]), lid, 1.5)
			5:  # Lashes.
				for k in 3:
					var root := at + Vector2(side * (1.0 + k * 1.3), -radii.y + 0.6 - k * 0.3)
					_line(_p([root.x, root.y, root.x + side * 1.8, root.y - 1.8]), lid, 1.0)
			1:  # Almond: the upper lid curves higher at the outer corner.
				_line(_p([at.x + side * (radii.x - 1.5), at.y - radii.y + 0.6, at.x + side * (radii.x + 0.8), at.y - radii.y - 0.3]), lid, 1.5)


func _draw_nose(skin: Color) -> void:
	var shade := skin.darkened(0.2)
	var line := skin.darkened(0.45)
	var at := _head + Vector2(0.0, 6.0)
	match _part("nose"):
		0:  # Button.
			_ellipse(at, Vector2(2.6, 2.2), shade, false)
			_line(_ellipse_points(at, Vector2(2.6, 2.2), 0.2, PI - 0.2, 10), line, 1.1)
		1:  # Long.
			_line(_p([at.x, at.y - 8.0, at.x + 1.2, at.y + 2.0, at.x - 1.8, at.y + 3.0]), line, 1.3)
		2:  # Wide.
			_line(_ellipse_points(at + Vector2(0.0, 0.5), Vector2(5.0, 2.6), 0.2, PI - 0.2, 10), line, 1.3)
			_dot(at + Vector2(-2.8, 1.8), 0.9, line)
			_dot(at + Vector2(2.8, 1.8), 0.9, line)
		3:  # Pointed.
			_shape(_p([at.x, at.y - 7.0, at.x + 3.4, at.y + 2.5, at.x - 2.6, at.y + 2.5]), shade, false)
			_line(_p([at.x, at.y - 7.0, at.x + 3.4, at.y + 2.5, at.x - 2.6, at.y + 2.5]), line, 1.1)
		4:  # Hooked.
			_line(_p([at.x - 0.5, at.y - 8.0, at.x + 3.2, at.y - 1.0, at.x + 2.2, at.y + 3.0, at.x - 1.8, at.y + 2.5]), line, 1.3)
		5:  # Small.
			_dot(at + Vector2(-1.2, 1.5), 0.85, line)
			_dot(at + Vector2(1.2, 1.5), 0.85, line)
		6:  # Roman.
			_line(_p([at.x, at.y - 9.0, at.x + 2.8, at.y + 0.0, at.x + 1.4, at.y + 3.0, at.x - 2.0, at.y + 2.5]), line, 1.5)
		7:  # Snub.
			_line(_ellipse_points(at + Vector2(0.0, 0.5), Vector2(2.8, 2.4), PI + 0.3, TAU - 0.3, 10), line, 1.3)
			_dot(at + Vector2(-1.3, 1.8), 0.7, line)
			_dot(at + Vector2(1.3, 1.8), 0.7, line)
		8:  # Broad.
			_ellipse(at + Vector2(0.0, 0.5), Vector2(4.4, 2.9), shade, false)
			_line(_ellipse_points(at + Vector2(0.0, 0.5), Vector2(4.4, 2.9), 0.15, PI - 0.15, 12), line, 1.2)
		9:  # Freckled.
			_ellipse(at, Vector2(2.4, 2.1), shade, false)
			_line(_ellipse_points(at, Vector2(2.4, 2.1), 0.2, PI - 0.2, 10), line, 1.1)
			for spot: Vector2 in [Vector2(-9.0, 3.0), Vector2(-7.0, 5.5), Vector2(-10.5, 6.0), Vector2(9.0, 3.0), Vector2(7.0, 5.5), Vector2(10.5, 6.0), Vector2(-5.5, 3.5), Vector2(5.5, 3.5)]:
				_dot(_head + spot, 0.7, Color("#a5603a"))


func _draw_mouth(skin: Color) -> void:
	var line := Color("#4a2420")
	var lip := skin.darkened(0.25).lerp(Color("#c0504d"), 0.4)
	var at := _head + Vector2(0.0, 13.0)
	match _part("mouth"):
		0:  # Smile.
			_line(_ellipse_points(at + Vector2(0, -2.0), Vector2(5.5, 3.4), 0.25, PI - 0.25, 12), line, 1.7)
		1:  # Grin.
			var grin := _ellipse_points(at + Vector2(0, -1.0), Vector2(6.0, 4.0), 0.0, PI, 12)
			_shape(grin, Color("#fbfbfb"), true, 1.4)
			_line(_p([at.x - 5.5, at.y + 0.6, at.x + 5.5, at.y + 0.6]), Color(0, 0, 0, 0.25), 0.6)
		2:  # Straight.
			_line(_p([at.x - 4.5, at.y, at.x + 4.5, at.y]), line, 1.7)
		3:  # Smirk.
			_line(_p([at.x - 4.5, at.y + 0.6, at.x + 2.0, at.y + 0.3, at.x + 5.0, at.y - 2.0]), line, 1.7)
		4:  # Laugh.
			var open := _ellipse_points(at + Vector2(0, -0.5), Vector2(5.5, 5.0), 0.0, PI, 12)
			_shape(open, Color("#5a1a1a"), true, 1.4)
			_ellipse(at + Vector2(0, 2.6), Vector2(3.0, 1.6), Color("#d0606a"), false)
			_shape(_p([at.x - 5.0, at.y - 0.5, at.x + 5.0, at.y - 0.5, at.x + 4.0, at.y + 1.2, at.x - 4.0, at.y + 1.2]), Color("#fbfbfb"), false)
		5:  # Surprised.
			_ellipse(at + Vector2(0, 0.5), Vector2(2.4, 3.0), Color("#5a1a1a"), true)
		6:  # Frown.
			_line(_ellipse_points(at + Vector2(0, 3.0), Vector2(5.0, 3.0), PI + 0.3, TAU - 0.3, 12), line, 1.7)
		7:  # Red lips.
			_shape(_p([at.x - 5.2, at.y, at.x - 2.5, at.y - 2.2, at.x, at.y - 1.3, at.x + 2.5, at.y - 2.2, at.x + 5.2, at.y, at.x + 2.5, at.y + 2.4, at.x - 2.5, at.y + 2.4]), Color("#c42f42"), true, 1.0)
			_line(_p([at.x - 4.8, at.y, at.x + 4.8, at.y]), Color("#7a1a28"), 0.8)
		8:  # Cheeky.
			_line(_ellipse_points(at + Vector2(0, -2.0), Vector2(5.5, 3.4), 0.25, PI - 0.25, 12), line, 1.7)
			_ellipse(at + Vector2(2.0, 2.4), Vector2(2.0, 1.8), Color("#d0606a"), true)
		9:  # Gentle.
			_shape(_ellipse_points(at + Vector2(0, -0.8), Vector2(4.5, 2.0), 0.0, PI, 10), lip, false)
			_line(_ellipse_points(at + Vector2(0, -1.2), Vector2(4.5, 1.8), 0.2, PI - 0.2, 10), line, 1.2)


## A band of beard round the jaw: the lower face's edge out from one angle to
## the other, back along a smaller arc (inner, as a share of the head's radii).
func _jaw(inner := 0.6, drop := 0.0, from := PI * 0.12, to := PI * 0.88) -> PackedVector2Array:
	var points := _ellipse_points(_head, HEAD_RADII + Vector2(0.8, 0.8 + drop), from, to, 16)
	points.append_array(_ellipse_points(_head + Vector2(0.0, 2.0), HEAD_RADII * inner, to, from, 12))
	return points


func _draw_beard(hair: Color) -> void:
	match _part("facial_hair"):
		1:  # Stubble.
			_fill(_jaw(0.62), Color(hair, 0.3))
		4:  # Full beard.
			_shape(_jaw(0.6, 3.0), hair)
		5:  # Chinstrap.
			_shape(_jaw(0.9), hair)
		8:  # Mutton chops.
			for side: float in [-1.0, 1.0]:
				var from := PI * 0.25 if side > 0.0 else PI * 0.75
				var to := PI * 0.0 if side > 0.0 else PI * 1.0
				var points := _ellipse_points(_head, HEAD_RADII + Vector2(0.8, 0.8), from, to, 8)
				points.append_array(_ellipse_points(_head + Vector2(0.0, 2.0), HEAD_RADII * 0.7, to, from, 8))
				_shape(points, hair)
		9:  # Long beard.
			var points := _ellipse_points(_head, HEAD_RADII + Vector2(0.8, 0.8), PI * 0.12, PI * 0.42, 8)
			points.append(_head + Vector2(6.0, HEAD_RADII.y + 15.0))
			points.append(_head + Vector2(0.0, HEAD_RADII.y + 21.0))
			points.append(_head + Vector2(-6.0, HEAD_RADII.y + 15.0))
			points.append_array(_ellipse_points(_head, HEAD_RADII + Vector2(0.8, 0.8), PI * 0.58, PI * 0.88, 8))
			points.append_array(_ellipse_points(_head + Vector2(0.0, 2.0), HEAD_RADII * 0.6, PI * 0.88, PI * 0.12, 12))
			_shape(points, hair)


func _draw_moustache(hair: Color) -> void:
	var at := _head + Vector2(0.0, 9.8)
	var tash := _p([at.x - 6.5, at.y + 0.8, at.x - 3.0, at.y - 1.6, at.x, at.y - 0.6, at.x + 3.0, at.y - 1.6, at.x + 6.5, at.y + 0.8, at.x + 3.0, at.y + 0.6, at.x, at.y + 1.4, at.x - 3.0, at.y + 0.6])
	match _part("facial_hair"):
		2, 3:  # Moustache, goatee.
			_shape(tash, hair)
			if _part("facial_hair") == 3:
				_shape(_p([at.x - 4.0, at.y + 6.0, at.x + 4.0, at.y + 6.0, at.x + 3.0, at.y + 11.0, at.x, at.y + 12.5, at.x - 3.0, at.y + 11.0]), hair)
		4, 9:  # The full and long beards' moustache.
			_shape(tash, hair.darkened(0.12))
		6:  # Handlebar.
			_shape(tash, hair)
			for side: float in [-1.0, 1.0]:
				_line(_p([at.x + side * 6.0, at.y + 0.5, at.x + side * 10.0, at.y - 0.5, at.x + side * 11.5, at.y - 3.5, at.x + side * 9.5, at.y - 5.0]), hair, 1.8)
		7:  # Soul patch.
			_shape(_p([at.x - 1.8, at.y + 7.0, at.x + 1.8, at.y + 7.0, at.x, at.y + 10.5]), hair)


# --- Hair, glasses and hats ----------------------------------------------------

func _draw_back_hair(hair: Color) -> void:
	var h := _head
	match _part("hair"):
		5:  # Long.
			_shape(_p([h.x - 18.0, h.y - 8.0, h.x + 18.0, h.y - 8.0, h.x + 20.0, _shoulder_y + 12.0, h.x + 10.0, _shoulder_y + 16.0, h.x, _shoulder_y + 12.0, h.x - 10.0, _shoulder_y + 16.0, h.x - 20.0, _shoulder_y + 12.0]), hair)
		6:  # Bob.
			_shape(_p([h.x - 18.5, h.y - 8.0, h.x + 18.5, h.y - 8.0, h.x + 19.5, h.y + 17.0, h.x + 12.0, h.y + 20.0, h.x - 12.0, h.y + 20.0, h.x - 19.5, h.y + 17.0]), hair)
		7:  # Ponytail.
			_shape(_p([h.x + 12.0, h.y - 8.0, h.x + 21.0, h.y - 2.0, h.x + 24.0, h.y + 18.0, h.x + 20.0, h.y + 30.0, h.x + 16.0, h.y + 18.0, h.x + 14.0, h.y]), hair)
			_ellipse(h + Vector2(16.5, 1.0), Vector2(3.0, 3.0), Color("#c8343a"))
		8:  # Curly.
			for spot: Vector2 in [Vector2(-16.0, -6.0), Vector2(16.0, -6.0), Vector2(-18.0, 6.0), Vector2(18.0, 6.0), Vector2(-14.0, 16.0), Vector2(14.0, 16.0)]:
				_ellipse(h + spot, Vector2(7.5, 7.5), hair)
		9:  # Braids.
			for side: float in [-1.0, 1.0]:
				var top := h + Vector2(side * 15.0, 6.0)
				var end := Vector2(h.x + side * 17.0, _shoulder_y + 14.0)
				_capsule(top, end, 3.2, hair)
				for k in range(1, 5):
					var at := top.lerp(end, k / 5.0)
					_line(_p([at.x - 2.5, at.y - 1.0 * side, at.x + 2.5, at.y + 1.0 * side]), hair.darkened(0.3), 0.9)
				_ellipse(end + Vector2(0.0, 1.0), Vector2(2.2, 2.2), Color("#c8343a"), true)
		11:  # Bun.
			_ellipse(h + Vector2(0.0, -HEAD_RADII.y - 4.0), Vector2(8.5, 7.5), hair)
		12:  # Afro.
			_ellipse(h + Vector2(0.0, -3.0), HEAD_RADII + Vector2(9.0, 8.0), hair)


func _draw_front_hair(hair: Color) -> void:
	var h := _head
	var cap := _ellipse_points(h + Vector2(0, -1.0), HEAD_RADII + Vector2(1.3, 1.3), PI * 1.02, TAU * 0.99, 18)
	var brow_y := h.y - 9.0
	var style := _part("hair")
	if _part("headwear") != 0 and style in [4, 10]:
		style = 2  # A quiff or a mohawk is flattened under a hat.
	match style:
		0:  # Bald: a shine.
			_dot(h + Vector2(-5.0, -13.0), 2.2, Color(1, 1, 1, 0.35))
		1:  # Buzz cut.
			var buzz := _ellipse_points(h, HEAD_RADII + Vector2(0.3, 0.3), PI * 1.08, TAU * 0.96, 16)
			buzz.append(h + Vector2(0.0, brow_y - h.y - 2.0))
			_fill(buzz, Color(hair, 0.65))
		2:  # Short: a neat cap with a soft fringe.
			cap.append_array(_p([h.x + 16.0, brow_y + 3.0, h.x + 10.0, brow_y - 0.5, h.x + 3.0, brow_y - 2.0, h.x - 4.0, brow_y - 2.0, h.x - 11.0, brow_y - 0.5, h.x - 16.0, brow_y + 3.0]))
			_shape(cap, hair)
		3:  # Side part.
			cap.append_array(_p([h.x + 16.0, brow_y + 2.0, h.x + 6.0, brow_y - 4.0, h.x - 8.0, brow_y - 1.0, h.x - 15.0, brow_y + 6.0]))
			_shape(cap, hair)
			_line(_p([h.x - 9.0, brow_y - 10.0, h.x - 7.0, brow_y - 3.0]), hair.darkened(0.35), 1.0)
		4:  # Quiff: a big sweep up and back over the forehead, on the cap.
			cap.append_array(_p([h.x + 17.0, brow_y + 2.0, h.x, brow_y - 2.0, h.x - 17.0, brow_y + 2.0]))
			_shape(cap, hair)
			_shape(_p([h.x + 17.0, brow_y + 2.0, h.x + 15.0, brow_y - 8.0, h.x + 9.0, brow_y - 17.0, h.x - 2.0, brow_y - 20.0, h.x - 12.0, brow_y - 15.0, h.x - 16.5, brow_y - 5.0, h.x - 17.0, brow_y + 2.0, h.x - 8.0, brow_y - 1.0, h.x + 4.0, brow_y - 1.0]), hair)
			_line(_p([h.x + 8.0, brow_y - 8.0, h.x + 2.0, brow_y - 12.0]), hair.darkened(0.3), 1.0)
		5, 6:  # Long, bob: a fringe swept to the sides.
			cap.append_array(_p([h.x + 17.5, brow_y + 10.0, h.x + 11.0, brow_y - 3.0, h.x, brow_y - 5.0, h.x - 11.0, brow_y - 3.0, h.x - 17.5, brow_y + 10.0]))
			_shape(cap, hair)
		7, 11:  # Ponytail, bun: pulled back.
			cap.append_array(_p([h.x + 11.0, brow_y - 5.0, h.x, brow_y - 7.0, h.x - 11.0, brow_y - 5.0]))
			_shape(cap, hair)
		8:  # Curly.
			for x in range(-14, 15, 6):
				_ellipse(h + Vector2(x, brow_y - h.y - 5.0 + absf(x) * 0.2), Vector2(6.0, 6.0), hair)
		9:  # Braids: a parted top.
			cap.append_array(_p([h.x + 14.0, brow_y - 2.0, h.x, brow_y - 6.0, h.x - 14.0, brow_y - 2.0]))
			_shape(cap, hair)
			_line(_p([h.x, brow_y - 6.0, h.x, h.y - HEAD_RADII.y - 1.0]), hair.darkened(0.35), 1.0)
		10:  # Mohawk.
			_shape(_p([h.x - 4.5, brow_y - 1.0, h.x - 4.5, brow_y - 14.0, h.x - 2.5, brow_y - 24.0, h.x, brow_y - 30.0, h.x + 2.5, brow_y - 24.0, h.x + 4.5, brow_y - 14.0, h.x + 4.5, brow_y - 1.0]), hair)
		12:  # Afro: the front of the big round.
			cap.append_array(_p([h.x + 17.0, brow_y + 4.0, h.x + 8.0, brow_y - 1.0, h.x, brow_y - 3.0, h.x - 8.0, brow_y - 1.0, h.x - 17.0, brow_y + 4.0]))
			_shape(cap, hair)


func _draw_eyewear() -> void:
	var left := _eye(-1.0)
	var right := _eye(1.0)
	var frame := Color("#262626")
	match _part("eyewear"):
		1:  # Round.
			for at in [left, right]:
				_line(_ellipse_points(at, Vector2(5.6, 5.6)), frame, 1.3)
			_line(_p([left.x + 5.6, left.y, right.x - 5.6, right.y]), frame, 1.3)
		2:  # Square.
			for at: Vector2 in [left, right]:
				_line(_p([at.x - 6.0, at.y - 5.0, at.x + 6.0, at.y - 5.0, at.x + 6.0, at.y + 4.5, at.x - 6.0, at.y + 4.5, at.x - 6.0, at.y - 5.0]), frame, 1.5)
			_line(_p([left.x + 6.0, left.y - 1.0, right.x - 6.0, right.y - 1.0]), frame, 1.3)
		3:  # Sunglasses.
			for at: Vector2 in [left, right]:
				_shape(_p([at.x - 6.5, at.y - 4.5, at.x + 6.5, at.y - 4.5, at.x + 5.5, at.y + 4.0, at.x - 5.5, at.y + 4.0]), Color("#151515"))
				_line(_p([at.x - 4.0, at.y - 2.5, at.x - 1.0, at.y - 2.5]), Color(1, 1, 1, 0.35), 1.2)
			_line(_p([left.x + 6.5, left.y - 3.0, right.x - 6.5, right.y - 3.0]), frame, 1.5)
		4:  # Aviators.
			for at: Vector2 in [left, right]:
				var lens := _ellipse_points(at + Vector2(0, 0.8), Vector2(6.0, 5.2), 0.0, TAU, 20)
				_fill(lens, Color(0.35, 0.25, 0.1, 0.7))
				_line(lens, Color("#c8a040"), 1.2)
			_line(_p([left.x + 5.0, left.y - 3.5, right.x - 5.0, right.y - 3.5]), Color("#c8a040"), 1.2)
		5:  # Monocle.
			_line(_ellipse_points(right, Vector2(5.8, 5.8)), Color("#c8a040"), 1.4)
			_line(_p([right.x + 3.5, right.y + 5.0, right.x + 7.0, right.y + 16.0, right.x + 4.0, right.y + 27.0]), Color("#c8a040"), 0.8)
		6:  # Half-rims.
			for at: Vector2 in [left, right]:
				_line(_p([at.x - 6.0, at.y - 3.0, at.x + 6.0, at.y - 3.0]), frame, 2.4)
				_line(_ellipse_points(at + Vector2(0, -3.0), Vector2(6.0, 6.0), 0.0, PI, 10), Color(frame, 0.35), 0.8)
			_line(_p([left.x + 6.0, left.y - 3.0, right.x - 6.0, right.y - 3.0]), frame, 1.3)
		7:  # Cat-eye.
			for side: float in [-1.0, 1.0]:
				var at := left if side < 0.0 else right
				var outer := at.x + side * 6.8
				_line(_p([at.x - side * 5.5, at.y - 3.0, outer, at.y - 5.5, at.x + side * 5.0, at.y + 3.8, at.x - side * 5.0, at.y + 3.8, at.x - side * 5.5, at.y - 3.0]), Color("#c42f42"), 1.7)
			_line(_p([left.x + 5.5, left.y - 2.5, right.x - 5.5, right.y - 2.5]), Color("#c42f42"), 1.3)
		8:  # Goggles.
			_line(_p([_head.x - 19.0, left.y, _head.x + 19.0, right.y]), Color("#3a3a3a"), 3.4)
			for at: Vector2 in [left, right]:
				_ellipse(at, Vector2(6.5, 5.8), Color(0.55, 0.8, 0.95, 0.75))
				_line(_ellipse_points(at, Vector2(6.5, 5.8)), Color("#3a3a3a"), 1.8)
		9:  # Eye patch.
			_line(_p([_head.x - 18.0, _head.y - 9.0, _head.x + 18.0, _head.y + 6.0]), Color("#111111"), 1.3)
			_ellipse(left + Vector2(0, 0.5), Vector2(6.0, 5.5), Color("#111111"))


func _draw_headwear(hair: Color) -> void:
	var h := _head
	var top := h.y - HEAD_RADII.y  # The top of the head.
	var brim_y := h.y - 10.0  # Where a hat's brim sits (the top of the brow).
	var half := HEAD_RADII.x + 2.0
	match _part("headwear"):
		1:  # Captain's cap: a white crown, a black band and visor, a gold badge.
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 1.0), Vector2(half + 1.0, 13.0), PI, TAU, 16), WHITE)
			_shape(_p([h.x - half, brim_y - 1.0, h.x + half, brim_y - 1.0, h.x + half, brim_y + 5.0, h.x - half, brim_y + 5.0]), Color("#1a1a1a"))
			_shape(_p([h.x - half + 1.0, brim_y + 5.0, h.x + half - 1.0, brim_y + 5.0, h.x + 12.0, brim_y + 10.0, h.x - 12.0, brim_y + 10.0]), Color("#151515"))
			_ellipse(h + Vector2(0, brim_y - h.y - 5.0), Vector2(4.5, 3.5), GOLD)
			_line(_p([h.x - 8.0, brim_y + 2.0, h.x + 8.0, brim_y + 2.0]), GOLD, 1.2)
		2:  # Sailor cap: the white dixie cup.
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 2.0), Vector2(half - 2.0, 11.0), PI, TAU, 14), WHITE)
			_shape(_p([h.x - half, brim_y - 2.0, h.x + half, brim_y - 2.0, h.x + half - 2.0, brim_y + 6.0, h.x - half + 2.0, brim_y + 6.0]), Color("#ececec"))
		3:  # Sou'wester: a yellow dome with a wide brim, longer at the back.
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 2.0), Vector2(half, 15.0), PI, TAU, 16), Color("#f2c230"))
			_shape(_p([h.x - half - 7.0, brim_y + 2.0, h.x + half + 7.0, brim_y + 2.0, h.x + half + 9.0, brim_y + 7.0, h.x + 8.0, brim_y + 8.0, h.x - 8.0, brim_y + 8.0, h.x - half - 9.0, brim_y + 7.0]), Color("#e0b020"))
			_shape(_p([h.x + half - 0.5, brim_y + 4.0, h.x + half + 8.0, brim_y + 2.0, h.x + half + 9.0, h.y + 14.0, h.x + half + 0.5, h.y + 12.0]), Color("#e0b020"))
			_line(_p([h.x - half + 2.0, brim_y - 2.0, h.x + half - 2.0, brim_y - 2.0]), Color("#d0a018"), 1.4)
		4:  # Tricorne: a black three-cornered hat with gold trim.
			var crown := _ellipse_points(h + Vector2(0, brim_y - h.y + 2.0), Vector2(half - 3.0, 12.0), PI, TAU, 14)
			_shape(crown, Color("#1e1a1a"))
			_shape(_p([h.x - half - 9.0, brim_y - 9.0, h.x - half - 2.0, brim_y + 1.0, h.x - 6.0, brim_y + 4.0, h.x + 6.0, brim_y + 4.0, h.x + half + 2.0, brim_y + 1.0, h.x + half + 9.0, brim_y - 9.0, h.x + half + 2.0, brim_y - 2.0, h.x, brim_y - 4.0, h.x - half - 2.0, brim_y - 2.0]), Color("#242020"))
			_line(_p([h.x - half - 9.0, brim_y - 9.0, h.x - half - 2.0, brim_y + 1.0, h.x - 6.0, brim_y + 4.0, h.x + 6.0, brim_y + 4.0, h.x + half + 2.0, brim_y + 1.0, h.x + half + 9.0, brim_y - 9.0]), GOLD, 1.3)
		5:  # Bandana: red, knotted at the side.
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 3.0), Vector2(half, 14.0), PI, TAU, 16), Color("#c8343a"))
			_shape(_p([h.x + half - 3.0, brim_y, h.x + half + 7.0, brim_y - 5.0, h.x + half + 9.0, brim_y + 4.0, h.x + half + 2.0, brim_y + 5.0]), Color("#a82a30"))
			_line(_p([h.x - half + 2.0, brim_y + 3.0, h.x + half - 2.0, brim_y + 3.0]), Color("#a82a30"), 1.6)
			for spot: Vector2 in [Vector2(-9.0, -7.0), Vector2(0.0, -10.0), Vector2(9.0, -7.0), Vector2(-4.0, -2.0), Vector2(5.0, -2.0)]:
				_dot(h + Vector2(0, brim_y - h.y) + spot, 1.2, Color("#f4f4f4"))
		6:  # Watch cap: a navy knitted beanie.
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 4.0), Vector2(half, 16.0), PI, TAU, 16), NAVY)
			_shape(_p([h.x - half, brim_y - 1.0, h.x + half, brim_y - 1.0, h.x + half, brim_y + 6.0, h.x - half, brim_y + 6.0]), NAVY.darkened(0.2))
			for x in range(-14, 15, 4):
				_line(_p([h.x + x, brim_y, h.x + x, brim_y + 5.0]), NAVY.lightened(0.15), 0.8)
		7:  # Straw hat: a wide tan brim and a band.
			_shape(_p([h.x - half + 2.0, brim_y + 1.0, h.x - half + 4.0, top - 6.0, h.x + half - 4.0, top - 6.0, h.x + half - 2.0, brim_y + 1.0]), Color("#e3c78a"))
			_shape(_p([h.x - half - 12.0, brim_y - 1.0, h.x + half + 12.0, brim_y - 1.0, h.x + half + 10.0, brim_y + 5.0, h.x - half - 10.0, brim_y + 5.0]), Color("#d6b876"))
			_line(_p([h.x - half + 3.0, brim_y - 4.0, h.x + half - 3.0, brim_y - 4.0]), Color("#3a5a9a"), 2.6)
		8:  # Bucket hat.
			_shape(_p([h.x - half + 4.0, brim_y + 2.0, h.x - half + 6.0, top - 2.0, h.x, top - 5.0, h.x + half - 6.0, top - 2.0, h.x + half - 4.0, brim_y + 2.0]), Color("#b9a274"))
			_shape(_p([h.x - half - 2.0, brim_y, h.x + half + 2.0, brim_y, h.x + half + 7.0, brim_y + 7.0, h.x - half - 7.0, brim_y + 7.0]), Color("#a68f62"))
		9:  # Baseball cap.
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 3.0), Vector2(half - 1.0, 15.0), PI, TAU, 16), Color("#2f5fb0"))
			_shape(_p([h.x - half + 2.0, brim_y + 1.0, h.x + half - 1.0, brim_y + 1.0, h.x + half + 11.0, brim_y + 5.0, h.x + half - 1.0, brim_y + 7.0, h.x - half + 2.0, brim_y + 5.0]), Color("#24498a"))
			_dot(h + Vector2(0, brim_y - h.y - 12.0), 1.6, Color("#24498a"))
		10:  # Top hat.
			_shape(_p([h.x - half + 4.0, brim_y + 2.0, h.x - half + 5.0, top - 26.0, h.x + half - 5.0, top - 26.0, h.x + half - 4.0, brim_y + 2.0]), Color("#1a1a1a"))
			_shape(_p([h.x - half + 5.0, brim_y - 6.0, h.x + half - 5.0, brim_y - 6.0, h.x + half - 5.0, brim_y - 1.0, h.x - half + 5.0, brim_y - 1.0]), Color("#7a1a28"), false)
			_shape(_p([h.x - half - 6.0, brim_y + 1.0, h.x + half + 6.0, brim_y + 1.0, h.x + half + 4.0, brim_y + 6.0, h.x - half - 4.0, brim_y + 6.0]), Color("#111111"))
		11:  # Hard hat.
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 3.0), Vector2(half, 17.0), PI, TAU, 16), Color("#f2c230"))
			_shape(_p([h.x - half - 3.0, brim_y + 1.0, h.x + half + 3.0, brim_y + 1.0, h.x + half + 5.0, brim_y + 6.0, h.x - half - 5.0, brim_y + 6.0]), Color("#e0b020"))
			_line(_p([h.x, top - 10.0, h.x, brim_y + 1.0]), Color("#d0a018"), 2.4)
		12:  # Cowboy hat.
			_shape(_p([h.x - half + 5.0, brim_y + 1.0, h.x - half + 6.0, top - 10.0, h.x - 5.0, top - 12.0, h.x, top - 9.0, h.x + 5.0, top - 12.0, h.x + half - 6.0, top - 10.0, h.x + half - 5.0, brim_y + 1.0]), Color("#8a5a30"))
			_shape(_p([h.x - half - 14.0, brim_y - 2.0, h.x - half - 2.0, brim_y + 2.0, h.x, brim_y + 3.0, h.x + half + 2.0, brim_y + 2.0, h.x + half + 14.0, brim_y - 2.0, h.x + half + 10.0, brim_y + 5.0, h.x + 10.0, brim_y + 8.0, h.x - 10.0, brim_y + 8.0, h.x - half - 10.0, brim_y + 5.0]), Color("#7a4e28"))
			_line(_p([h.x - half + 5.5, brim_y - 2.0, h.x + half - 5.5, brim_y - 2.0]), Color("#3a2414"), 2.4)
		13:  # Fisherman's cap: a navy Greek cap, a black visor and a braided cord.
			_shape(_p([h.x - half, brim_y + 2.0, h.x - half - 1.0, brim_y - 9.0, h.x - 6.0, top - 4.0, h.x + 8.0, top - 4.0, h.x + half + 2.0, brim_y - 9.0, h.x + half, brim_y + 2.0]), NAVY)
			_shape(_p([h.x - half + 1.0, brim_y + 1.0, h.x + half - 1.0, brim_y + 1.0, h.x + 12.0, brim_y + 7.0, h.x - 12.0, brim_y + 7.0]), Color("#151515"))
			_line(_p([h.x - half + 2.0, brim_y - 1.0, h.x + half - 2.0, brim_y - 1.0]), Color("#151515"), 2.2)
			_line(_p([h.x - half + 3.0, brim_y + 1.5, h.x + half - 3.0, brim_y + 1.5]), GOLD, 0.9)
		14:  # Flat cap: grey tweed, its peak snug over the brow.
			_shape(_p([h.x - half, brim_y + 2.0, h.x - half + 2.0, top - 1.0, h.x + 4.0, top - 3.0, h.x + half + 3.0, brim_y - 6.0, h.x + half + 1.0, brim_y + 2.0]), Color("#6f6a62"))
			_shape(_p([h.x - half + 2.0, brim_y + 1.0, h.x + half + 1.0, brim_y + 1.0, h.x + half + 3.0, brim_y + 5.0, h.x - half + 4.0, brim_y + 5.0]), Color("#5c574f"))
			for k in 4:
				_line(_p([h.x - 12.0 + k * 7.0, top + 2.0, h.x - 10.0 + k * 7.0, brim_y - 2.0]), Color("#857f75"), 0.8)
		15:  # Beret: navy, slouched to one side, a little stalk on top.
			_shape(_ellipse_points(h + Vector2(4.0, brim_y - h.y - 4.0), Vector2(half + 3.0, 9.0), 0.0, TAU, 20), Color("#24305a"))
			_shape(_p([h.x - half + 2.0, brim_y - 1.0, h.x + half - 2.0, brim_y - 1.0, h.x + half - 3.0, brim_y + 3.0, h.x - half + 3.0, brim_y + 3.0]), Color("#1a2448"))
			_line(_p([h.x + 4.0, brim_y - 13.0, h.x + 5.0, brim_y - 17.0]), Color("#1a2448"), 1.8)
		16:  # Bicorne: an admiral's black hat worn athwart, gold-edged, a cockade.
			_shape(_p([h.x - half - 12.0, brim_y + 1.0, h.x - 10.0, top - 14.0, h.x + 10.0, top - 14.0, h.x + half + 12.0, brim_y + 1.0, h.x, brim_y + 4.0]), Color("#1c1a1e"))
			_line(_p([h.x - half - 12.0, brim_y + 1.0, h.x - 10.0, top - 14.0, h.x + 10.0, top - 14.0, h.x + half + 12.0, brim_y + 1.0]), GOLD, 1.4)
			_ellipse(Vector2(h.x, top - 4.0), Vector2(4.0, 4.0), Color("#c8343a"))
			_dot(Vector2(h.x, top - 4.0), 1.6, WHITE)
		17:  # Pompom beanie: red knit, a white turn-up and a big white pompom.
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 4.0), Vector2(half, 16.0), PI, TAU, 16), Color("#c8343a"))
			_shape(_p([h.x - half, brim_y - 1.0, h.x + half, brim_y - 1.0, h.x + half, brim_y + 6.0, h.x - half, brim_y + 6.0]), Color("#f0ece4"))
			_ellipse(Vector2(h.x, top - 12.0), Vector2(6.0, 6.0), Color("#f4f2ee"))
			for x in range(-12, 13, 6):
				_line(_p([h.x + x, brim_y - 4.0, h.x + x * 0.6, top - 4.0]), Color("#a82a30"), 0.8)
		18:  # Fedora: brown felt, a pinched crown and a black band.
			_shape(_p([h.x - half + 5.0, brim_y + 1.0, h.x - half + 6.0, top - 8.0, h.x - 4.0, top - 12.0, h.x, top - 9.0, h.x + 4.0, top - 12.0, h.x + half - 6.0, top - 8.0, h.x + half - 5.0, brim_y + 1.0]), Color("#6a4e36"))
			_shape(_p([h.x - half - 8.0, brim_y + 1.0, h.x + half + 8.0, brim_y + 1.0, h.x + half + 6.0, brim_y + 5.0, h.x - half - 6.0, brim_y + 5.0]), Color("#5a4230"))
			_line(_p([h.x - half + 5.5, brim_y - 2.0, h.x + half - 5.5, brim_y - 2.0]), Color("#1a1412"), 2.6)
		19:  # Pith helmet: a white dome with a sloping brim and a band.
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 2.0), Vector2(half - 1.0, 19.0), PI, TAU, 18), Color("#efe9d8"))
			_shape(_p([h.x - half - 6.0, brim_y + 4.0, h.x + half + 6.0, brim_y + 4.0, h.x + half + 2.0, brim_y - 1.0, h.x - half - 2.0, brim_y - 1.0]), Color("#e2dcc8"))
			_line(_p([h.x - half + 1.0, brim_y - 3.0, h.x + half - 1.0, brim_y - 3.0]), Color("#b8a882"), 2.0)
			_dot(Vector2(h.x, top - 15.0), 1.8, Color("#c8b88a"))
		20:  # Conical hat: woven straw, a wide cone with a chin cord.
			_shape(_p([h.x - half - 16.0, brim_y + 3.0, h.x, top - 18.0, h.x + half + 16.0, brim_y + 3.0, h.x, brim_y + 6.0]), Color("#dcc387"))
			for k in range(1, 4):
				var f := k / 4.0
				_line(_p([lerpf(h.x, h.x - half - 16.0, f), lerpf(top - 18.0, brim_y + 3.0, f), lerpf(h.x, h.x + half + 16.0, f), lerpf(top - 18.0, brim_y + 3.0, f)]), Color("#b89c5e"), 0.8)
			_line(_p([h.x - half + 2.0, brim_y + 5.0, h.x - 6.0, h.y + 20.0, h.x + 6.0, h.y + 20.0, h.x + half - 2.0, brim_y + 5.0]), Color("#8a6a3a"), 0.7)
		21:  # capotain (a skin pack's: see Cosmetics).
			_shape(_p([h.x - half + 4.0, brim_y + 2.0, h.x - half + 7.0, top - 24.0, h.x + half - 7.0, top - 24.0, h.x + half - 4.0, brim_y + 2.0]), Color("#1c1a1c"))
			_shape(_p([h.x - half - 9.0, brim_y + 1.0, h.x + half + 9.0, brim_y + 1.0, h.x + half + 7.0, brim_y + 6.0, h.x - half - 7.0, brim_y + 6.0]), Color("#111111"))
			_line(_p([h.x - half + 4.5, brim_y - 3.0, h.x + half - 4.5, brim_y - 3.0]), Color("#6b5a2e"), 2.8)
			_shape(_p([h.x - 3.0, brim_y - 6.0, h.x + 3.0, brim_y - 6.0, h.x + 3.0, brim_y, h.x - 3.0, brim_y]), GOLD, true, 0.8)
		22:  # coif (a skin pack's: see Cosmetics).
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 4.0), Vector2(half + 1.0, 17.0), PI, TAU, 16), Color("#f8f6f0"))
			for side: float in [-1.0, 1.0]:
				_shape(_p([h.x + side * (half - 1.0), brim_y + 1.0, h.x + side * (half + 2.0), brim_y + 1.0, h.x + side * (half + 1.0), h.y + 13.0, h.x + side * (half - 3.0), h.y + 13.0]), Color("#f8f6f0"))
			_line(_p([h.x - half + 2.0, brim_y, h.x + half - 2.0, brim_y]), Color("#d8d2c4"), 1.2)
			_line(_p([h.x - half + 2.0, h.y + 13.0, h.x - 4.0, h.y + 22.0, h.x + 4.0, h.y + 22.0, h.x + half - 2.0, h.y + 13.0]), Color("#d8d2c4"), 0.9)
		23:  # monmouth (a skin pack's: see Cosmetics).
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 4.0), Vector2(half, 16.0), PI, TAU, 16), Color("#6b4a2e"))
			_shape(_p([h.x - half, brim_y - 1.0, h.x + half, brim_y - 1.0, h.x + half, brim_y + 5.0, h.x - half, brim_y + 5.0]), Color("#5a3c22"))
			for x in range(-14, 15, 4):
				_line(_p([h.x + x, brim_y - 1.0, h.x + x, brim_y + 4.0]), Color("#8a6240"), 0.8)
			_dot(Vector2(h.x, top - 11.0), 2.2, Color("#4a3018"))
		24:  # turkey (a skin pack's: see Cosmetics).
			var c := Vector2(h.x, top - 6.0)
			var feathers := [[-0.95, Color("#c47a2a")], [-0.5, Color("#e8a040")], [0.0, Color("#f2c233")], [0.5, Color("#e8a040")], [0.95, Color("#c47a2a")]]
			for feather: Array in feathers:
				var a: float = feather[0] - PI / 2.0
				var points := PackedVector2Array()
				for k in 16:
					var t := TAU * k / 16.0
					var local := Vector2(cos(t) * 4.5, sin(t) * 17.0 - 14.0)
					points.append(c + local.rotated(a + PI / 2.0))
				_shape(points, feather[1])
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 4.0), Vector2(half, 16.0), PI, TAU, 16), Color("#8a5a30"))
			_shape(_p([h.x - 5.0, brim_y - 1.0, h.x + 5.0, brim_y - 1.0, h.x, brim_y + 7.0]), Color("#f2c233"))
			_shape(_p([h.x - 1.0, brim_y + 3.0, h.x + 3.0, brim_y + 3.0, h.x + 4.0, brim_y + 12.0, h.x, brim_y + 12.0]), RED)
		25:  # cap_navy (a skin pack's: see Cosmetics).
			_cap(NAVY, RED)
		26:  # cap_red (a skin pack's: see Cosmetics).
			_cap(RED, WHITE)
		30:  # cap_black (a skin pack's: see Cosmetics).
			_cap(Color("#1c1c1e"), Color("#1c1c1e"))
		31:  # cap_1920 (a skin pack's: see Cosmetics).
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 3.0), Vector2(half, 14.0), PI, TAU, 16), Color("#efe6cc"))
			for x in range(-12, 13, 6):
				_line(_p([h.x + x, brim_y - 2.0, h.x + x * 0.4, top - 10.0]), NAVY, 0.7)
			_shape(_p([h.x - half + 3.0, brim_y + 1.0, h.x + half - 2.0, brim_y + 1.0, h.x + half + 6.0, brim_y + 4.0, h.x + half - 2.0, brim_y + 6.0, h.x - half + 3.0, brim_y + 5.0]), NAVY)
			_dot(h + Vector2(0, brim_y - h.y - 11.0), 1.6, NAVY)
		27:  # batting_helmet (a skin pack's: see Cosmetics).
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 3.0), Vector2(half + 1.5, 17.0), PI, TAU, 16), NAVY)
			_shape(_p([h.x - half + 1.0, brim_y + 1.0, h.x + half, brim_y + 1.0, h.x + half + 10.0, brim_y + 5.0, h.x + half, brim_y + 7.0, h.x - half + 1.0, brim_y + 5.0]), NAVY.darkened(0.2))
			_shape(_p([h.x - half - 1.0, brim_y + 1.0, h.x - half + 7.0, brim_y + 1.0, h.x - half + 7.0, h.y + 12.0, h.x - half + 1.0, h.y + 13.0, h.x - half - 1.0, h.y + 8.0]), NAVY)
			_line(_p([h.x - half + 2.0, brim_y - 4.0, h.x + half - 2.0, brim_y - 4.0]), WHITE, 1.4)
			_line(_p([h.x - 10.0, top - 9.0, h.x + 2.0, top - 12.0]), Color(1, 1, 1, 0.35), 1.6)
		28:  # catchers_mask (a skin pack's: see Cosmetics).
			_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 2.0), Vector2(half, 13.0), PI, TAU, 16), NAVY)
			var frame := _ellipse_points(h + Vector2(0, 1.0), Vector2(half + 1.0, 21.0), 0.0, TAU, 28)
			_line(frame, Color("#8a8f96"), 2.6)
			_line(frame, OUTLINE, 0.7)
			for y: float in [h.y - 8.0, h.y + 1.0, h.y + 10.0]:
				_line(_p([h.x - half, y, h.x + half, y]), Color("#8a8f96"), 1.4)
			_line(_p([h.x, h.y - 17.0, h.x, h.y + 19.0]), Color("#8a8f96"), 1.4)
			_line(_p([h.x - half - 1.0, h.y - 4.0, h.x - half - 6.0, h.y - 6.0]), Color("#2a2a2a"), 1.6)
			_line(_p([h.x + half + 1.0, h.y - 4.0, h.x + half + 6.0, h.y - 6.0]), Color("#2a2a2a"), 1.6)
		29:  # paper_hat (a skin pack's: see Cosmetics).
			_shape(_p([h.x - half + 1.0, brim_y + 1.0, h.x - half + 6.0, top - 7.0, h.x + half - 6.0, top - 7.0, h.x + half - 1.0, brim_y + 1.0]), Color("#f8f6f0"))
			_line(_p([h.x - half + 3.0, brim_y - 2.0, h.x + half - 3.0, brim_y - 2.0]), RED, 2.0)
			_line(_p([h.x - half + 5.0, top - 7.0, h.x + half - 5.0, top - 7.0]), Color("#d8d2c4"), 1.0)


# --- The skin packs' outfits' helpers (see Cosmetics) --------------------------

const GREY := Color("#a9adb3")
const RED := Color("#c8343a")
const LINEN := Color("#ece2c8")
const LEATHER := Color("#7a5230")
const BLACK := Color("#1f1d1f")

## The seat and two legs in a colour down to a hem (as Portrait's trousers).
func _legs(color: Color, hem: float, r: float, flat := true) -> void:
	var seat := _p([50.0 - _hip - 0.5, _hip_y - 5.0, 50.0 + _hip + 0.5, _hip_y - 5.0, 50.0 + _leg_x + r, _hip_y + 10.0, 50.0 - _leg_x - r, _hip_y + 10.0])
	_shape(seat, color)
	for side: float in [-1.0, 1.0]:
		var x := 50.0 + side * _leg_x
		_capsule(Vector2(x, _hip_y - 2.0), Vector2(x, hem), r, color, true, flat)
	_shape(seat, color, false)
	_line(_p([50.0, _hip_y + 10.0, 50.0, _hip_y + 18.0]), color.darkened(0.35), 1.0)


## White stockings on the lower legs (under breeches).
func _stockings(color := WHITE) -> void:
	for side: float in [-1.0, 1.0]:
		var x := 50.0 + side * _leg_x
		_capsule(Vector2(x, _hip_y + 24.0 * _hf), Vector2(x, _ankle_y - 1.5), _leg_r + 0.9, color)


## Vertical stripes following the torso's taper (jersey pinstripes, a vendor's shirt).
func _torso_stripes(color: Color, step: float, width: float) -> void:
	# Each stripe follows the torso's edge at every height (in at the waist,
	# out at the hips), so none crosses the air beside it.
	var x := 50.0 - _sh + 3.0
	while x < 50.0 + _sh - 2.0:
		var share := (x - 50.0) / _sh
		var points := PackedVector2Array()
		var y := _shoulder_y + 3.0
		while y < _hip_y - 1.0:
			points.append(Vector2(50.0 + share * (_torso_half(y) - 1.4), y))
			y += 3.0
		points.append(Vector2(50.0 + share * (_torso_half(_hip_y - 1.0) - 1.4), _hip_y - 1.0))
		_line(points, color, width)
		x += step


func _collar_falling(color := WHITE) -> void:
	_shape(_p([50.0 - _sh * 0.95, _shoulder_y + 1.0, 50.0 + _sh * 0.95, _shoulder_y + 1.0, 50.0 + 9.0, _shoulder_y + 15.0, 50.0 - 9.0, _shoulder_y + 15.0]), color)
	_line(_p([50.0, _shoulder_y + 2.0, 50.0, _shoulder_y + 14.0]), color.darkened(0.2), 0.9)


func _rope_belt() -> void:
	var y := _waist_y + 2.0
	_line(_p([50.0 - _torso_half(y) + 0.5, y, 50.0 + _torso_half(y) - 0.5, y]), Color("#c9ad7a"), 2.6)
	var x := 50.0 - _torso_half(y) + 2.0
	while x < 50.0 + _torso_half(y) - 2.0:
		_line(_p([x, y - 1.2, x + 2.0, y + 1.2]), Color("#9a7e4c"), 0.8)
		x += 3.5
	_dot(Vector2(50.0 + 3.0, y), 2.0, Color("#c9ad7a"))
	_line(_p([51.0, y + 1.0, 53.0, y + 9.0]), Color("#c9ad7a"), 1.8)
	_line(_p([54.0, y + 1.0, 57.0, y + 7.0]), Color("#c9ad7a"), 1.8)


func _sleeve_trim(color: Color, reach: float, width := 1.6) -> void:
	for side: float in [-1.0, 1.0]:
		var at := _arm_top(side).lerp(_hand(side), reach)
		_line(_p([at.x - _arm_r - 1.4, at.y, at.x + _arm_r + 1.4, at.y]), color, width)



func _cap(color: Color, button: Color) -> void:
	var h := _head
	var brim_y := h.y - 10.0
	var half := HEAD_RADII.x + 2.0
	_shape(_ellipse_points(h + Vector2(0, brim_y - h.y + 3.0), Vector2(half - 1.0, 15.0), PI, TAU, 16), color)
	_shape(_p([h.x - half + 2.0, brim_y + 1.0, h.x + half - 1.0, brim_y + 1.0, h.x + half + 11.0, brim_y + 5.0, h.x + half - 1.0, brim_y + 7.0, h.x - half + 2.0, brim_y + 5.0]), color.darkened(0.2))
	_line(_p([h.x, brim_y - 12.0, h.x, brim_y + 1.0]), color.darkened(0.25), 0.8)
	_dot(h + Vector2(0, brim_y - h.y - 12.0), 1.6, button)
