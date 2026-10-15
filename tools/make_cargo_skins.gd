# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends SceneTree
## Makes the per-commodity cargo art for livestock and vehicle carriers
## (art/ships/<category>_cargo_<commodity>.svg; see MapView.load_ship_art())
## from the general cargo art: cows (the original), sheep (cream fleeces with
## dark faces), pigs (pink) and horses (bays, chestnuts, greys and blacks with
## dark heads) in the pens; cars (the original), trucks (a cab
## and a long box trailer across two car spaces) and boats (white hulls with a
## pointed bow and a blue stripe) on the decks; and for the Fresh produce
## carriers, crates of each fresh crop (data/farms.json colours) under their
## slatted hatch covers (produce_cargo.svg itself is apples).
##
##   Godot --headless --path . -s tools/make_cargo_skins.gd

const DIR := "res://art/ships/"
const HEADER := "<!-- Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire. -->"
const SHEEP := ["#f6f2e6", "#ece6d6", "#fffcf2", "#e4ddc8"]
const PIGS := ["#f3b7b0", "#e9a39c", "#f8c9c3", "#dc9088"]
const HORSES := ["#7a3e1c", "#a0602c", "#d8d0c4", "#2a201a", "#c8a070", "#5a301a"]
## The produce crates: the cargo zone's columns and rows (art units).
const CRATE_X := [35.0, 48.0, 61.0, 74.0, 87.0, 100.0, 113.0, 126.0]
const CRATE_Y := [9.0, 21.0, 33.0]
const CRATE_SIZE := Vector2(12.0, 11.0)
## How each crop sits in its crates.
const SMALL := ["cherries", "strawberries", "blueberries", "raspberries", "blackberries", "cranberries", "grapes"]
const LONG := ["bananas"]
const LEAFY := ["lettuce"]
const OVAL := ["lemons", "mangoes", "avocados", "potatoes", "peppers", "pears"]
const TRAILERS := ["#f4f4f4", "#c0392b", "#2e5c9a", "#e1b12c", "#d8d8d8", "#27805a"]
const STRIPES := ["#2e5c9a", "#1f3f6a", "#c0392b", "#27805a"]


func _init() -> void:
	var animals := FileAccess.get_file_as_string(DIR + "livestock_cargo.svg")
	_save("livestock_cargo_cows.svg", animals)
	_save("livestock_cargo_sheep.svg", _animals(animals, SHEEP, "#2a2420"))
	_save("livestock_cargo_pigs.svg", _animals(animals, PIGS, ""))
	_save("livestock_cargo_horses.svg", _animals(animals, HORSES, "#1e140c"))
	var farms: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/farms.json"))
	for crop: Dictionary in farms.get("crops", []):
		if crop.kind == "fresh":
			_save("produce_cargo_%s.svg" % crop.id, _produce(str(crop.id), Color(str(crop.color))))
			if crop.id == "apples":
				_save("produce_cargo.svg", _produce("apples", Color(str(crop.color))))
	var cars := FileAccess.get_file_as_string(DIR + "vehicles_cargo.svg")
	_save("vehicles_cargo_cars.svg", cars)
	_save("vehicles_cargo_trucks.svg", _vehicles(cars, true))
	_save("vehicles_cargo_boats.svg", _vehicles(cars, false))
	quit()


func _save(file_name: String, text: String) -> void:
	var file := FileAccess.open(DIR + file_name, FileAccess.WRITE)
	file.store_string(text)
	print("Wrote ", file_name)


## Each animal recoloured from the palette in turn; with a face color, a small
## dark head at one end (sheep have black faces).
static func _animals(svg: String, palette: Array, face: String) -> String:
	var regex := RegEx.create_from_string('<ellipse cx="([0-9.]+)" cy="([0-9.]+)" rx="([0-9.]+)" ry="([0-9.]+)" fill="#[0-9a-f]{6}"')
	var out := ""
	var last := 0
	var n := 0
	for found in regex.search_all(svg):
		out += svg.substr(last, found.get_start() - last)
		var cx := float(found.get_string(1))
		var cy := float(found.get_string(2))
		var rx := float(found.get_string(3))
		out += '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s"' % [cx, cy, rx, found.get_string(4), palette[n % palette.size()]]
		if not face.is_empty():
			out = out.substr(0, out.rfind("<ellipse")) + '<circle cx="%s" cy="%s" r="0.9" fill="%s"/>' % [cx + rx * 0.95, cy, face] + out.substr(out.rfind("<ellipse"))
		last = found.get_end()
		n += 1
	return out + svg.substr(last)


## A Fresh produce carrier's crates of a crop: wooden crates in the cargo
## zone, each filled with the crop in its colour (lighter and darker by turns),
## round, oval, small (berries, cherries, grapes), long (bananas) or leafy.
static func _produce(crop_id: String, color: Color) -> String:
	var lines := PackedStringArray(['<svg xmlns="http://www.w3.org/2000/svg" width="180" height="52" viewBox="0 0 180 52">', HEADER])
	var n := 0
	for x: float in CRATE_X:
		for y: float in CRATE_Y:
			lines.append('<rect x="%s" y="%s" width="%s" height="%s" rx="0.6" fill="#7a5a36" stroke="#3a2a18" stroke-width="0.5"/>' % [x, y, CRATE_SIZE.x, CRATE_SIZE.y])
			var shade := color.lightened(0.18) if n % 3 == 1 else (color.darkened(0.15) if n % 3 == 2 else color)
			var fill := "#" + shade.to_html(false)
			var edge := "#" + color.darkened(0.45).to_html(false)
			var cx := x + CRATE_SIZE.x / 2.0
			var cy := y + CRATE_SIZE.y / 2.0
			if crop_id in SMALL:
				for i in 3:
					for j in 3:
						lines.append('<circle cx="%s" cy="%s" r="1.25" fill="%s" stroke="%s" stroke-width="0.3"/>' % [x + 2.4 + i * 3.6, y + 2.2 + j * 3.3, fill, edge])
			elif crop_id in LONG:
				for i in 3:
					var top := y + 2.0 + i * 3.3
					lines.append('<path d="M%s,%s Q%s,%s %s,%s" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round"/>' % [x + 1.8, top + 1.6, cx, top - 0.6, x + CRATE_SIZE.x - 1.8, top + 1.6, fill])
					lines.append('<circle cx="%s" cy="%s" r="0.6" fill="#3a2a18"/>' % [x + CRATE_SIZE.x - 1.6, top + 1.6])
			elif crop_id in LEAFY:
				for i in 2:
					lines.append('<circle cx="%s" cy="%s" r="3.1" fill="%s" stroke="%s" stroke-width="0.4"/>' % [x + 3.3 + i * 5.4, cy, fill, edge])
					lines.append('<circle cx="%s" cy="%s" r="1.4" fill="#%s"/>' % [x + 3.3 + i * 5.4, cy, color.lightened(0.45).to_html(false)])
			elif crop_id == "pineapples":
				for i in 2:
					var px := x + 3.3 + i * 5.4
					lines.append('<ellipse cx="%s" cy="%s" rx="2.3" ry="3.4" fill="%s" stroke="%s" stroke-width="0.4"/>' % [px, cy + 1.0, fill, edge])
					lines.append('<path d="M%s,%s l-1.2,-2.4 M%s,%s l0,-2.8 M%s,%s l1.2,-2.4" stroke="#3e7a2a" stroke-width="0.8"/>' % [px, cy - 2.2, px, cy - 2.2, px, cy - 2.2])
			else:
				var oval := crop_id in OVAL
				for i in 2:
					for j in 2:
						var fx := x + 3.2 + i * 5.6
						var fy := y + 3.0 + j * 5.0
						if oval:
							lines.append('<ellipse cx="%s" cy="%s" rx="2.5" ry="1.9" fill="%s" stroke="%s" stroke-width="0.35"/>' % [fx, fy, fill, edge])
						else:
							lines.append('<circle cx="%s" cy="%s" r="2.2" fill="%s" stroke="%s" stroke-width="0.35"/>' % [fx, fy, fill, edge])
						lines.append('<circle cx="%s" cy="%s" r="0.55" fill="#ffffff" fill-opacity="0.55"/>' % [fx - 0.8, fy - 0.7])
			n += 1
	lines.append("</svg>")
	return "\n".join(lines) + "\n"


## Trucks (two car spaces each: a box trailer and a darker cab) or boats (one
## space each: a white hull with a pointed bow and a stripe), in the car spaces.
static func _vehicles(svg: String, trucks: bool) -> String:
	var regex := RegEx.create_from_string('<rect x="([0-9.]+)" y="([0-9.]+)" width="([0-9.]+)" height="([0-9.]+)"[^>]*/>')
	var spaces := []
	for found in regex.search_all(svg):
		spaces.append(Vector4(float(found.get_string(1)), float(found.get_string(2)), float(found.get_string(3)), float(found.get_string(4))))
	var head := svg.substr(0, svg.find("<rect"))
	var body := ""
	var n := 0
	for space: Vector4 in spaces:
		var x := space.x
		var y := space.y
		var w := space.z
		var h := space.w
		if trucks:
			# A truck takes this space and the next one along (the odd columns).
			var column := roundi((x - spaces[0].x) / 8.4)
			if column % 2 == 1:
				continue
			var color: String = TRAILERS[n % TRAILERS.size()]
			body += '<rect x="%s" y="%s" width="%s" height="%s" rx="0.5" fill="%s" stroke="#1a1a1a" stroke-width="0.5"/>\n' % [x, y, w * 1.75, h, color]
			body += '<rect x="%s" y="%s" width="%s" height="%s" rx="0.8" fill="#3a3f46" stroke="#1a1a1a" stroke-width="0.5"/>\n' % [x + w * 1.85, y + 0.3, w * 0.55, h - 0.6]
		else:
			var stripe: String = STRIPES[n % STRIPES.size()]
			body += '<path d="M%s,%s L%s,%s L%s,%s L%s,%s L%s,%s Z" fill="#fbfbf8" stroke="#1a1a1a" stroke-width="0.5"/>\n' % [
				x, y + 0.4, x + w * 0.65, y + 0.1, x + w, y + h / 2.0, x + w * 0.65, y + h - 0.1, x, y + h - 0.4]
			body += '<path d="M%s,%s L%s,%s" stroke="%s" stroke-width="0.8"/>\n' % [x + 0.6, y + h / 2.0, x + w * 0.7, y + h / 2.0, stripe]
			body += '<rect x="%s" y="%s" width="%s" height="%s" rx="0.4" fill="#cfe3f0"/>\n' % [x + w * 0.25, y + h * 0.3, w * 0.25, h * 0.4]
		n += 1
	return head + body + "</svg>\n"
