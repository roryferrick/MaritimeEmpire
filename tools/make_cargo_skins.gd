# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends SceneTree
## Makes the per-commodity cargo art for livestock and vehicle carriers
## (art/ships/<category>_cargo_<commodity>.svg; see MapView.load_ship_art())
## from the general cargo art: cows (the original), sheep (cream fleeces with
## dark faces) and pigs (pink) in the pens; cars (the original), trucks (a cab
## and a long box trailer across two car spaces) and boats (white hulls with a
## pointed bow and a blue stripe) on the decks.
##
##   Godot --headless --path . -s tools/make_cargo_skins.gd

const DIR := "res://art/ships/"
const HEADER := "<!-- Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire. -->"
const SHEEP := ["#f6f2e6", "#ece6d6", "#fffcf2", "#e4ddc8"]
const PIGS := ["#f3b7b0", "#e9a39c", "#f8c9c3", "#dc9088"]
const TRAILERS := ["#f4f4f4", "#c0392b", "#2e5c9a", "#e1b12c", "#d8d8d8", "#27805a"]
const STRIPES := ["#2e5c9a", "#1f3f6a", "#c0392b", "#27805a"]


func _init() -> void:
	var animals := FileAccess.get_file_as_string(DIR + "livestock_cargo.svg")
	_save("livestock_cargo_cows.svg", animals)
	_save("livestock_cargo_sheep.svg", _animals(animals, SHEEP, "#2a2420"))
	_save("livestock_cargo_pigs.svg", _animals(animals, PIGS, ""))
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
