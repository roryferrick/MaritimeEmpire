# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name SiteArt
extends Control
## A research site's picture (see Research): a side view down through the
## sea to it, drawn from its category's template with its own details: the
## water darkening with depth (and its depth marked), the seabed, and what's
## there: a trench's walls dropping away under a submersible's light, a
## wreck (liner, galleon, warship or plane by its name), vents smoking, a
## seamount, a reef, columns of a sunken city, a canyon or blue hole, a whale
## or squid, or a mystery's sound trace. The same site always looks the same
## (its details are seeded by its id); an uncharted one is a dark sea with a "?".

var site_id := ""
var uncharted := false
var _rng := RandomNumberGenerator.new()


func _init(for_site := "", hide := false) -> void:
	site_id = for_site
	uncharted = hide
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(320, 170)


func _draw() -> void:
	var site := Research.site(site_id)
	var w := size.x
	var h := size.y
	_rng.seed = absi(site_id.hash())
	var depth := float(site.get("depth_m", 100))
	var deep := clampf(log(maxf(depth, 5.0)) / log(11000.0), 0.0, 1.0)  # (0 near the surface, 1 the deepest trench.)
	# The water: lit at the top, darker the deeper the site.
	var top := Color(0.36, 0.66, 0.82).lerp(Color(0.14, 0.3, 0.48), deep * 0.7)
	var bottom := Color(0.12, 0.34, 0.5).lerp(Color(0.01, 0.03, 0.09), deep)
	var bands := 24
	for i in bands:
		var t := float(i) / bands
		draw_rect(Rect2(0, h * t, w, h / bands + 1.0), top.lerp(bottom, t))
	draw_line(Vector2(0, 2), Vector2(w, 2), Color(1, 1, 1, 0.35), 2.0)
	if depth < 200.0:  # Sunlight in shafts down through the shallows.
		for i in 4:
			var x := w * (0.15 + 0.22 * i + _rng.randf_range(-0.05, 0.05))
			_poly(PackedVector2Array([Vector2(x, 0), Vector2(x + 18, 0), Vector2(x - 20, h * 0.8), Vector2(x - 44, h * 0.8)]), Color(1, 1, 0.9, 0.06))
	if uncharted:
		var font := get_theme_default_font()
		draw_string(font, Vector2(w / 2.0 - 10.0, h / 2.0 + 14.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1, 1, 1, 0.5))
		return
	var bed := h * 0.82
	var sand := Color(0.55, 0.5, 0.38).lerp(Color(0.18, 0.17, 0.16), deep)
	var category := str(site.get("category", ""))
	var color := Color.from_string(str(Research.category(category).get("color", "#9a7bd8")), Color(0.6, 0.5, 0.85))
	match category:
		"trench":
			_trench(w, h, sand)
		"seamount":
			_seabed(w, h, bed, sand)
			_seamount(w, h, bed, sand)
		"canyon":
			if depth <= 450.0:
				_blue_hole(w, h, sand)
			else:
				_canyon(w, h, sand)
		_:
			_seabed(w, h, bed, sand)
	match category:
		"wreck", "relic":
			if _is_plane(site):
				_plane(Vector2(w * 0.5, bed - 6.0), w * 0.42)
			else:
				_wreck(Vector2(w * 0.5, bed), w * 0.6, category == "relic", str(site.get("when", "")))
		"vent":
			_vents(w, bed)
		"reef":
			_reef(w, bed, depth > 60.0)
		"ruins":
			_ruins(w, bed)
		"wildlife":
			_wildlife(w, h, site)
	if category != "wildlife" and category != "trench" and depth < 1500.0:
		_fish(w, h, 4 + _rng.randi() % 5, Color(color.lightened(0.4), 0.8))
	# Its depth on a scale down the right.
	var font := get_theme_default_font()
	var label := "%s m" % Fmt.thousands(int(depth))
	draw_string(font, Vector2(w - 70.0, h - 8.0), label, HORIZONTAL_ALIGNMENT_RIGHT, 62, 13, Color(1, 1, 1, 0.85))
	draw_line(Vector2(w - 6.0, 6.0), Vector2(w - 6.0, h - 22.0), Color(1, 1, 1, 0.3), 1.0)
	for k in 5:
		var y := 6.0 + (h - 28.0) * k / 4.0
		draw_line(Vector2(w - 10.0, y), Vector2(w - 6.0, y), Color(1, 1, 1, 0.3), 1.0)


func _is_plane(site: Dictionary) -> bool:
	var name := str(site.get("name", "")).to_lower()
	for word: String in ["flight", "air ", "p-38", "mh370", "nikumaroro", "aircraft"]:
		if name.contains(word):
			return true
	return false


## A gently rolling seabed from the left edge to the right at about `bed`.
func _seabed(w: float, h: float, bed: float, sand: Color) -> void:
	var points := PackedVector2Array([Vector2(0, h)])
	for i in 13:
		points.append(Vector2(w * i / 12.0, bed + sin(i * 1.3 + _rng.randf() * 2.0) * 5.0))
	points.append(Vector2(w, h))
	_poly(points, sand)
	for i in 10:  # Pebbles.
		draw_circle(Vector2(_rng.randf() * w, bed + 6.0 + _rng.randf() * (h - bed - 8.0)), 1.5 + _rng.randf() * 2.0, sand.darkened(0.25))


func _trench(w: float, h: float, sand: Color) -> void:
	var left := PackedVector2Array([Vector2(0, h * 0.35), Vector2(w * 0.3, h * 0.42), Vector2(w * 0.42, h * 0.95), Vector2(w * 0.42, h), Vector2(0, h)])
	var right := PackedVector2Array([Vector2(w, h * 0.3), Vector2(w * 0.72, h * 0.4), Vector2(w * 0.56, h * 0.95), Vector2(w * 0.56, h), Vector2(w, h)])
	_poly(left, sand)
	_poly(right, sand.darkened(0.15))
	# A submersible far down, its light cone on the trench floor.
	var sub := Vector2(w * 0.49, h * 0.72)
	_poly(PackedVector2Array([sub + Vector2(4, 4), sub + Vector2(-26, h * 0.26), sub + Vector2(34, h * 0.26)]), Color(1, 0.95, 0.7, 0.12))
	_submersible(sub, 10.0)


func _submersible(at: Vector2, r: float) -> void:
	var hull := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		hull.append(at + Vector2(cos(a) * r * 1.5, sin(a) * r))
	_poly(hull, Color(0.95, 0.55, 0.15))
	draw_rect(Rect2(at + Vector2(-r * 0.4, -r * 1.5), Vector2(r * 0.8, r * 0.6)), Color(0.95, 0.55, 0.15))
	draw_circle(at + Vector2(r * 0.7, 0.0), r * 0.35, Color(0.7, 0.9, 1.0))
	draw_circle(at + Vector2(r * 1.5, r * 0.3), r * 0.25, Color(1, 1, 0.8))


func _seamount(w: float, h: float, bed: float, sand: Color) -> void:
	var peak := h * (0.2 + _rng.randf() * 0.15)
	_poly(PackedVector2Array([Vector2(w * 0.12, bed + 4), Vector2(w * 0.38, peak + 12), Vector2(w * 0.46, peak), Vector2(w * 0.56, peak + 4),
		Vector2(w * 0.86, bed + 4)]), sand.lightened(0.05))
	for i in 7:  # Corals and sponges on its flanks.
		var x := w * (0.3 + _rng.randf() * 0.4)
		var y := peak + (bed - peak) * (absf(x - w * 0.48) / (w * 0.38))
		draw_circle(Vector2(x, y), 2.5 + _rng.randf() * 2.5, Color(0.9, 0.55, 0.45, 0.9))


func _canyon(w: float, h: float, sand: Color) -> void:
	_poly(PackedVector2Array([Vector2(0, h * 0.25), Vector2(w * 0.2, h * 0.27), Vector2(w * 0.3, h * 0.6), Vector2(w * 0.38, h * 0.9), Vector2(w * 0.38, h), Vector2(0, h)]), sand)
	_poly(PackedVector2Array([Vector2(w, h * 0.22), Vector2(w * 0.78, h * 0.24), Vector2(w * 0.68, h * 0.55), Vector2(w * 0.6, h * 0.9), Vector2(w * 0.6, h), Vector2(w, h)]), sand.darkened(0.18))
	for k in 4:  # Its walls' strata.
		var y := h * (0.35 + 0.12 * k)
		draw_line(Vector2(0, y), Vector2(w * 0.24 + k * 8.0, y + 4.0), sand.darkened(0.2), 1.0)
		draw_line(Vector2(w, y - 6.0), Vector2(w * 0.74 - k * 7.0, y), sand.darkened(0.35), 1.0)


func _blue_hole(w: float, h: float, sand: Color) -> void:
	var lip := h * 0.32
	_poly(PackedVector2Array([Vector2(0, lip), Vector2(w * 0.32, lip), Vector2(w * 0.36, h), Vector2(0, h)]), sand.lightened(0.15))
	_poly(PackedVector2Array([Vector2(w, lip), Vector2(w * 0.68, lip), Vector2(w * 0.64, h), Vector2(w, h)]), sand.lightened(0.05))
	draw_rect(Rect2(w * 0.36, lip + 8.0, w * 0.28, h - lip), Color(0.0, 0.04, 0.16, 0.55))
	for i in 5:  # Stalactites from the old cave roof.
		var x := w * (0.33 + _rng.randf() * 0.04)
		_poly(PackedVector2Array([Vector2(x, lip + 20.0 + i * 18.0), Vector2(x + 7.0, lip + 20.0 + i * 18.0), Vector2(x + 3.5, lip + 34.0 + i * 18.0)]), sand.darkened(0.2))


func _wreck(at: Vector2, length: float, warship: bool, when: String) -> void:
	var old := when.contains("16") or when.contains("15") or when.contains("17") or when.contains("BC")
	var hull := Color(0.32, 0.22, 0.16) if old else Color(0.24, 0.24, 0.26)
	var rust := Color(0.55, 0.3, 0.16)
	var tilt := _rng.randf_range(-0.06, 0.06)
	var half := length / 2.0
	var broken := _rng.randf() < 0.5 and not old
	var pieces: Array = [[-half, half]] if not broken else [[-half, -half * 0.15], [half * 0.1, half]]
	for piece: Array in pieces:
		var a := at + Vector2(float(piece[0]), 0).rotated(tilt)
		var b := at + Vector2(float(piece[1]), 0).rotated(tilt)
		var up := Vector2(0, -length * 0.13).rotated(tilt)
		var bow := Vector2(length * 0.06, 0).rotated(tilt) if float(piece[1]) >= half - 1.0 else Vector2.ZERO
		_poly(PackedVector2Array([a + up, b + up + bow, b, a + Vector2(length * 0.04, 0).rotated(tilt)]), hull)
		draw_line(a + up, b + up + bow, rust, 2.0)
	if old:  # A galleon's broken masts and a cannon.
		for k in 2:
			var foot := at + Vector2(-length * 0.15 + k * length * 0.3, -length * 0.13)
			draw_line(foot, foot + Vector2(_rng.randf_range(-20, 20), -length * 0.2), Color(0.35, 0.25, 0.15), 3.0)
		draw_rect(Rect2(at + Vector2(-length * 0.4, -4), Vector2(14, 4)), Color(0.15, 0.15, 0.15))
	else:
		var funnels := 1 + _rng.randi() % 4
		for k in funnels:
			var x := -length * 0.2 + k * length * 0.13
			draw_rect(Rect2(at + Vector2(x, -length * 0.25), Vector2(length * 0.05, length * 0.12)), rust.darkened(0.2))
		if warship:  # Gun turrets fore and aft.
			for x: float in [-0.32, 0.3]:
				var t := at + Vector2(length * x, -length * 0.15)
				draw_rect(Rect2(t, Vector2(length * 0.07, length * 0.04)), hull.darkened(0.3))
				draw_line(t + Vector2(length * 0.07, length * 0.015), t + Vector2(length * 0.14, 0), hull.darkened(0.3), 2.0)
	for i in 6:  # Rusticles and growth.
		draw_line(at + Vector2(_rng.randf_range(-half, half), -length * 0.04), at + Vector2(_rng.randf_range(-half, half), length * 0.02), Color(0.7, 0.4, 0.2, 0.5), 1.0)


func _plane(at: Vector2, span: float) -> void:
	var body := Color(0.55, 0.58, 0.6)
	_poly(PackedVector2Array([at + Vector2(-span * 0.5, -3), at + Vector2(span * 0.45, -6), at + Vector2(span * 0.55, 0), at + Vector2(span * 0.45, 4), at + Vector2(-span * 0.5, 4)]), body)
	_poly(PackedVector2Array([at + Vector2(-span * 0.05, -2), at + Vector2(span * 0.12, -2), at + Vector2(span * 0.02, -span * 0.25), at + Vector2(-span * 0.12, -span * 0.25)]), body.darkened(0.15))
	_poly(PackedVector2Array([at + Vector2(-span * 0.5, -3), at + Vector2(-span * 0.42, -3), at + Vector2(-span * 0.5, -span * 0.16)]), body.darkened(0.2))
	for i in 4:
		draw_circle(at + Vector2(_rng.randf_range(-span * 0.4, span * 0.4), 6), 2.0, Color(0.4, 0.35, 0.3))


func _vents(w: float, bed: float) -> void:
	var count := 3 + _rng.randi() % 3
	for i in count:
		var x := w * (0.15 + 0.7 * i / maxf(count - 1, 1)) + _rng.randf_range(-12, 12)
		var tall := 30.0 + _rng.randf() * 50.0
		var white := _rng.randf() < 0.3
		_poly(PackedVector2Array([Vector2(x - 9, bed + 2), Vector2(x + 9, bed + 2), Vector2(x + 4, bed - tall), Vector2(x - 4, bed - tall)]), Color(0.85, 0.85, 0.8) if white else Color(0.2, 0.17, 0.15))
		for k in 6:  # Its plume.
			draw_circle(Vector2(x + sin(k * 1.4) * 4.0 + k * 3.0, bed - tall - 6.0 - k * 9.0), 5.0 + k * 1.6, Color(0.9, 0.9, 0.9, 0.2) if white else Color(0.05, 0.05, 0.05, 0.4 - k * 0.05))
		for k in 5:  # Tube worms round its foot.
			var foot := Vector2(x - 16 + k * 8.0, bed + 1)
			draw_line(foot, foot + Vector2(0, -10 - _rng.randf() * 8.0), Color(0.95, 0.92, 0.88), 2.0)
			draw_circle(foot + Vector2(0, -12 - _rng.randf() * 6.0), 2.2, Color(0.9, 0.15, 0.2))


func _reef(w: float, bed: float, cold: bool) -> void:
	var colors := [Color(0.98, 0.5, 0.6), Color(1.0, 0.75, 0.3), Color(0.6, 0.45, 0.9), Color(0.4, 0.85, 0.7)] if not cold else [Color(0.95, 0.95, 0.9), Color(0.95, 0.75, 0.6)]
	for i in 16:
		var x := _rng.randf() * w
		var c: Color = colors[_rng.randi() % colors.size()]
		match _rng.randi() % 3:
			0:  # Branching coral.
				var foot := Vector2(x, bed + 2)
				for k in 4:
					draw_line(foot, foot + Vector2(-12 + k * 8.0, -16 - _rng.randf() * 14.0), c, 2.5)
			1:  # Brain coral.
				draw_circle(Vector2(x, bed - 4), 7.0 + _rng.randf() * 6.0, c.darkened(0.1))
			2:  # Kelp or a sea fan.
				var stem := PackedVector2Array()
				for k in 8:
					stem.append(Vector2(x + sin(k * 0.9) * 4.0, bed - k * 9.0))
				draw_polyline(stem, Color(0.4, 0.55, 0.2) if not cold else c, 2.0)


func _ruins(w: float, bed: float) -> void:
	var stone := Color(0.78, 0.74, 0.62)
	draw_rect(Rect2(w * 0.2, bed - 10.0, w * 0.55, 10.0), stone.darkened(0.1))
	draw_rect(Rect2(w * 0.24, bed - 16.0, w * 0.47, 6.0), stone.darkened(0.05))
	var standing := 3 + _rng.randi() % 3
	for k in standing:
		var x := w * 0.27 + k * (w * 0.4 / maxf(standing - 1, 1))
		var tall := 30.0 + _rng.randf() * 40.0 if _rng.randf() < 0.75 else 12.0
		draw_rect(Rect2(x - 5.0, bed - 16.0 - tall, 10.0, tall), stone)
		draw_rect(Rect2(x - 8.0, bed - 20.0 - tall, 16.0, 4.0), stone.lightened(0.1))
	_poly(PackedVector2Array([Vector2(w * 0.78, bed), Vector2(w * 0.88, bed - 5), Vector2(w * 0.95, bed + 1)]), stone.darkened(0.2))  # A toppled drum.
	var amphora := Vector2(w * 0.12, bed - 6.0)
	draw_circle(amphora, 5.0, Color(0.7, 0.4, 0.25))
	draw_line(amphora + Vector2(0, -4), amphora + Vector2(0, -10), Color(0.7, 0.4, 0.25), 2.5)


func _wildlife(w: float, h: float, site: Dictionary) -> void:
	var name := str(site.get("name", "")).to_lower()
	if name.contains("squid"):
		var at := Vector2(w * 0.45, h * 0.45)
		_poly(PackedVector2Array([at + Vector2(-40, 0), at + Vector2(0, -12), at + Vector2(30, 0), at + Vector2(0, 12)]), Color(0.75, 0.3, 0.25))
		for k in 8:
			var arm := PackedVector2Array()
			for s in 8:
				arm.append(at + Vector2(30 + s * 9.0, (k - 3.5) * 2.0 + sin(s * 0.8 + k) * 6.0))
			draw_polyline(arm, Color(0.75, 0.3, 0.25), 2.0)
		return
	if name.contains("bloop") or name.contains("upsweep") or name.contains("anomaly") or name.contains("triangle") or name.contains("garbage") or name.contains("craters") or name.contains("formations") or name.contains("milky") or name.contains("brine"):
		var trace := PackedVector2Array()
		for i in 60:  # A hydrophone's trace of the sound (or the sonar's return).
			var x := w * 0.08 + w * 0.8 * i / 59.0
			trace.append(Vector2(x, h * 0.45 + sin(i * 0.6) * (6.0 + 22.0 * sin(PI * i / 59.0)) * (0.6 + _rng.randf() * 0.4)))
		draw_polyline(trace, Color(0.6, 1.0, 0.8, 0.85), 2.0, true)
		return
	if name.contains("shark") or name.contains("manta") or name.contains("coelacanth") or name.contains("sardine"):
		_fish(w, h, 12, Color(0.85, 0.9, 0.95, 0.85))
		return
	# A whale.
	var at := Vector2(w * 0.45, h * 0.4)
	var body := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		body.append(at + Vector2(cos(a) * 70.0, sin(a) * 16.0))
	_poly(body, Color(0.32, 0.4, 0.5))
	_poly(PackedVector2Array([at + Vector2(-66, 0), at + Vector2(-96, -14), at + Vector2(-90, 0), at + Vector2(-96, 14)]), Color(0.32, 0.4, 0.5))
	draw_circle(at + Vector2(48, 2), 2.0, Color(0.05, 0.05, 0.1))


func _fish(w: float, h: float, count: int, color: Color) -> void:
	var middle := Vector2(w * (0.3 + _rng.randf() * 0.4), h * (0.3 + _rng.randf() * 0.25))
	for i in count:
		var at := middle + Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-22, 22))
		var s := 3.0 + _rng.randf() * 2.0
		_poly(PackedVector2Array([at + Vector2(-s * 1.6, 0), at + Vector2(0, -s * 0.6), at + Vector2(s * 1.2, 0), at + Vector2(0, s * 0.6)]), color)
		_poly(PackedVector2Array([at + Vector2(-s * 1.4, 0), at + Vector2(-s * 2.3, -s * 0.6), at + Vector2(-s * 2.3, s * 0.6)]), color)


## A filled polygon, skipped if it can't be filled (a shape folded on itself by its seeded details).
func _poly(points: PackedVector2Array, color: Color) -> void:
	if points.size() >= 3 and not Geometry2D.triangulate_polygon(points).is_empty():
		draw_colored_polygon(points, color)
