class_name LabelAtlas
extends SubViewport
## The map's labels (port, country and feature names) rendered once into one
## texture, each then put on the map as a quad from it (all of a frame's in
## one batch: see MapView._draw_label_layer()) instead of being shaped and set
## glyph by glyph every frame the view moves. Text is rendered white on black
## at the window's pixel scale, so the texture holds each label's coverage
## (its red channel), coloured by the quad's tint through LABEL_SHADER; a sea
## name's outline is an entry of its own. Entries are packed in rows by
## height. Anything not in the atlas (see cell()) is drawn the old way.

const LABEL_SHADER := preload("res://scripts/ui/label.gdshader")
## The atlas's width (logical px); its height is what the rows need, up to this.
const WIDTH := 2048
const MAX_HEIGHT := 2048
## Clear px round each entry (plus its outline), so neighbours never bleed in.
const PAD := 2

var _entries := {}  # font -> {size * 16 + outline -> {text -> cell Rect2 (logical px)}}
var _all := []  # Every entry: [font, size, outline, text, cell].
var _row_y := 0  # The next row's top...
var _row_h := 0  # ...the row being filled's height...
var _row_x := 0  # ...and how far along it is.
var _pixels := 1.0  # Device px per logical px (the window's scale).
var _full := false
var _stale := false  # Entries added since it was last rendered.
var _canvas := Control.new()


func _init(pixels := 1.0) -> void:
	_pixels = maxf(pixels, 0.5)
	size = Vector2i(WIDTH, 64)
	disable_3d = true
	gui_disable_input = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_canvas.draw.connect(_draw_entries)
	add_child(_canvas)


## Adds a label (nothing if it's in already, or there's no room). Shows once rendered: see render().
func add(font: Font, font_size: int, outline: int, text: String) -> void:
	if font == null or text.is_empty() or _full:
		return
	var by_font: Dictionary = _entries.get_or_add(font, {})
	var by_size: Dictionary = by_font.get_or_add(font_size * 16 + outline, {})
	if by_size.has(text):
		return
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var cell_size := Vector2i((text_size + Vector2.ONE * 2.0 * (PAD + outline)).ceil())
	if _row_x + cell_size.x > WIDTH:
		_row_y += _row_h
		_row_x = 0
		_row_h = 0
	if _row_y + cell_size.y > MAX_HEIGHT:
		_full = true
		return
	var cell := Rect2(Vector2(_row_x, _row_y), Vector2(cell_size))
	_row_x += cell_size.x
	_row_h = maxi(_row_h, cell_size.y)
	by_size[text] = cell
	_all.append([font, font_size, outline, text, cell])
	_stale = true


## The cell (logical px of the atlas) a label was rendered into, or an empty
## Rect2 if it isn't in. The label's text sits PAD + outline px in from the
## cell's top left; the quad for a label at `at` (its text's top left) is
## Rect2(at - Vector2.ONE * (PAD + outline), cell.size).
func cell(font: Font, font_size: int, outline: int, text: String) -> Rect2:
	if _stale:
		return Rect2()
	var by_font: Variant = _entries.get(font)
	if by_font == null:
		return Rect2()
	var by_size: Variant = (by_font as Dictionary).get(font_size * 16 + outline)
	if by_size == null:
		return Rect2()
	return (by_size as Dictionary).get(text, Rect2())


## The cell's place in the texture (0 to 1 each way), for its quad's UVs.
func uv(cell_rect: Rect2) -> Rect2:
	var logical := Vector2(size) / _pixels
	return Rect2(cell_rect.position / logical, cell_rect.size / logical)


## Renders every entry (once, when any's been added) at the window's pixel
## scale: the texture's sized to the rows. Call once a frame before drawing from it.
func render(pixels: float) -> void:
	pixels = maxf(pixels, 0.5)
	if not _stale and is_equal_approx(pixels, _pixels):
		return
	_pixels = pixels
	_stale = false
	size = Vector2i((Vector2(WIDTH, maxi(_row_y + _row_h, 1)) * _pixels).ceil())
	_canvas.size = Vector2(size) / _pixels
	_canvas.queue_redraw()
	render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw_entries() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(size)), Color.BLACK)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _pixels)
	for entry: Array in _all:
		var font: Font = entry[0]
		var font_size: int = entry[1]
		var outline: int = entry[2]
		var cell_rect: Rect2 = entry[4]
		var baseline := cell_rect.position + Vector2.ONE * (PAD + outline) + Vector2(0.0, font.get_ascent(font_size))
		if outline > 0:
			_canvas.draw_string_outline(font, baseline, entry[3], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color.WHITE)
		else:
			_canvas.draw_string(font, baseline, entry[3], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
