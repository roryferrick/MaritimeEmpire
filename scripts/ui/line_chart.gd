# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name LineChart
extends Control
## A line chart of one series (the Intelligence screen's price and currency
## history): the line over a faint grid, a dashed reference line (1.0, the
## usual price) when it's in range, the lowest and highest values at the left,
## a few x labels along the bottom, and the value under the mouse in a
## tooltip. Set the series and labels, then queue_redraw().

## The values, oldest first.
var series := PackedFloat32Array()
## A label for each value ("" for none); a few are shown.
var labels := PackedStringArray()
## Drawn dashed across the chart when within the values' range (0 for none).
var reference := 1.0
var line_color := Color(0.98, 0.78, 0.35)
## Values shown as "x1.25" (ratios) or as given.
var as_ratio := true
var font_size := 12
## A small chart (no axis labels, a thinner line).
var small := false

const PAD_LEFT := 46.0
const PAD_BOTTOM := 18.0
const PAD := 6.0
const X_LABELS := 6


func _init(height := 180.0) -> void:
	custom_minimum_size = Vector2(120.0, height)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _plot_rect() -> Rect2:
	if small:
		return Rect2(Vector2.ONE * 2.0, size - Vector2.ONE * 4.0)
	return Rect2(Vector2(PAD_LEFT, PAD), Vector2(size.x - PAD_LEFT - PAD, size.y - PAD - PAD_BOTTOM))


func _range() -> Array:
	var lo := INF
	var hi := -INF
	for v in series:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if series.is_empty():
		lo = 0.0
		hi = 1.0
	if reference > 0.0 and series.size() > 0:
		lo = minf(lo, reference)
		hi = maxf(hi, reference)
	if hi - lo < 0.0001:
		hi = lo + 1.0
	var margin := (hi - lo) * 0.08
	return [lo - margin, hi + margin]


func _point(k: int, lo: float, hi: float, rect: Rect2) -> Vector2:
	var x := rect.position.x + rect.size.x * (float(k) / maxf(series.size() - 1, 1))
	var y := rect.end.y - rect.size.y * (series[k] - lo) / (hi - lo)
	return Vector2(x, y)


func _text(value: float) -> String:
	return "x%s" % Fmt.decimal(value, 2) if as_ratio else Fmt.decimal(value, 2)


func _draw() -> void:
	var rect := _plot_rect()
	var font := get_theme_default_font()
	var dim := Color(1, 1, 1, 0.12)
	var text_color := Color(1, 1, 1, 0.7)
	draw_rect(rect, Color(0, 0, 0, 0.18))
	var span := _range()
	var lo: float = span[0]
	var hi: float = span[1]
	for k in 4:
		var y := rect.position.y + rect.size.y * k / 3.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), dim, 1.0)
	if series.is_empty():
		if not small:
			draw_string(font, rect.get_center() + Vector2(-40.0, 4.0), "No history yet", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		return
	if reference > 0.0 and reference >= lo and reference <= hi:
		var y := rect.end.y - rect.size.y * (reference - lo) / (hi - lo)
		var x := rect.position.x
		while x < rect.end.x:
			draw_line(Vector2(x, y), Vector2(minf(x + 6.0, rect.end.x), y), Color(1, 1, 1, 0.35), 1.0)
			x += 10.0
	var points := PackedVector2Array()
	for k in series.size():
		points.append(_point(k, lo, hi, rect))
	if points.size() >= 2:
		draw_polyline(points, line_color, 1.5 if small else 2.0, true)
	else:
		draw_circle(points[0], 3.0, line_color)
	if small:
		return
	# The lowest and highest values, and a few labels along the bottom.
	var low_k := 0
	var high_k := 0
	for k in series.size():
		if series[k] < series[low_k]:
			low_k = k
		if series[k] > series[high_k]:
			high_k = k
	draw_string(font, Vector2(2.0, rect.position.y + 10.0), _text(series[high_k]), HORIZONTAL_ALIGNMENT_LEFT, PAD_LEFT - 4.0, font_size, text_color)
	draw_string(font, Vector2(2.0, rect.end.y - 2.0), _text(series[low_k]), HORIZONTAL_ALIGNMENT_LEFT, PAD_LEFT - 4.0, font_size, text_color)
	if not labels.is_empty():
		var step := maxi(ceili(float(labels.size()) / X_LABELS), 1)
		var k := 0
		while k < labels.size():
			if not labels[k].is_empty():
				var at := _point(k, lo, hi, rect)
				draw_line(Vector2(at.x, rect.end.y), Vector2(at.x, rect.end.y + 3.0), text_color, 1.0)
				draw_string(font, Vector2(at.x - 20.0, size.y - 3.0), labels[k], HORIZONTAL_ALIGNMENT_LEFT, 60.0, font_size - 1, text_color)
			k += step


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not series.is_empty():
		var rect := _plot_rect()
		var k := clampi(roundi((event.position.x - rect.position.x) / maxf(rect.size.x, 1.0) * (series.size() - 1)), 0, series.size() - 1)
		tooltip_text = "%s%s" % [_text(series[k]), "" if labels.is_empty() or labels[k].is_empty() else " · " + labels[k]]
