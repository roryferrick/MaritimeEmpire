# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CompanyLogo
extends Control
## A company's logo (Company.logo: {shape, layout, secondary, swap}), filling
## the control: its shape (square, circle, triangle or diamond) in its two
## colours (the company's colour and its secondary one; swap trades their
## places) laid out solid, bordered, split on the diagonal or with a stripe
## across, and the mark of the type the company started as (CompanyTypeIcon)
## on it. paint() draws one on any canvas (the map's HQ and hub signs).

const SHAPES := ["square", "circle", "triangle", "diamond"]
const LAYOUTS := ["solid", "bordered", "diagonal", "stripe"]
const SHAPE_NAMES := {square = "Square", circle = "Circle", triangle = "Triangle", diamond = "Diamond"}
const LAYOUT_NAMES := {solid = "Solid", bordered = "Bordered", diagonal = "Diagonal split", stripe = "Stripe"}

var logo := {}
var color_id := "purple"
var type_id := ""


func _init(for_logo := {}, company_color := "purple", start_type := "") -> void:
	logo = for_logo
	color_id = company_color
	type_id = start_type
	mouse_filter = MOUSE_FILTER_IGNORE


## A company's logo control (its logo, colour and first type).
static func of(company: Company) -> CompanyLogo:
	return CompanyLogo.new(company.logo, company.color, company.start_type())


func _draw() -> void:
	paint(self, Rect2(Vector2.ZERO, size), logo, color_id, type_id)


## A logo made up from a company's colour (rivals, joined players and saves
## from before logos): a square, solid, on a secondary colour that stands out
## from it; with a seed, a shape, layout and secondary picked at random.
static func default_logo(company_color: String, seed := -1) -> Dictionary:
	var colors: Array = (GameData.config.get("company_colors", []) as Array).map(func(entry: Array) -> String: return str(entry[0])).filter(func(id: String) -> bool: return id != company_color)
	if seed >= 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		return {shape = SHAPES[rng.randi() % SHAPES.size()], layout = LAYOUTS[rng.randi() % LAYOUTS.size()],
			secondary = colors[rng.randi() % colors.size()] if not colors.is_empty() else "white", swap = rng.randf() < 0.3}
	var light := GameState.company_color_value(company_color).get_luminance() > 0.6
	var secondary := "black" if light else "white"
	if secondary == company_color:
		secondary = "purple"
	return {shape = "square", layout = "solid", secondary = secondary, swap = false}


## Draws a logo into `area` (square, centred) on any canvas item.
static func paint(item: CanvasItem, area: Rect2, for_logo: Dictionary, company_color: String, start_type: String) -> void:
	var side := minf(area.size.x, area.size.y)
	var box := Rect2(area.position + (area.size - Vector2.ONE * side) / 2.0, Vector2.ONE * side)
	var primary := GameState.company_color_value(company_color)
	var secondary := GameState.company_color_value(str(for_logo.get("secondary", "white")))
	var back := secondary if for_logo.get("swap", false) else primary
	var fore := primary if for_logo.get("swap", false) else secondary
	var shape := _shape(str(for_logo.get("shape", "square")), box)
	var layout := str(for_logo.get("layout", "solid"))
	item.draw_colored_polygon(shape, back)
	var symbol := back if layout == "stripe" else fore  # (On the stripe, in the background's colour.)
	var symbol_back := fore if layout == "stripe" else back
	match layout:
		"bordered":
			var inner := _shape(str(for_logo.get("shape", "square")), box.grow(-side * 0.09))
			var ring := inner.duplicate()
			ring.append(inner[0])
			item.draw_polyline(ring, fore, maxf(side * 0.05, 1.0), true)
		"diagonal":
			var half := PackedVector2Array([box.position + Vector2(box.size.x, 0), box.end, box.position + Vector2(0, box.size.y)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(shape, half):
				item.draw_colored_polygon(piece, fore)
		"stripe":
			var band := PackedVector2Array([box.position + Vector2(0, side * 0.3), box.position + Vector2(side, side * 0.3),
				box.position + Vector2(side, side * 0.7), box.position + Vector2(0, side * 0.7)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(shape, band):
				item.draw_colored_polygon(piece, fore)
	# The mark: smaller in a triangle (to sit in its body), with a halo of the
	# background colour where it crosses a split.
	var scale := 0.42 if for_logo.get("shape", "") == "triangle" else 0.56
	var mark := Rect2(box.get_center() - Vector2.ONE * side * scale / 2.0, Vector2.ONE * side * scale)
	if str(for_logo.get("shape", "")) == "triangle":
		mark.position.y += side * 0.12
	if layout == "diagonal":
		CompanyTypeIcon.paint(item, start_type, mark.grow(side * 0.03), symbol_back, symbol_back)
	CompanyTypeIcon.paint(item, start_type, mark, symbol, symbol_back)


## A shape's outline filling `box`.
static func _shape(shape: String, box: Rect2) -> PackedVector2Array:
	var p := box.position
	var s := box.size
	match shape:
		"circle":
			var points := PackedVector2Array()
			for i in 40:
				var a := TAU * i / 40.0
				points.append(box.get_center() + Vector2(cos(a), sin(a)) * s.x / 2.0)
			return points
		"triangle":
			return PackedVector2Array([p + Vector2(s.x / 2.0, 0), p + s, p + Vector2(0, s.y)])
		"diamond":
			return PackedVector2Array([p + Vector2(s.x / 2.0, 0), p + Vector2(s.x, s.y / 2.0), p + Vector2(s.x / 2.0, s.y), p + Vector2(0, s.y / 2.0)])
	# A square with softly rounded corners.
	var r := s.x * 0.08
	var square := PackedVector2Array()
	for corner: Array in [[p + Vector2(s.x - r, r), -PI / 2.0], [p + Vector2(s.x - r, s.y - r), 0.0], [p + Vector2(r, s.y - r), PI / 2.0], [p + Vector2(r, r), PI]]:
		for i in 5:
			var a: float = corner[1] + PI / 2.0 * i / 4.0
			square.append((corner[0] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return square
