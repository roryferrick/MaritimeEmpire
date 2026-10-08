# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Portrait
extends Control
## A character (Characters: the CEO, a ship's captain or mates) drawn from
## their look: standing, head to shoes, or (bust) just head and shoulders on a
## round backdrop, for small pictures. Drawn in a design space DESIGN wide and
## tall, scaled to fit.

const DESIGN := Vector2(100, 200)
## The part of the design a bust shows.
const BUST_VIEW := Rect2(22, 6, 56, 62)
const OUTLINE := Color(0, 0, 0, 0.4)
const OUTLINE_WIDTH := 1.1
const BUST_BACKDROP := Color(0.55, 0.68, 0.8)

const SKINS: Array[Color] = [Color("#ffe3d3"), Color("#f8d2b6"), Color("#eec19b"), Color("#dcaa7c"), Color("#c99364"),
	Color("#b98053"), Color("#a06a43"), Color("#835430"), Color("#65401f"), Color("#4a2d15")]
const HAIR_COLORS: Array[Color] = [Color("#1c1a19"), Color("#3b2618"), Color("#5a3a22"), Color("#8a6240"), Color("#8e3b1e"),
	Color("#c4612a"), Color("#d99a6c"), Color("#e3c46e"), Color("#f0e6c8"), Color("#9a9a9a"), Color("#ececec"),
	Color("#3c6fd8"), Color("#e46fb0"), Color("#3fa65a")]
## Eyes: [style, iris color]; styles round, narrow, wide, sleepy, lashes, smiling.
const EYES := [["round", Color("#6b4423")], ["round", Color("#3d7cc9")], ["round", Color("#3f8f4f")],
	["narrow", Color("#5a3a20")], ["narrow", Color("#8a7038")], ["wide", Color("#3d7cc9")], ["sleepy", Color("#7d8790")],
	["lashes", Color("#6b4423")], ["lashes", Color("#3f8f4f")], ["smiling", Color.BLACK]]
## Tops: [style, color]; long sleeves unless short.
const TOPS := [["tee", Color("#f2f2f2")], ["tee", Color("#c8343a")], ["captain", Color("#1f2b4d")], ["hoodie", Color("#8a8f96")],
	["stripes", Color("#f4f4f4")], ["jumper", Color("#3f7a4a")], ["polo", Color("#e8c540")], ["suit", Color("#23252b")],
	["flannel", Color("#a8322e")], ["hivis", Color("#7b8088")]]
## Bottoms: [style, color]; trousers, shorts or skirt.
const BOTTOMS := [["trousers", Color("#3f5f8f")], ["trousers", Color("#c2a878")], ["trousers", Color("#262626")],
	["shorts", Color("#2c3a5c")], ["cargo", Color("#6b6f4a")], ["trousers", Color("#ececec")], ["cords", Color("#7a5536")],
	["skirt", Color("#b8323a")], ["skirt", Color("#2c3a5c")], ["shorts", Color("#5577a8")]]
## Shoes: [style, color]; trainers, boots, dress, sandals or wellies.
const SHOES := [["trainers", Color("#f2f2f2")], ["boots", Color("#222222")], ["boots", Color("#6e4526")], ["dress", Color("#151515")],
	["trainers", Color("#c8343a")], ["sandals", Color("#7a4e2a")], ["wellies", Color("#f2c230")], ["trainers", Color("#3a6fc4")],
	["dress", Color("#7a4a25")], ["wellies", Color("#3c7a44")]]

const HEAD := Vector2(50, 38)
const HEAD_RADII := Vector2(16, 19)
const EYE_Y := 37.0
const EYE_X := 7.0

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


func _init(for_character := {}, as_bust := false) -> void:
	character = for_character
	bust = as_bust
	mouse_filter = MOUSE_FILTER_PASS


func _part(key: String) -> int:
	return clampi(int(_look.get(key, 0)), 0, Characters.option_count(key) - 1)


func _draw() -> void:
	_look = character.get("look", {})
	var view := BUST_VIEW if bust else Rect2(Vector2.ZERO, DESIGN)
	var scale := minf(size.x / view.size.x, size.y / view.size.y)
	var offset := (size - view.size * scale) / 2.0 - view.position * scale
	if bust:
		draw_circle(size / 2.0, minf(size.x, size.y) / 2.0, BUST_BACKDROP, true, -1.0, true)
	draw_set_transform(offset, 0.0, Vector2.ONE * scale)
	var skin := SKINS[_part("skin")]
	var hair := HAIR_COLORS[_part("hair_color")]
	_draw_back_hair(hair)
	_draw_legs(skin)
	_draw_shoes(skin)
	_draw_top(skin)
	_draw_neck_and_head(skin)
	_draw_eyes(hair)
	_draw_nose(skin)
	_draw_beard(hair)
	_draw_mouth(skin)
	_draw_moustache(hair)
	_draw_front_hair(hair)
	_draw_eyewear()
	_draw_headwear()
	draw_set_transform_matrix(Transform2D.IDENTITY)


# --- Shapes --------------------------------------------------------------------

static func _ellipse_points(center: Vector2, radii: Vector2, from := 0.0, to := TAU, steps := 28) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps + 1:
		var angle := lerpf(from, to, float(i) / steps)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


func _shape(points: PackedVector2Array, color: Color, outline := true) -> void:
	draw_colored_polygon(points, color)
	if outline:
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, OUTLINE, OUTLINE_WIDTH, true)


func _ellipse(center: Vector2, radii: Vector2, color: Color, outline := true) -> void:
	var points := _ellipse_points(center, radii)
	points.resize(points.size() - 1)
	_shape(points, color, outline)


func _line(points: PackedVector2Array, color: Color, width := 1.2) -> void:
	draw_polyline(points, color, width, true)


static func _p(values: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, values.size(), 2):
		points.append(Vector2(values[i], values[i + 1]))
	return points


# --- Body ----------------------------------------------------------------------

func _draw_legs(skin: Color) -> void:
	var bottoms: Array = BOTTOMS[_part("bottoms")]
	var style: String = bottoms[0]
	var color: Color = bottoms[1]
	var bare_from := 176.0
	if style == "shorts":
		bare_from = 142.0
	elif style == "skirt":
		bare_from = 150.0
	if bare_from < 176.0:
		for x: float in [35.0, 51.0]:
			_shape(_p([x, bare_from - 4, x + 14, bare_from - 4, x + 13, 178, x + 1, 178]), skin)
	if style == "skirt":
		_shape(_p([33, 114, 67, 114, 72, 152, 28, 152]), color)
		_line(_p([31, 133, 69, 133]), color.darkened(0.25), 0.8)
		return
	var bottom := bare_from
	for x: float in [34.0, 50.5]:
		_shape(_p([x, 114, x + 15.5, 114, x + 15, bottom, x + 0.5, bottom]), color)
	_shape(_p([33, 113, 67, 113, 67, 124, 33, 124]), color)
	_line(_p([50, 124, 50, 132]), color.darkened(0.35), 0.8)
	match style:
		"cargo":
			for x: float in [35.0, 56.0]:
				_shape(_p([x, 140, x + 9, 140, x + 9, 152, x, 152]), color.darkened(0.12))
		"cords":
			for x in range(37, 64, 4):
				if absf(x - 50.0) > 1.5:
					_line(_p([x, 126, x, bottom - 2]), color.darkened(0.2), 0.6)
		"trousers":
			if color.get_luminance() < 0.5 and color.b > color.r:  # Jeans: stitched seams.
				for x: float in [41.5, 58.5]:
					_line(_p([x, 126, x, bottom - 2]), color.lightened(0.25), 0.5)
	_line(_p([33, 116, 67, 116]), color.darkened(0.3), 1.0)  # The belt line.


func _draw_shoes(skin: Color) -> void:
	var shoes: Array = SHOES[_part("shoes")]
	var style: String = shoes[0]
	var color: Color = shoes[1]
	for side: float in [-1.0, 1.0]:
		var middle := 50.0 + side * 8.0
		var toe := middle + side * 4.0
		var top := 174.0
		if style == "boots":
			top = 164.0
		elif style == "wellies":
			top = 156.0
		if style == "sandals":
			_shape(_p([middle - side * 7, 176, middle + side * 7, 176, toe + side * 5, 186, toe - side * 12, 186]), skin)
			_line(_p([middle - 7, 180, middle + 7, 180]), color, 2.0)
			_line(_p([toe - side * 10, 184, toe + side * 4, 184]), color, 1.6)
			_shape(_p([toe - side * 13, 186, toe + side * 6, 186, toe + side * 6, 188, toe - side * 13, 188]), color.darkened(0.2))
			continue
		_shape(_p([middle - side * 7.5, top, middle + side * 7.5, top, middle + side * 7.5, 180, toe + side * 6, 181, toe + side * 6, 187, middle - side * 8, 187]), color)
		if style == "trainers":
			_shape(_p([middle - side * 8, 184, toe + side * 6, 184, toe + side * 6, 188, middle - side * 8, 188]), Color("#f8f8f8"))
			_line(_p([middle - 3, 178, middle + 3, 177]), color.darkened(0.3), 0.8)
		elif style == "dress":
			_line(_p([middle - side * 7, 186, toe + side * 5, 186]), color.lightened(0.3), 0.6)


func _draw_top(skin: Color) -> void:
	var top: Array = TOPS[_part("top")]
	var style: String = top[0]
	var color: Color = top[1]
	var short := style in ["tee", "polo"]
	if style == "hoodie":
		_ellipse(Vector2(50, 60), Vector2(17, 9), color.darkened(0.15))  # The hood, behind the neck.
	var body := _p([30, 68, 42, 63, 58, 63, 70, 68, 75, 78, 71, 120, 29, 120, 25, 78])
	var reach := 0.33 if short else 0.95  # How far down the arm the sleeve goes.
	for side: float in [-1.0, 1.0]:
		var outer := 50.0 + side * 25.0
		var top_out := Vector2(outer, 76)
		var top_in := Vector2(outer - side * 7, 82)
		var bottom_out := Vector2(outer + side * 5, 118)
		var bottom_in := Vector2(outer - side * 3, 120)
		_shape(PackedVector2Array([top_out, bottom_out, bottom_in, top_in]), skin)
		_shape(PackedVector2Array([top_out, top_out.lerp(bottom_out, reach), top_in.lerp(bottom_in, reach), top_in]), color)
		_ellipse(Vector2(outer + side * 1.5, 123), Vector2(4.5, 5), skin)  # The hand.
	_shape(body, color)
	match style:
		"captain":
			_shape(_p([44, 63, 56, 63, 50, 76]), Color("#f4f4f4"))
			for y: float in [82.0, 94.0, 106.0]:
				for x: float in [44.0, 56.0]:
					draw_circle(Vector2(x, y), 1.6, Color("#e2b43c"), true, -1.0, true)
			for side: float in [-1.0, 1.0]:
				_line(_p([50.0 + side * 22.5, 113, 50.0 + side * 27.5, 113]), Color("#e2b43c"), 2.0)
			_line(_p([50, 76, 50, 120]), color.darkened(0.4), 0.8)
		"hoodie":
			_shape(_p([38, 98, 62, 98, 64, 114, 36, 114]), color.darkened(0.08))
			_line(_p([47, 66, 46, 82]), Color("#f0f0f0"), 0.8)
			_line(_p([53, 66, 54, 82]), Color("#f0f0f0"), 0.8)
		"stripes":
			for y in range(70, 120, 6):
				_line(_p([27 if y < 80 else 29, y, 73 if y < 80 else 71, y]), Color("#22325c"), 2.2)
			for side: float in [-1.0, 1.0]:
				for y in range(84, 118, 6):
					var outer := 50.0 + side * 25.0
					_line(_p([outer - side * 6, y, outer + side * 3, y]), Color("#22325c"), 2.0)
		"jumper":
			for x in range(32, 70, 3):
				_line(_p([x, 114, x, 120]), color.darkened(0.25), 0.6)
		"polo":
			_shape(_p([42, 63, 50, 70, 48, 72, 40, 66]), color.lightened(0.2))
			_shape(_p([58, 63, 50, 70, 52, 72, 60, 66]), color.lightened(0.2))
			draw_circle(Vector2(50, 74), 0.9, color.darkened(0.4), true, -1.0, true)
		"suit":
			_shape(_p([43, 63, 57, 63, 50, 84]), Color("#f4f4f4"))
			_shape(_p([49, 66, 51, 66, 52.5, 82, 50, 86, 47.5, 82]), Color("#b8323a"))
			_line(_p([43, 63, 50, 92, 57, 63]), color.lightened(0.25), 0.8)
		"flannel":
			for y in range(70, 120, 7):
				_line(_p([28, y, 72, y]), color.darkened(0.35), 1.2)
			for x in range(32, 70, 7):
				_line(_p([x, 66, x, 120]), color.darkened(0.35), 1.2)
			_line(_p([50, 64, 50, 120]), Color(0, 0, 0, 0.3), 0.6)
		"hivis":
			var vest := Color("#ff8a1f")
			_shape(_p([31, 68, 42, 64, 46, 90, 54, 90, 58, 64, 69, 68, 70, 118, 30, 118]), vest)
			for y: float in [100.0, 110.0]:
				_line(_p([31, y, 69, y]), Color("#d8dde2"), 2.6)
		"tee":
			_line(_p([43, 64, 50, 68, 57, 64]), color.darkened(0.25), 1.0)


func _draw_neck_and_head(skin: Color) -> void:
	_shape(_p([44, 52, 56, 52, 56, 66, 44, 66]), skin.darkened(0.08))
	for side: float in [-1.0, 1.0]:
		_ellipse(Vector2(50.0 + side * 16.0, 40), Vector2(3.5, 4.5), skin)
	_ellipse(HEAD, HEAD_RADII, skin)


# --- Face ----------------------------------------------------------------------

func _draw_eyes(hair: Color) -> void:
	var eyes: Array = EYES[_part("eyes")]
	var style: String = eyes[0]
	var iris: Color = eyes[1]
	for side: float in [-1.0, 1.0]:
		var at := Vector2(50.0 + side * EYE_X, EYE_Y)
		_line(_p([at.x - 3.5, at.y - 6.0 - (0.6 if style == "wide" else 0.0), at.x + 3.5, at.y - 6.0]), hair.darkened(0.15), 1.4)  # Eyebrow.
		if style == "smiling":
			_line(_ellipse_points(at + Vector2(0, 1), Vector2(3, 2.2), PI, TAU, 10), Color("#2a1d16"), 1.2)
			continue
		var radii := Vector2(3.6, 3.0)
		var iris_r := 2.0
		match style:
			"narrow":
				radii = Vector2(3.6, 1.7)
				iris_r = 1.5
			"wide":
				radii = Vector2(4.2, 3.8)
				iris_r = 2.4
		_ellipse(at, radii, Color("#fbfbfb"), false)
		draw_circle(at, iris_r, iris, true, -1.0, true)
		draw_circle(at, iris_r * 0.45, Color("#111111"), true, -1.0, true)
		draw_circle(at + Vector2(-0.6, -0.7), 0.5, Color.WHITE, true, -1.0, true)
		_line(_ellipse_points(at, radii, PI, TAU, 10), Color("#2a1d16"), 0.8)
		if style == "sleepy":
			_shape(_ellipse_points(at, radii + Vector2(0.3, 0.3), PI, TAU, 10), SKINS[_part("skin")].darkened(0.12), false)
			_line(_p([at.x - 3.8, at.y, at.x + 3.8, at.y]), Color("#2a1d16"), 0.8)
		elif style == "lashes":
			for k in 3:
				var root := at + Vector2(side * (1.2 + k * 1.2), -radii.y + 0.4)
				_line(_p([root.x, root.y, root.x + side * 1.6, root.y - 1.4]), Color("#1a1a1a"), 0.7)


func _draw_nose(skin: Color) -> void:
	var shade := skin.darkened(0.22)
	var line := skin.darkened(0.4)
	match _part("nose"):
		0:  # Button.
			_ellipse(Vector2(50, 45), Vector2(2.4, 2), shade, false)
		1:  # Long.
			_line(_p([50, 37, 51, 47, 48.5, 48]), line)
		2:  # Wide.
			_line(_ellipse_points(Vector2(50, 46), Vector2(4.5, 2.2), 0.2, PI - 0.2, 10), line)
			draw_circle(Vector2(47.5, 47), 0.8, line, true, -1.0, true)
			draw_circle(Vector2(52.5, 47), 0.8, line, true, -1.0, true)
		3:  # Pointed.
			_shape(_p([50, 39, 53, 47.5, 48, 47.5]), shade, false)
		4:  # Hooked.
			_line(_p([49.5, 38, 53, 44, 52, 48, 48.5, 47.5]), line)
		5:  # Small.
			draw_circle(Vector2(49, 46), 0.7, line, true, -1.0, true)
			draw_circle(Vector2(51, 46), 0.7, line, true, -1.0, true)
		6:  # Roman.
			_line(_p([50, 35, 52.5, 45, 51, 47.5, 48, 47]), line, 1.4)
		7:  # Snub.
			_line(_ellipse_points(Vector2(50, 44.5), Vector2(2.6, 2.2), 0.0, PI, 10), line)
			draw_circle(Vector2(49, 46), 0.6, line, true, -1.0, true)
			draw_circle(Vector2(51, 46), 0.6, line, true, -1.0, true)
		8:  # Broad.
			_ellipse(Vector2(50, 45.5), Vector2(4, 2.6), shade, false)
		9:  # Freckled.
			_ellipse(Vector2(50, 45), Vector2(2.2, 1.9), shade, false)
			for spot: Vector2 in [Vector2(41, 43), Vector2(43, 45), Vector2(40, 46), Vector2(59, 43), Vector2(57, 45), Vector2(60, 46)]:
				draw_circle(spot, 0.6, Color("#a5603a"), true, -1.0, true)


func _draw_mouth(skin: Color) -> void:
	var line := Color("#5a2a22")
	var lip := skin.darkened(0.25).lerp(Color("#c0504d"), 0.35)
	var at := Vector2(50, 51)
	match _part("mouth"):
		0:  # Smile.
			_line(_ellipse_points(at + Vector2(0, -1.5), Vector2(5, 3), 0.25, PI - 0.25, 12), line, 1.3)
		1:  # Grin.
			var grin := _ellipse_points(at + Vector2(0, -0.5), Vector2(5.5, 3.6), 0.0, PI, 12)
			_shape(grin, Color("#fbfbfb"))
			_line(_p([at.x - 5, at.y + 1, at.x + 5, at.y + 1]), Color(0, 0, 0, 0.25), 0.5)
		2:  # Straight.
			_line(_p([at.x - 4, at.y, at.x + 4, at.y]), line, 1.3)
		3:  # Smirk.
			_line(_p([at.x - 4, at.y + 0.5, at.x + 2, at.y + 0.3, at.x + 4.5, at.y - 1.5]), line, 1.3)
		4:  # Laugh.
			var open := _ellipse_points(at + Vector2(0, -0.5), Vector2(5, 4.5), 0.0, PI, 12)
			_shape(open, Color("#5a1a1a"))
			_ellipse(at + Vector2(0, 2.4), Vector2(2.6, 1.4), Color("#d0606a"), false)
		5:  # Surprised.
			_ellipse(at + Vector2(0, 0.5), Vector2(2, 2.6), Color("#5a1a1a"))
		6:  # Frown.
			_line(_ellipse_points(at + Vector2(0, 2.5), Vector2(4.5, 2.5), PI + 0.3, TAU - 0.3, 12), line, 1.3)
		7:  # Red lips.
			_ellipse(at, Vector2(4.6, 2.2), Color("#c42f42"), false)
			_line(_p([at.x - 4.3, at.y, at.x + 4.3, at.y]), Color("#7a1a28"), 0.7)
		8:  # Cheeky.
			_line(_ellipse_points(at + Vector2(0, -1.5), Vector2(5, 3), 0.25, PI - 0.25, 12), line, 1.3)
			_ellipse(at + Vector2(1.5, 2.2), Vector2(1.8, 1.6), Color("#d0606a"))
		9:  # Gentle.
			_shape(_ellipse_points(at + Vector2(0, -0.6), Vector2(4, 1.8), 0.0, PI, 10), lip, false)
			_line(_ellipse_points(at + Vector2(0, -1.0), Vector2(4, 1.6), 0.2, PI - 0.2, 10), line, 0.9)


func _draw_beard(hair: Color) -> void:
	var jaw := _p([34, 40, 35, 48, 40, 55, 46, 58.5, 54, 58.5, 60, 55, 65, 48, 66, 40, 63, 45, 58, 49, 50, 50, 42, 49, 37, 45])
	match _part("facial_hair"):
		1:  # Stubble.
			draw_colored_polygon(jaw, Color(hair, 0.28))
		4:  # Full beard.
			_shape(jaw, hair)
		5:  # Chinstrap.
			_shape(_p([34, 40, 35, 48, 40, 55, 46, 58.5, 54, 58.5, 60, 55, 65, 48, 66, 40, 64, 41, 63, 48, 58, 53, 50, 56, 42, 53, 37, 48, 36, 41]), hair)
		8:  # Mutton chops.
			for side: float in [-1.0, 1.0]:
				_shape(_p([50 + side * 16, 38, 50 + side * 16.5, 48, 50 + side * 12, 53, 50 + side * 9, 50, 50 + side * 12.5, 38]), hair)
		9:  # Long beard.
			_shape(_p([34, 40, 35, 50, 40, 62, 46, 74, 50, 77, 54, 74, 60, 62, 65, 50, 66, 40, 63, 45, 58, 49, 50, 50, 42, 49, 37, 45]), hair)


func _draw_moustache(hair: Color) -> void:
	match _part("facial_hair"):
		2, 3:  # Moustache, goatee.
			_shape(_p([44, 49.5, 47, 47.5, 50, 48.2, 53, 47.5, 56, 49.5, 53, 49.2, 50, 49.8, 47, 49.2]), hair)
			if _part("facial_hair") == 3:
				_shape(_p([46, 54, 54, 54, 53, 59, 50, 60.5, 47, 59]), hair)
		4, 9:  # The full and long beards' moustache.
			_shape(_p([43, 49.5, 47, 47, 50, 48, 53, 47, 57, 49.5, 53, 49.5, 50, 50, 47, 49.5]), hair.darkened(0.1))
		6:  # Handlebar.
			_shape(_p([44, 49, 47, 47.5, 50, 48.2, 53, 47.5, 56, 49, 53, 49.2, 50, 49.8, 47, 49.2]), hair)
			for side: float in [-1.0, 1.0]:
				_line(_p([50 + side * 5.5, 49, 50 + side * 9, 48.5, 50 + side * 10, 46, 50 + side * 8.5, 45]), hair, 1.4)
		7:  # Soul patch.
			_shape(_p([48.5, 54, 51.5, 54, 50, 57]), hair)


# --- Hair, glasses and hats ----------------------------------------------------

func _draw_back_hair(hair: Color) -> void:
	match _part("hair"):
		4:  # Long.
			_shape(_p([32, 30, 68, 30, 70, 74, 60, 78, 50, 74, 40, 78, 30, 74]), hair)
		5:  # Bob.
			_shape(_p([32, 30, 68, 30, 69, 55, 62, 57, 38, 57, 31, 55]), hair)
		6:  # Ponytail.
			_shape(_p([62, 30, 71, 36, 74, 56, 70, 66, 66, 56, 64, 38]), hair)
		7:  # Curly.
			for spot: Vector2 in [Vector2(34, 32), Vector2(66, 32), Vector2(32, 44), Vector2(68, 44), Vector2(36, 54), Vector2(64, 54)]:
				_ellipse(spot, Vector2(7, 7), hair)
		9:  # Bun.
			_ellipse(Vector2(50, 15), Vector2(8, 7), hair)


func _draw_front_hair(hair: Color) -> void:
	var cap := _ellipse_points(HEAD + Vector2(0, -1), HEAD_RADII + Vector2(1, 1), PI * 1.02, TAU * 0.99, 18)
	match _part("hair"):
		1:  # Buzz cut.
			var buzz := _ellipse_points(HEAD, HEAD_RADII, PI * 1.08, TAU * 0.96, 16)
			buzz.append(Vector2(50, 27))
			draw_colored_polygon(buzz, Color(hair, 0.6))
		2:  # Short.
			cap.append_array(_p([62, 27, 56, 25, 50, 27, 44, 25, 38, 27, 34, 33]))
			_shape(cap, hair)
		3:  # Side part.
			cap.append_array(_p([64, 30, 54, 25, 42, 30, 36, 36]))
			_shape(cap, hair)
			_line(_p([42, 21, 44, 26]), hair.darkened(0.3), 0.8)
		4, 5:  # Long, bob: a fringe swept to the sides.
			cap.append_array(_p([66, 38, 60, 27, 50, 25, 40, 27, 34, 38]))
			_shape(cap, hair)
		6, 9:  # Ponytail, bun: pulled back.
			cap.append_array(_p([60, 26, 50, 24, 40, 26]))
			_shape(cap, hair)
		7:  # Curly.
			for x in range(36, 66, 6):
				_ellipse(Vector2(x, 22 + absf(x - 50.0) * 0.18), Vector2(5.5, 5.5), hair)
		8:  # Mohawk.
			_shape(_p([46, 30, 46, 14, 48, 6, 50, 2, 52, 6, 54, 14, 54, 30]), hair)


func _draw_eyewear() -> void:
	var left := Vector2(50 - EYE_X, EYE_Y)
	var right := Vector2(50 + EYE_X, EYE_Y)
	var frame := Color("#262626")
	match _part("eyewear"):
		1:  # Round.
			for at in [left, right]:
				_line(_ellipse_points(at, Vector2(4.6, 4.6)), frame, 1.0)
			_line(_p([left.x + 4.6, EYE_Y, right.x - 4.6, EYE_Y]), frame, 1.0)
		2:  # Square.
			for at: Vector2 in [left, right]:
				_line(_p([at.x - 5, at.y - 4, at.x + 5, at.y - 4, at.x + 5, at.y + 3.5, at.x - 5, at.y + 3.5, at.x - 5, at.y - 4]), frame, 1.2)
			_line(_p([left.x + 5, EYE_Y - 1, right.x - 5, EYE_Y - 1]), frame, 1.0)
		3:  # Sunglasses.
			for at: Vector2 in [left, right]:
				_shape(_p([at.x - 5.5, at.y - 3.5, at.x + 5.5, at.y - 3.5, at.x + 4.5, at.y + 3, at.x - 4.5, at.y + 3]), Color("#151515"))
			_line(_p([left.x + 5.5, EYE_Y - 2, right.x - 5.5, EYE_Y - 2]), frame, 1.2)
		4:  # Aviators.
			for at: Vector2 in [left, right]:
				var lens := _ellipse_points(at + Vector2(0, 0.5), Vector2(5, 4.2), 0.0, TAU, 20)
				draw_colored_polygon(lens, Color(0.35, 0.25, 0.1, 0.7))
				_line(lens, Color("#c8a040"), 0.9)
			_line(_p([left.x + 4, EYE_Y - 3, right.x - 4, EYE_Y - 3]), Color("#c8a040"), 0.9)
		5:  # Monocle.
			_line(_ellipse_points(right, Vector2(4.8, 4.8)), Color("#c8a040"), 1.1)
			_line(_p([right.x + 3, right.y + 4, right.x + 6, right.y + 14, right.x + 3, right.y + 24]), Color("#c8a040"), 0.6)
		6:  # Half-rims.
			for at: Vector2 in [left, right]:
				_line(_p([at.x - 5, at.y - 2.5, at.x + 5, at.y - 2.5]), frame, 2.0)
				_line(_ellipse_points(at + Vector2(0, -2.5), Vector2(5, 5), 0.0, PI, 10), Color(frame, 0.35), 0.6)
			_line(_p([left.x + 5, EYE_Y - 2.5, right.x - 5, EYE_Y - 2.5]), frame, 1.0)
		7:  # Cat-eye.
			for side: float in [-1.0, 1.0]:
				var at := left if side < 0.0 else right
				var outer := at.x + side * 5.5
				_line(_p([at.x - side * 4.5, at.y - 2.5, outer, at.y - 4.5, at.x + side * 4, at.y + 3, at.x - side * 4, at.y + 3, at.x - side * 4.5, at.y - 2.5]), Color("#c42f42"), 1.4)
			_line(_p([left.x + 4.5, EYE_Y - 2, right.x - 4.5, EYE_Y - 2]), Color("#c42f42"), 1.0)
		8:  # Goggles.
			_line(_p([34, EYE_Y, 66, EYE_Y]), Color("#3a3a3a"), 3.0)
			for at: Vector2 in [left, right]:
				_ellipse(at, Vector2(5.5, 4.8), Color(0.55, 0.8, 0.95, 0.75))
				_line(_ellipse_points(at, Vector2(5.5, 4.8)), Color("#3a3a3a"), 1.4)
		9:  # Eye patch.
			_line(_p([35, 30, 65, 44]), Color("#111111"), 1.0)
			_ellipse(left + Vector2(0, 0.5), Vector2(5, 4.5), Color("#111111"))


func _draw_headwear() -> void:
	match _part("headwear"):
		1:  # Captain's cap.
			_shape(_p([31, 26, 34, 14, 50, 10, 66, 14, 69, 26]), Color("#f4f4f4"))
			_shape(_p([33, 24, 67, 24, 67, 29, 33, 29]), Color("#1a1a1a"))
			_shape(_p([33, 29, 67, 29, 62, 34, 38, 34]), Color("#151515"))
			_ellipse(Vector2(50, 20), Vector2(4, 3), Color("#e2b43c"))
		2:  # Beanie.
			_shape(_ellipse_points(Vector2(50, 27), Vector2(18, 17), PI, TAU, 16), Color("#c8343a"))
			_shape(_p([32, 24, 68, 24, 68, 31, 32, 31]), Color("#a82a30"))
			_ellipse(Vector2(50, 9), Vector2(3.5, 3.5), Color("#f0f0f0"))
		3:  # Baseball cap.
			_shape(_ellipse_points(Vector2(50, 28), Vector2(17.5, 15), PI, TAU, 16), Color("#2f5fb0"))
			_shape(_p([34, 27, 66, 27, 76, 31, 66, 32, 34, 30]), Color("#24498a"))
			draw_circle(Vector2(50, 13.5), 1.4, Color("#24498a"), true, -1.0, true)
		4:  # Bucket hat.
			_shape(_p([36, 28, 38, 14, 50, 11, 62, 14, 64, 28]), Color("#b9a274"))
			_shape(_p([30, 26, 70, 26, 75, 33, 25, 33]), Color("#a68f62"))
		5:  # Cowboy hat.
			_shape(_p([37, 24, 38, 10, 46, 8, 50, 11, 54, 8, 62, 10, 63, 24]), Color("#8a5a30"))
			_shape(_p([18, 24, 30, 27, 50, 28, 70, 27, 82, 24, 78, 30, 64, 33, 36, 33, 22, 30]), Color("#7a4e28"))
			_line(_p([37.5, 22, 62.5, 22]), Color("#3a2414"), 2.0)
		6:  # Bandana.
			_shape(_ellipse_points(Vector2(50, 29), Vector2(17.5, 14), PI, TAU, 16), Color("#c8343a"))
			_shape(_p([66, 26, 74, 22, 76, 30, 70, 31]), Color("#a82a30"))
			for spot: Vector2 in [Vector2(42, 21), Vector2(50, 18), Vector2(58, 21), Vector2(46, 26), Vector2(55, 26)]:
				draw_circle(spot, 1.0, Color("#f4f4f4"), true, -1.0, true)
		7:  # Top hat.
			_shape(_p([37, 25, 38, -4, 62, -4, 63, 25]), Color("#1a1a1a"))
			_shape(_p([38, 18, 62, 18, 62, 23, 38, 23]), Color("#7a1a28"))
			_shape(_p([28, 24, 72, 24, 70, 29, 30, 29]), Color("#111111"))
		8:  # Sailor cap.
			_shape(_ellipse_points(Vector2(50, 26), Vector2(15, 9), PI, TAU, 14), Color("#f8f8f8"))
			_shape(_p([30, 23, 70, 23, 68, 30, 32, 30]), Color("#ececec"))
		9:  # Hard hat.
			_shape(_ellipse_points(Vector2(50, 27), Vector2(17, 16), PI, TAU, 16), Color("#f2c230"))
			_shape(_p([29, 26, 71, 26, 73, 30, 27, 30]), Color("#e0b020"))
			_line(_p([50, 11, 50, 26]), Color("#d0a018"), 2.0)
