class_name ShipPicture
extends Control
## A model's map art (see MapView.load_ship_art()), bow to the right: its hull
## in the model's map color, a full hold for models whose cargo shows, and its
## details. Drawn `length` pixels long (bow included) and as wide as the
## model's map_size proportions make it, centered in the control. Models
## without art are drawn as their plain map shape.

var model: Dictionary
var length := 100.0

var _art: Dictionary


func _init(for_model: Dictionary, pixels_long: float) -> void:
	model = for_model
	length = pixels_long
	_art = MapView.load_ship_art(str(model.get("category", "")))
	mouse_filter = MOUSE_FILTER_IGNORE
	# The art is drawn well below its size: mipmaps keep it smooth.
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	var dims: Array = model.get("map_size", [14, 6])
	var width := float(dims[1])
	var map_length := float(dims[0]) + width * MapView.BOW_LENGTH_FACTOR
	var rect_size := Vector2(length, length * width / map_length)
	var rect := Rect2((size - rect_size) / 2.0, rect_size)
	var color := Color.from_string(model.get("map_color", "#ffffff"), Color.WHITE)
	if _art.is_empty():
		draw_rect(rect, color)
		return
	draw_texture_rect(_art.hull, rect, false, color)
	if _art.has("cargo"):
		var zone: Vector2 = _art.zone
		var share := zone.y / MapView.SHIP_ART_WIDTH
		var texture: Texture2D = _art.cargo
		draw_texture_rect_region(texture, Rect2(rect.position, Vector2(rect.size.x * share, rect.size.y)),
			Rect2(Vector2.ZERO, Vector2(texture.get_width() * share, texture.get_height())))
	draw_texture_rect(_art.details, rect, false)
