# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends SceneTree
## Makes the logo and store art for Maritime Empire and Ships: the Dominator
## (its map art: red hull, full hold) bow up on a blue sea, at every size Steam,
## the App Store, Google Play, Amazon, Samsung and Huawei ask for, in
## branding/<game>/ (kept out of the game by branding/.gdignore). Art that
## shows the name puts it beside or below the ship.
##
## Needs a window (text is drawn by the renderer), so not --headless:
##   Godot --path . -s tools/make_branding.gd

const OUT := "res://branding/"
const SHIP_DIR := "res://art/ships/"
const HULL := Color("#cc2222")
const SEA_LIGHT := Color("#2f8ee0")
const SEA_DARK := Color("#0a3266")
const TEXT_OUTLINE := Color("#06203f")
const FONTS := ["Segoe UI Black", "Arial Black", "Impact"]
const GAMES := {
	"maritime_empire": ["MARITIME", "EMPIRE"],
	"ships": ["SHIPS"],
}
const ICON_SIZES := [512, 256, 192, 180, 167, 152, 144, 128, 120, 114, 96, 87, 80, 76, 72, 64, 60, 58, 48, 40, 32, 29, 20, 16]

var _ship_svg := ""
var _font: SystemFont


func _initialize() -> void:
	_run()


func _run() -> void:
	_ship_svg = _upright_ship_svg()
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(FONTS)
	_font.font_weight = 900
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ignore := FileAccess.open(OUT + ".gdignore", FileAccess.WRITE)
	ignore.close()
	for game: String in GAMES:
		await _make_game(game, GAMES[game])
	await _make_fleet()
	print("Branding written to ", ProjectSettings.globalize_path(OUT))
	quit()


func _make_game(game: String, name_lines: Array) -> void:
	var dir := OUT + game + "/"
	for sub in ["", "icons", "steam", "ios", "android", "amazon", "samsung", "huawei", "trademark"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + sub))

	# Vector masters.
	_save_text(dir + "logo.svg", _logo_svg(false))
	_save_text(dir + "logo_black_and_white.svg", _logo_svg(true))

	# The square icon, drawn at 1024 and scaled down for every other size.
	var icon := await _render(Vector2i(1024, 1024), _square.bind(0.8, true), false)
	_save_png(icon, dir + "logo_1024.png", false)
	for px: int in ICON_SIZES:
		_save_png(_scaled(icon, px), dir + "icons/icon_%d.png" % px, false)

	# Steam (store and library art; the name on every capsule, none on the hero).
	var steam := dir + "steam/"
	for spec: Array in [["header_capsule", 920, 430], ["small_capsule", 462, 174], ["main_capsule", 1232, 706],
			["vertical_capsule", 748, 896], ["library_capsule", 600, 900], ["library_header", 920, 430]]:
		var image := await _render(Vector2i(spec[1], spec[2]), _named.bind(name_lines), false)
		_save_png(image, steam + "%s_%dx%d.png" % spec, false)
	_save_png(await _render(Vector2i(3840, 1240), _hero, false), steam + "library_hero_3840x1240.png", false)
	_save_png(await _render(Vector2i(1280, 720), _name_only.bind(name_lines), true), steam + "library_logo_1280x720.png", true)
	_save_png(await _render(Vector2i(1438, 810), _background_only, false), steam + "page_background_1438x810.png", false)
	_opaque(_scaled(icon, 184)).save_jpg(steam + "community_icon_184x184.jpg", 0.95)
	_save_ico(steam + "client_icon.ico", [_scaled(icon, 16), _scaled(icon, 32)])
	_save_ico(steam + "shortcut_icon.ico", [_scaled(icon, 16), _scaled(icon, 32), _scaled(icon, 48), _scaled(icon, 256)])
	_save_ico(dir + "icons/windows_app_icon.ico", [_scaled(icon, 16), _scaled(icon, 32), _scaled(icon, 48), _scaled(icon, 256)])

	# iOS / iPadOS: the 1024 App Store icon (no transparency) and Xcode's sizes.
	_save_png(icon, dir + "ios/AppStore_1024.png", false)
	for px: int in [180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20]:
		_save_png(_scaled(icon, px), dir + "ios/icon_%d.png" % px, false)

	# Android / Google Play: store icon, adaptive layers (ship inside the safe
	# circle), legacy launcher sizes and the feature graphic.
	var android := dir + "android/"
	_save_png(_scaled(icon, 512), android + "play_store_icon_512.png", false)
	_save_png(await _render(Vector2i(432, 432), _square.bind(0.58, false), true), android + "adaptive_foreground_432.png", true)
	_save_png(await _render(Vector2i(432, 432), _background_only, false), android + "adaptive_background_432.png", false)
	_save_png(await _render(Vector2i(432, 432), _monochrome, true), android + "adaptive_monochrome_432.png", true)
	for spec: Array in [["mdpi", 48], ["hdpi", 72], ["xhdpi", 96], ["xxhdpi", 144], ["xxxhdpi", 192]]:
		_save_png(_scaled(icon, spec[1]), android + "launcher_%s_%d.png" % spec, false)
	_save_png(await _render(Vector2i(1024, 500), _named.bind(name_lines), false), android + "feature_graphic_1024x500.png", false)

	# Other Android stores.
	_save_png(_scaled(icon, 512), dir + "amazon/icon_512.png", false)
	_save_png(_scaled(icon, 114), dir + "amazon/icon_114.png", false)
	_save_png(_scaled(icon, 512), dir + "samsung/icon_512.png", false)
	_save_png(_scaled(icon, 216), dir + "huawei/icon_216.png", false)

	# Trademark drawings (USPTO: JPG, 250-944 px a side).
	_opaque(_scaled(icon, 900)).save_jpg(dir + "trademark/logo_color_900.jpg", 0.95)
	var mono := Image.new()
	mono.load_svg_from_string(_logo_svg(true), 900.0 / 1024.0)
	_opaque(mono).save_jpg(dir + "trademark/logo_black_and_white_900.jpg", 0.95)


## Promo shots in branding/fleet/: the Dominator, Supertanker and Giant Car
## Carrier under way to the north-east, side by side with wakes behind them,
## at their true relative sizes; plus a transparent ships-only version.
func _make_fleet() -> void:
	var dir := OUT + "fleet/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for spec: Array in [["fleet_3840x2160", 3840, 2160, true], ["fleet_1920x1080", 1920, 1080, true],
			["fleet_2048x2048", 2048, 2048, true], ["fleet_transparent_3840x2160", 3840, 2160, false]]:
		var image := await _render(Vector2i(spec[1], spec[2]), _fleet.bind(spec[3]), not spec[3])
		_save_png(image, dir + spec[0] + ".png", not spec[3])


func _fleet(vp: SubViewport, with_sea: bool) -> void:
	if with_sea:
		_add_sea(vp)
	var models := {}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ship_models.json"))
	for model: Dictionary in data.models:
		models[model.name] = model
	var size := Vector2(vp.size)
	var square := is_equal_approx(size.x, size.y)
	# Square: abreast on a line across their heading, the Supertanker a little
	# ahead. Wide: left to right, the outer two higher up.
	var fleet := [["Dominator", Vector2(0.29, 0.31)], ["Supertanker", Vector2(0.54, 0.48)],
		["Giant Car Carrier", Vector2(0.71, 0.73)]] if square else \
		[["Dominator", Vector2(0.24, 0.42)], ["Supertanker", Vector2(0.5, 0.6)], ["Giant Car Carrier", Vector2(0.76, 0.4)]]
	var longest := 0.0
	for entry: Array in fleet:
		longest = maxf(longest, _map_dims(models[entry[0]]).x)
	var px_per_unit := minf(size.x, size.y) * (0.36 if square else 0.46) / longest
	var heading := -PI / 4.0
	# Every wake first, so none is drawn over another ship.
	if with_sea:
		for entry: Array in fleet:
			_add_wake(vp, entry[1] * size, _map_dims(models[entry[0]]) * px_per_unit, heading)
	for entry: Array in fleet:
		_add_model(vp, models[entry[0]], entry[1] * size, _map_dims(models[entry[0]]) * px_per_unit, heading)


## A model's drawn length (bow included) and width in map units.
func _map_dims(model: Dictionary) -> Vector2:
	var dims: Array = model.map_size
	return Vector2(float(dims[0]) + float(dims[1]) * 0.6, float(dims[1]))


## A model's map art as the game draws it (see ShipPicture): hull in its map
## color, a full hold, details on top; `dims` long and wide, turned to `angle`.
func _add_model(vp: SubViewport, model: Dictionary, center: Vector2, dims: Vector2, angle: float) -> void:
	var category := str(model.category)
	var ship := Control.new()
	ship.size = dims
	ship.pivot_offset = dims / 2.0
	ship.position = center - dims / 2.0
	ship.rotation = angle
	vp.add_child(ship)
	var hull := _layer(ship, category + "_hull.svg", dims)
	hull.self_modulate = Color.from_string(str(model.map_color), Color.WHITE)
	var zones := {container = 138.0, vehicles = 147.4}
	if zones.has(category):
		var cargo := _layer(ship, category + "_cargo.svg", dims)
		var share: float = zones[category] / 180.0
		var atlas := AtlasTexture.new()
		atlas.atlas = cargo.texture
		atlas.region = Rect2(0, 0, cargo.texture.get_width() * share, cargo.texture.get_height())
		cargo.texture = atlas
		cargo.size.x = dims.x * share
	_layer(ship, category + "_details.svg", dims)


func _layer(parent: Control, file: String, dims: Vector2) -> TextureRect:
	var text := FileAccess.get_file_as_string(SHIP_DIR + file)
	var image := Image.new()
	image.load_svg_from_string(text, dims.x * 2.0 / 180.0)
	image.generate_mipmaps()
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.size = dims
	parent.add_child(rect)
	return rect


## Foam behind a moving ship: a widening trail from the stern, fading out.
func _add_wake(vp: SubViewport, center: Vector2, dims: Vector2, angle: float) -> void:
	var ahead := Vector2.from_angle(angle)
	var side := ahead.orthogonal()
	var stern := center - ahead * dims.x * 0.5
	var foam := Color(1, 1, 1, 0.35)
	var clear := Color(1, 1, 1, 0.0)
	# [half-width at the stern, half-width at the end, length, strength] (in ship widths and lengths).
	for layer: Array in [[0.9, 1.1, 1.1, 0.5], [0.45, 0.45, 0.7, 1.0]]:
		var trail := Polygon2D.new()
		var near: float = dims.y * 0.5 * layer[0]
		var far: float = dims.y * layer[1]
		var reach: float = dims.x * layer[2]
		trail.polygon = PackedVector2Array([stern + side * near, stern - side * near,
			stern - ahead * reach - side * far, stern - ahead * reach + side * far])
		var strength := Color(1, 1, 1, foam.a * layer[3])
		trail.vertex_colors = PackedColorArray([strength, strength, clear, clear])
		vp.add_child(trail)


# --- Layouts (each fills a SubViewport) ---

func _square(vp: SubViewport, ship_share: float, with_sea: bool) -> void:
	if with_sea:
		_add_sea(vp)
	var height := vp.size.y * ship_share
	_add_ship(vp, Vector2(vp.size) / 2.0, height)


func _named(vp: SubViewport, name_lines: Array) -> void:
	_add_sea(vp)
	var w := float(vp.size.x)
	var h := float(vp.size.y)
	if w > h * 1.25:
		# Wide: ship on the left, name filling the rest.
		var ship_h := h * 0.86
		var ship_w := ship_h * 52.0 / 180.0
		var margin := h * 0.12
		var ship_x := margin + ship_w / 2.0 + h * 0.06
		_add_ship(vp, Vector2(ship_x, h / 2.0), ship_h)
		var left := ship_x + ship_w / 2.0 + margin
		_add_name(vp, Rect2(left, h * 0.1, w - left - margin, h * 0.8), name_lines)
	else:
		# Tall or squarish: ship above, name below.
		var ship_h := h * 0.56
		_add_ship(vp, Vector2(w / 2.0, h * 0.06 + ship_h / 2.0), ship_h)
		_add_name(vp, Rect2(w * 0.08, h * 0.66, w * 0.84, h * 0.28), name_lines)


func _hero(vp: SubViewport) -> void:
	_add_sea(vp)
	_add_ship(vp, Vector2(vp.size) / 2.0, vp.size.y * 0.8)


func _name_only(vp: SubViewport, name_lines: Array) -> void:
	_add_name(vp, Rect2(Vector2(vp.size) * 0.05, Vector2(vp.size) * 0.9), name_lines)


func _background_only(vp: SubViewport) -> void:
	_add_sea(vp)


func _monochrome(vp: SubViewport) -> void:
	# A white silhouette: the ship's shape with every pixel turned white.
	var ship := _add_ship(vp, Vector2(vp.size) / 2.0, vp.size.y * 0.58)
	var image := ship.texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			image.set_pixel(x, y, Color(1, 1, 1, image.get_pixel(x, y).a))
	ship.texture = ImageTexture.create_from_image(image)


# --- Pieces ---

func _add_sea(vp: SubViewport) -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([SEA_LIGHT, SEA_DARK])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.45)
	texture.fill_to = Vector2(1.25, 1.2)
	texture.width = 256
	texture.height = 256
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = vp.size
	vp.add_child(rect)


func _add_ship(vp: SubViewport, center: Vector2, height: float) -> TextureRect:
	var image := Image.new()
	image.load_svg_from_string(_ship_svg, height / 180.0)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.size = Vector2(image.get_size())
	rect.position = (center - rect.size / 2.0).round()
	vp.add_child(rect)
	return rect


func _add_name(vp: SubViewport, box: Rect2, lines: Array) -> void:
	# The biggest size at which the widest line fits the width and all lines the height.
	var widest := 0.0
	for line: String in lines:
		widest = maxf(widest, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x)
	var line_h := _font.get_height(100) * 0.92
	var font_size := int(minf(box.size.x / widest, box.size.y / (line_h * lines.size())) * 100.0)
	var settings := LabelSettings.new()
	settings.font = _font
	settings.font_size = font_size
	settings.font_color = Color.WHITE
	settings.line_spacing = -_font.get_height(font_size) * 0.08
	settings.outline_size = maxi(2, font_size / 12)
	settings.outline_color = TEXT_OUTLINE
	settings.shadow_size = 0
	settings.shadow_color = Color(0, 0, 0, 0.35)
	settings.shadow_offset = Vector2(0, maxf(2.0, font_size * 0.05))
	var label := Label.new()
	label.text = "\n".join(lines)
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = box.position
	label.size = box.size
	vp.add_child(label)


func _render(size: Vector2i, build: Callable, transparent: bool) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	build.call(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	vp.queue_free()
	return image


# --- Ship art ---

## The Dominator's map art (container hull in its red, full hold, details),
## turned bow up: 52 wide, 180 tall.
func _upright_ship_svg() -> String:
	var hull := _svg_body("container_hull.svg") \
		.replace("#ffffff", "#" + HULL.to_html(false)) \
		.replace("#e2e2e2", "#" + (HULL * 0.886).to_html(false)) \
		.replace("#b4b4b4", "#" + (HULL * 0.706).to_html(false))
	var body := hull + _svg_body("container_cargo.svg") + _svg_body("container_details.svg")
	return '<svg xmlns="http://www.w3.org/2000/svg" width="52" height="180" viewBox="0 0 52 180">' \
		+ '<g transform="translate(0,180) rotate(-90)">' + body + "</g></svg>"


func _svg_body(file: String) -> String:
	var text := FileAccess.get_file_as_string(SHIP_DIR + file)
	var start := text.find(">", text.find("<svg")) + 1
	var body := text.substr(start, text.rfind("</svg>") - start)
	var comment := RegEx.create_from_string("<!--.*?-->")
	return comment.sub(body, "", true)


## The square logo as a vector file: sea and ship, or (black_and_white) a black
## square with the ship in white and black lines, for a trademark drawing that
## claims no colour.
func _logo_svg(black_and_white: bool) -> String:
	var ship := _ship_svg.substr(_ship_svg.find("<g"), _ship_svg.rfind("</svg>") - _ship_svg.find("<g"))
	var background := '<rect width="1024" height="1024" fill="url(#sea)"/>'
	var defs := '<defs><radialGradient id="sea" cx="0.5" cy="0.45" r="0.85" gradientUnits="objectBoundingBox">' \
		+ '<stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></radialGradient></defs>' \
		% [SEA_LIGHT.to_html(false), SEA_DARK.to_html(false)]
	if black_and_white:
		defs = ""
		background = '<rect width="1024" height="1024" fill="#000000"/>'
		# A white hull and bridge with black lines and a black hold of containers.
		var hull_colours := [HULL, HULL * 0.886, HULL * 0.706].map(func(c: Color) -> String: return c.to_html(false))
		var colour := RegEx.create_from_string('(fill|stroke)="#([0-9a-fA-F]{6})"')
		var out := ""
		var last := 0
		for m in colour.search_all(ship):
			var hex := m.get_string(2).to_lower()
			var white := m.get_string(1) == "fill" and (hex in hull_colours or Color("#" + hex).get_luminance() > 0.8)
			var bw := "#ffffff" if white else "#000000"
			out += ship.substr(last, m.get_start() - last) + '%s="%s"' % [m.get_string(1), bw]
			last = m.get_end()
		ship = out + ship.substr(last)
	var scale := 1024.0 * 0.8 / 180.0
	var place := "translate(%f,%f) scale(%f)" % [512.0 - 26.0 * scale, 512.0 - 90.0 * scale, scale]
	return '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n' \
		+ "<!-- Copyright (c) 2026 Rory Ferrick. All rights reserved. -->\n" \
		+ defs + background + '<g transform="%s">' % place + ship + "</g></svg>\n"


# --- Saving ---

func _scaled(image: Image, px: int) -> Image:
	var copy := image.duplicate() as Image
	copy.resize(px, px, Image.INTERPOLATE_LANCZOS)
	return copy


func _opaque(image: Image) -> Image:
	var copy := image.duplicate() as Image
	copy.convert(Image.FORMAT_RGB8)
	return copy


func _save_png(image: Image, path: String, keep_alpha: bool) -> void:
	var copy := image.duplicate() as Image
	copy.convert(Image.FORMAT_RGBA8 if keep_alpha else Image.FORMAT_RGB8)
	copy.save_png(path)


func _save_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


## A Windows .ico holding each image as a PNG entry.
func _save_ico(path: String, images: Array) -> void:
	var pngs: Array[PackedByteArray] = []
	for image: Image in images:
		var copy := image.duplicate() as Image
		copy.convert(Image.FORMAT_RGBA8)
		pngs.append(copy.save_png_to_buffer())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_16(0)
	file.store_16(1)
	file.store_16(pngs.size())
	var offset := 6 + 16 * pngs.size()
	for i in pngs.size():
		var px: int = images[i].get_width()
		file.store_8(0 if px >= 256 else px)
		file.store_8(0 if px >= 256 else px)
		file.store_8(0)
		file.store_8(0)
		file.store_16(1)
		file.store_16(32)
		file.store_32(pngs[i].size())
		file.store_32(offset)
		offset += pngs[i].size()
	for png in pngs:
		file.store_buffer(png)
